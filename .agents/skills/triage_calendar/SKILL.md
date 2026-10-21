---
name: triage-calendar
description: >
  Triage one calendar account (outlook / teams calendar via the outlook skill;
  google calendar not yet wired) event-by-event. Invoked by the chief of staff
  with an account id. Covers the CURRENT week only (Mon-Sun, user directive
  2026-09-14). Opens every event of the week on screen, one by one, and asks
  the user: accept / decline / tentative / leave — then ensures each accepted
  event exists in TickTick, anchored on its start time (dueDate = start, end
  time in the title, org tag). Writes accounts.last_swept_at when done.
  Generic — org tag, Chrome profile, and reader skill come from the registry.
allowed-tools: Bash(sqlite3:*), Bash(jq:*), Bash(agent-browser:*), Bash(npx agent-browser:*), Bash(sleep:*), read, ask_user_question
---

# triage-calendar

You triage **one calendar account**, event by event. The `chief of staff` chief of staff gave
you an **account id**. Everything about the account (org, tag, reader skill,
profile) comes from the registry — do not hardcode org names.

## 1. Load the account

```bash
ACC_ID=<account id>
triage "
SELECT a.id, o.name org, o.ticktick_tag, p.name platform, COALESCE(a.reader_skill, p.reader_skill) AS reader_skill,
       a.identifier, a.notes, a.last_swept_at
FROM accounts a JOIN orgs o ON o.id=a.org_id JOIN platforms p ON p.id=a.platform_id
WHERE a.id=$ACC_ID;"
```
Parse `notes` (`key: value;` → map). You need `reader_skill`, `ticktick_tag`,
and for OWA the `profile` (alias from `$ORG_CONFIG_DIR/env/chrome-profiles.env`) + expected signed-in email (`identifier`).

## 2. Read the events of the current week (delegate to the reader skill)

- **`reader_skill = outlook`**: run the **`outlook`** skill with the browser
  binding the chief of staff gave you (the shared walk instance: `--auto-connect
  --session triage-inboxes-<label> --pin-tab`, live Chrome, never your own
  browser) with the account's expected email — but on the **calendar** view
  (`https://outlook.office.com/calendar`). It snapshots upcoming event buttons;
  parse the events of the **CURRENT week only** (Mon–Sun — user directive
  2026-09-14; never a rolling 7-day window). Skip only canceled events — walk
  EVERY other event of the week one by one, including already-accepted ones
  (re-confirm with the user, do not silently skip).
- **`reader_skill = NULL`** (google calendar, not wired): tell the user and stop.

List existing TickTick tasks once up front (all projects + inbox, see the
`ticktick` skill) so accepted events never get duplicate tasks. Always print a
quick non-interactive overview of the week first, then walk the events one by
one (step 3). If the week has no events at all, say so and stop (write
`last_swept_at`).

## 3. For each event of the current week (soonest first)

1. **Open it on screen** (click the event in the calendar view) so the user sees
   the details (time, organizer, Teams link, attendees).
2. **Ask** via `ask_user_question`. Bake a ≤2-sentence summary + a recommendation
   into the question text. Options (≤4; swap as appropriate):

   | Option | Action |
   |--------|--------|
   | Accept | RSVP Accept via the calendar UI in the browser (or keep the existing acceptance) — and **ensure the TickTick task for it** (user directives 2026-09-14): create if missing — `dueDate` = the event START time (the task anchors on the start), time range in the title, org `ticktick_tag`; skip if a matching task already exists. NEVER accept a meeting without a TickTick task. NEVER send `startDate` — the TickTick Open API collapses it into `dueDate`, anchoring the task on the wrong time. Advance. |
   | Decline | RSVP Decline. Advance. |
   | Tentative | RSVP Tentative. Advance. |
   | Add a reminder (TickTick task) | create a TickTick task: "Meeting: <title> <time>", tagged with the org `ticktick_tag`. Follow the ticktick skill's **Calendar events as tasks** rule: `dueDate` = the event START time, end time in the title (e.g. "Meeting: <title> 14:00–15:00" due at 14:00). Confirm. |
   | Leave it | do nothing; advance. |

   "Type something." is always available ("move to another day", "ask <organizer>
   to reschedule", "block focus time before it").

3. Execute, then move to the next event of the week.

## 4. When done

Write the cursor:
```bash
triage \
  "UPDATE accounts SET last_swept_at='$(date -u +%Y-%m-%dT%H:%M:%SZ)' WHERE id=$ACC_ID;"
```
Leave the calendar tab open. Report a short wrap-up to the caller.