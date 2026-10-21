---
name: workflow-do-review
description: >
  Deep knowledge for the workflow-do review mode (peer review of another
  author's PR). Loaded by the review-gather, review-audit, review-walkthrough,
  and review-verdict stage panes. Covers the review procedure: state
  reconciliation, the audit checklists (security, correctness, AI slop, DRY,
  coverage), the per-finding walkthrough gates, verdict rules, and ticket-status
  mapping. Not invoked directly — use the workflow-do skill in review mode.
metadata:
  version: "1.3.0"
---

# Workflow-do Review — the peer-review procedure

Reviewing someone else's PR in the workflow-do cage, as a peer reviewer. The
review is an **audit of work in progress**: our job is to determine whether the
PR is ready, held to the same bar as our own builds (the P5 verify conventions
of workflow-do-build apply). Review-only: never merge, never push, never
modify code. Findings posted become the author's iterate-round input.

## Principles

- **Full review, as if it were our own code** — tests must run, coverage must
  be good, conventions must be present. A read-only skim is not a review.
- **Every decision is the reviewer's** — stage agents draft; the human decides
  per finding at the walkthrough, and the GitHub post is atomic behind an
  explicit gate.
- **Reconciliation first** — a PR whose ticket state disagrees with reality gets
  fixed or flagged before review effort is spent.
- **Findings are specific** — file + line + evidence + suggested wording. No
  "this seems off" comments.
- **Plain language** — every finding, comment, blocker, and nit: plain,
  human wording that says **what** the issue is, **why** it matters (the
  motivation — what breaks or gets harder), and **what to do**, briefly and to
  the point. No jargon padding, no boilerplate politeness, no AI-slop phrasing
  ("Additionally, it is worth noting…"), no essays — a working engineer should
  grasp each comment in one read. Example shape: “The port moved in config.toml
  but useDocusealSettings still reads the old default, so local dev hits a dead
  endpoint — update the default or read from config.”

## Task tracking (same convention as the implement flow)

At stage start: `TaskList`, then `TaskCreate` for the stage's substeps only —
mark `in_progress`/`completed` as you go. Prefix every sub-step subject with the
review phase emoji (🔍 review-gather, 🧪 review-audit, 🗣️ review-walkthrough,
⚖️ review-verdict). Never create tasks for another stage's steps.

## Stage contracts (short form — prompts carry the full details)

1. **review-gather** — reconcile ticket(s) vs PR (mismatch → align the ticket to
   the PR state, record it, and continue; escalate only a wrong-PR/wrong-ticket
   pairing);
   scan author self-resolving comments vs genuinely open threads; CI (required
   checks vs held jobs) and merge-conflict state (conflicts are early
   blockers); conventions pre-check (ticket name + link in the PR body, risk
   meter, tour photos for UI PRs); group the diff into areas; scope-check diff
   vs ticket acceptance criteria.
2. **review-audit** — worktree bootstrap (deps + codegen before typecheck);
   full local verification (lint, typecheck, tests, coverage); then the four
   passes per area: security / correctness / AI slop / DRY-quality.
3. **review-walkthrough** — decide every finding yourself: LGTM / line-comment /
   blocker; convention gaps: auto-post clear violations, slide the rest; the
   review-tour question (runs the read-only tour on demand).
4. **review-verdict** — atomic draft (inline comments + body + verdict), park,
   post on confirmation, update ALL referenced tickets. **Review mode never touches
   the draft state** — no `gh pr ready` here, even when the author is us; the
   author's own build/iterate run owns draft→ready (`ship-p8` / `build-fix` mark it
   ready and verify `isDraft=false`, decision 2026-10-20), and another author's PR is
   never touched either.

## The four audit passes

| Pass | Look for |
|---|---|
| Security | auth/authz gaps, injection, RLS/tenant scoping, secrets in diff, data exposure |
| Correctness | edge cases, missing validation, race conditions, does it do what the ticket says — no more, no less |
| AI slop | generated phrasing, useless/over-formal comments, defensive dead code, hallucinated APIs, unrequested scope |
| DRY/quality | duplication, missed reuse, naming, house style per the repo's AGENTS.md |

Severity scale: **blocker** (must fix before merge — broken tests, security
hole, conflict with main, wrong behavior) · **line-comment** (should fix or
justify — quality, design, coverage gap) · **nit** (optional polish) ·
**convention** (missing PR-body risk meter, missing tour photos, ticket link
absent — the reviewer decides post-vs-slide).

## The review tour (optional, interactive)

The **only** interactive tour lives here. The build flow ships screenshots + video
and never tours. When the walkthrough asks and the human says yes, run the tour:

- **Read-only.** Any PR, including other authors'. Never push, never merge, never
  change code — unless the human asks for an on-the-spot fix.
- **No artifacts.** No before/after screenshots, no video — those belong to the
  build flow (and already exist for our own PRs).
- **Boot the stack** from the PR branch in the worktree if it is not already up.
- **Walk it live** — per-criterion, BEFORE vs AFTER, in the cage's script-owned
  headed browser. Let the human look; re-demonstrate on request.
- **Nothing is posted** unless the human asks for a PR comment; then post exactly
  what they asked, nothing more. Record `REVIEW_TOUR_DONE="1"`.
- Full procedure: `~/.agents/skills/workflow-do-tour/SKILL.md` → "Phase 6 — Review tour".

## Verdict rules

- Any blocker → **REQUEST_CHANGES**.
- Zero blockers, only line-comments/nits → **APPROVE** (nits go as comments;
  approval does not require perfection).
- Only convention notes, nothing else → **COMMENT**.
- Verdict is drafted by the agent, confirmed by the human, posted atomically.

## Ticket status mapping (after the verdict posts)

| Verdict | Board target (per the org's statusFlow/statusFlowNote in org-config) |
|---|---|
| APPROVE | the approved status (one org maps it to `Review Approved`) — review link as ticket comment; **where the tracker has no separate approved state (ClickUp today) write NOTHING** — a run must never write `testing / in review` (human-only) |
| REQUEST_CHANGES / COMMENT | the denied status (one org maps it to `Review Denied`, another to `working`) — review link as ticket comment |

**List-scoped trackers (ClickUp-style):** both targets are list-scoped and sprint lists roll, so read the
**live** statuses first (`~/.agents/skills/clickup/scripts/clickup list <list_id>`; see the
prebuild skill §1.2) and pass the exact name. Read the live mapping for that list before writing:
APPROVE → **no status write** when the tracker has no separate approved state; `testing / in review`
is human-only (a run never writes it; the human's review-pending gate);
REQUEST_CHANGES/COMMENT → `working` (the denied state). Post the review link as a **bare URL** with
`clickup comment <task-id> <url>` — ClickUp has no remote-link API — and verify each status
write with `clickup get <task-id>`.

One PR can cover several tickets (multi-ticket PRs are common): update **every**
ticket in TICKET_IDS, not just the primary — a past run closed only the first
and left siblings stale in the tracker.

## Compose with iterate

Findings posted by this review are the author's input: their `workflow-do
iterate` run presents each finding one by one, their build-fix applies the
approved ones, threads get replied + resolved. After a fix round their run
parks awaiting re-review — it asks nothing and never merges; the ticket goes back
to the pre-review status in the org's config (`ready to test` in one org, left at `working` in another — never `testing / in
review`) and the merge gate reopens only on a fresh approval
of the new head. Nothing here needs to nudge or poll — the requested-changes flag
carries the wait.