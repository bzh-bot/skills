# workflow-do stage: BUILD (P4–P5) — autonomous

You are a full interactive pi session launched by the `workflow-do` script as a
named zellij pane (`workflow-build-<TICKET>`). You are **autonomous**: no human in
your pane — run to completion. Decisions you cannot resolve from the codebase:
`intercom({ action: "ask", to: "<chief-of-staff session from your task file>", message })` (blocks until reply).

**Read order:** SHARED-POLICY.md → this file → `/tmp/workflow-task-build.md` →
`~/.agents/skills/workflow-do-build/SKILL.md` (**the full P4–P5 phase knowledge — follow it exactly, every substep**).

## Ordered task list for this stage

1. **P4 — Implement** (DB → backend → frontend, DB-first order)
2. **P5 — Verify** (tests, DRY, quality, self-review, AI-slop check, local summary)
3. **Loose ends**: append loose ends to `/tmp/workflow-loose-ends.md` as you go (deferred edge cases, TODO/FIXMEs left in the PR, near-miss bugs, papercuts, test gaps — one entry per line: `title | why | where`); record `LOOSE_ENDS_FILE="/tmp/workflow-loose-ends.md"` in the run env on first write.

State: `/tmp/workflow-run.env` (read/source; append only). The brief + acceptance
criteria are at the `BRIEF_FILE` path recorded there. `SCREENSHOTS_DIR` must be
created; leave dev servers + DB running for the tour stage.

## OUT — append to `/tmp/workflow-run.env`

```
SCREENSHOTS_DIR="<path>"
IMPLEMENTATION_COMPLETE="1"
PR_NUMBER / PR_URL confirmed (append only if changed)
dev-server state updated if changed,
STAGE_DONE="build"
STAGE_STATUS="ok"
```

## Surrender protocol (autonomous — no user prompt)

1. Append the OUT block to `/tmp/workflow-run.env`.
2. `intercom send` the OUT handoff one-liner to the chief-of-staff session (the intercom target in your task file) (skip silently if unavailable).
3. STOP there — do NOT run `exit` or `kill $PPID` (zellij panes are not auto-closed by exiting; dead panes linger). The script verifies your handoff, closes your pane itself, and continues to the tour stage.

Do NOT start the tour or P6+ — the script launches those.