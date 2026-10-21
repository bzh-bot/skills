---
name: workflow-do-post
version: 1.6.1
description: "workflow-do sub-skill — phases P11–P13 (Post-merge monitoring + notification; post-run skill improvement; email summary) + final worktree cleanup. Loaded by a workflow-do worker session the script launches as a named zellij pane (pi --name), coordinated via pi-intercom. Not invoked directly."
---

# Post-merge agent — workflow-do-post (Phases P11–P13)

> **`workflow-do` worker sub-skill.** You are a full pi session launched by the
`workflow-do` script as a **named zellij pane** (`pi --name workflow-post-...`),
NOT a subagent tool call. Your launch prompt tells you which phase(s) to run
and inlines the handoff. Load this skill by reading its SKILL.md first.

**Your session name is in your launch prompt** (e.g. `workflow-p11-<TICKET>`).
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

You are **autonomous**: no human in your pane. Run to completion, then send your OUT handoff to the chief-of-staff session via `intercom send` (target: the intercom target in your task file / `ORCHESTRATOR_SESSION` in the run env). You also perform the **final worktree cleanup** (deferred from P10.4) after the email is sent, so the Phase 13 email can still embed `$WORKTREE/screenshots/`.

**IN — variables in your `task` prompt:**
- the `workflow-do-ship` OUT handoff: `TICKET_ID`, `TICKET_URL`, `TICKET_TITLE`, `FEATURE_TAG`, `PR_URL`, `PR_NUMBER`, `ORG`, `REPO_NAME`, `WORKTREE`, `BRANCH_NAME`, `SOURCE_REPO`, `INTEGRATION_BRANCH`, detected deployment flags (`HAS_VERCEL`, `HAS_GH_ACTIONS`, `HAS_CIRCLECI`, `HAS_DATADOG`, `HAS_SUPABASE`), the brief + the Phase 5.7 summary + tour results + screenshot paths/URLs

**OUT — your final message (handoff back to the chief-of-staff session):**
- deployment monitored + reported (healthy / watching / failed); rollback decision surfaced if needed
- dev-server/DB background tasks stopped (`bg_kill`); no leftover panes (pane lifecycle is script-owned); task list verified clean
- (P12) ALL the run's sessions scanned for friction/corrections — every named `workflow-*` session for the ticket (supervisor, stage panes, earlier iterate rounds), not just the current one; friction is **recorded** for the periodic bulk friction scan. Per-ticket skill edits were removed — do not ask about incorporating learnings and do not edit any skill file during a run.
- (P13) HTML email summary sent via `msmtp` to `$NOTIFY_EMAIL` — NEVER skipped: if msmtp or ~/.msmtprc is unconfigured, set it up per §13.2 before sending
- **final cleanup:** `git worktree remove "$WORKTREE" --force`, `git branch -D "$BRANCH_NAME"`, `git worktree prune` (only AFTER the email sends, so screenshots survive)

## Operating rules

- **Read the shared policy first:** `~/.agents/skills/workflow-do/SHARED-POLICY.md` (see its FIRST ACTION note). Do this before any phase task.
- Run phases P11 → P12 → P13 in order, then final cleanup.
- **Task tracking:** `TaskList`, then `TaskCreate` for only `P11.*`, `P12.*`, `P13.*` substeps; mark `in_progress`/`completed` as you go. Prefix every sub-step `TaskCreate` subject with the phase emoji (🔐 P0, 🔍 P1, ❓ P2, 📦 P3, 💻 P4, 🧪 P5, 📸 P6, 🖥️ P7, 🚀 P8, ⏳ P9, ✅ P10, 📡 P11, 🔄 P12, 📧 P13) — emojis no longer go in zellij tab names; they live on the pi-task subjects.
- Rename your zellij tab at each transition: `workflow_rename_tab "${TICKET_ID}: P<n> <Verb> ${FEATURE_TAG}"`.
- Access verification (P0) was already completed by `workflow-do-prebuild`; do not re-run it.
- **No human in your pane.** P12 records friction only: there is no "incorporate learnings?" ask and no skill editing during a run (per-ticket skill improvement was removed; a periodic bulk friction scan covers it).
- **P12.4 removed:** skill edits are not made during a run — the periodic bulk friction scan owns them.
- **Cleanup ordering is critical:** email (P13) BEFORE worktree removal, because the email embeds `$WORKTREE/screenshots/*-annotated.png` as inline base64. GitHub user-attachment URLs are auth-gated (404 via curl), so once the worktree is gone the images can't be re-fetched.
- When done, return your **OUT** handoff summary. This is the last group — the run is complete.

## Shared policy

**FIRST ACTION before any phase work:** read
`~/.agents/skills/workflow-do/SHARED-POLICY.md` and follow it for the entire run
(Hard Prerequisites, DB-First Thinking Order, implementation style pointers,
Zellij tab naming, pane management). It applies to every workflow-do worker —
this file no longer duplicates it.
## Your phases

## Phase 11 — Post-Merge Monitoring & Notification

**→ TaskUpdate: P11 → in_progress**

**→ Print: "Phase 11: Monitoring deployment and notifying team..."**

```bash
workflow_rename_tab "${TICKET_ID}: P11 Watch ${FEATURE_TAG}"
```

### 11.1 Monitor Deployment

**→ TaskUpdate: P11.1 → in_progress**

Define the repo slug first — the GitHub org slug is `GITHUB_ORG`, NOT `ORG`
(the org KEY, which is only correct for worktree paths):

```bash
export GH_REPO="${GITHUB_ORG:-$ORG}/$REPO_NAME"   # never use "$ORG/$REPO_NAME" in a gh call — it 404s
```

Watch the appropriate deployment/build pipeline for errors. Check based on what was detected in Phase 1.7:

**Vercel** (if HAS_VERCEL):

```bash
# Check Vercel deployment status via GitHub deployment status
gh api repos/$GH_REPO/deployments --jq '.[0] | {state: .state, environment: .environment, url: .url}'
```

**GitHub Actions** (if HAS_GH_ACTIONS):

```bash
# Watch the workflow run triggered by the merge
gh run list --branch "$INTEGRATION_BRANCH" --limit 3
gh run view <run-id> --log-failed 2>/dev/null
```

**CircleCI** (if HAS_CIRCLECI):

```bash
# Check recent pipeline status — use circleci skill if available
# Otherwise check via GitHub commit status
gh api repos/$GH_REPO/commits/$INTEGRATION_BRANCH/status --jq '.statuses[] | {context, state, target_url}'
```

**⚠️ gh log retrieval — cache permission denied:** on some machines
`gh run view <run-id> --log-failed` fails with
`creating cache entry: open /home/<user>/.cache/gh/run-log-*.zip: permission denied`.
Workaround: run the command with `XDG_CACHE_HOME=/tmp/gh-cache`:

```bash
XDG_CACHE_HOME=/tmp/gh-cache gh run view <run-id> --log-failed
```

**Supabase** (if HAS_SUPABASE):

- Check if migrations ran successfully on the target environment
- Verify edge functions deployed if applicable

**Datadog** (if HAS_DATADOG):

- Check for error spikes in the service after deploy
- Verify no new error patterns in logs

**→ TaskUpdate: P11.1 → completed**

### 11.2 Rollback Plan

**→ TaskUpdate: P11.2 → in_progress**

If deployment fails or errors are detected:

**Transient infra failure? Re-run first, don't loop.** If the failure is from
transient infrastructure (502/503 from a registry or CI provider) while tests
were green (e.g. `docker push` to the org's container registry returning 502/503), the
standard first remediation is to re-run the failed workflow, not to revert:

```bash
gh run rerun <run-id> --failed
```

If the re-run fails again, **report back (intercom-ask the chief of staff) rather
than looping** — record `DEPLOYMENT_STATUS="failed"` with the error excerpt and
note that the workflow should be retried manually once the infra recovers.

For non-transient errors:

```bash
# Create a revert commit
git -C "$SOURCE_REPO" fetch origin
git -C "$SOURCE_REPO" checkout "$INTEGRATION_BRANCH"
git -C "$SOURCE_REPO" pull
MERGE_SHA=$(git -C "$SOURCE_REPO" log --oneline -1 --format="%H")
git -C "$SOURCE_REPO" revert "$MERGE_SHA" --no-edit
git -C "$SOURCE_REPO" push origin "$INTEGRATION_BRANCH"
```

If errors are detected, **do not auto-revert**. Instead:

1. Report the error to the user with log excerpts
2. Ask whether to revert or fix-forward
3. Execute their decision

**→ TaskUpdate: P11.2 → completed**

### 11.3 Notify Completion

**→ TaskUpdate: P11.3 → in_progress**

Send a completion notification in chat AND as a ticket record (for the audit trail):

```bash
# Notification content
NOTIFY_MSG="✅ Ticket completed: <ticket-id> — <title>

PR: <PR URL> (merged)
Ticket: <ticket URL> (done)

Changes:
- <1-line summary of DB changes if any>
- <1-line summary of backend changes if any>
- <1-line summary of frontend changes if any>

Deployment: <status — healthy / watching / failed>"
```

**Delivery (BOTH required):**

1. **In chat** (mandatory — the human must be notified immediately):
   ```
   $NOTIFY_MSG
   ```
2. **Ticket record** — put the completion notification where the ticket lives, so the audit
   trail survives:
   - **Notion: the integration may have NO comment-insert scope.**
     `POST /v1/comments` returns `403 restricted_resource: Insufficient permissions for this
     endpoint` (reproduced). Do **not** call the comment endpoint at all
     and do not retry it. Write the completion record as a `## Completion` section appended to
     the page's Description rich_text — the same append-the-section pattern the run already
     uses for its `## Pull request` section. (Learned 2026-09-06, confirmed 2026-10-06.)
   - **ClickUp:** `~/.agents/skills/clickup/scripts/clickup comment <task_id> "<text>"` — bare URLs for any ticket/PR links; ClickUp has **no remote-link API**, so plain text is the only linking mechanism (plain text, never labelled links).
   - **Jira / GitHub Issues:** post a normal issue comment.
   - If the write fails for any other reason, skip it gracefully and say so in the chat
     notification so the record is still visible somewhere.

Both channels are used — chat for real-time notification, the ticket record for the permanent one.

**→ TaskUpdate: P11.3 → completed**

### 11.4 Stop Dev-Server/DB Background Tasks

**→ TaskUpdate: P11.4 → in_progress**

Pane lifecycle is script-owned (the script closed your stage pane); dev servers and the DB ran as `bg_run` background tasks — stop them:

```bash
# Kill background tasks (dev servers + DB)
bg_kill  # frontend dev server task ID
bg_kill  # backend dev server task ID
bg_kill  # database server task ID


```

If the user prefers to keep dev servers running for further testing, ask before closing them.

**End-of-run Chrome / permanent-tab check — report the gap, never skip silently** (learned
learned the hard way): the run keeps three permanent tabs (ticket, PR, pi) for its whole life.
Verify `CHROME_SESSION` / `CHROME_SESSION_PROFILE` are set in the run env and that the run's
Chrome is alive before declaring the run closed:

```bash
[ -n "${CHROME_SESSION:-}" ] && [ -n "${CHROME_SESSION_PROFILE:-}" ] || echo "⚠️ CHROME vars missing"
pgrep -u pc -af '^/usr/bin/google-chrome --remote-debugging-port' | grep -c "user-data-dir=$CHROME_SESSION_PROFILE"
```

If the vars are missing or no run Chrome exists (the iterate/resume path can skip the launch),
the tab check **cannot** be performed: record `CHROME_MISSING="1"` in the run env, print the
warning in the handoff and tell the chief of staff — do NOT launch Chrome yourself, and never
report the tab check as passed when it was impossible.

**→ Print: "✅ All panes cleaned up. Ticket-do run complete."**

**→ TaskUpdate: P11.4 → completed**

### 11.5 Verify Task List Is Clean

**→ TaskUpdate: P11.5 → in_progress**

Before printing the final report, verify that every task created during this run was completed and clean up the list so the next run starts fresh:

```
TaskList
```

- If any task is **not completed** (still `pending` or `in_progress`), warn the user: `⚠️ Task '<subject>' is still <status> — this phase may not have finished cleanly. Review before starting another run.`
- **Delete all tasks** (set status to `deleted` for each) to leave a clean slate:
  ```
  For each task (by ID): TaskUpdate → status: deleted
  ```
- Re-run `TaskList` and confirm it is empty.

This guarantees no stale tasks leak into the next workflow-do run and that any incomplete phase is surfaced before the user moves on.

**→ TaskUpdate: P11.5 → completed**

### 11.6 Final Report

**→ TaskUpdate: P11.6 → in_progress**

**→ TaskUpdate: P11 → completed. Print final status table (see Output Format below).**
**→ TaskUpdate: P12 → in_progress**

**→ TaskUpdate: P11.6 → completed**

---

## Phase 12 — Friction Record (🔄) — skill edits removed

**→ TaskUpdate: P12 → in_progress**

**→ Print: "Phase 12: Reviewing session for skill improvement opportunities..."**

```bash
workflow_rename_tab "${TICKET_ID}: P12 Resume ${FEATURE_TAG}"
```

This phase runs **after every workflow-do run** — regardless of whether the ticket was
completed, partially completed, or aborted. The goal is **continuous self-improvement**:
learn from friction, corrections, and confusion encountered during this run and ask the
user whether to incorporate those learnings into the skill itself.

workflow-do is split across the main skill (`~/.agents/skills/workflow-do/SKILL.md`) and 5 group sub-skills (`~/.agents/skills/workflow-do-{prebuild,build,tour,ship,post}/SKILL.md`). Improvements are written to whichever of those files the friction concerns.

### 12.1 Locate the Current Session JSONL

**→ TaskUpdate: P12.1 → in_progress**

The current agent session is recorded as a JSONL file under `~/.pi/agent/sessions/`.
The session directory name is derived from the working directory (CWD) by replacing every
`/` with `-` and wrapping the result in leading/trailing `-`. For example:

- CWD `/Users/you/repos/<org>/<project>` → directory `--Users-you-repos-org-project--`

Find the **current** session file — it is the most recently modified `.jsonl` file in the
matching session directory:

```bash
# The script records RUN_SESSION_DIR (the pi session dir name) at run start —
# it is in /tmp/workflow-run.env. Only the fallback re-derives it.
SESSIONS_BASE="$HOME/.pi/agent/sessions"
SESSION_DIR_NAME="${RUN_SESSION_DIR:-}"
if [ -z "$SESSION_DIR_NAME" ] || [ ! -d "$SESSIONS_BASE/$SESSION_DIR_NAME" ]; then
  SESSION_DIR_NAME="--$(pwd | sed 's|^/||; s|/|-|g')--"
fi

# P12 scans ALL agent sessions for THIS ticket — not just the post agent's own.
# Every session of the run is named: the supervisor (cage launches it with
# WORKFLOW_PI_NAME=workflow-orch-<TICKET_ID>), and every stage pane (the script
# launches them as `pi --name workflow-<stage>-<TICKET_ID>`). Sessions from earlier
# rounds of the same ticket (iterate re-runs) count too — they are still sessions
# for this ticket.
#
# Selection rule — a session file belongs to this run's ticket iff:
#   1. its first line (`type: session`) has a `name` containing the ticket id
#      (case-insensitive), OR
#   2. the ticket id appears anywhere in the file content (catches the supervisor
#      and any unnamed/renamed session that worked on this ticket)
#
# $TICKET_ID comes from /tmp/workflow-run.env — source it first.
mapfile -t RUN_SESSIONS < <(
  grep -ils "$TICKET_ID" "$SESSIONS_BASE/$SESSION_DIR_NAME"/*.jsonl 2>/dev/null | sort -u
)

if [ -z "${RUN_SESSIONS[*]}" ]; then
  echo "⚠️ No session files found for ticket $TICKET_ID in $SESSIONS_BASE/$SESSION_DIR_NAME. Skipping Phase 12."
  # Mark sub-tasks as completed/skipped and end
else
  echo "Found ${#RUN_SESSIONS[@]} session(s) for $TICKET_ID:"
  printf '  %s\n' "${RUN_SESSIONS[@]}"
fi
```

If no session files are found, skip Phase 12 gracefully.

**→ TaskUpdate: P12.1 → completed**


### 12.2 Scan Session for Friction, Corrections & Confusion

**→ TaskUpdate: P12.2 → in_progress**

Read **every session JSONL in `RUN_SESSIONS`** and analyze the conversations for patterns that
indicate the skill could be improved. Run the scan below once per file and **tag each finding
with the session it came from** (the stage name — e.g. `workflow-build-<TICKET_ID>` — or
the run's supervisor session) so the friction list you present in 12.3 says where each problem occurred.
Specifically look for:

#### Friction Signals to Detect

1. **User corrections** — the user told the agent it was wrong, on the wrong track, or
   should do something differently:
   - "no", "stop", "wait", "that's wrong", "not what I meant"
   - "actually...", "instead of...", "use X not Y", "fix but..."
   - Repeating the same instruction because the agent didn't get it the first time

2. **AI confusion** — the agent itself was uncertain, went down the wrong path, or
   showed misunderstanding:
   - The agent asked a question the user found unnecessary or obvious
   - The agent attempted an approach and the user redirected
   - The agent assumed something about the project that was incorrect

3. **Failed attempts that didn't work initially** — tool calls or approaches that errored
   out or produced wrong results before the agent corrected course:
   - Bash commands that failed and had to be re-run with different arguments
   - Git operations that failed (wrong branch, missing remote, signing issues)
   - Docker/container issues that required troubleshooting
   - The agent tried something, it didn't work, tried something else

4. **Missing information in the skill** — situations where the skill's instructions
   weren't clear enough and the agent had to figure it out through trial and error:
   - A step that the skill described ambiguously
   - A tool or command that wasn't documented in the skill
   - An edge case the skill doesn't handle

#### How to Scan

Parse the JSONL file. Each line is a JSON object. Focus on:

- **`type: "message"`** entries where `message.role` is `"user"` — these are human
  instructions, corrections, and feedback
- **`type: "message"`** entries where `message.role` is `"assistant"` — these show
  what the agent did and whether it later had to backtrack
- **`type: "toolResult"`** entries — look for error results or failed commands

```bash
# Extract all user messages and their text content from the session
python3 -c "
import json, sys

session_file = sys.argv[1]
friction = []

with open(session_file) as f:
    for line in f:
        try:
            d = json.loads(line)
        except:
            continue
        if d.get('type') != 'message':
            continue
        msg = d.get('message', {})
        role = msg.get('role', '')
        content = msg.get('content', [])

        # Extract text from content blocks
        texts = []
        for c in content:
            if isinstance(c, dict) and c.get('type') == 'text':
                texts.append(c['text'])
            elif isinstance(c, str):
                texts.append(c)
        full_text = ' '.join(texts).strip()
        if not full_text:
            continue

        if role == 'user':
            # Check for correction/friction patterns
            lower = full_text.lower()
            friction_words = ['no ', 'stop', 'wait', 'wrong', 'not what', 'actually',
                            'instead', 'use ', 'fix but', 'that\'s not', 'you should',
                            'don\'t', 'should be', 'i think', 'is it', 'why did',
                            'try again', 'restart', 'isn\'t', 'is not', 'not mounted',
                            'not working', 'failed', 'error']
            if any(w in lower for w in friction_words):
                friction.append(('user_correction', full_text[:500]))
        elif role == 'assistant':
            # Check for confusion/backtracking
            lower = full_text.lower()
            confusion_words = ['let me try', 'that didn\'t work', 'oops', 'mistake',
                              'actually', 'i was wrong', 'let me re', 'retry',
                              'failed', 'error:', 'incorrect']
            if any(w in lower for w in confusion_words):
                friction.append(('agent_confusion', full_text[:500]))
        elif role == 'toolResult':
            # Check for failed tool results
            if 'error' in full_text.lower() or 'failed' in full_text.lower():
                friction.append(('failed_tool', full_text[:500]))

if not friction:
    print('NO_FRICTION_FOUND')
else:
    for kind, text in friction:
        print(f'--- {kind} ---')
        print(text)
        print()
" "$SESSION_FILE"
```

Loop `SESSION_FILE` over every file in `RUN_SESSIONS` — the script takes the session
file path as argv[1] and prints findings with `--- <kind> ---` headers; prefix each
run's output with the session/stage name when collecting the list.

The above script is a **starting heuristic** — also use your own judgment reading the
session. The keyword matching is deliberately broad (false positives are OK at this
stage; you will filter and present only actionable items to the user in 12.3).

After scanning, categorize the findings:

- **Actionable** — a friction point that reveals a gap, ambiguity, or missing instruction
  in the skill that, if fixed, would prevent the same friction in future runs
- **One-off** — a friction point specific to this environment/ticket that wouldn't recur
  (e.g., a one-time credential setup issue) — not worth incorporating
- **Nothing meaningful** — the run was smooth; no corrections or confusion worth capturing

**→ TaskUpdate: P12.2 → completed**


### 12.3 Record friction — do NOT edit skills

**→ TaskUpdate: P12.3 → in_progress**

Per-ticket skill improvement was removed (decision 2026-10-08): a run does **not** ask about
incorporating learnings and does **not** edit skill files. Skill edits happen through a
**periodic bulk friction scan** — a separate recurring job that reads friction collected
across many runs at once.

Record each friction point in a form that is easy to scan and act on later, and keep the
motivation **highly summarized**:

```
- <what happened> → <why it matters, one line> → <proposed fix, one line>
```

One line per point, never prose. Write the list to `/tmp/workflow-friction.md`, then export
it so the P13 email can include it:

```bash
FRICTION="$(cat /tmp/workflow-friction.md)"; export FRICTION
```

Print the list, then move on. Do not ask, do not wait, and do not touch any SKILL.md. If
the scan found nothing, record `FRICTION=""` and say so.

The friction list is surfaced in the **P13 email summary** under "Friction / skill
observations" — that is where the periodic bulk scan picks it up. The periodic scan itself
asks about its proposed edits in that same shape (what → why it matters → proposed fix,
one line each), with the motivation summarized to a single line so each ask is clear.

**→ TaskUpdate: P12.3 → completed**

### 12.4 (removed)

Skill-file edits are no longer applied during a run. There is no P12.4.

**→ TaskUpdate: P12.4 → completed (no-op, removed)**
**→ TaskUpdate: P12 → completed. Print: "✅ Phase 12 complete. Friction recorded (skills not edited during a run)."**

---

## Phase 13 — Email Summary (📧)

**→ TaskUpdate: P13 → in_progress**

**→ Print: "Phase 13: Preparing email summary..."**

```bash
workflow_rename_tab "${TICKET_ID}: P13.1 Email ${FEATURE_TAG}"
```

This phase runs **after Phase 12**. It gathers ticket metadata, calculates timing,
generates a professional HTML email, and sends it to `$NOTIFY_EMAIL` via
`msmtp` (configured for `$MSMTP_FROM` through Resend SMTP).

**⚠️ ORDERING (ticket friction example):** the email embeds the annotated screenshots from `$WORKTREE/screenshots/` as inline base64 images. Send the email **BEFORE** the Phase 10.4 worktree cleanup removes that dir — the screenshots must still be on disk. If the worktree was already removed, the GitHub user-attachment URLs are auth-gated (404 via curl) and can't be re-fetched, so the email goes out without inline images (text + PR link only). Prefer: merge (10.3) → Phase 13 email → then 10.4 cleanup. (Phase numbering is advisory; the email send can be pulled forward to preserve screenshots.)

The email gives you a single, scannable summary of what was done — PR link, ticket
link, how long it took, what changed, the guided tour results, and the annotated
screenshots — so you don't have to dig through GitHub to see what happened.

### 13.1 Gather Ticket Data + Calculate Timing

**→ TaskUpdate: P13.1 → in_progress**

Collect all the data the email needs. Most of it is already available from earlier
phases — the agent has `$TICKET_ID`, `$TICKET_URL`, `$PR_URL`, the summary from
Phase 5.8, the tour results from Phase 6.2, and the screenshot URLs from Phase 7.6.

The run-wide token & prompt counters (13.1b) are computed by the script
(`appendRunStats`) and recorded in `/tmp/workflow-run.env` along with
`RUN_SESSION_DIR` and `RUN_STARTED_AT_EPOCH` (both recorded by the script at run
start). If they are missing (a pre-v8 run), 13.1b falls back to scanning the
last 24h of the run's session directory.

#### Accurate per-run metrics from pi session JSONL (user mandate 2026-09-22)

All counts MUST come from the run's **actual pi session JSONL files** — never
estimated, never word-counted. Token counts ARE accurately available: every
assistant response in the JSONL carries a usage block with `input`, `output`,
and `cacheRead` counts; summing them across the run's sessions is exact.

**Time Taken (unit mandatory):** pi session JSONL lines are timestamped — the
first and last timestamp of a session file give that session's span. Run time
= the **sum of the run's session spans** (stages run sequentially, so spans
don't overlap). Render with a unit: `<N>h <M>m` if ≥ 60 minutes, else `<M>m`.
The 13.2 email script computes this itself from the ticket's session files
(`TIME_TAKEN_MINUTES` in the run env is the run-side record, not an email input).

```bash
# Per-run metrics recipe (adapt the session glob to the run's cwd dirs):
python3 - <<'PYEOF'
import json, glob, re
files = sorted(glob.glob('$HOME/.pi/agent/sessions/*<RUN_CWD_DIR>*/<DATE-RANGE>*.jsonl'))
ti=to=tc=0; humans=0; first=None; last=None
for f in files:
    spans=[]; prev_ts=None
    for line in open(f):
        m=re.search(r'"timestamp":"([^"]+)"', line)
        ts=m.group(1) if m else None
        if ts:
            if first is None or ts<first: first=ts
            if last is None or ts>last: last=ts
            if prev_ts is None: spans.append([ts, ts])
            else: spans[-1][1]=ts
            prev_ts=ts
        d=json.loads(line)
        if d.get('type')=='message':
            msg=d.get('message',{})
            if msg.get('role')=='user':
                c=msg.get('content'); t=c if isinstance(c,str) else ' '.join(
                    x.get('text','') for x in c if isinstance(x,dict) and x.get('type')=='text')
                # human = a user message that is NOT a stage-prompt
                # (stage prompts start with 'Read $HOME/.agents/skills/workflow-do')
                if t.strip() and not t.strip().startswith('Read $HOME/.agents/skills/workflow-do'):
                    humans+=1
        if '"input":' in line:
            i=re.search(r'"input":(\d+)',line); o=re.search(r'"output":(\d+)',line)
            cr=re.search(r'"cacheRead":(\d+)',line)
            ti+=int(i.group(1)) if i else 0; to+=int(o.group(1)) if o else 0
            tc+=int(cr.group(1)) if cr else 0
print('input:',ti,'output:',to,'cacheRead:',tc,'total:',ti+to+tc)
print('human prompts:',humans)
PYEOF
```

- **DAYS_SINCE_CREATED**: from the tracker's **create timestamp** — Notion page
  `created_time` (GitHub `created_at`, ClickUp `date_created` — epoch **ms**,
  from `clickup get <id> --json`). Compute days to
  completion (the run's last session timestamp), not to "now".
- **DAYS_SINCE_STARTED**: from the **first pi session** of the run (earliest
  session timestamp across the run's sessions) to completion (last session
  timestamp) — compute days.
- **REVIEW_FEEDBACK_COUNT / review rounds**: read the PR's review history —
  count every review/comment by a user OTHER than the ticket owner (gh:
  `gh api repos/<org>/<repo>/pulls/$PR_NUMBER/reviews --jq '[.[] | select(.author.login != "<OWNER>") | .state]'`);
  each non-owner review = one review round; the count of
  CHANGES_REQUESTED-then-revisit cycles is the "rounds required".
- **Risk meter**: mirror the PR body's **Risk Assessment** line (emoji + level
  + one-line rationale) into the email's `RISK_METER` var.
- **STEPS_TABLE** (new): one row per executed workflow phase in
  `phase;tokens;time;cost;human` form — phase from the stage panes, per-phase
  tokens/time from the per-session sums above, human = gate prompts answered
  in that phase (0 for fully autonomous phases).

#### Time Taken — SCRIPT-COMPUTED

`RUN_STARTED_AT_EPOCH` / `RUN_ENDED_AT_EPOCH` / `TIME_TAKEN_MINUTES` are already in `/tmp/workflow-run.env` (`TIME_TAKEN_MINUTES` = the wall-clock span from run start to the last park/done exit). They are the run-side record — the 13.2 email script does NOT use them: it renders **total time taken = the SUM of the ticket's per-session durations**, and it never adds a wall-clock caveat to the body.

**Why the two differ:** the wall-clock span includes time between sessions — waiting for human approval (Phase 9 polling), guided-tour pauses and idle periods — which the session spans exclude. Use the run-env value when you describe the run in the handoff/run log; expect the email's "Total time taken" to be the smaller, per-session sum. Both are honest; they answer different questions.

#### Ticket Days Since Created / Started

Fetch the ticket's creation date and "started" date from the tracker API:

- **Created date:** every tracker exposes this — GitHub issue `created_at`,
  ClickUp `date_created` (epoch ms, via `~/.agents/skills/clickup/scripts/clickup get <id> --json`),
  Notion page
  `created_time`.
- **Started date:** the date the ticket was moved to "In Progress" (or equivalent).
  ClickUp exposes it as the task's `start_date` (the clickup CLI sets it at P3.10;
  read it with `clickup get <id> --json`) — use it when set, otherwise fall back to
  the session start timestamp from the JSONL above. If the tracker has no status
  transition history (GitHub Issues), the session timestamp is the answer.

```bash
# GitHub Issues example:
CREATED_AT=$(gh issue view $TICKET_NUMBER --json createdAt --jq '.createdAt')
# ClickUp example (epoch ms → ISO):
# CREATED_AT=$(python3 -c "import datetime; print(datetime.datetime.fromtimestamp(<epoch_ms>/1000, datetime.timezone.utc).isoformat())")

# Calculate days since created
DAYS_SINCE_CREATED=$(python3 -c "
from datetime import datetime, timezone
created = datetime.fromisoformat('${CREATED_AT}'.replace('Z', '+00:00'))
now = datetime.now(timezone.utc)
delta = (now - created).days
print(delta)
" 2>/dev/null || echo "unknown")

# For "started" date: use the session start timestamp as a fallback
# (or query the tracker's status transition history if available)
DAYS_SINCE_STARTED=$(python3 -c "
from datetime import datetime, timezone
started = datetime.fromisoformat('${START_TS}'.replace('Z', '+00:00'))
now = datetime.now(timezone.utc)
delta = (now - started).days
print(delta)
" 2>/dev/null || echo "unknown")
```

#### Collect the Remaining Fields

Gather these from data already produced in earlier phases:

| Field               | Source                                                                                                                                                                                   |
| ------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `TICKET_ID`         | Phase 1                                                                                                                                                                                  |
| `TICKET_TITLE`      | Phase 1                                                                                                                                                                                  |
| `TICKET_URL`        | Phase 1                                                                                                                                                                                  |
| `PR_URL`            | Phase 3.7                                                                                                                                                                                |
| `MOTIVATION`        | Phase 2 (groomed ticket description) or the original ticket body                                                                                                                         |
| `DB_SUMMARY`        | Phase 5.7 summary — 1-line condensation of the Database Changes section                                                                                                                  |
| `BACKEND_SUMMARY`   | Phase 5.7 summary — 1-line condensation of the Backend Changes section                                                                                                                   |
| `FRONTEND_SUMMARY`  | Phase 5.7 summary — 1-line condensation of the Frontend Changes section                                                                                                                  |
| `SCREENSHOTS`       | Phase 7.6 — before/after annotated screenshots as `path\|url\|caption` lines, the same ones posted to the PR. Shown inline in the email. |
| `DEPLOYMENT_STATUS` | Phase 11.1                                                                                                                                                                               |
| `TOKEN_TOTAL`, `TOKEN_INPUT` / `TOKEN_OUTPUT`, `COST_TOTAL`, `HUMAN_PROMPT_COUNT`, `REVIEW_FEEDBACK_COUNT` | 13.1b — run-env record of the run's counters (run log + handoff). Not email inputs: the 13.2 script recomputes tokens, cost, human prompts and time from the per-ticket session files. |

Note: the email's headline numbers (days since started, total time taken, review iterations)
and the per-session table are all derived in 13.2's script — 13.1/13.1b only supply the
narrative fields above.

Write the motivation as 1-2 sentences in plain English explaining **why this
ticket exists** — the problem it solves, not the technical implementation. Pull
this from the groomed ticket description (Phase 2) or the original ticket body.
Keep it human and brief, not AI-sounding.
#### Per-Ticket Run Stats — Token, Prompt & Review-Feedback Counters

**→ TaskUpdate: P13.1b → in_progress**

**The script computes these** (`appendRunStats` at every park/done exit) and appends them to the run env: `TOKEN_TOTAL`, `TOKEN_INPUT`, `TOKEN_OUTPUT`, `COST_TOTAL`, `HUMAN_PROMPT_COUNT`. Read them — do NOT re-scan. These are the run-side record for the run log and the handoff: §13.2's email script recomputes the same numbers from the session files itself and takes none of them as input.

```bash
# Primary: script-computed vars already in /tmp/workflow-run.env (source it first)
export TOKEN_TOTAL="${TOKEN_TOTAL:-0}" TOKEN_INPUT="${TOKEN_INPUT:-0}" \
       TOKEN_OUTPUT="${TOKEN_OUTPUT:-0}" COST_TOTAL="${COST_TOTAL:-0}" \
       HUMAN_PROMPT_COUNT="${HUMAN_PROMPT_COUNT:-0}"
export REVIEW_FEEDBACK_COUNT="$HUMAN_PROMPT_COUNT"

# Fallback (pre-v8 runs without the vars): the same jq scan the script runs —
# RUN_SESSION_DIR + RUN_STARTED_AT_EPOCH are also recorded in the run env.
if [ -z "${TOKEN_TOTAL:-}" ] || [ "$TOKEN_TOTAL" = "0" ]; then
  RUN_SESSION_DIR="${RUN_SESSION_DIR:-$HOME/.pi/agent/sessions/--$(pwd | sed 's|^/||; s|/|-|g')--}"
  RUN_STARTED_AT_EPOCH="${RUN_STARTED_AT_EPOCH:-$(( $(date +%s) - 86400 ))}"
  find "$RUN_SESSION_DIR" -maxdepth 1 -name '*.jsonl' -newermt "@$RUN_STARTED_AT_EPOCH" -print0 \
  | xargs -0 cat 2>/dev/null \
  | jq -R 'fromjson? // empty' \
  | jq -s 'map(select(.type == "message" and (.message.usage != null))) | {token_total: (map(.message.usage.totalTokens // 0) | add // 0), token_input: (map(.message.usage.input // 0) | add // 0), token_output: (map(.message.usage.output // 0) | add // 0), cost_total: (map(.message.usage.cost.total // 0) | add // 0), human_prompts: (map(select(.message.role == "user")) | length)}' \
  > /tmp/workflow_run_stats.json
  read -r TOKEN_TOTAL TOKEN_INPUT TOKEN_OUTPUT COST_TOTAL HUMAN_PROMPT_COUNT < <(
    jq -r '[.token_total, .token_input, .token_output, .cost_total, .human_prompts] | @tsv' /tmp/workflow_run_stats.json
  )
  export TOKEN_TOTAL TOKEN_INPUT TOKEN_OUTPUT COST_TOTAL HUMAN_PROMPT_COUNT
  export REVIEW_FEEDBACK_COUNT="$HUMAN_PROMPT_COUNT"
fi

# Comma-grouped variants for the run log / handoff (not email inputs — §13.2's
# script formats its own numbers):
export TOKEN_TOTAL_FMT="$(printf "%'d" "$TOKEN_TOTAL")" \
       TOKEN_INPUT_FMT="$(printf "%'d" "$TOKEN_INPUT")" \
       TOKEN_OUTPUT_FMT="$(printf "%'d" "$TOKEN_OUTPUT")" \
       COST_TOTAL_FMT="$(printf "%.4f" "$COST_TOTAL")"
export HUMAN_PROMPT_COUNT_FMT="$(printf "%'d" "$HUMAN_PROMPT_COUNT")" \
       REVIEW_FEEDBACK_COUNT_FMT="$HUMAN_PROMPT_COUNT_FMT"

# DEBUG — print so the run log shows what was aggregated:
echo "sessions scanned: $(find "$RUN_SESSION_DIR" -maxdepth 1 -name '*.jsonl' -newermt "@$RUN_STARTED_AT_EPOCH" | wc -l)"
echo "tokens=$TOKEN_TOTAL_FMT (in $TOKEN_INPUT_FMT / out $TOKEN_OUTPUT_FMT) · cost \$$COST_TOTAL_FMT · human prompts=$HUMAN_PROMPT_COUNT"
```

How the numbers are defined (workflow-do convention — compute directly, no
helper script):

- `TOKEN_TOTAL` sums `usage.totalTokens` over every assistant message AND every
  `toolResult` message that carries nested LLM usage (the jq filter includes any
  message with `usage`), so tool-driven LLM calls are captured. `usage.input` /
  `usage.output` are the in/out subfields. `usage.cost.total` is 0.0 on accounts
  that don't track cost — render as "—" in the email then.
- `HUMAN_PROMPT_COUNT` — messages with `message.role == "user"`. Tool results
  arrive as a separate `toolResult` role and are **not** counted, so this is
  genuine human-typed input.
- `REVIEW_FEEDBACK_COUNT` — by the chosen definition, the same as the human
  prompt count (every human message counts as feedback).
- Files are selected by **mtime >= RUN_STARTED_AT_EPOCH**, which captures the run's own
  supervisor session even when its start slightly precedes the recorded epoch.

**Known limitation:** if a second, concurrent pi session runs in the same repo
CWD during the workflow-do run, its tokens are included too. workflow-do runs are
normally singular/interactive, so this is rare; the email is a nice-to-have
analytics aid, not billing-grade.

**→ TaskUpdate: P13.1b → completed**

**→ TaskUpdate: P13.1 → completed**

### 13.2 Generate HTML Email + Send via msmtp

**→ TaskUpdate: P13.2 → in_progress**

The email lives in a dedicated TypeScript script — run it with `npx tsx`:

```
~/.agents/skills/workflow-do/send-summary-email.ts
```

(`send-summary-email.sh` next to it is only a thin shim that execs this file, kept so the
container path `/usr/local/bin/send-summary-email.sh` from the Dockerfile keeps working —
never put email logic in the `.sh`.)

It **fetches its own data** — the run env, the pi session logs of EVERY session belonging to
the ticket (all dirs under `~/.pi/agent/sessions` + `RUN_SESSION_DIR`, matched on the session
directory, the recorded `cwd` or the session label — earlier runs of the ticket, sibling
worktrees and earlier days included), Notion, the GitHub PR and `phases.json` — and renders a
multipart MIME message (text fallback + styled HTML: headline totals table, one row per
session, risk meter, phases table, guided-tour screenshots) which it pipes to `msmtp`.

Three modes (fetch → verify → send, never one blind step):

```bash
# 1. FETCH the verified source of truth and READ it: headline totals, per-session rows and
#    the session files used are printed on stderr and written to the JSON.
TS=~/.agents/skills/workflow-do/send-summary-email.ts
npx tsx "$TS" --fetch-only --out /tmp/workflow-summary-email.json

# 2. OPTIONAL: render the HTML body + text fallback to files and inspect/grep them.
npx tsx "$TS" --render /tmp/workflow-email-body.html --json /tmp/workflow-summary-email.json

# 3. SEND the real email.
npx tsx "$TS" --send --json /tmp/workflow-summary-email.json
```

**⚠️ Verification NEVER sends mail** — not once, not to a test address, not to yourself.
Verify with `--fetch-only` + `--render` and read the JSON/HTML; `--send` is run only for the
real P13 email. (User directive 2026-10-14.)

Everything else comes from the run env (`/tmp/workflow-run.env`, or `$WORKFLOW_RUN_ENV`), so the
invocation above needs no exports. Env vars it honours:

| Env var | Used for |
| --- | --- |
| `TICKET_ID` (else run env) | which ticket's sessions + tracker page to collect |
| `PR_URL` / `PR_NUMBER`, `REPO_SLUG` or `GITHUB_ORG`+`REPO_NAME` | PR link, risk line, review history |
| `WORKTREE` (else run env, else `~/worktrees/*/*/<TICKET>*`) | `.workflow-handoff.env` → review-iteration count |
| `TICKET_URL`, `NOTION_TOKEN` / `NOTION_PAGE_ID` | ticket link, created time, motivation |
| `SCREENSHOTS` — `path\|url\|caption` lines | inline annotated screenshots (resized, base64 CID) |
| `DB_SUMMARY`, `BACKEND_SUMMARY`, `FRONTEND_SUMMARY`, `RISK_METER`, `DEPLOYMENT_STATUS`, `FRICTION` | summary sections; each falls back to the PR body |
| `EMAIL_TO` or `NOTIFY_EMAIL` (also read from `$ORG_CONFIG_DIR/env/notify.env`), `MSMTP_FROM` | recipient + From |

Every number is computed by the script from the session JSONL / tracker / PR — never
hand-counted, never passed in: days since started = now − the earliest session timestamp, total
time taken = the SUM of the per-session durations (not the wall-clock span), review iterations =
how often the ticket went to Review Denied and back into a fix round (handoff → run env/state →
`CHANGES_REQUESTED` PR reviews, rendered as "—" when absent), and the per-session table's TOTAL
row equals the headline totals. The `TOKEN_*` / `COST_TOTAL` / `HUMAN_PROMPT_COUNT` vars in the run
env are the run-side record (13.1b) — they are NOT email inputs.

The script sends to `$NOTIFY_EMAIL` by default. Override with `EMAIL_TO="other@example.com"`.

**Prerequisites (must be configured once, see msmtp setup below):**

- `msmtp` installed (`apt install msmtp msmtp-mta`)
- `~/.msmtprc` configured for Resend SMTP (`smtp.resend.com:587`, from `$MSMTP_FROM`)
- `$ORG_CONFIG_DIR/env/gmail.env` or Resend API key in the msmtp passwordeval

#### msmtp Configuration (reference — set up once)

`~/.msmtprc` must be mode 600 and contain:

```
defaults
auth           on
tls            on
tls_starttls   on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        ~/.msmtp.log

account        resend
host           smtp.resend.com
port           587
from           $MSMTP_FROM
user           resend
passwordeval   "grep RESEND_API_KEY $ORG_CONFIG_DIR/env/resend.env | head -1 | cut -d'=' -f2 | tr -d '\"'"

account default : resend
```

The Resend API key lives in `$ORG_CONFIG_DIR/env/resend.env`:

```
RESEND_API_KEY="re_..."
```

If `msmtp` is not installed or `~/.msmtprc` is missing, **do NOT skip this
phase — never skip the email (user decision 2026-09-22: "never ever skip
again").** Install/configure it on the spot: `sudo apt install msmtp
msmtp-mta`, then write `~/.msmtprc` exactly per the reference block above
(mode 600) and re-run step 3 of the invocation above. Only if a step genuinely needs the user (e.g.
a missing API key file after checking `$ORG_CONFIG_DIR/env/resend.env`), STOP and
ask via intercom — the email is a required output of the run, not a
nice-to-have.

**→ Print:**

```
📧 Email summary sent to $NOTIFY_EMAIL
   From: $MSMTP_FROM
   Subject: ✅ <TICKET_ID> — <TICKET_TITLE>
```

If the send fails (msmtp exits non-zero), read `~/.msmtp.log` for the error,
print a warning, and continue — do not block on email delivery.

**→ TaskUpdate: P13.2 → completed**
**→ TaskUpdate: P13 → completed. Print: "✅ Phase 13 complete. Email summary sent."**

---

