---
name: clickup
description: >
  Work with ClickUp from pi — read/create/update/assign/move tasks, set status,
  Sprint Points, start/due dates and custom fields, comment, attach files, and
  search or read ClickUp Docs. Use when asked to create ClickUp tasks, copy
  tickets into ClickUp, look something up in a ClickUp list/space/doc, or update
  a ClickUp task. Drives ClickUp through the
  personal API token — the pi MCP server for ClickUp is NOT used.
allowed-tools: Bash(~/.agents/skills/clickup/scripts/clickup:*), Bash(python3:*), Bash(curl:*), read
---

# ClickUp

**ClickUp is reached with the personal API token over the REST API v2, through
[`scripts/clickup`](scripts/clickup) — not through an MCP server.** The MCP path
was retired: its OAuth token is scoped to `mcp.clickup.com` and 401s against
`api.clickup.com`, it could not write Sprint Points, and one CLI is easier for an
agent than a codemode round-trip.

- **Token:** `CLICKUP_TOKEN` (or `CLICKUP_API_TOKEN`) in the environment, or in a
  private env file the CLI sources for you — nothing needs exporting by hand.
  The token acts as the human who owns it, across every workspace they belong to.
- **Never** ask for the token or print it; only the CLI needs it.
- `~/.agents/skills/clickup/scripts/clickup <command>` — every call below.
  `scripts/clickup --help` lists them; each subcommand takes `--help`.

---

## Hard rules

### 1. Ticket links are PLAIN URLs — never hidden behind text

Write the URL as the visible text. Do not wrap it in a label.

```
GOOD   https://app.clickup.com/t/<task_id>
BAD    [#868mh7m12](https://app.clickup.com/t/<task_id>)
BAD    [<task name>](https://app.clickup.com/t/<task_id>)
```

**Why:** a labelled link renders as a chip whose
text replaces the URL. When that content is copied, exported or round-tripped
through the API, the reader is left with the label alone — **the interactive
link is lost and the ticket's id/status is no longer visible from the text.**
A bare URL survives (ClickUp stores it as `[url](url)`, text == URL), stays
clickable, and can unfurl into a task chip that shows the status.

Applies everywhere: ClickUp Docs pages, task descriptions, comments, and any
ticket list/table written for a human to read.

### 2. Editing a Doc page rewrites the whole page and mangles it

Writing a Doc page means re-importing the **entire** page as markdown — inserting
one table row does that. ClickUp's importer does not round-trip its own output:

| Written as | Comes back as | Effect |
|---|---|---|
| `[@Some One](#user_mention#<user_id>)` | `[@Some One](http://#user_mention#<user_id>)` | dead link, mention chip lost |
| `[@Some One](user_mention#<user_id>)` | `@Some One` | plain text, mention chip lost |
| `[@Some One](http://#user_mention#<user_id>)` | `@Some One` | plain text, mention chip lost |

So: **@mention chips cannot be written through the API** — only plain-text
`@Name`. Also `**` gets escaped (`## Details**:**` → `## Details\*\*:\*\*`) and
stray blank lines are dropped.

Procedure before any page write:

1. Save the current content to a file (your only rollback copy).
2. Edit the saved copy, write the whole page back.
3. Re-read and **diff against the copy**; fix or report every unintended change
   (mentions, escaped `**`, dropped lines). Do not assume the write was clean.

---

## Command reference

```bash
clickup me                        # token sanity + workspace members
clickup hierarchy [--space-id ID] # spaces → folders → lists (ids)
clickup list <list_id>            # list name + the EXACT valid status names
clickup fields --space ID | --folder ID | --list ID   # custom fields + option UUIDs
clickup members

clickup tasks [--list ID] [--space ID] [--folder ID] [--assignee me|ID]
              [--status NAME] [--include-closed] [--limit N]

clickup get <task_id> [--json] [--description]        # --description = markdown body
clickup update <task_id> [--name N] [--status S] [--assignee me|ID]...
              [--priority urgent|high|normal|low|none]
              [--due today|'YYYY-MM-DD[ HH:MM]'|none] [--start same-as-due]
              [--points N|none] [--description MD] [--append-description MD]
              [--custom-field ID=VALUE]...
clickup create --list LIST_ID --name NAME [...]       # same flags as update

clickup comment <task_id> "markdown, bare URLs"
clickup comments <task_id>
clickup attach <task_id> FILE
clickup delete <task_id>
```

Working examples:

```bash
S=~/.agents/skills/clickup/scripts/clickup
$S get <task_id> --description            # ticket + body
$S update <task_id> --status "working" --assignee me --start today --points 3
$S comment <task_id> "https://github.com/<org>/<repo>/pull/123"
$S create --list <list_id> --name "<KEY-123> — <title>" \
   --assignee me --priority normal --points 3 \
   --custom-field <field_id>=<option_id>   # e.g. the required dropdown, if the list has one
```

---

## Finding ids

Nothing about a workspace is knowable from this skill: workspace, space, folder,
list, doc, user and custom-field ids all differ per ClickUp account. Discover them
per workspace, once, and keep them in your own notes:

```bash
clickup hierarchy                  # spaces -> folders -> lists, with ids
clickup list <list_id>             # statuses (per list) + task field ids
clickup fields --space <space_id>  # custom fields + every dropdown option UUID
clickup fields --list <list_id>    # the fields that list actually requires
```

Sprints are usually **lists** named after a date range; resolve their ids the same
way. Statuses are per-list — always read them with `clickup list <id>` before
writing one.

## Gotchas (REST specifics — the MCP-era notes do not apply)

- **Descriptions:** a raw `GET /task/{id}` has NO `markdown_description` — that is
  an MCP-only response field. Markdown comes back only with
  `?include_markdown_description=true` (the CLI does this for
  `get --description`), and writes use **`markdown_content`**. Reading the wrong
  key makes an append silently **wipe** the existing description (bug hit while
  building the CLI, 2026-10-14 — the CLI now does both correctly).
- **`--description` replaces the whole body**; use `--append-description` (which
  reads, appends and writes back) to add a section.
- **`--assignee` REPLACES the assignee set** — pass every assignee you want kept.
  A points/status-only update leaves assignees alone (verified).
- **Priority is numeric in the API** (1 urgent … 4 low). The CLI takes the names.
- **Dates are epoch milliseconds** (`due_date`, `start_date`); `*_time` booleans
  say whether to show a time. The CLI converts `today`, `YYYY-MM-DD`,
  `YYYY-MM-DD HH:MM` (local, 09:00 default for a bare date) and passes epoch ms
  through; `none` clears.
- **`create` returns the task object** (`id`, `url`, `name`, …) — not the MCP's
  `{success, task_id, task_url}`.
- **Custom fields must go through the field endpoint.** Putting `custom_fields` in
the create/update body answers **200 and silently ignores the values** — every
shape tried (option UUID, option orderindex, option name) left the field unset
(verified 2026-10-14). The CLI handles this: `--custom-field ID=VALUE` issues
`POST /task/{id}/field/{field_id}` with `{"value": …}`, which sticks.
- **Value shapes:** dropdown → the option UUID; checkbox → `true`/`false`;
  people (`users`) → `{"add":["<user id>"]}` (and `"rem"` to remove); labels →
  `["<option uuid>"]`; url / short_text → the string. **Reads come back
differently:** a dropdown's `value` is the option's **orderindex** (integer), not
  the UUID — e.g. `Planned/Unplanned = 2` is the *Null* option. Map it with
  `clickup fields`.
- **Required custom field:** some sprint lists require a dropdown to be set on
  creation. `clickup fields --list <id>` names it and prints its option UUIDs; pass
  it on `create` or creation fails there.
- **Filters need the workspace id** — the CLI takes it from `CLICKUP_WORKSPACE`
  (or `--workspace`); there is no sensible default, so set it once per workspace.
- **Copying a Jira ticket:** use the `atlassian` skill's credentials
  (`ATLASSIAN_SITE` / `ATLASSIAN_USER_EMAIL` / `ATLASSIAN_API_TOKEN`, HTTP Basic);
  mirror description, metadata and attachments, and write the Jira link as a plain
  URL too: `https://<site>.atlassian.net/browse/<KEY>-123`.
- **Docs** are not exposed by the CLI yet; if a Doc/page write is needed, use the
  API directly with the same token (`GET|POST /api/v3/workspaces/{ws}/docs…`) and
  follow Hard rule 2.

## Custom fields

Every field is set the same way, once you know its id and — for dropdowns — the
option's UUID:

```bash
clickup update <task_id> --custom-field <field_id>=<value>
clickup fields --list <list_id>   # the ids, types and option UUIDs for that list
```

What matters generally:

- **A required dropdown on a list means creation fails without it** — pass the
  field on `create`, or fill it immediately after. Discover which lists require
  what with `clickup fields --list <id>`; never assume from another workspace.
- **Dropdown values are option UUIDs, not labels.** Reads come back as the option's
  **orderindex** (an integer), so map it back with `clickup fields` before reporting
  a value.
- **Checkbox** → `true` / `false`. **People** → `'{"add":["<user id>"]}'`
  (`"rem"` to remove). **Labels** → `["<option uuid>"]`. **url / short_text** → the
  string.
- **Some fields are read-only or auto-managed** (baselines, mirroring fields, label
  fields on spaces that do not apply to tasks). Writes to those silently do
  nothing — if a value never appears, check the field's type before retrying.
- **Judgement, not filling:** planning metadata (delivery windows, verticals,
  quarters, tactics, goals) should only be set when the ticket itself makes the
  answer unambiguous. Otherwise ask the user rather than guessing.

## Sprint Points (story points) — the built-in field

**Story points go in ClickUp's built-in Sprint
Points field — not a custom field, and never `time_estimate`.**

```bash
clickup update <task_id> --points 3      # set
clickup get    <task_id>                 # -> pts=3
clickup update <task_id> --points none   # clear
```

- Sprint Points is a **built-in** attribute, so it does NOT appear in `clickup
  fields` (no *points* field exists at list/folder/space level) and it is not
  `time_estimate` (ClickUp's clock-style estimate, a different thing).
- It is the API's `points`, which ClickUp's own reference documents as **"Update
  the task's Sprint Points"** (`developer.clickup.com/reference/updatetask`).
  **Verified 2026-10-14**: set 3, read back 3.
- Never post the estimate as a comment instead, and never invent a custom field
  for it.

## Start date — set it when work starts

**When a ticket system supports a start date, set it.** ClickUp does (`start_date`), so when work on a ticket begins:

```bash
clickup update <task_id> --start today        # the day implementation starts
```

Use it together with the status change (`--status "working"`) and, for a
ticket that has no estimate yet, `--points`. `--start none` clears it.
