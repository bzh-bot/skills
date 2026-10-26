#!/bin/bash
# zellij-wrapper.sh — forwards `zellij action` commands to the host via TCP proxy.
#
# On macOS, the host's zellij Unix socket can't be mounted into the container
# (VirtioFS limitation). The cage function starts a socat TCP proxy on the host
# that accepts action commands. This wrapper:
#   1. Strips a leading `--session <name>` (pi/tools often pass this; the host's
#      session is already fixed by the proxy, so we ignore any override).
#   2. If the resulting first arg is `action`, forwards the rest to the TCP proxy.
#   3. If it's `list-panes` (a common non-action subcommand pi calls), maps it
#      to `action list-panes` (equivalent for our purposes) and forwards.
#   4. Otherwise, exec the real zellij binary.
#
# Each argument is shell-escaped with printf %q so that eval on the host
# correctly handles spaces, quotes, and special characters.
# The `sleep 0.5` keeps the TCP connection open briefly after sending the
# command so the zellij server has time to send its response back.

# Strip optional leading `--session <name>`
if [ "$1" = "--session" ] && [ -n "$2" ]; then
  shift 2
fi

subcmd="${1:-}"

forward_action() {
  local quoted=""
  local arg q
  for arg in "$@"; do
    printf -v q '%q' "$arg"
    quoted="$quoted $q"
  done
  (printf '%s\n' "${quoted# }"; sleep 0.5) | socat - TCP:host.docker.internal:"$WORKFLOW_ZELLIJ_TCP_PORT"
}

if [ -n "$WORKFLOW_ZELLIJ_TCP_PORT" ]; then
  case "$subcmd" in
    action)
      shift
      forward_action "action" "$@"
      exit $?
      ;;
    run)
      # The sequencer launches every stage pane with `zellij --session <s> run
      # --tab-id <n> --name <pane> …`, so `run` MUST be forwarded too — without
      # this the wrapper exec'd zellij.real inside the cage (no server there) and
      # every stage launch failed, killing each run into the pi fallback
      # (2026-10-26).
      shift
      forward_action "run" "$@"
      exit $?
      ;;
    list-panes|list-tabs|list-sessions|list-clients)
      # Some non-action subcommands are usable via `action <same-name>` on the
      # host session. Forward them so scripts written for host-zellij work
      # inside the cage.
      forward_action "action" "$@"
      exit $?
      ;;
  esac
fi

exec /usr/local/bin/zellij.real "$@"
