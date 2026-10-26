#!/usr/bin/env python3
"""voice-stats.py — per-beat pitch / voiced-ratio QA for a narration set.

A neural TTS with stochastic sampling drifts between independent calls. Median
F0 spread across beats is the number that correlates with "the voice keeps
changing": ~35 Hz between beats is audible, <20 Hz reads as one narrator.

Usage:  voice-stats.py <tts-dir> [--ext .wav]
Run with any venv that has librosa + soundfile (e.g. `uv run --with librosa --with soundfile`):
  uv run --with librosa --with soundfile python voice-stats.py out/tts
"""
import argparse
import glob
import os
import sys

import librosa
import numpy as np
import soundfile as sf


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("dir")
    ap.add_argument("--ext", default=".wav")
    a = ap.parse_args()

    rows = []
    for f in sorted(glob.glob(os.path.join(a.dir, f"*{a.ext}"))):
        if ".norm." in f:
            continue
        y, sr = sf.read(f)
        if y.ndim > 1:
            y = y.mean(1)
        f0 = librosa.yin(y.astype(np.float32), fmin=60, fmax=350, sr=sr)
        f0 = f0[np.isfinite(f0)]
        rms = librosa.feature.rms(y=y, frame_length=1024, hop_length=256)[0]
        dur = len(y) / sr
        voiced = (rms > rms.max() * 0.12).sum() * 256 / sr
        rows.append((os.path.basename(f)[:18], float(np.median(f0)),
                     float(np.percentile(f0, 10)), float(np.percentile(f0, 90)), dur, voiced / dur))

    if not rows:
        sys.exit(f"no {a.ext} files in {a.dir}")
    print(f"{'beat':18s} {'F0 med':>7s} {'F0 p10':>7s} {'F0 p90':>7s} {'dur':>6s} {'voiced%':>8s}")
    for r in rows:
        print(f"{r[0]:18s} {r[1]:7.1f} {r[2]:7.1f} {r[3]:7.1f} {r[4]:6.1f} {r[5]*100:7.0f}%")
    meds = np.array([r[1] for r in rows])
    spread = meds.max() - meds.min()
    verdict = "ok (single narrator)" if spread < 20 else ("audible drift" if spread < 35 else "STRONG drift — retune or use a different reference")
    print(f"\nmedian-F0 across beats: {meds.min():.0f}-{meds.max():.0f} Hz "
          f"(std {meds.std():.1f}, spread {spread:.0f} Hz) → {verdict}")


main()
