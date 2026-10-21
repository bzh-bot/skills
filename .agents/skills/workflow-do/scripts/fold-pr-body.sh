#!/usr/bin/env bash
# fold-pr-body.sh — enforce the ONE-DESCRIPTION rule: GitHub process comments
# (screenshots / guided tour / implementation summary / review outcome) are
# folded into the PR body and the comments deleted; human discussion comments
# are untouched. Extracted from workflow-do-tour P7.6 + workflow-do-ship P8.2 (v8).
#
# ⚠️ AUTHOR-SAFE (learned the hard way): only the run's OWN comments and bots are
# ever folded/deleted. A body-text match alone is NOT sufficient — a human reviewer
# writing "nice work, review passed" matches the pattern and would have been
# silently DELETED. Never delete a comment authored by anyone else.
#
# Usage: fold-pr-body.sh <org/repo> <pr-number> [section-title]
#   section-title defaults to "## 📸 Screenshots"
# Env: GH_TOKEN must be set (pick the org token as in prebuild P1.3a).
set -euo pipefail

REPO="${1:?usage: fold-pr-body.sh <org/repo> <pr-number> [section-title]}"
PR="${2:?missing pr number}"
TITLE="${3:-## 📸 Screenshots}"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

PATTERN='Screenshot|Guided Tour|Implementation summary|review'

# 1. Collect process comments: pattern match AND author is us (or a bot).
ME=$(gh api user --jq .login 2>/dev/null || echo "")
gh api "repos/$REPO/issues/$PR/comments?per_page=100" > "$TMP/comments.json"
mapfile -t IDS < <(jq -r --arg me "$ME" '
  .[]
  | select(.body | test("'"$PATTERN"'"))
  | select((.user.login == $me) or (((.user.login // "") | endswith("[bot]"))))
  | .id' "$TMP/comments.json" 2>/dev/null || true)

# Report — never silently ignore — pattern matches authored by other humans.
SKIPPED_HUMAN=$(jq -r --arg me "$ME" '
  [ .[]
    | select(.body | test("'"$PATTERN"'"))
    | select((.user.login != $me) and ((((.user.login // "") | endswith("[bot]")) | not)))
  ] | length' "$TMP/comments.json" 2>/dev/null || echo 0)
if [ "${SKIPPED_HUMAN:-0}" -gt 0 ]; then
  echo "note: skipped ${SKIPPED_HUMAN} pattern-matching comment(s) authored by someone else (human) — left untouched"
fi

if [ "${#IDS[@]}" -eq 0 ] || [ -z "${IDS[0]:-}" ]; then
  echo "no process comments found — nothing to fold"
  exit 0
fi

# 2. Append the comment bodies under the section title (never overwrite the body)
gh pr view "$PR" --repo "$REPO" --json body -q .body > "$TMP/body.md" 2>/dev/null || true
{
  cat "$TMP/body.md" 2>/dev/null
  echo ""
  echo "$TITLE"
  echo ""
  for id in "${IDS[@]}"; do
    gh api "repos/$REPO/issues/comments/$id" --jq '.body'
    echo ""
    echo "---"
    echo ""
  done
} > "$TMP/new-body.md"
gh pr edit "$PR" --repo "$REPO" --body-file "$TMP/new-body.md"

# 3. Delete the folded comments (their content now lives in the body)
for id in "${IDS[@]}"; do
  gh api -X DELETE "repos/$REPO/issues/comments/$id"
done

echo "folded ${#IDS[@]} process comment(s) into the PR body and deleted them"