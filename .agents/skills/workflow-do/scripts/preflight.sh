#!/usr/bin/env bash
# preflight.sh — fail-fast access preflight for a workflow-do run, BEFORE the tour.
#
# Why this exists (2026-10-19): all four live runs that day (<KEY-209>/1210/1211/1212)
# reached the tour with a dashboard missing NEXT_PUBLIC_MICROSOFT_CLIENT_ID, an
# expired AWS SSO session and a signed-out GitHub browser. Each was discovered
# mid-tour, after the pane had already started, and each cost a fix round. This
# script checks the same five things up front, prints PASS/FAIL/SKIP per check and
# exits non-zero on any FAIL with a one-line remediation — the sequencer refuses to
# launch the tour pane while a FAIL stands.
#
# Checks (all read-only — no repo writes, no installs, no new browser tabs):
#   env-file        dashboard/ or frontend/ env file exists
#   env-keys        its required <project>_* keys
#   env-oauth       its NEXT_PUBLIC_* sign-in keys (SKIP when a local JWT login is available)
#   aws-sso         AWS SSO profile still valid (non-interactive sts get-caller-identity)
#   github-api      gh authenticates with the run's GH_TOKEN_<account>
#   browser-github  the run Chrome is signed in to GitHub (cookie probe over CDP; SKIP when Chrome is down)
#   dashboard-login local dashboard login is possible (backend JWT_SECRET)
#
# Writes verdicts to $WORKFLOW_PREFLIGHT_ENV (default /tmp/workflow-preflight.env) as
#   PREFLIGHT_<CHECK>="PASS|FAIL|SKIP" / PREFLIGHT_<CHECK>_DETAIL="…" / PREFLIGHT_STATUS="ok|failed"
#
# Env:
#   WORKFLOW_RUN_ENV        run state (default /tmp/workflow-run.env)
#   WORKFLOW_PREFLIGHT_ENV  verdict file (default /tmp/workflow-preflight.env)
#   WORKFLOW_CWD            repo root (fallback: WORKTREE, then $PWD)
#   PREFLIGHT_AWS_PROFILES  space-separated candidate profiles (default: AWS_PROFILE, then the
#                           first SSO profile in ~/.aws/config)
#   PREFLIGHT_ENV_DIR       force the dashboard app dir (dashboard|frontend), else auto-detect
#   PREFLIGHT_OAUTH_OPTIONAL=1  do not FAIL when no OAuth provider is configured
#   PREFLIGHT_SKIP          space-separated check names to force SKIP (e.g. "aws-sso github-api"
#                           for a repo with no AWS/GitHub dependency)
#   PREFLIGHT_REQUIRED_ENV_KEYS  space-separated base keys this repo needs (default APP_API_URL MASSCEC_WEBAPP_URL;
#                           keys the app's source does not read are skipped automatically)
#
# Exit: 0 all PASS/SKIP · 1 at least one FAIL · 2 cannot run (no repo)
set -uo pipefail

RUN_ENV="${WORKFLOW_RUN_ENV:-/tmp/workflow-run.env}"
OUT="${WORKFLOW_PREFLIGHT_ENV:-/tmp/workflow-preflight.env}"
FAILS=0
PASSES=0
SKIPS=0

runvar() {
  [ -f "$RUN_ENV" ] || return 0
  sed -n "s/^$1=\"\(.*\)\"\$/\1/p" "$RUN_ENV" | tail -1
}

# Fresh verdict file per invocation (the run env stays append-only; this report does not).
mkdir -p "$(dirname "$OUT")" 2>/dev/null || true
: >"$OUT"

# Env-file values must stay single-line KEY="value" (stages source this file).
record() { # record CHECK STATE DETAIL
  local check="$1" state="$2" detail="${3:-}"
  detail="$(printf '%s' "$detail" | tr '"\n' '  ') "
  detail="${detail% }"
  mkdir -p "$(dirname "$OUT")" 2>/dev/null || true
  printf 'PREFLIGHT_%s="%s"\nPREFLIGHT_%s_DETAIL="%s"\n' \
    "$(printf '%s' "$check" | tr '[:lower:]-' '[:upper:]_')" "$state" \
    "$(printf '%s' "$check" | tr '[:lower:]-' '[:upper:]_')" "$detail" >>"$OUT"
}

verdict() { # verdict CHECK STATE MESSAGE [REMEDIATION]
  local check="$1" state="$2" message="$3" fix="${4:-}" s
  for s in ${PREFLIGHT_SKIP:-}; do
    if [ "$s" = "$check" ]; then
      state=SKIP
      message="skipped by PREFLIGHT_SKIP (${message})"
      fix=""
    fi
  done
  case "$state" in
    PASS) PASSES=$((PASSES + 1)); printf 'PASS %-16s %s\n' "$check" "$message" ;;
    SKIP) SKIPS=$((SKIPS + 1)); printf 'SKIP %-16s %s\n' "$check" "$message" ;;
    *)
      FAILS=$((FAILS + 1))
      printf 'FAIL %-16s %s%s\n' "$check" "$message" "${fix:+ | fix: $fix}"
      ;;
  esac
  record "$check" "$state" "${message}${fix:+ | fix: $fix}"
}

have_key() { # have_key FILE KEY — a non-empty assignment, ignoring comments
  grep -qE "^[[:space:]]*$2=[^[:space:]]+" "$1" 2>/dev/null
}

key_value() { # key_value FILE KEY — last value, quotes and CR stripped
  sed -n "s/^[[:space:]]*$2=\(.*\)\$/\1/p" "$1" 2>/dev/null | tail -1 | tr -d '\r' | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//"
}

REPO="${WORKFLOW_CWD:-}"
[ -n "$REPO" ] || REPO="$(runvar WORKTREE)"
[ -z "$REPO" ] && [ -d "$PWD/dashboard" ] && REPO="$PWD"
[ -z "$REPO" ] && [ -d "$PWD/frontend" ] && REPO="$PWD"
if [ -z "$REPO" ] || [ ! -d "$REPO" ]; then
  printf 'FAIL repo             cannot find the repo (WORKFLOW_CWD/WORKTREE unset or missing) | fix: run this inside the cage with WORKFLOW_CWD set\n'
  record repo FAIL "cannot find the repo"
  printf 'PREFLIGHT_STATUS="failed"\n' >>"$OUT"
  exit 2
fi

# ── 1. dashboard/frontend env file ──────────────────────────────────────────
# Only apps this repo actually has are checked: a repo without a Next.js app must
# not be blocked by a frontend rule it cannot satisfy.
APP_DIR=""
ENV_FILE=""
for app in ${PREFLIGHT_ENV_DIR:+$PREFLIGHT_ENV_DIR} dashboard frontend web app; do
  [ -d "$REPO/$app" ] || continue
  [ -z "$APP_DIR" ] && APP_DIR="$app"
  for f in "$REPO/$app/.env.local" "$REPO/$app/.env"; do
    if [ -f "$f" ]; then
      APP_DIR="$app"
      ENV_FILE="$f"
      break 2
    fi
  done
done
if [ -n "$ENV_FILE" ]; then
  verdict env-file PASS "$ENV_FILE"
elif [ -n "$APP_DIR" ]; then
  verdict env-file FAIL "no $APP_DIR/.env.local or $APP_DIR/.env under $REPO" \
    "create $REPO/$APP_DIR/.env.local from the app README (base URLs + NEXT_PUBLIC_* sign-in keys)"
else
  verdict env-file SKIP "no dashboard/frontend app in this repo (nothing to configure)"
fi

# Does the app's SOURCE read KEY? Env files are excluded by the extension filter, so a
# key that only exists in .env.example does not count as required.
refs_source() {
  [ -n "$APP_DIR" ] || return 1
  grep -rqs --exclude-dir=node_modules --exclude-dir=.next --exclude-dir=dist --exclude-dir=build \
    --include='*.ts' --include='*.tsx' --include='*.js' --include='*.jsx' --include='*.mjs' \
    --include='*.cjs' --include='*.vue' --include='*.svelte' --include='*.astro' \
    -- "$1" "$REPO/$APP_DIR" 2>/dev/null
}

# ── 2. required env keys + NEXT_PUBLIC sign-in keys ────────────────────────
JWT_FILE=""
for f in "$REPO/backend/.env.local" "$REPO/backend/.env" "$REPO/.env.local" "$REPO/.env"; do
  if [ -f "$f" ] && have_key "$f" JWT_SECRET; then
    JWT_FILE="$f"
    break
  fi
done

REQ_KEYS="${PREFLIGHT_REQUIRED_ENV_KEYS:-APP_API_URL APP_WEBAPP_URL}"
if [ -z "$ENV_FILE" ]; then
  verdict env-keys SKIP "no env file to inspect"
  verdict env-oauth SKIP "no env file to inspect"
else
  APPLICABLE=""
  for k in $REQ_KEYS; do
    refs_source "$k" && APPLICABLE="$APPLICABLE $k"
  done
  if [ -z "$APPLICABLE" ]; then
    verdict env-keys SKIP "none of the configured required keys (${REQ_KEYS}) is read by $APP_DIR source — set PREFLIGHT_REQUIRED_ENV_KEYS for this repo"
  else
    MISSING_BASE=""
    for k in $APPLICABLE; do
      have_key "$ENV_FILE" "$k" || MISSING_BASE="$MISSING_BASE $k"
    done
    if [ -n "$MISSING_BASE" ]; then
      verdict env-keys FAIL "missing in $ENV_FILE:$MISSING_BASE" \
        "add the missing keys to $ENV_FILE (see $REPO/$APP_DIR/README.md)"
    else
      verdict env-keys PASS "required base keys set in $ENV_FILE (${APPLICABLE# })"
    fi
  fi
  # At least one OAuth provider drives the sign-in buttons; without one the login page
  # has no provider option (the <KEY> runs had a Microsoft-only dashboard and a missing
  # NEXT_PUBLIC_MICROSOFT_CLIENT_ID). A local JWT login is legitimate, so that is an
  # explicit SKIP — never a silent PASS that hides the missing keys.
  PROVIDER_KEYS=""
  PROVIDER_DETAIL=""
  for k in NEXT_PUBLIC_MICROSOFT_CLIENT_ID NEXT_PUBLIC_MICROSOFT_TENANT_ID NEXT_PUBLIC_GOOGLE_CLIENT_ID NEXT_PUBLIC_APPLE_SERVICE_ID; do
    refs_source "$k" || continue
    if have_key "$ENV_FILE" "$k"; then
      PROVIDER_DETAIL="$PROVIDER_DETAIL $k=set"
      case "$k" in NEXT_PUBLIC_MICROSOFT_TENANT_ID) ;; *) PROVIDER_KEYS="$PROVIDER_KEYS $k" ;; esac
    else
      PROVIDER_DETAIL="$PROVIDER_DETAIL $k=missing"
    fi
  done
  if [ -z "$PROVIDER_DETAIL" ]; then
    verdict env-oauth SKIP "no NEXT_PUBLIC_* OAuth provider keys are read by $APP_DIR source"
  elif [ -z "$(printf '%s' "$PROVIDER_KEYS" | tr -d ' ')" ]; then
    if [ -n "$JWT_FILE" ] && [ "${PREFLIGHT_OAUTH_OPTIONAL:-0}" != "1" ]; then
      verdict env-oauth SKIP "no NEXT_PUBLIC_* OAuth provider configured (${PROVIDER_DETAIL# }); local JWT login is available via $JWT_FILE"
    else
      verdict env-oauth FAIL "no NEXT_PUBLIC_* OAuth provider configured and no backend JWT_SECRET — the sign-in page cannot authenticate (${PROVIDER_DETAIL# })" \
        "add NEXT_PUBLIC_MICROSOFT_CLIENT_ID (+ NEXT_PUBLIC_MICROSOFT_TENANT_ID) to $ENV_FILE, or JWT_SECRET to backend/.env"
    fi
  else
    verdict env-oauth PASS "provider configured:${PROVIDER_KEYS};${PROVIDER_DETAIL}"
  fi
fi

# ── 3. AWS SSO profile validity (non-interactive) ─────────────────────────
if ! command -v aws >/dev/null 2>&1; then
  verdict aws-sso SKIP "aws CLI not on PATH"
else
  AWS_CANDIDATES="${PREFLIGHT_AWS_PROFILES:-${AWS_PROFILE:-}}"
  if [ -z "$AWS_CANDIDATES" ] && [ -f "$HOME/.aws/config" ]; then
    AWS_CANDIDATES="$(sed -n 's/^\[profile \([^]]*\)\]$/\1/p' "$HOME/.aws/config" | head -1)"
  fi
  if [ -z "$AWS_CANDIDATES" ]; then
    verdict aws-sso SKIP "no AWS profile configured (~/.aws/config has no [profile …])"
  else
    AWS_OK=""
    AWS_TRIED=""
    for prof in $AWS_CANDIDATES; do
      AWS_TRIED="$AWS_TRIED $prof"
      ident="$(AWS_PROFILE="$prof" AWS_PAGER="" AWS_CLI_AUTO_PROMPT=off AWS_EC2_METADATA_DISABLED=true \
        timeout 25 aws sts get-caller-identity --query Arn --output text 2>&1)"
      if [ "$?" -eq 0 ] && [ -n "$ident" ] && ! printf '%s' "$ident" | grep -qi 'error\|expired\|invalid'; then
        AWS_OK="$prof ($ident)"
        break
      fi
    done
    if [ -n "$AWS_OK" ]; then
      verdict aws-sso PASS "profile ${AWS_OK%% (*}"
    else
      verdict aws-sso FAIL "AWS SSO is not valid (tried:${AWS_TRIED}) — $(printf '%s' "$ident" | sed -n '/[^[:space:]]/{p;q;}' | cut -c1-160)" \
        "aws sso login --profile $(printf '%s' "$AWS_TRIED" | awk '{print $1}')"
    fi
  fi
fi

# ── 4. GitHub API auth via gh ─────────────────────────────────────────────
if ! command -v gh >/dev/null 2>&1; then
  verdict github-api SKIP "gh CLI not on PATH"
else
  TOKENS=""
  if [ -n "${GH_TOKEN:-}" ]; then TOKENS="env:GH_TOKEN"; fi
  TOKEN_ENV="$(runvar GH_TOKEN_ENV)"
  if [ -n "$TOKEN_ENV" ] && [ -n "${!TOKEN_ENV:-}" ]; then TOKENS="$TOKENS $TOKEN_ENV"; fi
  for v in $(compgen -e | grep '^GH_TOKEN_' || true); do
    case " $TOKENS " in *" $v "*) ;; *) TOKENS="$TOKENS $v" ;; esac
  done
  GH_USER=""
  GH_USED=""
  for t in $TOKENS; do
    if [ "$t" = "env:GH_TOKEN" ]; then
      token="$GH_TOKEN"
    else
      token="${!t:-}"
    fi
    [ -n "$token" ] || continue
    user="$(GH_TOKEN="$token" timeout 25 gh api user -q .login 2>&1)"
    if [ "$?" -eq 0 ] && [ -n "$user" ] && ! printf '%s' "$user" | grep -qi 'requires authentication\|bad credentials\|error'; then
      GH_USER="$user"
      GH_USED="$t"
      break
    fi
  done
  if [ -n "$GH_USER" ]; then
    verdict github-api PASS "authenticated as $GH_USER (via $GH_USED)"
  elif [ -z "$TOKENS" ]; then
    verdict github-api FAIL "no GitHub token in the environment (GH_TOKEN/GH_TOKEN_<account>)" \
      "ensure cage() exports GH_TOKEN_<account> for this org (secrets/org-config.json poll.github.account)"
  else
    verdict github-api FAIL "none of the available tokens authenticates:$(printf '%s' "$TOKENS")" \
      "mint a fresh token (gh auth login -h github.com -p https -w) and export it as the run's GH_TOKEN_<account>"
  fi
fi

# ── 5. browser GitHub login state over the run chrome CDP port ────────────
CDP_PORT="$(runvar CHROME_CDP_PORT)"
if [ -z "$CDP_PORT" ] || [ "$CDP_PORT" = "0" ]; then
  verdict browser-github SKIP "no CHROME_CDP_PORT recorded for this run (Chrome not launched)"
elif ! curl -s --max-time 2 "http://127.0.0.1:$CDP_PORT/json/version" 2>/dev/null | grep -q '"Browser"'; then
  verdict browser-github SKIP "run Chrome is down on CDP $CDP_PORT — start it with scripts/chrome.sh revive"
else
  CHROME_SESSION="$(runvar CHROME_SESSION)"
  CHROME_SESSION="${CHROME_SESSION:-chrome-$(runvar TICKET_ID)}"
  CHROME_XDG="$(runvar CHROME_XDG_DATA_HOME)"
  CHROME_XDG="${CHROME_XDG:-/tmp/xdg-preflight}"
  mkdir -p "$CHROME_XDG" 2>/dev/null || true
  # Probe from a THROWAWAY session so the run's own daemon is never touched (the CLI
  # binary can differ between the run script's PATH and a login shell's PATH, and a
  # mismatched binary replaces the session's daemon). The probe only READS cookies —
  # it never navigates — and its daemon is killed immediately: killing an ATTACHED
  # daemon never stops the CDP Chrome (only a daemon-owned Chrome dies).
  PROBE_SESSION="chrome-preflight-$(runvar TICKET_ID)"
  COOKIES="$(XDG_DATA_HOME="$CHROME_XDG" agent-browser --session "$PROBE_SESSION" \
    --cdp "http://127.0.0.1:$CDP_PORT" cookies get --url https://github.com 2>/dev/null)"
  pidf="/run/user/1000/agent-browser/$PROBE_SESSION.pid"
  [ -f "$pidf" ] && kill -9 "$(cat "$pidf")" 2>/dev/null
  rm -f "/run/user/1000/agent-browser/$PROBE_SESSION."* 2>/dev/null || true
  BUSER="$(printf '%s\n' "$COOKIES" | sed -n 's/^dotcom_user=//p' | head -1)"
  if printf '%s\n' "$COOKIES" | grep -q '^logged_in=yes$' && [ -n "$BUSER" ]; then
    verdict browser-github PASS "signed in as $BUSER (CDP $CDP_PORT)"
  else
    verdict browser-github FAIL "the run Chrome is NOT signed in to GitHub (CDP $CDP_PORT)" \
      "sign in to github.com manually in the run Chrome window, then re-run scripts/preflight.sh"
  fi
fi

# ── 6. local dashboard login capability (JWT_SECRET) ──────────────────────
# Only a repo whose source actually mints/verifies JWTs is checked, so unrelated
# projects are not blocked by an auth mechanism they do not use.
USES_JWT=""
for d in backend dashboard frontend api server; do
  [ -d "$REPO/$d" ] || continue
  if grep -rqs --exclude-dir=node_modules --exclude-dir=.next --exclude-dir=dist --exclude-dir=coverage \
    --include='*.ts' --include='*.tsx' --include='*.js' --include='*.mjs' --include='*.py' --include='*.go' \
    -- "JWT_SECRET" "$REPO/$d" 2>/dev/null; then
    USES_JWT=1
    break
  fi
done
if [ -z "$USES_JWT" ]; then
  verdict dashboard-login SKIP "no JWT_SECRET in this repo's source (no local JWT login to verify)"
elif [ -n "$JWT_FILE" ] && [ -n "$(key_value "$JWT_FILE" JWT_SECRET)" ]; then
  verdict dashboard-login PASS "JWT_SECRET set in $JWT_FILE"
elif [ -n "$JWT_FILE" ]; then
  verdict dashboard-login FAIL "JWT_SECRET is empty in $JWT_FILE" \
    "set JWT_SECRET=$(openssl rand -hex 16 2>/dev/null || echo any-value-for-local-development) in $JWT_FILE"
else
  verdict dashboard-login FAIL "the source requires JWT_SECRET but no backend/.env[.local] (or .env[.local]) defines it" \
    "add JWT_SECRET=any-value-for-local-development to $REPO/backend/.env (see dashboard/README.md)"
fi

# ── summary ───────────────────────────────────────────────────────────────
if [ "$FAILS" -gt 0 ]; then
  printf 'PREFLIGHT_STATUS="failed"\nPREFLIGHT_FAIL_COUNT="%s"\n' "$FAILS" >>"$OUT"
  printf '\npreflight: %s passed, %s failed, %s skipped — fix each FAIL above, then re-run: bash %s\n' \
    "$PASSES" "$FAILS" "$SKIPS" "$0"
  exit 1
fi
printf 'PREFLIGHT_STATUS="ok"\nPREFLIGHT_FAIL_COUNT="0"\n' >>"$OUT"
printf '\npreflight: %s passed, 0 failed, %s skipped — OK\n' "$PASSES" "$SKIPS"
exit 0
