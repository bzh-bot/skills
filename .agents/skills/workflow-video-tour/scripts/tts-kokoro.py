#!/usr/bin/env python3
"""tts-kokoro.py — narrate a timeline with Kokoro-82M (Apache-2.0, CPU-fast).

Usage:
  tts-kokoro.py --timeline out/timeline.json --out out/tts \
    [--voice bm_george] [--speed 0.95] [--model PATH] [--voices PATH]

Install/run without polluting the environment:
  uv run --with kokoro-onnx --with soundfile python tts-kokoro.py ...

Voices starting with 'b' are treated as British English. Model files:
  https://github.com/thewh1teagle/kokoro-onnx/releases/tag/model-files-v1.0
  (~/.local/share/kokoro/{kokoro-v1.0.onnx,voices-v1.0.bin})
"""
import argparse
import json
import os

import numpy as np
import soundfile as sf
from kokoro_onnx import Kokoro

HOME = os.path.expanduser("~")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--timeline", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--voice", default="bm_george")
    ap.add_argument("--speed", type=float, default=0.95)
    ap.add_argument("--model", default=os.environ.get("KOKORO_MODEL", f"{HOME}/.local/share/kokoro/kokoro-v1.0.onnx"))
    ap.add_argument("--voices", default=os.environ.get("KOKORO_VOICES", f"{HOME}/.local/share/kokoro/voices-v1.0.bin"))
    a = ap.parse_args()

    beats = json.load(open(a.timeline, encoding="utf-8"))
    os.makedirs(a.out, exist_ok=True)
    lang = "en-gb" if a.voice.startswith("b") else "en-us"
    kokoro = Kokoro(a.model, a.voices)
    for beat in beats:
        text = (beat.get("narration") or "").strip()
        if not text:
            continue
        samples, sr = kokoro.create(text, voice=a.voice, speed=a.speed, lang=lang)
        out = os.path.join(a.out, f"{beat['id']}.wav")
        sf.write(out, samples, sr)
        print(f"  kokoro {beat['id']:<18} {len(samples) / sr:5.1f}s  {sr}Hz → {out}")


main()
