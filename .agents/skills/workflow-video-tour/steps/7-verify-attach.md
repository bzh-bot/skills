# V7 — Verify & attach

```bash
S=~/.agents/skills/workflow-video-tour; SLUG="${TICKET_ID}-${FEATURE_TAG}"; FINAL="$VIDEO_DIR/$SLUG-final.mp4"
# after a revoice, use the NEW boundaries (<slug>.video.json), not the source video.json
bash $S/scripts/verify-video.sh "$FINAL" --timeline "$VIDEO_DIR/timeline.json" --video-json "$VIDEO_DIR/video.json"
```

`verify-video.sh` fails on: no audio stream, mean < −35 dB, > 3 silences ≥ 2 s, or a
`--timeline`/`--video-json` path that does not exist (it refuses to "verify" while
silently skipping checks — that once let a whole verification pass with nothing
checked). Warns on: > 40 MB, quiet peak, a box whose top edge is not red/green.

It also writes **`$VIDEO_DIR/contact-sheet.png`** — one frame per beat. **Look at
it.** The colour test proves a box was drawn; only your eyes prove it is on the right
element, and the sheet is the cheapest way to check all of them at once (it caught
four misplaced boxes in one glance on the first sample that used it). **The diagram
frames are the other reason to look:** each one must be readable at 1600×900, with the
kind chip visible and no caption sitting on a table name. **Do not attach on FAIL.**

## Attach — top of the PR body, above `## Motivation`

```bash
gh pr edit "$PR_NUMBER" --repo "$ORG/$REPO_NAME" --attach "$FINAL"     # uploads; returns the asset URL in the body
```
`--attach` appends the asset at the bottom. Move it: fetch the body, cut the
`https://github.com/user-attachments/assets/…` line, and re-insert this block as
the first thing in the body:

```markdown
<asset URL>

🎵 <MUSIC_ATTRIBUTION>            ← only when the licence requires it

(no heading, no duration label — the video stands alone at the top of the body)
```

`workflow-do-ship` P8 rewrites the body from its template; the template has this
block first, so P8 must carry the asset URL over (it reads `VIDEO_PATH`/`VIDEO_URL`
from the run env).

## Hand off

```bash
cp "$FINAL" "$VIDEO_DIR/storyboard.json" "$VIDEO_DIR/video.json" "$SCREENSHOTS_DIR/"
# the diagram sources + renders travel with the video: a reviewer must be able to open
# the .mmd and check the ERD against the migration (see ../diagrams.md)
cp -r "$VIDEO_DIR/diagrams" "$SCREENSHOTS_DIR/diagrams"
cat >> /tmp/workflow-run.env <<EOF
VIDEO_PATH="$FINAL"
VIDEO_URL="<asset URL>"
VIDEO_ATTACHED="1"
VIDEO_DURATION_S="$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$FINAL" | cut -d. -f1)"
VIDEO_DIAGRAMS="$(jq '[.beats[] | select(.source == "image")] | length' "$VIDEO_DIR/storyboard.json") (intro + ERD if touchesDataModel)"
VIDEO_NARRATION="qwen3-clone/ref-10s"
VIDEO_AVATAR="svg"
VIDEO_MUSIC="$(basename "$TRACK")"
MUSIC_ATTRIBUTION="$MUSIC_ATTRIBUTION"
EOF
```

Report the beat list (what the reviewer will see, diagrams included) in the handoff. Keep the
browser and dev servers up — P8 runs next. Keep `$VIDEO_DIR`.

If the human authorised skipping the video: `VIDEO_ATTACHED="0"`,
`VIDEO_SKIP_NOTE="user authorised skip of P7.8: <reason>"`, nothing else. If the human
authorised a diagram-less video, `VIDEO_DIAGRAMS="none — <reason>"` — that exception is
recorded in the PR body by name of the person who gave it.
