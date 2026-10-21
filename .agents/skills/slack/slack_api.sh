#!/usr/bin/env bash
set -euo pipefail

# slack_api.sh — Raw Slack Web API helper (no mcporter, no MCP server)
# Dependencies: curl, jq
#
# Usage:
#   slack_api.sh <workspace> <command> [args...] [--raw]
#
# Workspaces map to env files in ~/secrets/env/:
#   <ws>   → slack_<ws>.env
#   <ws2> → slack_<ws2>.env
#
# Commands:
#   auth-test                          Verify tokens are valid
#   channels [types] [limit]           List channels (types: public_channel,private_channel,im,mpim)
#   history <channel_id> [limit]       Get channel/DM message history
#   search <query>                     Search messages (supports Slack search syntax)
#   send <channel_id> <text> [ts]      Send a message (optionally as thread reply)
#   replies <channel_id> <ts>          Get all replies in a thread
#   mark <channel_id> [ts]             Mark channel as read (up to ts, or fully)
#   users [limit]                      List workspace users
#   info <channel_id>                  Get info about a channel/DM
#   dm <user_id_or_email>              Resolve a user to their DM channel ID
#
# Examples:
#   slack_api.sh <ws> channels im,public_channel 200
#   slack_api.sh <ws> history D0123456789 50
#   slack_api.sh <ws> search "from:@jake deployment"
#   slack_api.sh <ws> send C012A30B73L "Hello!"
#   slack_api.sh <ws> send C012A30B73L "Reply" 1234567890.123456
#   slack_api.sh <ws> replies C012A30B73L 1234567890.123456
#   slack_api.sh <ws> mark C012A30B73L
#   slack_api.sh <ws> dm someone@example.com
#
# Token extraction (from browser):
#   1. Log in to the workspace at <workspace>.slack.com
#   2. DevTools → Application → Cookies → find cookie named "d" → value starts with xoxd- → SLACK_XOXD_TOKEN
#   3. DevTools → Network → find any request to slack.com/api/* → look for "token" param → starts with xoxc- → SLACK_XOXC_TOKEN

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS_DIR="${SLACK_SECRETS_DIR:-$HOME/secrets/env}"
SLACK_API="https://slack.com/api"
RAW=false

# ── Workspace resolution ──────────────────────────────────────────

resolve_workspace() {
  local ws="$1"
  local env_file

  # If tokens already in env, use them directly
  if [[ -n "${SLACK_XOXC_TOKEN:-}" && -n "${SLACK_XOXD_TOKEN:-}" ]]; then
    return 0
  fi

  case "$ws" in
    *) env_file="$SECRETS_DIR/slack_${ws}.env" ;;
  esac

  if [[ ! -f "$env_file" ]]; then
    echo "ERROR: Secrets file not found: $env_file" >&2
    echo "Create it with SLACK_XOXC_TOKEN and SLACK_XOXD_TOKEN." >&2
    echo "Harvest tokens from your browser session (see SKILL.md)." >&2
    exit 1
  fi

  set -a; source "$env_file"; set +a
}

check_tokens() {
  : "${SLACK_XOXC_TOKEN:?SLACK_XOXC_TOKEN is not set (source the env file or create ~/secrets/env/slack_<workspace>.env)}"
  : "${SLACK_XOXD_TOKEN:?SLACK_XOXD_TOKEN is not set}"
}

# ── API helpers ───────────────────────────────────────────────────
# Auth: token as query/form param + d cookie (matches browser behavior)

slack_get() {
  local endpoint="$1"; shift
  curl -sS -G "${SLACK_API}/${endpoint}" \
    -H "Cookie: d=${SLACK_XOXD_TOKEN}" \
    --data-urlencode "token=${SLACK_XOXC_TOKEN}" \
    "$@"
}

slack_post() {
  local endpoint="$1"; shift
  curl -sS "${SLACK_API}/${endpoint}" \
    -H "Cookie: d=${SLACK_XOXD_TOKEN}" \
    --data-urlencode "token=${SLACK_XOXC_TOKEN}" \
    "$@"
}

# ── Output helpers ────────────────────────────────────────────────

check_ok() {
  local json="$1"
  local ok
  ok=$(echo "$json" | jq -r '.ok // false')
  if [[ "$ok" != "true" ]]; then
    echo "ERROR: Slack API returned error:" >&2
    echo "$json" | jq '.error // . | {ok, error}' >&2
    return 1
  fi
}

# ── Commands ──────────────────────────────────────────────────────

cmd_auth_test() {
  local resp
  resp=$(slack_get auth.test)
  check_ok "$resp" || return 1
  if $RAW; then echo "$resp" | jq .; return; fi
  echo "$resp" | jq -r '"✓ Authenticated as \(.user) in team \(.team) (\(.team_id))\n  User ID: \(.user_id)\n  URL: \(.url)"'
}

cmd_channels() {
  local types="${1:-public_channel,private_channel,im,mpim}"
  local limit="${2:-200}"
  local resp
  resp=$(slack_get conversations.list \
    --data-urlencode "types=${types}" \
    --data-urlencode "limit=${limit}")
  check_ok "$resp" || return 1
  if $RAW; then echo "$resp" | jq .; return; fi
  echo "$resp" | jq -r '.channels[] | [
    .id,
    (.name // .user // "?"),
    (if .is_im then "DM" elif .is_mpim then "group-DM" elif .is_private then "private" else "public" end),
    (.num_members // "-" | tostring)
  ] | @tsv' | column -t -N "ID,NAME,TYPE,MEMBERS"
}

cmd_history() {
  local channel="$1"
  local limit="${2:-50}"
  local resp
  resp=$(slack_get conversations.history \
    --data-urlencode "channel=${channel}" \
    --data-urlencode "limit=${limit}")
  check_ok "$resp" || return 1
  if $RAW; then echo "$resp" | jq .; return; fi
  echo "$resp" | jq -r '.messages[] | "[\(.ts)] \(if .subtype then "(" + .subtype + ") " else "" end)\(.user // .bot_id // "unknown"): \(.text // "[non-text]")"' 2>/dev/null || echo "$resp" | jq .
}

cmd_search() {
  local query="$1"
  local resp
  resp=$(slack_get search.messages \
    --data-urlencode "query=${query}" \
    --data-urlencode "count=50")
  check_ok "$resp" || return 1
  if $RAW; then echo "$resp" | jq .; return; fi
  echo "$resp" | jq -r '.messages.matches[] | "[\(.ts)] #\(.channel.name) \(.username // .user // "?"):\n  \(.text)\n"' 2>/dev/null || echo "$resp" | jq .
}

cmd_send() {
  local channel="$1"
  local text="$2"
  local thread_ts="${3:-}"
  local resp
  if [[ -n "$thread_ts" ]]; then
    resp=$(slack_post chat.postMessage \
      --data-urlencode "channel=${channel}" \
      --data-urlencode "text=${text}" \
      --data-urlencode "thread_ts=${thread_ts}")
  else
    resp=$(slack_post chat.postMessage \
      --data-urlencode "channel=${channel}" \
      --data-urlencode "text=${text}")
  fi
  check_ok "$resp" || return 1
  if $RAW; then echo "$resp" | jq .; return; fi
  echo "$resp" | jq -r '"✓ Sent (ts: \(.ts), channel: \(.channel))"'
}

cmd_replies() {
  local channel="$1"
  local ts="$2"
  local resp
  resp=$(slack_get conversations.replies \
    --data-urlencode "channel=${channel}" \
    --data-urlencode "ts=${ts}")
  check_ok "$resp" || return 1
  if $RAW; then echo "$resp" | jq .; return; fi
  echo "$resp" | jq -r '.messages[] | "[\(.ts)] \(.user // .bot_id // "unknown"): \(.text // "[non-text]")"' 2>/dev/null || echo "$resp" | jq .
}

cmd_mark() {
  local channel="$1"
  local ts="${2:-}"
  local resp
  if [[ -n "$ts" ]]; then
    resp=$(slack_post conversations.mark \
      --data-urlencode "channel=${channel}" \
      --data-urlencode "ts=${ts}")
  else
    resp=$(slack_post conversations.mark \
      --data-urlencode "channel=${channel}")
  fi
  check_ok "$resp" || return 1
  if $RAW; then echo "$resp" | jq .; return; fi
  echo "✓ Marked $channel as read"
}

cmd_users() {
  local limit="${1:-200}"
  local resp
  resp=$(slack_get users.list \
    --data-urlencode "limit=${limit}")
  check_ok "$resp" || return 1
  if $RAW; then echo "$resp" | jq .; return; fi
  echo "$resp" | jq -r '.members[] | [.id, .name, (.profile.email // "-")] | @tsv' | column -t -N "ID,USERNAME,EMAIL"
}

cmd_info() {
  local channel="$1"
  local resp
  resp=$(slack_get conversations.info \
    --data-urlencode "channel=${channel}")
  check_ok "$resp" || return 1
  echo "$resp" | jq .
}

cmd_dm() {
  local user="$1"
  local resp
  # Try to open a DM conversation with the user (returns the DM channel ID)
  resp=$(slack_post conversations.open \
    --data-urlencode "users=${user}")
  check_ok "$resp" || return 1
  if $RAW; then echo "$resp" | jq .; return; fi
  echo "$resp" | jq -r '.channel.id'
}

# ── Main dispatch ─────────────────────────────────────────────────

main() {
  if [[ $# -lt 2 ]]; then
    grep '^#' "$0" | head -30
    exit 1
  fi

  local workspace="$1"; shift
  local command="$1"; shift

  # Check for --raw flag
  for arg in "$@"; do
    if [[ "$arg" == "--raw" ]]; then
      RAW=true
      # Remove --raw from args
      local new_args=()
      for a in "$@"; do [[ "$a" != "--raw" ]] && new_args+=("$a"); done
      set -- "${new_args[@]}"
      break
    fi
  done

  resolve_workspace "$workspace"
  check_tokens

  case "$command" in
    auth-test)    cmd_auth_test ;;
    channels)     cmd_channels "$@" ;;
    history)      cmd_history "$@" ;;
    search)       cmd_search "$@" ;;
    send)         cmd_send "$@" ;;
    replies)      cmd_replies "$@" ;;
    mark)         cmd_mark "$@" ;;
    users)        cmd_users "$@" ;;
    info)         cmd_info "$@" ;;
    dm)           cmd_dm "$@" ;;
    *)            echo "Unknown command: $command" >&2; exit 1 ;;
  esac
}

main "$@"