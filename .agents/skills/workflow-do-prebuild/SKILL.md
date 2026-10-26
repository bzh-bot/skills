---
name: workflow-do-prebuild
version: 1.5.1
description: "workflow-do sub-skill — phases P0–P3 (Access & Browser, Project Detection + Ticket Resolution, Groom/Grill, Workspace Setup + Draft PR). Loaded by a workflow-do worker session the script launches as a named zellij pane (pi --name), coordinated via pi-intercom. Not invoked directly."
---

# Pre-build agent — workflow-do-prebuild (Phases P0–P3)

> **`workflow-do` worker sub-skill.** You are a full pi session launched by the
`workflow-do` script as a **named zellij pane** (`pi --name workflow-prebuild-...`),
NOT a subagent tool call. Your launch prompt tells you which phase(s) to run
and inlines the handoff. Load this skill by reading its SKILL.md first.

**Your session name is in your launch prompt** (e.g. `workflow-p0-<TICKET>`).
Every report/question goes to the **chief-of-staff session** — the session that launched this
cage. Your task file prints its intercom target (`ORCHESTRATOR_SESSION` in the run env,
supplied by the chief of staff at kickoff). Pass `--name` once; the name persists.

## Handoff contract

> **v7 script model:** the sequencer is the deterministic script
> `~/.agents/skills/workflow-do/workflow-do.ts`. Your OUT vars are appended to
> `/tmp/workflow-run.env` (append-only) plus a `STAGE_DONE` block; your pane is
> launched and closed by the script. Read `~/.agents/skills/workflow-do/SHARED-POLICY.md`
> -> "Stage Orchestration (script model, v7)" for the full contract, and your stage
> prompt file (`~/.agents/skills/workflow-do/prompts/`) for the exact surrender steps.

You are **autonomous** — P0, P1, P2 and P3 all run without asking. Answer every grill question the codebase, ticket or conventions can answer, and record each answer as an assumption in the brief. **workflow-do never creates tickets:** the run always works on an EXISTING tracker ticket, so there is no ticket-creation ask anywhere.

**IN — variables in your `task` prompt:**
- `$ARGUMENTS` — either a **ticket reference** (URL/ID/key) or a **free-form idea**
- pointer to `$ORG_CONFIG_DIR/org-config.json` (org mapping, tracker credentials, ticket ID formats, status flows)
- cage/host env vars already set by the `cage` function: `WORKFLOW_CONTAINER_ID`, `WORKFLOW_CWD`, `GH_TOKEN_<account>` for each GitHub account

**OUT — your final message (handoff back to the chief-of-staff session):**
- `TICKET_ID`, `TICKET_URL`, `TICKET_TITLE`, `FEATURE_TAG`
- `ORG`, `REPO_NAME`, `REPO_ROOT`, `SOURCE_REPO`, `INTEGRATION_BRANCH`, `PKG_MGR`
- `BRANCH_NAME`, `WORKTREE`, `PR_NUMBER`, `PR_URL` (draft PR created, PR link on ticket)
- `WORKFLOW_CONTAINER_ID`, `WORKFLOW_CWD`, `WORKFLOW_TAB_ID`, `WORKFLOW_VIEWPORT_W`, `WORKFLOW_VIEWPORT_H`
- `SCREENSHOTS_DIR`, `DB_URL`, running dev-server state (frontend/backend/DB panes + ports)
- detected flags: `HAS_FRONTEND`, `FRONTEND_DIR`, `BACKEND_DIR`, `IS_MONOREPO`, `HAS_VERCEL`, `HAS_GH_ACTIONS`, `HAS_CIRCLECI`, `HAS_JENKINS`, `HAS_SUPABASE`, `HAS_DATADOG`
- the **5-element brief** (goal, constraints, done-criteria, non-goals, context pointers) + the acceptance criteria list

## Operating rules

- **Read the shared policy first:** `~/.agents/skills/workflow-do/SHARED-POLICY.md` (see its FIRST ACTION note). Do this before any phase task.
- Run phases P0 → P1 → P2 → P3 in order, every substep (P1.1/P1.4/P1.5/P1.7 are script-detected — pre-filled in the run env, see their sections).
- **Task tracking:** call `TaskList`, then `TaskCreate` for only your phases' substeps (`P0.*`, `P1.*`, `P2.*`, `P3.*`); mark `in_progress`/`completed` as you go. Do not create tasks for other groups' phases. Prefix every sub-step `TaskCreate` subject with the phase emoji (🔐 P0, 🔍 P1, ❓ P2, 📦 P3, 💻 P4, 🧪 P5, 📸 P6, 🖥️ P7, 🚀 P8, ⏳ P9, ✅ P10, 📡 P11, 🔄 P12, 📧 P13) — emojis no longer go in zellij tab names; they live on the pi-task subjects.
- Rename your zellij tab at each transition: `workflow_rename_tab "${TICKET_ID}: P<n>.<sub> <Verb> ${FEATURE_TAG}"` (define `workflow_rename_tab` from the Pane Management Convention in SHARED-POLICY.md before first use — pane launch/close is script-owned, you never open or close panes).
- Pane lifecycle is **script-owned**: you never launch or close panes; the script launches your stage pane and the Chrome pane and closes them after verification.
- **Access verification (P0) is YOUR job** — you are the group that runs it. The Hard Prerequisites below are the checks you perform in P0, not pre-satisfied assumptions.
- Human decision boundary: **none** in the normal path. The grill questions and the P2.4b brief are derived from the codebase and recorded as assumptions (see P2.3). The only stop condition is a missing tracker ticket — see P1.10.
- When all of P0–P3 are done, return your **OUT** handoff summary as your final message. Do NOT start Phase 4 — the script spawns `workflow-do-build` next.

## Shared policy

**FIRST ACTION before any phase work:** read
`~/.agents/skills/workflow-do/SHARED-POLICY.md` and follow it for the entire run
(Hard Prerequisites, DB-First Thinking Order, implementation style pointers,
Zellij tab naming, pane management). It applies to every workflow-do worker —
this file no longer duplicates it.
## Your phases

## Phase 0 — Access & Browser Verification

**→ Print: "Phase 0: Verifying access and starting browser..."**

```bash
workflow_rename_tab "${TICKET_ID}: P0.1 Access ${FEATURE_TAG}"
```

**→ TaskUpdate: Phase 0 → in_progress**

This phase reads the system prompt, updates pi, opens the browser **first**, and verifies the environment access paths the run depends on — zellij, git signing, the browser, and the agent-browser connection. GitHub login and API access are verified in Phase 1.3 after project detection, because they depend on knowing which org/account is being used. If any check fails, **stop immediately** and tell the user what to fix. Do not proceed to Phase 1 until all environment access is confirmed.

### 0.1 Read APPEND_SYSTEM.md (System Prompt)

**→ TaskUpdate: P0.1 → in_progress**

This is the very first thing the skill does. Read `~/.pi/agent/APPEND_SYSTEM.md` if it exists — this file contains global agent instructions that apply to all skills and must be loaded into context before any other check:

```bash
[ -f ~/.pi/agent/APPEND_SYSTEM.md ] && cat ~/.pi/agent/APPEND_SYSTEM.md
```

If the file exists, read it and follow any instructions it contains throughout the entire run. If it does not exist, proceed normally.

**→ TaskUpdate: P0.1 → completed**


### 0.2 Update pi + Extensions

**→ TaskUpdate: P0.2 → in_progress**

```bash
workflow_rename_tab "${TICKET_ID}: P0.2 Access ${FEATURE_TAG}"
```

Ensure pi and its extensions are up to date before starting work. Running an outdated pi or stale extensions can cause subtle failures (missing tool support, changed CLI flags, broken MCP servers) that are hard to trace mid-run.

```bash
# Update pi itself, then update extensions
pi update && pi update --extensions
```

If either command fails or reports errors, warn the user but do not abort — the updates are best-effort. If pi itself was updated, the user may need to restart the session for the new version to take effect; note this in the output.

**→ TaskUpdate: P0.2 → completed**


### 0.3 Verify Zellij Session

**→ TaskUpdate: P0.3 → in_progress**

```bash
workflow_rename_tab "${TICKET_ID}: P0.3 Access ${FEATURE_TAG}"
```

```bash
if [ -z "$ZELLIJ" ] && [ -z "$ZELLIJ_SESSION_NAME" ]; then
  echo "FATAL: workflow-do requires zellij. Start a zellij session first: zellij"
  exit 1
fi
echo "✅ Zellij session active"
```

If not in zellij, **FAIL LOUDLY and do not proceed.** Do not fall back to background processes. The skill relies on zellij panes for the development workflow.

Define the `workflow_rename_tab` helper now (see **Pane Management Convention** in SHARED-POLICY.md for the function body) — it is needed before the first tab rename. Pane launch/close is script-owned: you never open or close panes.

**→ TaskUpdate: P0.3 → completed**


### 0.4 Verify Git Signing

**→ TaskUpdate: P0.4 → in_progress**

```bash
workflow_rename_tab "${TICKET_ID}: P0.4 Access ${FEATURE_TAG}"
```

Check `workflowDo.signCommits` for your detected org in `$ORG_CONFIG_DIR/org-config.json` (under `orgs[] → workflowDo`). Not all orgs require signed commits — only configure signing when the org requires it.

**If signing is NOT required for this org:** skip this step, print `✅ Git signing not required for this org`, mark P0.4 completed, and proceed.

**If signing IS required:**

```bash
# 1. Ensure SSH signing is configured (set defaults if not already set)
SIGN_Fthe business orgT=$(git -C "$REPO_ROOT" config --get gpg.format 2>/dev/null)
if [ "$SIGN_Fthe business orgT" != "ssh" ]; then
  git config --global gpg.format ssh
  echo "Configured gpg.format = ssh"
fi

# 2. Set the signing key (remap host paths to container paths)
SIGNING_KEY=$(git -C "$REPO_ROOT" config --get user.signingkey 2>/dev/null)
case "$SIGNING_KEY" in
  /Users/*|/home/*)
    KEY_BASENAME=$(basename "$SIGNING_KEY")
    CONTAINER_KEY="$HOME/.ssh/$KEY_BASENAME"
    if [ -f "$CONTAINER_KEY" ]; then
      git config --global user.signingkey "$CONTAINER_KEY"
      git config --global gpg.ssh.program ssh-keygen
      echo "Remapped signing key to container path: $CONTAINER_KEY"
    fi
    ;;
  *)
    # Not set or already a relative path — default to the standard key
    if [ -z "$SIGNING_KEY" ] && [ -f "$HOME/.ssh/id_ed25519.pub" ]; then
      git config --global user.signingkey "$HOME/.ssh/id_ed25519.pub"
      git config --global gpg.ssh.program ssh-keygen
      echo "Set signing key to ~/.ssh/id_ed25519.pub"
    fi
    ;;
esac

# 3. Enable auto-signing for all commits and tags
git config --global commit.gpgsign true
git config --global tag.gpgsign true

# 4. Verify signing works
git -C "$REPO_ROOT" commit --allow-empty -S -m "test signing" --dry-run 2>/dev/null || {
  echo "FATAL: Git commit signing is required but not working."
  echo ""
  echo "Setup instructions (SSH signing):"
  echo "  1. Configure Git:"
  echo "     git config --global gpg.format ssh"
  echo "     git config --global user.signingkey ~/.ssh/id_ed25519.pub"
  echo "     git config --global commit.gpgsign true"
  echo "  2. Register SSH key as a SIGNING key on GitHub:"
  echo "     https://github.com/settings/ssh/signing_keys"
  echo "     (This is different from regular SSH keys — signing keys have their own page)"
  echo "  3. Verify: git commit --allow-empty -m 'test' && git verify-commit HEAD"
  echo ""
  echo "See the commitSigning.setup array in $ORG_CONFIG_DIR/org-config.json for full instructions."
  exit 1
}
echo "✅ Git signing verified (SSH)"
```

**Key points:**

- **SSH signing only** (not GPG) — `gpg.format ssh` with `~/.ssh/id_ed25519.pub`
- **GitHub registration required:** The SSH key must be registered as a **signing key** at `github.com/settings/ssh/signing_keys` (not just an auth key). Without this, commits show as signed but NOT verified on GitHub.
- **Container path remap:** The host may set `user.signingkey` to a host path (e.g. `/Users/...`); remap to `~/.ssh/<basename>` inside the container. The `~/.ssh` directory is mounted read-only.
- **`gpg.ssh.program`** must be set to `ssh-keygen` (installed via `openssh-client` in the cage image).
- Full setup steps are in the `commitSigning.setup` array in `$ORG_CONFIG_DIR/org-config.json`.

**→ TaskUpdate: P0.4 → completed**


### 0.5 Chrome — Attach to the Script-Owned Chrome Pane (Never Launch)

**→ TaskUpdate: P0.5 → in_progress**

```bash
workflow_rename_tab "${TICKET_ID}: P0.5 Access ${FEATURE_TAG}"
```

**The script owns Chrome launch.** Before this stage started, the workflow-do
script launched the run Chrome on a **FIXED CDP port** with the **org's**
user-data-dir (mounted into the container; resolved from the registry
`chrome_user_data_dir` by the cage's `WORKFLOW_ORG` hook). `CHROME_LAUNCHED="1"`,
`CHROME_CDP_PORT` and `CHROME_SESSION_PROFILE` in `/tmp/workflow-run.env` are the
proof. **You never launch Chrome yourself** — no `google-chrome` commands, no
`--headed`/`--profile` launch flags, never `--remote-debugging-port=0`. You
ATTACH (and if it is genuinely dead, `bash ~/.agents/skills/workflow-do/scripts/chrome.sh
status` then `... chrome.sh revive` — idempotent, same profile, same recorded port):

```bash
# The daemon reuses the live Chrome the script started — never a second instance.
# The ticket tab is opened FIRST and stays open for the whole run (SHARED-POLICY
# "Persistent Ticket + PR Tabs") — ensure_tab keeps it a single, labeled tab.
ensure_tab ticket "${TICKET_URL:-about:blank}"
```

- Open the ticket URL once known (Phase 1.2) the same way — `agent-browser
  open` adds a tab to the running instance.
- If Chrome died mid-run and no window is live, do NOT relaunch it by hand:
  `bash ~/.agents/skills/workflow-do/scripts/chrome.sh status` (is it really down? on
  which port?) then `... chrome.sh revive` (idempotent: one relaunch on the SAME
  profile, on the SAME recorded `CHROME_CDP_PORT`). Then attach again with
  `agent-browser --headed --profile "$CHROME_SESSION_PROFILE" --session "$CHROME_SESSION" --pin-tab --cdp "http://127.0.0.1:$CHROME_CDP_PORT" open <url>`.
  The script also probes + revives once before every browser-using stage.
- The org user-data-dir is persistent (under `$ORG_CONFIG_DIR/<org>/` on the host),
  so logins survive across runs just like the old shared profile did — but
  now isolated per org.

**⚠️ NEVER use headless browser. Chrome must ALWAYS be headed (visible on screen).** Never pass `--headless` to Chrome or `agent-browser`. If Chrome is not visible on screen, something is wrong — do not fall back to headless.

**→ TaskUpdate: P0.5 → completed**

### 0.6 Verify agent-browser Works

**→ TaskUpdate: P0.6 → in_progress**

```bash
workflow_rename_tab "${TICKET_ID}: P0.6 Access ${FEATURE_TAG}"
```

agent-browser launched Chrome in Phase 0.5 (via the script's Chrome pane), so
its daemon owns the connection —
there is no separate CDP wiring to verify. This step catches two failure modes
**before** they surface mid-run: agent-browser missing/silently no-opping, and
Chrome being unreachable for screenshots later.

```bash
# ── Ensure agent-browser is actually installed ──
# A missing binary makes agent-browser silently no-op (empty stdout, exit 0),
# so later checks pass vacuously and breakage only surfaces mid-run (Phase 6
# screenshots). The cage-base image bakes agent-browser into /opt/agent-browser;
# this guard is a fallback for older images / host mode.
if ! agent-browser --version >/dev/null 2>&1 || [ -z "$(agent-browser --version 2>/dev/null)" ]; then
  echo "⚠  agent-browser not installed. Installing via npx cache + wrapper..."
  npx --yes agent-browser --version >/dev/null 2>&1   # populate the npx cache
  AB_JS=$(ls "$HOME"/.npm/_npx/*/node_modules/agent-browser/bin/agent-browser.js 2>/dev/null | head -1)
  if [ -z "$AB_JS" ]; then
    echo "FATAL: could not locate agent-browser in npx cache. Run: npm i -g agent-browser (on a writable npm prefix)."
    exit 1
  fi
  mkdir -p "$HOME/.bin"
  cat > "$HOME/.bin/agent-browser" <<EOF
#!/bin/bash
exec node "$AB_JS" "\$@"
EOF
  chmod +x "$HOME/.bin/agent-browser"
  export PATH="$HOME/.bin:$PATH"
  echo "✅ agent-browser installed at ~/.bin/agent-browser (npx-cached)"
fi

# ── Sanity checks: navigation + screenshot capability (attach, never launch) ──
agent-browser --headed --profile "$CHROME_SESSION_PROFILE" --session "$CHROME_SESSION" --pin-tab --cdp "http://127.0.0.1:$CHROME_CDP_PORT" open https://example.com 2>/dev/null
TEST_URL=$(agent-browser --headed --session "$CHROME_SESSION" --pin-tab --cdp "http://127.0.0.1:$CHROME_CDP_PORT" get url 2>/dev/null | tail -1)
if echo "$TEST_URL" | grep -q "example.com"; then
  echo "✅ agent-browser navigation verified"
else
  echo "FATAL: agent-browser connected but navigation failed. URL was: $TEST_URL"
  echo "  Chrome may have crashed or the daemon is stale. Ask the chief of staff to relaunch the script's Chrome pane, then retry attachment."
  exit 1
fi

agent-browser screenshot /tmp/.ab-connection-test.png 2>/dev/null
if [ -f /tmp/.ab-connection-test.png ]; then
  echo "✅ agent-browser screenshot capability verified"
  rm -f /tmp/.ab-connection-test.png
else
  echo "FATAL: agent-browser cannot take screenshots — Phase 7 will fail. Aborting."
  exit 1
fi

# ── Stale-daemon note ──
# If agent-browser is installed yet fails BOTH checks while Chrome itself runs
# (`pgrep -f google-chrome` shows it), the daemon is likely stale (version
# mismatch — observed in a ticket). Fix: `agent-browser upgrade` (or install the
# latest into a writable prefix and shadow the old binary in ~/.bin), then retry.

```

All later phases call agent-browser directly (no connection variable needed —
the daemon persists between calls). Attach with `agent-browser --headed --profile "$CHROME_SESSION_PROFILE" --session "$CHROME_SESSION" --pin-tab --cdp "http://127.0.0.1:$CHROME_CDP_PORT" open
<url>` — Chrome is the script-owned pane instance (org user-data-dir,
`CHROME_LAUNCHED="1"` in the run env); never pass `--headed --profile` launch
flags from stage panes, and never launch Chrome yourself.

**⚠️ Never overwrite `/tmp/workflow_env.sh` (or any scratch env file) partially — append only.** Re-establishing anything after a Chrome restart must NOT overwrite the scratch env file with only the browser vars — that silently drops `$PR_NUMBER`/`$WORKTREE`/`$BRANCH_NAME`, and a later `gh pr edit`/`gh pr merge` then runs with `PR_NUMBER=""` and (from the wrong cwd) clobbers an unrelated **merged** PR's body (this happened in a past ticket). If you must rebuild the file, re-derive every variable from git/`gh` first, or write to a separate file. Use `>>`, never `>` on an existing shared env file.

## Phase 1 — Project Detection + Ticket Resolution

Before any work, detect the project context and check for existing work that might be resumed.

**→ Print: "Phase 1: Detecting project context..."**

```bash
workflow_rename_tab "${TICKET_ID}: P1.1 Detect ${FEATURE_TAG}"
```

**→ TaskUpdate: Phase 1 → in_progress**

### 1.1 Repository & Org — SCRIPT-DETECTED

**→ TaskUpdate: P1.1 → completed (pre-filled by the script)**

`REPO_ROOT`, `REPO_NAME`, `ORG`, and `GITHUB_ORG` are already in `/tmp/workflow-run.env` — the script ran repo/org detection (`detectContext`) before launching this stage. **Read them from the run env; do NOT re-derive.** If a detected value disagrees with reality (e.g. a renamed remote), derive the correct value once, append it to the run env, and record a loose end — never silently re-derive in later steps.

### 1.2 Issue Tracker

**→ TaskUpdate: P1.2 → in_progress**

Read your detected org's `workflowDo` block in `$ORG_CONFIG_DIR/org-config.json` for the tracker type, credentials path, database IDs/env files, **ticket ID prefix** (`workflowDo.ticketIdPrefix`), status flow (`workflowDo.statusFlow`), and assignee method. The ticket ID prefix is needed in Phase 1.2 when the tracker doesn't auto-assign IDs (e.g. Notion).

**Read the tracker's skill file before making any API calls.** The skill contains auth setup, API patterns, and field schema discovery instructions.

**A tracker migration is a registry fact, not a memory.** If an org has moved from one
tracker to another, only the registry knows; read the org's `reader_skill` and use that
tool end to end — never mix two trackers in one run, and never fall back to a retired
integration. Read the `clickup` skill (`~/.agents/skills/clickup/SKILL.md`) before the
first call when that is the tracker. Four facts shape every later step:

- **The CLI is the only entry point.** `~/.agents/skills/clickup/scripts/clickup`; the personal token is read automatically from `$ORG_CONFIG_DIR/<org>/env/clickup.env` (mounted read-only into the cage), so there is no OAuth/MCP setup to do.
- **The ticket id lives in the task NAME.** The `<KEY>-####` prefix (e.g. `<KEY-212>` in `<KEY-212> — Intervals filter…`) is the ticket id used in branches/PR titles; the ClickUp task id (e.g. `868mh7m2g`) is only the URL/API handle. Task URL: `https://app.clickup.com/t/<task-id>`.
- **Statuses are LIST-scoped and the Sprint lists roll** (a fresh list roughly every two weeks), so **never hardcode a status name — read the live ones first** with `clickup list <list_id>` (list ids come from `clickup hierarchy`; use the current sprint list id). That list offers `backlog`, `cleaned backlog`, `ready to work`, `working`, `blocked`, `testing / in review`, `validation / merged`, `shipped`, `cancelled` — a snapshot, not the contract. Map each semantic step through the org's `workflowDo.statusFlow`/`statusFlowNote` in `$ORG_CONFIG_DIR/org-config.json` onto a live name, then `clickup update <task-id> --status "<exact live name>"`. **A name the list rejects silently no-ops**, so verify every status write with `clickup get <task-id>`.
- **Assignee writes replace, and there is no remote-link API.** `clickup update <task-id> --assignee me` REPLACES the assignee set (pass the full list when there is more than one). The PR/review link goes on the ticket as a **bare-URL comment** — `clickup comment <task-id> <url>`, a plain URL, never a labelled markdown link.

**→ TaskUpdate: P1.2 → completed**

### 1.3 GitHub Credentials + Login Verification

**→ TaskUpdate: P1.3 → in_progress**

Now that the org is detected (Phase 1.1), verify GitHub access for the **correct account** — both the API token and the browser login session. Different orgs use different GitHub accounts, so this must happen after org detection, not before.

#### 1.3a Select org-specific GH_TOKEN and verify API access

**→ Remember: Update task P1.3 in TaskList as you work through this substep.**

**The `cage` function passes all gh tokens as env vars** (`GH_TOKEN_<account>` for each account). The container's keyring is inaccessible, so tokens are fetched from the host and passed via `--env-file`. Set the active `GH_TOKEN` from the detected org's account:

```bash
# _cage_detect_org returned $gh_account (org account alias)
# Pick the right token from the env vars passed by cage
export GH_TOKEN="${GH_TOKEN_${gh_account}}"

# Verify the token works against the GitHub API
GH_TEST_USER=$(gh api user --jq .login 2>/dev/null)
if [ -z "$GH_TEST_USER" ]; then
  echo "FATAL: GH_TOKEN for account '$gh_account' does not authenticate against the GitHub API."
  echo "  Token may be expired or missing. On the host, run: gh auth login --user $gh_account"
  exit 1
fi
echo "✅ GitHub API access verified (account: $gh_account, user: $GH_TEST_USER)"

# Verify the token can access this specific repo
gh repo view "$(git -C "$REPO_ROOT" remote get-url origin | sed 's|.*github.com[:/]||;s|\.git$||')" --json name -q .name 2>/dev/null || {
  echo "FATAL: GH_TOKEN for '$gh_account' cannot access this repository. Check that the account has access."
  exit 1
}
```

If `gh` fails, check that `$GH_TOKEN` is set (`echo $GH_TOKEN | head -c 10`). If empty, the token for this account wasn't available on the host — run `gh auth token --user $gh_account` on the host to verify it works.

**If the token authenticates but is EXPIRED/invalid** (a real 2026-09-06 run lost ~20 min because every later stage rediscovered `Failed to log in to github.com ... token is invalid`): do NOT just warn and continue. Fix it once, here, and record the outcome so downstream stages never re-derive it. Try in order:

1. `GH_TOKEN="$(git -C "$REPO_ROOT" remote get-url origin | sed -n 's|.*x-access-token:\([^@]*\)@.*|\1|p')"` — many checkouts carry a valid x-access-token in the origin URL; verify with `gh api user --jq .login`.
2. Mint a fresh token via `gh auth login` device flow (headless-safe: `gh auth login -h github.com -p https -w` prints a code — complete it in the cage Chrome, which is already logged in to GitHub).
3. If neither works, fall back to **browser-only verification** for the rest of the run (agent-browser for PR/CI checks, merge via the web UI) — but say so explicitly in the handoff.

Whichever fallback wins, append `GH_AUTH_FALLBACK="browser|remote-token|device-flow"` to `/tmp/workflow-run.env`, and note that iterate-mode rehydration (hydrate stage) runs this same check — resuming a run skips P0, so 1.3a is often the FIRST thing to catch an expired token. Do not skip it on resume.

#### 1.3b Verify GitHub login in browser

**→ Remember: Update task P1.3 in TaskList as you work through this substep.**

Screenshot uploads to GitHub PRs require a logged-in browser session — and it must be the **correct GitHub account** for this org. Chrome was started in Phase 0.5 and the agent-browser connection was verified in Phase 0.6. The Chrome profile is persistent (`/chrome-profile`), so on most runs the user is already logged in to GitHub (and Google/Microsoft) from a previous session — the check below will detect this and proceed immediately.

**No credentials are stored in the skill or env files.** Login sessions live entirely in the persistent Chrome profile. On the first run (or if the profile is ever wiped), the user must log in manually in the Chrome window. See the **Browser Login Handling** policy in Hard Prerequisites — GitHub is an external service, so always wait for the user to log in manually.

```bash
# REAL login check — never grep for "dashboard". The logged-out redirect is
# https://github.com/login?return_to=...dashboard , so a dashboard grep matches BOTH
# states and lets an anonymous browser through (a false positive was seen:
# the run proceeded with no GitHub session and only failed later at screenshot upload).
# Assert the RESOLVED URL of an authenticated-only page instead.
check_gh_login() {
  agent-browser --headed --profile "$CHROME_SESSION_PROFILE" --session "$CHROME_SESSION" --pin-tab --cdp "http://127.0.0.1:$CHROME_CDP_PORT" \
    open https://github.com/settings/profile >/dev/null 2>&1
  sleep 3
  local url; url=$(agent-browser --headed --session "$CHROME_SESSION" --cdp "http://127.0.0.1:$CHROME_CDP_PORT" get url 2>/dev/null | tail -1)
  echo "GH check: settings/profile -> $url"
  case "$url" in
    *"/login"*|*"/session"*|*"/signup"*) echo "❌ GitHub NOT logged in (redirected to $url)"; return 1 ;;
    *"/settings/profile"*|*"github.com/settings"*) echo "✅ GitHub logged in: $url"; return 0 ;;
    *) echo "⚠️  GitHub login state UNCLEAR (resolved $url) — treat as NOT logged in"; return 1 ;;
  esac
}

if ! check_gh_login; then
  # Not logged in — open the login page and wait for the user to complete it manually
  echo "⚠️  GitHub login required. Please log in manually in the Chrome window."
  echo "    The persistent Chrome profile will remember this session for future runs."
  echo "    If you see 'This browser or app may not be secure' (Google blocking OAuth),"
  echo "    run this on the HOST first: google-chrome --user-data-dir=~/.cage-chrome-profile"
  echo "    Log in there, close it, then retry here."
  agent-browser --headed --profile "$CHROME_SESSION_PROFILE" --session "$CHROME_SESSION" --pin-tab --cdp "http://127.0.0.1:$CHROME_CDP_PORT" open https://github.com/login
  sleep 2

  # Poll until the authenticated page really resolves (user completes login in Chrome)
  echo "⏳ Waiting for GitHub login (complete it in the Chrome window)..."
  for i in $(seq 1 120); do
    sleep 5
    if check_gh_login; then echo "✅ GitHub login verified"; break; fi
    [ "$i" = "120" ] && { echo "❌ GitHub login timed out after 10 minutes — aborting"; exit 1; }
    echo "  Still waiting... (attempt $i/120)"
  done
fi
```

**Also print the verdict into the run env** so a missing session is loud and auditable
instead of silent: append `GH_BROWSER_LOGIN="ok"` (or `"missing"` when the poll is still
failing and the stage aborts) together with the resolved URL. A `missing` value is the
early warning for the attach-only phantom incidents: an anonymous browser is almost always a
Chrome that was relaunched on a different profile, not a genuinely expired session.

**→ TaskUpdate: P1.3 → completed**

### 1.4 Branching Model — SCRIPT-DETECTED

**→ TaskUpdate: P1.4 → completed (pre-filled by the script)**

`INTEGRATION_BRANCH` is already in the run env (script: prefer `develop`, else remote HEAD). The **production branch** (usually `main`/`master`) still needs noting for ship/post phases — record it as a comment in your OUT handoff if it differs from `INTEGRATION_BRANCH`.

### 1.5 Project Stack Detection — SCRIPT-DETECTED

**→ TaskUpdate: P1.5 → completed (pre-filled by the script)**

`PKG_MGR`, `HAS_FRONTEND`, `FRONTEND_DIR`, `BACKEND_DIR`, `IS_MONOREPO` are already in the run env, and `PROJECT_PROFILE_FILE` points at the detected profile (including the package.json scripts dump). **Read them; do NOT re-derive.**

⚠️ If `PKG_MGR` is empty in the run env (non-standard layout), derive it once from the lockfile, append it, and record a loose end. **If the project has pnpm-lock.yaml, ALWAYS use pnpm — NEVER npm** (a conflicting package-lock.json breaks the lockfile). All commands use `$PKG_MGR`: install, run, test, lint, typecheck, dev.

### 1.6 Discover Project Commands

**→ TaskUpdate: P1.6 → in_progress**

Read `AGENTS.md`, `CLAUDE.md`, `README.md`, `CONTRIBUTING.md`, and `package.json` scripts in all workspaces (root, frontend, backend) to discover the command set. The **package.json scripts are already dumped in `PROJECT_PROFILE_FILE`** (script-detected) — read the profile first, then fill gaps from AGENTS.md/README:

- **Dev server command** (frontend): e.g. `pnpm run dev`
- **Dev server command** (backend): e.g. `pnpm run dev` or `pnpm run start:dev`
- **Database start command**: e.g. `pnpm run docker:deps` or `docker compose up -d`
- **Database reset command**: e.g. `pnpm run db:migrate:reset:local`
- **Database migration command**: e.g. `pnpm run db:migrate:deploy:local`
- **Database hydration/seed command**: e.g. `pnpm run hydrate:local`
- **Test command**: e.g. `pnpm test`
- **Lint command**: e.g. `pnpm run lint`
- **Typecheck command**: e.g. `pnpm run typecheck` or `npx tsc --noEmit`

**Do not assume commands — read the scripts objects.** Each project is different.

**→ TaskUpdate: P1.6 → completed**

### 1.7 Detect Deployment & Monitoring Stack — SCRIPT-DETECTED

**→ TaskUpdate: P1.7 → completed (pre-filled by the script)**

`HAS_VERCEL`, `HAS_GH_ACTIONS`, `HAS_CIRCLECI`, `HAS_JENKINS`, `HAS_SUPABASE`, `HAS_DATADOG` are already in the run env (script probed `vercel.json`/`.vercel`, `.github/workflows`, `.circleci`, `Jenkinsfile`, `supabase/`, and package.json for dd-trace/datadog). The post-merge stage (P11.1) reads these — include them in your OUT handoff (they are already verified by the script).

### 1.8 Check for Existing Wiki/Documentation

**→ TaskUpdate: P1.8 → in_progress**

Look for existing documentation that provides context:

- Check for existing documentation that provides context. See the `wiki` block in `$ORG_CONFIG_DIR/org-config.json` for org-specific wiki sources (e.g. Confluence, Notion). Also check:
- `docs/` directory in the repo
- Check for ADRs in `docs/adr/` or `adr/`
- Check `CHANGELOG.md` existence (will need updating later)
- Check for OpenAPI/Swagger specs (`openapi.yaml`, `swagger.json`, `docs/api/`)

**→ TaskUpdate: P1.8 → completed**

### 1.9 Resumability — Check for Existing Work

**→ TaskUpdate: P1.9 → in_progress**

Before starting fresh, check if work already exists for this ticket:

```bash
# Check for existing worktrees related to this ticket
git -C "$SOURCE_REPO" worktree list 2>/dev/null | grep -i "<ticket-id-or-keyword>"

# Check for existing branches
git -C "$SOURCE_REPO" branch -a 2>/dev/null | grep -i "<ticket-id-or-keyword>"

# Check for existing PRs
gh pr list --search "<ticket-id-or-keyword>" --json number,title,state,headRefName
```

If existing work is found (worktree, branch, or PR), **always resume it**. Do not ask the user — just pick up where the work left off:

```
Found existing work for this ticket — resuming:
  - Branch: <branch-name>
  - Worktree: <path> (exists/missing — recreate if missing)
  - PR: #<number> (<state>)
  - Ticket status: <status>
```

Recreate the worktree if it's missing (`git worktree add` with the existing branch). Use the existing PR number for all subsequent operations. Only start fresh if the existing work is explicitly on the wrong branch or the PR was closed without merging — in that case, tell the user what happened before starting over.

**→ TaskUpdate: Phase 1 → completed. Print: "✅ Phase 1 complete. Detected: <org>, <tracker>, <integration-branch>, <pkg-mgr>. Proceeding to Phase 2."**
**→ TaskUpdate: Phase 1 → in_progress**

**→ TaskUpdate: P1.9 → completed**

---

### 1.10 Ticket Resolution (the ticket MUST already exist)

**→ TaskUpdate: P1.10 → in_progress**

**→ TaskUpdate: Phase 1 → in_progress**

**→ Print: "Phase 1.10: Resolving the existing ticket..."**

```bash
workflow_rename_tab "${TICKET_ID}: P1.10 Detect ${FEATURE_TAG}"
```

**workflow-do never creates tickets.** The run always works on an EXISTING tracker ticket. If the input is a ticket reference (URL, ID, or key like `ABC-123`, `#42`), fetch it from the tracker. If the input is a free-form idea with no ticket, **STOP** and tell the user a ticket must exist first — they (or the chief of staff) create it, then re-run. Do not invent one, do not create one, and do not proceed untracked.

Resolve and record the ticket's title, status, assignee (set it to the implementer if it is someone else), acceptance criteria/description (→ the P2.4b brief), and ID (branch/PR naming per `workflowDo.ticketIdPrefix`). For Notion the `ID` unique_id property IS the ticket number — read it, never compute one. For ClickUp, the `workflowDo.ticketIdPrefix` id (e.g. `<KEY-212>`) lives **in the task name** (`<KEY-212> — Intervals filter…`); read it from the name — the ClickUp task id (e.g. `868mh7m5g`) is only the API/URL handle. Resolve a `<KEY>-####` reference with `~/.agents/skills/clickup/scripts/clickup tasks --assignee me` (or `get <task-id>` for a `https://app.clickup.com/t/<id>` URL) — the clickup CLI, **not** the retired ClickUp MCP.

**Capture `TICKET_ID`, `TICKET_URL`, and `FEATURE_TAG`** — these are used throughout the run (zellij tab name, opening the ticket in the browser, writing the PR link back to the ticket). `FEATURE_TAG` is a 2-3 word slug describing what the feature relates to (e.g. `dark-mode-toggle`, `invoice-pdf-export`), distilled from the ticket title; it appears in every zellij tab rename and groups the run visually:

```bash
TICKET_ID="<tracker-id>"        # e.g. ABC-42, #123, or Notion page ID
TICKET_URL="<tracker-url>"      # e.g. https://app.clickup.com/t/868mh7m5g, https://notion.so/..., https://github.com/org/repo/issues/123
FEATURE_TAG="<2-3-word-slug>"   # e.g. dark-mode-toggle — derived from the ticket title
export TICKET_ID TICKET_URL FEATURE_TAG
```

If the input was a **ticket reference** (Phase 1 fetched an existing ticket), capture `TICKET_URL` from the fetched ticket's URL.

**Open the ticket in the browser FIRST** (SHARED-POLICY "Persistent Ticket + PR
Tabs" — this is the run's first browser action and the tab stays open for the
whole run). agent-browser's daemon reuses the live script-launched instance, and
`ensure_tab` makes it idempotent (no duplicate tabs on re-runs/resume):

```bash
ensure_tab ticket "$TICKET_URL"
```

**Name the pi session** with the ticket ID so it's identifiable in `pi --resume` and session lists. Update the current session's display name by modifying the first line of the session JSONL to add a `"name"` field:

```bash
# Derive the session directory and find the current session file
CWD_DIR="$(pwd)"
SESSION_DIR_NAME="--$(echo "$CWD_DIR" | sed 's|/|-|g')--"
CURRENT_SESSION=$(ls -t "$HOME/.pi/agent/sessions/$SESSION_DIR_NAME"/*.jsonl 2>/dev/null | head -1)

if [ -n "$CURRENT_SESSION" ]; then
  # Add/update the "name" field in the first line of the session file
  python3 -c "
import json, sys
lines = open(sys.argv[1]).readlines()
first = json.loads(lines[0])
first['name'] = f'{sys.argv[2]} {sys.argv[3] or \"\"}'.strip()
lines[0] = json.dumps(first) + '\n'
open(sys.argv[1], 'w').writelines(lines)
" "$CURRENT_SESSION" "$TICKET_ID" "$TICKET_TITLE"
fi
```

**→ TaskUpdate: Phase 1 → completed. Print: "✅ Phase 1 complete. Ticket: <ID> — <title>. Session named. Proceeding to Phase 2."**
**→ TaskUpdate: Phase 2 → in_progress**

**→ TaskUpdate: P1.10 → completed**

---

## Phase 2 — Groom the Ticket (Grill Mode)

**→ TaskUpdate: Phase 2 → in_progress**

**→ Print: "Phase 2: Grooming ticket (grill mode)..."**

```bash
workflow_rename_tab "${TICKET_ID}: P2.1 Groom ${FEATURE_TAG}"
```

Interrogate the ticket until it is genuinely ready to implement: interview the user relentlessly about every aspect of the plan, walking down each branch of the design tree, resolving dependencies between decisions one by one.

### 2.1 Load & Assess

**→ TaskUpdate: P2.1 → in_progress**

Read the ticket's current state from the tracker. Check its status — if already past "ready to start", ask if re-grooming is wanted.

**→ Check the assignee IMMEDIATELY.** If the ticket has no assignee, or is assigned to someone else (e.g. the person who created or reported the ticket), **reassign it to the current user (the implementer) right now** — do not wait until Phase 3. A ticket that is being groomed must already have an owner, and that owner is always the person doing the work, not the person who created the ticket. The assignee must be set **before any status changes** are made.

#### Assignee Setting (by tracker) — HARD REQUIREMENT

The ticket MUST have an assignee before any status changes. If the assignee is blank or assigned to someone other than the current user, set it to the current user first. **The assignee is always the implementer (the current user), never the ticket creator or reporter.**

**Set the assignee using the method for your detected tracker** — see your org's `workflowDo.assignee` in `$ORG_CONFIG_DIR/org-config.json` for the specific API endpoint, env file, and auth token. The general approach:

- **Notion:** source the org's env file, list workspace users to find the current user's ID, then PATCH the page's people property.
- **ClickUp:** `~/.agents/skills/clickup/scripts/clickup update <task_id> --assignee me` (token comes from `$ORG_CONFIG_DIR/<org>/env/clickup.env` automatically; the retired MCP's OAuth is not used and not needed). Assignees **replace** the set, so pass the full list when there is more than one.
- **GitHub Issues:** `gh issue edit <N> --add-assignee @me --repo <org>/<repo>`

**→ TaskUpdate: P2.1 → completed**

### 2.2 Explore the Codebase First

**→ TaskUpdate: P2.2 → in_progress**

Before asking questions, explore the codebase to answer what you can yourself:

- Read relevant models/schemas to understand existing data structures
- Read related API routes/controllers to understand existing patterns
- Read related frontend components to understand UI patterns
- Identify existing conventions for the type of change requested

Only ask the user questions that **cannot** be answered by reading the code.

**→ TaskUpdate: P2.2 → completed**

### 2.3 Grill — DB-First Decision Tree

**→ TaskUpdate: P2.3 → in_progress**

Walk the design tree in DB-first order and answer each question from codebase exploration, recording your answer as an assumption in the brief. **Do NOT ask the user one question at a time — the grill is autonomous, and there is no ticket-creation ask** (the ticket already exists; see P1.10).

**Database layer:**

- What tables/collections are affected? What columns/fields are added/modified/removed?
- What are the relationships? Foreign keys? Indexes needed?
- What are the constraints? NOT NULL, UNIQUE, CHECK, defaults?
- What migrations are needed? Are they backwards-compatible?

**Backend layer:**

- What endpoints are added/modified?
- What RBAC rules apply? Who can create/read/update/delete?
- What mandatory side effects exist? (emails, webhooks, audit logs, cache invalidation)
- What validation rules apply? What error states are possible?
- What edge cases exist? (concurrent writes, partial failures, empty states)

**Frontend layer:**

- Where does the state live? (server state via queries, local state, URL state, form state)
- What components are affected? New or modified?
- What user interactions trigger what mutations?
- What loading/error/empty states need handling?
- What accessibility requirements exist?

**→ TaskUpdate: P2.3 → completed**

### 2.4 Readiness Checklist

**→ TaskUpdate: P2.4 → in_progress**

The ticket is not ready until ALL hold:

- [ ] **Problem framed by impact** — who is hurting, and how?
- [ ] **Acceptance criteria are explicit and testable** — a reviewer could objectively pass/fail
- [ ] **Scope is bounded** — in-scope and explicit non-goals both written down
- [ ] **Dependencies / blockers identified** — other tickets, services, data, access
- [ ] **Edge cases and error paths considered** — empty states, failures, permissions
- [ ] **Technical approach sketched** — affected components/files, enough to not start from zero
- [ ] **Effort re-validated** — estimate matches the now-clarified scope
- [ ] **Verification strategy defined** — how will we know the ticket is done? (DB queries, API tests, UI states)

**→ TaskUpdate: P2.4 → completed**

### 2.4b Produce the 5-Element Brief

**→ TaskUpdate: P2.4b → in_progress**

Condense everything grooming established into ONE structured block — the
**brief**. This is the contract for the rest of the run: Phase 4 implements
against it, Phase 5.6 self-reviews against it, and the blind reviewer judges
the diff against its done-criteria. Later phases re-read it from the ticket
instead of re-deriving intent from chat history (which compaction may have
eaten).

```markdown
## Brief
**Goal** — one sentence: the user-visible outcome this ticket delivers.
**Constraints** — hard boundaries: stack, patterns to follow, perf/compat requirements, things that must not change.
**Done-criteria** — the acceptance criteria as objectively checkable statements (a reviewer can pass/fail each one).
**Non-goals** — explicitly out of scope; adjacent work this ticket deliberately does NOT touch.
**Context pointers** — files/modules/tables to start from, related tickets/PRs, relevant docs.
```

Rules:
- Every element is REQUIRED. If you cannot fill one, grooming is not done — go back to 2.3.
- Keep it under ~25 lines. The brief is a contract, not a design doc.
- Done-criteria here and the ticket's acceptance criteria must be the same list, not two divergent copies.

**→ TaskUpdate: P2.4b → completed**

### 2.5 Write Back to Ticket

**→ TaskUpdate: P2.5 → in_progress**

Write clarifications back into the ticket as they solidify — the ticket is the source of truth, not the chat. The ticket carries the **problem, not the plan**:

- **Clarified issue** — the problem statement, sharpened by grooming
- **Acceptance criteria** — testable statements a reviewer can pass/fail (same list as the brief's done-criteria, not a divergent copy)
- **Out-of-scope / non-goals** — the adjacent work this ticket deliberately does not touch
- **Context pointers** — files/modules/tables to start from, related tickets/PRs, docs
- **Constraints** — hard boundaries (stack, patterns to follow, compat/perf requirements)

> ⚠️ **NEVER write an approach, implementation plan, step-by-step task list, or file-by-file breakdown into the ticket.** Some trackers forbid it outright — an org's own contributing guide can ban plans and task lists in tickets. The plan lives in `/tmp/workflow-brief.md` (BRIEF_FILE) and in the PR; the ticket stays a problem + acceptance-criteria statement. (User directive 2026-09-30.)

**→ While you are here, fill in the ticket's STRUCTURED FIELDS — the ones the
ticket itself makes unambiguous** (user directive 2026-10-14). A ticket that keeps
its planning metadata current is worth more than the prose. For ClickUp the full
inventory lives in the clickup skill ("Task field inventory") with field ids and
value shapes; the ones a grooming pass can usually answer:

```bash
S=~/.agents/skills/clickup/scripts/clickup
$S update <task_id> --custom-field <required-field-id>=<option-uuid>
```

- `Planned/Unplanned` (required on sprint lists) — a bug report nobody scheduled is
  `Unplanned`; the option UUIDs are in the clickup skill.
- `Customer Vertical` — only when the ticket says which vertical it is. **Known gap:
  `Residential` does not exist as an option** and that customer project's
  work is residential, so leave it unset there and say so rather than picking a
  wrong vertical.
- Anything sprint-planning-owned (`Expected Delivery`, `Committed Quarter`,
  `Swimlane Tactic`, `Tech Goals`, `Committed Initiative`) — set it only if the
  ticket is explicit; otherwise leave it and do not guess.

Never invent a value to "fill a field". An empty field is honest; a wrong one is not.

**→ TaskUpdate: P2.5 → completed**

### 2.6 Advance Status

**→ TaskUpdate: P2.6 → in_progress**

Only when every checklist item is satisfied, advance the ticket to the tracker's "ready to start" state. **ClickUp:*** that state is `ready to work` — read the **live** list statuses first (`clickup list <list_id>`; Sprint lists roll, so a hardcoded name can silently no-op — see 1.2), pass that exact name, and verify with `clickup get <task-id>`.

**→ TaskUpdate: P2.6 → completed**

### 2.7 Set Story Points / Difficulty Estimate

**→ TaskUpdate: P2.7 → in_progress**

After grooming is complete and the scope is clarified, set a story point estimate (or difficulty estimate) on the ticket. Base the estimate on the now-clarified scope — not the original vague description.

**Estimation scale:** Use Fibonacci (1, 2, 3, 5, 8, 13) or the tracker's native scale. General guidance:

| Points | Complexity | Example                                                               |
| ------ | ---------- | --------------------------------------------------------------------- |
| 1      | Trivial    | Text change, config tweak, one-line fix                               |
| 2      | Small      | Single component, no new patterns, clear DB change                    |
| 3      | Medium     | A few files, one new endpoint + UI, straightforward migration         |
| 5      | Large      | Multiple endpoints, new patterns, RBAC changes, multi-table migration |
| 8      | Complex    | Cross-cutting feature, new architecture, significant refactoring      |
| 13     | Epic-level | Should probably be split into smaller tickets                         |

**Set the estimate using the method for your detected tracker:**

- **Notion:** PATCH the page's effort select property — for a Notion ticket DB this is e.g. **"Effort level"** (a select, NOT a number/story-points field). Set it by option name (e.g. "1", "2", "3" Fibonacci). Read `workflowDo.effortProperty` in `$ORG_CONFIG_DIR/org-config.json` for the per-org property name. If the select option doesn't exist yet, PATCHing with the new name creates it. (friction example: a skill once said "Story Points number property" but the DB had no such field — read `workflowDo.effortProperty` instead).
- **ClickUp:** set the estimate in ClickUp's built-in **Sprint Points** field (user directive 2026-10-14) — it is a built-in attribute, NOT a custom field and NOT `time_estimate`:

  ```bash
  ~/.agents/skills/clickup/scripts/clickup update <task_id> --points <n>
  ```

  That is the API's `points`, which ClickUp documents as "Update the task's Sprint Points". The token is in `$ORG_CONFIG_DIR/<org>/env/clickup.env` and the org config directory is mounted read-only into the cage, so this works inside a run. Verified end-to-end 2026-10-14 (set 3, read back 3). Do NOT substitute a comment and do NOT invent a custom field. (The retired MCP could not write points at all.)
- **GitHub Issues:** if the repo has a story-point label or estimate field, apply it. Otherwise, post a comment with the estimate: `gh issue comment <N> --body "**Story points: <N>** (Fibonacci scale)"`.

If the tracker has no story point field or estimation system, post the estimate as a ticket comment instead.

**→ TaskUpdate: P2.7 → completed**

**→ TaskUpdate: Phase 2 → completed. Print: "✅ Phase 2 complete. Ticket groomed, marked 'ready to start', story points set. Proceeding to Phase 3."**
**→ TaskUpdate: Phase 3 → in_progress**

---


## Phase 3 — Workspace Setup + PR Creation

**→ TaskUpdate: Phase 3 → in_progress**

**→ Print: "Phase 3: Setting up workspace..."**

```bash
workflow_rename_tab "${TICKET_ID}: P3.0 Setup ${FEATURE_TAG}"
```

### 3.0 Detect Monitor + Position Chrome + Set Viewport

- If Chrome inside the container dies, use the script's own idempotent recipe — `bash ~/.agents/skills/workflow-do/scripts/chrome.sh status`, then `... chrome.sh revive` — then re-attach with `agent-browser --headed --profile "$CHROME_SESSION_PROFILE" --session "$CHROME_SESSION" --pin-tab --cdp "http://127.0.0.1:$CHROME_CDP_PORT" open "$TICKET_URL"` and re-verify the agent-browser connection (Phase 0.6) and GitHub login (Phase 1.3b) before continuing. The persistent profile preserves login sessions across Chrome restarts within the same container run.


**→ TaskUpdate: P3.0 → in_progress**

#### 3.0.1 Detect leftmost landscape monitor

**→ Remember: Update task P3.0 in TaskList as you work through this substep.**

Uses `wlr-randr` (installed in the container) which queries the Wayland display directly — works from inside the container because the Wayland socket is mounted.

**On macOS (`WORKFLOW_X11=1`)** there is no Wayland/niri and no monitor detection — skip this step and use a fixed viewport set in 3.0.2.

```bash
# macOS / X11: no Wayland, no monitor detection — fixed viewport set in 3.0.2.
if [ "${WORKFLOW_X11:-0}" = "1" ]; then
  echo "🖥️  macOS/X11 mode — skipping wlr-randr monitor detection (no Wayland)."
else
MONITOR=$(wlr-randr 2>/dev/null | awk '
  /^[^ ]/ { name=$1 }
  /Position:/ { split($2, p, ","); x=p[1]+0 }
  /Transform:/ { transform=$2 }
  /current/ { split($1, m, "x"); w=m[1]+0; h=m[2]+0 }
  /^$/ {
    if (name != "" && w > 0 && h > 0) {
      if (transform ~ /90|270/) { tmp=w; w=h; h=tmp }
      if (w > h) print x, w, h, name
    }
    name=""; x=0; w=0; h=0; transform="normal"
  }
  END {
    if (name != "" && w > 0 && h > 0) {
      if (transform ~ /90|270/) { tmp=w; w=h; h=tmp }
      if (w > h) print x, w, h, name
    }
  }
' | sort -n | head -1)
MON_W=$(echo "$MONITOR" | awk '{print $2}')
MON_H=$(echo "$MONITOR" | awk '{print $3}')
MON_NAME=$(echo "$MONITOR" | awk '{print $4}')
echo "🖥️  Leftmost monitor: $MON_NAME ${MON_W}x${MON_H}"
fi
```

#### 3.0.2 Move Chrome to horizontal monitor + maximize + set viewport

**→ Remember: Update task P3.0 in TaskList as you work through this substep.**

The niri socket is mounted from the host, but **`niri msg` does NOT work inside the container**: `/usr/bin/niri` is the *host's* binary bind-mounted read-only and fails against the cage's older stack (`libdisplay-info.so.3`, `GLIBC_2.43`, `LIBINPUT_1.30` missing). Never call `niri` directly from a stage — it fails silently and the placement step no-ops (which is what happened on every run until 2026-09-30).

Instead ask the HOST to do it, through the shipped shim (zellij commands are executed by the host daemon):

```bash
bash ~/.agents/skills/workflow-do/scripts/place-chrome.sh            # title "Google Chrome", monitor $NIRI_CHROME_MONITOR or HDMI-A-3
bash ~/.agents/skills/workflow-do/scripts/place-chrome.sh "Notion"   # match a different window title
```

It starts a short-lived host pane that runs `~/.local/bin/workflow-chrome-place`, which finds the newest window whose title matches, moves it to the landscape monitor and fills the column. Treat placement as best-effort: if the shim prints "placement skipped", continue — the agent-browser viewport below is what screenshots actually depend on.

**On macOS (`WORKFLOW_X11=1`)** there is no niri — Chrome renders into an Xquartz window the human positions manually. Set a fixed landscape viewport (1440×900) so screenshot framing stays consistent.

```bash
if [ "${WORKFLOW_X11:-0}" = "1" ]; then
  # macOS/X11: no niri compositor. Xquartz window is positioned by the human.
  # Use a fixed landscape viewport for consistent screenshot framing.
  MON_W=1440; MON_H=900
  agent-browser set viewport $MON_W $MON_H 2>/dev/null
  echo "🖥️  macOS/X11 mode — viewport set to ${MON_W}x${MON_H} (position the Xquartz window yourself)"
else
# Host-side placement (best-effort) — see the note above for why niri cannot be called here.
if [ -n "$MON_NAME" ]; then
  bash ~/.agents/skills/workflow-do/scripts/place-chrome.sh "Google Chrome" "$MON_NAME" 2>/dev/null || true
  echo "🖥️  asked the host to move Chrome to $MON_NAME and fill it"
fi

# Set viewport to match monitor resolution
if [ -n "$MON_W" ] && [ -n "$MON_H" ]; then
  agent-browser set viewport $MON_W $MON_H 2>/dev/null
  echo "🖥️  Viewport set to ${MON_W}x${MON_H}"
fi
fi
```

**→ TaskUpdate: P3.0 → completed**


### 3.1 Sync Integration Branch

**→ TaskUpdate: P3.1 → in_progress**

Before creating the feature branch, ensure the integration branch is fully up to date with its remote counterpart. This guarantees the new branch starts from the latest code — not a stale local ref that may be days old.

```bash
BRANCH_NAME="<ticket-id>-<short-description>"  # e.g. ABC-42-user-preferences
ORG="<detected-org>"
SOURCE_REPO=~/repos/$REPO_NAME

# Worktree base: ~/worktrees is the ONE canonical location # (past decision —
# retired the old ~/r split which was a read-only mount in some cages and caused
# path drift / past "Permission denied" incident). Nested as $ORG/$REPO_NAME so paths
# mirror the repo layout. Always writable inside the cage.
WT_BASE="$HOME/worktrees/$ORG/$REPO_NAME"
mkdir -p "$WT_BASE"
WORKTREE="$WT_BASE/$BRANCH_NAME"

# Fetch all latest refs from origin (safe for parallel runs — does NOT change
# source repo HEAD)
git -C "$SOURCE_REPO" fetch origin

# Update the local integration branch to match the remote. If the integration
# branch is NOT currently checked out in the source repo (the common case in a
# cage container, where the source repo is in detached HEAD or on a different
# branch), this fast-forwards the local ref safely:
if ! git -C "$SOURCE_REPO" symbolic-ref -q HEAD 2>/dev/null | grep -q "$INTEGRATION_BRANCH"; then
  git -C "$SOURCE_REPO" branch -f "$INTEGRATION_BRANCH" "origin/$INTEGRATION_BRANCH"
  echo "✅ Local $INTEGRATION_BRANCH synced to origin/$INTEGRATION_BRANCH"
else
  # Integration branch IS checked out in the source repo — pull directly
  git -C "$SOURCE_REPO" pull --ff-only origin "$INTEGRATION_BRANCH"
  echo "✅ Pulled latest into $INTEGRATION_BRANCH (was already checked out)"
fi

# Verify we are branching from truly-latest code
git -C "$SOURCE_REPO" log --oneline -1 "origin/$INTEGRATION_BRANCH"
```

**→ TaskUpdate: P3.1 → completed**

### 3.2 Create Worktree + Feature Branch

**→ TaskUpdate: P3.2 → in_progress**

Now create the feature branch from the freshly-synced integration branch and
add the worktree:

```bash
# Create branch from the (now up-to-date) integration branch — NO checkout on
# source repo, which would change its HEAD and break other parallel runs
git -C "$SOURCE_REPO" branch "$BRANCH_NAME" "origin/$INTEGRATION_BRANCH"
git -C "$SOURCE_REPO" worktree add "$WORKTREE" "$BRANCH_NAME"
```

For **monorepos**: all services (frontend, backend, shared libs) live in the same worktree. Do NOT create separate worktrees for frontend and backend — they share the same branch and PR.

**Note:** The `cage` bashrc function already started the Docker container with the worktree path mounted. You are running inside that container right now. No need to start a container — just create the worktree and work in it.

**→ TaskUpdate: P3.2 → completed**

### 3.3 Push Branch to Remote

**→ TaskUpdate: P3.3 → in_progress**

Push the feature branch to the remote immediately after creating it. This is required before creating the draft PR (Phase 3.11) and allows CI to start running early.

```bash
git -C "$WORKTREE" push -u origin "$BRANCH_NAME"
echo "✅ Branch $BRANCH_NAME pushed to origin"
```

**→ TaskUpdate: P3.3 → completed**

### 3.4 Copy Repository Secrets

**→ TaskUpdate: P3.4 → in_progress**

Copy the base repository's root-level `secrets/` directory into the new worktree at the same relative path. Use an independent copy, not symlinks: setup may replace the downloaded vault and generated files. Keep an existing worktree's secrets untouched when resuming.

```bash
if [ -d "$SOURCE_REPO/secrets" ] && [ ! -e "$WORKTREE/secrets" ]; then
  (
    umask 077
    mkdir -p "$WORKTREE/secrets"
    cp -RL "$SOURCE_REPO/secrets/." "$WORKTREE/secrets/"
  )
fi
```

Check the repository root's package scripts and setup documentation for a command that prepares or extracts secrets. Discover the command from the repository; do not assume a fixed name. Run it from the worktree root after dependencies are installed in P3.5 and before starting the database or dev servers. A copied vault may already exist; let the repository's setup command handle it. Verify setup succeeds and creates the environment files needed by the chosen local startup commands. Do not print secret values or commit the copied directory or generated environment files.

**→ TaskUpdate: P3.4 → completed**

### 3.5 Install Dependencies + Codegen

**→ TaskUpdate: P3.5 → in_progress**

**⚠️ MANDATORY: Run codegen after install, before ANY commits.** Many projects use pre-commit hooks (Husky, lint-staged, etc.) that run typecheck or lint. These hooks will **fail** if generated files (Prisma client, OpenAPI clients, generated types) are missing. Codegen must happen after `pnpm install` and before the first `git commit` — there is no skipping this.

```bash
cd "$WORKTREE" && $PKG_MGR install
# Also install in sub-workspaces if they have separate deps
[ -d "$WORKTREE/$FRONTEND_DIR" ] && (cd "$WORKTREE/$FRONTEND_DIR" && $PKG_MGR install)
[ -d "$WORKTREE/$BACKEND_DIR" ] && (cd "$WORKTREE/$BACKEND_DIR" && $PKG_MGR install)
```

**Check for errors.** If install fails (missing registry access, peer dep conflicts), diagnose and fix before continuing.

**Run codegen — this is NOT optional.** Pre-commit hooks (Husky, lint-staged) will fail without generated files. After `pnpm install`, check `package.json` scripts for codegen commands and run them:

```bash
# Check for codegen scripts in each workspace
for ws in "$WORKTREE" "$WORKTREE/$FRONTEND_DIR" "$WORKTREE/$BACKEND_DIR"; do
  [ -f "$ws/package.json" ] || continue
  HAS_GENERATE=$(cat "$ws/package.json" | python3 -c "
import json, sys
d = json.load(sys.stdin)
scripts = d.get('scripts', {})
for k in ['generate', 'generate:prisma-schemas', 'generate:api-clients', 'generate:prisma']:
    if k in scripts:
        print(k)
" 2>/dev/null)
  if [ -n "$HAS_GENERATE" ]; then
    echo "Running codegen in $(basename $ws): $HAS_GENERATE"
    (cd "$ws" && $PKG_MGR run generate 2>/dev/null || true)
  fi
done
```

Common codegen patterns:

- **Prisma**: `npx prisma generate` (required before TypeScript typecheck)
- **OpenAPI clients**: `pnpm run generate:api-clients` (required before TypeScript typecheck)
- **Fix generated types**: `pnpm run fix:generated-types` (may be needed for strict mode)

**If a pre-commit hook fails with typecheck errors during Phase 4**, it is almost certainly because codegen wasn't run (or needs re-running after schema changes). Run `pnpm run generate` (or the project's equivalent) in the relevant workspace, then retry the commit. Do NOT bypass the hook with `--no-verify`.

\*\* Use pnpm if there is a lock file for that or npm otherwise if it is a node project

Run the root-level secrets setup command discovered in P3.4, if the repository provides one, and verify it succeeds before starting services.

**→ TaskUpdate: P3.5 → completed**

### 3.6 Start Database + Migrate + Hydrate

**→ TaskUpdate: P3.6 → in_progress**

```bash
workflow_rename_tab "${TICKET_ID}: P3.6 Setup ${FEATURE_TAG}"
```

Start the database BEFORE implementation so the agent can test incrementally during Phase 4. The DB runs via Docker-in-Docker (the container has its own Docker daemon with isolated ports).

**Start the database** using the `bg_run` tool. **Always wrap `bg_run` commands in `bash -c '...'`** — `bg_run` executes the command with `/bin/sh` by default, which lacks `source` and doesn't expand env-file variables, so a command like `source /tmp/workflow_env.sh; cd "$WORKTREE/..." && pnpm dev` silently never starts (past incident: `/bin/sh: 1: source: not found`).

```
bg_run:
  command: "bash -c 'source /tmp/workflow_env.sh; cd \"$WORKTREE\" && <db-start-command>'"
  name: "Database server"
  isAgent: false
```

Wait for the database to be healthy:

```bash
until pg_isready -h localhost -p 5432 2>/dev/null; do sleep 1; done
echo "✅ Database ready"
```

If the DB startup fails, check logs with `bg_logs`, diagnose, fix, and re-run.

**⚠️ Fresh-cage image-pull timeouts: re-run, don't rebuild.** In a fresh cage, `supabase start` (or any DinD DB bring-up) pulls images and can exceed a 10-minute timeout mid-pull, exiting as failed even though nothing is wrong. Re-run the same start command once — docker layer pulls resume from cache and the second attempt typically completes. Only diagnose further if the re-run also fails. (Learned 2026-09-14.)

**Reset, migrate, and hydrate** — run from the workspace that owns the DB commands (usually backend — check Phase 1.6):

```bash
cd "$WORKTREE/<workspace-with-db-commands>"

# 1. Reset (drop and recreate)
$PKG_MGR run <db-reset-script>

# 2. Migrate (apply all migrations)
$PKG_MGR run <db-migrate-script>

# 3. Hydrate / Seed (populate with test data)
cd "$WORKTREE/$BACKEND_DIR"
$PKG_MGR run <db-hydrate-script>
```

**Verify each step succeeded.** A silently-failed migration or empty DB makes testing worthless. Check for error output and non-zero exit codes. If any step fails, diagnose and fix before continuing.

**→ TaskUpdate: P3.6 → completed**

### 3.7 Start Dev Servers

**→ TaskUpdate: P3.7 → in_progress**

```bash
workflow_rename_tab "${TICKET_ID}: P3.7 Setup ${FEATURE_TAG}"
```

Start dev servers BEFORE implementation so the agent can test in the browser during Phase 4. **No `lsof | kill` port cleanup needed** — the container starts fresh with no stale processes. Ports are isolated per container.

Use the `bg_run` tool to start frontend and backend dev servers as background tasks (NOT zellij panes). **Always wrap `bg_run` commands in `bash -c '...'`** (see P3.6 note — `bg_run` uses `/bin/sh` by default, which lacks `source` and doesn't expand env-file vars).

```
bg_run:
  command: "bash -c 'source /tmp/workflow_env.sh; cd \"$WORKTREE/$FRONTEND_DIR\" && $PKG_MGR run dev'"
  name: "Frontend dev server"
  isAgent: false

bg_run:
  command: "bash -c 'source /tmp/workflow_env.sh; cd \"$WORKTREE/$BACKEND_DIR\" && $PKG_MGR run dev'"
  name: "Backend dev server"
  isAgent: false
```

**⚠️ CRITICAL: Dev servers are long-running processes that NEVER exit.** Do NOT wait for the bg_run task to complete. Instead, **actively poll** to verify the server is ready:

```bash
timeout 60 bash -c 'until curl -sf http://localhost:3000 2>/dev/null; do sleep 1; done' \
  && echo "✅ Frontend ready" || { echo "❌ Frontend not responding after 60s"; bg_logs <task-id>; }

timeout 60 bash -c 'until curl -sf http://localhost:3001 2>/dev/null; do sleep 1; done' \
  && echo "✅ Backend ready" || { echo "❌ Backend not responding after 60s"; bg_logs <task-id>; }
```

If a server failed, check logs with `bg_logs`, diagnose, fix, and re-run with `bg_kill` + `bg_run`. Only proceed once both servers are running.

**→ TaskUpdate: P3.7 → completed**

### 3.8 Baseline Checks (Tests + Lint Before Changes)

**→ TaskUpdate: P3.8 → in_progress**

```bash
workflow_rename_tab "${TICKET_ID}: P3.8 Setup ${FEATURE_TAG}"
```

Run the existing test suite and lint checks BEFORE making any changes. This establishes a green baseline — if tests fail here, the failures are pre-existing and not caused by our changes. If they pass, any failures after implementation are ours.

```bash
cd "$WORKTREE"

# Run existing tests (use the project's test command from Phase 1.6)
$PKG_MGR test 2>&1 | tee /tmp/baseline-tests.log
BASELINE_TESTS_EXIT=$?

# Run lint (use the project's lint command from Phase 1.6)
$PKG_MGR run lint 2>&1 | tee /tmp/baseline-lint.log
BASELINE_LINT_EXIT=$?

# Report baseline status
if [ $BASELINE_TESTS_EXIT -eq 0 ]; then
  echo "✅ Baseline tests: PASS"
else
  echo "⚠️  Baseline tests: FAIL (pre-existing — not caused by our changes)"
  echo "   These failures exist on the integration branch before any changes."
  echo "   Note them — Phase 5 will compare against this baseline."
fi

if [ $BASELINE_LINT_EXIT -eq 0 ]; then
  echo "✅ Baseline lint: PASS"
else
  echo "⚠️  Baseline lint: FAIL (pre-existing — not caused by our changes)"
fi
```

Save the baseline results for comparison in Phase 5. If tests or lint fail at baseline, note which tests/rules fail so Phase 5 can distinguish pre-existing failures from new ones.

**→ TaskUpdate: P3.8 → completed**

### 3.9 ~~Open Lazygit Pane~~ (removed)

Removed 2026-09-06 — the workflow no longer opens a lazygit pane; no task pane is opened here (pane lifecycle is script-owned).

**→ TaskUpdate: P3.9 → completed** (nothing to do)

### 3.10 Update Ticket Status

**→ TaskUpdate: P3.10 → in_progress**

Set the ticket to "in progress" in the tracker.

**→ SET THE START DATE IN THE SAME WRITE (user directive 2026-10-14).** Starting
work is when the ticket's start date should be recorded — whenever the tracker has
one, set it now, in the same call as the status change:

- **ClickUp:** read the **live** statuses of the task's list first —
  `~/.agents/skills/clickup/scripts/clickup list <list_id>` (Sprint lists roll, so a
  hardcoded name can silently no-op; see 1.2) — then set the start-of-work status by its
  exact live name; a list here calls it `working`:

  ```bash
  ~/.agents/skills/clickup/scripts/clickup update <task_id> --status "working" --start today
  ```

  (`--start` takes `today`, `YYYY-MM-DD[ HH:MM]` local, or epoch ms; the CLI
  converts to the epoch-ms the API wants.) Verify the write with `clickup get <task_id>`.
- **Notion:** set the date property named in `workflowDo.startDateProperty`
  (skip silently if the org's block does not name one).
- **Jira (only when that org's tracker is Jira):** set the `Start date` field if the project's screen has one.
- **GitHub Issues:** no start-date field — skip (the PR/branch timestamps carry it).

Do not skip this silently: if the tracker supports a start date, set it. If it
cannot be set programmatically, say so in the run log.

**→ Verify the assignee is set to the current user.** The assignee should have been set in Phase 2.1. If it is still blank or assigned to someone else, **set it to the current user NOW before changing the status** — see the Assignee Setting procedure in 2.1. Never advance a ticket's status without the correct assignee. The person doing the work (the current user) is always the assignee, never the ticket creator or reporter.

**→ TaskUpdate: P3.10 → completed**

### 3.11 Create Draft PR

**→ TaskUpdate: P3.11 → in_progress**

**⚠️ Prerequisite: the feature branch needs at least one commit before GitHub will create a PR.** `gh pr create --draft` fails with `GraphQL: No commits between <base> and <branch>` when the branch is still identical to the integration branch (observed in a ticket — the skill creates the draft PR before Phase 4 implementation, so there is nothing to diff yet). If Phase 4 has not produced any commits yet, either (a) defer this step until the first implementation commit is pushed, or (b) make an initial commit first (e.g. a scaffold/chore commit) and then create the draft PR.

Create a draft PR with:

- **Title**: `<ticket-id> <ticket-title>` (for ClickUp/Notion — for ClickUp the task name already starts with the NVR id) or just the title (for GitHub Issues with `Fixes #N`)
- **Base**: `$INTEGRATION_BRANCH`
- **Body**: Include the ticket URL, motivation, and approach sections

```bash
cd "$WORKTREE"

cat << 'EOF' > /tmp/pr-body.md

## Motivation

<problem statement from ticket>

## Approach

<technical approach from ticket>

## Risk Assessment

<Preliminary rating — 🟢 Low / 🟡 Medium / 🔴 High — based on the planned approach: schema or RLS changes, auth/permission changes, money-path changes, or destructive operations raise the level. Re-assessed and justified in the final body at P8.>

## Ticket

<ticket URL>
EOF

gh pr create --draft \
  --title "<ticket-id> <title>" \
  --body-file /tmp/pr-body.md \
  --base "$INTEGRATION_BRANCH"

# Capture the PR URL immediately after creation
PR_URL=$(gh pr view --json url -q .url)
PR_NUMBER=$(gh pr view --json number -q .number)

# Open the PR in its PERMANENT labeled tab (never a duplicate) so the human can
# see the PR and the ticket side by side — both stay open for the whole run.
ensure_tab pr "$PR_URL"
ensure_tab ticket "$TICKET_URL"
```

**→ TaskUpdate: P3.11 → completed**

### 3.12 Add PR Link to the Ticket

**→ Remember: Update task P3.11 in TaskList as you work through this substep.**

**HARD REQUIREMENT: The PR link MUST be written to the ticket as soon as the draft PR exists.** Do not wait until a later phase — the ticket is the source of truth and must reference the PR from the moment the PR is created. This is what keeps the tracker as the single source of truth that connects the ticket to the code.

Write the PR URL back to the ticket using the tracker's API. Use the method and credentials for your detected tracker — see your org's `workflowDo` block (`prLinkOnTicket`, `credentials`) in `$ORG_CONFIG_DIR/org-config.json`. The general approach:

- **Notion:** source the org's env file, then either set a `Pull Request` URL property on the page or post a page comment with the PR URL.
- **ClickUp:** `~/.agents/skills/clickup/scripts/clickup comment <task_id> "<bare PR URL>"` — ClickUp has **no remote-link API**, so the comment *is* the link mechanism; send a **bare URL as plain text**, never a labelled markdown link (see the clickup skill's Hard rule 1: labels lose the URL on copy/export).
- **GitHub Issues:** post a comment on the issue with the PR URL (GitHub also auto-links via `Fixes #N` in the PR body).

If the tracker API call fails, **do not abort the run** — log a warning and retry in Phase 8.5 (when the PR is finalized) and Phase 10.5 (when the ticket is closed). The PR link must end up on the ticket by the time the ticket is done.

**⚠ MANDATORY FALLBACK: if comments/links fail, append to the ticket body IMMEDIATELY.** If the tracker's comment or link API fails (e.g. permissions, unsupported endpoint), you MUST immediately fall back to editing the ticket's description/body directly — append a `## Pull Request` section at the bottom with the PR URL. Do NOT just log a warning and move on — execute the fallback right now. For Notion, the "Dev tasks" DB has **no `Description` rich_text property** — instead append child blocks to the page (a `heading_2` "Pull request" + a `bookmark` block with the PR URL) via `PATCH /v1/blocks/{page_id}/children`. (past friction: a skill once PATCHed a Description property that doesn't exist on the Notion DB.) For ClickUp, `~/.agents/skills/clickup/scripts/clickup update <task_id> --append-description "## Pull Request

<bare PR URL>"` — the CLI reads the existing markdown and writes the whole body back (the API's `markdown_description` is read-only and writes use `markdown_content`; asking the CLI is the safe way). For GitHub Issues, the `Fixes #N` in the PR body already links them, but also post a comment if possible. The PR link must be visible on the ticket immediately after the draft PR is created — not deferred to a later phase.

