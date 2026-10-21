#!/usr/bin/env bash
# setup-mermaid.sh — install the pinned mermaid-cli (mmdc) this skill renders with.
#
# mmdc is NOT on PATH by default on these machines, and a global `npm i -g` drifts
# between runs. Install into a stable, WRITABLE prefix instead, with the bundled
# Chromium download skipped: the render uses the system Chrome (see pptr config in
# render-diagrams.mjs). Same version + same .mmd = same PNG bytes, which is what
# makes a re-render of one diagram safe to splice into a finished video.
#
# WHY NOT ~/.local/share (2026-10-19): inside the workflow cage ~/.local/share is
# root-owned, so the install failed with EACCES and a live run had to hand-install
# mermaid-cli into the worktree mid-tour. The prefix is now chosen from a list of
# WRITABLE locations, worktree first:
#
#   1. $MERMAID_CLI_PREFIX              explicit override (must be writable)
#   2. $VIDEO_TOOLS_DIR/mermaid-cli     the shared tools dir for this run/worktree
#   3. <worktree>/.video-tools/mermaid-cli
#                                       default: $WORKTREE, else the git toplevel of $PWD
#   4. ~/.local/share/mermaid-cli       only when it is actually writable (the host)
#
# The chosen prefix is recorded in $VIDEO_TOOLS_DIR/mermaid-cli.path (when that dir is
# in play) and in <prefix>/.mmdc-prefix, so render-diagrams.mjs finds the SAME install
# instead of silently using a different one.
#
# Usage: setup-mermaid.sh [--force]      (idempotent; ~10 s when already installed)
set -euo pipefail

VERSION="${MERMAID_CLI_VERSION:-12.0.0}"
FORCE=0
[ "${1:-}" = "--force" ] && FORCE=1

command -v node >/dev/null || { echo "FAIL: node is not on PATH" >&2; exit 1; }
command -v npm  >/dev/null || { echo "FAIL: npm is not on PATH" >&2; exit 1; }

# ── pick a writable prefix ──────────────────────────────────────────────────
writable() { # writable DIR → mkdir -p succeeds and the dir is writable
  mkdir -p "$1" 2>/dev/null && [ -w "$1" ]
}

worktree() {
  if [ -n "${WORKTREE:-}" ] && [ -d "$WORKTREE" ]; then printf '%s' "$WORKTREE"; return 0; fi
  git rev-parse --show-toplevel 2>/dev/null || printf '%s' "$PWD"
}

choose_prefix() {
  local wt; wt="$(worktree)"
  local candidates=()
  [ -n "${MERMAID_CLI_PREFIX:-}" ] && candidates+=("$MERMAID_CLI_PREFIX")
  [ -n "${VIDEO_TOOLS_DIR:-}" ] && candidates+=("$VIDEO_TOOLS_DIR/mermaid-cli")
  candidates+=("$wt/.video-tools/mermaid-cli")
  candidates+=("$HOME/.local/share/mermaid-cli")
  local c
  for c in "${candidates[@]}"; do
    if writable "$c"; then printf '%s' "$c"; return 0; fi
    echo "· ${c} is not writable — skipping" >&2
  done
  return 1
}

if ! PREFIX="$(choose_prefix)"; then
  cat >&2 <<'EOF'
FAIL: no writable install location for mermaid-cli.

Tried, in order: $MERMAID_CLI_PREFIX, $VIDEO_TOOLS_DIR/mermaid-cli,
<worktree>/.video-tools/mermaid-cli, ~/.local/share/mermaid-cli.
Inside the workflow cage ~/.local/share is root-owned, which is why the worktree-local
default exists. Either run this from inside the worktree ($WORKTREE or the git toplevel),
or point the installer at a writable directory yourself:

  VIDEO_TOOLS_DIR=/path/you/own bash scripts/setup-mermaid.sh
  MERMAID_CLI_PREFIX=/path/you/own/mermaid-cli bash scripts/setup-mermaid.sh
EOF
  exit 1
fi

BIN="$PREFIX/node_modules/.bin/mmdc"

# Record the prefix so the renderer resolves THIS install, not a stale one elsewhere.
record_prefix() {
  printf '%s\n' "$PREFIX" > "$PREFIX/.mmdc-prefix" 2>/dev/null || true
  if [ -n "${VIDEO_TOOLS_DIR:-}" ] && writable "$VIDEO_TOOLS_DIR"; then
    printf '%s\n' "$PREFIX" > "$VIDEO_TOOLS_DIR/mermaid-cli.path" 2>/dev/null || true
  fi
}

if [ -x "$BIN" ] && [ "$FORCE" -eq 0 ]; then
  have="$("$BIN" --version 2>/dev/null | tail -1)"
  if [ "$have" = "$VERSION" ]; then
    echo "✅ mmdc $have already installed → $BIN"
    record_prefix
    exit 0
  fi
  echo "· mmdc $have found, want $VERSION — reinstalling"
fi

# Never pull a second Chrome: mermaid-cli's puppeteer dependency would download one
# (~150 MB) that the render never uses.
export PUPPETEER_SKIP_DOWNLOAD=true
export PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true

echo "· installing @mermaid-js/mermaid-cli@$VERSION → $PREFIX"
writable "$PREFIX" || { echo "FAIL: $PREFIX became unwritable" >&2; exit 1; }
npm install --prefix "$PREFIX" --no-fund --no-audit --no-save \
  "@mermaid-js/mermaid-cli@$VERSION" >/dev/null

[ -x "$BIN" ] || { echo "FAIL: $BIN missing after install" >&2; exit 1; }

record_prefix
echo "✅ mmdc $("$BIN" --version | tail -1) → $BIN"
echo "   prefix: $PREFIX"
echo "   render: node $(dirname "$0")/render-diagrams.mjs --storyboard <storyboard.json> --out <VIDEO_DIR>"
