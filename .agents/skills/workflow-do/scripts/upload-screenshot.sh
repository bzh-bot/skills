#!/usr/bin/env bash
# upload-screenshot.sh — upload one image to GitHub's user-attachments CDN via the
# cage Chrome's logged-in session (the upload endpoint has no public API).
# Prints the permanent URL on stdout. Extracted from workflow-do-tour P7.6 (v8) so
# tour and build-fix share one tested implementation.
#
# Usage: upload-screenshot.sh <org/repo> <pr-or-issue-number> <image-path>
# Requires: agent-browser attached to the run's Chrome (the script-owned pane;
# attach with: agent-browser --headed --session "$CHROME_SESSION" --pin-tab open <url>),
# logged in to GitHub (verified at prebuild P1.3b).
set -euo pipefail

REPO="${1:?usage: upload-screenshot.sh <org/repo> <number> <image>}"
ISSUE="${2:?missing issue/pr number}"
IMG="${3:?missing image path}"
[ -f "$IMG" ] || { echo "FATAL: image not found: $IMG" >&2; exit 1; }
# The full attach triple is MANDATORY: --headed (no headless phantom) and
# --profile (no logged-out temp-profile phantom that kills the run's Chrome).
# ALWAYS prefer the run's SESSION profile COPY: pointing this at the SOURCE profile
# launches a second Chrome on the shared dir and DROPS EVERY TAB (incl. the permanent
# ticket/PR tabs) — <KEY-138> hit exactly that, 2026-09-30.
# Attach mode: when CHROME_CDP_URL is exported (the cage fixed-port recipe), attach over
# CDP and DO NOT pass --profile — on that path --profile makes the CLI launch its own
# Chrome (silent "exited early without DevToolsActivePort") and can kill the run browser.
# Without CHROME_CDP_URL fall back to the session-profile triple.
if [ -n "${CHROME_CDP_URL:-}" ]; then
  AB="agent-browser --headed --cdp $CHROME_CDP_URL"
else
  AB="agent-browser --headed --profile ${CHROME_SESSION_PROFILE:-${CHROME_USER_DATA_DIR:-$HOME/chrome-org}}"
fi
[ -n "${CHROME_SESSION:-}" ] && AB="$AB --session $CHROME_SESSION"

$AB open "https://github.com/$REPO/issues/$ISSUE"
$AB wait --load networkidle || true
# GitHub redirects .../issues/<n> to .../pull/<n> for PRs. Interacting before that
# redirect settles races the load (the comment form is fetched twice and the upload
# lands on a form that is then replaced) — <KEY-205>, 2026-10-01. Wait for a STABLE
# resolved URL (and a comment form) before touching the DOM.
for _i in $(seq 1 10); do
  _url=$($AB get url 2>/dev/null | tail -1)
  case "$_url" in
    */pull/*|*/issues/*) : ;;
    *) _url="" ;;
  esac
  if [ -n "$_url" ] && $AB eval '!!document.querySelector("form.js-new-comment-form")' 2>/dev/null | grep -qi true; then
    echo "upload-screenshot: settled on $_url"
    break
  fi
  sleep 1
done
# must be logged in (verified in P1.3b); GitHub only reacts to its own attach()
# flow, so hand the file from the comment form's input to GitHub's
# file-attachment element via DataTransfer:
$AB eval 'document.querySelector("form.js-new-comment-form input[type=file]").id = "workflow-upload"'
$AB upload "#workflow-upload" "$IMG"
$AB eval --stdin <<'JS'
(() => {
  const input = document.querySelector("#workflow-upload");
  const el = document.querySelector("form.js-new-comment-form file-attachment");
  const dt = new DataTransfer();
  for (const f of input.files) dt.items.add(f);
  el.attach(dt);
})()
JS
# GitHub pastes the permanent URL into the comment textarea — poll for it
for i in $(seq 1 15); do
  sleep 2
  URL=$($AB eval 'document.querySelector("#new_comment_field").value' | grep -o 'https://github.com/user-attachments/assets/[a-f0-9-]*' | head -1)
  if [ -n "$URL" ]; then
    $AB eval 'document.querySelector("#new_comment_field").value = ""'
    echo "$URL"
    exit 0
  fi
done
echo "FATAL: upload failed for $IMG" >&2
exit 1