#!/usr/bin/env bash
# avatar-visemes.sh — Rhubarb Lip Sync cues (A..H, X) for the avatar's mouth.
#
# Always run this on the FINISHED video's audio, not on the per-beat narration
# WAVs: the finished mix already contains the 400 ms lead-ins and the gaps
# between beats, so the cues line up with the timeline frame-for-frame and no
# offset maths is needed.
#
#   avatar-visemes.sh --video "$VIDEO_DIR/<slug>.mp4" --out "$VIDEO_DIR/avatar/cues.json"
#   avatar-visemes.sh --audio voice.wav               --out cues.json
set -euo pipefail

VIDEO=""; AUDIO=""; OUT="cues.json"; RHUBARB="${RHUBARB:-}"
while [ $# -gt 0 ]; do
  case "$1" in
    --video) VIDEO="$2"; shift 2 ;;
    --audio) AUDIO="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --rhubarb) RHUBARB="$2"; shift 2 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -n "$VIDEO$AUDIO" ] || { echo "FATAL: pass --video or --audio" >&2; exit 2; }

# ── ensure rhubarb (MIT, ~2 MB) ─────────────────────────────────────────────
if [ -z "$RHUBARB" ]; then
  RHUBARB=$(command -v rhubarb || true)
fi
if [ -z "$RHUBARB" ]; then
  RHUBARB=$(find "$HOME/.local/share/rhubarb" -type f -name rhubarb 2>/dev/null | head -1 || true)
fi
if [ -z "$RHUBARB" ]; then
  echo "  · installing Rhubarb Lip Sync 1.14.0 → ~/.local/share/rhubarb"
  tmp=$(mktemp -d)
  curl -sL -o "$tmp/r.zip" \
    https://github.com/DanielSWolf/rhubarb-lip-sync/releases/download/v1.14.0/Rhubarb-Lip-Sync-1.14.0-Linux.zip
  unzip -q -o "$tmp/r.zip" -d "$HOME/.local/share/rhubarb"
  rm -rf "$tmp"
  RHUBARB=$(find "$HOME/.local/share/rhubarb" -type f -name rhubarb | head -1)
fi
[ -x "$RHUBARB" ] || chmod +x "$RHUBARB"
echo "  · rhubarb: $RHUBARB ($("$RHUBARB" --version 2>&1 | head -1))"

# ── 16 kHz mono WAV ─────────────────────────────────────────────────────────
WORK=$(mktemp -d)
WAV="$AUDIO"
if [ -n "$VIDEO" ]; then
  WAV="$WORK/voice16k.wav"
  ffmpeg -hide_banner -loglevel error -y -i "$VIDEO" -vn -ac 1 -ar 16000 -c:a pcm_s16le "$WAV"
  echo "  · audio extracted: $(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$WAV")s"
fi

# ── cue ─────────────────────────────────────────────────────────────────────
mkdir -p "$(dirname "$OUT")"
"$RHUBARB" -f json -o "$OUT" --machineReadable "$WAV" >/dev/null 2>&1
python3 - "$OUT" <<'PY'
import collections, json, sys
d = json.load(open(sys.argv[1]))
cues = d["mouthCues"]
hist = collections.Counter(c["value"] for c in cues)
print(f"  · {len(cues)} cues over {cues[-1]['start']:.1f}s — "
      + ", ".join(f"{k}:{v}" for k, v in sorted(hist.items())))
if hist.get("X", 0) == len(cues):
    print("  ! every cue is X (no speech detected) — did you cue the right audio?")
PY
rm -rf "$WORK"
echo "  ✓ $OUT"
