# Prompt: draw a *custom* SVG avatar (replaces the shipped mascot)

The default avatar is the mascot in `assets/avatar.svg` — a generic character, not
a likeness. Use this prompt when the human wants a **different character** (their
own, a brand mascot, a drawn person) and wants to keep editing it in
Figma/Inkscape. The output is contract-compatible with
`scripts/avatar/avatar-svg-frames.py`, so it drops into the identical overlay path.

Send this with **either** a photo (a likeness) **or** a written character brief
(brand colours, what it should feel like) **or** both. A likeness needs the
person's consent — ask before you send their photo to anything.

---

## ROLE

You are a **vector illustrator and SVG engineer**. You produce production-grade,
hand-editable SVG — not a traced bitmap.

## INPUT

Either an attached photograph of the person the avatar must depict, or a written
brief describing the character (or both). **Look at any image carefully.** If you
were sent a photo and cannot actually see it, say so and stop — never invent a
face.

## DELIVERABLES

1. `avatar.svg` — one self-contained file.
2. `avatar.palette.json` — every colour you sampled, with the pixel region it came from.
3. `avatar.notes.md` — layer list, palette, and anything ambiguous about the face.

## STYLE BRIEF

Flat editorial illustration: 2–3 tone shading per material, no photorealism, no
texture, no blur. Resemblance comes from **silhouette and feature geometry**,
never from detail: hair silhouette and hairline (temple recession, slight widow's
peak, side part if present), whether they wear glasses, beard extent and shape,
eyebrow thickness, and shirt colour. No hat, no hood — hair must read as *hair*.

## HARD SVG REQUIREMENTS

- SVG 1.1, `xmlns="http://www.w3.org/2000/svg"`, **`viewBox="0 0 240 240"`**, width/height 240.
- **Forbidden:** `<image>`, base64, external references, `<filter>`, `<style>`,
  CSS animation, `@keyframes`, `<use>` of external symbols. Presentation
  attributes only — this has to survive a Figma / Inkscape / Lottie import.
- Everything outside the rounded card is **fully transparent** (card corners included).
- **Fewer than ~60 paths total.** Flat fills; strokes only for glasses rims, the
  hair's inner edge and the iris rim.
- Every path closed, no stray sub-paths, no transform-scaling tricks
  (`translate` on groups is fine, `scale` is not).

## REQUIRED STRUCTURE (ids are contractual — do not rename)

```
#avatar                      root group, everything inside
├── #card                    rounded rect, x=6 y=6 w=228 h=228 rx=30
│   ├── #card-fill           fill #0C0C10, fill-opacity 0.66
│   └── #card-ring           stroke #CBB9C2, stroke-width 2.2, stroke-opacity 0.5, no fill
├── #body
│   ├── #shirt               flat fill, plain white shirt
│   └── #collar              V-shaped collar, lighter than the shirt
├── #hair-back               ONLY if the hair falls below the jaw
├── #head
│   ├── #head-shape          face
│   ├── #ears
│   ├── #beard               jaw and chin only — must NOT reach above the cheekbone
│   ├── #moustache
│   ├── #hair-front          cap + hairline
│   ├── #sideburns           tapered, ending above the ears
│   ├── #brows  →  #brow-left, #brow-right
│   ├── #eyes
│   │   ├── #eye-left        → #sclera-left #iris-left #pupil-left #highlight-left #lid-left
│   │   └── #eye-right       → same five parts
│   ├── #mouth               see below
│   ├── #eyes-open           all eyes open    (delivered visible)
│   └── #eyes-closed         both lids shut   (delivered hidden)
└── #glasses                 omit entirely if they don't wear glasses
    ├── #lens-left / #lens-right   fill-opacity ≤ 0.06 (clear lenses, NOT sunglasses)
    └── #frame                     thin rim, ~1.1 units
```

### Mouth — nine interchangeable visemes

Draw **all nine** and give each `id="viseme-X" … id="viseme-H"`. Exactly one is
visible in the delivered file (`viseme-X`); the other eight have `visibility="hidden"`.
Each is a `<g>` containing the lips (and teeth where noted):

| id | shape | teeth |
|---|---|---|
| `viseme-X` | rest, gently closed, slight smile | no |
| `viseme-A` | closed (M / B / P) | no |
| `viseme-B` | small opening | no |
| `viseme-C` | medium opening | no |
| `viseme-D` | wide open | yes |
| `viseme-E` | rounded "O" | no |
| `viseme-F` | pursed, wider than tall | yes |
| `viseme-G` | tight and small | yes |
| `viseme-H` | nearly closed | yes |

**Contract:** every viseme is drawn on the *same baseline box* — mouth centre at
`(120, 142)`, inside a 26×24 unit band. Swapping one for another must not move
the lips, the beard notch or the chin.

## COLOUR

Sample from the photo and record in `avatar.palette.json`:
forehead and both cheeks → **skin**; hairline and hair sides → **hair**;
jaw below the mouth → **beard**; chest → **shirt**; top corners → **backdrop**.

A beard, if present, is **two-tone**: near the hair colour at the sideburns and
warmer toward the chin (worked example: `#2E2018` → `#8F4E22`).

### Blink — the eyes come in a pair

Wrap the two eyes in **two sibling groups**, `id="eyes-open"` (delivered
`visibility="visible"`) and `id="eyes-closed"` (delivered `visibility="hidden"`).
Both keep the same eye ids (`#eye-left`/`#eye-right` and their five parts); the
closed one draws shut lids on the same baseline. The frames script toggles those
two groups the same way it toggles the visemes — that is what makes the avatar
blink. A delivered file may omit them, but then the avatar never blinks.

## SELF-CHECK BEFORE YOU ANSWER

1. Rasterise `avatar.svg` at **240×240** and at **1024×1024** and *look at both*.
   Ask: does this read as that person at 240 px, next to a video frame? If not, redraw.
2. Grep your own file: no `<image`, no `<filter`, no `<style`, no `@keyframes`.
3. Confirm all ids exist, exactly one `viseme-*` is visible, every viseme path sits
   inside the 26×24 mouth band around `(120, 142)`, and exactly one of
   `#eyes-open` / `#eyes-closed` is visible.
4. Confirm the four canvas corners are transparent.

## REPORT BACK

Palette table, full layer list, path count, and the judgement calls you made
(hair length, beard extent, glasses on/off) so a human can correct them fast.

## STAGE 2 (only if asked)

Animated version: keep the structure, switch `viseme-*` visibility on a timeline
supplied as Rhubarb JSON (`{start, value}` cues, A–H and X), plus a blink
animation on the `#eye-*` lids. Output SVG+CSS or Lottie JSON — state which.

---

---

## Integrating the answer

Save it as `assets/avatar.svg`, then follow `steps/5-avatar.md` — the frames script
rasterises all nine viseme states through chrome-headless-shell and hard-links them
into the sequence `avatar-overlay.sh` consumes (no SVG rasteriser is installed on
this box: no resvg / rsvg-convert / inkscape / cairosvg).
