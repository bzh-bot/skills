---
name: triage-confluence-reconcile
description: >
  Reconcile a Confluence priorities page against Jira: make sure everything on
  the page is captured as a Jira issue, and use the page's ordering to set Jira
  priorities. Invoked by the chief of staff with an account id (platform =
  confluence, item_type = reference). Fetches the page (Confluence Cloud REST
  API via the atlassian skill), parses the priority lines, JQL-matches each
  against Jira, and surfaces gaps (page items with no matching issue) for the
  user to: create a Jira issue now / add a TickTick task to create it / mark
  already tracked / skip. Writes accounts.last_swept_at when done. Generic — the
  page id, space, and env come from the registry.
allowed-tools: Bash(sqlite3:*), Bash(source:*), Bash(curl:*), Bash(jq:*), read, ask_user_question
---

# triage-confluence-reconcile

You reconcile **one Confluence priorities page** against Jira. The `chief of staff`
chief of staff gave you an **account id** (platform `confluence`). This is NOT a
one-by-one inbox triage — it's a gap check. Everything about the page comes from
the registry (page id = `identifier`; `notes` has `space`, `url`, `env`).

## 1. Load the account

```bash
ACC_ID=<account id>
triage "
SELECT a.id, o.name org, o.ticktick_tag, a.identifier page_id, a.notes
FROM accounts a JOIN orgs o ON o.id=a.org_id JOIN platforms p ON p.id=a.platform_id
WHERE a.id=$ACC_ID;"
```
`identifier` = Confluence page id. `notes` = `space: USA; url: ...; env: atlassian.env; reconcile: jira`.

## 2. Fetch the page

Auth = the same Atlassian basic auth as Jira (env file from `notes.env`, e.g.
`atlassian.env` → `ATLASSIAN_USER_EMAIL` + `ATLASSIAN_API_TOKEN`; site
`<org>.atlassian.net`). Use the **atlassian** skill for the API:

```bash
source $ORG_CONFIG_DIR/env/<env>
PAGE_ID=<page_id>
curl -s -u "$ATLASSIAN_USER_EMAIL:$ATLASSIAN_API_TOKEN" \
  "https://$ATLASSIAN_SITE/wiki/rest/api/content/${PAGE_ID}?expand=body.view,space,version" \
  | jq -r '.body.view.value'   # HTML — parse the priority list items
# (Newer "Atlas doc" pages: if body.view is empty, use /wiki/api/v2/pages/${PAGE_ID}?body-format=styled.)
```

Parse the HTML for the priority items (`<li>` rows / table rows / headed
sections). Each item becomes a **priority line** (text + any status/owner/date).
Preserve top-to-bottom order (it encodes priority).

## 3. Reconcile against Jira

For each priority line, search Jira for a matching issue (via the atlassian
skill). Prefer a cited Jira key (`USA-123`) → fetch it; else JQL by the line
text. A line is **captured** if an issue clearly matches; a **gap** if none.

## 4. Surface gaps + priority misalignment

For each **gap**, ask via `ask_user_question` (bake a summary into the question):

| Option | Action |
|--------|--------|
| Create a Jira issue now | draft summary + description from the line, pick the project (default from the page space), confirm, then `POST /rest/api/3/issue`. |
| Add a TickTick task to create it | create a task tagged with the org `ticktick_tag`, due this week, content = the Confluence line + page URL. Confirm. |
| Already tracked (paste key) | record the Jira key against the line so it isn't flagged again. |
| Skip | leave it; will re-surface next reconciliation. |

"Type something." is always available ("split into 2 issues", "this is done —
link USA-99", "not in scope").

For **captured** items, compare the page's ordering to the Jira issue's priority
/ backlog rank. If a top-of-page item is low priority / unranked in Jira, offer
to bump (confirm before any `PUT /rest/api/3/issue/<key>`).

## 5. When done

Write the cursor:
```bash
triage \
  "UPDATE accounts SET last_swept_at='$(date -u +%Y-%m-%dT%H:%M:%SZ)' WHERE id=$ACC_ID;"
```

## Notes

- No org names hardcoded — page id, space, env, tag come from the DB.
- This is a reconciliation run, not per-item triage; only gaps + priority
  misalignments are surfaced for a decision.