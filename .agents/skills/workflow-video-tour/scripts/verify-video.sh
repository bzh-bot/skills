#!/usr/bin/env bash
# verify-video.sh — refuse to publish a video that is silent, dead-aired, or has
# an annotation box that never landed. Run this before `gh pr edit --attach`.
#
# ImageMagick's scope here is VERIFICATION ONLY — never annotation. It is used to
# (a) sample the frame where a burned-in annotation box should be and (b) montage the
# contact sheet. Drawings are never produced by ImageMagick: annotations live in the page
# (`workflow-do/scripts/annotate.js`, captured by BOTH the screenshots and the video).
#
# Usage: verify-video.sh <video.mp4> [--timeline timeline.json] [--video-json video.json]
set -uo pipefail

VIDEO="${1:-}"; [ -n "$VIDEO" ] || { echo "usage: verify-video.sh <video.mp4> [--timeline t.json] [--video-json video.json]" >&2; exit 2; }
shift || true
TIMELINE=""; VIDEOJSON=""
while [ $# -gt 0 ]; do
  case "$1" in
    --timeline) TIMELINE="$2"; shift 2;;
    --video-json) VIDEOJSON="$2"; shift 2;;
    *) shift;;
  esac
done
[ -f "$VIDEO" ] || { echo "FAIL: $VIDEO not found" >&2; exit 1; }
# A verification script that silently skips a check is worse than no check: a typo in
# --video-json used to make the box test and the contact sheet do nothing at all.
for pair in "TIMELINE:timeline" "VIDEOJSON:video-json"; do
  var=${pair%%:*}; name=${pair##*:}
  if [ -n "${!var}" ] && [ ! -f "${!var}" ]; then
    echo "FAIL: --$name ${!var} does not exist (refusing to 'verify' without it)" >&2
    exit 2
  fi
done

FAIL=0
note() { printf '  %-9s %s\n' "$1" "$2"; }

echo "── container ──────────────────────────────────────────────"
probe=$(ffprobe -v error -show_entries stream=codec_type,codec_name,width,height,avg_frame_rate -show_entries format=duration,size -of default=nw=1 "$VIDEO")
echo "$probe" | sed 's/^/  /'
if ! echo "$probe" | grep -q 'codec_type=video'; then note FAIL "no video stream"; FAIL=1; fi
if ! echo "$probe" | grep -q 'codec_type=audio'; then note FAIL "no audio stream — the narration is missing"; FAIL=1; fi
size_mb=$(( $(stat -c%s "$VIDEO") / 1024 / 1024 ))
[ "$size_mb" -lt 40 ] || note WARN "${size_mb} MB — GitHub attachment limit is ~100 MB; consider a lower CRF"
note OK "${size_mb} MB"

echo "── loudness ───────────────────────────────────────────────"
vol=$(ffmpeg -hide_banner -i "$VIDEO" -af volumedetect -f null - 2>&1)
mean=$(echo "$vol" | awk '/mean_volume/{print $5}')
max=$(echo "$vol" | awk '/max_volume/{print $5}')
note INFO "mean ${mean:-?} dB · max ${max:-?} dB"
if [ -n "${mean:-}" ] && awk -v m="$mean" 'BEGIN{exit !(m < -35)}'; then
  note FAIL "mean below -35 dB — effectively silent"; FAIL=1
elif [ -n "${max:-}" ] && awk -v m="$max" 'BEGIN{exit !(m < -12)}'; then
  note WARN "quiet peak (${max} dB) — check loudnorm ran"
fi

echo "── dead air (silence > 2 s) ───────────────────────────────"
spans=$(ffmpeg -hide_banner -i "$VIDEO" -af silencedetect=noise=-45dB:d=2 -f null - 2>&1 | grep -c silence_start)
note INFO "${spans} silence span(s) — 1 (the title card) is expected"
if [ "$spans" -gt 3 ]; then note FAIL "too many long silences — a beat is missing its narration"; FAIL=1; fi

echo "── annotation boxes ───────────────────────────────────────"
if [ -n "$TIMELINE" ] && [ -n "$VIDEOJSON" ] && command -v magick >/dev/null 2>&1; then
  tmp=$(mktemp -d)
  # shellcheck disable=SC2064
  trap "rm -rf $tmp" EXIT
  while read -r id rect color start vw vh; do
    [ "$rect" = "null" ] && continue
    x=$(echo "$rect" | jq -r '.x'); y=$(echo "$rect" | jq -r '.y'); w=$(echo "$rect" | jq -r '.w')
    fw=$(jq -r '.width' "$VIDEOJSON"); sx=$(awk -v a="$fw" -v b="$vw" 'BEGIN{print a/b}')
    cx=$(awk -v v="$x" -v s="$sx" 'BEGIN{printf "%d", v*s}')
    cy=$(awk -v v="$y" -v s="$sx" 'BEGIN{printf "%d", v*s}')
    cw=$(awk -v v="$w" -v s="$sx" 'BEGIN{printf "%d", v*s}')
    mid=$(awk -v a="$start" 'BEGIN{printf "%.2f", a+4}')
    ffmpeg -hide_banner -loglevel error -y -ss "$mid" -i "$VIDEO" -frames:v 1 -vf "crop=${cw}:5:${cx}:${cy}" "$tmp/edge.png" 2>/dev/null || continue
    read -r r g b < <(magick "$tmp/edge.png" -resize 1x1 -format '%[fx:int(255*r)] %[fx:int(255*g)] %[fx:int(255*b)]' info:)
    verdict="box not visible"
    if [ "$color" = "#EF4444" ] && [ "$r" -gt $((g + 10)) ] && [ "$r" -gt $((b + 10)) ]; then verdict="red box landed"; fi
    if [ "$color" = "#22C55E" ] && [ "$g" -gt $((r + 10)) ] && [ "$g" -gt $((b + 10)) ]; then verdict="green box landed"; fi
    note "$([ "$verdict" = "box not visible" ] && echo WARN || echo OK)" "$id @${mid}s rgb($r,$g,$b) — $verdict"
  done < <(jq -r --slurpfile v "$VIDEOJSON" '
      ($v[0].beats | map({key: .id, value: .start}) | from_entries) as $times
      | .[] | select(.rect != null and .rect != "null")
      | [.id, (.rect | tojson), (.boxColor // "#22C55E"), ($times[.id] // 0), (.viewportW // 0)] | @tsv' "$TIMELINE" 2>/dev/null)
else
  note SKIP "pass --timeline and --video-json (with jq + magick) to check boxes landed"
fi

echo "── contact sheet ──────────────────────────────────────────"
# Resolve a WORKING montage first. IM6 ships the `montage` binary; IM7 uses
# `magick montage`. A `magick` that is really IM6 (the cage ships /usr/local/bin/magick
# as a convert shim) parses `magick montage` as `convert montage` and fails — that is
# how this check used to print OK without ever writing the sheet (2026-10-07, <KEY>).
MONTAGE_CMD=""
if command -v montage >/dev/null 2>&1; then
  MONTAGE_CMD="montage"
elif command -v magick >/dev/null 2>&1 && magick -version 2>/dev/null | grep -q 'ImageMagick 7'; then
  MONTAGE_CMD="magick montage"
fi
# A check that silently does nothing is worse than no check: this used to print OK
# even when montage never wrote the file (n counted ATTEMPTS, not landed frames, and
# the glob also matched the *-raw.png files). Now: real frame count, asserted output,
# and a loud FAIL when the toolchain is missing.
if [ -z "$VIDEOJSON" ]; then
  note FAIL "no --video-json — the per-beat contact-sheet check cannot run (refusing a silent skip)"
  FAIL=1
elif [ -z "$MONTAGE_CMD" ]; then
  note FAIL "no working montage — need IM6 'montage' or IM7 'magick montage' (an IM6-shimmed 'magick', as in the cage at /usr/local/bin/magick, parses 'magick montage' as 'convert montage' and fails); the contact-sheet check CANNOT run, so do not publish as verified"
  FAIL=1
else
  sheet=$(mktemp -d); n=0; ok=0
  # Frame labels are burned in with ffmpeg's drawtext, not `magick -annotate`: ImageMagick
  # stays a montage/sampling tool only, and a missing font must not fail the extraction.
  FONT=""
  for f in /usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf; do
    [ -f "$f" ] && { FONT="$f"; break; }
  done
  while IFS=$'\t' read -r id start end; do
    [ -n "$id" ] || continue
    mid=$(awk -v a="$start" -v b="$end" 'BEGIN{printf "%.2f", (a+b)/2}')
    frame="$sheet/$(printf '%02d' "$n")-raw.png"
    ffmpeg -hide_banner -loglevel error -y -ss "$mid" -i "$VIDEO" -frames:v 1 \
      -vf "scale=760:-1,drawbox=x=0:y=ih-30:w=iw:h=30:color=black@0.75:t=fill" \
      "$frame" 2>/dev/null || { n=$((n+1)); continue; }
    [ -s "$frame" ] || { n=$((n+1)); continue; }
    out_frame="$sheet/$(printf '%02d' "$n").png"
    if [ -n "$FONT" ]; then
      txt="$sheet/$(printf '%02d' "$n").txt"
      printf '%s @%ss' "$id" "$mid" > "$txt"
      ffmpeg -hide_banner -loglevel error -y -i "$frame" \
        -vf "drawtext=fontfile=$FONT:textfile=$txt:fontcolor=white:fontsize=20:x=10:y=h-26" \
        "$out_frame" 2>/dev/null || true
    fi
    [ -s "$out_frame" ] || cp "$frame" "$out_frame"
    ok=$((ok+1)); n=$((n+1))
  done < <(jq -r '.beats[] | [.id, .start, .end] | @tsv' "$VIDEOJSON" 2>/dev/null)
  if [ "$ok" -eq 0 ]; then
    note FAIL "no frame could be extracted at any beat of $VIDEO — check the video and the beat timings"
    FAIL=1
  else
    out="$(dirname "$VIDEO")/contact-sheet.png"
    rm -f "$out"
    if $MONTAGE_CMD "$sheet"/[0-9][0-9].png -tile 2x -geometry +5+5 -background '#111' "$out" >/dev/null 2>&1 && [ -s "$out" ]; then
      note OK "$out — one frame per beat ($ok frames): LOOK at it before attaching"
    else
      note FAIL "contact sheet NOT written ($out) although $ok frames were captured — montage failed; the video is NOT verified"
      FAIL=1
    fi
  fi
  rm -rf "$sheet"
fi

echo "───────────────────────────────────────────────────────────"
if [ "$FAIL" -eq 1 ]; then echo "❌ verification FAILED — fix before attaching"; exit 1; fi
echo "✅ verification passed — safe to attach"
