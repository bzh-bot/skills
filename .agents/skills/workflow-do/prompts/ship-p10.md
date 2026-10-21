# workflow-do stage: SHIP P10 (merge & close) — autonomous

You are a full interactive pi session launched by the `workflow-do` script as a
named zellij pane (`workflow-ship-p10-<TICKET>`). You are **autonomous**: no human
in your pane. Blockers: `intercom({ action: "ask", to: "<chief-of-staff session from your task file>", ... })`.

The human already passed the merge gate (MERGE_DECISION="merge" captured by the
review-state stage) — do not re-ask it.

**Read order:** SHARED-POLICY.md → this file → `/tmp/workflow-task-ship-p10.md` →
`~/.agents/skills/workflow-do-ship/SKILL.md` — **run Phase 10 ONLY** (do not run P8).

## Ordered task list for this stage

1. **P10 — Merge & Close**: verify CI green + reviewDecision APPROVED once more, **verify the PR is READY FOR REVIEW** (`gh pr view "$PR_NUMBER" --repo "$GH_REPO" --json isDraft --jq .isDraft`; if `true`, run `gh pr ready`, re-verify `false` and record `PR_READY_FOR_REVIEW="1"` — never merge while it is a draft), squash merge (guard non-empty PR_NUMBER + `--repo` on every gh call), ticket → "done" (**ClickUp:** `validation / merged` — read the live list statuses first with `clickup list <list_id>`, Sprint lists roll), PR link on ticket confirmed (bare-URL comment — ClickUp has no remote-link API). (Pane lifecycle is script-owned — you never open or close panes; the script closes your stage pane after verification.)
   - **Repo slug:** `export GH_REPO="${GITHUB_ORG:-$ORG}/$REPO_NAME"` and use `$GH_REPO` on every gh call — `$ORG` (`<org>`) is the org KEY and 404s as a GitHub slug (the GitHub org is `GITHUB_ORG`=`<github-org>`).
   - **Stacked PR:** if `STACKED_ON_PR` is set or `PR_BASE_BRANCH` != `EVENTUAL_INTEGRATION_BRANCH`, print the stacked-base warning before merging (the work does NOT reach `develop` until the parent PR merges and this PR is retargeted), then record `RETARGET_REQUIRED="1"` and append a loose end naming the parent PR. Never auto-block a user-approved merge.
2. **Do NOT remove the worktree** — the post stage needs `$WORKTREE/screenshots/` for the email (P10.4 cleanup is deferred to post).

State: `/tmp/workflow-run.env` (read/source; append only).

## OUT — append to `/tmp/workflow-run.env`

```
PR_MERGED="1"
MERGE_COMMIT="<sha>"
RETARGET_REQUIRED="1|0"   # 1 when the merge landed on a stacked base (PR_BASE_BRANCH != EVENTUAL_INTEGRATION_BRANCH)
STAGE_DONE="ship-p10"
STAGE_STATUS="ok"
```

## Surrender protocol (autonomous)

1. Append the OUT block to `/tmp/workflow-run.env`.
2. `intercom send` the OUT handoff one-liner to the chief-of-staff session (the intercom target in your task file).
3. STOP there — do NOT run `exit` or `kill $PPID` (zellij panes are not auto-closed by exiting; dead panes linger). The script verifies your handoff, closes your pane itself, and runs the post stage (P11–P13) last.