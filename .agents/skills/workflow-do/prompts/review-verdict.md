# workflow-do stage: REVIEW-VERDICT (review mode, final) — interactive, approval gate

You are the **final interactive** stage pane (`workflow-review-verdict-<LABEL>`).
Everything in the findings file is decided; your job is to turn it into a
GitHub review **with an atomic post behind an explicit human gate**. Nothing
posts until the reviewer confirms in this pane.

**Read order:** SHARED-POLICY.md → this file → the task file → the run env → the
FINDINGS_FILE → ~/.agents/skills/workflow-do-review/SKILL.md.

## Ordered task list

1. **Draft the review atomically** from the decisions in the findings file:
   - one inline comment per decided line-comment (file, line, final comment text
     from the walkthrough decisions — polish wording, keep it factual and kind)
   - **Language: plain, clear, brief** — each comment says what the issue is,
     why it matters (motivation), and what to do, in one short read. No jargon
     padding, no boilerplate politeness, no AI-slop phrasing, no essays.
   - the review body: one line per finding, verdict rationale
   - the verdict: **APPROVE** if zero blockers; **REQUEST_CHANGES** if any
     blocker; **COMMENT** if only nits/convention notes
2. **Show the full draft in-pane** — every inline comment and the body — and
   **PARK**. Ask the reviewer: post as drafted / edit / abort. Only on explicit
   confirmation proceed; on abort record `REVIEW_SUBMITTED="0"` and surrender.
3. **Post on confirmation**:
   - inline comments: `POST /repos/$GITHUB_ORG/$REPO_NAME/pulls/$PR_NUMBER/comments`
   - the review: `POST /repos/$GITHUB_ORG/$REPO_NAME/pulls/$PR_NUMBER/reviews`
     with `event=APPROVE|REQUEST_CHANGES|COMMENT` and the body (comments can be
     submitted together with the review — prefer the single-review submission
     carrying all inline comments).
4. **Update EVERY ticket referenced by the PR** (TICKET_IDS in the run env — a
   PR may cover several; past runs closed only the first and left siblings
   open, do not repeat that). Use the org's statusFlow/statusFlowNote in
   $ORG_CONFIG_DIR/org-config.json as the authority for status names, and read the
   **live** statuses before writing one — for ClickUp  the statuses are
   list-scoped and Sprint lists roll (`clickup list <list_id>`); post the review
   link as a bare URL (`clickup comment <task-id> <url>` — no remote-link API):
   - verdict APPROVE → the approved status, and
     comment the review link on each ticket. **Where the tracker has no separate
     approved status (ClickUp today) write NOTHING** — in particular never
     `testing / in review`: that status is the human's review-pending gate, and no
     run may write it (policy 2026-10-15).
   - verdict REQUEST_CHANGES/COMMENT → the denied status (do NOT fall back to
     In Progress where a denied status exists),
     and comment the review link.
5. **This REVIEW run never touches the PR's draft state** — review mode must not run `gh pr ready` or otherwise change a PR's draft state, **including when the PR author is us**. The draft→ready transition belongs to the author's own build/iterate run (`ship-p8` / `build-fix` mark it ready and verify `isDraft=false`, decision 2026-10-20); a reviewer flipping it for someone else's PR would be acting as the author. Read-only inspection is fine
   (`gh pr view … --json isDraft`), writing never is. Leave the draft state exactly as it is and
   say so in the OUT block and the final summary.
6. Final summary in-pane + intercom: verdict, findings posted, ticket updates, and that the PR was
   left exactly as it was — the draft state is the author's/their run's to change.

Never merge. Never push. Never change a PR's draft state in review mode. The author's own iterate run picks up
these findings.

## OUT — append to the run env

```
REVIEW_SUBMITTED="1", REVIEW_VERDICT (APPROVE|REQUEST_CHANGES|COMMENT|ABORTED),
REVIEW_URL, TICKETS_UPDATED,
PR_DRAFT_STATE="untouched — review mode never changes it (the author's build/iterate run owns draft→ready)",
STAGE_DONE="review-verdict", STAGE_STATUS="ok"
```

`PR_READY_MARKED` is gone on purpose: it is not in the script's stage `requires` list (the only
`PR_READY` there is P8's "PR finalized" flag from ship-p8 — a different thing), so nothing reads it.

## Surrender protocol (interactive)

1. Append the OUT block to the run env.
2. `intercom send` the final one-liner to the chief-of-staff session (the intercom target in your task file).
3. STOP — the script closes your pane and the run completes. No closure
   confirmation is asked (the explicit post confirmation at step 2 above is the
   only ask in this stage).