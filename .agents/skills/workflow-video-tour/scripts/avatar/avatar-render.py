#!/usr/bin/env python3
"""avatar-render.py — render a stylized speaking-avatar PNG sequence (and optionally
a preview clip) whose mouth follows a Rhubarb Lip Sync viseme track.

  avatar-render.py --appearance appearance.json --cues cues.json --audio voice.wav \
      --out frames/ [--fps 30] [--start 0] [--count N] [--size 240] \
      [--preview preview.mp4 --preview-bg 0xF6F4F5]

The frames are 8-bit RGBA PNGs at --size square (default 240x240), transparent
outside the rounded card, so ffmpeg can overlay them straight onto the video:

  ffmpeg -i video.mp4 -framerate 30 -i frames/f%05d.png \\
    -filter_complex "[1:v]format=rgba[av];[0:v][av]overlay=X:Y:format=auto[v]" \\
    -map "[v]" -map 0:a -c:v libx264 -pix_fmt yuv420p -c:a copy out.mp4

Design notes (see steps/5-avatar.md):
  • one frame per 1/fps, drawn at 4x and downscaled with LANCZOS for clean edges
  • mouth  = Rhubarb cues (A..H, X) mapped to nine fixed-baseline shapes
  • bob    = audio RMS + a slow sine; brows lift with amplitude
  • blink  = one every 3.6 s
  • the card is static (no pulsing) and semi-transparent; only the figure moves
"""
import argparse
import array
import json
import math
import os
import sys
import wave

from PIL import Image, ImageDraw, ImageFilter

DEFAULTS = {
    # palette
    "skin": "#CDA9A2", "skin_shadow": "#A78780", "lips": "#A5645C",
    "hair": "#1E1514",
    "beard": True, "beard_dark": "#2E2018", "beard_warm": "#8F4E22",
    "glasses": False, "frame_colour": "#8A8A93", "frame_width": 1.1,
    "lens_colour": "#DCE6EF", "lens_alpha": 12,
    "hair_length": "short",          # short | long
    # shirt
    "shirt_style": "plain",          # plain | trim | gingham
    "shirt": "#F7F5F2", "shirt_check": "#7B2233", "check_cell": 11,
    "collar": "#FCFBF9",
    # card
    "card": "#0C0C10", "card_alpha": 168, "accent": "#CBB9C2",
    "ring_width": 2.2, "ring_alpha": 130, "shadow_alpha": 90,
}

MOUTHS = {  # viseme -> (width, height, teeth)  — all on the same baseline box
    "X": (0.60, 0.035, False), "A": (0.50, 0.05, False), "B": (0.46, 0.19, False),
    "C": (0.52, 0.33, False), "D": (0.56, 0.48, True), "E": (0.40, 0.38, False),
    "F": (0.44, 0.17, True), "G": (0.34, 0.23, True), "H": (0.48, 0.13, True),
}


def rgba(hexc, a=255):
    hexc = hexc.lstrip("#")
    return tuple(int(hexc[i:i + 2], 16) for i in (0, 2, 4)) + (a,)


def shade(c, d):
    return tuple(max(0, min(255, c[i] - d)) for i in range(3)) + (255,)


def light(c, d):
    return tuple(max(0, min(255, c[i] + d)) for i in range(3)) + (255,)


def load_cues(path):
    cues = json.load(open(path))["mouthCues"]
    return cues


def shape_at(cues, t):
    v = "X"
    for c in cues:
        if c["start"] <= t:
            v = c["value"]
        else:
            break
    return v


def load_envelope(path, fps):
    wf = wave.open(path, "rb")
    samples = array.array("h", wf.readframes(wf.getnframes()))
    sr = wf.getframerate()
    n = max(1, sr // fps)

    def rms(i):
        seg = samples[i * n:(i + 1) * n]
        if not seg:
            return 0.0
        return math.sqrt(sum(float(x) * x for x in seg) / len(seg)) / 32768.0

    return rms


def blink_factor(i, fps):
    phase = (i / fps) % 3.6
    return abs(math.cos(math.pi * phase / 0.14)) if phase < 0.14 else 1.0


class Avatar:
    def __init__(self, ap, size=240, supersample=4):
        self.ap = ap
        self.size = size
        self.S = supersample

    def render(self, t, i, viseme, amp, blink):
        ap, S, size = self.ap, self.S, self.size
        SKIN, SKIN_SH = rgba(ap["skin"]), rgba(ap["skin_shadow"])
        HAIR = rgba(ap["hair"])
        BEARD_DARK, BEARD_WARM = rgba(ap["beard_dark"]), rgba(ap["beard_warm"])
        SHIRT, SHIRT2 = rgba(ap["shirt"]), rgba(ap["shirt_check"])
        CARD = rgba(ap["card"], int(ap["card_alpha"]))
        ACCENT, WHITE = rgba(ap["accent"]), rgba(ap["collar"])
        LIPS, FRAME = rgba(ap["lips"]), rgba(ap["frame_colour"])
        LENS = rgba(ap["lens_colour"], int(ap["lens_alpha"]))
        TEETH = (250, 250, 248, 255)

        img = Image.new("RGBA", (size * S, size * S), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)

        shadow = Image.new("RGBA", img.size, (0, 0, 0, 0))
        ImageDraw.Draw(shadow).rounded_rectangle(
            (10 * S, 14 * S, size * S - 10 * S, size * S - 6 * S), radius=32 * S,
            fill=(0, 0, 0, int(ap["shadow_alpha"])))
        img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(7 * S)))
        d.rounded_rectangle((6 * S, 6 * S, size * S - 6 * S, size * S - 6 * S),
                            radius=30 * S, fill=CARD)
        d.rounded_rectangle((6 * S, 6 * S, size * S - 6 * S, size * S - 6 * S), radius=30 * S,
                            outline=ACCENT[:3] + (int(ap["ring_alpha"]),),
                            width=max(2, int(ap["ring_width"] * S)))

        cx = size * S // 2
        hy = int(size * S * 0.49)
        hy += int(math.sin(2 * math.pi * 0.32 * t) * 1.5 * S + amp * 2.0 * S)
        scale = size / 240.0  # geometry below is authored for a 240px avatar

        def P(v):
            return int(v * S * scale)

        if ap.get("hair_length") == "long":
            d.ellipse((cx - P(62), hy - P(60), cx + P(62), hy + P(96)), fill=HAIR)
            d.rectangle((cx - P(62), hy + P(20), cx - P(34), hy + P(92)), fill=HAIR)
            d.rectangle((cx + P(34), hy + P(20), cx + P(62), hy + P(92)), fill=HAIR)

        # ── shirt ────────────────────────────────────────────────────────────
        shirt_box = (cx - P(66), hy + P(46), cx + P(66), size * S - P(8))
        layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
        ld = ImageDraw.Draw(layer)
        ld.rounded_rectangle(shirt_box, radius=P(26), fill=SHIRT)
        if ap["shirt_style"] == "gingham":
            x0, y0, x1, y1 = shirt_box
            cell, band = P(ap["check_cell"]), max(2, P(ap["check_cell"]) // 2)
            for xx in range(int(x0), int(x1), cell):
                ld.rectangle((xx, y0, min(xx + band, x1), y1), fill=SHIRT2[:3] + (150,))
            for yy in range(int(y0), int(y1), cell):
                ld.rectangle((x0, yy, x1, min(yy + band, y1)), fill=SHIRT2[:3] + (150,))
        img.alpha_composite(layer)
        if ap["shirt_style"] == "trim":
            d.rectangle((cx - P(4), hy + P(62), cx + P(4), size * S - P(8)), fill=SHIRT2)
            for by_ in (hy + P(78), hy + P(96)):
                d.ellipse((cx - P(3), by_, cx + P(3), by_ + P(6)), fill=light(SHIRT2[:3], 40))

        collar = [(cx - P(34), hy + P(46)), (cx, hy + P(70)), (cx + P(34), hy + P(46))]
        d.polygon(collar, fill=WHITE)
        edge = SHIRT2 if ap["shirt_style"] == "trim" else shade(WHITE[:3], 26)
        d.line([collar[0], collar[1]], fill=edge, width=max(1, P(1.3)))
        d.line([collar[1], collar[2]], fill=edge, width=max(1, P(1.3)))
        d.polygon([(cx - P(20), hy + P(46)), (cx, hy + P(62)), (cx + P(20), hy + P(46))],
                  fill=shade(WHITE[:3], 10))
        d.rectangle((cx - P(15), hy + P(26), cx + P(15), hy + P(56)), fill=SKIN_SH)

        # ── head ─────────────────────────────────────────────────────────────
        d.ellipse((cx - P(44), hy - P(52), cx + P(44), hy + P(52)), fill=SKIN)
        d.ellipse((cx - P(50), hy - P(6), cx - P(38), hy + P(14)), fill=SKIN_SH)
        d.ellipse((cx + P(38), hy - P(6), cx + P(50), hy + P(14)), fill=SKIN_SH)

        if ap["beard"]:
            # jaw + chin only — the cheeks stay clear; two-tone gradient
            outline = [
                (cx - P(43), hy + P(3)), (cx - P(46), hy + P(24)), (cx - P(35), hy + P(45)),
                (cx, hy + P(56)), (cx + P(35), hy + P(45)), (cx + P(46), hy + P(24)),
                (cx + P(43), hy + P(3)),
                (cx + P(17), hy + P(15)), (cx + P(15), hy + P(33)), (cx, hy + P(40)),
                (cx - P(15), hy + P(33)), (cx - P(17), hy + P(15)),
            ]
            bmask = Image.new("L", img.size, 0)
            ImageDraw.Draw(bmask).polygon(outline, fill=255)
            grad = Image.new("RGBA", img.size, (0, 0, 0, 0))
            gd = ImageDraw.Draw(grad)
            y0, y1 = hy + P(2), hy + P(57)
            for y in range(int(y0), int(y1) + 1):
                f = ((y - y0) / max(1, (y1 - y0))) ** 1.25
                gd.line([(0, y), (img.size[0], y)],
                        fill=tuple(int(BEARD_DARK[i] * (1 - f) + BEARD_WARM[i] * f) for i in range(3)) + (255,))
            img.paste(grad, (0, 0), bmask)
            mid = tuple(int(BEARD_DARK[i] * 0.55 + BEARD_WARM[i] * 0.45) for i in range(3)) + (255,)
            d.rounded_rectangle((cx - P(16), hy + P(12), cx + P(16), hy + P(20)), P(3), mid)
            d.rounded_rectangle((cx - P(20), hy + P(18), cx - P(10), hy + P(24)), P(2), mid)
            d.rounded_rectangle((cx + P(10), hy + P(18), cx + P(20), hy + P(24)), P(2), mid)

        # hair: shaped with an uneven hairline (not a cap), tapered sideburns
        RX, RY = P(47), P(55)
        top_cy = hy - P(8)
        pts = [(cx + RX * math.cos(math.radians(a)), top_cy + RY * math.sin(math.radians(a)))
               for a in range(178, 363, 3)]
        for x in range(int(cx + RX), int(cx - RX), -max(2, P(3))):
            dx = (x - cx) / RX
            base = hy - P(16)
            recede = max(0.0, abs(dx) - 0.5) ** 1.2 * P(46)
            peak = (1 - min(1.0, abs(dx) * 3.4)) * P(5)
            part = P(3) if dx > 0.25 else 0
            pts.append((x, base - recede + peak - part))
        d.polygon(pts, fill=HAIR)
        for sx in (-1, 1):
            d.polygon([(cx + sx * P(47), hy - P(16)), (cx + sx * P(40), hy - P(2)),
                       (cx + sx * P(46), hy + P(8)), (cx + sx * P(49), hy - P(4))], fill=HAIR)
        d.arc((cx - P(38), hy - P(50), cx + P(26), hy - P(6)), 200, 300,
              fill=light(HAIR[:3], 34), width=max(1, P(2.2)))

        # ── eyes ─────────────────────────────────────────────────────────────
        eye_dx, eye_y = P(17), hy - P(9)
        rx, ry = P(12.5), int(P(9.5))
        for sx in (-1, 1):
            ex = cx + sx * eye_dx
            ryb = int(ry * blink)
            if ryb < 2:
                d.line((ex - rx, eye_y, ex + rx, eye_y), fill=FRAME, width=max(1, P(1.6)))
                continue
            d.ellipse((ex - rx, eye_y - ryb, ex + rx, eye_y + ryb), fill=(255, 255, 255, 255))
            ir = max(1, int(P(6.2) * (0.75 + 0.25 * blink)))
            d.ellipse((ex - ir, eye_y - ir, ex + ir, eye_y + ir), fill=(74, 52, 38, 255))
            d.ellipse((ex - ir * 0.46, eye_y - ir * 0.46, ex + ir * 0.46, eye_y + ir * 0.46), fill=FRAME)
            d.ellipse((ex - ir * 0.75, eye_y - ir * 0.95, ex - ir * 0.15, eye_y - ir * 0.35),
                      fill=(255, 255, 255, 190))
            d.arc((ex - rx, eye_y - ryb, ex + rx, eye_y + ryb), 185, 355, fill=FRAME,
                  width=max(1, P(2.0)))
            if ryb > int(P(3)):   # PIL rejects an inverted arc box on half-blinks
                d.arc((ex - rx, eye_y - ryb + int(P(1.5)), ex + rx, eye_y + ryb - int(P(1.5))),
                      5, 175, fill=shade(SKIN[:3], 34), width=max(1, P(1.0)))

        if ap["glasses"]:
            lens_r = P(14)
            for sx in (-1, 1):
                ex = cx + sx * eye_dx
                d.rounded_rectangle((ex - lens_r, eye_y - lens_r * 0.86, ex + lens_r,
                                     eye_y + lens_r * 0.86), radius=P(4.5), fill=LENS,
                                    outline=FRAME, width=max(1, P(ap["frame_width"])))
                d.line((ex + sx * lens_r, eye_y - P(2), cx + sx * P(48), eye_y - P(6)),
                       fill=FRAME, width=max(1, P(1.1)))
            d.line((cx - P(5), eye_y - P(3), cx + P(5), eye_y - P(3)), fill=FRAME,
                   width=max(1, P(1.4)))

        lift = int(amp * 2.5 * S * scale)
        by = eye_y - (P(18) if ap["glasses"] else P(15)) - lift
        d.rounded_rectangle((cx - P(29), by, cx - P(6), by + P(4.4)), P(2), HAIR)
        d.rounded_rectangle((cx + P(6), by, cx + P(29), by + P(4.4)), P(2), HAIR)

        # ── mouth ────────────────────────────────────────────────────────────
        mw, mh, teeth = MOUTHS.get(viseme, MOUTHS["X"])
        my = hy + P(24)
        mwid, mhgt = mw * P(44), max(0.035, mh) * P(44)
        d.ellipse((cx - mwid / 2, my - mhgt / 2, cx + mwid / 2, my + mhgt / 2), fill=LIPS)
        if teeth:
            d.rounded_rectangle((cx - mwid * 0.42, my - mhgt / 2, cx + mwid * 0.42,
                                 my - mhgt * 0.18), radius=max(1, P(1.5)), fill=TEETH)
        d.arc((cx - mwid / 2, my - mhgt / 2, cx + mwid / 2, my + mhgt / 2), 20, 160,
              fill=tuple(min(255, c + 30) for c in SKIN[:3]) + (170,), width=max(1, P(1.1)))

        return img.resize((size, size), Image.LANCZOS).filter(ImageFilter.SMOOTH)


def main():
    ap = argparse.ArgumentParser(description="render the speaking-avatar frame sequence")
    ap.add_argument("--appearance", required=True)
    ap.add_argument("--cues", required=True, help="Rhubarb JSON ({mouthCues:[{start,value}]})")
    ap.add_argument("--audio", required=True, help="16 kHz mono WAV the cues were made from")
    ap.add_argument("--out", required=True, help="frames directory")
    ap.add_argument("--fps", type=int, default=30)
    ap.add_argument("--start", type=int, default=0, help="first frame index")
    ap.add_argument("--count", type=int, default=0, help="frames to render (0 = to end of audio)")
    ap.add_argument("--size", type=int, default=240)
    ap.add_argument("--preview", help="also write an mp4 of the avatar alone")
    ap.add_argument("--preview-bg", default="0xF6F4F5")
    args = ap.parse_args()

    appearance = dict(DEFAULTS)
    appearance.update(json.load(open(args.appearance)))
    cues = load_cues(args.cues)
    rms = load_envelope(args.audio, args.fps)

    with wave.open(args.audio) as wf:
        total = int(wf.getnframes() / wf.getframerate() * args.fps)
    count = args.count or max(0, total - args.start)

    os.makedirs(args.out, exist_ok=True)
    av = Avatar(appearance, size=args.size)
    for k in range(count):
        i = args.start + k
        t = i / args.fps
        frame = av.render(t, i, shape_at(cues, t), min(1.0, rms(i) * 9), blink_factor(i, args.fps))
        frame.save(os.path.join(args.out, f"f{k:05d}.png"))
    print(f"rendered {count} frames ({args.start / args.fps:.1f}s→{(args.start + count) / args.fps:.1f}s) "
          f"→ {args.out}")

    if args.preview:
        import subprocess
        cmd = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
               "-f", "lavfi", "-i",
               f"color=c={args.preview_bg}:s={args.size * 2}x{args.size * 2}:d={count / args.fps}",
               "-framerate", str(args.fps), "-i", os.path.join(args.out, "f%05d.png"),
               "-filter_complex",
               f"[1:v]scale={args.size * 2}:{args.size * 2}[av];[0:v][av]overlay=0:0:format=auto,format=yuv420p[v]",
               "-map", "[v]", "-c:v", "libx264", "-crf", "20", "-r", str(args.fps),
               "-t", f"{count / args.fps:.3f}", args.preview]
        subprocess.run(cmd, check=True)
        print(f"preview → {args.preview}")


if __name__ == "__main__":
    sys.exit(main())
