# R4 — Narration → `tts/*.wav` + the measured budget

**→ TaskUpdate: R4 → in_progress**

## Before you render: sync the storyboard into the timeline

**Do this first, or the render silently ignores every script edit you have made since the
capture.** `capture-beats.mjs` copies each beat into `timeline.json`, and `tts-qwen3.py`
reads the *timeline* — not `storyboard.json`. A narration, caption or divider edit that
lands in the storyboard after R3 is invisible here, and nothing warns you: the build simply
speaks the previous revision. In an early release video that shipped stale audio
on 11 of 19 beats.

```bash
V=~/.agents/skills/workflow-release-video
node $V/scripts/check-narration-sync.mjs "$VIDEO_DIR/storyboard.json" "$VIDEO_DIR/timeline.json" \
  || node $V/scripts/sync-timeline-from-storyboard.mjs "$VIDEO_DIR/storyboard.json" "$VIDEO_DIR/timeline.json"
node $V/scripts/check-narration-sync.mjs "$VIDEO_DIR/storyboard.json" "$VIDEO_DIR/timeline.json"
```

`sync-timeline-from-storyboard.mjs` copies only the spoken/shown fields — `narration`,
`caption`, `heading`, `bullets`, `footer` — and never touches capture geometry (`segment`,
`durationMs`, `rect`, frame sizes). A narration fix must never cost a re-capture. Run the
check again **after** the rebuild too, and again in R5 before `compose-video.mjs`.

## Render the narration

`workflow-video-tour/steps/3-narration.md` is the authority — read it. The command is
unchanged; what changes at 26 beats is how much the identity and sizing checks matter.

```bash
S=~/.agents/skills/workflow-video-tour
export QWEN3_ROOT=~/.cache/qwen3-tts
export TORCH_DISABLE_NATIVE_JIT=1
~/.cache/qwen3-tts/venv/bin/python $S/scripts/tts-qwen3.py \
  --mode custom --speaker Aiden --stable --instruct "" \
  --timeline "$VIDEO_DIR/timeline.json" --out "$VIDEO_DIR/tts"
~/.cache/qwen3-tts/venv/bin/python $S/scripts/voice-identity.py "$VIDEO_DIR/tts"
~/.cache/qwen3-tts/venv/bin/python $S/scripts/voice-stats.py    "$VIDEO_DIR/tts"
```

Output is one `<beat-id>.wav` per narrated beat (including cards). `compose-video.mjs`
loudnorms each into `<beat-id>.n.wav` itself — do not normalise them here.

## The measured budget — the check that only exists in this skill

Every per-beat number in `storyboard.json` was an estimate. This is where the estimate
meets the truth, and where a 4-minute video is won or lost: **26 lines that each run one
second long is 26 extra seconds**, which is 10 % over.

Reproduce `compose-video.mjs`'s own arithmetic — `max(6, voice + 1.5)` for a filmed beat,
`max(6, voice + 1.8)` for a card **or a diagram still**, plus 4 s of intro — and compare it
with the plan. Diagram beats are `segment: null`, so the snippet counts them as cards,
which is correct and is why a diagram beat costs its words plus ~1.8 s:

```bash
total=$(for f in "$VIDEO_DIR"/tts/*.wav; do
  id=$(basename "$f" .wav)
  is_card=$(jq -r --arg id "$id" '.[] | select(.id==$id) | if .segment == null then "card" else "film" end' "$VIDEO_DIR/timeline.json")
  d=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$f")
  awk -v d="$d" -v k="$is_card" 'BEGIN{ pad = (k=="card" ? 1.8 : 1.5); t = d + pad; if (t < 6) t = 6; printf "%.2f\n", t }'
done | awk '{s+=$1} END { printf "%.1f\n", s + 4 }')
planned=$(jq -r '.plannedWords / 2.5 + .cards * 1.8 + .filmBeats * 1.5 + 4 | floor' "$VIDEO_DIR/budget.json")
echo "measured ${total}s   planned ${planned}s   target $(jq -r .targetS "$VIDEO_DIR/budget.json")s"; echo "$(ls "$VIDEO_DIR"/tts/*.wav | wc -l) wavs"
```

Write the result back so R5 and R7 can read it, and stop here if it is out of range:

```bash
jq --argjson measured "$total" --argjson wavs "$(ls "$VIDEO_DIR"/tts/*.wav | wc -l)" \
   '. + {measuredS: $measured, beatsRendered: $wavs}' \
   "$VIDEO_DIR/budget.json" > "$VIDEO_DIR/budget.tmp" && mv "$VIDEO_DIR/budget.tmp" "$VIDEO_DIR/budget.json"
```

**If `measuredS` is outside 230–290:**

| measured | what to do |
|---|---|
| < 200 s | the release is thin. Ship the shorter video; do **not** pad the narration |
| 200–230 s | add one filmed beat to each of the 2–3 biggest chapters (`--only` capture) |
| 230–290 s | accept |
| > 290 s | cut the weakest chapter (its divider and its beats), not words from good lines |
| > 320 s | the storyboard was over budget; go back to R2 with the measured words/beat |

Never fix the length by trimming speech. `compose-video.mjs` freezes the last frame to
let a long line finish, so an over-long beat shows as a still image with a voice over it
— the single ugliest failure this pipeline produces, and it is always the storyboard's
fault, never the TTS's.

## Checks

- [ ] **`voice-identity.py` → "ok — one speaker"** (LTAS cosine ≥ 0.99). This is the
      check that matters most at this length: a drift that is barely audible across six
      beats is unmistakable across twenty-six, and it is the failure mode that shipped
      once already on the six-beat version
- [ ] every diagram beat has a WAV too — a silent architecture beat is the one beat a
      viewer needs the words for
- [ ] **`check-narration-sync.mjs` passes** — the timeline and the storyboard agree on
      everything a viewer hears or reads. This is the check that would have caught the
      stale 11-of-19-beat render; no other automated gate would have
- [ ] one `.norm.wav` per narrated beat, including every **card** beat — a missing card
      WAV means a silent chapter divider in R5
- [ ] no runaway take: no WAV longer than ~14 s, and none roughly equal across beats of
      different lengths
- [ ] `measuredS` recorded in `budget.json`, in range, and the decision recorded when it
      is not
- [ ] `voice-stats.py` per-beat pitch spread < 20 Hz (a spread is fine; a second speaker
      is not)
- [ ] listen to the first divider and the close back to back — same person, same energy

**→ TaskUpdate: R4 → completed**
