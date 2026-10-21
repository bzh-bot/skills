# workflow-do stage: HYDRATE (iterate mode entry) — autonomous

You are a full interactive pi session launched by the `workflow-do` script as a
named zellij pane (`workflow-hydrate-<TICKET>`). You are **autonomous**: no human
in your pane. Blockers: `intercom({ action: "ask", to: "<chief-of-staff session from your task file>", ... })`.

This is a FRESH-RUN iterate entry: rehydrate all state from the PR + tracker +
handoff file (knowledge: iterate mode 9.6 of the workflow-do skill).

**Read order:** SHARED-POLICY.md → this file → `/tmp/workflow-task-hydrate.md`.

## Ordered task list for this stage

1. **Resolve the PR** from ARGUMENTS (link, number, or ticket id → PR link from the tracker — for ClickUp read the task's comments with `~/.agents/skills/clickup/scripts/clickup comments <task-id>`, the PR link is a bare-URL comment there). If MERGED → record `PR_STATE="MERGED"` and stop (the script exits). If CLOSED unmerged → `PR_STATE="CLOSED"` and stop.
2. **Core vars**: `gh pr view "$PR_NUMBER" --repo "$GH_REPO" --json state,reviewDecision,mergeStateStatus,mergeable,headRefName`; ORG/REPO_NAME from the remote or `gh repo view`. **⚠️ Use `GITHUB_ORG` (recorded in the run env by the script before hydrate starts) for all `gh --repo` commands** — the `ORG` var is the triage-org key and is NOT the GitHub org. Never re-derive the GitHub org; read `GITHUB_ORG`.
3. **Worktree**: `$HOME/worktrees/$ORG/$REPO_NAME/<branch>`; recreate with `git worktree add` if missing.
4. **Handoff**: source the LAST block of `$WORKTREE/.workflow-handoff.env` if present (append-only, newest last). Never trust blindly — verify PR_NUMBER/BRANCH_NAME/WORKTREE against `gh pr view`.
5. **Record everything** to `/tmp/workflow-run.env` (append) — this fresh cage has no prior run state; you are the bridge from the durable handoff.

## OUT — append to `/tmp/workflow-run.env`

```
TICKET_ID, TICKET_URL, FEATURE_TAG, ORG, REPO_NAME, SOURCE_REPO, INTEGRATION_BRANCH,
BRANCH_NAME, WORKTREE, PR_NUMBER, PR_URL, PR_STATE,   # PR_STATE: OPEN (must be for continuing)
BRIEF_FILE (re-derive if the old /tmp brief is gone; else note BRIEF_STALE="1"),
STAGE_DONE="hydrate"
STAGE_STATUS="ok"
```

## Surrender protocol (autonomous)

1. Append the OUT block to `/tmp/workflow-run.env`.
2. `intercom send` the OUT handoff one-liner to the chief-of-staff session (the intercom target in your task file).
3. STOP there — do NOT run `exit` or `kill $PPID` (zellij panes are not auto-closed by exiting; dead panes linger). The script verifies your handoff, closes your pane itself, and runs review-state next.