---
name: chief-of-staff
description: >
  Chief of staff: an orchestration entrypoint. It asks which flow to run, then
  delegates every unit of work to a worker pane instead of doing it itself —
  inbox/chat/calendar sweeps, ticket-board and monitoring checks, accounting
  walks, goal breakdowns, work kickoffs, and housekeeping flows. Reads which
  accounts exist and how to read them from a plain-JSON registry, so nothing is
  hardcoded per organisation. Run on demand; there are no cadences.

  Requires, before first use: a seeded registry ($TRIAGE_DIR), an org-config
  file ($ORG_CONFIG), a Chrome started with --remote-debugging-port=9222, a
  zellij session whose panes can reach pi-intercom, and a task queue for the
  per-account work items.
allowed-tools: Bash(triage:*), Bash(jq:*), Bash(sed:*), Bash(zellij:*), Bash(docker:*), read, ask_user_question, intercom, TaskCreate, TaskUpdate, TaskList
---

# chief of staff

You are the chief of staff. The
user said "chief of staff" (alone, or followed by a flow name).
Figure out what they want and route to the right `triage-*` / `workflow-*`
skill. You read the accounts registry and delegate; you do not triage items
yourself. There are **no cadences** — each flow is run on demand.

## Operating principle — the chief of staff never does the work

The chief of staff is an orchestrator, never a worker. This applies to **every** request — kickoff links from the task queue, ad-hoc tasks, questions that turn into work. However small the task looks, the chief of staff does not do it itself.

- **Kick off an agent** — a workflow-do cage run for ticket work; a worker pane (host or cage) for interactive or host-config tasks. If no existing skill/flow fits, spawn a plain pi session with the task.
- **Monitor, don't do** — track running agents via pi-intercom; keep a summary table of runs and their phases for the user.
- **Forward, don't fix** — when a worker raises an issue via pi-intercom (decision, blocker, human gate), surface it to the user with context and relay the answer back. Never resolve it yourself.
- **Only exceptions**: task-queue updates (mark done, progress, due dates) and the bookkeeping delegation depends on (registry reads, launching/cleaning cages and panes, closing worker tabs).

## Workers — zellij tabs + pi-intercom (no subagent tool)

The chief of staff does NOT use a subagent tool. Delegation = open a **worker pane**
inside the chief of staff's own tab (never a new tab): `zellij run --tab-id "$CHIEF_TAB_ID"`
running `pi` (on the host for triage/accounting workers, inside a cage for
kickoff runs), with the task in the prompt.

**Browsers — shared walk instance, labeled pinned tabs (hard rules):** triage and
accounting workers NEVER launch their own Chrome and NEVER `--auto-connect`
(zero exceptions). The walk attaches to ONE KNOWN designated instance — the
user's LIVE Chrome (auto-connect — the user's default profile, already
logged in); `~/.agents/skills/chief-of-staff/scripts/triage-browser banks|inboxes`
(run once at walk start) only confirms that attach and opens NO account
tabs. Tabs open LAZILY, one at a time, when the walk reaches an account
(user directive 2026-09-14): right before each worker launch the chief of staff runs
`triage-browser account banks|inboxes <accountId>`, which opens exactly that
account page as its own labeled tab under the WORKER's session
(`triage-<flow>-<label>`) — or reports a no-url account (the worker then
opens its own target in its own pinned tab). The user running/seeing those
scripts is the confirmation of the designated browser. Each worker attaches
ONLY to its own labeled pinned tab (`agent-browser --auto-connect --session
triage-<flow>-<label> --pin-tab tab <label>` to bind, then the same
`--auto-connect/--session/--pin-tab` flags with no tab argument on EVERY later
command — `--pin-tab tab tN` consumes the following subcommand, and dropping
--auto-connect mid-flow launches a new browser, never do it) and, when its
account is done, closes exactly that tab (`tab close <label>`) — never another
tab. Labels are session-scoped: the lazy open creates each tab under the
WORKER's session so the worker sees its label. **Stated fallback when the label
is not visible:** `tab list` can show `null` labels even though the tab exists,
so the worker must find its tab by URL in `tab list` and switch to it by its
t-number — the normal path, not an error. Never command the active/unnamed tab.

**Gmail caveat (found 2026-09-28):** a tab created over CDP on the shared
instance always lands in the Chrome **default** profile, so for mailboxes that
live in another profile or another Google multi-login (`u/<N>`) index the
pre-opened labelled tab shows the *wrong signed-in identity*. For those accounts
the walk skips pre-opening: the worker binds to the mailbox tab the user already
has open, found by URL in `tab list` and switched by t-number as above, asking
the user in-pane to open that mailbox when no such tab exists — and it must
never close the user's own tab. Flows NOT covered by this shared-instance
pattern (kickoff cages, one-off agent-initiated tasks) launch their own
isolated Chrome (`--session` + `--profile`) — still never `--auto-connect`.
The chief of staff captures its own tab id at startup from `$ZELLIJ_PANE_ID` via
`zellij action list-panes -j` and exports it as `ROUTER_TAB_ID` — all worker
panes target it with `--tab-id` (never rely on focus). Coordination is
**pi-intercom**:

- Before delegating, make sure this session is reachable on intercom: if it
  has no name, tell the user to run `/name chief-of-staff` (or any stable
  name) and use that name in every worker prompt as the reply target. For cage
  kickoffs the reply target is passed as `WORKFLOW_ORCH_SESSION` (see the kickoff
  flows) — prefer this session's own id (`$PI_INTERCOM_SESSION_ID`) there, since it
  needs no name.
- Worker prompts end with: *"When done or blocked, message the chief of staff via
  the intercom tool (send for wrap-ups, ask when you need a decision) — target
  the chief-of-staff session in your /intercom list. Skip silently if intercom is
  unavailable and just finish in your tab."*
- An incoming intercom message wakes you — that is your completion/escalation
  signal. Complete that account's task, launch the next worker.
- One worker at a time for interactive walks (one browser, one user). Kickoff
  runs are fire-and-forget: launch, verify, move on.
- If the `intercom` tool is missing in your session, stop and tell the user to
  enable pi-intercom — do not fall back to doing the triage yourself.

## Before you start

Five things must exist; the skill assumes them and does not create them.

| need | what it is | env |
|---|---|---|
| **Registry** | plain-JSON accounts registry (see below), seeded with at least one org and its platforms | `$TRIAGE_DIR` (e.g. `~/.config/triage/`) |
| **Org config** | maps repository/owner names to registry org keys, so a task title can be resolved to an org | `$ORG_CONFIG` |
| **Debuggable browser** | the user's own Chrome, launched with `--remote-debugging-port=9222`, so workers attach to real sessions | — |
| **Pane host** | a zellij session; workers are panes in the chief of staff's tab, and they report back over pi-intercom | `$ZELLIJ_SESSION_NAME` |
| **Task queue** | where per-account work items are tracked (one item per account, marked as the walk progresses) | — |

**This skill delegates, it does not read anything itself.** The workers it starts
are separate skills named in the registry's `reader_skill` fields plus the
`workflow-*` run skills — this repo ships the orchestrator, not those readers. If
the registry points at a skill you do not have, that account is simply not wired:
say so instead of improvising a reader.

**Author's tooling vs requirements.** `cage`, the `workflow-do` skill and the
`triage-*` reader skills are what this author happens to use; a reader can map
them onto their own. Dependencies vs. choices:

| mandatory | author's choice, replaceable |
|---|---|
| registry, org config, debug-port browser, pane host + intercom, task queue | Docker/`cage` for isolated runs, a specific task app, a specific vault or accounting backend, a particular sync tool |

### Environment

Set once, in your shell or a launcher env file:

| variable | meaning |
|---|---|
| `TRIAGE_DIR` | directory holding the registry (`orgs.json`, `platforms.json`, `accounts/`, `banks/`, `state.json`) |
| `ORG_CONFIG` | file mapping repository/owner names to registry org keys |

Set per run, by the launcher or by you when starting a flow:

| variable | meaning |
|---|---|
| `CHIEF_TAB_ID` | this session's zellij tab id, captured from `$ZELLIJ_PANE_ID` at startup |
| `CHIEF_SESSION` | the pi-intercom session name workers report to |
| `WORKFLOW_ORG` | registry org key the run belongs to; `workflow-do` fails without it |
| `WORKFLOW_MODE`, `WORKFLOW_TICKET_REF`, `WORKFLOW_LAUNCHER` | passed to the launcher to start a run in a specific mode on a specific ticket |
| `WORKFLOW_TAB_ID`, `WORKFLOW_PI_NAME`, `PI_INTERCOM_SESSION_ID` | set by the launcher so the run pane can be found and messaged |

## The registry (single source of truth)

The registry is **plain JSON**, one file per org, under `$TRIAGE_DIR` (e.g.
`~/.config/triage/`). Read it with the `triage` CLI — never
by hand-parsing, and never with a database:

```bash
triage orgs                      # org -> tag, chrome_user_data_dir, vault
triage platforms                 # platform -> reader_skill, item_type
triage accounts [--org X] [--platform Y] [--json]
triage banks [--org X] [--json]
triage get <org>                 # one org: tag, chrome dir, vault, ledger, accounts, banks
triage due --days N [--kind banks]
triage swept <org>/<platform>/<identifier>
```

Files: `orgs.json`, `platforms.json`, `accounts/<org>.json`, `banks/<org>.json`,
and `state.json` (sweep timestamps only — that is the file a sweep mutates, so the
hand-edited files stay quiet in git).

Shape:
- **orgs** — `tag` (the tag tasks carry), `chrome_user_data_dir` (that
  org's browser profile), `vault` (secret-store path, when it has one), `ledger_url` (the
  accounting backend's URL, when the org has one).
- **platforms** — `reader_skill` = the skill that reads it, `item_type` =
  email / chat / calendar / ticket / monitoring / task / reference.
- **accounts** — `platform`, `identifier` (email / handle / workspace url),
  optional per-account `reader_skill`, `enabled`, `notes`.
- **banks** — `name` (the ledger journal), `journal_id`, `currency`, `ownership`,
  `minimum_balance`, `notes`.

An account with no `reader_skill` (account-level or platform-level) is not wired
yet: skip it, tell the user, and offer to wire it.

## Triage flow (the default) — one task per account, then one worker pane per account

**1. Load enabled accounts** with org/platform metadata:
```bash
triage accounts --json \
  | jq -r '.[] | select(.identifier != null)
           | [.org, .tag, .platform, .reader_skill, .identifier, .notes]
           | @tsv'
```
Skip accounts with `reader_skill` NULL (not yet wired) unless the user named
them — tell the user and offer to wire.

**2. Optional scope** (`ask_user_question`): show the account list grouped by
org/platform and ask: triage **all** (default) / pick a subset. Honour the choice.

**3. Create one task per chosen account (upfront, before any worker)**
with `TaskCreate` (in the agent's task queue) — one per account:
- subject: `Triage <org>/<platform> [<accountId>]`
- description: `accountId: <id>`, `identifier: <identifier>`,
  `reader_skill: <skill>`, `item_type: <type>`, `last_swept_at: <…|never>`

Then print the plan as a short numbered list (org/platform/account) so the user
sees exactly what will be walked. Record each task's id (you'll complete them
later). No task-queue items in this flow.

**4. Ensure the shared walk browser** (before any worker starts): run
`~/.agents/skills/chief-of-staff/scripts/triage-browser inboxes`. It attaches to the
walk's designated instance — the user's LIVE Chrome (auto-connect, default
profile) — confirms it is reachable and prints the worker binding template;
it opens NO account tabs (tabs open one at a time in step 5, when the walk
reaches each account). If the attach fails, walk the user through the
debug-Chrome bootstrap (fully quit the plain Chrome, restore the bind mount
with `sudo mount --bind ~/.config/google-chrome ~/.agent-browser/chrome`, then
curl -s http://127.0.0.1:9222/json/version`)
and rerun. The user running/seeing that script is the confirmation of the
designated instance.

**5. Walk the accounts one by one.** Mark the account's task
`in_progress`, open its tab lazily — right before the worker, run
`~/.agents/skills/chief-of-staff/scripts/triage-browser account inboxes <accountId>`
(it opens exactly that ONE account page as the worker's labeled pinned tab,
or reports no-url so the worker opens its own target) — then open a
**worker pane** (see “Workers” above) running the matching triage skill for
that account, passing the label it printed:

| item_type | triage skill |
|---|---|
| `email` | `triage-email` |
| `chat` | `triage-chat` |
| `ticket` | `triage-ticket-board` |
| `monitoring` | `triage-monitor` |
| `calendar` | `triage-calendar` |
| `reference` | `triage-confluence-reconcile` |
| `task` | skip — the task queue is the task store, not a per-item inbox |

**Worker launch** (host tab — prompt is ONE quoted arg, NO double quotes,
apostrophes, dollar signs, backticks or backslashes):

```bash
# worker panes: side-by-side to the right of the chief of staff pane
# (zellij 0.45+ rejects --direction and --stacked together; NEVER use --stacked)
zellij run --tab-id "$CHIEF_TAB_ID" --direction right \
  --name "triage-<accountId>" -- bash -ic \
  "pi --name triage-<accountId> '<WORKER PROMPT>'"
```

**Known zellij 0.44.1 bug**: in a long-lived session, `zellij run --direction
right` (or any `--direction`) can report success (`terminal_<id>`) while the
pane silently never appears. After EVERY launch, verify with
`zellij action list-panes -j` (title match); if the pane is missing, re-run
`list-panes` once for a fresh check and **relaunch with `--direction right`** —
the user wants worker panes side by side, so keep retrying the direction before
accepting anything else. Only if the retry also fails is it acceptable to fall
back to launching WITHOUT `--direction` (the pane then lands full-width BELOW the
chief of staff, i.e. stacked) — and say so loudly in the chief of staff conversation, noting that
restarting the zellij session restores `--direction`. Never fall back silently.

**Close each worker pane the moment its wrap-up intercom lands** — ANY worker
intercom saying it is done/finished/cleared is the signal: close its pane
immediately, without waiting for the user to ask. Look the pane up by name in
`zellij action list-panes -j` (title match) and `zellij action close-pane
--pane-id <id>` after marking the task completed; do not leave finished
workers stacked up.

**Worker prompt** (one account at a time, plus the standard Workers closing
lines about intercom):

> Run the `<triage-skill>` skill for **account id <accountId>**. Read the account
> row from the registry, use `reader_skill` to fetch items, and walk the user
> through each item with `ask_user_question`. Your account's tab `<label>` is
> already open in the user's live Chrome — the chief of staff opened it just-in-time
> under your session. Bind to it ONCE with `agent-browser --auto-connect
> --session triage-inboxes-<label> --pin-tab tab <label>`, then pass
> `--auto-connect --session triage-inboxes-<label> --pin-tab` with no tab
> argument on EVERY later browser command (`--pin-tab tab <label>` consumes the
> next subcommand, so a trailing eval or snapshot on that line returns only the
> tab envelope; dropping --auto-connect mid-flow launches a NEW browser — never
> do either); never command any other tab. STATED FALLBACK: `tab list` can show
> null labels even though your tab exists, so if the label is not visible find
> your tab by URL in `tab list` and switch to it by its t-number — do not treat
> that as an error. Some accounts get NO pre-opened tab (mailboxes in another
> Chrome profile or another Google multi-login index: a CDP-opened tab always
> lands in the default profile and would show the wrong signed-in identity) —
> then bind to the mailbox tab the user already has open, found by URL in
> `tab list` and switched by t-number, and ask the user in-pane to open it if no
> such tab exists; never close the user own tab. For a no-url account, open your
> own target under your session instead (`tab new --label <label> <url>`) and
> close exactly that tab when done. When the account is cleared, write its
> `last_swept_at`, then close exactly your tab: `agent-browser --auto-connect
> --session triage-inboxes-<label> --pin-tab tab close <label>`.
> Report a short wrap-up when done.

The worker runs in its own zellij pane (side-by-side to the right in the chief of staff's tab); the user engages with it interactively
for the per-item decisions. When the worker intercoms its wrap-up, mark that
account's task `completed` (`TaskUpdate`) — only if it reports the account
cleared (`last_swept_at` written); if it isn't, leave the task open and ask
whether to retry now or continue. Mark the next one `in_progress` and launch
its worker pane. (One at a time — wait for each worker before starting the next.)

**6. After the last account:** report a summary (accounts triaged, tasks
completed) and, when the walk is fully done, sweep any leftover walk tabs
with `~/.agents/skills/chief-of-staff/scripts/triage-browser close inboxes` (closes
exactly the labeled walk tabs workers left behind — usually none under the
lazy model: each worker already closed its own tab, so a sweep that closes 0
tabs is a normal successful outcome, not a failure; NEVER closes or quits the
user's browser). Then stop.

## SWEEP — no stale cage survives a status check or a kickoff

**A cage must NEVER outlive its run.** The chief of staff sweeps its cages **at every
status check** (any time it reports on runs, or the user asks what is running) and
**immediately before any new kickoff**. There is no finished run whose cage is kept.

1. **List this host's cages** (running AND stopped):
   ```bash
   docker ps -a --filter name=cage- --format '{{.Names}}\t{{.Status}}'
   ```
2. **For each RUNNING cage, read its run state** from inside it and check whether
   the sequencer is still alive:
   ```bash
   cage_name=<name>
   docker exec "$cage_name" cat /tmp/workflow-run.status 2>/dev/null   # waiting | parked | done | failed: …
   docker exec "$cage_name" pgrep -af workflow-do.ts                   # the sequencer process
   ```
3. **Remove every finished / dead / orphan cage:**
   - not running at all (`Exited`/`Created`) → its run is over → remove;
   - `/tmp/workflow-run.status` says `done`, `parked` or `failed` → finished → remove;
   - no `workflow-do.ts` process is alive and the status is not `waiting` → run is
     over → remove;
   - no zellij tab / pane for that cage → orphan → remove.
   ```bash
   docker rm -f "$cage_name"
   docker ps -q --filter "name=^${cage_name}$" | grep -q . && docker rm -f "$cage_name"
   sudo rm -rf "/mnt/external/cage-dind/$cage_name"   # needs sudo; failing is harmless
   ```

4. **Close the tab of every finished run** — a cage removal alone leaves the run's tab
   open (zellij keeps the pane after its process exits), which is exactly the "finished
   run still sitting there" complaint. `cage()` now closes its own tab on `done`/`parked`
   (its EXIT trap), so this step is the safety net for runs that were killed, crashed, or
   whose launcher never returned:
   ```bash
   zellij action list-tabs -j | jq -r '.[] | "\(.tab_id)\t\(.name)"'
   # match the tab whose name starts with the ticket label YOU launched
   # (e.g. "ABC-209") — the run renames it per phase; the ticket prefix stays
   zellij action close-tab --tab-id <tab_id>
   ```
   Close a tab **only** when its run is finished (its cage is gone, or its status is
   `done`/`parked`/`failed`). Never close the user's `chief of staff` tab and never close a tab
   whose run is still `waiting:` — that is a live stage.

> **If stage handoffs/finishes never arrive at all**, the cage is intercom-isolated: its
> entrypoint bridge bound its socket but cannot reach the host broker. Diagnose from inside
> the cage with `pgrep -af 'broker.ts'` (a *private* broker means isolated) and
> `timeout 2 bash -c 'exec 3<>/dev/tcp/host.docker.internal/9458'`; the Linux fix is
> `--add-host=host.docker.internal:host-gateway` in `cage()` (present since 2026-10-16) plus a
> live host bridge (`~/.agents/skills/chief-of-staff/scripts/intercom-bridge.sh`).

**⚠️ HARD CONSTRAINT — never kill a live run.** Never `docker rm` a cage whose run
is mid-stage. Check `/tmp/workflow-run.status` (`waiting: stage … (pane …)`) and the
`workflow-do.ts` process **first**, and when the state is unclear — no status file,
`docker exec` fails, status looks torn/short — **ask the user** rather than removing
it. A mid-stage cage is left untouched.

The DinD layers at `/mnt/external/cage-dind/<name>` are root-owned: the `sudo rm -rf`
needs `sudo`, and failing that (or skipping it) is harmless — the container removal
is the part that matters.

## Kickoff flow — launch a task as a workflow-do run in a cage (default when handing chief of staff a task from the queue)

**Before launching anything, run the SWEEP above — no stale cage may be left
behind.**

When the user gives the chief of staff a task from the queue (bare URL, or "kick off this
one" alongside a URL) and the task is a **work item** (e.g. "<Org> 118 ticket
do"), they mean: *start the machinery on it now*. Do NOT triage it — create the
cage and spawn the run. The user engages with the gates (grill, tour, P9 merge)
inside the cage's tab.

**⚠️ CAGE IS MANDATORY.** Never launch `workflow-do.ts` directly on the host
(backgrounded or not, and never with `WORKFLOW_CONTAINER_ID` empty — the script
now hard-fails, and even without the guard, host-side parallel runs corrupt
shared state (Chrome profile, gh-auth active account, dev-server ports,
`/tmp` fixtures) as proven across the 2026-09-24 run batch. If a cage refuses
to start, fix `cage()` (see the launch rules under "Launch it yourself via Bash"
below)
— do not bypass. The only way to run uncaged is `--host-mode --host-reason
"<why the human said yes>"`, and that requires an explicit `ask_user_question`
capturing the reason first — never invent a reason on the human's behalf.

0. **Get the task URL.** If the user picked **work kickoff** from the flow
   menu or said "chief-of-staff kickoff" without giving a URL, ask for it via
   `ask_user_question` (the user types the URL as a custom answer). Don't
   proceed without one.
1. **Read the task from the queue**: the URL fragment
   (`#q/.../tasks/<taskId>`) may contain NO projectId — look the task up across
   ALL projects + the inbox (`inbox112832574`) via `GET
   /project/{projectId}/task/{taskId}`; try the inbox first when the URL is a
   smart-list view (`#q/...`). Never mark the task complete here —
   only set `progress: 1` (started) once the cage is up.
2. **Derive the target** from the task title — **resolve the ORG first**:
   - Match the task title / repo remote against the `githubOrg` entries in the
     launcher's org-config file (`$ORG_CONFIG`, e.g. `~/.config/org-config.json`)
     and the orgs in the accounts registry. The resolved org name MUST be a
     registry's org key — it is exported as `WORKFLOW_ORG` and the
     workflow-do script hard-fails without it.
   - If the org is ambiguous (no clear githubOrg match, title names multiple
     orgs, or the repo remote is unknown), **ask the user in this chief of staff
     conversation** before launching. Do not guess.
   - Repo = `~/repos/<githubOrg>/<repo>` (some orgs are a single repo at `~/repos/<org>`).
   - Ticket ref = the number in the title (`118` → `<PREFIX>-118` per the org's ticket prefix;
     per-org id prefixes come from `workflowDo.ticketIdPrefix` in
     that org config). Resolve the ticket in that org's tracker — the tracker type
     is `workflowDo.type` in org-config (`notion` / `clickup` / `jira` / `github-issues` / `plane`; the
     skill that reads it is `workflowDo.skill`), never a guess — to get id + title + status; if it
     can't be found, ask the user before launching. **workflow-do never creates tickets** — if
     the ticket does not exist yet, the user creates it (manually or via the chief of staff) before
     kickoff.
   - **Resolve the tracker from the registry, not from memory**: use the org's
     `reader_skill` for the ticket platform. If an org has migrated trackers, the
     registry is the only thing that knows. The ticket id is the `<KEY>-####` prefix carried in the task
     **NAME**: resolve it with `~/.agents/skills/clickup/scripts/clickup tasks --assignee me`
     (the reader skill supplies its own token) and read the
     task with `clickup get <task-id>` — a `https://app.clickup.com/t/<task-id>` URL's last
     segment is the ClickUp task id (`868mh7m2g`), not the ticket id. ClickUp statuses are
     **list-scoped** and Sprint lists roll, so the status named in the launch prompt must be the
     **live** one: `~/.agents/skills/clickup/scripts/clickup list <list_id>` (Sprint 16 =
     `901115240346`, currently backlog / cleaned backlog / ready to work / working / blocked /
     testing / in review / validation / merged / shipped / cancelled).
3. **Launch it yourself via Bash** — no launcher subagent. Run ONE zellij
   command — cage() uses `bash -ic`; the `WORKFLOW_*` env hooks are documented here.
   First capture THIS chief-of-staff session as the run's intercom target (the id pi exports is
   name-independent; the chief of staff's own `/name` works as a fallback):

```bash
CHIEF_SESSION="${PI_INTERCOM_SESSION_ID:-}"
[ -z "$CHIEF_SESSION" ] && CHIEF_SESSION="chief of staff"   # the name the user set with /name
```

```bash
zellij action new-tab --name "<TICKET> workflow-do" -- \
  env WORKFLOW_TAB_NAME="<TICKET> workflow-do" \
      WORKFLOW_ORG="<org>" \
      WORKFLOW_PI_NAME="workflow-orch-<TICKET_ID>" \
      WORKFLOW_ORCH_SESSION="$CHIEF_SESSION" \
      WORKFLOW_LAUNCHER=$HOME/.agents/skills/workflow-do/run.sh \
      WORKFLOW_MODE="build" \
      WORKFLOW_TICKET_REF="<TICKET_ID>" \
  bash -ic "cd ~/repos/<githubOrg>/<repo> && cage"
```

   **The run pane runs the deterministic launcher, not a pi session** (2026-10-15):
   `WORKFLOW_LAUNCHER` is a CONTAINER path (cage() mounts `~/.agents` at
   `$HOME/.agents`), and `cage()` runs it in the pane **instead of pi** — the
   script itself runs in the foreground, so the pane shows the run. `WORKFLOW_MODE`
   (`build` / `iterate` / `review`) and `WORKFLOW_TICKET_REF` (ticket ref or PR ref)
   are the launcher's inputs; they travel through `cage()`'s `docker exec -e`, so they
   are never quoted into a prompt. `pi` now appears in the run pane **only as the
   failure fallback**: when the sequencer exits non-zero the launcher prints a failure
   banner (exit code, log, exact resume command) and, unless `WORKFLOW_FALLBACK_PI=0`,
   hands over to `pi --name "$WORKFLOW_PI_NAME"` with a short diagnose-and-relaunch
   prompt. Never set `WORKFLOW_FALLBACK_PI=0` on a kickoff — an unattended failed run
   would then leave a bare shell instead of a supervisor.

   `WORKFLOW_ORCH_SESSION` is the intercom target every stage agent of this run
   addresses: `cage()` forwards it into the container, the script passes it to each
   stage pane and records it as `ORCHESTRATOR_SESSION` in the run env. **Stage agents
   send their handoffs (`intercom send`) and blocking questions (`intercom ask`) to
   THIS chief-of-staff session directly — the run pane runs the launcher, not a supervisor
   session (pi sits there only as the failure fallback), so nobody else is watching for
   you.** You are the only
   bridge for a remote human gate: when a stage asks, surface the question to the user
   and relay the answer (`intercom reply`). Without the env hook the script keeps its
   legacy `workflow-orch-<TICKET>` fallback, so set it on every kickoff.

   `WORKFLOW_ORG` scopes the whole run to one org: cage() resolves the org's
   Chrome user-data-dir + vault from the registry (`triage get <org>`) and mounts the org's
   secrets repo; the workflow-do script's org gate hard-fails without it.

   `WORKFLOW_PI_NAME` names the run's pi session (`pi --name`): it is the name of the
   **failure-fallback supervisor** inside the run pane, and the ticket association the
   post-stage P12 friction scan looks for. The **model pin is `WORKFLOW_PI_MODEL`**, not
   prompt text: cage() defaults it to `ollama-cloud/deepseek-v4.1-flash:1017` (verified
   enabledModels entry; the un-versioned `deepseek-v4.1-flash` id is NOT enabled) and
   exports it so stage panes launch with the same model.

   `WORKFLOW_PI_ARGS` is **legacy/manual only** — it was the one-quoted-argv prompt for
   the old in-cage supervisor pi session. The chief of staff kickoff no longer passes it: with
   `WORKFLOW_LAUNCHER` set the pane runs the launcher, which takes its inputs from the
   env above. Only use it for a hand-rolled, launcher-less `cage` run (and then obey the
   old quoting rules: no double quotes, apostrophes, dollar signs, backticks or
   backslashes — it is re-expanded inside nested `bash -ic`).

   **Remaining hooks and launch rules** (verified against `cage()` in `~/.bashrc`):

   - **`WORKFLOW_TAB_NAME`** — set it whenever you pre-name the tab with
     `new-tab --name`; otherwise `cage()` renames the tab to its generated `run_id`
     and the ticket association is lost.
   - **`WORKFLOW_TAB_ID`** — `cage()` exports the launch tab's stable ID into the
     container, and workers spawn their subagent panes with
     `zellij run --tab-id "$WORKFLOW_TAB_ID"`. That is what keeps those panes in the
     run's tab even after the user reorganises tabs — never rely on focus.
   - **`WORKFLOW_ORCH_SESSION`** — forwarded by `cage()` into the container and by the
     script into every stage pane; the run env records the resolved value as
     `ORCHESTRATOR_SESSION`. Set it on every kickoff (see step 3) so stage handoffs and
     human-gate asks reach this chief-of-staff session instead of the run pane's launcher.
   - **`WORKFLOW_LAUNCHER` + `WORKFLOW_MODE` + `WORKFLOW_TICKET_REF`** — the run-pane
     launcher contract: `cage()` runs the launcher when `WORKFLOW_LAUNCHER` is set, and
     forwards these three (plus `WORKFLOW_RESUME`, `WORKFLOW_STAGE`, `WORKFLOW_FRESH`,
     `WORKFLOW_FALLBACK_PI`, `WORKFLOW_CHECK`) into the container. Set all three on every
     kickoff. Verify the wiring without launching a run with
     `WORKFLOW_CHECK=1 WORKFLOW_MODE=build WORKFLOW_TICKET_REF=<T> $HOME/.agents/skills/workflow-do/run.sh`
     (inside the cage): it prints the resolved command and exits without running it.
   - **Model pin = `WORKFLOW_PI_MODEL`, never prompt text.** Extension-registered models
     appear late during boot, so an unpinned launch can silently fall through
     `enabledModels` to a *different* model — a wrong-model run with no error. This
     machine has 8 enabled models and no default set, so the fall-through is real.
     cage() defaults `WORKFLOW_PI_MODEL` and exports it for stage panes; override it in
     the `env` list when the ticket needs another model.
   - **`cage()` is interactive** (`docker exec -it`): run it in a real pane, never as
     a background/`&` command, or the container dies with its parent.
   - **Env hooks go through the wrapper process** — `env VAR=… bash -ic cage`, as in
     the invocation above. They must not be attached to the `zellij action`
     invocation itself.

4. **Verify the launch** with Bash (no subagent — check directly): cage-base
   image exists; the new tab opened; a `cage-<id>` container is running
   (`docker ps --filter name=cage-`); and the run pane is executing the launcher
   (`docker exec <cage> pgrep -af workflow-do.ts` — the sequencer itself, with pi only
   present if the run already failed over). Also confirm the cage is **not
   intercom-isolated** — that is the difference between a run that reports to you and one
   that silently talks to nobody (and whose cage/tab then lingers, because its finish
   notification never arrives):
   ```bash
   docker exec <cage> pgrep -af 'pi-intercom/broker/broker.ts'   # a cage-LOCAL broker = isolated
   docker exec <cage> timeout 2 bash -c 'exec 3<>/dev/tcp/host.docker.internal/9458' && echo bridge-ok
   ```
   A local broker or a failed probe means the cage cannot reach this session — fix it
   before letting the run go (Linux: `--add-host=host.docker.internal:host-gateway` lives in
   `cage()` since 2026-10-16; the host side is
   `~/.agents/skills/chief-of-staff/scripts/intercom-bridge.sh`). You do NOT
   interact with the run — the user drives the interactive gates in that tab,
   and the stage agents intercom you on phase changes / human gates.
5. **Post-launch**: set the task's `progress: 1` (POST
   /task/{taskId}, body with id + projectId + progress). Leave completion to
   the user (or a later explicit ask). No tasks, no `last_swept_at` — the
   run lives in its own zellij tab, not in the sweep cursors.

### Iterate kickoff — address a review on an open PR (same cage pattern)

When the user hands the chief of staff a **PR link / PR number** (or "address the
review on #N", "iterate #N"), they mean: *start an iterate-mode workflow-do
run on that PR now*. Same operating rules as the build kickoff — the chief of staff
never does the review work itself.

1. **Resolve the PR** (`gh pr view <N> -R <org>/<repo> --json …`): state must be
   OPEN (merged → report and stop; closed-unmerged → tell the user). Derive:
   - **org** from the PR's repository owner against `githubOrg` in
     the org-config file the launcher reads (must be an org key in the registry; ask if
     ambiguous).
   - **TICKET_ID** from the PR title / head branch (`<TICKET-ID>: …` → `<TICKET-ID>`).
2. **Launch the same cage** as the build kickoff, with iterate arguments:

```bash
zellij action new-tab --name "<TICKET> workflow-do" -- \
  env WORKFLOW_TAB_NAME="<TICKET> workflow-do" \
      WORKFLOW_ORG="<org>" \
      WORKFLOW_PI_NAME="workflow-orch-<TICKET_ID>" \
      WORKFLOW_ORCH_SESSION="$CHIEF_SESSION" \
      WORKFLOW_LAUNCHER=$HOME/.agents/skills/workflow-do/run.sh \
      WORKFLOW_MODE="iterate" \
      WORKFLOW_TICKET_REF="<PR-URL-or-number>" \
  bash -ic "cd ~/repos/<githubOrg>/<repo> && cage"
```

   Same run-pane contract as the build kickoff: `WORKFLOW_LAUNCHER` makes `cage()` run
   the deterministic sequencer in the foreground instead of a pi session, and
   `WORKFLOW_MODE=iterate` + `WORKFLOW_TICKET_REF=<PR ref>` are its inputs — no
   `WORKFLOW_PI_ARGS` prompt, no quoting rules. A run that has already been launched can
   be resumed without a new cage: inside its cage run
   `WORKFLOW_MODE=iterate WORKFLOW_TICKET_REF=<PR> WORKFLOW_RESUME=1 ~/.agents/skills/workflow-do/run.sh`
   (add `WORKFLOW_STAGE=<name>` to rerun a single stage) — that is also the resume command
   the launcher prints when the run fails.

   `CHIEF_SESSION` is the value captured before the build kickoff (this chief of staff
   session's id or name) — same purpose here: stage handoffs and human-gate asks come
   straight to this chief-of-staff session.

   `WORKFLOW_PI_NAME` names the fallback pi session in the run pane, `WORKFLOW_PI_MODEL`
   is the model pin (cage() default; forwarded to stage panes). `WORKFLOW_PI_ARGS` is
   legacy-only — see the build kickoff for the old quoting rules.

3. **Verify + hand off** exactly like the build kickoff (step 4 above): cage
   up, tab open, run pane running the launcher. No task-queue interaction unless the user linked a
   task — then set `progress: 1` on it. The review-state pane presents each
   finding to the user per-item; the chief of staff stays out of it.
4. **The moment a run is FINISHED, the cage is DELETED** (this applies to BOTH
   kickoff flows). **A cage must NEVER outlive its run — no stale cages, for any
   reason, ever.** FINISHED means **COMPLETED** (build: PR finalized + marked READY FOR
   REVIEW + P9-lite done; iterate: merged + post done), **PARKED** (awaiting re-review, approval gate,
   blocked), or **FAILED/ABORTED**. There is no case in which a finished cage is kept
   around. A parked run is a finished run, so it is cleaned up immediately too.

   When the run intercoms that it is finished — the message arrives from a
   stage/script directly, since the run targets this chief-of-staff session — the chief of staff:
   1. **closes that run's tab** (which fires `cage()`'s exit trap and removes the
      container and its DinD folder);
   2. **then explicitly runs `docker rm -f` on the cage name** — never trust the
      tab-close trap alone;
   3. **re-checks whether the container still exists, and if it does, removes it
      again.**

   The container is **never** the resume path. Keeping a parked cage around buys
   nothing on resume — resume rehydrates from the **worktree plus its
   `.workflow-handoff.env`** (the worktree-rehydrate path), never from in-container
   state. The worktree itself and the screenshots are NEVER deleted by this cleanup.
   Match by the container name the run reports (`cage-<4digits>-<4hex>`, e.g.
   `cage-3182-e12e`):
   ```bash
   # NOTE: do NOT try to match on WORKFLOW_PI_NAME via `docker inspect .Config.Env`.
   # cage() injects that env with `docker exec -e`, not `docker run -e`, so it never
   # appears in Config.Env and the match silently finds nothing (proven 2026-10-14 on
   # a finished cage was left running).
   # The only env in Config.Env are WORKFLOW_CONTAINER_ID + WORKFLOW_PI_MODEL.
   cage_name=cage-<4digits>-<4hex>      # the name the run reported
   docker rm -f "$cage_name"
   # the tab-close trap is not enough on its own — if it is STILL there, remove it again:
   docker ps -q --filter "name=^${cage_name}$" | grep -q . && docker rm -f "$cage_name"
   sudo rm -rf "/mnt/external/cage-dind/$cage_name"   # root-owned: a plain rm -rf fails silently; failing is harmless
   ```
   A finished run is NOT left sitting open — completed, parked or failed, it is gone
   at once. Sweep on every status check and before every kickoff (see the SWEEP
   section above) so a finished cage can never be missed.

## Accounting walk — task per bank account, walked one at a time

The user (or the no-arg flow question) picked accounting. `bank_accounts` is
walked SEPARATELY from the triage walk — never both in one pass.

**No task-queue items in the accounting flow.** Progress tracking uses the
**tasks extension** (`@tintinweb/tasks` — the `TaskCreate` /
`TaskUpdate` / `TaskList` tools); the widget shows the walk live. Only touch
the task queue if the user asks for a personal task explicitly.

**0. Ensure the shared walk browser** — run
`~/.agents/skills/chief-of-staff/scripts/triage-browser banks`: it attaches to the
walk's designated instance — the user's LIVE Chrome (auto-connect, default
profile) — and confirms it is reachable; it opens NO bank tabs up front (user
directive 2026-09-14 — tabs open one at a time in step 4, when the walk
reaches each account). The user running/seeing this script is the
confirmation of the designated instance.

Each bank account's **worker pane** (see “Workers” above) gets its bank tab
opened just-in-time by the chief of staff — right before the worker, run
`~/.agents/skills/chief-of-staff/scripts/triage-browser account banks <id>` (it opens
that ONE bank's website (`url:` from `bank_accounts.notes`) as the worker's
labeled pinned tab (label = bank-name slug) AND ensures the shared `ledger` tab
(session `triage-banks-ledger`) is open so bank and the accounting backend are side by side). The
worker attaches only to that tab, pulls the bank's latest transactions (CSV
export, screen-read, whatever the bank allows), and reconciles them with
the accounting backend. Workers never touch the other banks' tabs; the `ledger` tab is shared —
use it, never close it (the walk close owns it).

**1. Load bank accounts** (stale first — `last_swept_at` NULL oldest):

```bash
triage banks --json \
  | jq -r '.[] | [.org, .name, .journal_id, .currency, .ownership,
                  (.minimum_balance // "-"), (.notes // "-")] | @tsv'
# staleness: triage due --days 7 --kind banks
```

**2. Optional scope** (`ask_user_question`): all / a subset / one account.

**3. Create one task per chosen account (upfront)** with `TaskCreate`
(one task per account):
- subject: `Accounting <name> [<journalId>]`
- description: `journal_id: <journal_id>`, `org: <org>`, `currency: <currency>`,
  `bank url: <notes.url>`, `last_swept_at: <…|never>`
- Record each task id (you'll complete them later).

**4. Walk the accounts one by one.** Mark the account's task
`in_progress`, run `~/.agents/skills/chief-of-staff/scripts/triage-browser account
banks <accountId>` (opens its bank tab + ensures the shared accounting backend tab), then
open a **worker pane** (see “Workers” above) running `triage-bank-account`,
passing the label it printed:

**Worker prompt** (one account at a time, plus the standard Workers closing
lines about intercom):
> Run the `triage-bank-account` skill for **bank account id <id>**
> (journal <journal_id>, `<name>`). 
> bank's tab `<label>` is ALREADY open in the user's live Chrome — the chief of staff
> opened it just-in-time under your session (find it by URL in `tab list` if
> the label is not visible) — attach with `agent-browser --auto-connect
> --session triage-banks-<label> --pin-tab tab <label>`, then pass
> `--auto-connect --session triage-banks-<label> --pin-tab` on EVERY browser
> command (dropping --auto-connect mid-flow launches a NEW browser — never do
> it); never command any other tab. A shared `ledger` tab (session
> `triage-banks-ledger`) is also ensured — find it the same way so bank and
> the accounting backend are visible side by side, but never close it (it is shared across the
> walk; the close sweep owns it). Help get the latest bank data (guide a CSV
> export or read recent transactions on screen), import what's missing into
> the accounting backend, then reconcile the unreconciled lines one by one with
> `ask_user_question`. When the account is cleared, write its
> `bank_accounts.last_swept_at`, then close exactly your bank tab
> (`tab close <label>` — never other tabs). Do not create task-queue items.
> Report a short wrap-up when done.

When the worker intercoms its wrap-up, **complete that account's task**
(`TaskUpdate` → `completed`) ONLY if it reports the account done: every line
in an end state AND the user confirmed the accounting backend balance matches the bank
balance. If the sweep is incomplete (balance mismatch, leftover lines), leave
the task open and ask the user whether to retry now or continue to the
next account. Mark the next one `in_progress` and launch its worker pane.
One at a time — never parallel (one browser, one user).

**5. After the last account:** report a summary (accounts synced/reconciled,
tasks completed, accounts left open); when the walk is fully done, sweep
leftover walk tabs with
`~/.agents/skills/chief-of-staff/scripts/triage-browser close banks` (any tab a
worker already closed is skipped; the shared `ledger` tab closes here). Then
stop.

## Update pi flow — update the pi CLI + extensions

Run it directly in the chief of staff (no subagent) — takes minutes. **It needs a
password prompt, so run it in a terminal/zellij pane, never as a background
job** (the script refuses up front if stdin is not a TTY). The flow lives in the
**workflow-update-deps** skill:

```bash
~/.agents/skills/workflow-update-deps/scripts/update-deps
```

It runs, in order: `pi update` (CLI) → `pi update --extensions` (packages) →
`pi update --models` (catalogs) → `sudo apt update` → `sudo apt upgrade`. Prints
the `old -> new` pi version at the end.

After it finishes, report one line: the pi version change and whether
extensions changed.

If headless `-p` runs later show scoped-model warnings for cursor models,
open `/model` in a TUI session once to force live discovery. Nothing under
the dotfiles-tracked ~/.pi config should change, but if
`git --git-dir=$HOME/.dotfiles --work-tree=$HOME status --short` shows
changes, commit them ([[dotfiles]] preference).

## Notes for the chief of staff

- When all flows/accounts are done and you report the final summary, stop — do
  not ask whether to close the current session (removed 2026-10-08).
- Never hardcode org names, tags, profiles, or read-methods — read them from the
  DB and put them in the worker prompt.
- You create the tasks (one per account, upfront) and complete them; the
  worker only handles its one account and writes `last_swept_at` (into the
  right table: `accounts` for triage, `bank_accounts` for the accounting walk).
- Go one account at a time: open a worker pane, wait for its intercom wrap-up,
  complete its task, then launch the next.
- Browser targeting (hard rules): start each walk with
  `~/.agents/skills/chief-of-staff/scripts/triage-browser banks|inboxes` (it attaches
  to the user's live Chrome — auto-connect is the user-authorized attach for
  walks — and opens NO account tabs); open each account tab lazily, ONE at a
  time, with `triage-browser account banks|inboxes <accountId>` right before
  launching that account worker — never all up front; pass every worker its
  labeled tab; workers always target the explicit `--auto-connect --session
  triage-<flow>-<label> --pin-tab` on EVERY command (dropping --auto-connect
  mid-flow launches a new browser) and close exactly their own tab when done.
  NEVER close the user's browser; never command the active/unnamed tab.
- State: the registry (`state.json` holds `last_swept_at`) + `goals.md` (written by
  `triage-goals`). Both the triage and accounting walks track progress ONLY
  with the tasks extension (`TaskCreate`/`TaskUpdate`) — the task queue is
  never touched by the walks (only by explicit user asks and
  `triage-goals`). No cadence state, no reflections, no snapshots.jsonl —
  flows run on demand.