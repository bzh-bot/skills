---
name: ticktick
org: personal
description: Add and manage tasks in the TickTick todo list for $TICKTICK_ACCOUNT via the TickTick Open API v1. Use when the user asks to add a task/todo, create a reminder, list projects, or otherwise interact with their TickTick account.
---

# TickTick

Manage the TickTick todo list for **$TICKTICK_ACCOUNT** using the TickTick Open API v1.

## Auth

All requests use a Bearer access token, read from the `TICKTICK_TOKEN`
environment variable (do NOT hardcode the token in this file):

```
Authorization: Bearer $TICKTICK_TOKEN
```

`TICKTICK_TOKEN` is expected in the environment (the usual shape is a private env
file sourced from your shell rc). If it is unset, tell the user to open a new shell
or source that file.

Base URL: `https://api.ticktick.com/open/v1`

## Add a task

The main operation. `POST /open/v1/task` with a JSON body.

```bash
curl -s -X POST "https://api.ticktick.com/open/v1/task" \
  -H "Authorization: Bearer $TICKTICK_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Buy milk"
  }'
```

Common body fields:

| Field       | Type   | Notes                                                                 |
|-------------|--------|----------------------------------------------------------------------|
| `title`     | string | Required. The task title.                                            |
| `content`   | string | Free-text notes/description.                                         |
| `projectId` | string | Target list/project. Omit to use the inbox (default list).           |
| `dueDate`   | string | Due date, ISO 8601 with offset, e.g. `2026-07-15T09:00:00+0000`.     |
| `isAllDay`  | bool   | `true` for an all-day task.                                          |
| `priority`  | int    | `0` none, `1` low, `3` medium, `5` high.                             |
| `startDate` | string | ISO 8601 with offset (same format as `dueDate`).                     |
| `reminders` | array  | e.g. `["TRIGGER:P0DT9H0M0S"]` (RFC 5545 triggers).                   |

Note: TickTick expects date offsets like `+0000` (no colon), e.g. `2026-07-15T09:00:00+0000`.

### Add to a specific project

Get project IDs first (see below), then pass `projectId`:

```bash
curl -s -X POST "https://api.ticktick.com/open/v1/task" \
  -H "Authorization: Bearer $TICKTICK_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Ship release",
    "content": "cut v1.2 and tag",
    "projectId": "6115cca88f088ae943307ba6",
    "priority": 5,
    "dueDate": "2026-07-15T17:00:00+0000"
  }'
```

## List projects (to find projectId)

```bash
curl -s -H "Authorization: Bearer $TICKTICK_TOKEN" \
  https://api.ticktick.com/open/v1/project
```

Returns an array of `{ id, name, color, ... }`. Known projects on this account include:
the default list plus named lists (list names are user data — read them live, don't hardcode).

## Get a task

`GET /open/v1/project/{projectId}/task/{taskId}`

```bash
curl -s -H "Authorization: Bearer $TICKTICK_TOKEN" \
  "https://api.ticktick.com/open/v1/project/{projectId}/task/{taskId}"
```

## Complete a task

`POST /open/v1/project/{projectId}/task/{taskId}/complete`

```bash
curl -s -X POST \
  -H "Authorization: Bearer $TICKTICK_TOKEN" \
  "https://api.ticktick.com/open/v1/project/{projectId}/task/{taskId}/complete"
```

## Update a task

`POST /open/v1/task/{taskId}` with a JSON body. Include `id` and `projectId` in the body along with the fields to change.

## Delete a task

`DELETE /open/v1/project/{projectId}/task/{taskId}`

## Timezones and dates (IMPORTANT — read before answering "what's due today")

The account owner lives in **Montreal (`America/Montreal`, = `America/Toronto`)**, currently
UTC−4 (EDT). Always resolve "today" in Montreal local time, not UTC. Note the local
calendar date is often one day *behind* the UTC date late at night (e.g. 9:32 PM Jul 11
Montreal = 01:32 Jul 12 UTC).

```bash
TZ="America/Montreal" date "+%A, %B %-d, %Y %-I:%M %p %Z"   # get local now
```

### How dates are stored on this account

- The API returns `dueDate`/`startDate` as UTC (`...+0000`). You MUST convert to
  `America/Montreal` before deciding which local day a task falls on.
- **All-day tasks** (`isAllDay: true`, and most undated-looking daily tasks) are stored as
  **`YYYY-MM-DDT04:00:00.000+0000`**. `04:00Z` = **midnight Montreal (EDT)**, so that date's
  *date portion* IS the intended Montreal day. i.e. `2026-07-12T04:00:00+0000` means the
  **July 12** all-day bucket in Montreal. Just read the date part for all-day tasks.
- **Watch for inconsistent entries**: some tasks are saved with `T00:00:00.000+0000` instead
  of `T04:00:00`. `00:00Z` = **8:00 PM the *previous* day in Montreal**. So a task showing
  `2026-07-12T00:00:00+0000` actually lands on **July 11, 8 PM** local, NOT July 12. When a
  task's local day seems off by one, check whether it used `00:00Z` vs `04:00Z`.
- **Timed tasks** carry a real time (e.g. `2026-07-12T22:00:00+0000` = 6 PM Montreal). Convert
  normally.
- Individual tasks also carry a `timeZone` field, but on this account it is inconsistent (some
  tasks show `Australia/Sydney`, `America/Havana`, `Europe/London`, etc. from past travel).
  Do NOT trust the per-task `timeZone` for "today" logic — anchor everything to
  `America/Montreal` and the `+0000` UTC values.

### Practical recipe for "what's due today"

Convert each task's `dueDate` to `America/Montreal` and compare the local date to today's
local date. Robust approach in Python:

```python
from datetime import datetime, date
from zoneinfo import ZoneInfo
MTL = ZoneInfo("America/Montreal")
today = datetime.now(MTL).date()
def local_day(due):  # due like "2026-07-12T04:00:00.000+0000"
    dt = datetime.strptime(due, "%Y-%m-%dT%H:%M:%S.%f%z")
    return dt.astimezone(MTL).date()
# task is "today" if local_day(task["dueDate"]) == today
```

## Listing all tasks (no global endpoint)

The Open API v1 has **no "all tasks" or "due today" endpoint**. To scan everything you must:
1. `GET /open/v1/project` to get all project IDs.
2. For each, `GET /open/v1/project/{projectId}/data` (returns `{project, tasks, columns}`).
3. Also query the inbox explicitly: `GET /open/v1/project/inbox112832574/data` — the inbox is
   NOT included in the `/project` list. (`inbox112832574` is this account's inbox id; it also
   shows up as the `projectId` on tasks created without a `projectId`.)
4. Only **uncompleted** tasks are returned. Completed tasks are not retrievable via this API.

**⚠️ The project data listing can be badly stale — never use it to confirm a fresh write or
to answer "what's due today" right after one.** Measured 2026-09-28: six tasks POSTed to
`/open/v1/task` were readable immediately via
`GET /open/v1/project/inbox112832574/task/{id}` with the correct `dueDate` and tags, yet
`/open/v1/project/{id}/data` (and the inbox data listing) still did not contain them minutes
later — and the newest `createdTime` visible across ALL projects plus the inbox was
`2026-09-23T23:37Z` while the wall clock read `2026-09-28T13:50Z`. So:

- Confirm a write with `GET`-by-id, never with the data listing.
- Treat a listing gap as **staleness**, not as a missing task.
- Each task in `/data` **and** in `GET`-by-id DOES carry a `tags` array (verified 2026-09-28;
  this corrects an earlier claim that the field is absent). Tag-based duplicate detection can
  read `tags` from `/data` when it is fresh, and from `GET`-by-id otherwise.

## "Paste a TickTick URL" workflow (start → work → complete)

When the user's message is **just a TickTick URL** (e.g.
`https://ticktick.com/web/app/#p/{projectId}/tasks/{taskId}` or any URL containing
`ticktick.com`), they mean: "find this task, do the work, and complete it."

Run this flow:

1. **Parse the URL** to extract `projectId` and `taskId`. TickTick web URLs typically
   embed them in the fragment after `#p/` and `/tasks/`. If the URL format differs,
   fall back to listing projects and searching task titles/ids to locate it.
2. **Fetch the task**: `GET /open/v1/project/{projectId}/task/{taskId}`. Confirm it
   exists and read its title/content so you know what "done" means.
3. **Mark progress as started** — set the task's **progress bar to 1% (started)**.
   Update via `POST /open/v1/task/{taskId}` with a body including `id`, `projectId`,
   and `progress: 1` (TickTick stores task progress as an integer 0–100; 0 = not
   started, 1 = started/in-progress, 100 = complete). If the API rejects the
   `progress` field on this account, fall back to setting a clear status note in
   `content` (e.g. prepend `🚧 Started — ` ) so the user can see it's in progress.
4. **Do the work** described by the task — read the task content, investigate the
   codebase/files, and implement whatever the task asks for. Treat the TickTick task
   as the source of truth for the goal, same as you would a ticket body.
5. **When you believe the work is done**, update progress to a high value
   (e.g. `progress: 99`) and then **ask the user with `ask_user_question`**:
   "Is this task complete?" with options like *Yes, mark complete* and *Not yet*.
   Do NOT auto-complete without confirmation.
6. **If the user confirms complete**: call
   `POST /open/v1/project/{projectId}/task/{taskId}/complete` to mark it done in
   TickTick (this also sets progress to 100 server-side). Report the result.
7. **If the user says not yet**: leave the task in-progress (progress stays at the
   started value), ask what's still needed, and continue working. Re-confirm before
   completing.

This flow applies **only** when the user's message is a bare TickTick URL. If they
add instructions alongside the URL, follow those instructions instead.

## Calendar events as tasks

When adding a **calendar event** as a TickTick task (from a calendar triage
walk, a class schedule, or any event with a start and end time):

- The task's **`dueDate` time = the event's START time** (never the end
  time, never the whole range) — the task anchors on the start.
- Put the **time range in the task title**, e.g. title
  `IO1 class 16:00–22:00` with `dueDate` set to that day at **16:00**.
- **API caveat (empirically tested 2026-09-14, 5 variants incl. timeZone /
  +0000 / startDate-only): the Open API v1 collapses `startDate` into
  `dueDate` on BOTH create and update — a true start→end block is NOT
  achievable via the API.** Do NOT send `startDate` for calendar events —
  with dueDate set to the event END it drags the task anchor to the wrong
  time. Anchor on the start; end time goes in the title.
- If the event is all-day, use an all-day due date and no time in the title.

Example: IO1 class Friday Sep 18, 4:00 PM–10:00 PM →
`{ "title": "IO1 class 16:00–22:00", "dueDate": "2026-09-18T16:00:00.000-0400", "isAllDay": false }`

## Notes

- The access token is a personal Open API token; keep it secret. It lives ONLY in
  the `TICKTICK_TOKEN` env var, in a private env file — never inline it into this
  skill file, which is tracked in a public repo.
- If the token ever returns `401`, it has expired or been revoked — regenerate it from
  the TickTick developer console and update that env file.
