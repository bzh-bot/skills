# workflow-do stage: PREBUILD (P0–P3) — interactive

You are a full interactive pi session launched by the `workflow-do` script as a
named zellij pane (`workflow-prebuild-<TICKET>`) inside the run's tab. The human
works in YOUR pane. You are the first stage of a deterministic stage machine:
when you surrender, the script launches the next stage automatically.

**Read order (already given in your launch prompt):**
1. `~/.agents/skills/workflow-do/SHARED-POLICY.md` — shared policy, pane + tab helpers
2. this file (your stage instructions)
3. `/tmp/workflow-task-prebuild.md` — state pointers, ARGUMENTS, run env location
4. `~/.agents/skills/workflow-do-prebuild/SKILL.md` — **the full P0–P3 phase knowledge; follow it exactly, every substep**

## Ordered task list for this stage

0. **Read the scout context pack first** — the run env records `SCOUT_FILE`
   (usually `/tmp/workflow-scout.md`): ticket summary, relevant repo files, org
   conventions, and existing PRs/branches/CI for this ticket. Use it to build
   the brief and skip re-scouting; if it is missing or stale, do a quick
   scout yourself before grooming.
1. **P0 — Access & Browser Verification** (per SKILL.md: APPEND_SYSTEM.md, pi update, zellij session, git signing, headed Chrome, agent-browser)
2. **P1 — Project Detection + Ticket Resolution** — ⚠️ **P1.1/P1.4/P1.5/P1.7 are SCRIPT-DETECTED** (`ORG`, `REPO_ROOT`, `REPO_NAME`, `INTEGRATION_BRANCH`, `PKG_MGR`, `HAS_*`, `PROJECT_PROFILE_FILE` already in the run env — read, don't re-derive). You still do: tracker resolution (**the ticket MUST already exist — runs never create tickets**), gh credentials, command discovery (profile first), docs, resumability
3. **P2 — Groom the Ticket (Grill Mode)** (explore codebase first, DB-first decision tree answered from code with recorded assumptions; the only ask is the ticket-creation question for bare-idea runs; 5-element brief; write back to ticket — for ClickUp read the live list statuses first with `clickup list <list_id>`, Sprint lists roll; advance status)
4. **P3 — Workspace Setup + PR Creation** (monitor detect + Chrome positioning, sync integration branch, worktree + feature branch, push, symlink secrets, install deps, DB up + migrate + hydrate, dev servers, draft PR, PR link on ticket)

State (run env): `/tmp/workflow-run.env` — read/source it; **append only, never overwrite**.
Your ARGUMENTS (ticket reference or idea) are in the task file. org-config is at `$ORG_CONFIG_DIR/org-config.json`.

**Chrome is script-owned:** the script already launched the run Chrome on a FIXED CDP port
before this stage started — `CHROME_LAUNCHED="1"`, `CHROME_CDP_PORT` and `CHROME_SESSION_PROFILE`
are in the run env. You **attach** to that browser with
`agent-browser --headed --session "$CHROME_SESSION" --pin-tab --profile "$CHROME_SESSION_PROFILE" --cdp "http://127.0.0.1:$CHROME_CDP_PORT" open <url>`
(every value read from the run env; NEVER `--auto-connect` — always target the run's explicit Chrome
session) — you never launch Chrome yourself. **Persistent tabs (SHARED-POLICY "Persistent Ticket + PR Tabs"): open the TICKET in its labeled `ticket` tab as your FIRST browser action, and open the PR in the labeled `pr` tab the moment the PR exists (`ensure_tab`); both stay open for the entire run and no other tab may reuse or close them.**
Always attach with the FULL QUADRUPLE — `XDG_DATA_HOME="$CHROME_XDG_DATA_HOME" agent-browser --headed --session "$CHROME_SESSION" --pin-tab --profile "$CHROME_SESSION_PROFILE" --cdp "http://127.0.0.1:$CHROME_CDP_PORT" <subcommand>` — with every value read from the run env. **NEVER the bare form, and never without `--profile`/`--headed`/`--cdp`** (this file used to say the opposite — it was wrong, corrected 2026-10-07): a call that omits them starts a NEW Chrome on a throwaway `/tmp/agent-browser-chrome-<uuid>` profile, i.e. a second, logged-out window on the user's desktop, and a Chrome started by `agent-browser` gets an EPHEMERAL debug port that nothing records. ONE browser per run — if an attach fails, fix the flags; never fall through to a fresh Chrome. If the browser is genuinely dead, run `bash ~/.agents/skills/workflow-do/scripts/chrome.sh status` then `... chrome.sh revive` (idempotent, same profile, records the port) — never hand-roll a launch.

## OUT — append to `/tmp/workflow-run.env` (append-only, KEY="value", no double quotes in values)

```
TICKET_ID, TICKET_URL, TICKET_TITLE, FEATURE_TAG,
ORG, REPO_NAME, REPO_ROOT, SOURCE_REPO, INTEGRATION_BRANCH, PKG_MGR,
BRANCH_NAME, WORKTREE, PR_NUMBER, PR_URL,
WORKFLOW_VIEWPORT_W, WORKFLOW_VIEWPORT_H, SCREENSHOTS_DIR, DB_URL,
BRIEF_FILE,                    # path to /tmp/workflow-brief.md (5-element brief + acceptance criteria)
HAS_FRONTEND, FRONTEND_DIR, BACKEND_DIR, IS_MONOREPO,
HAS_VERCEL, HAS_GH_ACTIONS, HAS_CIRCLECI, HAS_JENKINS, HAS_SUPABASE, HAS_DATADOG,
dev-server state (FRONTEND_PANE, BACKEND_PANE, DB_PANE, ports),
STAGE_DONE="prebuild"
STAGE_STATUS="ok"          # or "blocked" — then STOP; the script will halt for intervention
```

The 5-element brief + acceptance criteria go to `/tmp/workflow-brief.md` (record `BRIEF_FILE`).

## Surrender protocol (your final actions, in order)

1. Append the OUT block above to `/tmp/workflow-run.env` (`cat >> `, never `>`).
2. `intercom({ action: "send", to: "<chief-of-staff session from your task file>", message: "prebuild OUT handoff: <one-line summary>" })` — skip silently if intercom is unavailable.
3. STOP there — do NOT run `exit` or `kill $PPID` (zellij panes are not auto-closed by exiting; dead panes linger). The script verifies your handoff, closes your pane itself, and launches the build stage. No closure confirmation is asked (stage-closure prompts were removed).

Do NOT start Phase 4. The build stage is launched by the script, not by you.