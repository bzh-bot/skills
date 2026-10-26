#!/usr/bin/env bash
# workflow-do RUN pane launcher.
#
# The run pane runs THIS script, not a pi session: the deterministic sequencer
# (workflow-do.ts) runs in the FOREGROUND so the pane shows the run, and pi is only
# the FAILURE FALLBACK when the sequencer exits non-zero.
#
# Inputs come from the environment (never from argv quoting) — the chief of staff kickoff
# exports them and cage() forwards them into the container:
#   WORKFLOW_MODE         build | iterate | review            (required)
#   WORKFLOW_TICKET_REF   ticket reference, or PR ref/number  (required)
#   WORKFLOW_RESUME       1   → --resume (continue after the last OK stage)
#   WORKFLOW_STAGE        <n> → --stage <n> (rerun a single stage)
#   WORKFLOW_FRESH        1   → --fresh (discard stale run state)
#   WORKFLOW_PI_NAME      run/fallback session name (pi --name)
#   WORKFLOW_PI_MODEL     model pin — kept for stage panes and the fallback pi
#   WORKFLOW_FALLBACK_PI  1 (default) → hand over to pi on failure; 0 → just exit
#   WORKFLOW_RUN_LOG      run log     (default /tmp/workflow-do-run.log)
#   WORKFLOW_RUN_ENV      run state   (default /tmp/workflow-run.env)
#   WORKFLOW_CHECK        1 → print what would run, exit 0, run NOTHING (self-check)
#
# Subcommand / flag:
#   run.sh preflight      (or WORKFLOW_PREFLIGHT=1) → run scripts/preflight.sh only:
#                         PASS/FAIL/SKIP for dashboard env keys, AWS SSO, GitHub API +
#                         browser login, local dashboard JWT. Exit code is preflight's.
#
# Hard rules: never loop, never retry, never block on intercom. The PR's
# draft→ready transition is owned by the ship-p8 / build-fix stages (gh pr ready +
# verified isDraft=false); never flip it by hand in a recovery step.
set -uo pipefail

SKILL_DIR="${WORKFLOW_SKILL_DIR:-$HOME/.agents/skills/workflow-do}"
TSX="${WORKFLOW_TSX:-$HOME/.pi/agent/npm/node_modules/tsx/dist/cli.mjs}"
SCRIPT="$SKILL_DIR/workflow-do.ts"
SELF="${BASH_SOURCE[0]}"

MODE="${WORKFLOW_MODE:-}"
REF="${WORKFLOW_TICKET_REF:-}"
NAME="${WORKFLOW_PI_NAME:-}"
RUN_LOG="${WORKFLOW_RUN_LOG:-/tmp/workflow-do-run.log}"
RUN_ENV="${WORKFLOW_RUN_ENV:-/tmp/workflow-run.env}"
FALLBACK_PI="${WORKFLOW_FALLBACK_PI:-1}"

# node comes from nvm — make sure it is on PATH in this (non-interactive) pane shell.
if ! command -v node >/dev/null 2>&1; then
  [ -s "$HOME/.nvm/nvm.sh" ] && . "$HOME/.nvm/nvm.sh"
fi

FLAGS=()
[ "${WORKFLOW_RESUME:-}" = "1" ] && FLAGS+=(--resume)
[ -n "${WORKFLOW_STAGE:-}" ] && FLAGS+=(--stage "${WORKFLOW_STAGE}")
[ "${WORKFLOW_FRESH:-}" = "1" ] && FLAGS+=(--fresh)

CMD=(node "$TSX" "$SCRIPT" ${FLAGS[@]+"${FLAGS[@]}"} "$MODE" "$REF")

# ── preflight only (standalone): run.sh preflight | WORKFLOW_PREFLIGHT=1 ──
# The sequencer runs this automatically BEFORE the tour; this entry lets a human or
# the failure-fallback re-check the same five things without starting a run.
if [ "${1:-}" = "preflight" ] || [ "${WORKFLOW_PREFLIGHT:-}" = "1" ]; then
  exec bash "$SKILL_DIR/scripts/preflight.sh"
fi

case "$MODE" in
build | iterate | review) ;;
*)
  echo "❌ workflow-do launcher: WORKFLOW_MODE must be build|iterate|review (got '${MODE:-<unset>}')" >&2
  exit 2
  ;;
esac
if [ -z "$REF" ]; then
  echo "❌ workflow-do launcher: WORKFLOW_TICKET_REF is not set (ticket ref for build; PR ref/number for iterate/review)" >&2
  exit 2
fi

# ── self-check: print the resolved launch and exit WITHOUT running anything ──
if [ "${WORKFLOW_CHECK:-}" = "1" ]; then
  echo "workflow-do launcher — self check (WORKFLOW_CHECK=1; nothing will run)"
  echo "  launcher:  $SELF"
  echo "  mode:      $MODE"
  echo "  ref:       $REF"
  echo "  flags:     ${FLAGS[*]:-<none>}"
  echo "  run log:   $RUN_LOG"
  echo "  run env:   $RUN_ENV"
  echo "  fallback:  WORKFLOW_FALLBACK_PI=$FALLBACK_PI${NAME:+ name=$NAME}${WORKFLOW_PI_MODEL:+ model=$WORKFLOW_PI_MODEL}${WORKFLOW_PI_THINKING:+ thinking=$WORKFLOW_PI_THINKING}"
  echo "  preflight: bash $SKILL_DIR/scripts/preflight.sh   (also: $SELF preflight)"
  echo "  chrome:    bash $SKILL_DIR/scripts/chrome.sh status|revive"
  printf '  command:   '
  printf '%q ' "${CMD[@]}"
  printf '\n'
  exit 0
fi

mkdir -p "$(dirname "$RUN_LOG")" 2>/dev/null || true
printf '\n=== workflow-do %s %s — %s (launcher pid %s) ===\n' \
  "$MODE" "$REF" "$(date -Is 2>/dev/null || date)" "$$" >>"$RUN_LOG" 2>&1

# Foreground, tee'd to the run log: the pane shows the run AND the log keeps it.
"${CMD[@]}" 2>&1 | tee -a "$RUN_LOG"
rc=${PIPESTATUS[0]}

if [ "$rc" -eq 0 ]; then
  echo "✅ workflow-do $MODE $REF finished (exit 0) — log: $RUN_LOG"
  echo "   The chief of staff owns cage cleanup once the run reports complete."
  exit 0
fi

# ── failure: banner, then pi as the fallback supervisor (never a retry loop) ──
echo ""
echo "❌ workflow-do $MODE $REF exited non-zero (code $rc) — NOT retrying."
echo "   run log:    $RUN_LOG"
echo "   run env:    $RUN_ENV"
echo "   resume:     WORKFLOW_MODE=$(printf '%q' "$MODE") WORKFLOW_TICKET_REF=$(printf '%q' "$REF") WORKFLOW_RESUME=1 $SELF"
echo "   one stage:  WORKFLOW_MODE=$(printf '%q' "$MODE") WORKFLOW_TICKET_REF=$(printf '%q' "$REF") WORKFLOW_STAGE=<stage-name> $SELF"
echo "   preflight:  $SELF preflight   (dashboard env keys, AWS SSO, GitHub API + browser login, dashboard JWT)"
echo "   browser:    bash $SKILL_DIR/scripts/chrome.sh status   then   ... chrome.sh revive"

if [ "$FALLBACK_PI" = "0" ]; then
  echo "   WORKFLOW_FALLBACK_PI=0 — leaving the pane at a shell prompt."
  exit "$rc"
fi

PI_PROMPT="workflow-do's deterministic run exited non-zero (code ${rc}); you are the FAILURE FALLBACK supervisor, not the run launcher. Read the run log (${RUN_LOG}) and the run env (${RUN_ENV}), diagnose the failure, fix the root cause, then relaunch the sequencer with the same mode and ref: node ${TSX} ${SCRIPT} --resume ${MODE} ${REF} (or --stage <name> to rerun a single stage). Do not loop or retry blindly. Do not change the PR's draft/ready state by hand — the ship-p8/build-fix stages own draft→ready (`gh pr ready` + verified isDraft=false) and the script re-checks it; a rerun of that stage is the correct fix. When the run completes, or when you are blocked and need a decision, message the chief-of-staff session with the intercom tool; if intercom is unavailable, skip it silently and report here instead."

echo "   handing over to pi as the failure fallback (WORKFLOW_FALLBACK_PI=$FALLBACK_PI)…"
exec pi ${NAME:+--name "$NAME"} ${WORKFLOW_PI_MODEL:+--model "$WORKFLOW_PI_MODEL"} ${WORKFLOW_PI_THINKING:+--thinking "$WORKFLOW_PI_THINKING"} "$PI_PROMPT"
