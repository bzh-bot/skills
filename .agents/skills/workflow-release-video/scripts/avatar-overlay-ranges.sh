#!/usr/bin/env bash
# avatar-overlay-ranges.sh — composite the avatar only over the *card* beats.
#
# A 4-minute release video with a mascot bobbing in the corner for the whole runtime
# is exhausting; over the intro card, each chapter divider and the close it reads as a
# presenter. This is `workflow-video-tour/scripts/avatar/avatar-overlay.sh` extended
# with an `enable=` window expression — the shared tour script is deliberately NOT
# modified (workflow-do depends on its exact behaviour).
#
#   avatar-overlay-ranges.sh --video in.mp4 --frames "$VIDEO_DIR/avatar/frames" \
#     --out out.mp4 --video-json "$VIDEO_DIR/video.json" --timeline "$VIDEO_DIR/timeline.json" \
#     [--size 240] [--corner br] [--caption-band 88] [--bob 3] [--pad 0.4]
#
#   --ranges "0-4,40-46"   use an explicit list instead of deriving the card windows
#   --pad SECONDS          bleed each window by this much (default 0.4; a hard cut on
#                          the frame boundary looks like a glitch)
#   --all                  no windowing at all — behaves like the tour's overlay
set -euo pipefail

VIDEO=""; FRAMES=""; OUT=""; SIZE=240; CORNER="br"; GAP=28; BAND=88; BOB=3; BOB_PERIOD=3.4
X=""; Y=""; RANGES=""; VIDEO_JSON=""; TIMELINE=""; PAD=0.4; ALL=0; FPS=30
while [ $# -gt 0 ]; do
  case "$1" in
    --video) VIDEO="$2"; shift 2 ;;
    --frames) FRAMES="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --size) SIZE="$2"; shift 2 ;;
    --corner) CORNER="$2"; shift 2 ;;
    --gap) GAP="$2"; shift 2 ;;
    --caption-band) BAND="$2"; shift 2 ;;
    --bob) BOB="$2"; shift 2 ;;
    --bob-period) BOB_PERIOD="$2"; shift 2 ;;
    --x) X="$2"; shift 2 ;;
    --y) Y="$2"; shift 2 ;;
    --ranges) RANGES="$2"; shift 2 ;;
    --video-json) VIDEO_JSON="$2"; shift 2 ;;
    --timeline) TIMELINE="$2"; shift 2 ;;
    --pad) PAD="$2"; shift 2 ;;
    --fps) FPS="$2"; shift 2 ;;
    --all) ALL=1; shift ;;
    -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
for v in VIDEO FRAMES; do
  [ -n "${!v}" ] || { echo "FATAL: --${v,,} is required" >&2; exit 2; }
  [ -e "${!v}" ] || { echo "FATAL: --${v,,} not found: ${!v}" >&2; exit 2; }
done
[ -n "$OUT" ] || { echo "FATAL: --out is required" >&2; exit 2; }
[ -w "$(dirname "$OUT")" ] || { echo "FATAL: --out directory is not writable: $(dirname "$OUT")" >&2; exit 2; }
[ -d "$FRAMES" ] || { echo "FATAL: --frames is not a directory: $FRAMES" >&2; exit 2; }
command -v jq >/dev/null || { echo "FATAL: jq is required" >&2; exit 2; }
[ -n "$(ls "$FRAMES" | head -1)" ] || { echo "FATAL: no frames in $FRAMES" >&2; exit 2; }

# ── the windows ─────────────────────────────────────────────────────────────────
# A window is a card beat: the intro title (id 00-title) or any beat whose timeline
# entry has segment === null. Deriving them beats hand-listing times that drift the
# moment a narration line is re-voiced.
if [ "$ALL" = "1" ]; then
  RANGES=""
elif [ -z "$RANGES" ]; then
  [ -n "$VIDEO_JSON" ] || { echo "FATAL: --video-json (or --ranges, or --all) is required" >&2; exit 2; }
  [ -n "$TIMELINE" ] || { echo "FATAL: --timeline (or --ranges, or --all) is required" >&2; exit 2; }
  card_ids=$(jq -r '[.[] | select(.segment == null) | .id] | @tsv' "$TIMELINE")
  card_ids="00-title	$card_ids"
  RANGES=$(jq -r --arg ids "$card_ids" --argjson pad "$PAD" '
    ($ids | split("\t")) as $want
    | [ .beats[] | select(.id as $i | $want | index($i))
        | { a: ((.start - $pad) | if . < 0 then 0 else . end), b: (.end + $pad) } ]
    | map("\(.a)-\(.b)") | join("\n")' "$VIDEO_JSON")
  # Merge overlapping windows. The 0.4 s pad makes consecutive cards overlap (the intro
  # ends 0.4 s into the first divider), and an overlap is harmless in `enable=` but makes
  # the list unreadable — and an unreadable list is one nobody checks.
  RANGES=$(echo "$RANGES" | sort -t- -k1 -n | awk -F- '
    { a = $1 + 0; b = $2 + 0
      if (NR == 1) { sa = a; sb = b; next }
      if (a <= sb) { if (b > sb) sb = b; next }
      printf "%s-%s,", sa, sb; sa = a; sb = b }
    END { if (NR) printf "%s-%s", sa, sb }')
  echo "  · card beats: $(echo "$card_ids" | tr '\t' ' ')"
fi

if [ -n "$RANGES" ]; then
  ENABLE=$(echo "$RANGES" | tr ',' '\n' | awk -F- 'NF==2 {printf "%sbetween(t,%s,%s)", (NR>1?"+":""), $1, $2}')
  echo "  · avatar visible for $(echo "$RANGES" | tr ',' '\n' | wc -l) window(s): $RANGES"
else
  ENABLE="1"   # no windowing
  echo "  · avatar visible for the whole video"
fi

read -r W H <<<"$(ffprobe -v error -select_streams v -show_entries stream=width,height \
  -of csv=p=0 "$VIDEO" | head -1 | tr ',' ' ')"
if [ -z "${X:-}" ] || [ -z "${Y:-}" ]; then
  case "$CORNER" in
    br) X=$((W - SIZE - GAP)); Y=$((H - SIZE - BAND - 30)) ;;
    bl) X=$GAP;                Y=$((H - SIZE - BAND - 30)) ;;
    tr) X=$((W - SIZE - GAP)); Y=$GAP ;;
    tl) X=$GAP;                Y=$GAP ;;
    *) echo "FATAL: --corner must be br|bl|tr|tl" >&2; exit 2 ;;
  esac
fi
echo "  · video ${W}x${H} → avatar ${SIZE}px at ${X},${Y} (corner=$CORNER, caption band=${BAND}px)"

OVY="$Y"
[ "$BOB" != "0" ] && OVY="${Y}+${BOB}*sin(2*PI*t/${BOB_PERIOD})"

# -framerate must match the frames' own rate, or the overlay drifts out of sync with
# the mouth cues by the end of a 4-minute video.
ffmpeg -hide_banner -loglevel error -y -i "$VIDEO" \
  -framerate "$FPS" -i "$FRAMES/f%05d.png" \
  -filter_complex "[1:v]format=rgba[av];[0:v][av]overlay=x=${X}:y=${OVY}:enable='${ENABLE}':format=auto:eval=frame[v]" \
  -map "[v]" -map 0:a -c:v libx264 -preset veryfast -crf 19 -pix_fmt yuv420p \
  -c:a copy "$OUT"

echo "  ✓ $OUT ($(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$OUT")s)"
