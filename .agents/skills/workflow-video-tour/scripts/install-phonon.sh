#!/usr/bin/env bash
# install-phonon.sh — give this machine a Phonon-capable Ollama (speech/TTS).
#
# Replaces install-qwen3-tts.sh: no 4.3 GB checkpoint, no torch venv, no GPU. Phonon
# is a 112 MB Ollama model and the whole runtime is the Ollama binary plus (on Linux)
# its MLX libraries — the server refuses to run Phonon without them:
#
#   Error: this model requires MLX support, but the MLX runtime is not available
#
# so the `-mlx` release overlay is NOT optional on Linux. macOS ships the runtime in
# the app; no overlay is needed there.
#
# Usage:
#   scripts/install-phonon.sh              # system install to /usr/local (needs sudo)
#   scripts/install-phonon.sh --user       # user install, own service on port 11435
#   scripts/install-phonon.sh --check      # verify an existing runtime only
#   OLLAMA_VERSION=v0.40.11 scripts/install-phonon.sh
#
# After it finishes:  scripts/tts-phonon.py --check
set -euo pipefail

VERSION="${OLLAMA_VERSION:-v0.40.11}"   # first release with speech models
MODEL="${PHONON_MODEL:-phonon}"
MODE=system
CHECK_ONLY=0
PORT="${OLLAMA_PORT:-11434}"
for arg in "$@"; do
  case "$arg" in
    --user) MODE=user; PORT="${OLLAMA_PORT:-11435}" ;;
    --check) CHECK_ONLY=1 ;;
    -h | --help) sed -n '2,25p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TTS="$HERE/tts-phonon.py"
ok() { printf '  \033[32m%s\033[0m %s\n' "ok" "$1"; }
info() { printf '%s\n' "$1"; }
die() { printf '\033[31mFAIL\033[0m %s\n' "$1" >&2; exit 1; }

client_version() { # `ollama --version` reports the SERVER it can reach, and appends
  # "Warning: client version is X" when the binary is newer. The client is what has
  # the speech route, so prefer that line when it is there.
  local out
  out=$("$1" --version 2>&1 || true)
  printf '%s\n' "$out" | grep -oE 'client version is [0-9]+\.[0-9]+\.[0-9]+' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 \
    || printf '%s\n' "$out" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
}
server_version() { # server_version <base-url>
  curl -sf "$1/api/version" 2>/dev/null | sed -n 's/.*"version":"\([^"]*\)".*/\1/p'
}
has_speech() { # has_speech <binary> -> 0 when the model advertises the speech capability
  local base="http://127.0.0.1:${PORT}"
  curl -sf "$base/api/version" >/dev/null 2>&1 || return 1
  local caps
  caps=$(OLLAMA_HOST="$base" "$1" show "$MODEL" 2>/dev/null | grep -c "^ *speech" || true)
  [ "${caps:-0}" -ge 1 ]
}

if [ "$CHECK_ONLY" = "1" ]; then
  info "checking an existing runtime on port $PORT"
  command -v ollama >/dev/null || die "ollama is not on PATH"
  cv=$(client_version "$(command -v ollama)")
  sv=$(server_version "http://127.0.0.1:$PORT")
  info "client $cv · server ${sv:-down}"
  case "${sv:-$cv}" in
    0.4[0-9].* | 0.[5-9]* | [1-9]*) info "server supports speech" ;;
    *) die "server ${sv:-$cv} predates speech (needs >= 0.40.9) — run this script without --check" ;;
  esac
  PHONON_HOST="http://127.0.0.1:$PORT" python3 "$TTS" --check || exit 1
  exit 0
fi

# ── what are we installing onto ─────────────────────────────────────────────
os=$(uname -s)
arch=$(uname -m)
case "$os-$arch" in
  Linux-x86_64) asset="ollama-linux-amd64"; overlay="ollama-linux-amd64-mlx" ;;
  Linux-aarch64 | Linux-arm64) asset="ollama-linux-arm64"; overlay="ollama-linux-arm64-mlx" ;;
  Darwin-*) asset="Ollama-darwin.zip"; overlay="" ;;
  *) die "unsupported platform $os-$arch" ;;
esac
info "platform: $os-$arch → $asset"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
base="https://github.com/ollama/ollama/releases/download/$VERSION"

if [ "$os" = "Darwin" ]; then
  info "macOS: installing the app bundle (Phonon runs natively, MLX included)"
  curl -fL --progress-bar "$base/Ollama-darwin.zip" -o "$tmp/Ollama.zip"
  unzip -q "$tmp/Ollama.zip" -d /Applications
  open -a Ollama || true
  ok "Ollama installed — waiting for the server"
  for _ in $(seq 1 30); do
    curl -sf http://127.0.0.1:11434/api/version >/dev/null 2>&1 && break
    sleep 1
  done
  OLLAMA_HOST=http://127.0.0.1:11434 ollama pull "$MODEL" && ok "model $MODEL pulled"
  python3 "$TTS" --check
  exit 0
fi

# ── Linux: binary + MLX overlay ─────────────────────────────────────────────
info "downloading $VERSION ($asset)"
curl -fL --progress-bar "$base/$asset.tar.zst" -o "$tmp/main.tar.zst"
info "downloading the MLX runtime overlay ($overlay) — required for Phonon on Linux"
curl -fL --progress-bar "$base/$overlay.tar.zst" -o "$tmp/mlx.tar.zst"

extract() { # extract <archive> <dest>
  mkdir -p "$2"
  if command -v unzstd >/dev/null; then
    tar --use-compress-program=unzstd -xf "$1" -C "$2"
  else
    tar --zstd -xf "$1" -C "$2" 2>/dev/null || die "need zstd (or tar >= 1.31) to unpack $1"
  fi
}
extract "$tmp/main.tar.zst" "$tmp/main"
extract "$tmp/mlx.tar.zst" "$tmp/mlx"

if [ "$MODE" = "system" ]; then
  prefix=/usr/local
  sudo mkdir -p "$prefix/bin" "$prefix/lib"
  if [ -x "$prefix/bin/ollama" ]; then
    sudo cp -p "$prefix/bin/ollama" "$prefix/bin/ollama-$(client_version "$prefix/bin/ollama").bak"
    ok "backed up the current binary to $prefix/bin/ollama-*.bak"
  fi
  sudo cp "$tmp/main/bin/ollama" "$prefix/bin/ollama"
  sudo cp -r "$tmp/main/lib/." "$prefix/lib/" 2>/dev/null || true
  # Overlay AFTER the base libs so the MLX runtime is what wins.
  sudo cp -r "$tmp/mlx/lib/." "$prefix/lib/"
  ok "installed $prefix/bin/ollama + MLX runtime under $prefix/lib/ollama"
  if systemctl list-unit-files 2>/dev/null | grep -q '^ollama\.service'; then
    sudo systemctl restart ollama
    ok "restarted ollama.service"
  else
    sudo systemd-run --unit=ollama --setenv=OLLAMA_HOST="127.0.0.1:$PORT" \
      "$prefix/bin/ollama" serve >/dev/null 2>&1 || true
    ok "started ollama via systemd-run on port $PORT"
  fi
  BIN="$prefix/bin/ollama"
  HOSTURL="http://127.0.0.1:$PORT"
else
  prefix="$HOME/.local"
  mkdir -p "$prefix/bin" "$prefix/lib" "$HOME/.config/systemd/user"
  if [ -x "$prefix/bin/ollama" ]; then
    cp -p "$prefix/bin/ollama" "$prefix/bin/ollama-$(client_version "$prefix/bin/ollama").bak"
  fi
  cp "$tmp/main/bin/ollama" "$prefix/bin/ollama"
  cp -r "$tmp/main/lib/." "$prefix/lib/" 2>/dev/null || true
  cp -r "$tmp/mlx/lib/." "$prefix/lib/"
  cat >"$HOME/.config/systemd/user/ollama-phonon.service" <<UNIT
[Unit]
Description=Ollama (Phonon speech runtime)
After=network.target

[Service]
ExecStart=$prefix/bin/ollama serve
Environment=OLLAMA_HOST=127.0.0.1:$PORT
Environment=LD_LIBRARY_PATH=$prefix/lib:$prefix/lib/ollama
Restart=always
RestartSec=3

[Install]
WantedBy=default.target
UNIT
  systemctl --user daemon-reload
  systemctl --user enable --now ollama-phonon.service
  ok "user service ollama-phonon.service on port $PORT (export OLLAMA_HOST=127.0.0.1:$PORT)"
  BIN="$prefix/bin/ollama"
  HOSTURL="http://127.0.0.1:$PORT"
fi

for _ in $(seq 1 40); do
  curl -sf "$HOSTURL/api/version" >/dev/null 2>&1 && break
  sleep 1
done
curl -sf "$HOSTURL/api/version" >/dev/null || die "the server on $HOSTURL never came up"
ok "server up: $("$BIN" --version | head -1)"

info "pulling $MODEL (112 MB)"
OLLAMA_HOST="$HOSTURL" "$BIN" pull "$MODEL"
ok "model pulled"

PHONON_HOST="$HOSTURL" python3 "$TTS" --check
info "done — narrate with: PHONON_HOST=$HOSTURL python3 $TTS --timeline timeline.json --out tts-phonon"
