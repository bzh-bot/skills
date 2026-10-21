# V4 — Assemble → `<slug>.mp4` + `video.json`

```bash
S=~/.agents/skills/workflow-video-tour; SLUG="${TICKET_ID}-${FEATURE_TAG}"
node $S/scripts/compose-video.mjs --timeline "$VIDEO_DIR/timeline.json" --tts "$VIDEO_DIR/tts" \
  --out "$VIDEO_DIR" --slug "$SLUG" \
  --title "$(jq -r .title "$VIDEO_DIR/storyboard.json")" \
  --subtitle "$(jq -r .subtitle "$VIDEO_DIR/storyboard.json")"
```

Needs `ffmpeg`/`ffprobe` **with libfreetype** (the `drawtext` filter) on `PATH`.
The `ffmpeg-static` npm build has no drawtext, so point `PATH` at a full build
(cage: `/tmp/ffbtbn/bin`); `ffmpeg -filters | grep drawtext` confirms it.

## What it does

- **Intro card** (4 s, `--title-seconds` to change): `title` big, `subtitle` in the
  accent colour under it, silent. Always present — it is how a reviewer knows which
  ticket and PR they are looking at.
- Per beat: `drawbox` the measured rect (scaled if frame ≠ viewport), `drawtext`
  the caption from a file (no escaping), loudnorm narration to −16 LUFS, 400 ms
  lead-in, then the beat lives for `max(6, narration + 1.5)` s — the video follows the
  voice and the clip's excess hold after the line ends is dropped; the last frame is
  cloned (`tpad`) only when the line overruns the clip. Never fit the line to the
  clip: `max(6, min(clip, narration + 1.5))` truncated speech mid-word.
- Static beats become cards with the caption centred and the subtitle beneath.
- **Diagram beats** (`image` set) become stills: the PNG is fitted inside 92 % of the frame
  (never cropped), on the bed colour, with a gentle 1.05 push-in, a small
  `ARCHITECTURE` / `CONCEPT` / `DATA MODEL` chip top-left, and the caption in the same
  bottom band as every filmed beat. `beat.zoom: false` pins it. They live
  `max(6, voice + 1.8)` s, like a card — there is no clip to fit. A missing PNG stops the
  run with the path and the render command.
- Concat with `+faststart`; writes `video.json` **and `<slug>.video.json`** (beat
  boundaries — needed by V5, V7 and `revoice-video.mjs`). The per-slug copy matters
  when you compose several variants into one directory, where the shared name would be
  overwritten.

## Re-voice without re-capturing

```bash
node $S/scripts/revoice-video.mjs --source "$VIDEO_DIR/$SLUG.mp4" --video-json "$VIDEO_DIR/video.json" \
  --tts "$VIDEO_DIR/tts-v2" --out "$VIDEO_DIR" --slug "$SLUG-v2"
```
Cuts at the recorded boundaries, refits each beat to the new line, keeps the
burned-in boxes and captions.

**A re-voice changes the video's length, so three things must be redone** — the
script tells you when it detects it, but the order matters:

1. It writes **`<slug>.video.json`** with the new beat boundaries. Pass *that* to
   `verify-video.sh`; the source's `video.json` describes the old timing and makes
   the box checks sample the wrong frames (observed: three boxes reported "not
   visible" while they were perfectly fine).
2. **Re-cut the avatar cues from the new mix** (`avatar-visemes.sh --video
   "<slug>-v2.mp4"`) — the old cues were cued against the old audio, so the mouth
   drifts out of sync.
3. Re-run V5's frames and overlay, then V6 and V7.

## Checks

- [ ] `video.json.durationS` is 45–75
- [ ] `ffmpeg -i out.mp4 -af silencedetect=noise=-45dB:d=2 -f null -` → exactly
      one silence (the intro card)
- [ ] `volumedetect` mean ≈ −20 dB
- [ ] **look at `$VIDEO_DIR/contact-sheet.png`** — `verify-video.sh` writes one
      frame per beat; this is the only cheap way to confirm every red/green box is on
      the right element (V7 makes the same sheet)
- [ ] **the diagram frames in that sheet are readable at 1600×900** — no clipped edge, no
      caption over the smallest label, the chip present. The 3200 px PNG you approved is
      not what the viewer sees; this frame is.
- [ ] the intro card is legible over its backdrop and the close card's bullets fit
- [ ] nothing important sits under the caption band (bottom 88 px)

Cost: 1–2 min.
