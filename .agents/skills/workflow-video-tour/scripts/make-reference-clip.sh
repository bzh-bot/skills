#!/usr/bin/env bash
# make-reference-clip.sh — cut a clean 3–15 s voice reference from a recording,
# normalise it, and transcribe it (the transcript is required by Qwen3-TTS
# clone mode in ICL mode).
#
# Usage:
#   make-reference-clip.sh --video recording.MOV --out ref-4s.wav \
#     [--start 270] [--duration 10] [--trim-start 0] [--trim-duration 4.05] \
#     [--model ~/.local/share/voxtype/models/ggml-medium.en.bin]
#
# With no --start it RANKS 10-second windows by loudness and picks the loudest,
# which is the fastest way to find speech in a long recording. Print the
# transcript, then pass it to tts-qwen3.py --ref-text.
set -euo pipefail

VIDEO=""; OUT="ref.wav"; START=""; DURATION=10; TRIM_START=0; TRIM_DUR=""
MODEL="${WHISPER_MODEL:-$HOME/.local/share/voxtype/models/ggml-medium.en.bin}"

while [ $# -gt 0 ]; do
  case "$1" in
    --video) VIDEO="$2"; shift 2;;
    --out) OUT="$2"; shift 2;;
    --start) START="$2"; shift 2;;
    --duration) DURATION="$2"; shift 2;;
    --trim-start) TRIM_START="$2"; shift 2;;
    --trim-duration) TRIM_DUR="$2"; shift 2;;
    --model) MODEL="$2"; shift 2;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done
[ -n "$VIDEO" ] || { echo "usage: make-reference-clip.sh --video file --out ref.wav [--start s] [--duration s]" >&2; exit 2; }
[ -f "$VIDEO" ] || { echo "input not found: $VIDEO (is the rclone/gdrive mount up? see steps/3-narration.md)" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "→ extracting 16 kHz mono audio"
# -err_detect ignore_err: some phone MOVs have damaged AAC frames and flood stderr
ffmpeg -hide_banner -loglevel error -err_detect ignore_err -y -i "$VIDEO" -map 0:a:0 -vn -ac 1 -ar 16000 -c:a pcm_s16le "$WORK/full.wav"

if [ -z "$START" ]; then
  echo "→ ranking ${DURATION}s windows by loudness (this is where the speech is)"
  total=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$WORK/full.wav" | cut -d. -f1)
  : > "$WORK/rank.txt"
  for ((t=0; t<total; t+=DURATION)); do
    mean=$(ffmpeg -hide_banner -ss "$t" -t "$DURATION" -i "$WORK/full.wav" -af volumedetect -f null - 2>&1 \
      | awk '/mean_volume/{print $5}')
    echo "$mean $t" >> "$WORK/rank.txt"
  done
  START=$(sort -k1 -n -r "$WORK/rank.txt" | head -1 | awk '{print $2}')
  echo "  loudest window starts at ${START}s"
fi

echo "→ cutting ${DURATION}s from ${START}s and normalising to -18 LUFS"
ffmpeg -hide_banner -loglevel error -y -ss "$START" -t "$DURATION" -i "$WORK/full.wav" \
  -af "loudnorm=I=-18:TP=-2:LRA=11,aresample=24000" -ac 1 "$WORK/ref-full.wav"

if [ -n "$TRIM_DUR" ]; then
  ffmpeg -hide_banner -loglevel error -y -ss "$TRIM_START" -t "$TRIM_DUR" -i "$WORK/ref-full.wav" \
    -af "loudnorm=I=-18:TP=-2:LRA=11,aresample=24000" -ac 1 "$OUT"
else
  cp "$WORK/ref-full.wav" "$OUT"
fi

echo "→ transcribing (whisper)"
if command -v whisper-cli >/dev/null 2>&1 && [ -f "$MODEL" ]; then
  whisper-cli -m "$MODEL" -f "$OUT" -nt -t 8 2>/dev/null | sed 's/^ *//' | tee "$OUT.txt"
  echo
  echo "reference written: $OUT"
  echo "transcript      : $(cat "$OUT.txt")"
  echo "use with        : tts-qwen3.py --mode clone --ref-audio $OUT --ref-text \"\$(cat $OUT.txt)\""
else
  echo "whisper-cli/$MODEL not available — transcribe $OUT by hand and pass --ref-text" >&2
fi
