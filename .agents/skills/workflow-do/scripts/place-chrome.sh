#!/bin/bash
# place-chrome.sh — ask the HOST to place + fill this run's Chrome window.
#
# Stage agents run inside a cage where `niri msg` CANNOT work: /usr/bin/niri is the host's
# binary bind-mounted read-only, built against a newer glibc/libdisplay-info/libinput than the
# cage base image provides (libdisplay-info.so.3 / GLIBC_2.43 / LIBINPUT_1.30 missing), so any
# `niri msg ...` from a stage fails silently and the placement step no-ops.
#
# zellij commands are executed by the HOST daemon, so this shim starts a short-lived host pane
# that runs ~/.local/bin/workflow-chrome-place (host PATH). Call it from the stage instead of
# calling niri directly:
#     bash ~/.agents/skills/workflow-do/scripts/place-chrome.sh            # title "Google Chrome"
#     bash ~/.agents/skills/workflow-do/scripts/place-chrome.sh "Notion"   # match another title
# usage: place-chrome.sh [title-substring] [monitor-name]
set -uo pipefail

RUN_ENV="${WORKFLOW_RUN_ENV:-/tmp/workflow-run.env}"
TAB="${WORKFLOW_TAB_ID:-$(sed -n 's/^WORKFLOW_TAB_ID="\(.*\)"$/\1/p' "$RUN_ENV" 2>/dev/null | tail -1)}"
TICKET="${TICKET_ID:-$(sed -n 's/^TICKET_ID="\(.*\)"$/\1/p' "$RUN_ENV" 2>/dev/null | tail -1)}"
# Default match is the ticket id (present in the PR/Notion tab title, e.g. "<KEY-185> … · Pull Request #298").
# The generic "Google Chrome" pattern is a poor default when several cages are live — it can move ANOTHER
# run's window (it did on 2026-09-30), so prefer an explicit distinctive substring.
TITLE="${1:-${TICKET:-Google Chrome}}"
MON="${2:-${NIRI_CHROME_MONITOR:-HDMI-A-3}}"
if [ -z "$TAB" ]; then
  echo "place-chrome: no WORKFLOW_TAB_ID (env or $RUN_ENV) — skipping host-side placement" >&2
  exit 0
fi

zellij run --tab-id "$TAB" --name chrome-place --close-on-exit -- \
  bash -lc "workflow-chrome-place \"$TITLE\" \"$MON\"" >/dev/null 2>&1 \
  && echo "place-chrome: host-side placement requested (tab $TAB, title '$TITLE', monitor $MON)" \
  || echo "place-chrome: could not reach the host zellij daemon — placement skipped"
