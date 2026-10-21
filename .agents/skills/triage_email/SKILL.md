---
name: triage-email
description: >
  Triage one email account (gmail via the gmail-web skill, outlook mail via
  the outlook skill) item-by-item. Invoked by the chief of staff with an account id. Opens
  each unread email (oldest first) on screen, shows a summary + recommendation,
  and asks the user what to do: mark as read / add a TickTick task for today
  (tagged with the account's org ticktick_tag) / unsubscribe / draft a reply /
  leave it. Writes accounts.last_swept_at when the account is cleared. Generic
  — no org names hardcoded; the org tag, Chrome profile, and reader skill come
  from the registry.
allowed-tools: Bash(sqlite3:*), Bash(jq:*), Bash(curl:*), Bash(agent-browser:*), Bash(npx agent-browser:*), Bash(sleep:*), read, ask_user_question
---

# triage-email

You triage **one email account**, item by item. The `chief of staff` chief of staff gave you
an **account id**. Everything about the account (org, tag, reader skill, profile,
URL) comes from the registry — do not hardcode org names.

## 1. Load the account

```bash
ACC_ID=<account id>
triage "
SELECT a.id, o.name org, o.ticktick_tag, p.name platform, COALESCE(a.reader_skill, p.reader_skill) AS reader_skill,
       a.identifier, a.notes, a.last_swept_at
FROM accounts a JOIN orgs o ON o.id=a.org_id JOIN platforms p ON p.id=a.platform_id
WHERE a.id=$ACC_ID;"
```
Parse `notes` (`key: value;` → map). You need: `reader_skill`, `ticktick_tag`,
and for OWA the `profile` (alias from `$ORG_CONFIG_DIR/env/chrome-profiles.env`) + `url`; for gmail the `env` file.

## 2. Read unread emails (delegate to the reader skill)

- **`reader_skill = outlook`** (OWA: outlook mail): run the **`outlook`** skill
  with the account's `profile` + expected signed-in email (`identifier`). It
  opens OWA in a new tab, enables the reading pane, filters to **unread**,
  sorts **oldest first**, and verifies the signed-in account. It owns all the
  OWA mechanics (shadow-DOM clicks, reliable mark-as-read, etc.).
- **`reader_skill = gmail-web`** (the ONLY Gmail reader — gws was removed 2026-09-09, never use a `gws` CLI): run the **`gmail-web`** skill in TRIAGE MODE, attaching to the user's live Chrome with `--auto-connect` (user-authorized), pinned session `triage-<accountId>`, NEVER command other tabs, NEVER close the browser. **The worker NEVER opens Chrome tabs and NEVER performs or assists logins — the user is responsible for opening the tab and signing in.** If the account's tab is not open or not signed in, ASK THE USER IN-PANE to open the mailbox tab in their Chrome and log in themselves; wait, then bind to that tab (`agent-browser tab bind`). Do NOT launch any Chrome, do NOT `open --new-tab`, do NOT fetch credentials — no exceptions. Once bound: verify the signed-in account matches `identifier`, search `is:unread`, and open each thread. (Gmail web is newest-first — oldest-first isn't reliably available here.)
- **`reader_skill = NULL`**: the platform isn't wired — tell the user and stop.

Item window: **unread only**; prefer **oldest first** where the reader supports it (outlook does; gmail-web is newest-first). If none, say so and stop (write `last_swept_at` since the account is already clear).

## 3. For each unread email (oldest first)

1. **Open it on screen** so the user can glance at the full email — do NOT rely
   on the list preview snippet. (OWA: click the row per the `outlook` skill.
   Gmail: open the thread per the `gmail-web` skill.)
2. **Ask** via `ask_user_question`. Bake a **≤2-sentence summary + a
   recommendation with reasoning** into the *question text* (not as separate
   prose before the question). Default options (≤4; swap one for "Draft a
   reply" when the email clearly needs a reply):

   | Option | Action |
   |--------|--------|
   | Mark as read | OWA: per-row "Mark as read" button (never the Insert shortcut). Gmail: mark read via the `gmail-web` skill's flow. Advance. |
   | Add a TickTick task for today | create a TickTick task: title from subject, tagged with the account's `ticktick_tag`, `dueDate`=today (all-day). Confirm. |
   | Unsubscribe | find the unsubscribe mechanism (body link / List-Unsubscribe header / native affordance), show it, confirm, then open in a new tab (https) / draft a blank mailto / click the button; archive the message. If none found, fall back to "create a filter to skip sender". |
   | Leave it, come back later | OWA: re-mark **unread** (opening marked it read) so it stays in the unread view. Gmail: leave as-is. Advance. |
   | Draft a reply | (swap in when a reply is warranted) draft → show → confirm → send (never send without "yes"). |

   `ask_user_question` always appends a "Type something." row for custom actions
   ("reply with just 'OK'", "snooze", "delegate to X", "archive").

3. **Execute** the chosen action immediately, then move to the **next oldest**
   unread email.

**Fast exit**: if the user says "inbox clear" (or any equivalent — "inbox
 done", "all read", "I cleared it") at ANY point — stop the per-item walk
immediately, write `last_swept_at`, send the wrap-up intercom, and stop. Do not
verify each remaining row, do not ask anything further for that inbox.

## 4. When the account is cleared

When the user has decided on the last unread email (or the inbox was already
empty), write the cursor:

```bash
triage \
  "UPDATE accounts SET last_swept_at='$(date -u +%Y-%m-%dT%H:%M:%SZ)' WHERE id=$ACC_ID;"
```

Do NOT mark `last_swept_at` if the user bailed mid-account.

## Notes

- Never hardcode org names, tags, profiles, or URLs — use the account row.
- Leave the user's mail tab open when done; stop issuing browser commands.
- Report a short wrap-up (started N unread → ended 0; tasks created; etc.) back
  to the caller.