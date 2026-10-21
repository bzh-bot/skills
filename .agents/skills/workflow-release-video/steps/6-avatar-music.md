# R6 — Avatar + music → `<slug>-final.mp4`

**→ TaskUpdate: R6 → in_progress**

`workflow-video-tour/steps/5-avatar.md` and `steps/6-music.md` are the authority for the
cues, the frames and the bed. **One thing differs: where the mascot is drawn.**

## 6.1 Avatar — on the cards, not for four minutes

A mascot bobbing in the corner for the whole of a 4-minute video stops reading as a
presenter and starts reading as a watermark. Overlay it on the **cards** only — the intro,
each chapter divider and the close — and let the filmed beats be the app.

The tour's `avatar-overlay.sh` takes one contiguous `--start/--duration`; this skill ships
a superset that takes a window list and derives it from the assembled video's own
boundaries, so a re-voiced beat does not silently desync the windows.

```bash
S=~/.agents/skills/workflow-video-tour
V=~/.agents/skills/workflow-release-video
bash $S/scripts/avatar/avatar-visemes.sh --video "$VIDEO_DIR/$SLUG.mp4" --out "$VIDEO_DIR/avatar/cues.json"
python3 $S/scripts/avatar/avatar-svg-frames.py --svg "$S/assets/avatar.svg" \
  --cues "$VIDEO_DIR/avatar/cues.json" --out "$VIDEO_DIR/avatar/frames" --fps 30 --size 240

bash $V/scripts/avatar-overlay-ranges.sh \
  --video "$VIDEO_DIR/$SLUG.mp4" --frames "$VIDEO_DIR/avatar/frames" \
  --out "$VIDEO_DIR/$SLUG-avatar.mp4" \
  --video-json "$VIDEO_DIR/video.json" --timeline "$VIDEO_DIR/timeline.json" \
  --size 240 --corner br --caption-band 88 --bob 3
```

The tour's `steps/5-avatar.md` is the authority for the first two commands (the
"at most nine viseme states, rasterised once through chrome-headless-shell" trick, the
blink pair, the preflight). They are reproduced here so the shape of the chain is
visible — but if the two disagree, the tour's step wins.
- Cues come from the **finished mix**, not the per-beat WAVs — the mix already carries the
  400 ms lead-ins and the inter-beat gaps, so no offset maths is needed.
- **Frames must be one per video frame at the video's fps** (`f00000.png`, `f00001.png`, …).
  A `--framerate` mismatch drifts the mouth out of sync by the end of four minutes, which
  is the *only* way this looks broken rather than stylised. `--ranges "0-4,40-46"` takes an
  explicit window list; `--all` falls back to the tour's whole-video behaviour.
- **After any re-voice, re-derive.** `revoice-video.mjs` writes `<slug>.video.json` with
  new boundaries; pass **that** file to `--video-json`, or the windows point at the old
  beat times.

## 6.2 Music — always on, always licensed

`workflow-video-tour/steps/6-music.md`; the command is unchanged.

```bash
bash $S/scripts/add-music.sh --video "$VIDEO_DIR/$SLUG-avatar.mp4" \
  --music "$MUSIC_FILE" --out "$VIDEO_DIR/$SLUG-final.mp4"
```

- The bed is ducked by the narration (`sidechaincompress`), so a 4-minute runtime does not
  mean 4 minutes of the same 4 bars competing with the voice.
- **Pick the track for length, not for taste.** A 90-second loop is audibly looping by
  minute three; if the bed is shorter than the video, pick another or accept a
  `--fade`/loop decision knowingly.
- Attribution goes in the release body when the licence asks for it — record
  `MUSIC_ATTRIBUTION` now, not from memory later.

## Checks

- [ ] the avatar appears over the intro, every divider and the close, and **is absent on
      the filmed beats** (step through at 3 or 4 timestamps with `ffmpeg -ss … -frames:v 1`)
- [ ] window count printed by the overlay script equals the number of card beats + 1 for
      the intro
- [ ] the mouth moves on the dividers (they are narrated — a silent divider has a WAV
      missing, go back to R4)
- [ ] the mascot never covers the caption band or the boxed element
- [ ] the bed is audible under the voice and gone in the 4 s of silence at the front
      (`ffmpeg -ss 1 -t 2 -af volumedetect` on the intro should be near-silent before
      music, quiet after — the intro card has music in the tour's pipeline)
- [ ] `MUSIC_ATTRIBUTION` recorded in the run env / release body

**→ TaskUpdate: R6 → completed**
