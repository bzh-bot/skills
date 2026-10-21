# R5 — Assemble → `<slug>.mp4` + `video.json`

**→ TaskUpdate: R5 → in_progress**

`workflow-video-tour/steps/4-assemble.md` is the authority. The command is unchanged.

```bash
S=~/.agents/skills/workflow-video-tour
SLUG="${SLUG:-$(basename "${REPO}")-$(jq -r '.release.fromTag // .release.fromDate' "$VIDEO_DIR/release-manifest.json" | tr -d ':')}"
node $S/scripts/compose-video.mjs --timeline "$VIDEO_DIR/timeline.json" --tts "$VIDEO_DIR/tts" \
  --out "$VIDEO_DIR" --slug "$SLUG" \
  --title "$(jq -r .title "$VIDEO_DIR/storyboard.json")" \
  --subtitle "$(jq -r .subtitle "$VIDEO_DIR/storyboard.json")" \
  --intro-footer "$(jq -r '.release.slug + " · " + (.release.fromTag // .release.fromDate) + " → " + .release.toRef' "$VIDEO_DIR/release-manifest.json")"
```

`ffmpeg` must have **libfreetype** (`drawtext`). `ffmpeg -filters | grep drawtext`
before you start; the `ffmpeg-static` npm build does not have it.

**Re-check the narration sync first — it is not just an R4 concern.** `compose-video.mjs`
also reads `timeline.json`, so any caption, divider heading, bullet or footer edited in the
storyboard since R4 is silently ignored here too. In the first MassCEC release video a
stale caption and a stale close-card bullet both reached the cut this way, and only a
read of the contact sheet caught them.

```bash
node ~/.agents/skills/workflow-release-video/scripts/check-narration-sync.mjs \
  "$VIDEO_DIR/storyboard.json" "$VIDEO_DIR/timeline.json"
```

## What it does, and what is new here

Per beat: `drawbox` the measured rect, `drawtext` the caption, loudnorm the narration to
−16 LUFS, 400 ms lead-in, and the beat lives `max(6, voice + 1.5)` s. **Card beats**
(`segment: null`) become narrated cards — the intro from `title`/`subtitle`, a chapter
divider from `heading` + `bullets` + `footer`, the close the same. **Diagram beats**
(`image` set) become fitted stills: the PNG inside 92 % of the frame on the bed colour, a
1.05 push-in, an `ARCHITECTURE`/`CONCEPT`/`DATA MODEL` chip top-left, and the caption in
the bottom band; they live `max(6, voice + 1.8)` s. Everything else is the tour's
behaviour; nothing in `compose-video.mjs` is aware of chapters, and nothing needed to
change for a 4-minute video.

Two consequences of length:

- **The intro card is still 4 s of silence at the front.** `verify-video.sh` expects
  exactly one ≥2 s silence; with dividers *narrated* there is no other silent gap, so this
  still holds. If it reports more than one, a card beat is missing its WAV (R4).
- **Render time.** 26 beats × (encode + loudnorm) is a few minutes; the concat is
  `-c copy`. If the encoder dies mid-way, `compose-video.mjs` stops rather than hanging —
  fix the beat and re-run; it re-encodes from scratch, but the captures and WAVs are kept.

## Checks

- [ ] **`check-narration-sync.mjs` passes** — every caption, divider heading, bullet and
      footer in the cut matches the storyboard. A stale caption is invisible to
      `verify-video.sh`; only this check and the contact sheet catch it
- [ ] **the printed beat table lists all 25–27 narrated beats**, with `card` on every divider and
      on the close, and no beat missing
- [ ] `jq .durationS video.json` is within ~10 s of `budget.json.measuredS` from R4
      (a bigger gap means the intro or a card was skipped)
- [ ] **look at `contact-sheet.png`** — one frame per beat, the only cheap way to confirm
      every red/green box is on the right element and every divider reads correctly.
      `verify-video.sh` makes the same sheet in R7; looking now saves a full re-render
- [ ] **the diagram frames in that sheet are readable at 1600×900** — architecture and
      ERD frames, chip visible, no clipped edge, no caption over a table name
- [ ] the intro card is legible and the chapter bullets fit; a divider with 4 long bullets
      overflows its band — shorten the bullets, do not shrink the font
- [ ] nothing important sits under the caption band (bottom 88 px) — at this length the
      mascot and the captions both live down there
- [ ] `volumedetect` mean ≈ −20 dB (silence check is R7)

**→ TaskUpdate: R5 → completed**
