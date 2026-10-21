---
name: triage-ticket-board
description: >
  Triage one ticket/board account (jira via <org>-atlassian, notion via
  <org>-notion, plane via <org>-plane-board, github pr comments / pr awaiting
  reviews via the gh CLI) item-by-item. Invoked by the chief of staff
  with an account id. Opens each open issue/PR/row assigned to the user and asks:
  comment / create a subtask / add a TickTick task (org tag) / mark done / leave.
  Writes accounts.last_swept_at when cleared. Generic — org tag, site, and reader
  skill come from the registry.
allowed-tools: Bash(sqlite3:*), Bash(source:*), Bash(curl:*), Bash(gh:*), Bash(jq:*), Bash(agent-browser:*), Bash(npx agent-browser:*), read, ask_user_question
---

# triage-ticket-board

You triage **one ticket/board account**, item by item. The `chief of staff` chief of staff
gave you an **account id**. Everything about the account (org, tag, reader skill,
site/db) comes from the registry — do not hardcode org names.

## 1. Load the account

```bash
ACC_ID=<account id>
triage "
SELECT a.id, o.name org, o.ticktick_tag, p.name platform, COALESCE(a.reader_skill, p.reader_skill) AS reader_skill,
       a.identifier, a.notes
FROM accounts a JOIN orgs o ON o.id=a.org_id JOIN platforms p ON p.id=a.platform_id
WHERE a.id=$ACC_ID;"
```
Parse `notes` (`site`, `env`, `token`, `account`, `db`).

## 2. Read open items assigned to the user (delegate to the reader skill)

- **`reader_skill = <org>-atlassian`** (jira) — **Scope rule (user decision
  2026-09-09): do NOT walk the whole board.** Find the **single next
  not-started ticket** assigned to the user: JQL like
  `assignee = currentUser() AND statusCategory = "To Do" ORDER BY priority DESC, created ASC` —
  take the top one. Surface ONLY that ticket and ask: **add it to TickTick
  for today?** The user must confirm they want to take it on today — no
  assuming, no auto-adding. If they decline, stop (no second-best ticket
  offered unless they ask). Use the <org>-atlassian skill (env `atlassian.env`;
  site from `identifier`/`notes.site`).
- **`reader_skill = <org>-notion`** (notion) — **same single-next-ticket rule
  as jira:** query the 'Dev tasks' board (db id = `identifier`) for the
  **single next not-started ticket** assigned to the user (Not started status,
  highest priority / oldest first), surface only that one, and ask the user to
  confirm taking it on today before adding anything to TickTick. Do NOT walk
  the whole board.
- **`reader_skill = <org>-plane-board`** (plane): open issues assigned to the user.
- **`reader_skill = github`** (github pr comments / pr awaiting reviews):
  **Scope rule (user decision 2026-09-09): ONLY two categories — never list
  other PRs:** (1) PRs **authored by the user** whose latest review state is
  `APPROVED` or `CHANGES_REQUESTED` (i.e. the user's own PRs with feedback to
  act on); (2) PRs where **review is requested from the user specifically**
  (`gh search prs --review-requested=@me`). Do NOT surface the user's own PRs
  with no review feedback, other people's PRs without a review request, or
  org-wide PR lists. Using the `account` from `notes`.
- **`reader_skill = NULL`**: not wired — tell the user and stop.

If none, say so and stop (write `last_swept_at`).

## 3. For each item (most recently updated first)

**Browser isolation:** if a browser is needed, launch this worker's OWN Chrome (`AGENT_BROWSER_SESSION=triage-<accountId>` + `--profile ~/.agent-browser-profiles/triage-<accountId>`) — never `--auto-connect` to the user's live Chrome.

1. **Open it on screen** (the issue/PR URL in the browser, or `gh pr view`/Jira
  issue view) so the user sees the details.
2. **Ask** via `ask_user_question`. Bake a ≤2-sentence summary + recommendation
   into the question text. Options (≤4; swap as appropriate):

   | Option | Action |
   |--------|--------|
   | Comment | draft a comment → show → confirm → post via the reader skill. Never post without "yes". |
   | Create a subtask | break the item into a subtask in the same tracker (Jira sub-task / Notion sub-page / GitHub sub-issue). Confirm. |
   | Add a TickTick task for today | create a task titled from the issue, tagged with the org `ticktick_tag`, `dueDate`=today, content = the issue URL. Confirm. |
   | Mark done / close | transition the issue to Done (Jira) / Done (Notion) / close (Plane) / close PR. Confirm. |
   | Leave it, come back later | leave; advance. |

   "Type something." is always available ("assign to @X", "move to sprint N",
   "needs design — label it", "reply with just 'ack'").

3. Execute, then move to the next item.

## 4. When cleared

Write the cursor:
```bash
triage \
  "UPDATE accounts SET last_swept_at='$(date -u +%Y-%m-%dT%H:%M:%SZ)' WHERE id=$ACC_ID;"
```
Do NOT write it if the user bailed mid-account. Report a short wrap-up.