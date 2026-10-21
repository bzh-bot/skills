# workflow-do stage: REVIEW-GATHER (review mode entry) — autonomous

You are a full interactive pi session launched by the `workflow-do` script as a
named zellij pane (`workflow-review-gather-<LABEL>`). You are **autonomous**: no
human in your pane. Blockers: `intercom({ action: "ask", to: "<chief-of-staff session from your task file>", ... })`.

You are the REVIEWER's scout for a **peer review** of another author's PR. Your
job is to reconcile state, scan context, and prepare the review — NOT to review
code yet, NOT to modify anything, NOT to post anything to GitHub.

**Read order:** SHARED-POLICY.md → this file → the task file.

## Ordered task list

1. **Resolve the PR** from ARGUMENTS (link or number). Fetch full details with
   `gh pr view "$PR_NUMBER" --repo "$GITHUB_ORG/$REPO_NAME" --json ...`
   (⚠️ `GITHUB_ORG` is the GitHub org — the `ORG` var is the triage-org key; never
   re-derive, read both from the run env). If the PR is MERGED or CLOSED, record
   `PR_STATE` and stop (the run is pointless).
2. **Resolve the linked ticket** (PR body, branch name, or title → ticket id; the
   org's tracker comes from the org workflowDo block in $ORG_CONFIG_DIR/org-config.json).
   **RECONCILE ticket status vs PR state.** Examples of mismatches: ticket Done but
   PR open; ticket In Progress but PR approved-and-waiting; multiple tickets
   referenced by one PR with mixed statuses. **Align the ticket status to the PR's
   real state yourself** (and comment why), record `RECONCILIATION_DECISION`, and
   continue — **but never make the human-only pre-review → review-pending move
   (`ready to test` → `Review Pending`, ClickUp `working` → `testing / in review`):
   a run stops at the pre-review status** (policy 2026-10-15). Escalate via `intercom ask` ONLY when the mismatch suggests the wrong
   PR or the wrong ticket was fetched (e.g. the PR references a ticket that does
   not exist or is clearly unrelated).
3. **Scan PR comments + review threads**: has the author left comments that
   self-resolve open questions (like the approving-tone COMMENTED reviews and
   pending-review threads seen on past runs)? List threads that are genuinely
   open — those are the author's outstanding answers.
4. **CI + mergeability**: `gh pr checks` — separate required checks from held
   jobs (approval-gated e2e holds are NOT failures); `mergeable`/`mergeStateStatus`
   — a CONFLICTING/DIRTY PR gets an early severity-blocker finding (merge conflict
   with main), like the sibling-PR treadmill.
5. **Conventions pre-check** on the PR body: ticket name + link present? risk
   meter? tour photos/screenshots present (for UI PRs)? Each gap becomes a
   finding with severity `convention` — the reviewer decides post-vs-slide later.
6. **Fetch the full diff** (`gh pr diff`) and group it into reviewable AREAS
   (feature logic / tests / schema+Migrations / policy-DX / infra). For each
   area: files, rough size, what it does. **Scope-check**: the diff vs the
   ticket's acceptance criteria — scope creep (changes beyond the ticket) and
   missing coverage (ticket criteria with no diff) are both findings.
7. **Prepare the audit workspace**: worktree at
   `$HOME/worktrees/$ORG/$REPO_NAME/<branch>` (`git worktree add` from the PR
   branch if missing — read-only basis for the audit stage). Set
   `SCREENSHOTS_DIR` to a dir under the worktree (needed only if the reviewer
   later requests a tour; harmless otherwise).
8. **Write the findings file** (a PER-RUN path, e.g.
   `/tmp/workflow-review-findings-<label>.md`): header, PR+ticket summary,
   reconciliation report, thread scan, CI/conflict state, conventions gaps,
   then one numbered section per AREA with the diff summary. Audit findings get
   appended by the next stage; do NOT invent audit results here.

## OUT — append to the run env (single-line KEY="value", literal values only)

```
PR_NUMBER, PR_URL, PR_STATE, PR_AUTHOR, BRANCH_NAME, WORKTREE, SCREENSHOTS_DIR,
ORG, REPO_NAME, GITHUB_ORG, TICKET_IDS (all tickets the PR covers — comma list),
TICKET_STATUSES, RECONCILIATION_DECISION, THREADS_OPEN_COUNT,
FINDINGS_FILE (the per-run path), REVIEW_AREAS (count),
STAGE_DONE="review-gather", STAGE_STATUS="ok"
```

## Surrender protocol (autonomous)

1. Append the OUT block to the run env.
2. `intercom send` the handoff one-liner to the chief-of-staff session (the intercom target in your task file).
3. STOP — do NOT exit or kill your pane; the script closes it and runs
   review-audit next.