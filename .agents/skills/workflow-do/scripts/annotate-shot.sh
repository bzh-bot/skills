#!/usr/bin/env bash
# annotate-shot.sh — annotate the live page IN THE DOM, screenshot it, and record the
# evidence that the overlay was actually there.
#
# WHY THIS EXISTS (user directive 2026-10-19): annotations are NEVER painted onto a PNG
# afterwards — no ImageMagick, no "re-annotate the captured image". A painted box cannot
# follow the page, cannot be checked against the element, disagrees with the video capture
# of the same state, and looks identical to a real one in review. This is the ONE command
# the tour uses, so the screenshot and its evidence cannot drift apart:
#
#   inject annotate.js  →  verify the layer mounted  →  draw the marks  →  screenshot
#   →  append {file, sha256, mounted, styleApplied, marks, url, at} to annotations.json
#
# If the page refuses injected styles (CSP), the target does not resolve, or nothing was
# drawn, this script EXITS 1 and the stage FAILS the annotation gate. It never falls back
# to painting pixels.
#
# Usage:
#   annotate-shot.sh --out FILE [--box SELECTOR]... [--label TEXT] [--color before|after|accent]
#                    [--arrow FROM,TO] [--banner before|after] [--url URL] [--clear]
#                    [--session S] [--profile P] [--cdp URL] [--ledger FILE] [--no-shot]
#
# Env: WORKFLOW_RUN_ENV (default /tmp/workflow-run.env) supplies CHROME_SESSION,
#      CHROME_SESSION_PROFILE, CHROME_CDP_PORT; SCREENSHOTS_DIR supplies the default ledger.
set -uo pipefail

RUN_ENV="${WORKFLOW_RUN_ENV:-/tmp/workflow-run.env}"
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INJECT="$SELF_DIR/annotate.js"

runvar() { [ -f "$RUN_ENV" ] && sed -n "s/^$1=\"\(.*\)\"\$/\1/p" "$RUN_ENV" | tail -1; }

SESSION="${CHROME_SESSION:-$(runvar CHROME_SESSION)}"
PROFILE="${CHROME_SESSION_PROFILE:-$(runvar CHROME_SESSION_PROFILE)}"
CDP_PORT="${CHROME_CDP_PORT:-$(runvar CHROME_CDP_PORT)}"
CDP_URL="${CHROME_CDP_URL:-}"
[ -z "$CDP_URL" ] && [ -n "$CDP_PORT" ] && CDP_URL="http://127.0.0.1:$CDP_PORT"

OUT=""; URL=""; LABEL=""; COLORS_SPEC=""; BANNER=""; ARROW=""; CLEAR=0; NO_SHOT=0
LEDGER=""
BOXES=()
usage() { sed -n '20,26p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT="${2:-}"; shift 2;;
    --url) URL="${2:-}"; shift 2;;
    --box) BOXES+=("${2:-}"); shift 2;;
    --label) LABEL="${2:-}"; shift 2;;
    --color) COLORS_SPEC="${2:-}"; shift 2;;
    --arrow) ARROW="${2:-}"; shift 2;;
    --banner) BANNER="${2:-}"; shift 2;;
    --clear) CLEAR=1; shift;;
    --no-shot) NO_SHOT=1; shift;;
    --ledger) LEDGER="${2:-}"; shift 2;;
    --session) SESSION="${2:-}"; shift 2;;
    --profile) PROFILE="${2:-}"; shift 2;;
    --cdp) CDP_URL="${2:-}"; shift 2;;
    -h|--help) usage;;
    *) echo "annotate-shot.sh: unknown argument $1" >&2; usage;;
  esac
done

[ -f "$INJECT" ] || { echo "FAIL: annotate.js not found at $INJECT" >&2; exit 1; }
[ -n "$OUT" ] || usage

# The full attach quadruple — a call missing --profile/--cdp/--headed launches a second,
# logged-out Chrome (see SHARED-POLICY "ONE CHROME PER RUN").
AB=(agent-browser --headed)
[ -n "$SESSION" ] && AB+=(--session "$SESSION" --pin-tab)
[ -n "$PROFILE" ] && AB+=(--profile "$PROFILE")
[ -n "$CDP_URL" ] && AB+=(--cdp "$CDP_URL")
ab() { "${AB[@]}" "$@" 2>&1; }

say() { printf '%s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# ── navigate (optional; the caller usually opened the page already) ──────────
if [ -n "$URL" ]; then
  ab open "$URL" >/dev/null || fail "could not open $URL"
  ab wait --load networkidle >/dev/null 2>&1 || true
fi

# ── inject + prove the layer mounted ────────────────────────────────────────
if ! ab eval --stdin < "$INJECT" >/dev/null; then
  fail "annotate.js could not be injected into the page — annotations are IN-PAGE ONLY; fix the injection (CSP, wrong tab) and retry. There is no post-processing fallback."
fi

status_json() {
  local raw inner
  raw="$(ab eval "__wfAnnot && __wfAnnot.status()")" || return 1
  inner="$(printf '%s' "$raw" | jq -r '.' 2>/dev/null)" || return 1
  printf '%s' "$inner"
}

ST="$(status_json)" || fail "the annotation layer did not answer status() — injection failed"
[ "$(printf '%s' "$ST" | jq -r '.mounted')" = "true" ] \
  || fail "the annotation overlay did not mount (styleApplied=$(printf '%s' "$ST" | jq -r '.styleApplied')). The page refuses injected styles; annotations stay IN-PAGE and the gate fails — do not paint the PNG."
[ "$(printf '%s' "$ST" | jq -r '.styleApplied')" = "true" ] \
  || fail "the annotation styles were blocked (CSP?). The overlay would be invisible in the screenshot; the gate fails rather than accept an unannotated file."

# ── draw ───────────────────────────────────────────────────────────────────
if [ "$CLEAR" -eq 1 ]; then ab eval "__wfAnnot.clear()" >/dev/null; fi

COLOR="${COLORS_SPEC:-accent}"
for sel in "${BOXES[@]:-}"; do
  [ -n "$sel" ] || continue
  if [ -n "$LABEL" ]; then
    r="$(ab eval "__wfAnnot.box($(printf '%s' "$sel" | jq -Rs .), {label: $(printf '%s' "$LABEL" | jq -Rs .), color: $(printf '%s' "$COLOR" | jq -Rs .)})")"
  else
    r="$(ab eval "__wfAnnot.box($(printf '%s' "$sel" | jq -Rs .), {color: $(printf '%s' "$COLOR" | jq -Rs .)})")"
  fi
  r="$(printf '%s' "$r" | tr -d '"')"
  [ "$r" = "ok" ] || fail "box target not found: $sel (the page has no such element — fix the selector; a missing target is a failed beat, not an unannotated screenshot)"
done

if [ -n "$ARROW" ]; then
  from="${ARROW%%,*}"; to="${ARROW#*,}"
  r="$(ab eval "__wfAnnot.arrow($(printf '%s' "$from" | jq -Rs .), $(printf '%s' "$to" | jq -Rs .), {color: $(printf '%s' "$COLOR" | jq -Rs .)})" | tr -d '"')"
  [ "$r" = "ok" ] || fail "arrow endpoints not found: $ARROW"
fi

if [ -n "$LABEL" ] && [ "${#BOXES[@]}" -eq 0 ]; then
  ab eval "__wfAnnot.label($(printf '%s' "$LABEL" | jq -Rs .), {color: $(printf '%s' "$COLOR" | jq -Rs .)})" >/dev/null \
    || fail "could not draw the label"
fi

if [ -n "$BANNER" ]; then
  ab eval "__wfAnnot.banner($(printf '%s' "$BANNER" | jq -Rs .))" >/dev/null || fail "could not draw the banner"
fi

# ── re-read the evidence: ≥1 mark on a mounted overlay ─────────────────────
ST="$(status_json)" || fail "lost the annotation layer before the screenshot"
MARKS="$(printf '%s' "$ST" | jq -r '.marks // 0')"
[ "$MARKS" -ge 1 ] \
  || fail "nothing was drawn (marks=0) — pass --box/--label/--arrow/--banner. A screenshot with no mark is not an annotated screenshot."

if [ "$NO_SHOT" -eq 1 ]; then
  say "annotate-shot: mounted, styleApplied, marks=$MARKS (no screenshot requested)"
  exit 0
fi

# ── screenshot + ledger ────────────────────────────────────────────────────
mkdir -p "$(dirname "$OUT")"
ab screenshot "$OUT" >/dev/null || fail "agent-browser screenshot $OUT failed"
[ -s "$OUT" ] || fail "screenshot $OUT is empty"

HASH="$(sha256sum "$OUT" | awk '{print $1}')"
[ -n "$LEDGER" ] || LEDGER="$(dirname "$OUT")/annotations.json"
PAGE_URL="$(printf '%s' "$ST" | jq -r '.url')"
ENTRY="$(jq -n \
  --arg file "$(basename "$OUT")" --arg path "$OUT" --arg sha "$HASH" --arg url "$PAGE_URL" \
  --arg at "$(date -Is)" --argjson marks "$MARKS" \
  --argjson mounted "$(printf '%s' "$ST" | jq '.mounted')" \
  --argjson style "$(printf '%s' "$ST" | jq '.styleApplied')" \
  '{file:$file, path:$path, sha256:$sha, mounted:$mounted, styleApplied:$style, marks:$marks, url:$url, at:$at}')"
TMP="$(mktemp)"
if [ -f "$LEDGER" ]; then
  jq --arg file "$(basename "$OUT")" --argjson e "$ENTRY" '[.[] | select(.file != $file)] + [$e]' "$LEDGER" > "$TMP" \
    || { rm -f "$TMP"; fail "ledger $LEDGER is not valid JSON"; }
else
  jq -n --argjson e "$ENTRY" '[$e]' > "$TMP"
fi
mv "$TMP" "$LEDGER"

say "annotate-shot: $OUT  marks=$MARKS  sha256=${HASH:0:12}…  evidence → $LEDGER"
