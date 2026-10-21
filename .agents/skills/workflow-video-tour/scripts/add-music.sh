#!/usr/bin/env bash
# add-music.sh — mix an instrumental bed under the narration, ducked while the
# narrator speaks. See steps/6-music.md for choosing and licensing the track.
#
# Usage: add-music.sh --video in.mp4 --music track.mp3 --out out.mp4
#          [--bed-db -24] [--duck 8] [--fade-in 2] [--fade-out 3] [--limit 0.95]
set -euo pipefail

VIDEO=""; MUSIC=""; OUT=""
BED_DB="${MUSIC_BED_DB:--24}"; DUCK="${MUSIC_DUCK:-8}"; FADE_IN=2; FADE_OUT=3; LIMIT=0.95

while [ $# -gt 0 ]; do
  case "$1" in
    --video) VIDEO="$2"; shift 2;;
    --music) MUSIC="$2"; shift 2;;
    --out) OUT="$2"; shift 2;;
    --bed-db) BED_DB="$2"; shift 2;;
    --duck) DUCK="$2"; shift 2;;
    --fade-in) FADE_IN="$2"; shift 2;;
    --fade-out) FADE_OUT="$2"; shift 2;;
    --limit) LIMIT="$2"; shift 2;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done
[ -n "$VIDEO" ] && [ -n "$MUSIC" ] && [ -n "$OUT" ] || { echo "usage: add-music.sh --video in.mp4 --music track.mp3 --out out.mp4" >&2; exit 2; }
[ -f "$VIDEO" ] || { echo "video not found: $VIDEO" >&2; exit 1; }
[ -f "$MUSIC" ] || { echo "music not found: $MUSIC" >&2; exit 1; }

VD=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$VIDEO")
OUT_AT=$(awk -v d="$VD" -v f="$FADE_OUT" 'BEGIN{printf "%.2f", ((d-f) > 0 ? d-f : 0)}')
# sidechaincompress: the NARRATION triggers the gain reduction on the BED
ffmpeg -hide_banner -loglevel error -y -i "$VIDEO" -stream_loop -1 -i "$MUSIC" -filter_complex "\
[1:a]atrim=0:${VD},volume=${BED_DB}dB,afade=t=in:st=0:d=${FADE_IN},afade=t=out:st=${OUT_AT}:d=${FADE_OUT}[bed];\
[bed][0:a]sidechaincompress=threshold=0.02:ratio=${DUCK}:attack=15:release=400[bedduck];\
[0:a][bedduck]amix=inputs=2:duration=first:normalize=0,alimiter=limit=${LIMIT}[a]" \
  -map 0:v -map "[a]" -c:v copy -c:a aac -b:a 160k -movflags +faststart "$OUT"

echo "✅ $OUT (bed ${BED_DB} dB, duck ratio ${DUCK}:1)"
echo "   remember the attribution line for the PR body: <track> — <artist> · <url> · <licence>"
