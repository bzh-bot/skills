# V2 — Capture → `seg/*.mp4` + `timeline.json`

**⚠️ Always run the capture under a timeout.** `capture-beats.mjs` waits for `readyText` on the live
page; if the page never reaches that state (a dev-server hiccup, a login redirect, a CDP stream that
stopped pushing frames) the wait is **unbounded** and the tool call hangs for hours — one <KEY>
tour burned 3h21m on a single `--only b1` invocation before anyone noticed (2026-10-16). Wrap every
invocation, and never retry blindly more than twice:

```bash
timeout 600 node $S/scripts/capture-beats.mjs … 2>&1 | tail -12
echo "exit=$?  (124 = timed out → fix readyText/route/storyboard state, do NOT just re-run)"
```
The same applies to any long browser call in this skill (`agent-browser download`, `stream`, an
`open` that waits for a load event): give it a `timeout`. A hung capture is a hang, not a slow render.


```bash
S=~/.agents/skills/workflow-video-tour; export VIDEO_DIR="$WORKTREE/.workflow-video"
# 0. the window must be big enough for the 1600x900 frame. `--window-size` is only a
#    request under Wayland (niri sizes the tile), so MEASURE it; on failure widen the
#    niri column or run ~/.agents/skills/workflow-do/scripts/place-chrome.sh — never
#    shrink --viewport to match a 948x947 window (2026-10-19, live run).
bash ~/.agents/skills/workflow-do/scripts/chrome.sh viewport    # prints WxH, exit 1 below 1600x900
# 1. render the mandatory diagrams first (see ../diagrams.md) — the capture refuses to
#    start without them, and it validates that every PNG exists
node $S/scripts/render-diagrams.mjs --storyboard "$VIDEO_DIR/storyboard.json" --out "$VIDEO_DIR"
# 2. capture the filmed beats
timeout 600 node $S/scripts/capture-beats.mjs --storyboard "$VIDEO_DIR/storyboard.json" --out "$VIDEO_DIR" \
  --app "http://localhost:<frontend-port>" --session "$CHROME_SESSION" --profile "$CHROME_SESSION_PROFILE" \
  --viewport 1600x900 --login-email <dev-user> --login-password '<dev-pw>' \
  --before-cmd '<swap in the pre-fix code / deliver the BEFORE event>' \
  --after-cmd  '<restore the fix / deliver the AFTER event>' \
  [--only b2-before-gap]      # re-record one beat; merges into timeline.json
```

### The motivation gate (checked before the diagram gate)

The FIRST narrated beat must be `kind: "motivation"` and state the problem in the
reporter's words (`../steps/1-storyboard.md` → "The motivation beat"). The capture
**exits 2**, with no waiver flag, when the beat is missing, not first, has an empty
`quote`/`narration`, or is generic — a line that never names the reported symptom, who is
affected or the impact, or that paraphrases the ticket into engineering language.

### The diagram gate

Before any browser work the capture validates the storyboard against `../diagrams.md`
and **exits 2** on any of: no diagram beat at all; a diagram beat without a `.mmd` source
or a rendered PNG; no `concept`/`architecture` beat; that beat placed after the first
filmed beat; `touchesDataModel: true` with no `erd` beat; an ERD after the first
BEFORE/AFTER beat. The message names the beat and the fix — it is a storyboard error, not
a capture retry.

`--allow-no-diagrams` waives it, **only on a human's explicit say-so**, and the PR body
must carry the reason (`VIDEO_DIAGRAMS: none — <reason>`). It always prints what it waived.

## What it does per beat

prepare (SPA `pushstate`, re-login if the login form is showing, wait for `readyText`)
→ start the 30 fps frame pump → inject a fake cursor, glide to the click target,
ripple, click → smooth-scroll the box target into view → hold → measure the box
rect → stop. `phase` hooks (`--before-cmd`/`--after-cmd`) run once when the
storyboard first enters that phase.

**Stills skip all of that.** A `source: "static"` card or a `source: "image"` diagram is
copied into `timeline.json` with `segment: null`; the image beat additionally gets the
**absolute** path in `image` after the script checks the render exists. `--only <still-id>`
re-indexes it without opening a browser. Compose draws them from the card fields or the
PNG (see `4-assemble.md`).

## Web beats (DB console, code diff, API client, mail catcher, sheets, logs)

Non-UI evidence beats are ordinary `source: "web"` beats with a real `url` — see
`../non-ui-evidence.md` for which surface to use per change class and what to narrate.
Capture specifics:

- **Start the real tools first** (`scripts/demo-tools.sh up`) and take the URLs from
  `$VIDEO_DIR/demo-tools.json`; don't hardcode a port. `demo-tools.sh require` is the gate:
  a beat that shows a custom table/HTML page or pretty-printed `curl` while the tools are
  up is a failed beat, not a shortcut.
- **Prime the tab first.** A web IDE or DB console takes 10–20 s on first load; open it,
  wait for its `readyText`, *then* run the beat so the pump does not film a spinner.
- **Cross-origin means a real `open`** and a re-login when the beat needs the app session —
  keep these beats late, or group them (`--only`) so the app beats are not disturbed.
- `readyText` must be content you have really seen there: a table name, a column name, the
  ticket id, response-body text. A wrong `readyText` costs a re-record of that beat.
- **Zoom the page** (`ctrl+=`) so code/rows are readable at 1600×900, and leave the tool's
  URL bar or title in shot so the surface is identifiable.
- Use the `--before-cmd`/`--after-cmd` hooks to flip **data/schema/API state** for these
  beats (revert or re-apply the migration, reset + reseed, run the curl that triggers the
  mail) exactly as for app beats.
- Stop any container you started for a surface (`docker stop <name>`) once the beats are
  captured; never touch the run's own dev-server/DB containers.

## Why it is built this way (the traps)

- **Never `agent-browser record`.** It re-creates the browser context; the app
  re-runs its auth check (local Gotrue `/user` can take 40–65 s) and every beat
  films `/login`. The CDP screencast (`agent-browser stream`) reads the live page.
- **Stream caps are daemon-wide and read once.** The script sets
  `AGENT_BROWSER_STREAM_MAX_WIDTH/HEIGHT` for its own calls; if the daemon was
  started without them you get e.g. `901x900` frames for a `1600x900` viewport.
  Restart the daemon with the env set and confirm `frameW == viewportW` in
  `timeline.json`.
- **`set viewport` before `stream enable`.** It emulates the viewport regardless
  of the OS window; rect coordinates are then 1:1 with the frame.
- **SPA navigation only.** `open` on the app origin may log out; cross-origin
  `pushstate` throws, so app ↔ mail-catcher switches are real `open`s followed by
  a re-login. MUI controlled inputs drop `fill` — the script uses `type`.
- **Frames arrive on change only**; the pump repeats the last frame so motion is
  smooth at 30 fps rather than stepping at the page's repaint rate.
- **The OS pointer is never in the screencast.** The injected cursor + ripple is
  what makes clicks visible.

## Checks

- [ ] `render-diagrams.mjs --check` passes (every diagram PNG exists and its `.mmd` has
      not changed since the render)
- [ ] every diagram beat is in `timeline.json` with `segment: null` and an absolute
      `image` path, in storyboard order (intro → diagrams → BEFORE → AFTER)
- [ ] every filmed beat has a non-null `rect` in `timeline.json` (null → the box
      target was off-screen: fix `readyText`/`box`, re-record with `--only`)
- [ ] `frameW/frameH == viewportW/viewportH` on every beat
- [ ] BEFORE beats really show pre-fix behaviour (open a `seg/b2-*.mp4` frame)
- [ ] every non-UI surface beat shows the object/route/email **before and after**, not one state
- [ ] every API beat is in Hoppscotch and every DB beat in CloudBeaver (not Adminer,
      not a terminal, not a custom table); spreadsheet beats are in Google Sheets or the
      run stopped to ask
- [ ] `framesPushed / (durationMs/1000) ≈ 30`

Cost: 4–5 min for 6 beats.
