#!/usr/bin/env bash
# check-annotations.sh — the annotation gate. A screenshot is annotated ONLY when the
# in-page overlay was mounted for THAT capture and drew at least one mark; this script
# rejects every other PNG instead of letting it through as "annotated".
#
# WHY (user directive 2026-10-19): the tour used to accept any `*-annotated.png` on trust,
# and ImageMagick was available to paint boxes onto a captured PNG afterwards. A painted
# file is a different artefact — it cannot be checked against the element and disagrees
# with the video — so the fallback is gone and the only proof is the evidence that
# `annotate-shot.sh` writes: {file, sha256, mounted, styleApplied, marks}. A file with no
# entry, a stale entry (the PNG changed), marks=0, or an overlay that never mounted FAILS.
#
# Usage:
#   check-annotations.sh <dir|file>... [--ledger FILE]
#
#   <dir>   every *-annotated.png inside it is checked (non-recursive), ledger defaults to
#           <dir>/annotations.json
#   <file>  checked directly; the ledger defaults to its directory
#
# Exit 0 only when every candidate has a matching, valid entry.
set -uo pipefail

LEDGER=""; TARGETS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --ledger) LEDGER="${2:-}"; shift 2;;
    -h|--help) sed -n '12,23p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) TARGETS+=("$1"); shift;;
  esac
done

[ "${#TARGETS[@]}" -gt 0 ] || { echo "usage: check-annotations.sh <dir|file>... [--ledger FILE]" >&2; exit 2; }
command -v jq >/dev/null || { echo "FAIL: jq is required" >&2; exit 2; }

FILES=()
for t in "${TARGETS[@]}"; do
  [ -e "$t" ] || { echo "FAIL: $t does not exist" >&2; exit 2; }
  if [ -d "$t" ]; then
    [ -n "$LEDGER" ] || LEDGER="$t/annotations.json"
    while IFS= read -r f; do FILES+=("$f"); done < <(find "$t" -maxdepth 1 -type f -name '*-annotated.png' | sort)
  else
    [ -n "$LEDGER" ] || LEDGER="$(dirname "$t")/annotations.json"
    FILES+=("$t")
  fi
done

if [ "${#FILES[@]}" -eq 0 ]; then
  echo "FAIL: no *-annotated.png found in ${TARGETS[*]} — an unannotated screenshot may not be uploaded as annotated" >&2
  exit 1
fi

if [ ! -f "$LEDGER" ]; then
  echo "FAIL: no annotation evidence at $LEDGER — every screenshot must be captured with scripts/annotate-shot.sh (in-page overlay). Painting a box onto a PNG afterwards is not an annotation." >&2
  exit 1
fi
jq -e 'type == "array"' "$LEDGER" >/dev/null 2>&1 || { echo "FAIL: $LEDGER is not a JSON array" >&2; exit 1; }

FAIL=0; OK=0
for f in "${FILES[@]}"; do
  base="$(basename "$f")"
  sha="$(sha256sum "$f" | awk '{print $1}')"
  entry="$(jq -c --arg f "$base" '[.[] | select(.file == $f)] | last // empty' "$LEDGER")"
  if [ -z "$entry" ]; then
    printf '  FAIL %-46s no annotation evidence (never captured with the in-page overlay)\n' "$base"; FAIL=$((FAIL+1)); continue
  fi
  mounted="$(printf '%s' "$entry" | jq -r '.mounted')"
  style="$(printf '%s' "$entry" | jq -r '.styleApplied')"
  marks="$(printf '%s' "$entry" | jq -r '.marks // 0')"
  rec_sha="$(printf '%s' "$entry" | jq -r '.sha256 // ""')"
  reason=""
  [ "$mounted" = "true" ] || reason="overlay never mounted"
  [ -z "$reason" ] && [ "$style" != "true" ] && reason="annotation styles were blocked"
  [ -z "$reason" ] && [ "$marks" -lt 1 ] && reason="no mark drawn"
  [ -z "$reason" ] && [ "$rec_sha" != "$sha" ] && reason="PNG changed after capture (evidence sha mismatch)"
  if [ -n "$reason" ]; then
    printf '  FAIL %-46s %s\n' "$base" "$reason"; FAIL=$((FAIL+1))
  else
    printf '  OK   %-46s marks=%s\n' "$base" "$marks"; OK=$((OK+1))
  fi
done

echo "───────────────────────────────────────────────────────────"
if [ "$FAIL" -gt 0 ]; then
  echo "❌ annotation gate FAILED — $FAIL file(s) are not annotated evidence. Re-capture them with scripts/annotate-shot.sh on the live page; never paint the PNG and never upload an unannotated file as annotated." >&2
  exit 1
fi
echo "✅ annotation gate passed — $OK file(s) carry in-page overlay evidence"
