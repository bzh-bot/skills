#!/usr/bin/env bash
# install-qwen3-tts.sh — one-off setup of the V3 default narration backend.
#
# The cage is linux/amd64 even on an Apple-silicon Mac (cage() passes
# --platform linux/amd64), so a venv built by the host python is useless inside
# it. Build the venv and download the checkpoint with a linux/amd64 container
# that writes to the host directory cage() already mounts:
#
#   ~/.local/share/qwen3-tts  →  $HOME/.cache/qwen3-tts (ro) in the cage
#
# ⚠️ The container mounts that directory AT THE CAGE PATH, so every shebang
# inside the venv (`venv/bin/pip`, console scripts) points wherever the cage
# will see it. Building at /out and mounting at $HOME/.cache/qwen3-tts leaves
# `venv/bin/pip: cannot execute: required file not found` (hit 2026-10-14).
#
# Layout produced (what tts-qwen3.py expects under QWEN3_ROOT):
#   <root>/venv/
#   <root>/Qwen3-TTS-12Hz-1.7B-CustomVoice/     (4.2 GB — the `custom` mode)
#
# Usage:  bash ~/.agents/skills/workflow-video-tour/scripts/install-qwen3-tts.sh
#         QWEN3_ROOT=~/somewhere bash .../install-qwen3-tts.sh
#
# GPU: none here. The cage on macOS has no GPU at all, so this installs the CPU
# wheels and tts-qwen3.py runs on cpu (it auto-detects: see --device). On a Linux
# host with the nvidia runtime, install the CUDA wheels instead.
set -euo pipefail

DEST="${QWEN3_ROOT:-$HOME/.local/share/qwen3-tts}"
CONTAINER_ROOT="$HOME/.cache/qwen3-tts"   # the path the cage mounts this at
MODEL_DIR="Qwen3-TTS-12Hz-1.7B-CustomVoice"
CPU_INDEX="https://download.pytorch.org/whl/cpu"

mkdir -p "$DEST"

if [ -d "$DEST/venv" ] && [ -d "$DEST/$MODEL_DIR" ]; then
  echo "already installed at $DEST — skipping (delete the dir to redo)"
else
  TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"' EXIT

  cat >"$TMP/install.sh" <<EOS
set -euxo pipefail
apt-get update -qq
apt-get install -y -qq python3 python3-venv python3-pip git
mkdir -p "$CONTAINER_ROOT"
cd "$CONTAINER_ROOT"
# torch AND torchaudio together from the CPU index — torchaudio from PyPI is a
# CUDA build and dies with "libcudart.so.13 => not found" against CPU torch.
if [ ! -x "$CONTAINER_ROOT/venv/bin/python" ]; then
  python3 -m venv "$CONTAINER_ROOT/venv"
fi
PIP="$CONTAINER_ROOT/venv/bin/python -m pip"
\$PIP install --upgrade -q pip
\$PIP install -q torch torchaudio --index-url $CPU_INDEX
\$PIP install -q qwen-tts soundfile librosa huggingface_hub
# qwen-tts may pull torchaudio from PyPI again — put the CPU build back.
\$PIP install -q --force-reinstall --no-deps torchaudio --index-url $CPU_INDEX
\$PIP list | grep -iE '^torch'
\$PIP show qwen-tts >/dev/null
EOS

  echo "▶ building linux/amd64 venv + checkpoint into $DEST (several GB, be patient)"
  docker run --rm --platform linux/amd64 \
    -v "$DEST:$CONTAINER_ROOT" -v "$TMP/install.sh:/install.sh:ro" \
    ubuntu:24.04 bash /install.sh

  echo "▶ downloading the CustomVoice checkpoint (4.2 GB)"
  docker run --rm --platform linux/amd64 -v "$DEST:$CONTAINER_ROOT" ubuntu:24.04 \
    bash -c "apt-get update -qq && apt-get install -y -qq python3 >/dev/null && \
      $CONTAINER_ROOT/venv/bin/python -c \"
from huggingface_hub import snapshot_download
print(snapshot_download('Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice', local_dir='$CONTAINER_ROOT/$MODEL_DIR'))\""
fi

echo "▶ verifying imports at the cage path"
docker run --rm --platform linux/amd64 -v "$DEST:$CONTAINER_ROOT" \
  --entrypoint bash cage-base -c \
  "$CONTAINER_ROOT/venv/bin/python -c \"
import torch, torchaudio, soundfile, qwen_tts, librosa
print('torch', torch.__version__, '| torchaudio', torchaudio.__version__, '| cuda', torch.cuda.is_available())\" 2>/dev/null"

echo "▶ sizes"
du -sh "$DEST" "$DEST/$MODEL_DIR" 2>/dev/null || true
echo "✅ qwen3-tts ready — the cage sees it at $CONTAINER_ROOT (QWEN3_ROOT)."
