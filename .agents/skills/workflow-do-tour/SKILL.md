---
name: workflow-do-tour
version: 1.4.0
description: "workflow-do sub-skill — Phase 7 (Screenshot + Annotate; Video Tour) for the build flow, plus the interactive review tour (Phase 6) used by review mode. Loaded by a workflow-do worker session the script launches as a named zellij pane (pi --name), coordinated via pi-intercom. Not invoked directly."
---

# Tour agent — workflow-do-tour (Phase 7 build capture; Phase 6 review tour)

> **`workflow-do` worker sub-skill.** You are a full pi session launched by the
`workflow-do` script as a **named zellij pane** (`pi --name workflow-tour-...`),
NOT a subagent tool call. Your launch prompt tells you which phase(s) to run
and inlines the handoff. Load this skill by reading its SKILL.md first.

**Your session name is in your launch prompt** (e.g. `workflow-p6-<TICKET>`).
Every report/question goes to the **chief-of-staff session** — the session that launched this
cage. Your task file prints its intercom target (`ORCHESTRATOR_SESSION` in the run env,
supplied by the chief of staff at kickoff). Pass `--name` once; the name persists.

## Handoff contract

> **v7 script model:** the sequencer is the deterministic script
> `~/.agents/skills/workflow-do/workflow-do.ts`. Your OUT vars are appended to
> `/tmp/workflow-run.env` (append-only) plus a `STAGE_DONE` block; your pane is
> launched and closed by the script. Read `~/.agents/skills/workflow-do/SHARED-POLICY.md`
> -> "Stage Orchestration (script model, v7)" for the full contract, and your stage
> prompt file (`~/.agents/skills/workflow-do/prompts/`) for the exact surrender steps.

**Two modes (decision 2026-10-08):**

- **Build flow — Phase 7 (autonomous).** Screenshots + annotate + video. No
  interactive tour and no human gate. This is what the `tour` stage of a build
  run does. The build flow never asks about a tour.
- **Review mode — Phase 6 (interactive).** The live guided tour, run only when
  the review walkthrough asks for it. Read-only, on any PR (ours or someone
  else's), **no screenshots, no video, no automatic posts** — a human tour is
  just a tour; if the human asks, you may add a PR comment or make a fix on the
  spot. The review verdict gate is the approval, not the tour.

**IN — variables in your `task` prompt:**
- the `workflow-do-build` OUT handoff: `TICKET_ID`, `TICKET_URL`, `FEATURE_TAG`, `PR_NUMBER`, `PR_URL`, `ORG`, `REPO_NAME`, `WORKTREE`, `BRANCH_NAME`, `INTEGRATION_BRANCH`, `WORKFLOW_VIEWPORT_W`, `WORKFLOW_VIEWPORT_H`, `SCREENSHOTS_DIR`, `DB_URL`, running dev-server state, the **5-element brief** + acceptance criteria (your tour checklist)

**OUT — your final message (handoff back to the chief-of-staff session):**
- **build mode:** before/after screenshot pairs captured, annotated, uploaded to the PR (PR comment with annotated images); narrated video tour attached to the PR body; ticket + PR left open; dev servers + browser left up for the human
- **review mode:** the tour was walked live with the human; no artifacts produced and nothing posted unless the human asked on the spot

## Operating rules

- **Read the shared policy first:** `~/.agents/skills/workflow-do/SHARED-POLICY.md` (see its FIRST ACTION note). Do this before any phase task.
- Run the phases for YOUR mode. **Build run:** Phase 7 only, in order (P7.8 video runs inside P7, after 7.7, before the P7 completion print — see `~/.agents/skills/workflow-video-tour/SKILL.md`). **Review run:** Phase 6 only, read-only, and only when the review walkthrough asked for a tour. Never run the interactive tour in a build run.
- **Task tracking:** `TaskList`, then `TaskCreate` for the substeps of your mode only (`P6.*` in review mode, `P7.*` in build mode); mark `in_progress`/`completed` as you go. Prefix every sub-step `TaskCreate` subject with the phase emoji (🔐 P0, 🔍 P1, ❓ P2, 📦 P3, 💻 P4, 🧪 P5, 📸 P6, 🖥️ P7, 🚀 P8, ⏳ P9, ✅ P10, 📡 P11, 🔄 P12, 📧 P13) — emojis no longer go in zellij tab names; they live on the pi-task subjects.
- Rename your zellij tab at each transition: `workflow_rename_tab "${TICKET_ID}: P<n>.<sub> <Verb> ${FEATURE_TAG}"`.
- The tour is **proof**, not a demo: show BEFORE (broken/old) vs AFTER (fixed/new) for each criterion. Leave the browser open after the tour. (Build mode proves it through the P7 screenshots + video; review mode proves it live.)
- **Build mode:** do NOT skip screenshots (P7). If the local stack cannot be brought up after genuine retries, STOP and ask the user for help — never skip silently.
- When P6–P7 are done, return your **OUT** handoff summary. Do NOT finalize the PR — the script spawns `workflow-do-ship` (P8) next, then runs the P9-lite review handoff; review fixes + merge happen in iterate mode (same skill).

## Shared policy

**FIRST ACTION before any phase work:** read
`~/.agents/skills/workflow-do/SHARED-POLICY.md` and follow it for the entire run
(Hard Prerequisites, DB-First Thinking Order, implementation style pointers,
Zellij tab naming, pane management). It applies to every workflow-do worker —
this file no longer duplicates it.
## Your phases

## Phase 6 — Review tour (review mode only — NEVER run this in a build run)

**→ TaskUpdate: P6 → in_progress**

```bash
workflow_rename_tab "${TICKET_ID}: P6.1 Tour ${FEATURE_TAG}"
```

The tour happens live with the human in review mode. It is **read-only** and produces no artifacts: walk the change in the headed browser and let the human judge it. Boot the PR's dev stack first if it is not already running. If the human asks for a comment or an on-the-spot fix, do that; otherwise post nothing. There is **no local-approval gate** — the review verdict is where the human approves.

**The point of this tour is proof.** The human watching should understand:
- For **bugs**: this was broken before (shown in BEFORE screenshots) and is now fixed (shown live + AFTER screenshots)
- For **features**: this didn't exist before (BEFORE screenshots) and now works better (live + AFTER screenshots)

The live browser demonstration forms the proof. Screenshots are captured afterward in Phase 7 to document what was proven here.

### 6.1 Narrated Tour of Each Criterion

**→ TaskUpdate: P6.1 → in_progress**

Use `agent-browser` to drive the per-run Chrome. The human MUST see the browser window throughout the tour.

**Chrome is script-owned:** the workflow-do script launched the run Chrome on a FIXED CDP port
before this stage and recorded it (`CHROME_LAUNCHED="1"`, `CHROME_CDP_PORT`, `CHROME_SESSION_PROFILE`
in the run env). **Never launch Chrome yourself** — not with `agent-browser` and not with
`google-chrome --remote-debugging-port=0`. Attach with the full quadruple, reading every value from
the run env:

```bash
agent-browser --headed --profile "$CHROME_SESSION_PROFILE" --session "$CHROME_SESSION" --pin-tab \
  --cdp "http://127.0.0.1:$CHROME_CDP_PORT" open <url>
```

If Chrome is NOT live, use the script's own idempotent recipe — do not hand-roll one:

```bash
bash ~/.agents/skills/workflow-do/scripts/chrome.sh status   # is it down? on which port?
bash ~/.agents/skills/workflow-do/scripts/chrome.sh revive   # one relaunch, same profile, records the port
```

Then re-run the attach above. The script also probes + revives once before every browser-using
stage, and it runs `scripts/preflight.sh` before the tour (dashboard env keys, AWS SSO, GitHub API +
browser login, dashboard JWT) — a preflight FAIL means the tour never starts.

For each acceptance criterion, follow this loop:

**1. Announce** what you're about to show and why it matters:
```
→ Print: "👀 TOUR STEP <N>: <criterion>"
→ Print: "Context: <what this does, what problem it solves>"
→ Print: "Before: <old behavior / broken> → After: <new behavior / fixed>"
→ Print: "Show the BEFORE state live by temporarily reverting the fix or switching to the integration branch, then show the AFTER state with the fix applied."
→ Print: "Navigating to <route>... Watch the browser."
```

**2. Navigate and interact**, explaining each action:
```bash
agent-browser --headed --profile "$CHROME_SESSION_PROFILE" --session "$CHROME_SESSION" --pin-tab --cdp "http://127.0.0.1:$CHROME_CDP_PORT" open "http://localhost:<port>/<route>"
agent-browser wait --load networkidle
agent-browser wait 2000
agent-browser snapshot -i
agent-browser click @<ref>  # or navigate, fill form, etc.
agent-browser wait 1000
agent-browser snapshot -i
```
```
→ Print: "Now you should see <specific expected result>."
→ Print: "Notice: <detail 1>, <detail 2>, <detail 3>"
→ Print: "The difference between BEFORE and AFTER should be clear from the live demonstration."
```

**3. Ask for confirmation:**
```
→ Print: "❓ Can you see this working correctly? Say 'yes'/'next' to continue, or describe what's wrong."
```

**4. Wait for human response.** If confirmed → move to next criterion. If the human reports an issue: note it, fix in-session (if quick) or record as a finding, re-demonstrate after fixing. If the fix changes the behavior, re-demonstrate after fixing.

**⚠️ Which gates are HUMAN.** In review mode the per-criterion question ("can you see
this working?") is an interaction with the human, not an approval gate — there is **no
tour approval**. The one gate that must ALWAYS be answered by a human is **P9 (the merge
gate)**; the review verdict is where the human approves the change. If you are parked in
an `ask_user_question` while the supervisor needs to hand you a decision it injects Esc
(`zellij --session <s> action write -p <pane-id> 27`) to release the prompt, then
intercom-sends the decision; re-present your gate if the Esc cancelled it, and never
treat an Esc as an answer.

#### Tour Coverage (what to walk through)

1. **Happy path** — feature working end-to-end
2. **Data verification** — data correctly displayed/saved (check values match DB)
3. **Form interactions** — fill, submit, show result
4. **Edge cases** — empty states, error handling, boundary values
5. **RBAC** — different auth levels if applicable
6. **Before/after contrast** — reference the BEFORE screenshots on the PR and show the AFTER live
7. **Responsive/layout** — if UI changed, renders correctly
8. **External-API semantics** — if the build stage flagged a branch whose
   behavior depends on real provider rules (Stripe attach/detach, webhooks,
   OAuth), do NOT accept mocked unit tests as proof: exercise that branch live
   against the provider's test/sandbox mode during the tour. Real example: the re-attach branch passed 10 mocked unit tests, but live
   test-mode Stripe rejected `paymentMethods.attach` on a PM already attached
   to another customer — the tour caught it and the fix was redesigned in-session.

**Leave the browser open after the tour** so the human can interact with it themselves.

**→ TaskUpdate: P6.1 → completed**

### 6.2 Tour summary (no approval gate — review mode)

**→ TaskUpdate: P6.2 → in_progress**

After walking the change live with the human, print a short summary of what was
shown. There is **no approval gate** — the human judges at the review verdict.

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  🎬 REVIEW TOUR — <pr> <title>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Walked: <what was demonstrated>
  Browser: http://localhost:<port>/<route>  (still open)
  📋 PR: <PR URL>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

- If the human asks for a PR comment or an on-the-spot fix, do that. Otherwise post nothing.
- If the human wants to see something again, re-demonstrate it.
- Record `REVIEW_TOUR_DONE="1"` in the run env.

**→ TaskUpdate: P6.2 → completed**
**→ TaskUpdate: P6 → completed. Print: "✅ Review tour complete — no artifacts, nothing posted unless asked. Proceeding to the verdict."**


---


## Phase 7 — Screenshot + Annotate (📸)

**⚠️ HARD GATE: This phase CANNOT be skipped.** Every acceptance criterion MUST be demonstrated with before/after screenshots, captured, annotated, and uploaded to the PR. Do not skip because the change is "trivial" or "a one-liner". The default is always: capture screenshots.

**⚠️ NEVER skip autonomously.** If no display/browser is available, find a way to get screenshots (install Xvfb, use X11 forwarding, ask the user to restart the cage with a display).

**Infra-unavailable = STOP and ask for help (decision 2026-10-08).** If the local stack (dev servers / DB / browser) cannot be brought up after genuine repeated attempts (e.g. cage was lost, DinD won't start, browser dead), **STOP the run and ask the user for help** — state exactly what is broken and what you tried. Do **NOT** offer a silent "skip the tour/screenshots" escape: a full run whose infra is broken needs a human, not a skipped deliverable. If the human explicitly authorizes skipping in that conversation, record it in `TOUR_SKIP_NOTE`; never skip without that explicit decision. Never fabricate screenshots to fill the gap.

**The goal of this phase is proof.** The screenshots must prove to anyone looking at the PR that the ticket's problem is solved:
- For **bugs**: show the broken behavior (BEFORE) and the fixed behavior (AFTER)
- For **features**: show the state before the feature existed and the improved state after

A reviewer who has never seen the codebase should be able to look at the before/after screenshots and understand exactly what changed and why it matters.

**Do NOT ask for human approval during screenshot capture — it is autonomous.** Capture all screenshots, annotate them, upload them to the PR, then open the ticket and PR in browser tabs. In build mode there is no interactive tour; take the pass/fail context from the brief's acceptance criteria.

**→ TaskUpdate: P7 → in_progress**
**→ Print: "Phase 6: Planning and capturing before/after screenshots..."**
```bash
workflow_rename_tab "${TICKET_ID}: P7.1 Screenshot ${FEATURE_TAG}"
```

### ⚠️ Screenshot Execution Checklist (authoritative spec — self-audit before uploading)

Before uploading any screenshots, verify ALL of the following. If ANY item is missing, go back and complete it:

1. **Browser was visible** — screenshots taken in the per-run headed Chrome (`agent-browser`), not headless or the user's daily Chrome.
2. **Screenshots were planned first** — you wrote a screenshot plan (see 6.1) before capturing anything.
3. **Before/after contrast demonstrated** — for each criterion that changes behavior, you captured BEFORE (broken/old) and AFTER (fixed/new) screenshots with separate annotated images. BEFORE screenshots were taken with the fix temporarily reverted (or on the integration branch); AFTER screenshots with the fix applied.
4. **Screenshot taken for each criterion** — one before + one after per acceptance criterion, saved to `$SCREENSHOTS_DIR`.
5. **Region of interest is on screen** — before taking any screenshot, **scroll the element into view** with `agent-browser scrollintoview "<selector>"` or `agent-browser scroll down <px>`. The annotated red box must be visible in the screenshot.
6. **Each screenshot is annotated** — the annotation is drawn IN THE PAGE (`__wfAnnot`, see P7.4) so it is part of the capture itself; a red box marks the key UI element and a short caption. Capture through `scripts/annotate-shot.sh` (it records the evidence); there is no post-capture annotation and no ImageMagick fallback.
7. **DB verification included** — for each step that changes data, verified DB state matches the UI (ran a `SELECT` and reported the result in the screenshot caption or PR comment).
8. **Refresh/persistence test** — after the final action, refreshed the page and took a screenshot proving state persisted.
9. **Not lazy, not overly verbose** — enough screenshots to see exactly what's happening, no more. One before+after pair per criterion is the baseline; add edge-case screenshots only when they add meaningful proof.
10. **PR comment uses annotated images only, and the gate passed** — `check-annotations.sh "$SCREENSHOTS_DIR"` exits 0 for every `*-annotated.png`. A file with no in-page overlay evidence is recaptured (P7.5), never painted and never uploaded as annotated.

### 7.1 Plan the Screenshots

**→ TaskUpdate: P7.1 → in_progress**

Before capturing anything, write a screenshot plan in chat. The plan identifies:

1. **Each acceptance criterion** from the ticket and what it looks like in the UI
2. **For each criterion: what the BEFORE screenshot shows** (broken behavior for bugs, or absence of feature for new features)
3. **For each criterion: what the AFTER screenshot shows** (fixed behavior / feature working)
4. **What DB state / data is needed** to make the effect obvious (seed data, specific records, edge-case rows)
5. **What steps are needed between BEFORE and AFTER** (revert the fix, capture, reapply the fix, capture — or switch branches, or seed data)
6. **The route / URL** for each screenshot
7. **The key element** to annotate (the button, the error message, the list item, etc.)
8. **Any non-UI change** (migration/schema, RLS or policy, backend route/permission/
   middleware/job, email, export, logs) — capture it on the surface that makes it visible
   and not as an app screenshot: DB console with the same object BEFORE↔AFTER, the
   VS Code web diff or PR *Files changed* for backend code, Hoppscotch or the API's
   OpenAPI UI for payloads and the denial case, Mailpit for mail, a log/metrics board for
   jobs. Change class → surface, tool recipes (CloudBeaver/psql, Hoppscotch, Mailpit,
   github.dev) and what a backend shot must show are in
   `~/.agents/skills/workflow-video-tour/non-ui-evidence.md` — the video (P7.8) uses the
   same surfaces, so keep the two stories identical. **Never shoot a DB schema screenshot
   through Supabase Studio / the Supabase-local stack** (user directive 2026-10-16): use a
   neutral console (CloudBeaver, psql, DBeaver) against the same Postgres URL instead.

Capture screenshots for these the same way as app shots (real browser, annotated overlay,
uploaded to the PR), and stop any container you started for a surface when done.

Print the plan:
```
→ Print: "📋 SCREENSHOT PLAN for <ticket-id>"
→ Print: "Criterion 1: <description>"
→ Print: "  BEFORE: <route> — show <broken/old behavior>. Key element: <selector>."
→ Print: "  AFTER:  <route> — show <fixed/new behavior>. Key element: <selector>."
→ Print: "  DB setup: <what data needs to exist>"
→ Print: "Criterion 2: ..."
→ Print: "Total: <N> before/after pairs = <2N> screenshots"
```

**→ TaskUpdate: P7.1 → completed**

### 7.2 Ensure Everything is Running + Sample Data

**→ TaskUpdate: P7.2 → in_progress**

Before starting, verify all services are live and healthy **inside the container**:

```bash
# Verify DB is running and has data (inside the container)
psql "$DB_URL" -c "SELECT 1" 2>/dev/null || echo "WARN: DB not responding"

# Verify backend is responding (inside the container)
curl -sf http://localhost:<backend-port>/health 2>/dev/null || echo "WARN: Backend not responding"

# Verify frontend is serving (inside the container)
curl -sf http://localhost:<frontend-port> 2>/dev/null || echo "WARN: Frontend not responding"
```

If any service is down, **restart it** before continuing.

Verify the database has sufficient sample data to make the feature's effect **obvious** in the screenshots:

- If the feature adds a list/table: ensure 5-10+ rows exist with varied data
- If the feature adds filtering: ensure data spans multiple filter categories
- If the feature adds a form: ensure there's data to edit AND space to create new
- If the feature changes permissions: ensure users with different roles exist
- If the feature handles edge cases: ensure empty states, boundary values, and error conditions are represented

If data is insufficient, seed more now. This is part of the plan from 6.1.

**Login for local dev services:** When the browser navigates to the frontend (localhost) for screenshots, if a login screen appears, handle it per the **Browser Login Handling** policy — find credentials in `.env.local` / seed scripts / DB, or create a test user. Auto-fill and proceed without asking the user. Navigate to the relevant page and verify the app is showing the expected data before capturing screenshots.

Set the viewport:
```bash
agent-browser set viewport $WORKFLOW_VIEWPORT_W $WORKFLOW_VIEWPORT_H
```

Ensure Chrome is maximized on a horizontal monitor for consistent screenshot framing:
```bash
if [ -n "$NIRI_SOCKET" ]; then
  niri msg action focus-window --app-id google-chrome 2>/dev/null
  sleep 0.3
  # Move to landscape monitor if not already there
  if [ -n "$MON_NAME" ]; then
    niri msg action move-window-to-output "$MON_NAME" 2>/dev/null
    sleep 0.3
  fi
  niri msg action maximize-window 2>/dev/null
  sleep 0.3
  echo "🖥️ Chrome maximized on landscape monitor for screenshots"
fi
```

**→ TaskUpdate: P7.2 → completed**

### 7.3 Capture BEFORE Screenshots (Broken / Old Behavior)

**→ TaskUpdate: P7.3 → in_progress**

To capture the BEFORE state, you need the code WITHOUT the fix. There are two approaches depending on the change:

**Approach A — Revert the fix temporarily (for bug fixes):**
```bash
cd "$WORKTREE"
# Stash or revert the fix to see broken behavior
git stash  # or: git revert --no-commit HEAD if multiple commits
# Restart the dev server if needed (it may hot-reload, or may need manual restart)
```

**Approach B — Switch to the integration branch (for new features):**
```bash
cd "$WORKTREE"
git checkout origin/$INTEGRATION_BRANCH -- .  # or checkout the integration branch in a temp worktree
# Restart dev server
```

**Approach C — Use a separate worktree on the integration branch:**
```bash
BEFORE_WORKTREE="$WT_BASE/$BRANCH_NAME-before"
git -C "$SOURCE_REPO" worktree add "$BEFORE_WORKTREE" "origin/$INTEGRATION_BRANCH"
cd "$BEFORE_WORKTREE"
# Install deps, start dev server, seed data
```

For each acceptance criterion, capture the BEFORE screenshot:

```bash
agent-browser --headed --profile "$CHROME_SESSION_PROFILE" --session "$CHROME_SESSION" --pin-tab --cdp "http://127.0.0.1:$CHROME_CDP_PORT" open "http://localhost:<port>/<route>"
agent-browser wait --load networkidle
agent-browser wait 2000

# Scroll the key element into view
agent-browser scrollintoview "<selector>"

# Take the BEFORE screenshot — annotate IN PAGE first (user directive 2026-10-01, restated
# 2026-10-19): the overlay is drawn in the DOM, so the screenshot AND the video capture
# contain it, and it follows the page on scroll/resize. There is NO post-processing step
# and NO ImageMagick fallback: annotate-shot.sh injects the layer, proves it mounted, draws
# the marks, screenshots, and records the evidence in $SCREENSHOTS_DIR/annotations.json.
# If it fails, the annotation gate fails — never paint the PNG.
AB="agent-browser --headed --session $CHROME_SESSION --pin-tab --profile $CHROME_SESSION_PROFILE --cdp http://127.0.0.1:$CHROME_CDP_PORT"
bash ~/.agents/skills/workflow-do/scripts/annotate-shot.sh \
  --out "$SCREENSHOTS_DIR/<NN>-before-<description>-annotated.png" \
  --box '<selector>' --label "BEFORE: <what's broken/missing>" --color before \
  --banner before
# optional pointer / second target:  --arrow 'body,<selector>'  (or a second --box)
# optional exact frame:              --url "http://localhost:<port>/<route>"
```

If DB state needs to be set up to demonstrate the bug (e.g. a specific record that triggers the bug), do that BEFORE navigating to the page. Run the SQL, verify it's in the DB, then navigate and capture.

**⚠️ Never verify screenshots with model vision.** Do not attempt to read/inspect the captured PNG images yourself — many models have no image input, and a vision-less attempt produces garbage confidence. Verify placement through the browser instead: `agent-browser eval` bounding-box geometry (as above), snapshot refs, or element visibility checks. The human confirms visuals during the tour. (Learned 2026-09-14: user correction "no images vision for this model plz".)

**Restore the fix after capturing all BEFORE screenshots:**
```bash
cd "$WORKTREE"
git stash pop  # or: git checkout -- .  (undo the revert)
# Restart dev server to pick up the fix
```

If you used Approach C, kill the BEFORE worktree's dev server and clean up:
```bash
git -C "$SOURCE_REPO" worktree remove "$BEFORE_WORKTREE" --force
```

**→ TaskUpdate: P7.3 → completed**

### 7.4 Capture AFTER Screenshots (Fixed / New Behavior)

**→ TaskUpdate: P7.4 → in_progress**

Now with the fix applied and dev server running the latest code, capture the AFTER screenshots. For each acceptance criterion, follow the same route and interaction as the BEFORE screenshot:

```bash
agent-browser --headed --profile "$CHROME_SESSION_PROFILE" --session "$CHROME_SESSION" --pin-tab --cdp "http://127.0.0.1:$CHROME_CDP_PORT" open "http://localhost:<port>/<route>"
agent-browser wait --load networkidle
agent-browser wait 2000

# Scroll the key element into view
agent-browser scrollintoview "<selector>"

# Take the AFTER screenshot — same in-page layer: clear the BEFORE marks, then draw the AFTER ones
AB="agent-browser --headed --session $CHROME_SESSION --pin-tab --profile $CHROME_SESSION_PROFILE --cdp http://127.0.0.1:$CHROME_CDP_PORT"
bash ~/.agents/skills/workflow-do/scripts/annotate-shot.sh \
  --out "$SCREENSHOTS_DIR/<NN>-after-<description>-annotated.png" \
  --clear --box '<selector>' --label "AFTER: <what's fixed/improved>" --color after \
  --banner after
# Leave nothing behind on the run's page once the tour is over:
$AB eval "__wfAnnot.unmount()"
```

For each AFTER screenshot that changes data, verify the DB matches the UI:
```bash
psql "$DB_URL" -c "SELECT * FROM <table> WHERE <condition>"
# Report the result in the PR comment alongside the screenshot
```

After the final action, refresh the page and capture a persistence proof screenshot:
```bash
agent-browser reload
agent-browser wait 2000
agent-browser screenshot "$SCREENSHOTS_DIR/<NN>-persist-<description>.png"
```

**→ TaskUpdate: P7.4 → completed**

### 7.5 Annotate Remaining Screenshots

**→ TaskUpdate: P7.5 → in_progress**

If any screenshots were not annotated during capture (edge-case screenshots, persistence screenshots), annotate them now by **re-opening the page and capturing again** with `annotate-shot.sh` — the overlay has to be in the DOM at capture time. There is nothing to "fix up" afterwards: a captured PNG cannot be annotated retroactively, and painting boxes onto it with ImageMagick is forbidden (it is a different artefact from the in-page overlay, cannot be checked against the element, and disagrees with the video).

```bash
bash ~/.agents/skills/workflow-do/scripts/annotate-shot.sh \
  --url "http://localhost:<port>/<route>" \
  --out "$SCREENSHOTS_DIR/<NN>-<kind>-<desc>-annotated.png" \
  --box '<selector>' --label "<BEFORE|AFTER>: <text>" --color before --banner before
```

Palette everywhere: before `#EF4444`, after `#22C55E`, accent `#38BDF8`. Every screenshot referenced in the PR comment MUST have an `-annotated.png` counterpart — and that file must pass the gate:

```bash
bash ~/.agents/skills/workflow-do/scripts/check-annotations.sh "$SCREENSHOTS_DIR"
# exit 0 only when every *-annotated.png carries evidence that the in-page overlay was
# mounted for THAT capture and drew at least one mark (sha256-matched).
```

**The gate is not advisory.** A PNG with no evidence entry, a stale entry (the file changed after capture), `marks: 0`, or an overlay that never mounted (`styleApplied: false`) is rejected — upload nothing it rejects. If the page refuses injected styles, say so in the handoff and report the missing screenshots; do not substitute painted images.

**→ TaskUpdate: P7.5 → completed**

### 7.6 Upload Screenshots to PR

**→ TaskUpdate: P7.6 → in_progress**

Upload ALL annotated screenshots **into the PR body** (never as a comment — a PR has ONE description; screenshots, summary and review outcome all live there). **Delete any previous screenshot/tour comments first** — process noise; their content moves to the body — via the shared helper:

```bash
# Folds any process comments (Screenshot|Guided Tour|Implementation summary|review)
# into the PR body and deletes them:
bash ~/.agents/skills/workflow-do/scripts/fold-pr-body.sh "$GH_REPO" "$PR_NUMBER"

# Annotation gate BEFORE upload: every *-annotated.png must carry in-page overlay evidence.
# A file that fails here is recaptured (P7.5), never uploaded and never painted.
bash ~/.agents/skills/workflow-do/scripts/check-annotations.sh "$SCREENSHOTS_DIR" \
  || { echo "annotation gate failed — recapture the listed screenshots; do not upload them"; exit 1; }

# Then upload each annotated screenshot and APPEND a screenshots section to the PR body
SCREENSHOT_COMMENT="\n## 📸 Screenshots\n\n"

STEP=0
for img in "$SCREENSHOTS_DIR"/*-annotated.png; do
  [ -f "$img" ] || continue
  STEP=$((STEP+1))
  BASENAME=$(basename "$img")
  DESC=$(echo "$BASENAME" | sed 's/^[0-9]*-//' | sed 's/-annotated\.png$//' | tr '-' ' ')
  IMG_URL=$(bash ~/.agents/skills/workflow-do/scripts/upload-screenshot.sh "$GH_REPO" "$PR_NUMBER" "$img")
  SCREENSHOT_COMMENT+="**Step $STEP — ${DESC}**\n![${BASENAME}](${IMG_URL})\n\n"
done
echo -e "$SCREENSHOT_COMMENT" >> /tmp/pr-body.md
cmp -s <(gh pr view "$PR_NUMBER" --repo "$GH_REPO" --json body -q .body) /tmp/pr-body.md || \
  gh pr edit "$PR_NUMBER" --repo "$GH_REPO" --body-file /tmp/pr-body.md
```

**ONE-DESCRIPTION RULE:** the PR body is the single description of the final state. Screenshots, implementation summary, test instructions and review outcomes all belong there — never as separate process comments. Reviewer discussion stays in comments; process artifacts do not.

**How uploads work** — GitHub's API cannot upload `user-attachments` images; the shared helper (`scripts/upload-screenshot.sh`, extracted from this phase in v8) drives the cage Chrome the regular agent-browser way: it opens the PR comment form, hands the file to GitHub's `file-attachment` element via `DataTransfer`, and polls the textarea for the permanent `user-attachments/assets` URL. It requires the logged-in cage Chrome (P1.3b verified) — attach with `agent-browser --headed --profile "$CHROME_SESSION_PROFILE" --session "$CHROME_SESSION" --pin-tab --cdp "http://127.0.0.1:$CHROME_CDP_PORT" open <url>`, never `--auto-connect` and never launch Chrome yourself.

**→ TaskUpdate: P7.6 → completed**

### 7.7 Open Ticket + PR in Browser Tabs

**→ TaskUpdate: P7.7 → in_progress**

The ticket and PR tabs have been open since prebuild (SHARED-POLICY "Persistent
Ticket + PR Tabs") — REFOCUS them, never open duplicates and never close them.
Scratch work (the app under test, uploads, extra pages) happens in its own tab:

```bash
# the two permanent tabs — refocus by label (fall back to URL → t-number)
ensure_tab ticket "$TICKET_URL"
ensure_tab pr "$PR_URL"
# scratch tab for the app under test / screenshots
ensure_tab app "http://localhost:<port>/<route>"
```

Leave the app tab open as well. The human ends up with: the app (live), the PR
(screenshots) and the ticket (context) — and the ticket/PR tabs were never
reused or closed by the tour.

**→ TaskUpdate: P7.7 → completed**

### 7.8 Video tour (🎬)

**→ TaskUpdate: P7.8 → in_progress**

The screenshots prove the fix in stills; the video proves it in motion. It is
produced **now**, while the app, the DB and the signed-in browser are still up.

**Read `~/.agents/skills/workflow-video-tour/SKILL.md` and work its steps
V1–V7 in order** (`steps/1-storyboard.md` … `steps/7-verify-attach.md`, each
loaded right before you run it). That skill owns everything: the storyboard, the
screencast capture of the live page, the designed-voice narration, the intro card +
annotated assembly, the animated mascot, the music bed, verification and the attach
into the **top of the PR body** (above `## Motivation`).

```bash
S=~/.agents/skills/workflow-video-tour
mkdir -p "$WORKTREE/.workflow-video"      # NEVER /tmp: a tmp-cleaner wiped a whole run mid-flight
VIDEO_DIR="$WORKTREE/.workflow-video"; export VIDEO_DIR
```

**Policy.** Default is capture. If the video pipeline genuinely cannot run after
repeated attempts, **STOP and ask the user for help** (same rule as the P7 infra
rule above) — do not silently skip and do not fabricate one. `VIDEO_SKIP_NOTE` is
recorded only when the human explicitly authorizes a skip in that conversation.

**Do not attach an unverified video**, and do not hand-write the ffmpeg — every
command lives in the sub-skill's steps.

**→ TaskUpdate: P7.8 → completed**
**→ TaskUpdate: P7 → completed. Print: "✅ Phase 7 complete. <N> before/after screenshot pairs captured, annotated, uploaded to PR; video tour <attached|skipped>. Ticket + PR opened in browser. Proceeding to Phase 8 for PR finalization."**

---


