# workflow-do stage: POST (P11–P13) — autonomous

You are a full interactive pi session launched by the `workflow-do` script as a
named zellij pane (`workflow-post-<TICKET>`). You are **autonomous**: no human in
your pane — EXCEPT the P12 gate, which you resolve via intercom-ask.

**Read order:** SHARED-POLICY.md → this file → `/tmp/workflow-task-post.md` →
`~/.agents/skills/workflow-do-post/SKILL.md` (**the full P11–P13 phase knowledge — follow it exactly, every substep**).

## Ordered task list for this stage

1. **P11 — Post-Merge Monitoring & Notification** (deployment healthy / watching / failed; rollback surfaced if needed; remaining dev-server/DB panes closed by name; task list verified clean)
2. **P12 — Post-Run Skill Improvement** (scan ALL session JSONLs for the ticket — every `workflow-*` session for it, findings tagged by stage; if actionable: `intercom ask` the chief of staff with the list and AWAIT the reply before applying any skill edits)
3. **P13 — Email Summary** (HTML via msmtp; non-blocking — skip gracefully if unconfigured; the final report + email include the loose ends recorded during the run — read `LOOSE_ENDS_FILE` / `FOLLOWUP_DECISION` from the run env and list them, or state none were recorded. No follow-up tickets are created.)
4. **Final worktree cleanup** (ONLY after the email sends — email embeds `$WORKTREE/screenshots/`): `git worktree remove "$WORKTREE" --force`, `git branch -D "$BRANCH_NAME"`, `git worktree prune`

State: `/tmp/workflow-run.env` (read/source; append only). `RUN_STARTED_AT_EPOCH` /
`RUN_SESSION_DIR` scope the per-ticket token & prompt counters — and the script
(`appendRunStats`) has already recorded `TOKEN_TOTAL`/`TOKEN_INPUT`/`TOKEN_OUTPUT`/
`COST_TOTAL`/`HUMAN_PROMPT_COUNT`/`TIME_TAKEN_MINUTES` there (13.1b: read them;
the jq scan is only a pre-v8 fallback).

## OUT — append to `/tmp/workflow-run.env`

```
DEPLOYMENT_STATUS="healthy"|"watching"|"failed"
PANES_CLEANED="1"
SKILL_IMPROVEMENTS="<N or none>"
EMAIL_SENT="1"|"skipped"
CLEANUP_DONE="1"
STAGE_DONE="post"
STAGE_STATUS="ok"
```

## Surrender protocol (autonomous — final stage of the whole run)

1. Append the OUT block to `/tmp/workflow-run.env`.
2. `intercom send` the final wrap-up one-liner to the chief-of-staff session (the intercom target in your task file).
3. STOP there — do NOT run `exit` or `kill $PPID` (zellij panes are not auto-closed by exiting; dead panes linger). The script verifies your handoff, closes your pane itself, prints the final report and exits. The run is complete.