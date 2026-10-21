---
name: slack
description: Interact with Slack workspaces via the Slack Web API (raw curl, no MCP server). Search messages, list channels, send messages, read threads, and more. Use when asked to search Slack, read channel history, send messages, or interact with Slack.
metadata:
  author: personal
  version: "2.0.0"
---

# Slack Web API (Raw)

Interact with Slack directly via the **Slack Web API** using `curl` + `jq`. No mcporter, no MCP server, no external tools beyond curl and jq.

## Prerequisites

- `curl` and `jq` (both standard on most systems)
- Browser session tokens (`xoxc` + `xoxd`) harvested from a logged-in Slack session

## Authentication

The Slack Web API authenticates using **browser session tokens** (not OAuth2, not bot tokens). Each workspace requires two values:

| Variable           | Source                              | Description               |
| ------------------ | ----------------------------------- | ------------------------- |
| `SLACK_XOXC_TOKEN`  | DevTools → Network → `token` param  | User session token (`xoxc-...`) |
| `SLACK_XOXD_TOKEN`  | DevTools → Cookies → `d` cookie     | Session cookie (`xoxd-...`) |

Auth is sent as:
- `token` query/form parameter (matches browser behavior)
- `d` cookie via `Cookie: d=<xoxd-token>` header

## Token Extraction (from browser)

### Automated refresh via agent-browser skill (preferred)

When tokens are expired (`invalid_auth`), use the **agent-browser** skill to refresh them without manual DevTools work:

1. **Ensure Chrome is debuggable** (use the agent-browser bootstrap helper with the appropriate profile for the workspace):
   ```bash
   curl -s --max-time 2 http://127.0.0.1:9222/json/version >/dev/null && echo READY   # see agent-browser "Attach checklist"
   ```

2. **Open Slack** in the browser (navigate to the workspace URL):
   ```bash
   agent-browser --auto-connect --headed open "https://<workspace>.slack.com"
   agent-browser --auto-connect --headed wait --load networkidle
   agent-browser --auto-connect --headed wait 2000
   ```

3. **Extract `SLACK_XOXC_TOKEN`** from localStorage (Slack stores the session token in `localConfig_v2`):
   ```bash
   agent-browser --auto-connect --headed eval "
     (function() {
       var v = localStorage.getItem('localConfig_v2');
       if (!v) return 'NOT_FOUND';
       var m = v.match(/xoxc-[^\"']+/);
       return m ? m[0] : 'NO_XOXC_IN_VALUE';
     })()
   "
   ```

4. **Extract `SLACK_XOXD_TOKEN`** from Chrome's HttpOnly cookies via CDP (the `d` cookie is HttpOnly so `document.cookie` cannot read it). Use the WebSocket debugger URL from `http://localhost:9222/json` and send a `Network.getCookies` CDP command:
   ```bash
   # Get the Slack tab's WebSocket debugger URL
   WS_URL=$(curl -s http://localhost:9222/json | jq -r '[.[] | select(.url | test("slack.com/client"))] | .[0].webSocketDebuggerUrl')
   
   # Send CDP command to get cookies (requires the `ws` module — available in any Next.js project's node_modules)
   cd <any-nextjs-project>/node_modules/.pnpm/next@*/node_modules/next/dist/compiled
   node -e "
     const WebSocket = require('./ws');
     const ws = new WebSocket('$WS_URL');
     ws.on('open', () => {
       ws.send(JSON.stringify({id:1, method:'Network.getCookies', params:{urls:['https://slack.com','https://app.slack.com','https://<workspace>.slack.com']}}));
     });
     ws.on('message', (data) => {
       const resp = JSON.parse(data);
       if (resp.id === 1) {
         const d = resp.result?.cookies?.find(c => c.name === 'd' && c.value.startsWith('xoxd-'));
         console.log(d ? d.value : 'NOT_FOUND');
         ws.close();
       }
     });
   "
   ```

5. **Write tokens** back to the env file:
   ```bash
   # Edit your env file for <workspace> and replace the SLACK_XOXC_TOKEN and SLACK_XOXD_TOKEN values
   ```

6. **Verify** the new tokens work:
   ```bash
   set -a; source "$SLACK_ENV"   # e.g. ~/.config/slack/<workspace>.env; set +a
   curl -sS -G "https://slack.com/api/auth.test" \
     -H "Cookie: d=${SLACK_XOXD_TOKEN}" \
     --data-urlencode "token=${SLACK_XOXC_TOKEN}" | jq '{ok, user, team}'
   ```

### Manual extraction (fallback)

If the agent-browser skill is unavailable, extract tokens manually via DevTools:

1. Open `https://<workspace>.slack.com` in your browser → log in
2. Open **DevTools** (F12)
3. **For `xoxd`**: Application tab → Cookies → `https://<workspace>.slack.com` → find cookie named **`d`** → value starts with `xoxd-` → copy it
4. **For `xoxc`**: Network tab → filter by `slack.com/api` → click any request → find the **`token`** parameter in the request → value starts with `xoxc-` → copy it
5. Store them in a per-workspace env file of your choosing (see below)

> **Token expiry**: These are session tokens. They expire on logout, session timeout, or when Slack rotates them. Re-harvest if you get auth errors.

## Secrets Files

One env file per workspace, kept outside this repo (any private directory works; `~/.config/slack/` is a common choice):

```bash
# ~/.config/slack/<ws>.env
# Slack session tokens for workspace <ws> (<ws>.slack.com)
# Harvested from browser session — expires on logout/session end

SLACK_XOXC_TOKEN="xoxc-..."
SLACK_XOXD_TOKEN="xoxd-..."
SLACK_WORKSPACE="ws-alias"
SLACK_WORKSPACE_URL="<ws>.slack.com"
```

```bash
# ~/.config/slack/<ws2>.env
SLACK_XOXC_TOKEN="xoxc-..."
SLACK_XOXD_TOKEN="xoxd-..."
SLACK_WORKSPACE="ws2-alias"
SLACK_WORKSPACE_URL="ws2.slack.com"
```

Load credentials before making API calls:

```bash
set -a; source ~/.config/slack/<ws>.env; set +a
```

## Helper Script

A helper script wraps the common API calls with auth, error checking, and output formatting:

```bash
~/.pi/agent/skills/slack/slack_api.sh
```

Usage: `slack_api.sh <workspace> <command> [args] [--raw]`

| Command | Args | Description |
|---------|------|-------------|
| `auth-test` | — | Verify tokens are valid |
| `channels` | `[types] [limit]` | List channels (types: `public_channel,private_channel,im,mpim`) |
| `history` | `<channel_id> [limit]` | Get channel/DM message history |
| `search` | `<query>` | Search messages (Slack search syntax) |
| `send` | `<channel_id> <text> [thread_ts]` | Send a message (optionally as thread reply) |
| `replies` | `<channel_id> <thread_ts>` | Get all replies in a thread |
| `mark` | `<channel_id> [ts]` | Mark channel as read |
| `users` | `[limit]` | List workspace users |
| `info` | `<channel_id>` | Get info about a channel/DM |
| `dm` | `<user_id>` | Resolve a user to their DM channel ID |

Add `--raw` for unformatted JSON output.

### Examples

```bash
# Verify auth
slack_api.sh <ws> auth-test

# List all channels including DMs
slack_api.sh <ws> channels public_channel,private_channel,im,mpim

# List only DMs
slack_api.sh <ws> channels im

# Read recent DM history
slack_api.sh <ws> history D0123456789 50

# Search for messages
slack_api.sh <ws> search "from:@jake deployment"
slack_api.sh <ws> search "in:#incidents outage"
slack_api.sh <ws> search "after:2025-01-01 before:2025-02-01"

# Send a message
slack_api.sh <ws> send C012A30B73L "Hello from the agent!"

# Reply in a thread
slack_api.sh <ws> send C012A30B73L "Replying to thread" 1234567890.123456

# Get thread replies
slack_api.sh <ws> replies C012A30B73L 1234567890.123456

# Mark channel as read
slack_api.sh <ws> mark C012A30B73L

# List users (to find user IDs / DM targets)
slack_api.sh <ws> users

# Get a user's DM channel ID
slack_api.sh <ws> dm U0123456789

# Raw JSON output
slack_api.sh <ws> channels im --raw
```

## Raw API Reference

If you need to call endpoints not covered by the helper script, use curl directly:

### GET requests

```bash
curl -sS -G "https://slack.com/api/<endpoint>" \
  -H "Cookie: d=${SLACK_XOXD_TOKEN}" \
  --data-urlencode "token=${SLACK_XOXC_TOKEN}" \
  --data-urlencode "param=value" | jq
```

### POST requests

```bash
curl -sS "https://slack.com/api/<endpoint>" \
  -H "Cookie: d=${SLACK_XOXD_TOKEN}" \
  --data-urlencode "token=${SLACK_XOXC_TOKEN}" \
  --data-urlencode "param=value" | jq
```

### Key endpoints

| Endpoint | Method | Key params |
|----------|--------|------------|
| `auth.test` | GET | — |
| `conversations.list` | GET | `types`, `limit`, `cursor` |
| `conversations.history` | GET | `channel`, `limit`, `oldest`, `latest`, `cursor` |
| `conversations.replies` | GET | `channel`, `ts`, `limit`, `cursor` |
| `conversations.info` | GET | `channel` |
| `conversations.mark` | POST | `channel`, `ts` |
| `conversations.open` | POST | `users` (comma-separated user IDs) |
| `chat.postMessage` | POST | `channel`, `text`, `thread_ts` |
| `search.messages` | GET | `query`, `count`, `page` |
| `users.list` | GET | `limit`, `cursor` |
| `users.info` | GET | `user` |

### Slack search syntax

| Filter | Example | Meaning |
|--------|---------|---------|
| `from:` | `from:@jake` | Messages from a user |
| `in:` | `in:#incidents` | Messages in a channel |
| `after:` | `after:2025-01-01` | Messages after a date |
| `before:` | `before:2025-02-01` | Messages before a date |
| `during:` | `during:2025-01` | Messages during a month |
| `has:` | `has:thread` | Messages with threads |
| `has:` | `has:link` | Messages with links |
| `-` | `-from:@bot` | Negate a filter |

Combine: `from:@jake in:#deployments after:2025-01-01`

## Channel/User ID Formats

| Format | Example | Type |
|--------|---------|------|
| `C...` | `C012A30B73L` | Public channel |
| `G...` | `G0123456789` | Private channel / group DM |
| `D...` | `D0123456789` | Direct message |
| `U...` | `U0123456789` | User ID |

## Pagination

List endpoints return `response_metadata.next_cursor`. To paginate:

```bash
cursor=""
while true; do
  resp=$(curl -sS -G "https://slack.com/api/conversations.list" \
    -H "Cookie: d=${SLACK_XOXD_TOKEN}" \
    --data-urlencode "token=${SLACK_XOXC_TOKEN}" \
    --data-urlencode "types=public_channel,im" \
    --data-urlencode "limit=200" \
    --data-urlencode "cursor=${cursor}")
  echo "$resp" | jq '.channels[]'
  cursor=$(echo "$resp" | jq -r '.response_metadata.next_cursor // empty')
  [[ -z "$cursor" ]] && break
done
```

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `{"ok":false,"error":"invalid_auth"}` | Missing or expired tokens | Re-harvest `xoxc` and `xoxd` from browser |
| `{"ok":false,"error":"channel_not_found"}` | Wrong channel ID or no access | Verify channel ID; check token has access |
| `{"ok":false,"error":"not_authed"}` | Token parameter missing | Ensure `SLACK_XOXC_TOKEN` is set and sourced |
| Empty results on search | Search requires user-level token | `xoxc` session tokens should work; verify token is fresh |
| `{"ok":false,"error":"ratelimited"}` | Too many requests | Slow down; add sleep between calls |

## Sending Messages

### Style

Messages must be **concise and professional**. Lead with the key point, keep it short, and avoid excessive formatting. Do not use emojis.

### Human confirmation required

**Never send a message without explicit confirmation from the human operator.** Always draft the message, present it in chat, and wait for the operator to say "send" (or equivalent) before calling `chat.postMessage`. This applies to DMs, channel messages, and thread replies alike.

⚠️ The helper script's `send` command works out of the box — no special enablement needed (unlike the old MCP server). Always verify the response contains `ok: true` and a `ts` field before assuming the message was posted.

## Workspace-Specific Skills

For per-workspace usage with auto-loaded credentials, see:
- `<org>-slack` — org-specific workspace skill (kept in that org's secrets repo)
- one env file per workspace; load the one you need

These skills source the right env file and reference this skill for API patterns.