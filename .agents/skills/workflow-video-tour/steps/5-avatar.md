# V5 — Avatar → `<slug>-avatar.mp4`

A small animated presenter in the bottom-right card: **the mascot** (`assets/avatar.svg`).
Its mouth follows the narration's Rhubarb cues, its eyes blink, and the overlay
gives it a gentle bob. Fully offline — no face model, no deepfake, no GPU, and it
is nobody's likeness.

```bash
S=~/.agents/skills/workflow-video-tour; A="$VIDEO_DIR/avatar"; SLUG="${TICKET_ID}-${FEATURE_TAG}"
# 1. cues from the FINISHED mix (the 400 ms lead-ins and the gaps are already in it,
#    so the mouth needs no offset maths) — then 16 kHz mono for the frames script
$S/scripts/avatar/avatar-visemes.sh --video "$VIDEO_DIR/$SLUG.mp4" --out "$A/cues.json"
ffmpeg -v error -y -i "$VIDEO_DIR/$SLUG.mp4" -vn -ac 1 -ar 16000 "$A/voice16k.wav"
# 2. frames: <=9 viseme states x 2 eye states rasterised once, hard-linked per frame
$S/scripts/avatar/avatar-svg-frames.py --svg $S/assets/avatar.svg --cues "$A/cues.json" \
  --out "$A/frames" --fps 30 --preview "$VIDEO_DIR/avatar-preview.mp4"
# 3. overlay above the caption band, with the bob, one re-encode
$S/scripts/avatar/avatar-overlay.sh --video "$VIDEO_DIR/$SLUG.mp4" --frames "$A/frames" \
  --out "$VIDEO_DIR/$SLUG-avatar.mp4" --size 240 --corner br --caption-band 88 --bob 3
```

`VIDEO_AVATAR="mascot"`. Cost: cues < 5 s, frames ≈ 30 s, overlay ≈ 1 min.

Toolchain the cage does not ship: Rhubarb goes on `RHUBARB`
(`/tmp/vidtools/rhubarb/Rhubarb-Lip-Sync-1.14.0-Linux/rhubarb`); the frames script
needs Pillow, so run it as `uv run --with pillow python …`; and it rasterises the SVG
through a browser, found via `CHROME_HEADLESS_SHELL` or the usual chromium/
`google-chrome` paths.

**Preflight this before starting V5** (learned 2026-10-07, <KEY>): the cage image
ships neither `rhubarb` nor `unzip`, and Rhubarb's release download is a ZIP — so a run
that reaches V5 without both burns minutes and then dies at the cues step.

```bash
for t in unzip; do command -v "$t" >/dev/null || echo "MISSING: $t"; done
[ -x "${RHUBARB:-/nonexistent}" ] || command -v rhubarb >/dev/null || echo "MISSING: rhubarb"
```

If Rhubarb/unzip cannot be obtained in this container, **skip the avatar instead of
guessing**: keep `VIDEO_AVATAR="none"` and publish `$SLUG.mp4` (narration + music,
already verified) as the video, then record a 🟢 loose end naming the missing tool. A
verified video without the mascot beats a fabricated or unverified one.

## What animates

| part | driver | where |
|---|---|---|
| mouth | Rhubarb cues `A..H` + `X`, one `<g id="viseme-*">` per shape | SVG, one visible at a time |
| eyes | `#eyes-open` / `#eyes-closed`, toggled on an uneven 3.6 s schedule | `avatar-svg-frames.py` |
| body bob | `±3 px` sine on the overlay's `y` expression, 3.4 s period | `avatar-overlay.sh --bob` |
| card | **static by design** — furniture that moves reads as "the background is animating" | — |

Blink tuning: `--blink-interval 3.6 --blink-frames 4` (≈4 frames shut at 30 fps) or
`--no-blink`. An SVG without the eye pair still works; it just never blinks, and the
script says so.

## Checks

- [ ] the cue histogram is not all `X` (else you cued silent or wrong audio)
- [ ] frames are RGBA with transparent corners (`magick identify` → sRGBA)
- [ ] the mouth moves: `.state-X-open.png` vs `.state-D-open.png` differ in the mouth band
- [ ] the eyes move: `.state-X-open.png` vs `.state-X-closed.png` differ in the eye band
      (the script checks both pairs itself and prints a `!` if either fails)
- [ ] the card sits above the caption band and never covers a beat's box
- [ ] audio untouched: `volumedetect` mean the same as V4

## Replacing or editing the mascot

`assets/avatar.svg` is hand-editable — it is plain SVG 1.1 with presentation
attributes, no `<style>`, no `<filter>`, no `<image>`. Keep the contract:

- `viewBox="0 0 240 240"`, card `#card-fill` + `#card-ring` at x=6 y=6 w=228 h=228 rx=30;
- ids `#avatar #card #body #shirt #collar #head #head-shape #eyes #eye-left/right
  #sclera/iris/pupil/highlight-left/right #brows #brow-left/right #mouth` and the
  nine `viseme-X..H` groups — **exactly one visible**;
- every viseme drawn inside the **26×24 band centred on (120,142)** so swapping one
  never moves the mouth;
- the optional blink pair `#eyes-open` / `#eyes-closed`.

Smoke-test any edit before rendering a whole video:

```bash
$S/scripts/avatar/avatar-svg-frames.py --svg assets/avatar.svg \
  --cues $S/assets/voice/cues.sample.json --out /tmp/av --count 15 --size 240
```
Look at `/tmp/av/f00010.png` at 240 px next to a video frame.

To design a different one from scratch, `prompts/avatar-svg.md` is the brief to hand
an image-capable agent (it produces a `avatar.svg` + palette + notes); the same
contract applies, and `scripts/avatar/avatar-svg-test.svg` is a structural fixture
you can render to check a pipeline change without touching the real avatar.

## Alternative: a drawn person (`AVATAR_MODE=pil`)

If you ever want a person rather than the mascot, `avatar-headshot.py` samples a
palette from a headshot you supply and `avatar-render.py` draws it with RMS bob and
blinks. It is **not** wired to any photo in this repo:

```bash
uv run --with opencv-python-headless python $S/scripts/avatar/avatar-headshot.py \
  --image ~/some/headshot.jpg --out "$A/appearance.json" --glasses no --beard yes --hair-length short
$S/scripts/avatar/avatar-render.py --appearance "$A/appearance.json" --cues "$A/cues.json" \
  --audio "$A/voice16k.wav" --out "$A/frames" --fps 30 --preview "$VIDEO_DIR/avatar-preview.mp4"
```
Always pass the three overrides (`glasses`/`beard`/`hair-length`) — the sampler
cannot see them, and a wrong beard is the one thing that reads as "that is not me".
Never dress an avatar in someone's face without their consent.
