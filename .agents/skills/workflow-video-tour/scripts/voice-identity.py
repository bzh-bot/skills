#!/usr/bin/env python3
"""voice-identity.py — does every beat sound like the SAME person?

Pitch alone cannot answer that. A design-mode TTS call samples a *new speaker* each
time, so six beats can differ in timbre (formants, spectral envelope) while their
median F0 looks fine — which is exactly the "each phrase is a different voice"
defect. This measures the features that actually carry speaker identity:

  F1 / F2   median formant frequencies over voiced frames (LPC), the classic
            speaker cue — vowels are text-dependent but the medians are not
  LTAS      long-term average spectrum; the cosine similarity between two takes'
            LTAS is a cheap, text-robust identity proxy (1.00 = identical envelope)
  F0        median pitch — reported for completeness, NOT as an identity test

A set is consistent when the per-beat F1/F2 sit in a tight cluster and the mean
LTAS cosine similarity is high (>= 0.99 is the same speaker; <= 0.97 is audibly a
different person).

Usage:
  voice-identity.py <tts-dir> [--ext .wav] [--json out.json]
Needs librosa + soundfile (the qwen venv has them):
  ~/.local/share/qwen3-tts/venv/bin/python voice-identity.py "$VIDEO_DIR/tts"
"""
import argparse
import glob
import json
import os
import sys

import librosa
import numpy as np
import soundfile as sf

SR = 16000
N_FFT = 1024
HOP = 256


def feats(path):
    y, sr = sf.read(path)
    if y.ndim > 1:
        y = y.mean(1)
    y = y.astype(np.float32)
    if sr != SR:
        y = librosa.resample(y, orig_sr=sr, target_sr=SR)
    rms = librosa.feature.rms(y=y, frame_length=N_FFT, hop_length=HOP)[0]
    voiced = rms > rms.max() * 0.25
    f0 = librosa.yin(y, fmin=50, fmax=350, sr=SR)
    n = min(len(f0), len(voiced))
    f0v = f0[:n][voiced[:n]]
    f0v = f0v[np.isfinite(f0v)]

    # frames for LPC / LTAS
    frames = librosa.util.frame(y, frame_length=N_FFT, hop_length=HOP).T
    vmask = voiced[: len(frames)]
    frames = frames[vmask]
    pre = np.append(frames[:, 0:1], frames[:, 1:] - 0.97 * frames[:, :-1], axis=1)
    win = np.hanning(N_FFT)
    f1s, f2s = [], []
    for fr in pre[::2]:
        try:
            a = librosa.lpc(fr * win, order=12)
        except Exception:
            continue
        roots = [r for r in np.roots(a) if np.imag(r) > 0]
        fs = sorted(np.arctan2(np.imag(r), np.real(r)) * SR / (2 * np.pi) for r in roots)
        fs = [f for f in fs if 90 < f < SR / 2 - 200]
        f1 = next((f for f in fs if 200 < f < 1100), None)
        f2 = next((f for f in fs if f1 and 1100 < f < 3000), None)
        if f1 and f2:
            f1s.append(f1)
            f2s.append(f2)

    spec = np.abs(np.fft.rfft(frames * win, axis=1))
    ltas = np.log10(spec + 1e-9).mean(axis=0)
    ltas = ltas / np.linalg.norm(ltas)
    return {
        "file": os.path.basename(path),
        "f0": float(np.median(f0v)) if len(f0v) else float("nan"),
        "f1": float(np.median(f1s)) if f1s else float("nan"),
        "f2": float(np.median(f2s)) if f2s else float("nan"),
        "voiced_s": float(voiced.sum() * HOP / SR),
        "ltas": ltas,
    }


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("dir")
    ap.add_argument("--ext", default=".wav")
    ap.add_argument("--json", default="")
    a = ap.parse_args()

    files = [f for f in sorted(glob.glob(os.path.join(a.dir, f"*{a.ext}")))
             if ".norm." not in f and not os.path.basename(f).startswith(".")]
    if len(files) < 2:
        sys.exit(f"need at least 2 takes in {a.dir} (found {len(files)})")
    rows = [feats(f) for f in files]

    print(f"{'beat':20s} {'F0':>6s} {'F1':>6s} {'F2':>6s} {'voiced':>7s}")
    for r in rows:
        print(f"{r['file'][:19]:20s} {r['f0']:6.0f} {r['f1']:6.0f} {r['f2']:6.0f} {r['voiced_s']:6.1f}s")

    def spread(key):
        v = np.array([r[key] for r in rows])
        v = v[np.isfinite(v)]
        return (v.max() - v.min(), v.std()) if len(v) else (float("nan"),) * 2

    f1r, f1s = spread("f1")
    f2r, f2s = spread("f2")
    f0r, f0s = spread("f0")
    sims = []
    L = np.array([r["ltas"] for r in rows])
    for i in range(len(L)):
        for j in range(i + 1, len(L)):
            sims.append(float(np.dot(L[i], L[j])))
    sim = float(np.mean(sims))
    worst = float(np.min(sims))

    print(f"\nF0  {f0r:.0f} Hz spread (sd {f0s:.1f})   ← prosody, not identity")
    print(f"F1  {f1r:.0f} Hz spread (sd {f1s:.1f})")
    print(f"F2  {f2r:.0f} Hz spread (sd {f2s:.1f})")
    print(f"LTAS cosine  mean {sim:.4f}  worst pair {worst:.4f}")
    if sim >= 0.99:
        verdict = "ok — one speaker"
    elif sim >= 0.975:
        verdict = "borderline — a listener may notice the voice changing"
    else:
        verdict = "DIFFERENT SPEAKERS — design mode drew a new voice per call; switch to clone mode from one reference"
    print(f"→ {verdict}")

    if a.json:
        json.dump([{k: v for k, v in r.items() if k != "ltas"} for r in rows]
                  + [{"ltas_cosine_mean": sim, "ltas_cosine_worst": worst, "verdict": verdict}],
                  open(a.json, "w"), indent=2)
        print(f"   wrote {a.json}")


if __name__ == "__main__":
    main()
