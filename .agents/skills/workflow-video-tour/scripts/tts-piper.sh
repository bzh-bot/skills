#!/usr/bin/env bash
# tts-piper.sh — narrate a timeline with Piper (offline, ~0.04 RTF).
#
# Usage: tts-piper.sh --timeline out/timeline.json --out out/tts
#          [--model ~/.local/share/piper/voices/en_GB-alan-medium.onnx]
#          [--piper ~/.local/share/piper/piper] [--length-scale 0.95]
#          [--noise-scale 0.8] [--noise-w 1.0]
set -euo pipefail

PIPER="${PIPER_BIN:-$HOME/.local/share/piper/piper}"
MODEL="${PIPER_VOICE_PATH:-$HOME/.local/share/piper/voices/en_GB-alan-medium.onnx}"
LENGTH=0.95; NOISE=0.8; NOISE_W=1.0
TIMELINE=""; OUT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --timeline) TIMELINE="$2"; shift 2;;
    --out) OUT="$2"; shift 2;;
    --model) MODEL="$2"; shift 2;;
    --piper) PIPER="$2"; shift 2;;
    --length-scale) LENGTH="$2"; shift 2;;
    --noise-scale) NOISE="$2"; shift 2;;
    --noise-w) NOISE_W="$2"; shift 2;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done
[ -n "$TIMELINE" ] && [ -n "$OUT" ] || { echo "usage: tts-piper.sh --timeline t.json --out dir" >&2; exit 2; }
[ -x "$PIPER" ] || { echo "piper binary not found at $PIPER (see steps/3-narration.md for install)" >&2; exit 1; }
[ -f "$MODEL" ] || { echo "voice model not found at $MODEL" >&2; exit 1; }

mkdir -p "$OUT"
export LD_LIBRARY_PATH="$(dirname "$PIPER")${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

jq -r '.[] | select((.narration // "") != "") | .id' "$TIMELINE" | while read -r id; do
  text=$(jq -r --arg id "$id" '.[] | select(.id == $id) | .narration' "$TIMELINE")
  printf '%s' "$text" | "$PIPER" --model "$MODEL" --output_file "$OUT/$id.wav" \
    --length-scale "$LENGTH" --noise-scale "$NOISE" --noise-w "$NOISE_W" >/dev/null 2>&1
  secs=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$OUT/$id.wav")
  printf '  piper %-18s %5.1fs  %s\n' "$id" "$secs" "$OUT/$id.wav"
done
