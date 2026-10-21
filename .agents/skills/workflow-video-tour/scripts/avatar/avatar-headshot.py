#!/usr/bin/env python3
"""avatar-headshot.py — derive an avatar appearance JSON from a real headshot.

  avatar-headshot.py --image headshot.jpg --out appearance.json [--print]

It finds the face (Haar cascade), samples anatomical anchors (forehead, both
cheeks, hairline, hair sides, jaw, chest, backdrop) and writes the palette the
renderer consumes, plus a `guesses` block for the three things a colour sampler
cannot know: glasses, beard, hair length. ALWAYS sanity-check those three against
the photo — they are heuristics, and the renderer will happily dress the avatar
in a beard the person does not have.

If `cv2` is missing:
  uv run --with opencv-python-headless python avatar-headshot.py --image … --out …
"""
import argparse
import json
import os
import sys

try:
    import cv2
    import numpy as np
except ImportError:  # pragma: no cover
    print("FATAL: needs cv2 — run: uv run --with opencv-python-headless python "
          "avatar-headshot.py --image … --out …", file=sys.stderr)
    raise SystemExit(3)

from PIL import Image

SCALE_W = 1400


def hexc(rgb):
    return "#{:02X}{:02X}{:02X}".format(*(int(x) for x in rgb[:3]))


def cascade_path():
    candidates = []
    try:
        candidates.append(os.path.join(cv2.data.haarcascades, "haarcascade_frontalface_default.xml"))
    except AttributeError:
        pass
    candidates += [
        "/usr/share/opencv4/haarcascades/haarcascade_frontalface_default.xml",
        "/usr/local/share/opencv4/haarcascades/haarcascade_frontalface_default.xml",
    ]
    for c in candidates:
        if os.path.exists(c):
            return c
    raise SystemExit("FATAL: no haarcascade_frontalface_default.xml found")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--image", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--print", dest="show", action="store_true")
    ap.add_argument("--hair-length", choices=["short", "long"], help="override the guess")
    ap.add_argument("--glasses", choices=["yes", "no"], help="override the guess")
    ap.add_argument("--beard", choices=["yes", "no"], help="override the guess")
    args = ap.parse_args()

    img = cv2.imread(args.image)
    if img is None:
        raise SystemExit(f"FATAL: cannot read {args.image}")
    h0, w0 = img.shape[:2]
    img = cv2.resize(img, (SCALE_W, int(h0 * SCALE_W / w0)), interpolation=cv2.INTER_AREA)
    h, w = img.shape[:2]
    rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)

    def mean_rgb(box):
        x, y, bw, bh = (max(0, int(v)) for v in box)
        patch = rgb[y:y + bh, x:x + bw]
        return (0, 0, 0) if patch.size == 0 else tuple(int(v) for v in patch.reshape(-1, 3).mean(axis=0))

    faces = cv2.CascadeClassifier(cascade_path())
    det = faces.detectMultiScale(gray, scaleFactor=1.08, minNeighbors=6, minSize=(120, 120))
    if len(det) == 0:
        det = faces.detectMultiScale(gray, scaleFactor=1.05, minNeighbors=3, minSize=(80, 80))
    if len(det):
        fx, fy, fw, fh = max(det, key=lambda r: r[2] * r[3])
        source = "haar"
    else:  # portrait assumption: face in the upper third, centred
        fx, fy, fw, fh = int(w * 0.32), int(h * 0.18), int(w * 0.36), int(h * 0.42)
        source = "fallback (no face detected)"

    skin_forehead = mean_rgb((fx + fw * 0.35, fy + fh * 0.12, fw * 0.30, fh * 0.12))
    skin_l = mean_rgb((fx + fw * 0.12, fy + fh * 0.55, fw * 0.16, fh * 0.15))
    skin_r = mean_rgb((fx + fw * 0.72, fy + fh * 0.55, fw * 0.16, fh * 0.15))
    skin = tuple(int(np.mean([skin_forehead[i], skin_l[i], skin_r[i]])) for i in range(3))
    hair_top = mean_rgb((fx + fw * 0.2, max(0, fy - fh * 0.42), fw * 0.6, max(6, fh * 0.3)))
    jaw = mean_rgb((fx + fw * 0.78, fy + fh * 0.72, fw * 0.16, fh * 0.16))
    chin = mean_rgb((fx + fw * 0.34, fy + fh * 0.82, fw * 0.32, fh * 0.14))
    shirt = mean_rgb((w * 0.30, h * 0.88, w * 0.40, h * 0.10))
    bg = tuple(int(np.mean([mean_rgb((0, 0, w * 0.06, h * 0.06))[i],
                            mean_rgb((w - w * 0.06, 0, w * 0.06, h * 0.06))[i]])) for i in range(3))

    lum = lambda c: float(np.mean(cv2.cvtColor(np.uint8([[list(c)]]), cv2.COLOR_RGB2GRAY)))
    cheek_lum, jaw_lum = lum(skin_l), lum(jaw)
    eye_band = gray[fy + int(fh * 0.28):fy + int(fh * 0.46), fx:fx + fw]
    dark_cols = float((eye_band.min(axis=0).astype(float) < 70).mean()) if eye_band.size else 0.0
    side = mean_rgb((max(0, fx - fw * 0.22), fy + fh * 0.85, fw * 0.18, fh * 0.30))

    hair_dark = tuple(max(0, min(255, int(hair_top[i] * 0.9 + 18))) for i in range(3))
    warm = chin if sum(chin) > sum(hair_top) else (143, 78, 34)
    guesses = {
        "glasses": dark_cols > 0.62,
        "beard": jaw_lum / max(1.0, cheek_lum) < 0.90,
        "hair_length": "long" if lum(side) < 90 < cheek_lum else "short",
        "glasses_score": round(dark_cols, 3),
        "jaw_vs_cheek_lum": round(jaw_lum / max(1.0, cheek_lum), 3),
    }
    if args.glasses:
        guesses["glasses"] = args.glasses == "yes"
    if args.beard:
        guesses["beard"] = args.beard == "yes"
    if args.hair_length:
        guesses["hair_length"] = args.hair_length

    appearance = {
        "skin": hexc(skin), "skin_shadow": hexc(tuple(int(c * 0.87) for c in skin)),
        "hair": hexc(hair_top), "hair_length": guesses["hair_length"],
        "beard": guesses["beard"], "beard_dark": hexc(hair_dark),
        "beard_warm": hexc(warm),
        "glasses": guesses["glasses"],
        "shirt_style": "plain", "shirt": "#F7F5F2", "collar": "#FCFBF9",
        "card": hexc(tuple(int(c * 0.6) for c in bg)), "card_alpha": 168,
        "accent": "#CBB9C2", "ring_width": 2.2, "ring_alpha": 130, "shadow_alpha": 90,
        "lips": hexc(tuple(int(c * 0.82) for c in skin)),
        "_source": {"image": args.image, "face_box": [int(fx), int(fy), int(fw), int(fh)],
                    "detector": source, "sampled": {
                        "skin": hexc(skin), "shirt_sampled": hexc(shirt), "backdrop": hexc(bg)},
                    "guesses": guesses,
                    "warning": "glasses/beard/hair_length are heuristics — confirm against the photo"},
    }
    with open(args.out, "w") as out_file:
        json.dump(appearance, out_file, indent=2)
    print(f"  · face {fw}x{fh} at {fx},{fy} (detector: {source})")
    print(f"  · skin {appearance['skin']}  hair {appearance['hair']}  "
          f"beard {appearance['beard_dark']}→{appearance['beard_warm']}  backdrop {hexc(bg)}")
    print(f"  · guesses: glasses={guesses['glasses']} (score {guesses['glasses_score']}), "
          f"beard={guesses['beard']} (jaw/cheek {guesses['jaw_vs_cheek_lum']}), "
          f"hair={guesses['hair_length']}  ← CONFIRM THESE")
    print(f"  ✓ {args.out}")
    if args.show:
        print(json.dumps(appearance, indent=2))


if __name__ == "__main__":
    main()
