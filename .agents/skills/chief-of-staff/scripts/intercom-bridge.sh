#!/usr/bin/env bash
# intercom-bridge.sh — ensure the HOST pi-intercom broker is alive and reachable
# from a cage over TCP (default 9458).
#
# Why this exists (2026-10-14, first macOS run):
#   A Linux container cannot share the host's Unix socket through VirtioFS, so the
#   cage's entrypoint dials TCP host.docker.internal:9458 and expects the host to
#   proxy that to the broker's real socket. The old cage() started that proxy blind:
#   if the broker was dead (or its socket had been unlinked) every cage spawned its
#   own private broker and saw NO host peers — silently.
#   This script makes both halves true before a container starts, and proves it with
#   the same framed health handshake pi-intercom itself uses (4-byte length + JSON).
#
# Usage:  intercom-bridge.sh [--quiet]
# Exit 0 = host broker answers through the bridge; non-zero = not usable.
set -uo pipefail

QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1
say() { [ "$QUIET" = 1 ] || echo "$@"; }

AGENT_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
IC_DIR="$AGENT_DIR/intercom"
SOCK="$IC_DIR/broker.sock"
PIDF="$IC_DIR/broker.pid"
LOCK="$IC_DIR/broker.spawn.lock"
BROKER="$HOME/.pi/agent/npm/node_modules/pi-intercom/broker/broker.ts"
TSX="$HOME/.pi/agent/npm/node_modules/tsx/dist/cli.mjs"
PORT="${INTERCOM_BRIDGE_PORT:-9458}"

# shellcheck disable=SC2016
PROBE_JS='
const net=require("net"),crypto=require("crypto");
const target=process.argv[1];
const [h,p]=target.includes(":")?target.split(":"):[null,null];
const s=h?net.connect({host:h,port:+p}):net.connect(target);
const id=crypto.randomUUID();
const j=JSON.stringify({type:"health",requestId:id});
const f=Buffer.allocUnsafe(4+j.length); f.writeUInt32BE(j.length,0); f.write(j,4);
let b=Buffer.alloc(0);
const t=setTimeout(()=>process.exit(2),1500);
s.on("connect",()=>s.write(f));
s.on("data",d=>{b=Buffer.concat([b,d]);
  if(b.length<4)return; const n=b.readUInt32BE(0); if(b.length<4+n)return;
  const m=JSON.parse(b.subarray(4,4+n).toString()); clearTimeout(t);
  process.exit(m.type==="health_ok"&&m.requestId===id&&m.protocol==="pi-intercom"&&m.version===1?0:1)});
s.on("error",()=>{clearTimeout(t);process.exit(3)});
'
probe() { node -e "$PROBE_JS" "$1" >/dev/null 2>&1; }

detach() {  # run a long-lived host helper detached from this shell
  if command -v setsid >/dev/null 2>&1; then
    setsid nohup "$@" </dev/null >/dev/null 2>&1 &
  else
    nohup "$@" </dev/null >/dev/null 2>&1 &
  fi
}

start_broker() {
  if [ ! -f "$BROKER" ] || [ ! -f "$TSX" ]; then
    say "⚠️  intercom: broker sources missing — cannot start it"
    return 1
  fi
  rm -f "$SOCK" "$PIDF" "$LOCK"
  ( cd "$(dirname "$BROKER")/.." && PI_CODING_AGENT_DIR="$AGENT_DIR" NODE_NO_WARNINGS=1 \
      detach node "$TSX" "$BROKER" )
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    probe "$SOCK" && return 0
    sleep 0.5
  done
  return 1
}

start_bridge() {
  if command -v socat >/dev/null 2>&1; then
    pkill -f "socat.*TCP-LISTEN:$PORT" 2>/dev/null
    sleep 0.3
    detach socat "TCP-LISTEN:$PORT,reuseaddr,fork" "UNIX-CONNECT:$SOCK"
  else
    # Linux hosts frequently have no socat (Debian: apt install socat). The cage
    # still dials TCP :$PORT, so fall back to a tiny node proxy — node is always
    # present (nvm) on these machines.
    local proxy="$(dirname "$SELF")/intercom-tcp-proxy.cjs"
    [ -f "$proxy" ] || { say "⚠️  intercom: socat missing and $proxy not found"; return 1; }
    say "🔊 intercom: socat missing — using node TCP proxy"
    pkill -f "intercom-tcp-proxy.cjs" 2>/dev/null
    sleep 0.3
    INTERCOM_BRIDGE_PORT="$PORT" INTERCOM_SOCK="$SOCK" detach node "$proxy"
  fi
  for _ in 1 2 3 4 5 6; do
    probe "127.0.0.1:$PORT" && return 0
    sleep 0.5
  done
  return 1
}

# 1. host broker answering on its own socket?
if ! probe "$SOCK"; then
  say "🔊 intercom: host broker not answering — restarting it"
  start_broker || { say "❌ intercom: could not start the host broker"; exit 1; }
fi

# 2. bridge reachable from a container (and through it, the broker)?
if ! probe "127.0.0.1:$PORT"; then
  say "🔊 intercom: bridge on $PORT not answering — (re)starting it"
  start_bridge || { say "❌ intercom: bridge on $PORT not usable"; exit 1; }
fi

say "🔊 intercom bridge ready: containers → TCP $PORT → host broker ($SOCK)"
exit 0
