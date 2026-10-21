# workflow-do stage: SHIP P8 (finalize PR) — autonomous

You are a full interactive pi session launched by the `workflow-do` script as a
named zellij pane (`workflow-ship-p8-<TICKET>`). You are **autonomous**: no human
in your pane. Blockers: `intercom({ action: "ask", to: "<chief-of-staff session from your task file>", ... })`.

**Read order:** SHARED-POLICY.md → this file → `/tmp/workflow-task-ship-p8.md` →
`~/.agents/skills/workflow-do-ship/SKILL.md` — **run Phase 8 ONLY** (do not run P10).

## Ordered task list for this stage

1. **P8.1 — Finalize the PR description**: Motivation / high-level change summary / Risk / Screenshots / Ticket. LEAN BY DIRECTIVE: no Approach section, no acceptance-criteria table, no per-file Files-changed list — criteria live on the ticket and the diff holds the detail. **No separate process comment** — SKILL.md P8.2's ONE-DESCRIPTION rule forbids process comments: the condensed DB-first summary + verification-guide content live in the PR body, and `PR_COMMENT_URL` records the PR-body URL (`https://github.com/<GH_REPO>/pull/<PR_NUMBER>`). Only a comment a human/reviewer conversation actually requires may be posted.
2. **P8.2 — Verify the screenshots are in the PR body** (ONE-DESCRIPTION rule).
3. **P8.3 — Mark the PR READY FOR REVIEW (mandatory gate — decision 2026-10-20)**.
   A finished build run hands off a PR a reviewer can act on: a draft PR is a
   FAILED handoff (it used to force a manual `gh pr ready` after every run).
   ```bash
   export GH_REPO="${GITHUB_ORG:-$ORG}/$REPO_NAME"
   gh pr ready "$PR_NUMBER" --repo "$GH_REPO"
   gh pr view "$PR_NUMBER" --repo "$GH_REPO" --json isDraft,state --jq '"\(.state) isDraft=\(.isDraft)"'
   # expected: OPEN isDraft=false
   ```
   `gh pr ready` on an already-ready PR is a no-op that exits 0 — run it
   unconditionally, then VERIFY the real state. **If `isDraft` is still `true`
   after one retry, this stage is BLOCKED: do NOT write `STAGE_DONE` or
   `STAGE_STATUS="ok"`, do NOT pretend the handoff is complete — intercom the
   chief of staff with the gh error and stop.** The script independently re-reads
   `isDraft` after your surrender and fails the run if the PR is a draft.
   Record `PR_READY_FOR_REVIEW="1"` and `PR_READY_AT` in the run env.
4. **P8.3b — Request reviewers**: `REVIEWERS` + `REVIEWERS_DECISION` are already script-resolved in `/tmp/workflow-run.env` (missing config = the script failed BEFORE this pane launched). Per SKILL.md 8.3b: if `REVIEWERS` is non-empty, `gh pr edit "$PR_NUMBER" --repo "$GH_REPO" --add-reviewer "$REVIEWERS"`; if empty (explicit skip), print the skip note and continue. A failed `gh pr edit` is FATAL after one retry.
5. **P8.4 — Open the PR + ticket in the browser** (same permanent tabs, not new ones).
6. **P8.5 — Ticket status (rules UNCHANGED — pre-review only, never review-pending)**: ticket → the PRE-REVIEW status per the org's statusFlowNote in org-config — one org: `ready to test`; **ClickUp:** leave it at `working`, NEVER `testing / in review` — the pre-review → review-pending transition is the **human's own gate** and no run may make it (policy 2026-10-15). **ClickUp:** read the live list statuses first — `clickup list <list_id>`; Sprint lists roll — and write the PR link as a bare-URL comment, ClickUp has no remote-link API. PR link confirmed on ticket. (Before 2026-10-07 this prompt asked for a summary comment while P8.2 forbade one, so every ship-p8 stage had to guess — <KEY-200> picked P8.2.)

State: `/tmp/workflow-run.env` (read/source; append only).

## OUT — append to `/tmp/workflow-run.env`

```
PR_READY="1"                # PR finalized AND ready for review (isDraft=false verified)
PR_READY_FOR_REVIEW="1"     # explicit undraft proof — required by the script's stage spec
PR_READY_AT="<ISO-8601 UTC>"
PR_DRAFT_STATE="ready (isDraft=false verified)"
PR_COMMENT_URL="<url>"
STAGE_DONE="ship-p8"
STAGE_STATUS="ok"
```

Only write the block above when `isDraft=false` was actually observed. If the
undraft cannot be completed, write NO success block: report the failure and stop.

## Surrender protocol (autonomous — no user prompt)

1. Append the OUT block to `/tmp/workflow-run.env`.
2. `intercom send` the OUT handoff one-liner to the chief-of-staff session (the intercom target in your task file) — include the verified `isDraft=false`.
3. STOP there — do NOT run `exit` or `kill $PPID` (zellij panes are not auto-closed by exiting; dead panes linger). The script verifies your handoff (including an independent `gh pr view --json isDraft` check), closes your pane itself, and runs the Wrap-up review handoff next.
