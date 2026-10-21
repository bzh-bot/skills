# R3 — Capture → `seg/*.mp4` + `timeline.json`

**→ TaskUpdate: R3 → in_progress**

This is `workflow-video-tour/steps/2-capture.md`, unchanged. **Read that doc before
running anything** — every trap in it is live at 22 beats, and a few get worse.

```bash
S=~/.agents/skills/workflow-video-tour; V=~/.agents/skills/workflow-release-video
export VIDEO_DIR="${VIDEO_DIR:-$REPO/.release-video}"
# 0. render the diagrams BEFORE capture — the capture refuses a storyboard without them
#    (see workflow-video-tour/diagrams.md) and validates every PNG
node $S/scripts/render-diagrams.mjs --storyboard "$VIDEO_DIR/storyboard.json" --out "$VIDEO_DIR"
node $S/scripts/capture-beats.mjs --storyboard "$VIDEO_DIR/storyboard.json" --out "$VIDEO_DIR" \
  --app "$APP_URL" --session "$CHROME_SESSION" --profile "$CHROME_SESSION_PROFILE" \
  --viewport 1600x900 --login-email "$LOGIN_EMAIL" --login-password "$LOGIN_PASSWORD" \
  --before-cmd "$BEFORE_CMD" --after-cmd "$AFTER_CMD" \
  [--only c3-b1-invoice]
```

**Diagram beats are not captured.** They are `source: "image"` stills: no browser tab, no
`--before-cmd`, no `readyText`. The capture checks the PNG exists and writes the beat into
`timeline.json` with `segment: null`; `--only <still-id>` re-indexes it without opening
anything. The architecture beat and each chapter ERD must already be rendered, and the
contract gate (intro diagram before the first filmed beat, ERD before its chapter's
filmed beats, `touchesDataModel` honoured) exits 2 before any browser work if not.

**Start the real demo tools before any non-UI beat** — at 26 beats a release will have
several, and one hand-built table is enough to make the whole video untrustworthy:

```bash
bash $S/scripts/demo-tools.sh up        # CloudBeaver + Hoppscotch, run's DB + API base
bash $S/scripts/demo-tools.sh require   # exit 1 = the evidence gate fails
# URLs: jq -r '.cloudbeaver_url, .hoppscotch_url, .api_base' "$VIDEO_DIR/demo-tools.json"
```

## What is different at release scale

**1. `--before-cmd` / `--after-cmd` swap the whole release, not a fix.**

```bash
# BEFORE = the previous release, in its own worktree + dev server. Never a mock.
BEFORE_WT="$REPO/../$(basename $REPO)-at-${RELEASE_FROM}"
git -C "$REPO" worktree add "$BEFORE_WT" "${RELEASE_FROM}"
# …install deps, start its dev server on its own port, seed the same data…
BEFORE_CMD='kill $(cat /tmp/after.pid) 2>/dev/null; (cd '"$BEFORE_WT"' && ./dev.sh --port 5174) & echo $! >/tmp/before.pid; sleep 20'
AFTER_CMD='kill $(cat /tmp/before.pid) 2>/dev/null; (cd '"$REPO"' && ./dev.sh --port 5173) & echo $! >/tmp/after.pid; sleep 20'
```

If the previous release cannot be run (missing tag, schema drift, no data), **do not
fake a BEFORE** — drop the BEFORE beats, drop the `phase` from those beats, and narrate
the change instead. A fabricated BEFORE is the one thing in this skill that cannot be
recovered from.

**2. Cost is 20+ minutes, so batch by chapter and use `--only` without guilt.**

`capture-beats.mjs` writes `timeline.json` at the end of a full run; `--only <id>`
re-records a single beat and merges it in. Re-record one beat per fix, never a chapter.

**3. Cross-origin surfaces are real `open`s and re-logins.** With 8 chapters you will
switch app ↔ mail catcher ↔ logs ↔ metrics far more than six times. Each switch costs
a `open` + `ensureLogin()`; budget ~8 s per beat for it, and check the frame size after
each switch (the daemon caps are set once — see the tour's trap).

**4. Watch the daemon.** 22 beats over 25 minutes is long enough for the browser session
to die mid-run. If `timeline.json` is missing beats, that is why: re-run with `--only`
for the missing ids rather than starting over.

## Checkpoints

Run this after every 4–5 chapters instead of once at the end. A capture failure found at
beat 20 costs 20 minutes; found at beat 5, two.

```bash
# how far did it get, and is anything obviously wrong?
jq -r '.[] | [.id, (if .segment then "seg" elif .image then "diagram" else "card" end), (.durationMs/1000|tostring), (.rect.w|tostring)] | @tsv' \
  "$VIDEO_DIR/timeline.json" 2>/dev/null | column -t
```

## Checks

- [ ] every filmed beat has a non-null `rect` (null → the box target was off-screen: fix
      `readyText`/`box` and re-run with `--only`)
- [ ] `frameW/frameH == viewportW/viewportH` on every beat
- [ ] `framesPushed / (durationMs/1000) ≈ 30` on every beat (a low rate means the pump
      never started on that beat)
- [ ] every card beat is present with `segment: null` — a **missing card beat** is silent
      and shows up only in R5 as a missing chapter divider
- [ ] every diagram beat is present with `segment: null` and an absolute `image` path, in
      the right place: architecture before the first filmed beat, each ERD after its
      chapter's divider and before that chapter's filmed beats
- [ ] `render-diagrams.mjs --check` still passes (a `.mmd` edited during the run would
      otherwise ship a stale PNG)
- [ ] every non-UI beat is in CloudBeaver / Hoppscotch / Google Sheets — no custom table,
      no pretty-printed `curl`; the URLs came from `demo-tools.json`
- [ ] BEFORE beats really show the previous release (open `seg/c1-*.mp4` and look), AFTER
      beats really show HEAD
- [ ] `jq '[.[] | select(.segment)] | length' timeline.json` equals the number of filmed
      beats in the storyboard

**→ TaskUpdate: R3 → completed**
