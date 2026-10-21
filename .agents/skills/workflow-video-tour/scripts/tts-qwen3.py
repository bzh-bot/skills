#!/usr/bin/env python3
"""tts-qwen3.py — narrate a timeline with Qwen3-TTS 1.7B (Apache-2.0).

Modes:
  design  describe the voice in words            (VoiceDesign, accepts --instruct)  ← default
  custom  one of 9 preset timbres                (CustomVoice,  --speaker/--instruct)
  clone   3-second reference audio               (Base,        --ref-audio/--ref-text)

A beat may carry its own `instruct`; it overrides the global `--instruct`, which is
what lets delivery vary beat to beat. The approved narrator is the `custom` preset
Aiden with such per-beat clauses — see assets/voice/aiden-narration.md. Only the
design and custom models accept style text at all: generate_voice_clone has no
instruct argument.

Run with the qwen venv (see steps/3-narration.md for the install):
  ~/.local/share/qwen3-tts/venv/bin/python tts-qwen3.py --mode design ...

--stable pins the sampling variance that otherwise makes the voice drift between
beats: the prompt is built once and reused, torch is reseeded per beat, and a
repeat-runaway (a low-temperature take once emitted 655 s for a 15 s line) is
rejected and retried with a new seed. The sampling values are the approved voice:
temp 0.9 / top-k 50 / top-p 0.95 / rep-penalty 1.0. Those were chosen by
measurement, not taste — at temp 0.7 the delivery flattens (pitch movement drops
from ~148 Hz to ~85 Hz), which is exactly what "sounds bored" means.
"""
import argparse
import json
import os
import random

import numpy as np
import soundfile as sf
import torch
from qwen_tts import Qwen3TTSModel

ROOT = os.environ.get("QWEN3_ROOT", os.path.expanduser("~/.local/share/qwen3-tts"))
MODELS = {
    "design": f"{ROOT}/Qwen3-TTS-12Hz-1.7B-VoiceDesign",
    "custom": f"{ROOT}/Qwen3-TTS-12Hz-1.7B-CustomVoice",
    "clone": f"{ROOT}/Qwen3-TTS-12Hz-1.7B-Base",
}
DEFAULT_INSTRUCT = (
    "An Australian male voice, low and deep but brimming with energy: fast, bright, "
    "punchy delivery that stays in the low register. Warm, engaged, a little wry. "
    "Like an engineer who is genuinely pleased with what he just shipped."
)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--timeline", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--mode", choices=sorted(MODELS), default="design")
    ap.add_argument("--instruct", default=DEFAULT_INSTRUCT)
    ap.add_argument("--speaker", default="Ryan")
    ap.add_argument("--ref-audio", default="")
    ap.add_argument("--ref-text", default="")
    ap.add_argument("--language", default="English")
    ap.add_argument("--attn", default="sdpa", help="sdpa avoids building flash-attn")
    ap.add_argument("--device", default="auto",
                    help="auto (cuda when present, else cpu) | cuda:0 | cpu — cages without a GPU "
                         "(e.g. linux/amd64 under macOS) must run on cpu")
    ap.add_argument("--stable", action="store_true")
    ap.add_argument("--temperature", type=float, default=0.9)   # 0.7 flattens delivery; 0.9 is the approved voice
    ap.add_argument("--top-k", type=int, default=50)
    ap.add_argument("--top-p", type=float, default=0.95)
    ap.add_argument("--rep-penalty", type=float, default=1.0)
    ap.add_argument("--seed", type=int, default=1234)
    ap.add_argument("--x-vector-only", action="store_true",
                    help="speaker embedding only (measured: no more stable — steps/3-narration.md)")
    a = ap.parse_args()

    if a.mode == "clone" and not a.ref_audio:
        raise SystemExit("--mode clone needs --ref-audio (and --ref-text unless --x-vector-only)")

    beats = json.load(open(a.timeline, encoding="utf-8"))
    os.makedirs(a.out, exist_ok=True)

    torch.manual_seed(a.seed); torch.cuda.manual_seed_all(a.seed)
    random.seed(a.seed); np.random.seed(a.seed)

    print(f"loading {MODELS[a.mode]} (attn={a.attn})", flush=True)
    # A cage has no GPU on macOS (the host is arm64 but the container is linux/amd64),
    # so default to cuda only when it is actually available. bf16 is a GPU dtype —
    # on CPU it is emulated and much slower, so use fp32 there.
    dev = a.device
    if dev == "auto":
        dev = "cuda:0" if torch.cuda.is_available() else "cpu"
    dtype = torch.bfloat16 if str(dev).startswith("cuda") else torch.float32
    print(f"device={dev} dtype={dtype}", flush=True)
    model = Qwen3TTSModel.from_pretrained(MODELS[a.mode], device_map=dev,
                                          dtype=dtype, attn_implementation=a.attn)

    prompt = None
    if a.mode == "clone":
        prompt = model.create_voice_clone_prompt(
            ref_audio=a.ref_audio, ref_text=a.ref_text, x_vector_only_mode=a.x_vector_only)[0]
        print(f"prompt built (x_vector_only={a.x_vector_only})", flush=True)
    if a.stable:
        print(f"stable sampling · temp={a.temperature} top_k={a.top_k} top_p={a.top_p} "
              f"rep_pen={a.rep_penalty} seed={a.seed}", flush=True)

    def synth(text: str, instruct: str):
        gen = {}
        if a.stable:
            gen = dict(do_sample=True, top_k=a.top_k, top_p=a.top_p, temperature=a.temperature,
                       repetition_penalty=a.rep_penalty,
                       subtalker_dosample=True, subtalker_top_k=a.top_k,
                       subtalker_top_p=a.top_p, subtalker_temperature=a.temperature)
        if a.mode == "design":
            return model.generate_voice_design(text=text, language=a.language,
                                               instruct=instruct, **gen)
        if a.mode == "custom":
            return model.generate_custom_voice(text=text, language=a.language,
                                               speaker=a.speaker, instruct=instruct or None, **gen)
        return model.generate_voice_clone(text=text, language=a.language,
                                          voice_clone_prompt=[prompt], **gen)

    for beat in beats:
        text = (beat.get("narration") or "").strip()
        if not text:
            continue
        # a beat may carry its own `instruct` so delivery can vary beat to beat
        # (the `Delivery:` clause); the global --instruct stays the fallback
        instruct = (beat.get("instruct") or "").strip() or a.instruct
        out = os.path.join(a.out, f"{beat['id']}.wav")
        # guard: cap the length and retry with a new seed if the decoder loops
        budget = max(8.0, len(text.split()) / 2.2) * 2.5
        for attempt in range(4):
            seed = a.seed + attempt * 7919
            torch.manual_seed(seed); torch.cuda.manual_seed_all(seed)
            wavs, sr = synth(text, instruct)
            secs = len(wavs[0]) / sr
            if secs <= budget:
                sf.write(out, wavs[0], sr)
                print(f"  qwen3 {beat['id']:<18} {secs:5.1f}s (seed {seed})", flush=True)
                break
            print(f"  reject {beat['id']:<18} {secs:5.1f}s > {budget:.1f}s budget (seed {seed})", flush=True)
        else:
            print(f"  FAILED {beat['id']}: no usable take in 4 attempts", flush=True)


main()
