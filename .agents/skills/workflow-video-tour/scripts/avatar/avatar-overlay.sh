#!/usr/bin/env bash
# avatar-overlay.sh — composite the avatar PNG sequence onto the finished video.
#
#   avatar-overlay.sh --video in.mp4 --frames "$VIDEO_DIR/avatar/frames" \
#     --out out.mp4 [--size 240] [--corner br] [--gap 28] [--caption-band 88] \
#     [--bob 3] [--bob-period 3.4] [--start 0] [--duration 35]
#
# Placement: bottom-right by default, sitting **above the caption bar** so the
# burned-in captions stay readable (y = H - size - caption-band - 30). Use
# --corner bl|br|tr|tl, or --x/--y to place it exactly.
#
# --bob adds a gentle vertical sway (px, sine over --bob-period seconds) so the
# avatar feels alive rather than pasted on; --bob 0 pins it. The mouth (Rhubarb
# cues) and the blink (the SVG's eye pair) are already in the frame sequence.
set -euo pipefail

VIDEO=""; FRAMES=""; OUT=""; SIZE=240; CORNER="br"; GAP=28; BAND=88; BOB=3; BOB_PERIOD=3.4
X=""; Y=""; START=""; DURATION=""
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
    --start) START="$2"; shift 2 ;;
    --duration) DURATION="$2"; shift 2 ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
for v in VIDEO FRAMES OUT; do
  [ -n "${!v}" ] || { echo "FATAL: --${v,,} is required" >&2; exit 2; }
done
[ -d "$FRAMES" ] || { echo "FATAL: frames dir not found: $FRAMES" >&2; exit 2; }
first=$(ls "$FRAMES" | head -1) || true
[ -n "$first" ] || { echo "FATAL: no frames in $FRAMES" >&2; exit 2; }

read -r W H <<<"$(ffprobe -v error -select_streams v -show_entries stream=width,height \
  -of csv=p=0 "$VIDEO" | head -1 | tr ',' ' ')"
[ -n "${X:-}" ] && [ -n "${Y:-}" ] || {
  case "$CORNER" in
    br) X=$((W - SIZE - GAP)); Y=$((H - SIZE - BAND - 30)) ;;
    bl) X=$GAP;                Y=$((H - SIZE - BAND - 30)) ;;
    tr) X=$((W - SIZE - GAP)); Y=$GAP ;;
    tl) X=$GAP;                Y=$GAP ;;
    *) echo "FATAL: --corner must be br|bl|tr|tl" >&2; exit 2 ;;
  esac
}
echo "  · video ${W}x${H} → avatar ${SIZE}px at ${X},${Y} (corner=$CORNER, caption band=${BAND}px)"

# gentle bob: the overlay y is a per-frame expression, so the avatar sways ±BOB px
OVY="$Y"
if [ "$BOB" != "0" ]; then
  OVY="${Y}+${BOB}*sin(2*PI*t/${BOB_PERIOD})"
  echo "  · bob ±${BOB}px over ${BOB_PERIOD}s"
fi

TRIM=()
[ -n "$START" ] && TRIM+=(-ss "$START")
[ -n "$DURATION" ] && TRIM+=(-t "$DURATION")

ffmpeg -hide_banner -loglevel error -y "${TRIM[@]}" -i "$VIDEO" \
  -framerate 30 -i "$FRAMES/f%05d.png" \
  -filter_complex "[1:v]format=rgba[av];[0:v][av]overlay=x=${X}:y=${OVY}:format=auto:eval=frame[v]" \
  -map "[v]" -map 0:a -c:v libx264 -preset veryfast -crf 19 -pix_fmt yuv420p \
  ${DURATION:+-t "$DURATION"} -c:a copy "$OUT"

echo "  ✓ $OUT ($(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$OUT")s)"
echo "  · loudness of this window: $(ffmpeg -hide_banner -i "$OUT" -af volumedetect -f null - 2>&1 \
  | grep -E 'mean_volume' | sed 's/.*mean_volume/mean_volume/')"
echo "    (a short preview window can legitimately be the silent title card — run"
echo "     scripts/verify-video.sh on the full file before attaching)"
