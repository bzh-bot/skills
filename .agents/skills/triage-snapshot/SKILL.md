---
name: triage-snapshot
description: >
  A live overview of the user's tasks: counts by tag, overdue tasks, tasks due
  today, and the agent backlog (the TickTick 'pi' project). Run on demand
  ("chief of staff snapshot") — no persistence, no cadence. Queries TickTick via the
  ticktick skill and the account registry for the known tag list.
  Generic — tags come from the registry (orgs.ticktick_tag) + the user's TickTick.
allowed-tools: Bash(sqlite3:*), Bash(source:*), Bash(curl:*), Bash(jq:*), read
---

# triage-snapshot

You show a **live snapshot** of the user's tasks. Run whenever the user asks
("chief of staff snapshot" / "what's on my plate"). No state is written; this is
read-only and on-demand.

## 1. Tags

Known org tags come from the registry:
```bash
sqlite3 -column -header $TRIAGE_DIR "SELECT name, ticktick_tag FROM orgs WHERE ticktick_tag IS NOT NULL;"
```
Plus any other tags the user's TickTick has (fetched below).

## 2. Fetch all uncompleted TickTick tasks

Via the `ticktick` skill (`$ORG_CONFIG_DIR/env/ticktick.env`):
- all projects + inbox, uncompleted tasks only.
- For each: `title`, `tags`, `dueDate`, `priority`.

## 3. Compute + display

```
📋 SNAPSHOT  (N open tasks)

DUE TODAY (N)
  [HIGH] Task (due 2pm)
  [MED]  Task (all-day)

⚠️ OVERDUE (N)
  • Task (was due Aug 25)  [org]

BY TAG
  org-a          ████████████ 12
  <org>             ███ 3
  org-tag           ██████ 6
  aviation       ██ 2
  exercise       ░ 0  ← neglected?

🤖 AGENT BACKLOG (pi project): N queued, M running   # if the pi project exists
```

- **Due today**: `dueDate` local day (Montreal) == today.
- **Overdue**: `dueDate` local day < today.
- **By tag**: count uncompleted tasks per tag; flag any org tag with 0 as
  "neglected".
- **Agent backlog**: if a TickTick project named `pi` exists, show its count
  (delegated work — not personal focus). Don't recommend `pi` tasks as focus.

## Notes

- No `snapshots.jsonl`, no `last-run.json` — this is a live query, nothing
  persisted (cadences were dropped).
- Don't hardcode tags; pull the org tags from the DB and the rest from TickTick.
- Be opinionated: after the snapshot, suggest 1–3 tasks to focus on.