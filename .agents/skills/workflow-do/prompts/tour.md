# workflow-do stage: TOUR (P7 — Screenshots + Video) — autonomous

You are a full interactive pi session launched by the `workflow-do` script as a
named zellij pane (`workflow-tour-<TICKET>`). You are **autonomous**: no human in
your pane. Blockers: `intercom({ action: "ask", to: "<chief-of-staff session from your task file>", ... })`.

**The interactive guided tour is NOT part of the build flow (decision 2026-10-08).**
It lives in review mode — the review walkthrough asks whether to run it, and the
tour procedure is in `~/.agents/skills/workflow-do-tour/SKILL.md` → "Phase 6 —
Review tour". This stage only captures the proof artifacts.

**Read order:** SHARED-POLICY.md → this file → `/tmp/workflow-task-tour.md` →
`~/.agents/skills/workflow-do-tour/SKILL.md` (**the Phase 7 knowledge — follow it exactly, every substep**).

## Ordered task list for this stage

1. **P7 — Screenshot + Annotate** (before/after pairs, annotated, uploaded to the PR as a comment) — upload via the shared helper `~/.agents/skills/workflow-do/scripts/upload-screenshot.sh` and fold old process comments with `scripts/fold-pr-body.sh` (see SKILL.md 7.6). **Every DB beat is filmed in CloudBeaver** — run `bash ~/.agents/skills/workflow-video-tour/scripts/demo-tools.sh up` first and use the preconfigured `Run DB (workflow)` connection at `$VIDEO_DIR/demo-tools.json` → `.cloudbeaver_url`. **Adminer / pgAdmin / a raw `psql` terminal are not acceptable DB surfaces (user directive 2026-10-26)** — improvising one means re-shooting every DB beat and re-uploading the PR images.
2. **P7.8 — Video tour** (`~/.agents/skills/workflow-video-tour/SKILL.md` + its `steps/1..7-*.md`, phases V1–V7): a 45–75 s narrated, annotated MP4 of the same BEFORE/AFTER story — intro card → storyboard → screencast capture → narration in an energetic Australian designed voice → assemble → animated mascot + music bed → verify → attach into the TOP of the PR body (above `## Motivation`). Runs while the app and the signed-in browser are still up. Capture with the CDP screencast (**never** `agent-browser record`: it re-creates the browser context and every app beat records a /login redirect). Default is capture; if the pipeline genuinely cannot run after repeated attempts, STOP and ask the user for help — never skip silently, never fabricate one.
3. **Loose ends**: append loose ends to `/tmp/workflow-loose-ends.md` as you go (near-miss bugs, papercuts, edge cases noticed while capturing — one entry per line: `title | why | where`); record `LOOSE_ENDS_FILE="/tmp/workflow-loose-ends.md"` in the run env on first write.

State: `/tmp/workflow-run.env` (read/source; append only). Checklist = acceptance
criteria in the brief (`BRIEF_FILE`). Dev servers + browser are already up (build
left them running); leave them up afterwards for the human.

**Chrome is script-owned:** the script launched the run Chrome on a FIXED CDP port with the org's
user-data-dir before this stage (`CHROME_LAUNCHED="1"`, `CHROME_CDP_PORT`, `CHROME_SESSION_PROFILE`
in the run env). Attach with `agent-browser --headed --session "$CHROME_SESSION" --pin-tab --profile "$CHROME_SESSION_PROFILE" --cdp "http://127.0.0.1:$CHROME_CDP_PORT" open <url>` (every value is in the run env; NEVER --auto-connect) — never launch. **Persistent tabs (SHARED-POLICY "Persistent Ticket + PR Tabs"): the `ticket` and `pr` tabs have been open since prebuild — only REFOCUS them (`ensure_tab`), never duplicate them, never close them, and do all app/screenshot work in a separate `app` tab.**
Always attach with the FULL QUADRUPLE — `XDG_DATA_HOME="$CHROME_XDG_DATA_HOME" agent-browser --headed --session "$CHROME_SESSION" --pin-tab --profile "$CHROME_SESSION_PROFILE" --cdp "http://127.0.0.1:$CHROME_CDP_PORT" <subcommand>` — never launch Chrome yourself and never omit `--profile`/`--headed`/`--cdp`: a call without them starts a NEW Chrome on a throwaway temp profile (ephemeral debug port, nothing records it), i.e. a second window on the user's desktop. ONE browser per run. If Chrome is dead, use `bash ~/.agents/skills/workflow-do/scripts/chrome.sh status` then `... chrome.sh revive` — never hand-roll a launch.

The script already ran `scripts/preflight.sh` before this stage; its verdicts are in `/tmp/workflow-preflight.env`. A FAIL there aborts the run before this pane — do not work around it.

## OUT — append to `/tmp/workflow-run.env`

```
SCREENSHOTS_ANNOTATED="1"
SCREENSHOTS_DIR="<path>"
VIDEO_PATH="<path to the attached mp4>"
VIDEO_URL="<github user-attachments URL of the video, for the P8 body template>"
VIDEO_ATTACHED="1"
VIDEO_DURATION_S="<n>"
VIDEO_NARRATION="phonon/Alfie"
VIDEO_AVATAR="mascot|pil|none"
VIDEO_MUSIC="<track|none>"
MUSIC_ATTRIBUTION=""        # only when the licence requires it
VIDEO_SKIP_NOTE=""          # set only when the human explicitly authorised skipping P7.8
STAGE_DONE="tour"
STAGE_STATUS="ok"
```

## Surrender protocol (autonomous — no user prompt)

1. Append the OUT block to `/tmp/workflow-run.env`.
2. `intercom send` the OUT handoff one-liner to the chief-of-staff session (the intercom target in your task file).
3. STOP — do NOT run `exit` or `kill $PPID` (zellij panes are not auto-closed by exiting; dead panes linger). The script verifies your handoff, closes your pane itself, and runs ship-P8 next. No closure confirmation is asked (stage-closure prompts were removed).

Do NOT finalize the PR — the script launches ship-P8.
**Do NOT run an interactive tour** — that belongs to review mode.
