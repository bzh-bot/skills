# workflow-do stage: BUILD-FIX (fix round, P4–P5 re-run) — autonomous

You are a full interactive pi session launched by the `workflow-do` script as a
named zellij pane (`workflow-build-fix-<TICKET>`). You are **autonomous**: no human
in your pane. Blockers: `intercom({ action: "ask", to: "<chief-of-staff session from your task file>", ... })`.

**Read order:** SHARED-POLICY.md → this file → `/tmp/workflow-task-build-fix.md` →
`~/.agents/skills/workflow-do-build/SKILL.md` (re-run P4–P5 scoped to the fix list).

## Ordered task list for this stage

1. **Read the confirmed fix list** at the `FIX_LIST_FILE` path recorded in `/tmp/workflow-run.env` (every entry user-approved in review-state's per-finding walkthrough — apply EXACTLY those, nothing else). The `## Replies` / `## Skipped` sections carry the reply-only and skipped decisions — post the replies after the fixes.
2. **P4 — Implement fixes** (scoped; keep DB-first order where relevant). If the fix list includes a merge conflict with the base branch, resolve it with `git merge origin/<base>` — never a rebase, never a force-push (it would invalidate the PR's reviews).
3. **P5 — Verify** (tests, lint, typecheck, DRY, self-review; push).
4. **Replies + threads**: for every fix-list and reply-list entry, reply on its review thread describing what changed (with the commit) or the answer to the reviewer, then resolve the thread (`gh pr-review` or the resolveReviewThread GraphQL mutation). Skipped items stay open unless the reviewer resolves them.
5. **Note UI impact**: if anything user-visible changed, record `UI_CHANGED="1"` (the script will re-run the tour); else `UI_CHANGED="0"`.
6. **Mark the PR READY for review (mandatory — decision 2026-10-20)**: a fix round must never hand the PR back as a draft, so after the fixes are pushed (CI may still be running):
   ```bash
   export GH_REPO="${GITHUB_ORG:-$ORG}/$REPO_NAME"
   gh pr ready "$PR_NUMBER" --repo "$GH_REPO"
   gh pr view "$PR_NUMBER" --repo "$GH_REPO" --json isDraft,state --jq '"\(.state) isDraft=\(.isDraft)"'
   # expected: OPEN isDraft=false
   ```
   `gh pr ready` on an already-ready PR is a no-op that exits 0. Verify the real
   state: **if `isDraft` is still `true` after one retry, this stage is BLOCKED** —
   do NOT write `STAGE_DONE`/`STAGE_STATUS="ok"`; intercom the chief of staff with the gh
   error and stop. The script independently re-reads `isDraft` after surrender and
   fails the run if the PR is a draft. Record `PR_READY_FOR_REVIEW="1"`.
7. **Loose ends**: append loose ends to `/tmp/workflow-loose-ends.md` as you go (near-miss bugs spotted while fixing, deferred edge cases, test gaps — one entry per line: `title | why | where`); record `LOOSE_ENDS_FILE="/tmp/workflow-loose-ends.md"` in the run env on first write.

State: `/tmp/workflow-run.env` (read/source; append only).

## OUT — append to `/tmp/workflow-run.env`

```
FIXES_PUSHED="1"
UI_CHANGED="1"|"0"
PR_READY_FOR_REVIEW="1"   # gh pr ready done AND isDraft=false verified — required OUT var
PR_DRAFT_STATE="ready (isDraft=false verified)"
FIX_SUMMARY="<one line>"
STAGE_DONE="build-fix"
STAGE_STATUS="ok"
```

## Surrender protocol (autonomous)

1. Append the OUT block to `/tmp/workflow-run.env`.
2. `intercom send` the fix summary one-liner to the chief-of-staff session (the intercom target in your task file).
3. STOP there — do NOT run `exit` or `kill $PPID` (zellij panes are not auto-closed by exiting; dead panes linger). The script verifies your handoff, closes your pane itself, and re-runs review-state (plus tour if UI changed).