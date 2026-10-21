# workflow-do stage: REVIEW-WALKTHROUGH (review mode) — interactive

You are an **interactive** stage pane (`workflow-review-walkthrough-<LABEL>`) —
the human (the reviewer) works IN this pane. Present, ask, record.

**Read order:** SHARED-POLICY.md → this file → the task file → the run env → the
FINDINGS_FILE → ~/.agents/skills/workflow-do-review/SKILL.md.

## Ordered task list

1. Open with the one-screen summary: PR + ticket(s), reconciliation outcome,
   CI/conflict state, conventions gaps, verification results (tests/coverage),
   total findings by severity.
2. **Decide EVERY finding yourself** (findings file order — areas, then entries within): for each one record LGTM / line-comment / blocker in the findings file, including the suggested comment text for line-comments. Show the diff hunk, the audit's read, the evidence and the severity in-pane as you go, but do NOT ask the user per finding. **Convention findings:** auto-post a comment when a documented convention is clearly violated (missing ticket link, missing risk meter, missing tour photos for a UI PR); let subjective ones slide and record them.
3. **The review-tour question** (ask exactly once, near the end);
   "Do you want an interactive tour of this PR in the browser before the
   verdict?" This is the ONLY place the interactive tour lives — the build flow
   ships screenshots + video only, and never asks about a tour.
   - **Yes** → run the review tour **now, in this pane**: read-only, on the PR's
     branch, for any PR (ours or someone else's). Boot the PR's dev stack if
     needed, then walk the change live and let the human look. **No screenshots,
     no video, no automatic posts** — a human tour is just a tour; if the human
     asks, you may add a PR comment or make a fix on the spot. Procedure:
     `~/.agents/skills/workflow-do-tour/SKILL.md` → "Phase 6 — Review tour".
     Record `REVIEW_TOUR_NEEDED="yes"` and `REVIEW_TOUR_DONE="1"`.
   - **No** → record `REVIEW_TOUR_NEEDED="no"`.
4. After the last finding: record `DECIDED_COUNT`. Then surrender — no closure confirmation is asked (stage-closure prompts were removed).

Do NOT post anything to GitHub in this stage — drafts live in the findings file.

## OUT — append to the run env

```
DECIDED_COUNT, REVIEW_TOUR_NEEDED (yes|no), REVIEW_TOUR_DONE (1 when a tour was run),
STAGE_DONE="review-walkthrough", STAGE_STATUS="ok"
```

## Surrender protocol (interactive)

1. Append the OUT block to the run env.
2. `intercom send` the handoff one-liner to the chief-of-staff session (the intercom target in your task file).
3. STOP — the script closes your pane (and runs the tour next if requested,
   then review-verdict). No closure confirmation is asked.