---
name: workflow-do-ship
version: 1.5.0
description: "workflow-do sub-skill — phases P8 + P10 (Finalize PR; Merge & Close). P8 runs in the build flow; P10 runs in iterate mode (possibly a later session, invoked with the PR link). Loaded by a workflow-do worker session the script launches as a named zellij pane (pi --name), coordinated via pi-intercom. Not invoked directly."
---

# Ship agent — workflow-do-ship (Phases P8 + P10)

> **`workflow-do` worker sub-skill.** You are a full pi session launched by the
`workflow-do` script as a **named zellij pane** (`pi --name workflow-ship-...`),
NOT a subagent tool call. Your launch prompt tells you which phase(s) to run
and inlines the handoff. Load this skill by reading its SKILL.md first.

**Your session name is in your launch prompt** (e.g. `workflow-p8/p10-<TICKET>`).
Every report/question goes to the **chief-of-staff session** — the session that launched this
cage. Your task file prints its intercom target (`ORCHESTRATOR_SESSION` in the run env,
supplied by the chief of staff at kickoff). Pass `--name` once; the name persists.

## Handoff contract

> **v7 script model:** the sequencer is the deterministic script
> `~/.agents/skills/workflow-do/workflow-do.ts`. Your OUT vars are appended to
> `/tmp/workflow-run.env` (append-only) plus a `STAGE_DONE` block; your pane is
> launched and closed by the script. Read `~/.agents/skills/workflow-do/SHARED-POLICY.md`
> -> "Stage Orchestration (script model, v7)" for the full contract, and your stage
> prompt file (`~/.agents/skills/workflow-do/prompts/`) for the exact surrender steps.

The script spawns you **once per run, one phase per spawn**:

- **Build mode → P8 (finalize):**
- **Iterate mode → P10 (merge), after the approval gate passes:**

Iterate mode may be a **later session** (invoked with `workflow-do <PR>` after the
review gate) — P8 and P10 spawns do not share a session, so never rely on
intercom routing across the build→iterate boundary (P10 may run in a later
session — you are spawned fresh by whoever needs you); the handoff text +
`/tmp/workflow_env.sh` + `$WORKTREE/.workflow-handoff.env` carry the state.

You are **autonomous**: no human in your pane. Run to completion, then send your OUT handoff to the chief-of-staff session via `intercom send` (target: the intercom target in your task file / `ORCHESTRATOR_SESSION` in the run env).

**IN — variables in your `task` prompt:**
- the `workflow-do-tour` OUT handoff: `TICKET_ID`, `TICKET_URL`, `FEATURE_TAG`, `PR_NUMBER`, `PR_URL`, `ORG`, `REPO_NAME`, `WORKTREE`, `BRANCH_NAME`, `INTEGRATION_BRANCH`, `SOURCE_REPO`, `WORKFLOW_*` env, `SCREENSHOTS_DIR`, the brief + acceptance criteria
- `GITHUB_ORG` (the GitHub org slug) — define the repo slug once at the top of the stage:
  `export GH_REPO="${GITHUB_ORG:-$ORG}/$REPO_NAME"` and use **`$GH_REPO`** in every `gh` / `gh api` /
  GraphQL call. `$ORG` is the org KEY (`mdg`) and is only correct for worktree paths —
  `gh … --repo "$ORG/$REPO_NAME"` 404s (learned the hard way).

**OUT (after P8):** PR description updated, PR **marked READY FOR REVIEW and verified** (`gh pr ready`, then `isDraft=false` re-read;  a finished run never hands off a draft), ticket set to the **PRE-REVIEW** status (per the org's statusFlowNote in org-config: one org calls it `ready to test`, a ClickUp org is left at `working` — the review-pending transition is **human-only**, never a run's), PR link confirmed on ticket. **OUT (after P10, iterate mode):** PR merged (or merge-queued + confirmed merged — do NOT delete the worktree yet, the `workflow-do-post` subagent needs `$WORKTREE/screenshots/` for the email); ticket set to "done"; PR link on ticket. (Pane lifecycle is script-owned — you never open or close panes.)

## Operating rules

- **Read the shared policy first:** `~/.agents/skills/workflow-do/SHARED-POLICY.md` (see its FIRST ACTION note). Do this before any phase task.
- Run only the phase(s) the script named in your `task` (P8 from build mode, or P10 from iterate mode). Do not run the other.
- **Task tracking:** `TaskList`, then `TaskCreate` for only the substeps of the phase(s) you were asked to run (`P8.*` and/or `P10.*`); mark `in_progress`/`completed` as you go. Prefix every sub-step `TaskCreate` subject with the phase emoji (🔐 P0, 🔍 P1, ❓ P2, 📦 P3, 💻 P4, 🧪 P5, 📸 P6, 🖥️ P7, 🚀 P8, ⏳ P9, ✅ P10, 📡 P11, 🔄 P12, 📧 P13) — emojis no longer go in zellij tab names; they live on the pi-task subjects.
- Rename your zellij tab at each transition: `workflow_rename_tab "${TICKET_ID}: P<n> <Verb> ${FEATURE_TAG}"`.
- Access verification (P0) was already completed by `workflow-do-prebuild`; do not re-run it.
- **No human in your pane.** If you hit a blocker (merge conflict, merge-queue failure, branch-protection missing approval), intercom-ask the chief of staff (`intercom({ action: "ask", to: "<chief-of-staff session from your task file>", message: ... })`) and await its reply — the chief of staff surfaces it to the human and relays the answer.
- P10.4 worktree cleanup is **deferred to `workflow-do-post`** (after the email, so screenshots survive). You only close the lazygit pane.
- When done, return your **OUT** handoff summary.

## Shared policy

**FIRST ACTION before any phase work:** read
`~/.agents/skills/workflow-do/SHARED-POLICY.md` and follow it for the entire run
(Hard Prerequisites, DB-First Thinking Order, implementation style pointers,
Zellij tab naming, pane management). It applies to every workflow-do worker —
this file no longer duplicates it.
## Your phases

## Phase 8 — Finalize PR

**→ TaskUpdate: P8 → in_progress**

**→ Print: "Phase 8: Finalizing PR..."**
```bash
workflow_rename_tab "${TICKET_ID}: P8 Finalize ${FEATURE_TAG}"
```

### 8.1 Update PR Description

**→ TaskUpdate: P8.1 → in_progress**

Update the PR body with final implementation details, screenshots, and testing guide:

```bash
cat << 'EOF' > /tmp/pr-body-final.md

<the video goes FIRST in the body with NO heading and NO duration label — just the asset URL
(and the music attribution line when the licence requires it), inserted directly above
`## Motivation`>

<asset URL>

🎵 <music attribution line — only when the licence requires it (CC-BY / Zapsplat free tier)>

## Motivation

<final problem statement — the problem and why now, 2-3 sentences>

## Summary of changes

<HIGH LEVEL ONLY: one or two lines per layer. The reviewer reads the diff for detail.>

- **Database:** <e.g. one additive migration: new column + FK, no data migration>
- **Backend:** <e.g. one job + claim table + email template>
- **Frontend:** <e.g. new error state on the report page>  (omit for backend-only changes)

> ⚠️ Do NOT write any of these in a PR body: an `## Approach` / "implementation plan"
> section, an acceptance-criteria table or block, a per-file "Files changed" list,
> a `## How to Test` / `## How to Verify` / verification-log section, a "verified in
> this pass" note, or per-helper/per-table detail. Acceptance criteria live on the
> TICKET; the PR body is the lean "what changed" description and the diff is the
> detail. (User directives 2026-09-30: lean PR bodies, then no how-to-test/
> how-to-verify/files-changed/verified-in-this-pass sections at all.)

## Risk Assessment

<🟢|🟡|🔴> — pick exactly ONE dot and justify it in a short paragraph:
- 🟢 **Low** — additive change; no schema, RLS, auth, or money-path changes
- 🟡 **Medium** — behavior change, new schema without data migration, or non-trivial backend logic
- 🔴 **High** — migrations touching existing rows, RLS/permission changes, payment/billing paths, or destructive operations

<risk paragraph: what could break, blast radius, rollback path, and what was verified locally to de-risk it>

## Screenshots

<attach screenshots if frontend>

## Ticket

<ticket URL>
EOF

gh pr edit "$PR_NUMBER" --repo "$GH_REPO" --body-file /tmp/pr-body-final.md
```

**The video block is not optional when P7.8 attached one.** `gh pr edit --attach`
appends the asset at the bottom of the body; P7.8 records the resulting
`VIDEO_URL` and `MUSIC_ATTRIBUTION` in the run env. Carry both into the template
above — do not drop the video and do not duplicate it: ONE bare video (asset URL) at the very
top, before `## Motivation`, with no `## Video tour` heading and no duration label (user
directive 2026-09-30). If the run set `VIDEO_SKIP_NOTE`, omit the
block and leave the note in the run env.

(The script pre-verifies `PR_NUMBER`/`ORG`/`REPO_NAME` before this stage launches — no in-pane guard needed.)

**→ TaskUpdate: P8.1 → completed**

### 8.2 Verify Screenshots Are in the PR Body (ONE-DESCRIPTION RULE)

**→ TaskUpdate: P8.2 → in_progress**

Screenshots were captured, annotated, and appended to the **PR body** in Phase 7.6. The PR body is the SINGLE description of the final state: implementation summary, test instructions, screenshots and review outcome all live there — never as separate process comments. Verify:

```bash
# Missing screenshots → fold any old screenshot comments into the body, then delete them:
bash ~/.agents/skills/workflow-do/scripts/fold-pr-body.sh "$GH_REPO" "$PR_NUMBER"

# If the screenshots are missing entirely (e.g. Phase 7 upload failed), re-upload from
# $SCREENSHOTS_DIR using the Phase 7.6 workflow — appending to the body, not commenting.
```

If the screenshots are missing entirely (e.g. Phase 7 upload failed), re-upload from `$SCREENSHOTS_DIR` using the Phase 7.6 workflow — appending to the body, not commenting. **No process comments on the PR**: implementation summary / screenshots / review-outcome comments must be folded into the body and deleted; only human discussion stays in comments.

**⚠️ Author-safe folding (learned the hard way).** `fold-pr-body.sh` only folds and
deletes the run's OWN comments and bots, and now reports how many pattern-matching
comments by *other* humans it skipped. Never delete a comment authored by a human
reviewer — the pattern includes the bare word `review`, so a reviewer writing
"review passed" matched it and was one `gh api -X DELETE` away from losing their
comment. If the script reports skipped human comments, leave them and say so in the
handoff.

**→ TaskUpdate: P8.2 → completed**

### 8.3 Mark the PR READY FOR REVIEW (mandatory gate)

**→ TaskUpdate: P8.3 → in_progress**

**A finished build run hands off a PR a reviewer can act on — it must NOT be a draft
(decision 2026-10-20, superseding the 2026-10-08 "build never marks ready" rule).** A
draft PR at the end of the run forced a manual `gh pr ready` after every single run, which
is what made the handoff look complete while it was not.

```bash
export GH_REPO="${GITHUB_ORG:-$ORG}/$REPO_NAME"   # owner/repo, not the org KEY

# Idempotent: on an already-ready PR gh prints "already ready" and exits 0.
gh pr ready "$PR_NUMBER" --repo "$GH_REPO"

# Verify the REAL state — a gh exit code is not proof.
gh pr view "$PR_NUMBER" --repo "$GH_REPO" --json state,isDraft \
  --jq '"\(.state) isDraft=\(.isDraft)"'
# expected: OPEN isDraft=false
```

- `isDraft=false` → record `PR_READY_FOR_REVIEW="1"` (+ `PR_READY_AT`) in the run env and
  continue.
- `isDraft=true` after one retry → **BLOCKED**: do NOT write `STAGE_DONE` /
  `STAGE_STATUS="ok"`, do not report a complete handoff. Intercom the chief of staff with the gh
  error and stop. The orchestrator independently re-reads `isDraft` after the stage
  surrenders (`ensurePrReadyForReview()` in `workflow-do.ts`) and fails the run loudly if
  the PR is still a draft.

**→ TaskUpdate: P8.3 → completed**

### 8.3b Request Reviewers (script-resolved)

**→ TaskUpdate: P8.3b → in_progress**

The **script** resolves reviewer config before this stage launches and appends it to the run env:

- `REVIEWERS="<logins>"` + `REVIEWERS_DECISION="requested"` — apply it now (below).
- `REVIEWERS=""` + `REVIEWERS_DECISION="skip"` — empty-string entry in the org's `reviewers.json` = explicit skip; print `→ Empty reviewers entry for $GH_REPO — explicit skip` and continue.
- Resolution FAILED → the script never launched this pane (FATAL before the pane spins; fix `$ORG_CONFIG_DIR/reviewers.json` and relaunch with `--resume`).

Apply the resolved reviewers:

```bash
if [ -n "$REVIEWERS" ]; then
  gh pr edit "$PR_NUMBER" --repo "$GH_REPO" --add-reviewer "$REVIEWERS"
  echo "→ Reviewers requested on PR #$PR_NUMBER: $REVIEWERS"
else
  echo "→ Empty reviewers entry for $GH_REPO — explicit skip"
fi
```

If `gh pr edit --add-reviewer` fails (reviewer not a collaborator, removed login), print the error, retry once after re-reading `REVIEWERS` from the run env, and if it still fails treat it as **FATAL** — do not continue to 8.4 with an unrequested reviewer set; report the failure via the OUT block instead.

**→ TaskUpdate: P8.3b → completed**

### 8.4 Open PR and Ticket in Browser for Human Review

**→ TaskUpdate: P8.4 → in_progress**

Re-point the run's PERMANENT ticket + PR tabs (SHARED-POLICY "Persistent Ticket +
PR Tabs") — same tabs, not new ones — so the human can review both. They have
been open since prebuild and must still be open when this stage ends:

```bash
PR_URL=$(gh pr view "$PR_NUMBER" --repo "$GH_REPO" --json url -q .url)
ensure_tab pr "$PR_URL"
[ -n "${TICKET_URL:-}" ] && ensure_tab ticket "$TICKET_URL"
```

```
→ Print: "📖 PR is now open in Chrome for review: $PR_URL"
→ Print: "📋 Ticket is also open: $TICKET_URL"
→ Print: "  The PR is now READY FOR REVIEW (isDraft=false, verified). Review the diff, CI status, and files changed."
```

**→ TaskUpdate: P8.4 → completed**

### 8.5 Update Ticket Status

**→ TaskUpdate: P8.5 → in_progress**

Set the ticket to the tracker's **PRE-REVIEW** status per the org's statusFlow/statusFlowNote in org-config — a finished run **never** writes the review-pending status: the pre-review → review-pending transition is the **human's own gate** and no run may make it (policy 2026-10-15). **One org:** `ready to test`. **ClickUp orgs:** the pre-review state is not a distinct status — **leave the ticket at `working` and NEVER write `testing / in review`**; the human moves it to `testing / in review` when they hand the PR to the reviewer. Read the **live** statuses of the task's list first with `~/.agents/skills/clickup/scripts/clickup list <list_id>` (Sprint lists roll, so a name the list no longer carries silently no-ops — see workflow-do-prebuild SKILL.md §1.2); the token comes from `$ORG_CONFIG_DIR/<org>/env/clickup.env`. Verify any write with `clickup get <task-id>`.

**Verify the PR link is on the ticket.** It should have been written in Phase 3.12. If that step failed (or if the PR URL changed), re-attempt it now using the same tracker-specific procedure from 3.12 with the final PR URL:

```bash
PR_URL=$(gh pr view "$PR_NUMBER" --repo "$GH_REPO" --json url -q .url)
```

The ticket must reference the PR so reviewers can jump straight from the tracker to the code.

**→ TaskUpdate: P8.5 → completed**

**→ TaskUpdate: P8 → completed. Print: "✅ Phase 8 complete. PR #<number> finalized, marked READY FOR REVIEW (isDraft=false verified), PR link on ticket. Surrendering — the script runs the p9-lite review handoff next."**

---


## Phase 10 — Merge & Close (only after human says "merge" / "continue" / "lgtm")

**→ TaskUpdate: P10 → in_progress**

**→ Print: "Phase 10: Merging and closing..."**

```bash
workflow_rename_tab "${TICKET_ID}: P10 Merge ${FEATURE_TAG}"
```

### 10.1 Final CI Check

**→ TaskUpdate: P10.1 → in_progress**

Re-verify CI is still green (time may have passed since approval):

```bash
gh pr checks "$PR_NUMBER"
```

If checks have gone red (e.g. base branch moved), sync and fix before merging. The sync is a **merge** (`git merge origin/<base>`) — never a rebase, never a force-push: either would rewrite the SHAs the PR's reviews/approvals sit on.

**Also re-verify review-thread hygiene immediately before merging** (defense in depth — review-state
requires this, but a base move, a late reviewer comment or a new bot review can reopen the question
between the gate and the merge). Every conversation must be answered AND resolved, or explicitly
parked with a rationale the user acknowledged:

```bash
gh api graphql -f query="query(\$owner:String!,\$name:String!,\$num:Int!){repository(owner:\$owner,name:\$name){pullRequest(number:\$num){reviewThreads(first:100){totalCount nodes{isResolved path comments(first:1){nodes{author{login} createdAt}}}}}}}}" \
  -F owner="$GITHUB_ORG" -F name="$REPO_NAME" -F num="$PR_NUMBER" \
  | jq -r '.data.repository.pullRequest.reviewThreads | "unresolved=\([.nodes[]|select(.isResolved==false)]|length) of \(.totalCount)\([.nodes[]|select(.isResolved==false)]|map("\n  OPEN \(.path)")|join(""))"'
```

- Any thread that appeared AFTER the review-state gate must be dispositioned
  (reply + resolve, or parked with a recorded rationale) before merging — never merge past a conversation
  nobody answered.
- A thread resolved without a visible reply is incomplete: post the reply first, then resolve.
- If the count is non-zero and the open threads are NOT the parked-with-rationale set, STOP: report
to the chief of staff/user instead of merging.

**→ TaskUpdate: P10.1 → completed**

### 10.1b Draft check — NEVER merge a draft; undraft first

**→ TaskUpdate: P10.1b → in_progress**

`gh pr merge` refuses a draft PR. A finished build/iterate run is supposed to hand
the PR over ready (ship-p8 / build-fix undraft + verify, decision 2026-10-20); this
step is the merge-time guard for an older/manual PR.

```bash
DRAFT=$(gh pr view "$PR_NUMBER" --repo "$GH_REPO" --json isDraft -q .isDraft)
echo "isDraft=$DRAFT"
```

- `false` → continue to 10.2.
- `true` → run `gh pr ready "$PR_NUMBER" --repo "$GH_REPO"`, re-read `isDraft`, record
  `PR_READY_FOR_REVIEW="1"`, and continue only when it is `false`.
- Still `true` after one retry → **STOP**: report the failure to the chief of staff/human and
  do not merge; do not pretend the merge gate passed.

**→ TaskUpdate: P10.1b → completed**

### 10.2 Verify Approval

**→ TaskUpdate: P10.2 → in_progress**

**Stacked-PR warning (warning + explicit choice; never an auto-block)** — if `STACKED_ON_PR`
is set, or `PR_BASE_BRANCH` != `EVENTUAL_INTEGRATION_BRANCH`, this PR's base is **another
feature branch**, so merging here does NOT land the work on the integration branch
(`develop`): the parent PR must merge first and this PR must then be retargeted. Print this
plainly before merging (parent PR number + its state) and make sure the human's
`MERGE_DECISION` was taken with that fact on screen; then record `RETARGET_REQUIRED="1"` in
the OUT block **and** append a loose end naming the parent PR, so the retarget survives the
run. (Learned 2026-10-06, <KEY-145>: PR #294 was merged into its stacked base while parent
#293 was still OPEN/DIRTY, leaving `develop` with none of the work and nobody tracking the
retarget.) Once the parent PR lands and this PR is retargeted onto the integration branch,
bring the new base in with a **merge** (`git merge origin/$INTEGRATION_BRANCH`) — never a
rebase, never a force-push; the PR's reviewed SHAs must survive.

Confirm the PR has at least one approval:

```bash
gh pr view "$PR_NUMBER" --repo "$GH_REPO" --json reviewDecision -q .reviewDecision
# Expected: "APPROVED"
```

If branch protection requires approvals and none exist yet, tell the user and wait.

**Stale-review override (requires user confirmation):** when the outstanding
CHANGES_REQUESTED predates the latest fix-round, CI is green, and there are 0
unresolved review threads, surface an explicit `"merge now (stale-review override)"
option to the user (in-pane `ask_user_question`) with the stale-review evidence
shown (review date vs fix-round date, CI state, thread count). Never auto-merge on
it — an explicit human confirmation is what makes this safe.

**→ TaskUpdate: P10.2 → completed**

### 10.3 Merge (or Add to Merge Queue)

**→ TaskUpdate: P10.3 → in_progress**

Detect whether the repo uses a **merge queue**. If it does, `gh pr merge` will fail with "The merge strategy for main is set by the merge queue" — in that case, add the PR to the merge queue via GraphQL and **poll until the merge completes** before proceeding to cleanup.

**Step 1: Attempt direct merge:**

```bash
gh pr merge "$PR_NUMBER" --repo "$GH_REPO" --squash --delete-branch 2>/dev/null
```

(The script pre-verifies `PR_NUMBER`/`ORG`/`REPO_NAME` before this stage launches — no in-pane guard needed.)

If this succeeds, the PR is merged — proceed to 10.4.

**Step 2: If direct merge fails, check for merge queue:**

```bash
MERGE_RESULT=$(gh pr merge "$PR_NUMBER" --repo "$GH_REPO" --squash --delete-branch 2>&1)
if echo "$MERGE_RESULT" | grep -q "merge queue"; then
  echo "Repo uses merge queue — adding PR to queue..."

  PR_NODE_ID=$(gh api graphql -f query='
  query {
    repository(owner: "'$ORG'", name: "'$REPO_NAME'") {
      pullRequest(number: '$PR_NUMBER') { id }
    }
  }' --jq '.data.repository.pullRequest.id' 2>/dev/null)

  gh api graphql -f query="
  mutation {
    enqueuePullRequest(input: {pullRequestId: \"$PR_NODE_ID\"}) {
      clientMutationId
    }
  }" 2>/dev/null

  echo "PR added to merge queue. Monitoring merge status..."
fi
```

**Step 3: Poll until merge completes (CRITICAL — do NOT delete branch or cleanup until merge is confirmed):**

```bash
MAX_WAIT=600  # 10 minutes max
WAITED=0
while [ "$WAITED" -lt "$MAX_WAIT" ]; do
  PR_STATE=$(gh pr view "$PR_NUMBER" --repo "$GH_REPO" --json state,mergedAt --jq '.state + ":" + (.mergedAt // "null")' 2>/dev/null)

  if echo "$PR_STATE" | grep -q "MERGED"; then
    echo "✅ PR #$PR_NUMBER has been merged!"
    break
  fi

  if echo "$PR_STATE" | grep -q "CLOSED"; then
    echo "⚠️ PR #$PR_NUMBER was closed without merging. Check merge queue status."
    break
  fi

  # Check merge queue entry state
  QUEUE_STATE=$(gh api graphql -f query='
  query {
    repository(owner: "'$ORG'", name: "'$REPO_NAME'") {
      mergeQueue {
        entries(first: 5) { nodes { state pullRequest { number } } }
      }
    }
  }' --jq '.data.repository.mergeQueue.entries.nodes[] | select(.pullRequest.number == '$PR_NUMBER') | .state' 2>/dev/null)

  echo "Merge queue state: $QUEUE_STATE (waited ${WAITED}s)"

  if [ "$QUEUE_STATE" = "MERGED" ]; then
    echo "✅ PR #$PR_NUMBER merged via merge queue!"
    break
  fi

  if [ "$QUEUE_STATE" = "BLOCKED" ] || [ "$QUEUE_STATE" = "FAILED" ]; then
    echo "🚨 Merge queue entry $QUEUE_STATE for PR #$PR_NUMBER"
    break
  fi

  sleep 30
  WAITED=$((WAITED + 30))
done

if [ "$WAITED" -ge "$MAX_WAIT" ]; then
  echo "⚠️ Merge queue timeout after $MAX_WAIT seconds. The PR may still merge later."
  echo "Do NOT delete the worktree or branch — the merge is still pending."
fi
```

**⚠️ CRITICAL: Do NOT run `git worktree remove` or `git branch -D` until the merge is confirmed.** The previous version of this skill deleted the branch immediately after `gh pr merge`, which closed the PR before the merge queue could process it. The branch must survive until the merge is confirmed as complete.

**→ TaskUpdate: P10.3 → completed**

### 10.4 Clean Up Worktree + Docker Container

**→ TaskUpdate: P10.4 → in_progress**

**⚠️ DEFER WORKTREE REMOVAL until AFTER Phase 13 (Email Summary).** The annotated screenshots live in `$WORKTREE/screenshots/` and the Phase 13 email embeds them inline as base64 CIDs. If you remove the worktree now, Phase 13 can't include the screenshots (GitHub user-attachment URLs are auth-gated 404 via curl, so they can't be re-downloaded). Keep the worktree (and its `screenshots/` dir) around until the email is sent, then remove it as the very last step. (past-ticket friction note.)

```bash
cd ~
git -C "$SOURCE_REPO" worktree remove "$WORKTREE" --force
git -C "$SOURCE_REPO" branch -D "$BRANCH_NAME"
git -C "$SOURCE_REPO" worktree prune

# Full Docker cleanup — removes container, DinD volumes, Chrome profile, state files.
# No remnants left — clean slate for the next ticket.
echo "Container will be cleaned up when you exit zellij (the td function handles it)."
```

### 10.4.1 Screenshot Hosting

No cleanup needed — screenshots were uploaded via the agent-browser upload script to GitHub's `user-attachments` CDN and are permanently embedded in the **PR body** (see Phase 7.6 / the ONE-DESCRIPTION RULE). Do NOT delete or expire them.

**→ TaskUpdate: P10.4 → completed**

### 10.5 Update Ticket to Done

**→ TaskUpdate: P10.5 → in_progress**

Set the ticket to the tracker's "done" / "completed" state. **List-scoped trackers (ClickUp-style):** merged maps to `validation / merged` (`shipped` stays manual — set only once the change is released/verified); as always, read the **live** list statuses first (`~/.agents/skills/clickup/scripts/clickup list <list_id>`) and pass that exact name, then verify with `clickup get <task-id>`.

**Ensure the PR link is on the ticket.** This is the final chance to guarantee the ticket references the merged PR. If Phase 3.12 failed to write it, write it now using the same tracker-specific procedure from 3.12 with the final PR URL:

```bash
PR_URL=$(gh pr view "$PR_NUMBER" --repo "$GH_REPO" --json url -q .url)
```

A done ticket must link to the merged PR so the team can always trace a closed ticket back to the code that resolved it. Log a warning if this still fails, but do not block the rest of the run on it.

**→ TaskUpdate: P10.5 → completed**

### 10.6 Clean Up Zellij Panes (by name)

**→ TaskUpdate: P10.6 → in_progress**

Pane lifecycle is **script-owned** — you never open or close panes; the script closes your stage pane after verification. The lazygit and nvim-review panes no longer exist (removed 2026-09-06), and dev servers / DB run as `bg_run` background tasks, not panes.

**Do NOT stop the dev-server / DB background tasks yet** — those stay up through Phase 11.

**→ TaskUpdate: P10 → completed. Print: "✅ Phase 10 complete. PR merged, ticket done. Proceeding to Phase 11."**
**→ TaskUpdate: P11 → in_progress**

**→ TaskUpdate: P10.6 → completed**

---

