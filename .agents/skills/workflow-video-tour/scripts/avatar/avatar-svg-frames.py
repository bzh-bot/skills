#!/usr/bin/env python3
"""avatar-svg-frames.py — rasterise the SVG avatar into the RGBA PNG frame
sequence avatar-overlay.sh consumes:

  avatar-svg-frames.py --svg avatar.svg --cues cues.json \
      --out frames/ [--fps 30] [--start 0] [--count N] [--size 240] \
      [--no-blink] [--blink-interval 3.6] [--blink-frames 4] \
      [--preview preview.mp4 --preview-bg #F6F4F5]

At most nine viseme states (one per Rhubarb shape present in cues.json) — times
two when the SVG carries a blink pair — are rasterised once through
chrome-headless-shell, then hard-linked per frame: 2600 frames cost one Chrome
run per *state*, not per frame.

Blink: if the SVG has `#eyes-open` / `#eyes-closed` groups this script toggles
their visibility on an uneven, deterministic schedule (interval + per-blink
offset), the same way it toggles the visemes. SVGs without that pair still work —
they just never blink.

Self-checks (mirrors SKILL.md 5.5):
  · every variant renders at --size², RGBA, with fully transparent corners
  · two different open visemes must differ in the mouth band (proves the
    visibility swap actually reached the renderer, not just the file)
  · an open/closed pair must differ, when the blink groups exist
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

CHROME_CANDIDATES = [
    os.environ.get("CHROME_HEADLESS_SHELL", ""),
    os.path.expanduser(
        "~/.cache/puppeteer/chrome-headless-shell/linux-152.0.7977.42/"
        "chrome-headless-shell-linux64/chrome-headless-shell"),
    "/usr/bin/chromium-browser", "/usr/bin/chromium", "/usr/bin/google-chrome",
]

VISEMES = list("XABCDEFGH")
BAND = {"x0": 120 - 13, "y0": 142 - 12, "x1": 120 + 13, "y1": 142 + 12}
# uneven, deterministic blink offsets (seconds added to each interval multiple)
BLINK_OFFSETS = (0.0, 0.13, -0.06, 0.21, 0.04, -0.11, 0.17, 0.08)


def find_chrome():
    for c in CHROME_CANDIDATES:
        if c and os.path.isfile(c) and os.access(c, os.X_OK):
            return c
    path = shutil.which("chrome-headless-shell") or shutil.which("chromium")
    if path:
        return path
    sys.exit("FATAL: no chrome-headless-shell/chromium found "
             "(set CHROME_HEADLESS_SHELL)")


def _apply(svg, group_id, visible):
    """Set one <g id="..."> group's visibility. Returns (svg, found)."""
    tag_re = re.compile(r'<g\b[^>]*\bid="%s"[^>]*>' % re.escape(group_id))
    m = tag_re.search(svg)
    if not m:
        return svg, False
    tag = m.group(0)
    want = 'visibility="%s"' % ("visible" if visible else "hidden")
    new = re.sub(r'visibility\s*=\s*"[^"]*"', want, tag) if "visibility=" in tag \
        else tag[:-1].rstrip() + " " + want + ">"
    return svg[:m.start()] + new + svg[m.end():], True


def retarget(svg, visible, eyes=None):
    """Flip visibility of the nine id=viseme-* groups (+ the blink pair).

    eyes is 'open', 'closed' or None. None leaves the eye groups untouched, which
    is what an SVG without an #eyes-open/#eyes-closed pair needs.
    """
    misses = []
    for letter in VISEMES:
        svg, found = _apply(svg, "viseme-%s" % letter, letter == visible)
        if not found:
            misses.append(letter)
    if misses:
        sys.exit("FATAL: avatar.svg is missing viseme group(s): %s"
                 % ", ".join("viseme-" + x for x in misses))
    if eyes:
        for gid, want in (("eyes-open", eyes == "open"), ("eyes-closed", eyes == "closed")):
            svg, _ = _apply(svg, gid, want)
    return svg


def blink_at(t, interval, dur):
    """True while the lids are shut, on an uneven but deterministic schedule.

    The per-blink offset is positive or negative, so a blink can start just before
    OR just after the interval multiple — check the neighbouring windows too.
    """
    if interval <= 0 or dur <= 0:
        return False
    k = int(t // interval)
    for j in (k - 1, k, k + 1):
        if j < 0:
            continue
        start = j * interval + BLINK_OFFSETS[j % len(BLINK_OFFSETS)]
        if start <= t < start + dur:
            return True
    return False


def shape_at(cues, t):
    """Last cue with start ≤ t (same rule as avatar-render.py)."""
    if not cues:
        return "X"
    for c in reversed(cues):
        if c["start"] <= t:
            return c["value"]
    return cues[0]["value"]


def rasterise(chrome, svg_path, png_path, size):
    cmd = [chrome,
           "--headless", "--disable-gpu", "--no-sandbox", "--hide-scrollbars",
           "--force-device-scale-factor=1",
           "--default-background-color=00000000",
           "--user-data-dir=" + tempfile.mkdtemp(prefix="avsvg-"),
           "--screenshot=" + png_path,
           "--window-size=%d,%d" % (size, size),
           "file://" + os.path.abspath(svg_path)]
    subprocess.run(cmd, check=True, capture_output=True, timeout=120)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--svg", required=True, help="avatar.svg from the Stage-1 agent")
    ap.add_argument("--cues", required=True, help="Rhubarb JSON ({mouthCues:[{start,value}]})")
    ap.add_argument("--out", required=True, help="frames directory")
    ap.add_argument("--fps", type=int, default=30)
    ap.add_argument("--start", type=int, default=0, help="first frame index")
    ap.add_argument("--count", type=int, default=0, help="frames to render (0 = to last cue)")
    ap.add_argument("--size", type=int, default=240)
    ap.add_argument("--no-blink", action="store_true", help="ignore the blink pair, keep the eyes open")
    ap.add_argument("--blink-interval", type=float, default=3.6, help="seconds between blinks")
    ap.add_argument("--blink-frames", type=int, default=4, help="frames the lids stay shut")
    ap.add_argument("--preview", help="also write an mp4 of the avatar alone")
    ap.add_argument("--preview-bg", default="#F6F4F5")
    args = ap.parse_args()

    from PIL import Image

    svg = open(args.svg).read()
    cues = json.load(open(args.cues))["mouthCues"]
    os.makedirs(args.out, exist_ok=True)
    chrome = find_chrome()

    has_blink = ('id="eyes-open"' in svg and 'id="eyes-closed"' in svg)
    if not has_blink and not args.no_blink:
        print("  · no #eyes-open/#eyes-closed pair in the SVG — the avatar will not blink")
    eye_states = ("open", "closed") if (has_blink and not args.no_blink) else (None,)

    # one PNG per viseme that actually occurs in the cue track (x the blink pair)
    needed = sorted({c["value"] for c in cues} & set(VISEMES))
    unknown = sorted({c["value"] for c in cues} - set(VISEMES))
    if unknown:
        print(f"  ! cue values outside A-HX ignored: {unknown}")
    variants = {}
    for letter in needed:
        for eyes in eye_states:
            key = letter if eyes is None else f"{letter}-{eyes}"
            vsvg = os.path.join(args.out, ".state-%s.svg" % key)
            open(vsvg, "w").write(retarget(svg, letter, eyes))
            png = os.path.join(args.out, ".state-%s.png" % key)
            rasterise(chrome, vsvg, png, args.size)
            im = Image.open(png).convert("RGBA")
            if im.size != (args.size, args.size):
                sys.exit(f"FATAL: {key} rendered {im.size}, wanted {(args.size, args.size)}")
            corners = [im.getpixel(p)[3] for p in
                       ((0, 0), (args.size - 1, 0), (0, args.size - 1), (args.size - 1, args.size - 1))]
            if any(a != 0 for a in corners):
                print(f"  ! {key}: canvas corners not transparent (alpha {corners}) — "
                      "check the outside-card area of avatar.svg")
            variants[key] = png
    print(f"  · rasterised {len(variants)} state(s) from {len(needed)} viseme(s) "
          f"{needed}{' × blink' if len(eye_states) > 1 else ''} via {os.path.basename(chrome)}")

    # mouth-band sanity: an open viseme must differ from the rest pose
    eye0 = eye_states[0]
    k = lambda v: v if eye0 is None else f"{v}-{eye0}"
    crop = (BAND["x0"], BAND["y0"], BAND["x1"], BAND["y1"])
    if len(needed) >= 2 and "X" in needed and any(v != "X" for v in needed):
        other = next(v for v in needed if v != "X")
        a, b = Image.open(variants[k("X")]), Image.open(variants[k(other)])
        if list(a.crop(crop).getdata()) == list(b.crop(crop).getdata()):
            print(f"  ! mouth band identical for viseme-X and viseme-{other} — "
                  "the visibility swap is not reaching the renderer")
    # blink sanity: the pair must actually differ
    if len(eye_states) > 1:
        a = Image.open(variants[f"{needed[0]}-open"])
        b = Image.open(variants[f"{needed[0]}-closed"])
        if list(a.crop((80, 90, 160, 130)).getdata()) == list(b.crop((80, 90, 160, 130)).getdata()):
            print("  ! open and closed eyes are identical in the eye band — the blink "
                  "groups are not reaching the renderer")

    total = int(cues[-1].get("end", cues[-1]["start"]) * args.fps) + 1
    count = args.count or max(0, total - args.start)
    blink_dur = args.blink_frames / args.fps
    interval = 0.0 if args.no_blink else args.blink_interval
    links = falls_back = blinks = 0
    for j in range(count):
        i = args.start + j
        t = i / args.fps
        vis = shape_at(cues, t)
        key = vis
        if len(eye_states) > 1:
            shut = blink_at(t, interval, blink_dur)
            blinks += 1 if shut and not blink_at((i - 1) / args.fps, interval, blink_dur) else 0
            key = f"{vis}-{'closed' if shut else 'open'}"
        dst = os.path.join(args.out, f"f{j:05d}.png")
        if os.path.exists(dst):
            os.remove(dst)          # hard-linking onto itself raises SameFileError
        try:
            os.link(variants[key], dst)
        except OSError:
            shutil.copy(variants[key], dst)
            falls_back += 1
        links += 1
    print(f"rendered {count} frames ({args.start / args.fps:.1f}s→{(args.start + count) / args.fps:.1f}s) "
          + (f"· {blinks} blink(s) " if len(eye_states) > 1 else "")
          + f"→ {args.out}" + (f"  ({falls_back} copies, hardlinks unsupported)" if falls_back else ""))

    if args.preview:
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