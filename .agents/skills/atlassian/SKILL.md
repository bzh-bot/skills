---
name: atlassian
description: Search, read, edit, and create Jira tickets and Confluence pages
allowed-tools: Bash(curl:*), Bash(atlassian:*), Bash(jq:*), Bash(npx mcporter:*), read
---

# Atlassian Skill — Jira & Confluence (Preference-Driven)

## Tool Selection Order (required)

For Jira/Confluence actions, the agent must choose an access path in this order:

1. **Injected API token.** If `ATLASSIAN_API_TOKEN` — or a per-product `JIRA_API_TOKEN` / `CONFLUENCE_API_TOKEN` — is set together with `ATLASSIAN_SITE` and `ATLASSIAN_USER_EMAIL`, use the **REST + HTTP Basic** path in [API token over REST](#api-token-over-rest-no-oauth). Once this path is selected it is authoritative: do **not** use MCP, the `atlassian` CLI, MCPorter, or any browser/OAuth flow — not even as a fallback — and if the token is rejected (401/403), fail clearly rather than falling back (see that section). If these env vars are **not** set, this path does not apply — continue to the next option.
2. **MCP.** Otherwise, check whether Atlassian MCP tools are available in the current runtime; if so, use them first.
3. **`atlassian` CLI.** Otherwise, check whether the `atlassian` CLI is on PATH (e.g. `which atlassian`); if it exists, use it.
4. **Setup.** If none of the above are available, ask the user to install/set up via the MCPorter instructions below.

Do not scrape filesystem contents to discover binaries; use standard PATH checks. The injected-token path (1) is authenticated entirely by the env vars and has **no fallback** to host OAuth, MCPorter cache, or browser state.

## Secrets file (auto-load)

Before checking env vars, attempt to load credentials from a private env file if you
keep one:

```bash
# optional: your own private env file holding the Atlassian variables
: "${ATLASSIAN_ENV_FILE:=$HOME/.config/atlassian.env}"
if [[ -f "$ATLASSIAN_ENV_FILE" ]]; then
  set -a; source "$ATLASSIAN_ENV_FILE"; set +a
fi
```

That file is expected to set `ATLASSIAN_SITE`, `ATLASSIAN_USER_EMAIL`,
`ATLASSIAN_API_TOKEN`, optionally `ATLASSIAN_CLOUD_ID`, and optionally
`ATLASSIAN_GRAPHQL_RANK_ENDPOINT`. If it exists and sources successfully, the
injected-token path (1) above becomes available automatically — proceed with
[API token over REST](#api-token-over-rest-no-oauth) and
[GraphQL issue ranking](#graphql-issue-ranking) without further setup.

If the secrets file does not exist, fall back to checking env vars, then MCP, then CLI as described above.

## API token over REST (no OAuth)

When the env vars below are present, authenticate to Jira and Confluence directly over REST with **HTTP Basic** auth. The token's products, scopes, and permissions are fixed by whoever created it and enforced by Atlassian — the skill only uses the credential it is given.

### Credentials (injected env vars)

| Variable                                  | Meaning                                                                  |
| ----------------------------------------- | ------------------------------------------------------------------------ |
| `ATLASSIAN_SITE`                          | Site host, e.g. `your-site.atlassian.net`                                |
| `ATLASSIAN_USER_EMAIL`                    | Atlassian account email — the Basic-auth **username**                    |
| `ATLASSIAN_API_TOKEN`                     | API token (classic or scoped) — the Basic-auth **password**              |
| `JIRA_API_TOKEN` / `CONFLUENCE_API_TOKEN` | Per-product tokens; take precedence over `ATLASSIAN_API_TOKEN` where set |
| `ATLASSIAN_CLOUD_ID`                      | Optional; derived from the site at runtime when unset                    |

Auth is `base64(email:token)` — there is **no Bearer/PAT mode** (a `Bearer` header returns 403). Pass credentials with curl's `-u` flag and **never echo, print, or log the token**. Resolve the per-product token and the cloudId once, then reuse:

```bash
JIRA_TOKEN="${JIRA_API_TOKEN:-$ATLASSIAN_API_TOKEN}"
CONFLUENCE_TOKEN="${CONFLUENCE_API_TOKEN:-$ATLASSIAN_API_TOKEN}"
# cloudId from the site (no auth); node branch is the fallback when jq is absent:
CLOUD_ID="${ATLASSIAN_CLOUD_ID:-$(curl -sS "https://$ATLASSIAN_SITE/_edge/tenant_info" | jq -r .cloudId)}"
# CLOUD_ID="${ATLASSIAN_CLOUD_ID:-$(curl -sS "https://$ATLASSIAN_SITE/_edge/tenant_info" | node -e 'let d="";process.stdin.on("data",c=>d+=c).on("end",()=>console.log(JSON.parse(d).cloudId))')}"
```

### Base URL

Use the `ex/<cloudId>` base for both token types — it accepts classic and scoped tokens, so the tooling never branches:

```
https://api.atlassian.com/ex/jira/$CLOUD_ID/rest/api/3/...
https://api.atlassian.com/ex/confluence/$CLOUD_ID/wiki/api/v2/...
```

The site URL (`https://$ATLASSIAN_SITE/rest/...`) works for classic tokens but 401s for scoped ones — prefer `ex/<cloudId>` for uniformity.

### Verify auth first

Check whichever product(s) your token covers. A Jira-only token 401s on the Confluence check and vice-versa — that 401 is the scope boundary, not a failure:

```bash
# Jira (skip if Confluence-only):
curl -sS -o /dev/null -w '%{http_code}\n' -u "$ATLASSIAN_USER_EMAIL:$JIRA_TOKEN" \
  "https://api.atlassian.com/ex/jira/$CLOUD_ID/rest/api/3/myself"
# Confluence (skip if Jira-only):
curl -sS -o /dev/null -w '%{http_code}\n' -u "$ATLASSIAN_USER_EMAIL:$CONFLUENCE_TOKEN" \
  "https://api.atlassian.com/ex/confluence/$CLOUD_ID/wiki/api/v2/spaces?limit=1"
# 200 = OK; 401 = missing/bad token (or wrong product for a scoped token)
```

### Jira over REST

- **Search:** `GET /rest/api/3/search/jql` with **bounded** JQL — the legacy `/rest/api/3/search` is **410 Gone**, and an unbounded query (only `ORDER BY ...`) returns 400, so always include a restriction like `project = NVR` or `created >= -30d`.
  ```bash
  curl -sS -u "$ATLASSIAN_USER_EMAIL:$JIRA_TOKEN" \
    "https://api.atlassian.com/ex/jira/$CLOUD_ID/rest/api/3/search/jql?jql=project%3DNVR%20ORDER%20BY%20created%20DESC&maxResults=10&fields=key,summary,status"
  ```
- **Get issue:** `GET /rest/api/3/issue/<KEY>` (add `?fields=summary,status,description,...`).
- **Add comment:** `POST /rest/api/3/issue/<KEY>/comment` with an ADF `{"body": { ... }}`.
- **Edit issue:** `PUT /rest/api/3/issue/<KEY>` with `{"fields": { ... }}` or `{"update": { ... }}`.
- **Link issues:** `GET /rest/api/3/issueLinkType` to discover types, `POST /rest/api/3/issueLink` to create, `DELETE /rest/api/3/issueLink/<linkId>` to remove — see [Linking Jira Issues (Work Items)](#linking-jira-issues-work-items).

ADF shapes (paragraphs, headings, code blocks, task lists) are identical to [Editing a Jira Issue](#editing-a-jira-issue).

### Confluence over REST (v2)

Use the **v2** API (`/wiki/api/v2/...`) — scoped tokens 401 on v1 (`/wiki/rest/api/...`); classic tokens still work on v1.

- **Resolve a space:** `GET /wiki/api/v2/spaces?keys=<SPACEKEY>` → `.results[0].id` is the numeric `spaceId` (URL-encode `~` in personal-space keys as `%7E`).
- **Read page:** `GET /wiki/api/v2/pages/<id>?body-format=storage`.
- **Create page:** `POST /wiki/api/v2/pages` with `{"spaceId": "<id>", "status": "current", "title": "<title>", "body": {"representation": "storage", "value": "<p>…</p>"}}`.
- **Update page:** `PUT /wiki/api/v2/pages/<id>` with an incremented `version.number` (fetch current first).

Markdown → storage-format conversion follows [Converting Markdown to Confluence Storage Format](#converting-markdown-to-confluence-storage-format).

### Scoped-token caveats

Jira granular write scopes don't all map 1:1 to REST endpoints: `write:issue:jira` covers `PUT /issue` edits, but `POST /issue/<KEY>/comment` can return `401 "scope does not match"` without a broader scope (e.g. `write:jira-work`). A write that 401s with an otherwise-valid token means the token lacks that scope — report it, don't switch auth methods.

### No fallback (required)

A 401/403 on this path — expired or rejected token — must **stop and report**. Do not run `npx mcporter auth`, open a browser, or read `~/.mcporter` / host OAuth state: the injected token is the only credential in this mode.

### GraphQL issue ranking

The Jira board rank (custom field for issue ordering) **cannot** be changed via the REST API `PUT /issue` endpoint — it returns 200 but silently ignores the rank field. The MCP `editJiraIssue` tool also does not support it. Issue ranking requires the **GraphQL `useIssuesRankerMutation`** on the site gateway, authenticated with the same API token via HTTP Basic.

The endpoint URL and cloud ID are stored in the secrets env file as `ATLASSIAN_GRAPHQL_RANK_ENDPOINT` and `ATLASSIAN_CLOUD_ID`.

#### Construct issue ARIs

The GraphQL API uses Atlassian Resource Identifiers (ARIs) instead of issue keys:

```
ari:cloud:jira:$CLOUD_ID:issue/$ISSUE_ID
```

Where `$ISSUE_ID` is the numeric Jira issue ID (not the key like `PROJ-123`, but the internal numeric ID from `issue.id` in the REST API response). Get issue IDs from a JQL search:

```bash
curl -sS -u "$ATLASSIAN_USER_EMAIL:$JIRA_TOKEN" \
  "https://$ATLASSIAN_SITE/rest/api/3/search/jql?jql=project%3DNVR%20ORDER%20BY%20cf%5B10600%5D%20ASC&maxResults=100&fields=key,summary" \
  | jq -r '.issues[] | "\(.key)\t\(.id)"'
```

#### Rank an issue relative to another

```bash
curl -sS -X POST \
  -u "$ATLASSIAN_USER_EMAIL:$JIRA_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"operationName":"useIssuesRankerMutation","variables":{"rankInput":{"issues":["ari:cloud:jira:'"$CLOUD_ID"':issue/'"$ISSUE_ID"'"],"relativeToIssue":"ari:cloud:jira:'"$CLOUD_ID"':issue/'"$RELATIVE_ISSUE_ID"'"],"edge":"BOTTOM"}}}' \
  "$ATLASSIAN_GRAPHQL_RANK_ENDPOINT"
```

- `edge: "BOTTOM"` places the issue **after** `relativeToIssue` (i.e. ranked below it).
- `edge: "TOP"` places the issue **before** `relativeToIssue` (i.e. ranked above it).

#### Reorder a batch of issues

To reorder many issues into a specific priority order, rank each issue after the previous one (skip the first, it stays as the anchor):

```bash
# ORDER is a bash array of "issue_id issue_key" pairs in the desired order
for i in $(seq 1 $((${#ORDER[@]} - 1))); do
  CURRENT_ID=$(echo "${ORDER[$i]}" | cut -d' ' -f1)
  PREV_ID=$(echo "${ORDER[$((i-1))]}" | cut -d' ' -f1)
  curl -sS -X POST \
    -u "$ATLASSIAN_USER_EMAIL:$JIRA_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"operationName":"useIssuesRankerMutation","variables":{"rankInput":{"issues":["ari:cloud:jira/'"$CLOUD_ID"':issue/'"$CURRENT_ID"'"],"relativeToIssue":"ari:cloud:jira/'"$CLOUD_ID"':issue/'"$PREV_ID"'"],"edge":"BOTTOM"}}}' \
    "$ATLASSIAN_GRAPHQL_RANK_ENDPOINT" >/dev/null
done
```

A successful response: `{"data":{"jira":{"rankIssues":{"success":true,"errors":[]}}}}`.

## Preference Source of Truth

Before doing Jira/Atlassian or related AWS auth actions, read preferences from these paths in this order:

1. `./.config/skills/atlassian/preferences.json` (workspace-local, preferred)
2. `~/.config/skills/atlassian/preferences.json` (user-global fallback)

If neither file exists:

- Ask the user for their preferences.
- Create or update a preference file in one of the supported locations (prefer workspace-local unless user asks otherwise).

## Preference Management Rules

- The JSON structure is intentionally flexible and may evolve over time.
- Read the existing JSON first.
- Update preferences incrementally based on user answers.
- Do **not** blindly overwrite the whole file.
- Preserve unknown keys and existing user customizations.
- The skill may add new keys as needed (for example, per-project or per-repository preferences).

## Values That Must Come from Preferences or User Input

Never hardcode these values:

- Jira cloud/site URL (or cloudId)
- Jira project key (for example, `NVR`)
- Optional project conventions (for example, story-point defaults)

## Atlassian Usage Guidance

- For search behavior, follow tool guidance:
  - If using the Atlassian unified `search` tool, use it by default unless user explicitly asks for CQL or JQL.
  - Use dedicated JQL/CQL tools when requested.
- Format links with markdown, not smart links: `[Link text](URL)`
- When mentioning another ticket, make it a hyperlink.
- Atlassian does _not_ support `list_resources` with server name `atlassian` in some MCP runtimes.
- Avoid including identifiable customer information (e.g., first name, last name, phone number) in ticket descriptions, summaries, and comments. Use identifiers (account ID, external ID, serial number) instead.

## Searching Jira Issues

Use `searchJiraIssuesUsingJql` (MCP) or `atlassian searchJiraIssuesUsingJql` (CLI) to search issues with JQL (Jira Query Language).

CLI usage:

```bash
atlassian searchJiraIssuesUsingJql --cloud-id "<cloud-id>" --jql '<JQL>'
# Optional: --fields summary,status,labels  --max-results 50  --next-page-token <token>
```

### JQL Examples — Label Search

`labels = <value>` matches issues that **contain** the label (issues can have multiple labels). The match is case-insensitive. For multiple distinct label names, use `labels in (...)`.

- Has label: `labels = Arlington`
- Has either of multiple labels: `labels in (Arlington, boston)`
- Has both labels: `labels = Arlington AND labels = urgent`
- Label + project + status: `project = NVR AND labels = Arlington AND status = "To Do"`

**Tips:**

- Jira's `labels` operator is case-insensitive: `labels = arlington` matches the `Arlington` label. Use `labels in (...)` to match multiple distinct label names (not casing variants).
- Use `--fields` to limit returned fields and reduce response size: `--fields summary,status,labels`
- Use `--max-results` to control page size (default 10, max 100). For paginated results, pass `--next-page-token` from the previous response.

### JQL Examples — General

Each expression below is a `--jql` argument value.

- Text in summary/description: `text ~ "discharge bug"`
- My issues: `assignee = currentUser()`
- Bugs in a project: `issuetype = Bug AND project = NVR`
- Recently created: `created >= -7d ORDER BY created DESC`

---

## Editing a Jira Issue

Use `editJiraIssue` (MCP) or `atlassian editJiraIssue` (CLI).

### CLI — Key Rules

Always include `--content-format adf` when the `--fields` payload contains ADF.

Do **not** pass ADF JSON through `--description` in `createJiraIssue` — it sends plain text and will double-serialize the ADF, causing Jira to display raw JSON instead of rendered content. Use `editJiraIssue --content-format adf` to set the description after creation.

Use `--response-content-format adf` to get the stored description back in ADF format in the response JSON.

### CLI — How to edit an issue description

Write the JSON to a temp file with a single-quoted heredoc (prevents all variable substitution), then pass it via `$(cat ...)`:

```bash
cat > /tmp/jira_fields.json << 'EOF'
{"description": {"type": "doc", "version": 1, "content": [{"type": "paragraph", "content": [{"type": "text", "text": "Example"}]}]}}
EOF

atlassian editJiraIssue \
  --cloud-id "<cloud-id>" \
  --issue-id-or-key "ABC-123" \
  --fields "$(cat /tmp/jira_fields.json)" \
  --content-format adf \
  --response-content-format adf
```

The single-quoted heredoc (`<< 'EOF'`) prevents shell expansion so the JSON arrives intact.

Build the description as an ADF document. Key node types:

| Node         | ADF shape                                                                                                                                                                                |
| ------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Paragraph    | `{"type": "paragraph", "content": [{"type": "text", "text": "..."}]}`                                                                                                                    |
| Heading      | `{"type": "heading", "attrs": {"level": 2}, "content": [{"type": "text", "text": "..."}]}`                                                                                               |
| Code block   | `{"type": "codeBlock", "attrs": {"language": "typescript"}, "content": [{"type": "text", "text": "..."}]}`                                                                               |
| Ordered list | `{"type": "orderedList", "content": [{"type": "listItem", "content": [{"type": "paragraph", "content": [{"type": "text", "text": "item"}]}]}]}`                                          |
| Bullet list  | Same as orderedList but `type: "bulletList"`                                                                                                                                             |
| Inline code  | `{"type": "text", "marks": [{"type": "code"}], "text": "..."}`                                                                                                                           |
| Bold         | `{"type": "text", "marks": [{"type": "strong"}], "text": "..."}`                                                                                                                         |
| Checkbox     | `{"type": "taskList", "attrs": {"localId": "section1"}, "content": [{"type": "taskItem", "attrs": {"localId": "s1-1", "state": "TODO"}, "content": [{"type": "text", "text": "..."}]}]}` |

**Important**: `codeBlock` content must be an **array of text nodes**:

```json
{
  "type": "codeBlock",
  "attrs": { "language": "typescript" },
  "content": [{ "type": "text", "text": "const x = 1;" }]
}
```

### Checkbox items (task lists) in ADF

Jira renders checkboxes using `taskList`/`taskItem` ADF nodes. The critical detail is that **`taskItem` content must be a flat array of `text` nodes, NOT wrapped in `paragraph` nodes.** Wrapping in `paragraph` causes an `INVALID_INPUT` error.

#### ✅ Correct — direct text nodes inside taskItem

```json
{
  "type": "taskList",
  "attrs": { "localId": "section1" },
  "content": [
    {
      "type": "taskItem",
      "attrs": { "localId": "s1-1", "state": "TODO" },
      "content": [{ "type": "text", "text": "First checkbox item" }]
    },
    {
      "type": "taskItem",
      "attrs": { "localId": "s1-2", "state": "TODO" },
      "content": [{ "type": "text", "text": "Second checkbox item" }]
    }
  ]
}
```

#### ❌ Wrong — paragraph wrapper inside taskItem (causes INVALID_INPUT)

```json
{
  "type": "taskItem",
  "attrs": { "localId": "s1-1", "state": "TODO" },
  "content": [
    {
      "type": "paragraph",
      "content": [{ "type": "text", "text": "First checkbox item" }]
    }
  ]
}
```

Each `taskList` must have a unique `localId`. Each `taskItem` within it also needs a unique `localId`. The `state` attribute is `"TODO"` (unchecked) or `"DONE"` (checked).

Multiple `taskList` blocks in the same description are fine — use different `localId` values for each section.

### CLI — Markdown fallback (simple text only)

If ADF is too complex and only plain text is needed, use `--content-format markdown`:

```bash
cat > /tmp/jira_fields.json << 'EOF'
{"description": "Plain text description"}
EOF

atlassian editJiraIssue \
  --cloud-id "<cloud-id>" \
  --issue-id-or-key "ABC-123" \
  --fields "$(cat /tmp/jira_fields.json)" \
  --content-format markdown
```

In the Atlassian CLI, the `--content-format markdown` option only renders basic text — do not rely on lists or fenced code blocks being preserved.

### Formatting Guidelines

When the MCP tool is available, use markdown formatting (not wiki formatting):

- **Headers**: `# Heading`
- **Lists**: `- List item` or `* List item`
- **Bold**: `**bold text**`
- **Code**: `` `code` ``
- **Links**: `[Link text](URL)`
- **Checkboxes**: `- [ ]` is inconsistently converted in both MCP and CLI — some items become checkboxes while others become escaped bullet lists. Use ADF `taskList`/`taskItem` nodes instead (see table above and the **Checkbox items** section below). When using the CLI, pass `--content-format adf`.
- **Description headings**: do not repeat the ticket title as the first heading in the description. The title is already displayed above it. Use H1 for the first meaningful section (e.g., `# Problem`), not to repeat the title. (Note: Jira's API calls the ticket title the `summary` field — they are the same thing, so `# Summary` also repeats the title.)

## Creating Subtasks

- To create a subtask, use `createJiraIssue` with `--issue-type-name "Subtask"`.
- The `parent` field must be passed as a **string** (just the issue key, e.g. `"PROJ-568"`) via `--raw` — **not** as an object in `fields`.
- Subtasks inherit the sprint from their parent and cannot be directly assigned to a sprint.

### Example (CLI)

```bash
atlassian createJiraIssue \
  --cloud-id "<cloud-id>" \
  --project-key "NVR" \
  --issue-type-name "Subtask" \
  --summary "My subtask" \
  --description "Description here" \
  --raw '{"parent":"PROJ-568"}'
```

## Converting Issue Types (e.g. Task to Subtask)

- When converting a Task to a Subtask, both `issuetype` and `parent` must be set in the **same** `editJiraIssue` call.
- The `parent` field in `editJiraIssue` may need to be passed as a string via raw params, similar to creation.
- If direct conversion fails, do **not** recreate the issue — investigate the error and try alternative approaches first.

## General Guidance: Prefer Migration over Recreation

- When tickets need to be reorganized (e.g., moved under a different parent, changed type), always prefer **migrating/editing existing tickets** over deleting and recreating them.
- Deleting or marking tickets as obsolete loses history, comments, and links.
- Only mark tickets as obsolete as a last resort, and always confirm with the user first.

## Audit Trail Alternative

- Use `addCommentToJiraIssue` with `commentBody`.
- Do not pass `commentVisibility` unless restricting visibility.

## Understanding Ticket History

When investigating a Jira ticket, remember that **all changes to a ticket (field updates, status transitions, assignments, etc.) are recorded in the ticket's Activity/History section**. If you need to understand what has changed on a ticket—including previous states, who made changes, and when—look at the ticket's history view in Jira rather than assuming the current state is the only available information.

## Linking Jira Issues (Work Items)

When a ticket **relates to**, **blocks**, **is blocked by**, **duplicates**, or **clones** another, connect them with a typed **issue link** (the "Link work items" action in the Jira UI) — not just a prose mention. A line like `Related infra ticket: OTHER-2096` in a description creates no real relationship: it never shows in the issue's Links panel, is invisible to link-aware JQL (`issue in linkedIssues("PROJ-1022")`) and automation, and rots if either ticket is moved. Prose ticket keys are fine in PR descriptions and commit messages; ticket↔ticket relationships belong in issue links.

### Discover the link types

Link-type names are instance-specific — take them from the endpoint, never guess:

```bash
# REST (injected token):
curl -sS -u "$ATLASSIAN_USER_EMAIL:$JIRA_TOKEN" \
  "https://api.atlassian.com/ex/jira/$CLOUD_ID/rest/api/3/issueLinkType"
# MCP / CLI:
atlassian getIssueLinkTypes --cloud-id "<cloud-id>"
```

Each type has a `name` plus the two directional phrases `outward` / `inward`. Common types on an Atlassian Cloud site:

| `name`      | `outward`  | `inward`         |
| ----------- | ---------- | ---------------- |
| `Blocks`    | blocks     | is blocked by    |
| `Relates`   | relates to | relates to       |
| `Duplicate` | duplicates | is duplicated by |
| `Cloners`   | clones     | is cloned by     |

### Direction: inward vs outward

For directional types the two ends are **not** interchangeable — and the two access paths label them **oppositely**, so always confirm after writing:

- **Raw REST** `POST /rest/api/3/issueLink`: `outwardIssue` takes the `outward` phrase toward `inwardIssue`. For `Blocks`, **`outwardIssue` blocks `inwardIssue`** (equivalently, `inwardIssue` is blocked by `outwardIssue`).
- **MCP / CLI `createIssueLink`**: the tool's own help inverts this — it treats **`inwardIssue` as the blocker** ("inwardIssue = issue that blocks, outwardIssue = the blocked issue"), so on the CLI the blocker goes in `--inward-issue`.

Because the conventions are mirror images, read the link back after every write and check the phrasing (see [Verify and remove](#verify-and-remove)).

### Create a link

**Injected-token REST (path 1):**

```bash
cat > /tmp/issuelink.json << 'EOF'
{"type": {"name": "Relates"}, "inwardIssue": {"key": "PROJ-1022"}, "outwardIssue": {"key": "OTHER-2096"}}
EOF
curl -sS -o /dev/null -w '%{http_code}\n' -u "$ATLASSIAN_USER_EMAIL:$JIRA_TOKEN" -X POST \
  -H "Content-Type: application/json" --data @/tmp/issuelink.json \
  "https://api.atlassian.com/ex/jira/$CLOUD_ID/rest/api/3/issueLink" # 201, empty body
```

To record "PROJ-1022 **is blocked by** OTHER-2096", use `"type": {"name": "Blocks"}` with `outwardIssue` = the blocker (`OTHER-2096`) and `inwardIssue` = the blocked ticket (`PROJ-1022`).

**MCP / `atlassian` CLI (paths 2–3):** the tool is `createIssueLink` (there is no `linkJiraIssues`); `getIssueLinkTypes` lists the types. Mind the inverted direction — the blocker is `--inward-issue`:

```bash
# "PROJ-1022 is blocked by OTHER-2096" → blocker OTHER-2096 is the inward issue here:
atlassian createIssueLink --cloud-id "<cloud-id>" \
  --type Blocks --inward-issue OTHER-2096 --outward-issue PROJ-1022
# Non-directional "relates to" — either order reads the same:
atlassian createIssueLink --cloud-id "<cloud-id>" \
  --type Relates --inward-issue PROJ-1022 --outward-issue OTHER-2096
```

If only the MCP tool is exposed (no generated CLI flags), send the arguments object with the documented workaround:

```bash
cat > /tmp/link-args.json << 'EOF'
{"cloudId": "<cloud-id>", "type": "Relates", "inwardIssue": "PROJ-1022", "outwardIssue": "OTHER-2096"}
EOF
npx -y mcporter call atlassian createIssueLink --args "$(cat /tmp/link-args.json)"
```

### Verify and remove

Read the link back from either path to confirm the direction:

```bash
atlassian getJiraIssue --cloud-id "<cloud-id>" --issue-id-or-key PROJ-1022 --fields issuelinks
```

Each entry in `fields.issuelinks` carries the `type`, its own `id`, and one of `outwardIssue` / `inwardIssue` (the issue on the far end). A `Relates` entry pointing at `OTHER-2096` confirms the worked example above.

Remove a link by its `id`:

```bash
# Injected-token REST (path 1):
curl -sS -o /dev/null -w '%{http_code}\n' -u "$ATLASSIAN_USER_EMAIL:$JIRA_TOKEN" -X DELETE \
  "https://api.atlassian.com/ex/jira/$CLOUD_ID/rest/api/3/issueLink/<linkId>" # 204
```

The MCP / CLI paths expose **no** delete-link tool, and `editJiraIssue` with `update.issuelinks[].remove` is silently ignored — remove a link via the injected-token REST `DELETE` above (it needs the **Link Issues** project permission) or the Jira web UI.

---

# Confluence

## Confluence Values That Must Come from Preferences or User Input

Never hardcode these values:

- Confluence space key (for example, `MW`, `DevOps`)
- Confluence site URL (typically shared with Jira cloud URL)
- Page hierarchy / parent page IDs (when creating nested pages)

## Reading a Confluence Page

- Use `getConfluencePage` (MCP) or `atlassian getConfluencePage` (CLI).
- Provide the `pageId` parameter.
- The response includes the page content in Confluence storage format (XHTML-based). Convert to markdown for presentation.

## Searching Confluence

- Use the Atlassian unified `search` tool, or the dedicated `searchConfluenceUsingCql` (MCP) tool.
- CQL (Confluence Query Language) examples:
  - Search by space: `space = "MW"`
  - Search by title: `title ~ "deployment"`
  - Search by text content: `text ~ "CircleCI" AND space = "DevOps"`
  - Search recent pages: `type = page AND space = "MW" ORDER BY lastModified DESC`

## Creating a Confluence Page

- Use `createConfluencePage` (MCP) or `atlassian createConfluencePage` (CLI).
- Required parameters:
  - `spaceId` or `spaceKey` — the target space
  - `title` — page title
  - `body` — page content in Confluence storage format (XHTML). Use markdown-to-HTML conversion or the `representation` parameter if supported.
- Optional parameters:
  - `parentId` — to create a child page under an existing parent

### Converting Markdown to Confluence Storage Format

When creating or editing pages, convert markdown to Confluence storage format:

- **Headers**: `<h1>Heading</h1>`, `<h2>Heading</h2>`, etc.
- **Paragraphs**: `<p>text</p>`
- **Lists**: `<ul><li>item</li></ul>` (unordered), `<ol><li>item</li></ol>` (ordered)
- **Bold**: `<strong>text</strong>`
- **Code blocks**: Use `<ac:structured-macro ac:name="code"><ac:plain-text-body><![CDATA[code here]]></ac:plain-text-body></ac:structured-macro>`
- **Inline code**: `<code>code</code>`
- **Links**: `<a href="URL">Link text</a>`
- **Tables**: Use standard `<table>`, `<tr>`, `<td>` HTML

If the MCP tool supports `representation: "markdown"`, use that instead of manual conversion.

## Editing a Confluence Page

- Use `updateConfluencePage` (MCP) or `atlassian updateConfluencePage` (CLI).
- Required parameters:
  - `pageId` — the page to update
  - `body` — the new content (or the full content including existing sections you want to keep)
  - `version` — increment the version number from the current page version (fetch current version first via `getConfluencePage`)
- Important: Confluence page updates are **full replacements** of the body content. To edit part of a page:
  1. Fetch the current page with `getConfluencePage`
  2. Modify the content
  3. Send the complete updated content with the incremented version number

### Confluence Page Versioning

Always fetch the current page version before editing:

```text
1. getConfluencePage(pageId=...) → note the version.number
2. updateConfluencePage(pageId=..., body=..., version={ number: <current + 1> })
```

Failure to increment the version will result in a conflict error.

## Confluence Formatting Guidelines

- Use Confluence storage format (XHTML-based) for page body content.
- When displaying page content to users, convert to readable markdown.
- For code blocks, always use the `code` macro with `ac:structured-macro` syntax.
- Preserve existing formatting when editing — do not strip or reformat content you are not changing.

## Authentication (CLI)

### Check if auth is already working

Before attempting any Atlassian operation, verify that authentication is valid:

```bash
atlassian atlassianUserInfo
```

This is a read-only token check — it does **not** open a browser. If it returns user info (account_id, name, email), auth is working. Proceed with normal operations.

### If auth is broken

`atlassianUserInfo` failing means either the token path was not selected (re-check the env vars from
[Secrets auto-load](#secrets-file-auto-load)) or the CLI's own OAuth state is stale. Do **not**
follow the CLI's browser OAuth flow when it offers one — it can throw internal server errors.
Re-auth through MCPorter instead, which needs human interaction and should not be run proactively:

```bash
npx mcporter auth atlassian        # opens a browser
atlassian atlassianUserInfo        # re-verify
```

If the CLI is not on PATH at all, it is generated from the MCP server config already persisted in
`~/.mcporter/mcporter.json`:

```bash
npx mcporter config add atlassian --url https://mcp.atlassian.com/v1/mcp --auth oauth --config ~/.mcporter/mcporter.json
pushd ~/.local/bin && npx mcporter generate-cli --server https://mcp.atlassian.com/v1/mcp --compile
atlassian --help
```

Persist the config with `--auth oauth`, otherwise the browser flow can fail with 401.

---

# Advanced Workflow: Fetch, Review, Edit

This section covers advanced CLI patterns for fetching Jira tickets, reviewing changes locally, and editing with user approval.

## 1. Fetch the Current Jira Issue

Use `tee` with process substitution to write the full JSON response to a file **while also** displaying it in the terminal:

```bash
atlassian getJiraIssue \
  --cloud-id "<cloud-id>" \
  --issue-id-or-key ABC-123 \
  --response-content-format markdown \
  | tee /tmp/abc-123.json \
  >(jq -r '.fields.description' > /tmp/abc-123-description.md)
```

This writes:

- Full JSON → `/tmp/abc-123.json` AND stdout
- Description as plain text → `/tmp/abc-123-description.md`

This is bash/zsh-style process substitution and is **not** supported in plain POSIX `sh`; run this example in `bash` or `zsh`.

## 2. Edit the issue description

- Put proposed new content in `/tmp/abc-123-proposed.md`
- Let the user compare the two with their preferred diff tool:

```bash
# Terminal
diff /tmp/abc-123-description.md /tmp/abc-123-proposed.md

# You can use VS Code's --diff flag
code --diff /tmp/abc-123-description.md /tmp/abc-123-proposed.md
```

## 3. Let the User Tweak

After the agent proposes changes, the user can review and modify the proposed content before the edit is submitted.

## 4. Agent submits the edited file

```bash
atlassian editJiraIssue \
  --cloud-id "<cloud-id>" \
  --issue-id-or-key ABC-123 \
  --fields "$(jq -n --rawfile desc /tmp/abc-123-proposed.md '{description: $desc}')" \
  --content-format markdown
```

`--rawfile` reads the file directly and preserves trailing newlines that `$(cat ...)` and `--arg` can silently drop.
