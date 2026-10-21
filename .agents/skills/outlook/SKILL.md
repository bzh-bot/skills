---
name: outlook
description: >
  Read and act on Outlook on the web (OWA) mail via agent-browser driving the
  user's real Chrome in a specified profile. Use when asked to read/send/triage
  Outlook email, mark messages read, apply the unread filter, bulk-clear an
  inbox, or reply. The Graph API is blocked by M365 conditional access, so mail
  is driven in the browser. The caller passes the Chrome profile and the
  expected signed-in email address; always verify the signed-in account matches
  before acting, and never close the user's OWA tab. Interactive triage
  decisions (draft reply vs add a task vs unsubscribe vs leave) live in the
  calling flow — this skill provides the OWA mechanics only.
allowed-tools: Bash(agent-browser:*), Bash(npx agent-browser:*), Bash(sleep:*), Bash(curl:*), read
---

# Outlook (OWA) mail

Drive Outlook on the web in the user's real Chrome via the `agent-browser` skill.

**Per-account mode (isolated launch):** when the caller runs one browser per
account, do NOT auto-connect to the user's live Chrome. Launch an isolated headed
Chrome per account (`AGENT_BROWSER_SESSION=<account>-<accountId>` +
`--profile ~/.agent-browser-profiles/<account>-<accountId>`, persistent logins)
and verify the signed-in account matches the expected email.
The caller specifies **which Chrome profile** to use and **which signed-in email
address** to expect (the tenant→profile→email mapping is the caller's
responsibility, not this skill's).

> The Graph API device-code flow is **blocked** by M365 conditional access
> (error 53003 — requires a compliant/managed device), so everything is done in
> the browser.

## Golden rules

1. **Always open a NEW tab** for OWA — never navigate the user's existing tabs.
2. **Verify the signed-in account** matches the email address the caller
   specified (folder-pane treeitem shows the address) before reading or acting.
   If the wrong account is signed in, tell the caller and stop — do NOT act on
   the wrong account.
3. **Never close the user's OWA tab.** When you're done, just stop issuing
   agent-browser commands and leave the tab open.
4. **Confirm before sending.** Never send/reply without explicit approval from
   the calling flow; this skill just drafts/opens.

## Setup (once per session)

```bash
# 1. Confirm a debuggable Chrome is up on the required profile (agent-browser "Attach checklist")
curl -s --max-time 2 http://127.0.0.1:9222/json/version >/dev/null && echo READY

# 2. Open OWA inbox in a NEW tab, wait for it
agent-browser --auto-connect --headed open "https://outlook.office.com/mail/"
agent-browser --auto-connect --headed wait --load networkidle
sleep 3
agent-browser --auto-connect --headed snapshot
```

**Verify signed-in account:** the folder-pane treeitem should show the email
address the caller specified. Do not proceed on the wrong account.

## Enable the Reading Pane (do this first)

Turning the reading pane on avoids full-page reloads each time you open an
email; the list stays mounted while the URL becomes `/mail/inbox/id/…`.

- Open the **View** ribbon tab, click the **Reading pane** button, then click
  **"Show on the right"**.
- The flyout items live in a **shadow DOM not exposed to the a11y tree**, so
  click via JS: find `span.label-279` with text "Show on the right", walk up to
  the `menuitemcheckbox`/`BUTTON` ancestor, and `.click()` it.
  ```bash
  agent-browser --auto-connect --headed eval '(() => {
    const els = [...document.querySelectorAll("span.label-279")];
    const hit = els.find(e => /Show on the right/i.test(e.textContent || ""));
    let n = hit; while (n && n.tagName !== "BUTTON" && n.getAttribute("role") !== "menuitemcheckbox") n = n.parentElement;
    if (!n) return "not found";
    n.click(); return "clicked";
  })()'
  ```
- Once on, clicking a list option opens it in `main[aria-label="Reading Pane"]`.
  The message body is the element with `aria-label="Message body"` (tag != MAIN);
  read it with `.innerText`:
  ```bash
  agent-browser --auto-connect --headed eval 'document.querySelector("[aria-label=\"Message body\"]")?.innerText?.slice(0, 4000) ?? "(body not found)"'
  ```

## Unread filter (shadow-DOM flyout)

- Click the **Filter** button, then click the **"Unread"** `menuitemradio` via JS
  (also shadow-DOM): find `span.UagSo` with text "Unread", walk up to the
  `role=menuitemradio` ancestor, `.click()`.
  ```bash
  agent-browser --auto-connect --headed eval '(() => {
    const els = [...document.querySelectorAll("span.UagSo")];
    const hit = els.find(e => /^Unread$/i.test((e.textContent||"").trim()));
    let n = hit; while (n && n.getAttribute("role") !== "menuitemradio") n = n.parentElement;
    if (!n) return "not found";
    n.click(); return "clicked";
  })()'
  ```
- The Filter button label changes **"Filter" → "Unread"** when active.
- **Navigating to `https://outlook.office.com/mail/` RESETS the filter** and
  turns the reading pane off. Prefer staying in-tab; if you must return to the
  inbox root, re-apply both the reading pane and the unread filter.
- **Switching between the Focused and Other tabs also silently drops the
  Unread filter** — rows you then see under Other may already be read. After any
  tab switch, re-apply the unread filter and never count Other-tab rows as unread
  without verifying their read state per row.

## Order: oldest first

Triage the **oldest** unread message first (the user's preferred cadence). OWA
defaults to newest-first (Date ↓), so before triaging change the sort to oldest:

- Click the message-list **Sort** control (or the Date column header) and
  switch to **Date ↑** (oldest on top). The exact control is in the list header
  above the message rows.
- With unread filter + oldest-first sort both applied, triage **top to bottom** —
  that is now oldest → newest.
- Re-applying the filter or reloading can reset the sort; re-check the order
  before resuming.

If the sort control is shadow-DOM/unreachable via the a11y tree, click it via JS
the same way as the reading-pane/unread-filter flyouts (find the label text, walk
up to the clickable ancestor, `.click()`).

## Dismiss blocking overlays

A **Reminders** banner can cover the Filter button. Click **"Dismiss all"** first
before trying to reach Filter.

## Opening an email & reading it

Click the message row (`[role="option"]`) to open it in the reading pane — the
user can glance at the full email. Do **not** rely on the list preview snippet
alone.

Read the body via the `aria-label="Message body"` element (above). The header
(sender/subject/time) is in `main[aria-label="Reading Pane"]`.

## Mark as read (reliably)

**Use the per-row `Mark as read` button** — do **not** use the `Insert` keyboard
shortcut (it toggles read/unread and often doesn't stick; items reappear unread).

```bash
# Snapshot, find the row for <subject>, then the "Mark as read" button near it
agent-browser --auto-connect --headed snapshot
# locate via: sed -n '/<subject>/,+3p' the snapshot, then click @<ref> for "Mark as read"
agent-browser --auto-connect --headed click @<ref>
```

Clicking an option to **open** it does NOT reliably mark it read — always use the
mark-read button for an item you want read.

## Bulk mark-all-as-read

`button "Mark all as read"` marks the whole Inbox (Focused + Other). Safe to use
when all remaining unread are the same noise type (e.g. monitoring digests,
infrastructure health events). Use the snapshot + `click @<ref>` flow.

## Send / reply / draft

- **Reply:** open the message, click **Reply** (or Reply-all), type in the
  composer (`body[aria-label="Message body"]` of the compose surface), and
  **stop** — show the draft to the user and only send after explicit
  confirmation. Send with the Send button (not a keyboard shortcut) to be safe.
- **New message:** click **New mail**, fill To/Subject/body the same way.
- **Drafting only** (no send) is the safe default; the calling flow decides
  whether to send.

## Multiple OWA tabs

The user may have several Outlook tabs open. List with
`agent-browser tab list` and switch with `agent-browser tab t<n>`. Consolidate
on **one** Inbox tab to avoid confusing state across tabs.

## Known flakiness & recovery

After many mark-reads, the message-list `[role="option"]` rows sometimes stop
rendering in the a11y tree (the count shows 0 while the folder still reports
unread). Recover by:

1. Reloading `https://outlook.office.com/mail/`.
2. Re-enabling the **reading pane** (View → Reading pane → Show on the right).
3. Re-applying the **unread filter** (Filter → Unread).

If a snapshot comes back with 0 rows but the folder says "Inbox (N)",
assume this flakiness and recover before declaring inbox zero.

## When you're done

Leave the OWA tab open. Stop issuing agent-browser commands. Report what you
did (counts, actions taken) to the calling flow.