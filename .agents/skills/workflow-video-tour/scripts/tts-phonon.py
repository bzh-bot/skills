#!/usr/bin/env python3
"""tts-phonon.py — narrate a timeline with Phonon (Gradium TTS, Apache-2.0) over Ollama.

Replaces tts-qwen3.py. Phonon is the speech model shipped by Ollama >= 0.40.9: 43M
parameters, speech streamed from /v1/audio/speech, WAV 24 kHz mono out.

Why it replaced Qwen3-TTS: Qwen needed a 4.3 GB checkpoint, a torch venv and a GPU
(or slow CPU), and it sampled a fresh take per beat that had to be pinned with
--stable + a per-beat `instruct` clause to keep one speaker. Phonon is 112 MB, runs
on CPU through a plain HTTP call (no venv, no torch), and the `voice` parameter is
the speaker identity — the same value always returns the same person, so the
voice-identity machinery is no longer load-bearing.

What is NOT supported, and the reason steps/3-narration.md was rewritten:
  * speed  — only 1 is accepted ("only speed 1 is supported")
  * per-beat delivery / `instruct` — no style text input at all; a beat carrying
    `instruct` still narrates, the clause is ignored (warned once)
  * mp3    — response_format is wav or pcm only
  * seed   — accepted but ignored: two identical requests differ in bytes. Duration
    is stable to the frame, so timing checks stay meaningful.

Usage:
  tts-phonon.py --timeline timeline.json --out tts-phonon [--voice Alfie]
  tts-phonon.py --text "one line" --out-file /tmp/line.wav
  tts-phonon.py --check           # verify the runtime + model, generate one line

Timeline: JSON list of beats; `id` and `narration` are used. Writes <out>/<id>.wav.
Exit code is non-zero if any beat failed or produced a silent/oversized take.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
import wave

DEFAULT_VOICE = "Alfie"
DEFAULT_MODEL = "phonon"
# Words per second Phonon actually produces, measured on the tour beat sets.
# Used only to flag a runaway take, never to size the video (V4 fits video to voice).
WORDS_PER_SEC = 2.6
DURATION_SLACK = 2.5


def resolve_host(explicit: str | None) -> str:
    host = (explicit or os.environ.get("PHONON_HOST") or os.environ.get("OLLAMA_HOST")
            or "http://127.0.0.1:11434")
    host = host.strip().rstrip("/")
    if "://" not in host:
        host = "http://" + host
    return host


def post_json(url: str, payload: dict, timeout: int = 300) -> tuple[int, bytes, str]:
    data = json.dumps(payload).encode()
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, r.read(), r.headers.get("Content-Type", "")
    except urllib.error.HTTPError as e:
        return e.code, e.read(), e.headers.get("Content-Type", "") if e.headers else ""


def get_json(url: str, timeout: int = 30):
    with urllib.request.urlopen(url, timeout=timeout) as r:
        return json.load(r)


def normalize_wav(path: str) -> dict:
    """Rewrite a streamed wav with a truthful header, then measure it.

    Ollama streams the audio, so the data chunk length is 0xFFFFFFFF until the end:
    the file plays fine but wave/ffprobe report a bogus duration (measured: 89478 s
    for a 5 s take). Rewrite the canonical 44-byte header from the real payload
    length, otherwise every downstream timing check is wrong.
    """
    with open(path, "rb") as f:
        blob = f.read()
    if blob[:4] != b"RIFF" or blob[8:12] != b"WAVE":
        raise ValueError(f"{path}: not a RIFF/WAVE file")
    pos, fmt, data = 12, None, None
    while pos + 8 <= len(blob):
        cid, size = blob[pos:pos + 4], int.from_bytes(blob[pos + 4:pos + 8], "little")
        body = blob[pos + 8:pos + 8 + size]
        if cid == b"fmt ":
            fmt = body
        elif cid == b"data":
            # A streamed chunk claims 0xFFFFFFFF; the true length is what is there.
            data = body if size != 0xFFFFFFFF else blob[pos + 8:]
            break
        pos += 8 + size + (size & 1)
    if fmt is None or data is None:
        raise ValueError(f"{path}: missing fmt/data chunk")
    channels = int.from_bytes(fmt[2:4], "little")
    rate = int.from_bytes(fmt[4:8], "little")
    bits = int.from_bytes(fmt[14:16], "little")
    header = (b"RIFF" + (36 + len(data)).to_bytes(4, "little") + b"WAVEfmt "
              + (16).to_bytes(4, "little") + fmt[:16] + b"data"
              + len(data).to_bytes(4, "little"))
    with open(path, "wb") as f:
        f.write(header + data)
    return {"channels": channels, "rate": rate, "bits": bits}


def wav_stats(path: str) -> dict:
    """Header, duration and RMS of a wav — the checks that catch a broken take."""
    normalize_wav(path)
    with wave.open(path, "rb") as w:
        frames, rate, width = w.getnframes(), w.getframerate(), w.getsampwidth()
        raw = w.readframes(frames)
    if width != 2:
        raise ValueError(f"{path}: expected 16-bit PCM, got {width * 8}-bit")
    samples = memoryview(raw).cast("h")
    peak = max((abs(s) for s in samples), default=0)
    if samples:
        rms = (sum(s * s for s in samples) / len(samples)) ** 0.5
    else:
        rms = 0.0
    return {"duration": frames / rate, "rate": rate, "rms": round(rms, 1), "peak": peak}


def check_runtime(host: str, model: str, voice: str) -> int:
    """Verify the server is a new-enough Ollama that actually serves speech."""
    print(f"host: {host}")
    try:
        ver = get_json(f"{host}/api/version").get("version", "?")
    except Exception as e:  # noqa: BLE001 - any failure here is the answer
        print(f"FAIL cannot reach {host}: {e}")
        print("  fix: scripts/install-phonon.sh   (needs Ollama >= 0.40.9)")
        return 1
    print(f"ollama: {ver}")
    try:
        tags = get_json(f"{host}/api/tags")
        names = {m.get("name", "").split(":")[0] for m in tags.get("models", [])}
    except Exception as e:  # noqa: BLE001
        print(f"FAIL cannot list models: {e}")
        return 1
    if model not in names:
        print(f"FAIL model {model!r} is not pulled — run: ollama pull {model}")
        return 1
    print(f"model: {model} present")
    status, body, ctype = post_json(f"{host}/v1/audio/speech",
                                    {"model": model, "input": "Narration check.",
                                     "voice": voice, "response_format": "wav"})
    if status != 200 or "json" in ctype:
        print(f"FAIL /v1/audio/speech -> {status}: {body[:200].decode(errors='replace')}")
        print("  a 404 'path not found' means this Ollama build has no speech support,"
              " or (on Linux) the MLX runtime is missing — install-phonon.sh adds it")
        return 1
    out = "/tmp/phonon-check.wav"
    with open(out, "wb") as f:
        f.write(body)
    st = wav_stats(out)
    print(f"speech: ok — {st['duration']:.2f}s {st['rate']} Hz rms={st['rms']} ({out})")
    return 0


def synth(host: str, model: str, voice: str, text: str, out: str, attempts: int = 3) -> dict:
    payload = {"model": model, "input": text, "voice": voice, "response_format": "wav"}
    last = ""
    for n in range(attempts):
        status, body, ctype = post_json(f"{host}/v1/audio/speech", payload)
        if status == 200 and "json" not in ctype:
            with open(out, "wb") as f:
                f.write(body)
            st = wav_stats(out)
            # Guard rails, not tuning knobs: a silent file or a take far longer than
            # the text can justify means the request was mangled, not that the voice
            # is slow. Duration is stable to the frame for a given line.
            words = len(re.findall(r"[\w']+", text))
            budget = max(8.0, words / WORDS_PER_SEC) * DURATION_SLACK
            if st["rms"] < 30:
                last = f"silent take (rms {st['rms']})"
            elif st["duration"] > budget:
                last = f"runaway take {st['duration']:.1f}s > {budget:.1f}s budget"
            else:
                return st
        else:
            last = f"http {status}: {body[:160].decode(errors='replace')}"
        time.sleep(1 + n)
    raise RuntimeError(last)


def main() -> int:
    ap = argparse.ArgumentParser(description="Narrate with Phonon over Ollama.")
    ap.add_argument("--timeline", help="timeline.json (list of beats with id + narration)")
    ap.add_argument("--out", help="output directory for <beat id>.wav")
    ap.add_argument("--text", help="one-off line instead of a timeline")
    ap.add_argument("--out-file", help="destination for --text (default /tmp/phonon-line.wav)")
    ap.add_argument("--voice", default=os.environ.get("PHONON_VOICE", DEFAULT_VOICE),
                    help=f"Phonon voice (default {DEFAULT_VOICE}; `ollama show phonon` lists all)")
    ap.add_argument("--model", default=os.environ.get("PHONON_MODEL", DEFAULT_MODEL))
    ap.add_argument("--host", default=None, help="Ollama base URL (default $PHONON_HOST / $OLLAMA_HOST)")
    ap.add_argument("--check", action="store_true", help="verify runtime + model, exit")
    a = ap.parse_args()

    host = resolve_host(a.host)
    if a.check:
        return check_runtime(host, a.model, a.voice)

    if a.text:
        out = a.out_file or "/tmp/phonon-line.wav"
        st = synth(host, a.model, a.voice, a.text, out)
        print(f"phonon {os.path.basename(out)} {st['duration']:.1f}s rms={st['rms']}")
        return 0

    if not a.timeline or not a.out:
        ap.error("need --timeline and --out (or --text)")
    beats = json.load(open(a.timeline, encoding="utf-8"))
    os.makedirs(a.out, exist_ok=True)

    told_about_instruct = False
    failures, made = [], 0
    for beat in beats:
        text = (beat.get("narration") or "").strip()
        if not text:
            continue
        if beat.get("instruct") and not told_about_instruct:
            # Keep old timelines runnable rather than failing them: Phonon takes no
            # style text, so the clause is dropped, not mis-delivered.
            print("  note: timeline carries `instruct` clauses — Phonon ignores them "
                  "(no style input). Delivery is the voice's own.", flush=True)
            told_about_instruct = True
        out = os.path.join(a.out, f"{beat['id']}.wav")
        try:
            st = synth(host, a.model, a.voice, text, out)
            made += 1
            print(f"  phonon {beat['id']:<18} {st['duration']:5.1f}s rms={st['rms']}", flush=True)
        except Exception as e:  # noqa: BLE001 - report and continue, summary fails the run
            failures.append((beat["id"], str(e)))
            print(f"  FAILED {beat['id']:<18} {e}", flush=True)

    print(f"\n{a.voice} · {made} beat(s) → {a.out}")
    if failures:
        for beat_id, err in failures:
            print(f"  ! {beat_id}: {err}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
