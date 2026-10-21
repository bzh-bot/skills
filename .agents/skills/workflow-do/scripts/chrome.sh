#!/usr/bin/env bash
# chrome.sh — status / revive / port / probe for THIS run's Chrome, from inside the cage.
#
# Why this exists (2026-10-19, <KEY-209>/1210/1211/1212): the run Chrome used to be
# started through `agent-browser open`, whose launcher hardcodes
# `--remote-debugging-port=0` — an EPHEMERAL port. CHROME_CDP_PORT was never
# recorded, three of four runs lost their browser with no port on record, and every
# stage improvised its own relaunch (different port, different profile, sometimes a
# logged-out temp profile). This script is the ONE cage-safe recipe:
#   * a FIXED port, recorded as CHROME_CDP_PORT in the run env
#   * the run's own profile copy ($CHROME_SESSION_PROFILE), same profile on revive
#   * headed wayland ozone (never headless — the human watches this browser)
#   * never `--remote-debugging-port=0`
#   * an EXPLICIT window size, at least 1600x900 (CHROME_WINDOW_SIZE, default 1920,1080).
#     2026-10-19, live run: the window came up 948x947 and the video tour captured a
#     948x947 screencast — unusable for a 1600x900 cut. `--window-size` is required but
#     NOT sufficient under Wayland: niri is a tiling compositor and sizes the tile, so the
#     flag is a request the compositor may ignore. That is why `status`/`viewport` MEASURE
#     the real viewport over CDP and say when it is too small — the fix is then to widen
#     the niri column (or `place-chrome.sh` to fill the monitor), not to shrink the video.
# Agents must not hand-roll a launch: call `chrome.sh revive` instead.
#
# Usage:
#   bash ~/.agents/skills/workflow-do/scripts/chrome.sh status   # port / profile / pid / CDP alive / window + viewport / GitHub login (exit 1 when down)
#   bash ~/.agents/skills/workflow-do/scripts/chrome.sh revive   # idempotent: no-op when alive, else one relaunch
#   bash ~/.agents/skills/workflow-do/scripts/chrome.sh port     # print the recorded CDP port (empty if none)
#   bash ~/.agents/skills/workflow-do/scripts/chrome.sh probe    # exit 0 iff CDP answers on the recorded port
#   bash ~/.agents/skills/workflow-do/scripts/chrome.sh viewport # print "WxH" measured over CDP; exit 1 unless >= 1600x900
#
# Env: WORKFLOW_RUN_ENV (default /tmp/workflow-run.env). Values are read from it
# with source semantics (last KEY="value" wins) — never re-derived by hand.
set -uo pipefail

RUN_ENV="${WORKFLOW_RUN_ENV:-/tmp/workflow-run.env}"
CHROME_BIN="${CHROME_BIN:-/usr/bin/google-chrome}"
PORT_BASE="${WORKFLOW_CHROME_PORT_BASE:-9301}"
PORT_SPAN="${WORKFLOW_CHROME_PORT_SPAN:-90}"
# The video tour needs a 1600x900 frame, so the browser window must be at least that.
# 1920x1080 leaves room for browser chrome (tab strip + omnibox ~120 px) and still
# measures >= 1600x900 inside the page. Override with CHROME_WINDOW_SIZE=W,H (never smaller).
MIN_W=1600; MIN_H=900
WINDOW_SIZE="${CHROME_WINDOW_SIZE:-1920,1080}"
window_dims() { printf '%s' "$WINDOW_SIZE" | tr 'xX' ',' | awk -F, '{print ($1+0)" "($2+0)}'; }
validate_window_size() {
  local w h; read -r w h <<<"$(window_dims)"
  if [ "$w" -lt "$MIN_W" ] || [ "$h" -lt "$MIN_H" ]; then
    say "chrome.sh: CHROME_WINDOW_SIZE=$WINDOW_SIZE is smaller than ${MIN_W}x${MIN_H}. The video tour films a\n${MIN_W}x${MIN_H} frame, so a smaller window is refused — set CHROME_WINDOW_SIZE=${MIN_W},${MIN_H} or larger." >&2
    return 1
  fi
}

runvar() {
  [ -f "$RUN_ENV" ] || return 0
  sed -n "s/^$1=\"\(.*\)\"\$/\1/p" "$RUN_ENV" | tail -1
}

TICKET="$(runvar TICKET_ID)"
TICKET="${TICKET:-${TICKET_LABEL:-run}}"
SESSION="$(runvar CHROME_SESSION)"
SESSION="${SESSION:-chrome-$TICKET}"
PROFILE="$(runvar CHROME_SESSION_PROFILE)"
PROFILE="${PROFILE:-/tmp/chrome-profile-$TICKET}"
XDG_DATA="$(runvar CHROME_XDG_DATA_HOME)"
XDG_DATA="${XDG_DATA:-/tmp/xdg-$TICKET}"
PORT="$(runvar CHROME_CDP_PORT)"
LOG="/tmp/chrome-$TICKET.log"

say() { printf '%s\n' "$*"; }

append_runenv() { # append_runenv KEY VALUE  (single-line, plain — never backticks/$()
  local key="$1" value="$2"
  if printf '%s' "$value" | grep -q '["`]' || printf '%s' "$value" | grep -qF '$('; then
    say "chrome.sh: refusing to record $key (quotes/backtick/\$() are unsafe in the sourced run env)" >&2
    return 1
  fi
  mkdir -p "$(dirname "$RUN_ENV")" 2>/dev/null || true
  printf '%s="%s"\n' "$key" "$value" >>"$RUN_ENV"
}

cdp_alive() { # cdp_alive PORT
  curl -s --max-time 2 "http://127.0.0.1:$1/json/version" 2>/dev/null | grep -q '"Browser"'
}

tcp_open() { # tcp_open PORT
  timeout 1 bash -c "</dev/tcp/127.0.0.1/$1" >/dev/null 2>&1
}

main_pid() { # main_pid  (exactly ONE main chrome for this profile; children are excluded by the anchor)
  pgrep -u pc -f "^$CHROME_BIN.*user-data-dir=$PROFILE" 2>/dev/null | head -1
}

discover_port() { # recorded (if alive) → DevToolsActivePort → main process cmdline → recorded (even if dead)
  local p pid
  if [ -n "$PORT" ] && [ "$PORT" != "0" ] && cdp_alive "$PORT"; then printf '%s' "$PORT"; return 0; fi
  if [ -n "$(main_pid)" ]; then
    p="$(head -1 "$PROFILE/DevToolsActivePort" 2>/dev/null | tr -dc '0-9')"
    if [ -n "$p" ]; then printf '%s' "$p"; return 0; fi
    pid="$(main_pid)"
    p="$(tr '\0' '\n' <"/proc/$pid/cmdline" 2>/dev/null | sed -n 's/^--remote-debugging-port=\([0-9][0-9]*\)$/\1/p' | head -1)"
    if [ -n "$p" ]; then printf '%s' "$p"; return 0; fi
  fi
  if [ -n "$PORT" ] && [ "$PORT" != "0" ]; then printf '%s' "$PORT"; return 0; fi
  return 1
}

pick_port() { # never 0 — recorded/free port first, then a deterministic per-ticket spread
  local p i seed
  if [ -n "$PORT" ] && [ "$PORT" != "0" ]; then
    if cdp_alive "$PORT" || ! tcp_open "$PORT"; then printf '%s' "$PORT"; return 0; fi
    say "chrome.sh: recorded port $PORT is taken by another process — picking a free port" >&2
  fi
  seed=$(( $(printf '%s' "$TICKET" | cksum | awk '{print $1}') % PORT_SPAN ))
  for i in $(seq 0 $((PORT_SPAN - 1))); do
    p=$(( PORT_BASE + (seed + i) % PORT_SPAN ))
    if ! tcp_open "$p"; then printf '%s' "$p"; return 0; fi
  done
  say "chrome.sh: no free CDP port in $PORT_BASE-$((PORT_BASE + PORT_SPAN - 1))" >&2
  return 1
}

github_login() { # read-only cookie probe over CDP (no navigation, no new tab)
  local out user pidf probe
  # Throwaway session: never touch the run's own daemon (a different agent-browser
  # binary on PATH can replace a session's daemon, and the run's daemon owns the
  # pinned tabs). The probe only READS cookies; its daemon is killed immediately and
  # killing an ATTACHED daemon never stops the CDP Chrome.
  probe="chrome-preflight-$TICKET"
  out="$(XDG_DATA_HOME="$XDG_DATA" agent-browser --session "$probe" \
    --cdp "http://127.0.0.1:$1" cookies get --url https://github.com 2>/dev/null)"
  pidf="/run/user/1000/agent-browser/$probe.pid"
  [ -f "$pidf" ] && kill -9 "$(cat "$pidf")" 2>/dev/null
  rm -f "/run/user/1000/agent-browser/$probe."* 2>/dev/null || true
  user="$(printf '%s\n' "$out" | sed -n 's/^dotcom_user=//p' | head -1)"
  if printf '%s\n' "$out" | grep -q '^logged_in=yes$' && [ -n "$user" ]; then
    printf '%s' "$user"
    return 0
  fi
  return 1
}

viewport_of() { # viewport_of PORT → "WxH" measured in the live page (read-only; no navigation)
  # Same throwaway-session rule as github_login(): the run's own daemon owns the pinned
  # tabs, so we attach a probe, read innerWidth/innerHeight, and kill the probe.
  local probe out pidf
  probe="chrome-viewport-$TICKET"
  out="$(XDG_DATA_HOME="$XDG_DATA" agent-browser --session "$probe" \
    --cdp "http://127.0.0.1:$1" eval 'innerWidth+"x"+innerHeight' 2>/dev/null | tr -dc '0-9x')"
  pidf="/run/user/1000/agent-browser/$probe.pid"
  [ -f "$pidf" ] && kill -9 "$(cat "$pidf")" 2>/dev/null
  rm -f "/run/user/1000/agent-browser/$probe."* 2>/dev/null || true
  printf '%s' "$out"
  case "$out" in [0-9]*x[0-9]*) return 0 ;; *) return 1 ;; esac
}

viewport_ok() { # viewport_ok "WxH" → 0 when the page is at least MIN_WxMIN_H
  local w h
  w="$(printf '%s' "$1" | cut -dx -f1)"; h="$(printf '%s' "$1" | cut -dx -f2)"
  [ "${w:-0}" -ge "$MIN_W" ] && [ "${h:-0}" -ge "$MIN_H" ]
}

cmd_status() {
  local pid p alive login vp
  p="$(discover_port || true)"
  pid="$(main_pid)"
  say "run env:        $RUN_ENV"
  say "ticket:         $TICKET"
  say "session:        $SESSION"
  say "profile:        $PROFILE"
  say "chrome pid:     ${pid:-<none>}"
  say "window size:    $WINDOW_SIZE (requested; min ${MIN_W}x${MIN_H})"
  say "cdp port:       ${p:-<none>}   (CHROME_CDP_PORT=$(runvar CHROME_CDP_PORT || true))"
  if [ -z "$p" ]; then
    say "cdp:            DOWN (no port recorded and no live Chrome found)"
    say "next:           bash $0 revive"
    return 1
  fi
  if cdp_alive "$p"; then alive=up; else alive=down; fi
  say "cdp:            ${alive^^} (http://127.0.0.1:$p/json/version)"
  if [ "$alive" = up ]; then
    if vp="$(viewport_of "$p")"; then
      if viewport_ok "$vp"; then
        say "viewport:       $vp"
      else
        say "viewport:       $vp — TOO SMALL for a ${MIN_W}x${MIN_H} video frame"
        say "                fix: widen the niri column (or bash $(dirname "$0")/place-chrome.sh), then re-run status"
      fi
    else
      say "viewport:       unknown (could not measure over CDP)"
    fi
  fi
  if [ "$alive" = up ] && login="$(github_login "$p")"; then
    say "github login:   $login"
  elif [ "$alive" = up ]; then
    say "github login:   NOT LOGGED IN — sign in manually in the run Chrome window, then re-run status"
  else
    say "github login:   unknown (CDP down)"
  fi
  [ "$alive" = up ]
}

cmd_viewport() { # the gate the video stage calls before capturing
  local p vp
  p="$(discover_port)" || { say "chrome.sh: no CDP port on record"; return 1; }
  cdp_alive "$p" || { say "chrome.sh: CDP DOWN on $p"; return 1; }
  vp="$(viewport_of "$p")" || { say "chrome.sh: could not measure the viewport over CDP $p"; return 1; }
  say "$vp"
  viewport_ok "$vp" && return 0
  say "chrome.sh: viewport $vp is smaller than ${MIN_W}x${MIN_H}. The video tour films a ${MIN_W}x${MIN_H} frame; widen the niri column (or bash $(dirname "$0")/place-chrome.sh) — do not shrink the storyboard viewport." >&2
  return 1
}

cmd_revive() {
  local p pid
  validate_window_size || return 1
  p="$(pick_port)" || return 1
  if cdp_alive "$p"; then
    say "chrome.sh: run Chrome already alive on CDP $p — nothing to do (idempotent)"
    [ "$(runvar CHROME_CDP_PORT || true)" = "$p" ] || append_runenv CHROME_CDP_PORT "$p"
    [ "$(runvar CHROME_LAUNCHED || true)" = "1" ] || append_runenv CHROME_LAUNCHED 1
    [ "$(runvar CHROME_WINDOW_SIZE || true)" = "$WINDOW_SIZE" ] || append_runenv CHROME_WINDOW_SIZE "$WINDOW_SIZE"
    main_pid >/dev/null
    return 0
  fi
  say "chrome.sh: reviving the run Chrome on CDP $p (profile $PROFILE)"
  append_runenv CHROME_SESSION "$SESSION"
  append_runenv CHROME_SESSION_PROFILE "$PROFILE"
  append_runenv CHROME_XDG_DATA_HOME "$XDG_DATA"
  # Record the port BEFORE the launch: a failed launch must still leave a known port.
  append_runenv CHROME_CDP_PORT "$p"
  mkdir -p "$XDG_DATA" 2>/dev/null || true
  if [ ! -d "$PROFILE" ]; then
    local src="${CHROME_USER_DATA_DIR:-$HOME/chrome-org}"
    if [ -d "$src" ]; then
      cp -a "$src" "$PROFILE" 2>/dev/null || true
      say "chrome.sh: seeded the profile copy from $src"
    else
      mkdir -p "$PROFILE"
      say "chrome.sh: WARNING — no source profile at $src; starting from an empty profile (GitHub login will be lost)" >&2
    fi
  fi
  # A stale Chrome holding the profile silently sabotages every relaunch: kill in a
  # loop, then clear the singleton triple (a dying Chrome can rewrite it).
  local i
  for i in 1 2 3 4 5; do
    main_pid >/dev/null && pkill -u pc -f "^$CHROME_BIN.*user-data-dir=$PROFILE" 2>/dev/null
    [ -z "$(main_pid)" ] && break
    sleep 1
  done
  rm -f "$PROFILE"/SingletonLock "$PROFILE"/SingletonCookie "$PROFILE"/SingletonSocket "$PROFILE"/DevToolsActivePort
  # FIXED port + headed wayland ozone + an EXPLICIT window size. Never 0, never headless,
  # never --password-store=basic (it breaks the propagated GitHub cookies). Under Wayland
  # niri may still size the tile itself, so the size is verified afterwards by
  # `chrome.sh viewport` rather than assumed.
  append_runenv CHROME_WINDOW_SIZE "$WINDOW_SIZE"
  setsid nohup env \
    WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}" \
    XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/1000}" \
    "$CHROME_BIN" --ozone-platform=wayland --remote-debugging-port="$p" \
    --user-data-dir="$PROFILE" --no-sandbox --disable-setuid-sandbox --disable-dev-shm-usage \
    --no-first-run --no-default-browser-check --window-position=0,0 --window-size="$WINDOW_SIZE" about:blank \
    >>"$LOG" 2>&1 &
  for i in $(seq 1 60); do
    sleep 0.5
    if cdp_alive "$p"; then
      pid="$(main_pid)"
      append_runenv CHROME_LAUNCHED 1
      append_runenv CHROME_LAUNCH_EPOCH "$(date +%s)"
      [ -n "$pid" ] && append_runenv CHROME_PID "$pid"
      say "chrome.sh: run Chrome up — CDP http://127.0.0.1:$p${pid:+ (pid $pid)}; recorded CHROME_CDP_PORT=$p CHROME_WINDOW_SIZE=$WINDOW_SIZE CHROME_LAUNCHED=1"
      # Bind the run's agent-browser session to the browser we just launched.
      if XDG_DATA_HOME="$XDG_DATA" agent-browser --headed --session "$SESSION" --pin-tab \
        --profile "$PROFILE" --cdp "http://127.0.0.1:$p" open about:blank >/dev/null 2>&1; then
        say "chrome.sh: agent-browser session $SESSION attached over CDP $p"
      else
        say "chrome.sh: WARNING — CDP is up but agent-browser could not attach; retry the stage's browser call with --cdp http://127.0.0.1:$p" >&2
      fi
      return 0
    fi
  done
  say "chrome.sh: Chrome did NOT answer CDP on $p within 30s — see $LOG" >&2
  tail -5 "$LOG" 2>/dev/null >&2
  return 1
}

cmd_port() {
  discover_port || return 1
  printf '\n'
}

cmd_probe() {
  local p
  p="$(discover_port)" || { say "chrome.sh: no CDP port on record"; return 1; }
  cdp_alive "$p" || { say "chrome.sh: CDP DOWN on $p"; return 1; }
  say "chrome.sh: CDP UP on $p"
}

case "${1:-status}" in
  status) cmd_status ;;
  revive) cmd_revive ;;
  port) cmd_port ;;
  probe) cmd_probe ;;
  viewport) cmd_viewport ;;
  *)
    say "usage: $0 [status|revive|port|probe|viewport]" >&2
    exit 2
    ;;
esac
