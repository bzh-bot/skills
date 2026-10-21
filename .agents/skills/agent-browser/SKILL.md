---
name: agent-browser
description: Browser automation CLI for AI agents that drives the user's REAL, already-logged-in Chrome via --auto-connect (not a throwaway context). Use when the user needs to interact with websites, including navigating pages, filling forms, clicking buttons, taking screenshots, extracting data, testing web apps, or automating any browser task. Triggers include requests to "open a website", "fill out a form", "click a button", "take a screenshot", "scrape data from a page", "test this web app", "login to a site", "automate browser actions", or any task requiring programmatic web interaction.
allowed-tools: Bash(npx agent-browser:*), Bash(agent-browser:*), Bash(curl:*), Bash(ps:*), Bash(mountpoint:*), Bash(google-chrome:*)
---

# Browser Automation with agent-browser

> **Read the original before improvising — it ships with the CLI, version-matched.**
>
> This skill is a **local rule layer**. It deliberately does not vendor the generic
> command documentation, because the CLI carries its own docs in lockstep with the
> installed version. Resolve them at runtime — never hardcode the path (it moves
> when the nvm node version changes):
>
> ```bash
> agent-browser skills path core          # → live path to the bundled core skill
> agent-browser skills get core --full    # overview + full command reference + templates
> agent-browser skills list               # also: electron, slack, dogfood, webmcp-gen, …
> ```
>
> The bundled skill is `$(agent-browser skills path core)/SKILL.md` with `references/`
> beside it — `commands.md` (the complete command reference), `authentication.md`,
> `session-management.md`, `snapshot-refs.md`, `trust-boundaries.md`, `streaming.md`,
> `webgpu.md`, `profiling.md`, `proxy-support.md`, `video-recording.md`.
>
> **Precedence: where the bundled reference conflicts with anything in this skill, THIS SKILL WINS.**
> The most important instance: the bundled docs open with *"Always use your own session"*.
> In this skill's default mode that is **wrong** — see Mandatory Defaults #3.

## Hard rules: explicit instance + pinned, labeled tab

These rules are hard requirements for agent flows. They apply on top of everything below; wherever the older sections of this doc conflict, THESE RULES WIN.

1. **Attaching requires an explicit user-designated browser — and `--auto-connect` is how you attach to the user's live Chrome.** For router walks (triage / accounting) and any flow the user directs onto their live browser, `--auto-connect` IS the designated attach (user-authorized). For anything else, never attach to whatever browser happens to be running; use a designated instance.
2. **`--auto-connect` MUST be passed on EVERY command.** A named session does NOT keep the live-Chrome attachment between invocations — drop it once and agent-browser launches its OWN fresh browser (blank tab), which is never what anyone wants in an attach flow. Every command in an attach flow carries the full binding: `--auto-connect --session <name> --pin-tab` (plus `tab <label>`/`tab <n>` where needed).
3. **Confirm the instance with the user before the first browser command of any flow.** The designated instance must be one the user launched or approved in the moment. A helper script that the user runs (or whose output the user sees and proceeds on) counts as that confirmation.
4. **Always target a specific instance (session) AND a specific tab.** NEVER run commands against the current/active tab, and never rely on the session default tab. Labels are SESSION-scoped: a label only exists in the session that created it — if your flow has a pre-opened tab but no label in your session, find it by URL in `tab list`, switch by its t-number, and work within it. Only open your own tab if the target tab does not exist at all.
5. **`tab list` to FIND a tab is fine when the user asks on the host** to locate a tab — but never perform commands against the active browser or the active tab as a side effect.
6. **When a flow is done with a tab, close that exact tab** — `tab close <label-or-id>` — and never close others. In attach flows NEVER `close` the whole browser (it is the user's live Chrome — closing it kills their session).

**Pinning form (verified 2026-09-28):** `--pin-tab tab <label|tN>` binds the session to that tab **and consumes the following subcommand**, so `… --pin-tab tab t3 snapshot` performs only the tab selection and returns the tab envelope. Bind on its own invocation (`agent-browser --auto-connect --session S --pin-tab tab t3`), then run every later command as `agent-browser --auto-connect --session S --pin-tab <subcommand>` — no `tab t3`. The pin is sticky per session (`--no-pin-tab` clears it); once pinned, commands fail with a `tab_gone` error instead of falling back to another tab.

The CLI uses Chrome/Chromium via CDP directly. Install via `npm i -g agent-browser`, `brew install agent-browser`, or `cargo install agent-browser`. Run `agent-browser install` to download Chrome. Existing Chrome, Brave, Playwright, and Puppeteer installations are detected automatically. Run `agent-browser upgrade` to update to the latest version.

## Use the user's REAL browser (this skill's whole point)

This skill drives **the user's actual Chrome** — the same browser they are already logged into, with their real cookies, history, and profile — instead of launching isolated throwaway contexts that trigger CAPTCHAs and lose login state. It does this by connecting to the user's running Chrome over the Chrome DevTools Protocol (CDP) via `--auto-connect`.

The launchers must pass `--remote-debugging-port=9222` **and** a non-default user-data-dir (`~/.agent-browser/chrome`, bind-mounted from the real `~/.config/google-chrome`). Chrome refuses remote debugging on the *default* profile dir, so the bind mount is essential: it presents the live profile (logins, history, sessions, no copy, no drift) at a path Chrome accepts for debugging.

```bash
sudo mount --bind "$HOME/.config/google-chrome" "$HOME/.agent-browser/chrome"
```

All profiles share that one Chrome instance, so a single process owns port 9222 and every profile's tabs are reachable through it. Each launcher entry carries the same triple: `--remote-debugging-port=9222 --user-data-dir=~/.agent-browser/chrome --profile-directory=<Profile>`. Launching Chrome any other way opens **no** debug port and `--auto-connect` fails — see Mandatory Defaults #1 for the `CONFLICT` path.

Profile alias → profile-directory mappings are account identity, not skill content: keep them in your own env file and read the alias from there. Each entry may carry a `login_hint`; verify the signed-in account matches it before acting, especially when one Chrome profile is shared via an account switch. On a mismatch, consult the map rather than guessing.

## Mandatory Defaults (Always Apply)

Three rules apply to **every** `agent-browser` invocation in this skill, no exceptions:

1. **Always drive the user's real Chrome via `--auto-connect`.** This connects to their running, already-logged-in browser on port 9222 instead of spawning an isolated fresh context. Before the first command, confirm a debuggable Chrome is up with the [attach checklist](#attach-checklist-is-a-debuggable-chrome-up) below:

   ```bash
   curl -s --max-time 2 http://127.0.0.1:9222/json/version   # answers => READY, drive it
   ```

   If nothing answers and Chrome is running without the flag, that is a `CONFLICT` — ask the user to fully quit Chrome and relaunch it from their own launcher (the one that carries the debug flag). You cannot fix it yourself, and you must **not** kill their browser. If Chrome is fully closed, launch it per step 7 of the checklist.

2. **Always run headed — `--headed` is MANDATORY on every command, not optional.** `--auto-connect` attaches to the user's visible Chrome, which is inherently headed, and `--headed` is the flag that pins every other invocation to a *headed* browser. Headless mode is never used.

   **⚠️ Omitting `--headed` silently launches a throwaway browser instead of using the intended instance.** agent-browser falls back to its own isolated launch and creates a temp profile at `/tmp/agent-browser-chrome-<uuid>/`, headless (invisible). It looks like it worked — pages load, screenshots come back — but it is a different browser with **none of the real cookies/logins**, and nothing appears on the user's screen. Symptoms and detection:

   ```bash
   pgrep -af "user-data-dir=/tmp/agent-browser-chrome"   # >0 => a phantom exists
   ls -d /tmp/agent-browser-chrome-* 2>/dev/null         # leftover temp profiles
   ```

   If you see either, you (or an earlier call) dropped `--headed`: kill the phantoms (`pkill -f "user-data-dir=/tmp/agent-browser-chrome"`), delete the temp dirs, and **re-run the whole step with `--headed`** (plus the flow's binding flags, e.g. `--session <name> --pin-tab`) before trusting any result. Never "fix" it by continuing in the phantom — screenshots or verifications taken there are worthless.

3. **Isolate the profile by COPYING the folder — never share one user-data-dir between sessions.** Before a session launches or attaches to a browser, copy the whole source profile directory to a session-private path, then use the copy for every call:

   ```bash
   SESSION_PROFILE="/tmp/chrome-profile-${SESSION_NAME}"
   [ -d "$SESSION_PROFILE" ] || cp -a "$SOURCE_PROFILE" "$SESSION_PROFILE"
   agent-browser --headed --session "$SESSION_NAME" --profile "$SESSION_PROFILE" open about:blank
   ```

   - **Copy the ENTIRE directory, never a symlink and never selected files.** Chrome needs `Local State` (the `os_crypt` key that unwraps cookies under `--password-store=basic`), `Cookies`, `Login Data` and `Local Storage` — a partial copy loses the logins, and a symlink resolves to the same real path, so it keeps the exact singleton-lock collision the copy exists to prevent.
   - **Why it matters:** two Chrome instances pointed at one `user-data-dir` fight over `SingletonLock`/`SingletonSocket`; the loser's window disappears, a daemon relaunches a temp-profile browser, and the session silently ends up logged out on a profile nobody intended.
   - **Each session gets its own copy** (per run/ticket/session name) and keeps using it for the whole session — including every later attach, screenshot and upload. The copy is disposable; the source profile stays pristine.

4. **Do NOT use an isolated random `--session` in the default mode.** The whole point is to reuse the real browser's state, so creating an isolated context would defeat it. With `--auto-connect`, omit `--session` (or, if you must track multiple concurrent agent runs in the same browser, pass a short `--session` only as a logical grouping — it does **not** create a fresh cookie jar). The old "unique random session per task" rule only applies to the isolated-launch fallback (see [Fallback: isolated launch](#fallback-isolated-launch-when-you-cannot-use-the-real-browser)).

```bash
# Step 1 (once): confirm a debuggable Chrome is up (see "Attach checklist")
curl -s --max-time 2 http://127.0.0.1:9222/json/version

# Step 2: drive the ACTUAL browser — no --session, no fresh context
agent-browser --auto-connect --headed open https://example.com/form
agent-browser --auto-connect --headed snapshot -i
agent-browser --auto-connect --headed fill @e1 "user@example.com"
# Do NOT close the user's browser with `agent-browser close` in default mode.
# To disconnect without quitting Chrome, just stop issuing commands.
```

> **Note:** each Bash call is a fresh shell, so an env var or shell variable set in one call will NOT carry over to the next. Pass `--auto-connect --headed` (and `--session <name>` when needed) explicitly on every command. The browser itself persists between calls via the daemon, so the page state survives across invocations.

> **Never `agent-browser close` the user's real Chrome.** In default mode, `close` would quit the browser the user is actively using. Only disconnect your agent session (or simply stop issuing commands) when done.
>
> **Never close, navigate away from, or reload a tab the user had open before you started without explicit confirmation.** The user may have unsaved work in any tab (forms, drafts, code, chat). Before closing any existing tab or navigating an existing tab to a new URL, always ask: "You have [N] tabs open — I need to [close tab X / navigate tab X to Y]. OK?" and wait for a yes. If you opened the tab yourself, you may close it freely.
>
> **Prefer opening new tabs over reusing existing ones.** When you need to navigate to a URL, open a new tab (`agent-browser --auto-connect --headed open <url>`) rather than reusing a tab the user already had open. This preserves their work and is safer.

## Screenshot frugality

Don't take screenshots when text is sufficient. `snapshot` / `snapshot -i`
(accessibility tree, text) is the default read mode — cheap, fast, and
token-light. Only take a screenshot (`agent-browser screenshot`) when the
visual state actually matters: verifying a rendered layout, charts, an image,
or when the user explicitly asked to see something. A screenshot is never
needed to read text, check a status, or confirm a page loaded.

## Core Workflow

Every browser automation follows this pattern (defaults from above already applied):

1. **Ensure debuggable Chrome**: run the bootstrap helper once with the right profile
2. **Navigate**: `agent-browser --auto-connect --headed open <url>` (you're often already logged in — just open the page)
3. **Snapshot**: `agent-browser --auto-connect --headed snapshot -i` (get element refs like `@e1`, `@e2`)
4. **Interact**: Use refs to click, fill, select
5. **Re-snapshot**: After navigation or DOM changes, get fresh refs
6. **Disconnect**: stop issuing commands (do NOT `close` the user's browser)

```bash
# Step 1 (once): confirm a debuggable Chrome is running the right profile
curl -s --max-time 2 http://127.0.0.1:9222/json/version

agent-browser --auto-connect --headed open https://example.com/form
agent-browser --auto-connect --headed snapshot -i
# Output: @e1 [input type="email"], @e2 [input type="password"], @e3 [button] "Submit"

agent-browser --auto-connect --headed fill @e1 "user@example.com"
agent-browser --auto-connect --headed fill @e2 "password123"
agent-browser --auto-connect --headed click @e3
agent-browser --auto-connect --headed wait --load networkidle
agent-browser --auto-connect --headed snapshot -i  # Check result
# No close — the browser is the user's real Chrome.
```

## Command Chaining

Commands can be chained with `&&` in a single shell invocation. The browser persists between commands via a background daemon, so chaining is safe and more efficient than separate calls. `--auto-connect --headed` (and `--session <name>` when used) must still appear on every command in the chain (flags don't carry over between chained invocations).

```bash
# Chain open + wait + snapshot in one call (defaults applied)
agent-browser --auto-connect --headed open https://example.com && agent-browser --auto-connect --headed wait --load networkidle && agent-browser --auto-connect --headed snapshot -i

# Chain multiple interactions
agent-browser --auto-connect --headed fill @e1 "user@example.com" && agent-browser --auto-connect --headed fill @e2 "password123" && agent-browser --auto-connect --headed click @e3

# Navigate and capture
agent-browser --auto-connect --headed open https://example.com && agent-browser --auto-connect --headed wait --load networkidle && agent-browser --auto-connect --headed screenshot page.png
```

**When to chain:** Use `&&` when you don't need to read the output of an intermediate command before proceeding (e.g., open + wait + screenshot). Run commands separately when you need to parse the output first (e.g., snapshot to discover refs, then interact using those refs).

## Connect to Existing Chrome ← this skill's default

```bash
# This is the default mode: connect to the user's real Chrome (already logged in)
agent-browser --auto-connect --headed open https://example.com
agent-browser --auto-connect --headed snapshot

# Or with an explicit CDP port (the usual debug port is 9222)
agent-browser --cdp 9222 --headed snapshot
```

Auto-connect discovers Chrome via `DevToolsActivePort`, common debugging ports (9222, 9229), and falls back to a direct WebSocket connection if HTTP-based CDP discovery fails.

### Fallback: isolated launch (when you cannot use the real browser)

Only use this if `--auto-connect` is impossible (e.g., the user can't run a debuggable Chrome). It launches a **separate** Chrome with a `--profile` so login state persists across runs — but it is NOT the user's live browser, so it can still hit CAPTCHAs and may need a one-time login. This is the only mode that uses a unique random `--session` per task.

```bash
SESSION="ab-$(openssl rand -hex 4)"
# Separate user-data-dir so it never conflicts with the user's running Chrome
agent-browser --headed --session "$SESSION" \
  --profile ~/.agent-browser/profiles/isolated \
  --executable-path /usr/bin/google-chrome \
  --args "--no-first-run,--no-default-browser-check" \
  open https://example.com
agent-browser --headed --session "$SESSION" snapshot -i
# ... interact ...
agent-browser --headed --session "$SESSION" close   # closing this isolated instance is safe
```

Everything in the bundled reference (`agent-browser skills get core --full`) was written for the generic tool and often uses `--session`/`--profile`. In **this** skill's default mode, translate those examples to `agent-browser --auto-connect --headed …` and omit `--session`; reserve `--session`/`--profile` examples for the isolated-launch fallback only.

## Session Management and Cleanup

**Default mode (`--auto-connect`):** do NOT run `agent-browser close` — that would quit the user's real Chrome. Just stop issuing commands when you're done; the daemon stays attached to the user's browser harmlessly. If you absolutely must detach, use `agent-browser session list` to find your logical session name and `agent-browser --session <name> close` to release only that (this disconnects the agent, it does not quit Chrome).

**Fallback mode (isolated launch):** closing is expected and safe:

```bash
# Close the isolated session you launched with --profile
agent-browser --headed --session "$SESSION" close
# Nuclear option: shut down every session at once (ONLY in fallback mode — never on the user's real Chrome)
agent-browser close --all
```

If a previous isolated session was not closed properly, the daemon may still be running. Use `agent-browser close` to clean it up, or `agent-browser close --all` to shut down every session at once — but **verify first that you're not attached to the user's real browser** (check with `agent-browser session list` / `agent-browser get cdp-url`).

Daemons accumulate: per-session daemons (those created with an explicit `--session`) survive `--idle-timeout` and have been observed running for days. Run `agent-browser session list` periodically in long-lived flows and release the ones you own.

To auto-shutdown the daemon after a period of inactivity (useful for ephemeral/CI environments):

```bash
AGENT_BROWSER_IDLE_TIMEOUT_MS=60000 agent-browser open example.com
```

## Security

Most security features are opt-in. For the full model — page content as untrusted data, keeping secrets out of the model, staying on the user's target, init-script injection, network-interception artifacts — read `references/trust-boundaries.md` from the bundled reference (`agent-browser skills path core`).

### Content Boundaries (opt-in — turn them on for attach flows)

Content boundaries wrap page-sourced output in markers that help LLMs distinguish tool output from untrusted page content, mitigating indirect prompt injection:

```bash
export AGENT_BROWSER_CONTENT_BOUNDARIES=1   # or pass --content-boundaries
agent-browser snapshot
# Output:
# --- AGENT_BROWSER_PAGE_CONTENT nonce=<hex> origin=https://example.com ---
# [accessibility tree]
# --- END_AGENT_BROWSER_PAGE_CONTENT nonce=<hex> ---
```

### Domain Allowlist

Restrict navigation to trusted domains. Wildcards like `*.example.com` also match the bare domain `example.com`. Sub-resource requests, WebSocket, and EventSource connections to non-allowed domains are also blocked. Include CDN domains your target pages depend on:

```bash
export AGENT_BROWSER_ALLOWED_DOMAINS="example.com,*.example.com"
agent-browser open https://example.com        # OK
agent-browser open https://malicious.com       # Blocked
```

Note: the allowlist **rejects auto-connect** (and profiles, restore/state replay, raw profile-selecting startup args, iOS/Safari) because agent-browser cannot install equivalent containment before page scripts run. It requires a fresh, controllable browser context — so it is not usable in this skill's default attach mode.

### Action Policy

Use a policy file to gate destructive actions:

```bash
export AGENT_BROWSER_ACTION_POLICY=./policy.json
```

Example `policy.json`:

```json
{
  "default": "deny",
  "allow": ["navigate", "snapshot", "click", "scroll", "wait", "get"]
}
```

Auth vault operations (`auth login`, etc.) bypass action policy but domain allowlist still applies.

### Output Limits

Prevent context flooding from large pages:

```bash
export AGENT_BROWSER_MAX_OUTPUT=50000
```

## Diffing (Verifying Changes)

Use `diff snapshot` after performing an action to verify it had the intended effect. This compares the current accessibility tree against the last snapshot taken in the session.

```bash
# Typical workflow: snapshot -> action -> diff
agent-browser snapshot -i          # Take baseline snapshot
agent-browser click @e2            # Perform action
agent-browser diff snapshot        # See what changed (auto-compares to last snapshot)
```

For visual regression testing or monitoring:

```bash
# Save a baseline screenshot, then compare later
agent-browser screenshot baseline.png
# ... time passes or changes are made ...
agent-browser diff screenshot --baseline baseline.png

# Compare staging vs production
agent-browser diff url https://staging.example.com https://prod.example.com --screenshot
```

`diff snapshot` output uses `+` for additions and `-` for removals, similar to git diff. `diff screenshot` produces a diff image with changed pixels highlighted in red, plus a mismatch percentage.

## Browser Recovery (agent-owned browsers only)

**Boundary first:** never `pkill` or restart the **user's daily Chrome** — that requires explicit permission every time. This section applies only to agent-owned/isolated Chrome: browsers launched via `--profile`/`--session` (fallback mode) or a container/cage-managed Chrome.

### Automation hangs but Chrome process is alive

Symptom: `pgrep -f google-chrome` still shows Chrome, but every agent-browser call hangs or fails. Most common cause: a **GPU-process abort** tore down the rendering/automation channel while the main process lingered (GPU aborts surface as process exit 133 and can kill the DevTools listener without killing the browser).

Recovery — kill, clear locks, relaunch (persistent profile keeps logins):

```bash
pkill -9 -f google-chrome
pkill -9 -f chrome_crashpad_handler
sleep 3
rm -f <profile-dir>/Singleton* <profile-dir>/*.lock   # e.g. ~/.agent-browser/chrome/*
agent-browser --headed --profile <profile-dir> open <url>   # fresh launch on the same profile
```

Then re-verify before resuming work: navigate + `get url` matches, and a test `screenshot` succeeds.

### Chrome won't launch (display issues)

- **Keep `--headed` for anything user-visible** — headless is never a substitute; screenshots, tours, and human oversight all assume a visible window.
- **Displayless Linux hosts:** agent-browser starts Xvfb automatically; set `AGENT_BROWSER_NO_XVFB=1` only if you bring your own display.
- **macOS/X11 (containers):** Chrome needs X11 — `DISPLAY=host.docker.internal:0`, `xhost +` on the Mac (`/opt/X11/bin/xhost +`), and launch with `--ozone-platform=x11`. Plain launches without those crash ~10–15s in.

### agent-browser silently no-ops (empty stdout, exit 0)

Means the binary is missing or a wrapper points at a non-existent path — the daemon never started. Check `agent-browser --version` prints a real version; if empty, install first (`npm i -g agent-browser` on a writable prefix, or install from the npx cache into a wrapper like `~/.bin/agent-browser`). Run this check before any automation session — it's cheaper than debugging empty screenshots later.

## Version-Matched Reference (the generic docs)

This skill intentionally keeps **no** copy of the generic documentation. Use the CLI's own, which is always matched to the installed binary:

| What you need | Command / path |
| --- | --- |
| Full usage guide | `agent-browser skills get core` |
| Guide + complete command reference + templates | `agent-browser skills get core --full` |
| Live path (for `read`-ing the files directly) | `agent-browser skills path core` |
| Specialized skills | `agent-browser skills list` — `electron`, `slack`, `dogfood`, `webmcp-gen`, `vercel-sandbox`, `protected-vercel-deployments`, `agentcore`, `derive-client` |
| Flags reference | `agent-browser --help` |

The bundled `core` skill's `references/` covers: `commands.md` (every command and option), `authentication.md` (login, OAuth/SSO, 2FA, state reuse), `session-management.md` (parallel sessions, persistence), `snapshot-refs.md` (ref lifecycle, invalidation), `trust-boundaries.md` (safety model), `streaming.md`, `webgpu.md`, `profiling.md`, `proxy-support.md`, `video-recording.md`.

## Attach checklist: is a debuggable Chrome up?

There is no helper script — these checks are cheap, so run them yourself. All are read-only and
safe at any time. Work down the list; stop at the first one that answers.

**1. Resolve the profile alias.** Aliases map friendly names to Chrome profile directories in
whatever map the user keeps (an env file is the usual shape). Raw `Default` / `Profile N` work
directly too.

```bash
grep -v '^#' "$CHROME_PROFILES_MAP"    # <alias> -> <Profile N> …
```

**2. Is a debuggable Chrome already up?** The common case — if this answers, you are done.

```bash
curl -s --max-time 2 http://127.0.0.1:9222/json/version && echo READY
```

**3. Is Chrome running without the flag?** Then nothing here can fix it (see Outcomes). Zombies
do not hold the profile lock, so they do not count.

```bash
ps -C chrome -o pid=,stat= | awk '$2 !~ /^Z/'      # non-empty => CONFLICT
```

**4. Is the bind mount active?** If not, `~/.agent-browser/chrome` is an empty directory and
launching would give a **blank profile with none of the user's logins**. Refuse instead.

```bash
mountpoint -q ~/.agent-browser/chrome || echo "NOT MOUNTED — do not launch"
# repair: sudo mount --bind ~/.config/google-chrome ~/.agent-browser/chrome
```

**5. Does the profile directory exist under it?**

```bash
ls -d ~/.agent-browser/chrome/"Profile N"
```

**6. Which launcher carries the flag for this profile?** Only needed to tell the user exactly what
to click. Not every profile has a launcher; any that does not cannot be launched debuggably at all
today, so say so instead of retrying.

```bash
grep -l -- --remote-debugging-port ~/.local/share/applications/chrome-*.desktop
```

**7. Launch — only if steps 3, 4 and 5 all passed.** Chrome binds the port 1–2 s after launch, so
poll rather than assume.

```bash
google-chrome --remote-debugging-port=9222 --remote-allow-origins=* \
  --user-data-dir=~/.agent-browser/chrome \
  --profile-directory="Profile N" \
  --restore-last-session --no-first-run --no-default-browser-check &
for _ in $(seq 1 40); do curl -s --max-time 2 http://127.0.0.1:9222/json/version >/dev/null && break; sleep 0.5; done
```

### Outcomes

| Situation | What to do |
| --- | --- |
| Port answers (step 2) | **READY** — drive it with `--auto-connect`. |
| Chrome running, port dead (step 3) | **CONFLICT** — unfixable from here. Chrome allows one instance per profile, so a fresh launch only delegates to the running process and never opens the port. Ask the user to fully quit Chrome (all windows, every profile) and relaunch from the launcher named in step 6. Never `pkill` their Chrome. |
| Bind mount missing (step 4) | **BROKEN** — show the `mount --bind` repair command. Do not launch. |
| Profile dir missing (step 5) | **BROKEN** — the profile does not exist under the shared user-data-dir. |
| Unknown alias | **BROKEN** — add it to your profile map, or pass a raw `Profile N`. |
| Chrome fully closed, mount fine | **LAUNCH** using step 7. |
