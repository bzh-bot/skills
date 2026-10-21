#!/bin/bash
# send-summary-email.sh — SHIM. The real email script is send-summary-email.ts.
#
# This file is kept only so the container path /usr/local/bin/send-summary-email.sh
# (copied by the workflow-do Dockerfile) keeps working; it execs the TypeScript
# script and adds nothing of its own — no session scanning, no stats, no template.
#
# Callers may keep passing data as environment variables; the .ts reads the same
# run env (/tmp/workflow-run.env or $WORKFLOW_RUN_ENV) and the same env vars:
#   TICKET_ID, TICKET_URL, PR_URL, WORKTREE, TICKET_TITLE,
#   DB_SUMMARY, BACKEND_SUMMARY, FRONTEND_SUMMARY, RISK_METER,
#   DEPLOYMENT_STATUS, FRICTION, SCREENSHOTS (path|url|caption lines),
#   EMAIL_TO (default $NOTIFY_EMAIL), MSMTP_FROM, GH_TOKEN, NOTION_TOKEN
#
# Extra arguments are forwarded, so all three real modes work through the shim:
#   send-summary-email.sh --fetch-only --out /tmp/summary.json
#   send-summary-email.sh --render /tmp/body.html --json /tmp/summary.json
#   send-summary-email.sh --send --json /tmp/summary.json
#
# Never run the --send mode just to verify — render with --fetch-only/--render.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec npx --yes tsx "$SCRIPT_DIR/send-summary-email.ts" "$@"
