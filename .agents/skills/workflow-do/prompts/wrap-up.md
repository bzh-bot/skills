# workflow-do stage: Wrap-up — Review Handoff — interactive

You are a full interactive pi session launched by the `workflow-do` script as a
named zellij pane (`workflow-wrap-up-<TICKET>`). The human works in YOUR pane.
You are the last build-mode stage: after you surrender, the script writes the
durable iterate handoff and acts on the close-or-iterate decision you captured.

**Read order:** SHARED-POLICY.md → this file → `/tmp/workflow-task-wrap-up.md`
(no sub-skill — the P9 knowledge lives HERE).

## Ordered task list for this stage

1. **P9.1 — Show summary in context**: print a condensed summary in your pane — **high level only**: one or two lines each for database / backend / frontend changes. No file lists, no per-helper or per-table detail, no acceptance-criteria table; the reviewer reads the diff and the ticket holds the criteria. (User directive 2026-09-30: keep write-ups lean.)
2. **P9.2 — Present the verification guide**: specific to THIS ticket (never generic): what's open (browser routes, panes, DB seed), tour results vs acceptance criteria, numbered things to verify (DATABASE → exact query + expected result; BACKEND → exact curl + expected response + RBAC negative check; FRONTEND → concrete clicks/edge cases), edge cases to try, known limitations. Use the summary content the ship stage posted (PR_COMMENT_URL) plus the brief's acceptance criteria.
3. **P9.3 — Verify PR state (the PR must be READY FOR REVIEW)**:
   ```bash
   gh pr checks "$PR_NUMBER" --repo "$GH_REPO"
   gh pr view "$PR_NUMBER" --repo "$GH_REPO" --json state,isDraft,reviewDecision,mergeStateStatus
   ```
   Confirm: CI green, **`isDraft` is false** (ship-p8 marked it ready and verified it; if it is still `true`, the handoff is broken — fail this step loudly to the chief of staff rather than continuing), no unresolved review comments. Failures → fix first (intercom-ask the chief of staff) before proceeding.
4. Rename tab: `workflow_rename_tab "${TICKET_ID}: P9 Ready for review ${FEATURE_TAG}"`.

**Default to close — do NOT ask the close-or-iterate question (decision 2026-10-08).**
After your guide, record `DECISION_CLOSE_OR_ITERATE="close"` and surrender. Build mode
always ends with a **PR READY FOR REVIEW** (ship-p8 verified `isDraft=false`); iterate
mode can be started later from the PR link, so there is nothing to ask.

5. **Loose ends — record only, never create tickets (decision 2026-10-08)**:
   1. Read `/tmp/workflow-loose-ends.md` (the path is `LOOSE_ENDS_FILE` in the
      run env if recorded).
   2. If it has entries: print the numbered list in your pane (title | why |
      where) and leave it in the run report.
   3. Do **NOT** create follow-up tracker tickets. Runs never create tracker
      tickets at all. Record
      `FOLLOWUP_DECISION="none"` and `FOLLOWUP_TICKETS=""` in the run env, and name
      the loose ends in the final report so the human can turn them into tickets
      later.

## OUT — append to `/tmp/workflow-run.env`

```
DECISION_CLOSE_OR_ITERATE="close"   # always close in build mode (no ask)
FOLLOWUP_DECISION="none"             # follow-up tickets are never created at wrap-up
FOLLOWUP_TICKETS=""                  # always empty (runs never create tracker tickets)
STAGE_DONE="wrap-up"
STAGE_STATUS="ok"
```

The script appends the P9.4 handoff block to `$WORKTREE/.workflow-handoff.env` and
ends the build run with a **PR READY FOR REVIEW** (iterate mode is started later from the
PR link).

## Surrender protocol (interactive)

1. Append the OUT block to `/tmp/workflow-run.env`.
2. `intercom send` one-liner to the chief-of-staff session (the intercom target in your task file).
3. STOP there — do NOT run `exit` or `kill $PPID` (zellij panes are not auto-closed by exiting; dead panes linger). The script verifies your handoff, closes your pane itself, and takes over.