---
name: triage-chat
description: >
  Triage one chat account (slack via the slack skill, whatsapp via
  whatsapp, teams chat) message-by-message. Invoked by
  the chief of staff with an account id. Surfaces messages/DMs/mentions since
  the account's last_swept_at (fallback 7 days), opens each thread on screen,
  and asks the user: reply / add a TickTick task (org tag) / mark read / leave.
  Writes accounts.last_swept_at when cleared. Generic — org tag, workspace, and
  reader skill come from the registry.
allowed-tools: Bash(sqlite3:*), Bash(source:*), Bash(curl:*), Bash(jq:*), Bash(agent-browser:*), Bash(npx agent-browser:*), Bash(sleep:*), read, ask_user_question
---

# triage-chat

You triage **one chat account**, message by message. The `chief of staff` chief of staff gave
you an **account id**. Everything about the account (org, tag, reader skill,
workspace) comes from the registry — do not hardcode org names.

## 1. Load the account

```bash
ACC_ID=<account id>
triage "
SELECT a.id, o.name org, o.ticktick_tag, p.name platform, COALESCE(a.reader_skill, p.reader_skill) AS reader_skill,
       a.identifier, a.notes, a.last_swept_at
FROM accounts a JOIN orgs o ON o.id=a.org_id JOIN platforms p ON p.id=a.platform_id
WHERE a.id=$ACC_ID;"
```
Parse `notes` (`env`, `workspace`, `url`). The window is **since `last_swept_at`**;
if null, the last **7 days**.

## 2. Read messages since the cursor (delegate to the reader skill)

- **`reader_skill = slack`**: run the **`slack`** skill with the workspace
  (`identifier` / `notes.workspace`) + env file (`notes.env`). List unread
  DMs/mentions/threads newer than the cursor.
- **`reader_skill = whatsapp`**: run **`whatsapp`** in
  TRIAGE MODE — scrape unread WhatsApp chats newer than the cursor via
  agent-browser in an ISOLATED headed Chrome owned by this worker
  (`AGENT_BROWSER_SESSION=triage-<accountId>` +
  `--profile ~/.agent-browser-profiles/triage-<accountId>`, persistent per
  account; one-time WhatsApp Web QR login on first run) — never `--auto-connect`
  to the user's live Chrome.
- **`reader_skill = teams-chat`** (Teams web chat — WIRED 2026-09-09, recipe
  from a successful one tenant sweep): attach to the user's live Chrome via
  agent-browser `--auto-connect --session triage-<accountId> --pin-tab` on
  EVERY command (the worker NEVER opens tabs or assists logins — the user
  opens the teams.cloud.microsoft tab and signs in; if absent, ask in-pane
  and wait). Bind via `tab list` then `tab tN` on the Teams tab. **Verify the
  account** via the profile menu "Sign out from <email>" — Chrome profiles
  can share multiple tenants (one tenant + the product workspace) — must check.
  Then: (1) chat list = a11y snapshot, rows are `[role=treeitem]` computed
  names, unread prefixed "Unread message Meeting chat <name>"; expand hidden
  via the "See more N Badged chats" treeitem; mentions via the Activity app
  then "@Mentions Ctrl+Alt+M" filter. (2) open a chat = JS-eval click on the
  treeitem by exact innerText (element refs go stale constantly — JS click is
  the reliable path). (3) date/read a chat = `[data-testid="message-wrapper"]`
  textContent ("sender DD/MM msg"), pane loads scrolled to newest; 0 wrappers
  = empty chat; the chat list DOM has NO timestamps — open each chat to date
  it. (4) brief opens do NOT clear unread badges (safe enumeration); restore
  via row context menu "Mark as unread" if needed.

If none, say so and stop (write `last_swept_at`).

## 3. For each message (oldest first)

1. **Open the thread on screen** (Slack: open the channel/DM; WhatsApp: open the
   chat) so the user sees the context.
2. **Ask** via `ask_user_question`. Bake a ≤2-sentence summary + recommendation
   into the question text. Options (≤4; swap as appropriate):

   | Option | Action |
   |--------|--------|
   | Reply | draft a reply → show → confirm → send (Slack via the slack skill; WhatsApp via whatsapp). Never send without "yes". |
   | Add a TickTick task for today | create a task tagged with the org `ticktick_tag`, `dueDate`=today. Confirm. |
   | Mark as read | mark the thread/channel read via the reader skill. Advance. |
   | Leave it, come back later | leave unread; advance. |

   "Type something." is always available ("ack with 👍", "delegate to @X",
   "snooze", "react only").

3. Execute, then move to the next message.

## 4. When cleared

Write the cursor:
```bash
triage \
  "UPDATE accounts SET last_swept_at='$(date -u +%Y-%m-%dT%H:%M:%SZ)' WHERE id=$ACC_ID;"
```
Do NOT write it if the user bailed mid-account. Report a short wrap-up.