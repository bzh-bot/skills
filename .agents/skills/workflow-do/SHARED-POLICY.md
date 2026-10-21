# Shared Policy — every workflow-do worker

This file is the single source of truth for policy that applies to ALL
workflow-do group workers (prebuild, build, tour, ship, post). The
orchestrator (workflow-do) also follows it.

**FIRST ACTION before any phase work:** read this file fully and follow it
for the entire run. Do not skip sections — the Hard Prerequisites are gates.

## Script-Owned Detection & Mechanics (v8 — authoritative)

The following are computed by `workflow-do.ts` and recorded in
`/tmp/workflow-run.env` (or `/tmp/workflow-project-profile.md`). Stage agents
**read them — never re-derive**. If a script-detected value disagrees with
reality, derive the correct value ONCE, append it to the run env, and record a
loose end:

- **Context detection (before prebuild):** `ORG`, `REPO_ROOT`, `REPO_NAME`,
  `GITHUB_ORG`, `INTEGRATION_BRANCH`, `PKG_MGR`, `HAS_FRONTEND`/`FRONTEND_DIR`,
  `BACKEND_DIR`, `IS_MONOREPO`, `HAS_VERCEL`, `HAS_GH_ACTIONS`, `HAS_CIRCLECI`,
  `HAS_JENKINS`, `HAS_SUPABASE`, `HAS_DATADOG`, `PROJECT_PROFILE_FILE` (detected
  vars + package.json scripts dump).
- **Reviewer resolution (before ship-p8):** `REVIEWERS` + `REVIEWERS_DECISION`
  ("requested"/"skip") from the org's `reviewers.json`. Missing config = FATAL
  before the pane spins.
- **Run stats (at every park/done):** `TOKEN_TOTAL`, `TOKEN_INPUT`,
  `TOKEN_OUTPUT`, `COST_TOTAL`, `HUMAN_PROMPT_COUNT`, `TIME_TAKEN_MINUTES`,
  `RUN_ENDED_AT_EPOCH` (plus `RUN_SESSION_DIR` + `RUN_STARTED_AT_EPOCH` recorded
  at run start). Post (P13) reads them; its jq scan is only a pre-v8 fallback.
- **Pre-launch input verification:** each stage's input vars (e.g. `PR_NUMBER`,
  `ORG`, `REPO_NAME`) are verified BEFORE the pane launches — fail-fast replaces
  the in-skill `PR_NUMBER` guards.
- **CI wait (after build-fix):** the script polls CI green before review-state
  classifies (timeout: `WORKFLOW_CI_TIMEOUT`, default 600s; on timeout it
  continues and review-state classifies).
- **GitHub repo slug is `GH_REPO`, NOT `$ORG/$REPO_NAME`** (learned 2026-10-06,
  <KEY-145>): `ORG` is the org KEY (`<org>`) and doubles as the *worktree path* segment,
  while the GitHub org slug is `GITHUB_ORG` (`<github-org>`) — both are already in the
  run env. `gh … --repo "$ORG/$REPO_NAME"` therefore 404s on every call, which cost
  the ship-P10 stage of <KEY-145> a re-derivation of the slug from the origin remote.
  Every stage that touches GitHub must
  `export GH_REPO="${GITHUB_ORG:-$ORG}/$REPO_NAME"` and use `$GH_REPO` in every `gh` /
  `gh api` / GraphQL call (`-F owner="$GITHUB_ORG" -F name="$REPO_NAME"`) and every
  script that takes a repo slug (`fold-pr-body.sh`, `upload-screenshot.sh`). Keep
  `$ORG/$REPO_NAME` only for worktree paths (`$HOME/worktrees/$ORG/$REPO_NAME/…`).
  Prefer the run env's `GITHUB_ORG` over re-deriving the slug from the git remote.
  **Export the TOKEN too, not just the slug** (learned 2026-10-07, <KEY-200>): `GH_REPO` alone is not
  enough. The run env carries the token under an *indirect* name (`GH_TOKEN_ENV="GH_TOKEN_<account>"`),
  so a bare `gh pr view 303 --repo "$GH_REPO"` dies with `GraphQL: Could not resolve to a Repository
  with the name '<github-org>/<repo>'` — which reads like a wrong repo slug and sends you chasing
  `GITHUB_ORG`. Any shell that touches GitHub must start with:
  `export GH_TOKEN="${!GH_TOKEN_ENV}"; export GH_REPO="${GITHUB_ORG:-$ORG}/$REPO_NAME"`.
- **Stacked PRs — merging into a stack base does NOT land on the integration
  branch** (learned the hard way): when `STACKED_ON_PR` is set or
  `PR_BASE_BRANCH != EVENTUAL_INTEGRATION_BRANCH`, the PR's base is another feature
  branch, so `develop` receives nothing until the parent PR merges and this PR is
  retargeted. This is a **warning + explicit choice at the merge gate**, never an
  auto-block of a user-approved merge: print the stacked-branch warning at the
  review-state/merge gate, require the user to choose merge-into-stack-base vs
  park/retarget, and record `RETARGET_REQUIRED="1"` plus a loose-end entry naming
  the parent PR so the retarget survives the run.
- **Per-stage phase checklist:** the script renders the phase order into each
  task file (`/tmp/workflow-task-<stage>.md`) — follow that list, in sequence.

## ⚠️ NEVER Edit Skill Code While a Run Is Live (hard rule)

**POLICY: a run must NEVER edit skill code — not `workflow-do.ts`, not the sub-skills
(`workflow-do-build`, `workflow-do-tour`, `workflow-do-ship`, …), not the prompts
(`prompts/*.md`), not `SHARED-POLICY.md` — while it is running.**

The harness is SHARED code, read and executed by CONCURRENT runs (parallel cages,
other tickets, the host-side reviewer). A mid-run edit changes it out from under every
other run that is mid-flight: a stage re-reads a prompt that no longer matches its
task file, a sub-skill is rewritten while another run is executing it, and the edit is
invisible to git history until someone commits it. A run that patches the harness to
get itself unstuck is also unauditable — nobody can tell the fix from the failure.

**Reason: the <KEY> incident (2026-10-15).** A live iterate run hit
`stage tour cannot start — input vars missing: SCREENSHOTS_DIR` (the iterate flow never
runs `build`, which was the only place that recorded it). Instead of failing, the run
patched `workflow-do.ts` in place to derive the var — an uncommitted edit to shared,
concurrently-read code, made by a run that was supposed to be executing a ticket.

**What a run must do instead:**

- **Find a bug in the harness → FAIL LOUDLY. Do not patch it.** Stop with a clear
  message (which stage, which var/assumption, the exact error) and hand the diagnosis
  to the human and the chief of staff.
- **Record it as friction + a loose end** (`/tmp/workflow-loose-ends.md`, and the P12
  friction scan) so it survives the run and reaches the periodic bulk scan.
- **The fix is made by a HOST WORKER afterwards** — a separate, deliberate edit to the
  shared code, committed on its own, never from inside a live run.

## Stage Orchestration (script model, v7)

Since v6 the orchestrator is a **deterministic script**: `~/.agents/skills/workflow-do/workflow-do.ts`
(v7: TypeScript, run directly with node + tsx; the old v6 bash orchestrator is retired — its logic is fully ported to the .ts)
(runs inside the cage, launched in the FOREGROUND by the run pane's bash launcher
`~/.agents/skills/workflow-do/run.sh` — the run pane is not a pi session; pi is only
the failure fallback when that launcher sees a non-zero exit). The script — not a
model — owns stage order, pane launching, and handoff verification. Stage agents
(full interactive pi sessions in panes of the run's tab) follow this contract:

- **Stage panes:** one pane per MAIN stage, launched and closed entirely by the
  script (pane lifecycle is script-owned — stage agents never run zellij launch
  or close commands). Stage agents do NOT close their own pane — zellij does NOT
  auto-close panes when their command exits (dead panes linger). The agent
  surrenders and STOPS; the script closes the pane by pane-id once the stage is
  verified. Do not keep stage panes open.
- **Run state file `/tmp/workflow-run.env`:** append-only `KEY="value"` blocks
  (same rules as `.workflow-handoff.env` — never overwrite, never partially
  rewrite; last value wins on source). The stage agent's OUT vars are appended
  here, not sent as chat text.
- **Loose-ends gathering (`/tmp/workflow-loose-ends.md`):** EVERY stage agent
  appends loose ends to this file AS THEY ENCOUNTER THEM during any stage — not
  at the end. Loose ends = deferred edge cases, TODO/FIXME comments left in the
  PR, near-miss bugs spotted during implementation or review, papercuts skipped
  for scope, test gaps. Append-only, one entry per line, **prefixed with a
  severity marker**: `🔴|🟡|🟢 short title | why it matters | where in the code`,
  where 🔴 = blocker (blocks other work, a live bug, or a release), 🟡 = should-do
  (real risk or debt, schedule soon), 🟢 = nice-to-have (cosmetic or optional).
  On first write, record
  `LOOSE_ENDS_FILE="/tmp/workflow-loose-ends.md"` in the run env. **Loose ends are
  recorded, never turned into tickets by a run (decision 2026-10-08):** the wrap-up
  stage prints the list for the human and records `FOLLOWUP_DECISION="none"` +
  `FOLLOWUP_TICKETS=""`. Runs never create tracker tickets — the ticket the run works
  on must already exist. Each entry keeps its severity
  marker (🔴 blocker / 🟡 should-do / 🟢 nice-to-have) so the human can triage the
  list when they choose to file tickets.
- **Surrender point (the stage→script handoff):** the stage agent's final actions,
  in order: (1) append its OUT vars + `STAGE_DONE="<stage>"` +
  `STAGE_STATUS="ok"` (or `"blocked"`) to `/tmp/workflow-run.env`; (2) `intercom
  send` its handoff one-liner to the chief-of-staff session (skip silently if
  unavailable); (3) STOP — do NOT run `exit` or `kill $PPID` (zellij panes are not
  auto-closed by exiting; they linger dead). Stage-closure confirmation prompts were
  removed (2026-10-08). The script's file-poll regains control, verifies the
  stage's required vars, closes the pane by pane-id, and launches the next stage.
- **Verify your own surrender append — do not assume it landed.** After appending the OUT vars +
  `STAGE_DONE`/`STAGE_STATUS` block, **re-read `/tmp/workflow-run.env` and confirm your stage's
  block is the last one for your stage** (e.g. `grep -c '^STAGE_DONE=' <file>` must have grown and
  `tail -3` must show your block). Only then report success in-pane. A stage that reported
  "appended" while the write silently failed stalls the whole run: the script polls with
  `STAGE_TIMEOUT=0` (no timeout) and will wait indefinitely (<KEY-138> tour, 2026-09-30 — the
  supervisor had to append the block by hand). If the re-read does not show your block, retry the
  append once and intercom-ask the chief of staff rather than claiming success.
- **Never run anything after the surrender.** The script is the sequencer — a
  stage that starts the next group's phases breaks the handoff verification.
- **Intercom name-resolution flakiness:** if `intercom send/ask` to the
  chief-of-staff session by name fails with "not found / not currently connected",
  resolve the short id via `intercom({ action: "list" })` (leading prefix of the
  session ID shown in parentheses) and retry once with the short id — the
  session may be registered under a different name (e.g. the ticket-id name,
  not the run-id name). If the retry also fails, skip silently per the surrender
  protocol — the script's file-poll regains control regardless. (Learned
  2026-09-14/16: two sessions recovered by short-id retry.)
- **Prose (briefs, fix lists, summaries) goes in files** (`/tmp/workflow-brief.md`,
  `/tmp/workflow-fixlist.md`, ...) with the path recorded as a var — env values
  stay single-line `KEY="value"`, no embedded double quotes.
- **Script-side gates are captured, not asked by the script:** `wrap-up` records
  `DECISION_CLOSE_OR_ITERATE="close"` (build mode always closes); `review-state`
  records `RECOMMENDED_ACTION` and `LOOP_DECISION` automatically (close when all
  findings are addressed, otherwise another round) and takes `MERGE_DECISION` from
  the human's `ask_user_question` in its pane. The script only ACTS on those
  recorded decisions. **review-state must always append
  ALL THREE decision vars** — when parking on `MERGE_DECISION="wait"`, still write
  `LOOP_DECISION="another-round"`; when ending via merge, write
  `LOOP_DECISION="close"`. Missing/empty decision vars fail script verification.
- **Post-fix endings park — never ask, never merge** (policy 2026-10-15): once a fix
  round has run, the run asks NOTHING and never merges — `review-state` records
  `RECOMMENDED_ACTION="await-re-review"` with an empty `MERGE_DECISION`, sets the
  ticket to the org's PRE-REVIEW status (one org: `ready to test`; ClickUp: left at
  `working`), and the script parks awaiting re-review. The merge gate survives ONLY for a fresh peer approval of
  the CURRENT head with no fix round in this run. An unresolved thread still outranks
  every classification (it is fix-round feedback).
- **The pre-review → review-pending transition is HUMAN-ONLY** (policy 2026-10-15): a run
  stops at the pre-review status — `ready to test` in one org / `working` in a ClickUp org — and
  may NEVER write the review-pending status (`Review Pending` on <org>, `testing / in
  review` on ClickUp). The human makes that move when they hand the work to the reviewer.
- **A cage never outlives its run; parked or completed runs are reclaimed immediately**
  (policy 2026-10-15). FINISHED means completed (build: PR finalized + wrap-up;
  iterate: merged + post done), parked (awaiting re-review, approval gate, blocked), or
  failed — the host/chief of staff closes that run's tab, then explicitly `docker rm -f`s the
  cage and re-checks it is gone, never leaving a finished run open. Closing the tab
  fires `cage()`'s exit trap; resume is the worktree + `.workflow-handoff.env`
  (worktree-rehydrate), never the in-container `/tmp`. The worktree and screenshots are
  NEVER deleted by cleanup.
- **Intervention:** if a stage blocks/fails verification, the script halts with a
  loud message; the failure-fallback pi session (or the human) fixes the run state (append missing
  vars) and relaunches with `workflow-do.ts --resume` / `--stage <name>`.
- **intercom is a pi TOOL, not a shell command.** Stage agents must call it via
  the pi `intercom` tool (e.g. `intercom({ action: "send", to: ... })`), never as
  a bash CLI — `intercom ...` in bash fails with "command not found" and flags
  like `--to`/`--message` do not exist.
- **Intercom handoff is best-effort — the run env is the only real handoff channel**
  (v8, learned 2026-09-30): the SCRIPT owns sequencing and regains control by
  polling `/tmp/workflow-run.env` for `STAGE_DONE` + `STAGE_STATUS`. The `intercom
  send` of a handoff one-liner is a steering courtesy to the session that launched
  this cage; a stage must NEVER block, retry-forever or fail its surrender because
  that session is not currently listed. It is normal and harmless for
  `intercom({action:"list"})` to show no target session (the session is alive but its
  broker connection can be orphaned — e.g. when the intercom broker is replaced,
  which silently drops every connected session from the registry until it next sends).
- **Handoff/ask target = the chief of staff, the session that launched this cage (policy
  changed 2026-10-15).** The chief of staff exports `WORKFLOW_ORCH_SESSION` in the launch env
  (env var name unchanged for runs already in flight); the script passes that value
  to every stage pane and records it in the run env as `ORCHESTRATOR_SESSION`, and
  the stage task file prints the resolved target. Stage agents address the chief of staff
  directly — the in-cage supervisor session is NOT a relay for handoffs or human
  gates. Resolution order for that send (SAFE ORDER — never guess):
  1. the target printed in your task file / `ORCHESTRATOR_SESSION` in the run env,
     which is the chief of staff-supplied value when the chief of staff launched the cage
     (authoritative);
  2. else the exact name `workflow-orch-<TICKET_ID>` — the legacy in-cage supervisor
     name, used only when nothing was supplied (manual kickoffs, older runs);
  3. else `intercom({action:"list"})` and match an id whose session name is
     **exactly** `workflow-orch-<TICKET_ID>` (a leading `workflow-orch-run-<pid>`
     label may be the same session — accept it only when no sibling run is present);
  4. **if nothing matches exactly → SKIP SILENTLY.** Do NOT fall back to "the sole
     `workflow-orch-*` in this cwd": with parallel runs (the normal case now) that
     delivers this run's handoff into a SIBLING run's session — worse than sending
     nothing. (Corrected 2026-09-30, when <KEY> saw only `workflow-orch-<KEY-185>`
     while three runs were live.)
  Do not derive the target from a name prefix — prefix resolution repeatedly failed
  to resolve and silently skipped sends. The chief of staff is the only bridge for a human
  gate a stage cannot answer in-pane; a stage never has to reach the supervisor to
  make progress, and the supervisor must never be assumed to relay one.
- **Read the target from the task file or the run env instead of inferring it**
  (learned 2026-09-22, extended 2026-10-15): the script now prints the resolved
  intercom target in every stage task file (and records `ORCHESTRATOR_SESSION` in the
  run env), so no stage has to do the list-and-retry dance. Runs started before
  2026-10-15 may instead already carry a recorded `ORCHESTRATOR_RESOLVED_NAME` in
  their run env — consult that only when no target was supplied (they are the older
  runs; it is a read-back of what such a run resolved, never a fresh lookup).
- **Scout stage (build mode only, before prebuild):** an autonomous context
  gatherer. It resolves the ticket from the tracker, scans the repo, loads org
  conventions, and checks existing PRs/branches/CI, then writes a context pack
  to `/tmp/workflow-scout.md` (`SCOUT_FILE` in the run env). Prebuild reads the
  pack first and builds the brief from it. Scout creates no tickets, branches,
  or PRs.
- **Chrome is script-owned:** the script launches the run Chrome itself on a FIXED CDP port
  (`CHROME_CDP_PORT` in the run env — never `--remote-debugging-port=0`) with the org's
  user-data-dir (the registry via the cage `WORKFLOW_ORG` hook, mounted at `$HOME/chrome-org`)
  before prebuild and tour (`CHROME_LAUNCHED="1"`). Stage agents attach with
  `agent-browser --headed --session $CHROME_SESSION --pin-tab --profile "$CHROME_SESSION_PROFILE" --cdp "http://127.0.0.1:$CHROME_CDP_PORT" <subcommand>`
  (the run env carries every value — agents NEVER `--auto-connect`; they target the run's explicit
  session) — they never launch Chrome themselves. If the browser is dead, `scripts/chrome.sh
  status` then `scripts/chrome.sh revive` (idempotent, same profile, same recorded port). (This
  section used to say to OMIT `--headed --profile` — that contradicted the rule below and made
  every stage pane start a second, logged-out temp-profile Chrome; corrected 2026-10-07. One
  browser per run.)

## Hard Prerequisites

Before starting ANY phase, verify these. If any fail, **stop immediately** and tell the user what to fix.

The actual verification — reading the system prompt, updating pi, zellij, git signing, Chrome browser, and GitHub access — happens in **Phase 0 — Access & Browser Verification** (the first numbered phase). The sections below are reference material and policy that Phase 0 enforces.

### Read APPEND_SYSTEM.md

**Performed in Phase 0.1** — this is the very first action of the entire run, before any other check. Read `~/.pi/agent/APPEND_SYSTEM.md` if it exists. This file contains global agent instructions that apply to all skills and must be loaded into context before proceeding:

```bash
[ -f ~/.pi/agent/APPEND_SYSTEM.md ] && cat ~/.pi/agent/APPEND_SYSTEM.md
```

If the file exists, read it and follow any instructions it contains throughout the entire run. If it does not exist, proceed normally.

### Zellij Required (Host-Based)

**Verified in Phase 0.3.** The check below is performed there as the first access-verification step.

```bash
if [ -z "$ZELLIJ" ] && [ -z "$ZELLIJ_SESSION_NAME" ]; then
  echo "FATAL: workflow-do requires zellij. Start a zellij session first: zellij"
  exit 1
fi
```

**If not in zellij, FAIL LOUDLY and do not proceed.** Do not fall back to background processes. The skill relies on zellij panes for the development workflow.

**Zellij runs on the HOST, not inside the container.** The cage container connects to the host's zellij server via the mounted socket at `/run/user/$uid/zellij/`.

**Pane lifecycle is SCRIPT-owned — stage agents never launch or close panes.** The workflow-do script (workflow-do.ts) launches every stage pane and the Chrome pane, and closes stage panes by pane-id after verification. Stage agents never run `zellij run`, `zellij action new-pane`, or `close-pane`. Long-running processes a stage needs (dev servers, DB) run as `bg_run` background tasks, not panes. Tab **renames** remain agent-side via `workflow_rename_tab` (see the Pane Management Convention) — renaming is not launching or closing.

### Git Signing

**Verified in Phase 0.4.** The check is performed there as part of access verification.

Whether signing is required is determined by the `workflowDo.signCommits` field for your org in `$ORG_CONFIG_DIR/org-config.json` — not all orgs require it. When signing IS required:

- **Method:** SSH signing only (`gpg.format ssh`), not GPG
- **Key:** `~/.ssh/id_ed25519.pub` (mounted read-only from host)
- **Container path remap:** Host paths like `/Users/...` are remapped to `~/.ssh/<basename>`
- **GitHub registration:** The SSH key must be registered as a **signing key** at `github.com/settings/ssh/signing_keys` (separate from regular SSH auth keys) — without this, commits show as signed but NOT verified
- **Auto-sign:** `commit.gpgsign true` and `tag.gpgsign true` are set so all commits on the feature branch are signed automatically
- **`gpg.ssh.program`** must be set to `ssh-keygen` (installed via `openssh-client` in the cage image)

Full setup steps are in the `commitSigning.setup` array in `$ORG_CONFIG_DIR/org-config.json` (GitHub registration + re-signing existing commits).

### All Testing is Local — NEVER Test Against Staging

**⚠️ HARD RULE: All testing, verification, screenshots, and browser tours must run against LOCAL services only** — the dev servers and database running inside this container on `localhost`.

- **NEVER** point the browser, curl, or any test at a staging, preview, or production URL (e.g. `staging.example.com`, `*.vercel.app`, production API endpoints).
- **NEVER** run migrations, seeds, or tests against a remote/shared database. Only the local Docker-in-Docker database.
- Dev servers bind to `localhost` inside the container — that's the only target for testing.
- **Dev-server port drift — read the repo's real config, don't assume defaults** (learned
  learned the hard way): a backend that defaults to Postgres `127.0.0.1:54322` fails with
  `ECONNREFUSED` when the repo's `supabase/config.toml` serves a different port (<org>
  serves `55322`). Before declaring a backend/DB dev server broken, read the repo's
  `supabase/config.toml` / `docker-compose.yml` and set the backend's DB URL to the port
  actually served; if the mismatch is intrinsic to the repo, record it as a loose end
  rather than fighting it. Frontend + supabase alone are enough to run a
  frontend-only change.
- **Run artifacts stay out of the source checkout** (learned the hard way):
  `SCREENSHOTS_DIR` and other per-run temp files must live **inside the worktree**
  (`$WORKTREE/screenshots`) or under `/tmp` — never in the user's main checkout (e.g.
  `$REPO_ROOT/.workflow-tmp`), which is not gitignored and leaves untracked files behind
  after every run.
- If a project has a `.env.staging` or staging config, **do not use it** for any test-do activity. Use `.env.local` or `.env.development`.
- If the user explicitly asks to test against staging, confirm verbally first — but the default is always local.
- This prevents accidental data corruption on shared environments and ensures reproducible test results.

### PR Ready for Review — the run owns draft→ready; review mode never touches it

**HARD RULE (decision 2026-10-20): a finished build or iterate run hands off a PR that is
READY FOR REVIEW, never a draft.** `ship-p8` (build) and `build-fix` (iterate, after the
fixes are pushed) run `gh pr ready`, re-read `isDraft` and must observe `false` before they
surrender; the orchestrator independently re-reads `isDraft` (`ensurePrReadyForReview()` in
`workflow-do.ts`) and the run FAILS LOUDLY if it cannot be verified. A draft handoff used to
force a manual undraft after every run — that is the bug this rule fixes. Never claim the
undraft happened without the verified `isDraft=false`.

**Review mode is the exception:** a review run NEVER changes a PR's draft state (no
`gh pr ready`, even when the PR author is us) — the author's own build/iterate run owns that
transition. Read-only inspection (`gh pr view … --json isDraft`) is fine. `ship-p10` checks
ready state again before merging and undrafts only as a merge-time guard for an older/manual
PR.

**Ticket status is unchanged by any of this:** the run still stops at the PRE-REVIEW status
(`ready to test` / another org `working`) and never writes the review-pending status — that transition
is the human's gate (policy 2026-10-15).

### Integrating the Base Branch Into a PR Branch — a MERGE, never a rebase, never a force-push

**⚠️ HARD RULE: to bring the base branch (main, or the org's integration branch (often `develop`)) up to date in a feature branch, run `git merge origin/<base>` and resolve conflicts in the merge commit. NEVER rebase a branch that has an open pull request, and NEVER force-push it.** A rebase rewrites commit SHAs, so GitHub drops or marks stale every review and approval on the PR and can detach review threads — the review record the run relies on. A merge keeps the reviewed SHAs intact. Rebase is only fine before a PR exists (local tidy-up); force-push is never allowed on a branch under review — if a run believes it must, it stops and asks the chief of staff.

### Workspace script invocation — `pnpm --filter ./frontend`, never `pnpm --filter frontend`

A bare `pnpm --filter frontend <script>` matches **no** workspace project when the
package's `name` in its `package.json` differs from its directory (a frontend
package is named `dark-suits-tap`, learned 2026-10-06 on <KEY-145>): pnpm silently
does nothing and exits 0, so a "verified" acceptance criterion can be a no-op. In
briefs, verification steps and skill templates use `pnpm --filter ./frontend <script>`
or `cd frontend && pnpm <script>`.

### Long browser / CDP calls get a timeout — a hang is not a slow render

**⚠️ HARD RULE: every long browser call in a run carries a timeout.** `agent-browser download`,
`agent-browser stream`, a `capture-beats.mjs` invocation that waits on `readyText`, an `open` waiting
for a load event — all of them can wait forever when the page never settles or the CDP stream stops
pushing frames, and the stage then sits in one bash tool call with no output (the sequencer only
warns). One <KEY-208> tour hung **3h21m** on a single beat capture and another call hung 4h on a CSV
download before a human noticed (2026-10-16). Wrap them (`timeout 600 …`), and on exit 124 fix the
underlying state (route, `readyText`, dev server) instead of blindly re-running.

### Testing Tooling — what to use for what (always locally)

- **Email / mail**: Mailpit
- **APIs / endpoints**: Hoppscotch (self-hosted against the local API) or the backend's own OpenAPI UI
- **Databases / schema**: a NEUTRAL SQL console against the DB the product actually runs — CloudBeaver / psql / DBeaver (the repo's own pgAdmin/Adminer only when it is not Supabase). **Never demo through Supabase Studio or the Supabase-local stack** (user directive 2026-10-16): it is a dev-only vendor surface the product does not ship. When the dev stack is Supabase, connect the neutral console to the same Postgres URL and film that.
- **Web / UI**: Chrome (via agent-browser — see the Chrome section below)
- **Code diff (backend-only changes)**: VS Code for the Web (`github.dev/<org>/<repo>`) or the PR *Files changed* view
- **Logs / jobs / traces**: Dozzle, a queue board, the org's APM

These are also the **evidence surfaces when a change has no UI** — a migration, policy,
middleware, route or email is demonstrated on one of them, before↔after, and the security
and design implications are narrated. Change class → surface, recipes and the narration
rules: `~/.agents/skills/workflow-video-tour/non-ui-evidence.md`.

Run all of them against the LOCAL services only, never a remote/shared instance.

### Browser Login Handling — External vs Local

When the browser encounters a login screen during any phase, handle it differently depending on whether it's an **external service** or a **local dev service**:

**External services (GitHub, Google, Microsoft, Jira, Notion, Confluence, etc.):**

- **NEVER auto-fill credentials** for external services. No passwords are stored in the skill or env files.
- **Wait for the user** to log in manually in the Chrome window. Print a message: `⚠️ Login required for <service>. Please log in manually in the Chrome window.`
- Poll the page URL until the login redirect completes (as done in Phase 1.3b for GitHub).
- The persistent Chrome profile usually retains the session — on subsequent runs the login screen won't appear.
- This applies to: GitHub login, Google/Microsoft SSO, Jira/Confluence (if accessed via browser), Notion (if accessed via browser), and any other external service.

**Local dev services (localhost:3000, localhost:5173, local admin panels, local DB admin tools like pgAdmin, Redis Insight, etc.):**

- **Find or create credentials** — these are local test environments, not real services.
- Check for credentials in: `.env.local`, `.env.development`, `.env`, `docker-compose.yml`, seed scripts, or the project's README.
- Common patterns: `ADMIN_EMAIL`/`ADMIN_PASSWORD`, `TEST_USER_EMAIL`/`TEST_USER_PASSWORD`, `SEED_USER_*` env vars.
- If no credentials exist, **create a test user** via the project's seed/hydrate script or directly via the database (e.g. SQL INSERT, or the project's CLI create-user command).
- Auto-fill the login form using `agent-browser --headed fill "input[type=email]" "$email"` etc.
- **⚠️ MUI / React controlled inputs:** CSS-selector `fill` sets the DOM value but often does **not** trigger React's `onChange`, so the submit appears empty / login fails silently. Use the **snapshot-ref** form instead — `agent-browser --headed snapshot -i`, then `fill @<ref>` and `click @<ref>` on the textbox/button refs. This reliably drives MUI `TextField` and Refine login forms.
- If the login form uses non-standard fields, inspect the page with `agent-browser --headed eval 'document.querySelector("form").innerHTML'` to find the right selectors.
- Never prompt the user for local dev service credentials — the agent should be able to handle these autonomously.

### Chrome Browser — Per-Run Docker Chrome (Parallel-Safe)

**⚠️ Cage is required. There is no default host mode.** `workflow-do.ts` hard-fails at startup if `WORKFLOW_CONTAINER_ID` is empty, because every failure mode of the 2026-09-24 friction sequence (Chrome profile corruption, gh-auth whiplash between accounts, shared `/tmp` fixtures trampled between runs, kong/edge-runtime port fights, dev-server port collisions, singleton lock deaths) traces back to parallel runs sharing host state. Kick off every run via `cage()` per `chief of staff SKILL.md`'s "Kickoff flow — launch a task as a workflow-do run in a cage" section.

**Escape hatch — `--host-mode --host-reason "<why>"` — requires explicit human authorisation.** The reason is recorded as `HOST_MODE_REASON` in the run env, appears in every P12 friction scan, and stays there for the audit trail. Do NOT pass `--host-mode` because a cage "seems slow" or "the last run was uncaged" — confirm with the user, capture the reason in their words, and only then bypass. If you find yourself considering `--host-mode` without a user in the loop, that is a supervisor bug — stop and ask.

**In-cage `WORKFLOW_CONTAINER_ID` handling — keep it set** (learned 2026-09-22): an in-cage `docker ps` talks to the cage's own DinD daemon and never sees the cage container itself — "container not found" from inside the cage is a false negative. Check `[ -f /.dockerenv ]` first: if you ARE inside the cage, keep `WORKFLOW_CONTAINER_ID` set (panes must `docker exec` back in so they share `/tmp`); unsetting it from inside the cage launches panes on the host, whose separate `/tmp` silently swallows stage handoff vars and forces a full relaunch.

- **Chrome is script-owned in the cage** — the script launches the run Chrome with a dedicated profile dir (never the user's daily Chrome), on a FIXED CDP port recorded as `CHROME_CDP_PORT`, under the named session `CHROME_SESSION` (all in the run env); agents attach with `agent-browser --headed --session $CHROME_SESSION --pin-tab --profile "$CHROME_SESSION_PROFILE" --cdp "http://127.0.0.1:$CHROME_CDP_PORT" <subcommand>` — never `--auto-connect`, never launch Chrome themselves (use `scripts/chrome.sh status|revive` if it is dead).
- Pane lifecycle stays script-owned — stage agents never launch or close panes; dev servers and DBs run as `bg_run` background tasks.

Each workflow-do run executes inside a Docker container (started by the `cage` bashrc function) with its own Chrome (launched and managed by agent-browser against the persistent `/chrome-profile` mount), its own Docker daemon (DinD), and its own network namespace. The user's real daily Chrome is never touched. **Each cage has its own isolated network** — ports inside the cage (dev servers, Docker compose services, databases) do NOT bind to host ports, so parallel cage runs never clash with each other or with host services.

**Chrome profile is persistent.** The `cage` function mounts `$HOME/.cage-chrome-profile` at `/chrome-profile` inside the container, so login sessions (GitHub, Google, etc.) persist across container runs. On the first run the profile is blank and the user logs in manually; on subsequent runs the profile is restored and the user is typically already logged in. Chrome is launched in **Phase 0.5**, and GitHub login is verified in **Phase 1.3b** (after org detection, so the correct GitHub account is confirmed). This is a hard gate: if GitHub is not accessible, the session does not proceed, because screenshot uploads to GitHub PRs require a logged-in browser session.

**⚠️ Google "This browser or app may not be secure" error:** Chrome inside the cage runs with `--remote-debugging-port`, which Google detects as an automated browser and blocks OAuth login. **To pre-authenticate the profile, run this on the HOST (not inside the cage) before starting a cage:**

```bash
google-chrome --user-data-dir=~/.cage-chrome-profile
```

Log in to Google and GitHub in this normal Chrome (no debugging flags), then close it. The persistent profile retains the cookies — the cage's Chrome will pick up the already-authenticated session and no login screen will appear.

- Use `agent-browser` — its daemon launches/attaches to the container's Chrome.
- **⚠️ The run's Chrome is started ONCE, by the script itself, at run start — and NOTHING
  else may start a Chrome.** `launchChromePane()` runs inside the cage (no zellij pane):
  it copies the profile, kills any stray Chrome for this session, then launches
  `google-chrome --ozone-platform=wayland --remote-debugging-port="$CHROME_CDP_PORT" …` directly
  (a FIXED port — never `0`) and attaches `agent-browser --headed --session $CHROME_SESSION --pin-tab
  --profile $CHROME_SESSION_PROFILE --cdp http://127.0.0.1:$CHROME_CDP_PORT`, then opens the `pi` tab.
  Every later call — stages, uploads, tours — must **attach** with the full quadruple
  `--headed --session "$CHROME_SESSION" --pin-tab --profile "$CHROME_SESSION_PROFILE" --cdp "http://127.0.0.1:$CHROME_CDP_PORT"`.
  A call that drops `--profile`/`--headed`/`--cdp` (or omits the session) launches a SECOND, logged-out
  Chrome on a temp profile with an EPHEMERAL debug port — the phantom that broke the 2026-09-29/30 runs.
  Why the fixed port is mandatory: `agent-browser`'s own launcher hardcodes `--remote-debugging-port=0`,
  so a browser started through it leaves NO port on record (three of four runs on 2026-10-19 lost their
  browser with nothing to reconnect to). If a stage sees a Chrome it did not expect, it must not use it:
  report it and let the chief of staff/host clean up.
- **Do NOT create Chrome panes.** There is no `workflow-do-chrome-<TICKET>` pane any more; the
  run's browser is a plain background process owned by the script. If Chrome dies, use
  `scripts/chrome.sh` — never a new pane and never a hand-rolled launch:

```bash
bash ~/.agents/skills/workflow-do/scripts/chrome.sh status   # port / profile / pid / CDP alive / GitHub login
bash ~/.agents/skills/workflow-do/scripts/chrome.sh revive   # idempotent: one relaunch on the SAME profile
```

  The script also runs a liveness probe **before every browser-using stage** and performs that
  single automatic relaunch itself (recording `CHROME_CDP_PORT` + `CHROME_LAUNCHED` in the run
  env). A stage that finds the browser dead calls `chrome.sh revive`; it never improvises.
- **The run Chrome must be at least 1600x900 — pass an EXPLICIT window size.** The script
  launches it with `--window-position=0,0 --window-size=${CHROME_WINDOW_SIZE:-1920,1080}`
  and records `CHROME_WINDOW_SIZE` in the run env; `chrome.sh revive` refuses a size below
  1600x900. Why: the video tour films a 1600x900 frame, and on 2026-10-19 a live run came up
  **948x947**, so the tour captured a 948x947 screencast that was unusable for the cut.
  `--window-size` alone is not sufficient — niri is a tiling compositor and sizes the tile
  itself, so the flag is a request. That is why the size is **measured**, not assumed:
  `bash scripts/chrome.sh viewport` prints the real `WxH` from the live page and exits 1
  when it is below 1600x900. Run it before the video tour (or any screenshot pass that
  needs the frame); when it fails, widen the niri column or run `scripts/place-chrome.sh`
  to fill the monitor, then re-check. Never shrink the storyboard viewport to match a small
  window.
- **The run Chrome ALWAYS runs on a FIXED CDP port — never `--remote-debugging-port=0`.** The
  port is chosen by the script (deterministic per ticket, free-port checked), persisted as
  `CHROME_CDP_PORT` in the run env, and **every** `agent-browser` call must attach with
  `--cdp http://127.0.0.1:$CHROME_CDP_PORT` on top of the binding flags. Why: `agent-browser`'s own
  launcher hardcodes `--remote-debugging-port=0` (an ephemeral port), so a run started through it
  had no recorded port at all — three of the four runs on 2026-10-19 lost their browser with nothing
  to reconnect to (<KEY-209>/1210/1211/1212). `chrome.sh status` reports the live port; nothing may
  derive or guess one.
- **⚠️ The run's Chrome uses a PER-SESSION COPY of the profile — never the source dir itself.** Copy the WHOLE folder to a session-private temp path first, then launch (and attach) against the copy:

```bash
# one copy per run, made once, used for the whole run
CHROME_SESSION_PROFILE="/tmp/chrome-profile-<TICKET>"   # take the VALUE from the run env (CHROME_SESSION_PROFILE)
                                                        # — never derive it. CHROME_SESSION is already
                                                        # `chrome-<TICKET>`, so /tmp/chrome-profile-${CHROME_SESSION}
                                                        # gives the WRONG double-prefixed path and starts a
                                                        # second blank Chrome; the script uses /tmp/chrome-profile-<TICKET>.
[ -d "$CHROME_SESSION_PROFILE" ] || cp -a "$CHROME_USER_DATA_DIR" "$CHROME_SESSION_PROFILE"
agent-browser --headed --session "$CHROME_SESSION" --profile "$CHROME_SESSION_PROFILE" open about:blank
```

  Record `CHROME_SESSION_PROFILE` in the run env and use it in the attach triple for every later call. **Copy the ENTIRE directory — not a symlink, not selected files:** Chrome needs `Local State` (the `os_crypt` key that unwraps cookies under `--password-store=basic`), `Cookies`, `Local Storage` and `Login Data` to stay logged in, while a symlink resolves to the same real path and keeps the very singleton-lock collision the copy exists to prevent. This is what stops parallel runs (which all mount the same source profile) from killing each other's Chrome and falling into logged-out temp-profile phantoms. The copy is disposable — the source profile stays pristine.
- **NEVER hand-write run-env values containing a backtick or `$(`, and never source-then-execute them.**
  Every stage runs `set -a; source /tmp/workflow-run.env`, so such a value is EXECUTED by every later
  stage — a supervisor-written backtick value recursed into a ~2600-process fork bomb that blocked a
  pane for 25 minutes (<KEY>, 2026-10-08). Write values as plain text with `printf '%s\n' 'KEY="value"' >>`
  (no command substitution, no quotes inside), and if you must reference a command, put it in a file
  outside the env. `appendState()` now refuses backticks, `$(`, newlines and double quotes.
- **Fleet Chrome login source (2026-10-07).** `~/.cage-chrome-profile` (mounted at `/chrome-profile`) is the authenticated source: `Local State.profile.last_used = Profile 1` (that org's identity), which is why a plain `--user-data-dir` launch opens it and NOT `Default`. Two hard-won rules:
  1. **Never re-seed a run from a HOST-Chrome-written profile** — a host Chrome encrypts cookies with the OS keyring (`gnome-libsecret`) and no `os_crypt.encrypted_key` reaches the cage, so those `v10` blobs are undecryptable in-container: the browser looks signed in from cache, then drops `user_session` on the first real request.
  2. **To refresh the login, sign in ONCE in a CAGE window** (a cage Chrome has no keyring, so it falls back to the deterministic `peanuts` derivation and its cookies travel with a copy — **do NOT pass `--password-store=basic` explicitly anywhere in `AGENT_BROWSER_ARGS` or a launch command: with the flag set the propagated cookies fail to decrypt and GitHub re-walls (reproduced 2x on <KEY-200>, 2026-10-07). Always use the plain attach triple.**), then propagate that authenticated whole-directory copy back to `~/.cage-chrome-profile` and re-seed the other runs from it. Copy the WHOLE directory, keep `Local State` (`last_used=Profile 1`) intact, delete `Singleton*`/`DevToolsActivePort`, and launch with the plain triple (no `--args`, so stage calls never relaunch).
- **⚠️ `--headed` AND `--profile "$CHROME_SESSION_PROFILE"` (AND `--cdp http://127.0.0.1:$CHROME_CDP_PORT`) are MANDATORY on every `agent-browser` call** (together with the run's binding flags `--session "$CHROME_SESSION" --pin-tab`) — the full attach quadruple: `agent-browser --headed --session "$CHROME_SESSION" --pin-tab --profile "$CHROME_SESSION_PROFILE" --cdp "http://127.0.0.1:$CHROME_CDP_PORT" <subcommand>`. **ONE CHROME PER RUN — HARD RULE (user directive, 2026-10-07).** Every cage shares the host's display sockets, so each Chrome the run starts is a real window on the user's desktop that they have to close by hand. A bare `agent-browser <cmd>` — or a partial triple (missing `--profile`, or a bare `--session`, or a forgotten `--headed`) — starts a NEW Chrome on a throwaway `/tmp/agent-browser-chrome-<uuid>` profile: a second window, logged out, invisible to the run's own verification. NEVER do that, not to check one thing quickly, not while reading agent-browser docs, not from a second stage pane. If a call refuses to attach, re-attach to the run's own Chrome and fix the flags — never fall through to a fresh browser. Clean up any surplus you find (close non-run `agent-browser` sessions, kill non-run daemons between stages, `rm -rf /tmp/agent-browser-chrome-*`), then assert exactly 1 daemon + 1 main `/usr/bin/google-chrome ... --user-data-dir=$CHROME_SESSION_PROFILE`.
  - A call that omits `--headed` does NOT attach to the run's Chrome: agent-browser falls back to its own isolated launch and spins up a throwaway **headless** browser on a temp profile (`/tmp/agent-browser-chrome-<uuid>/`) — pages load and screenshots return, but it is a different, cookieless, invisible browser, so any screenshot or verification taken there is worthless.
  - A call that omits `--profile` can **kill the run's org-profile Chrome and relaunch a logged-out temp-profile phantom** (verified twice on parallel runs): the run then looks alive but has no GitHub/Notion session (PR links 404, `/settings/profile` → `/login`). A "you need to log in" gate on an external service is almost always this, not a real session loss.
  - Detection for either mistake: `pgrep -af "user-data-dir=/tmp/agent-browser-chrome"`, `ls -d /tmp/agent-browser-chrome-*`, and `pgrep -u pc -af "^/usr/bin/google-chrome --remote-debugging-port" | grep -c "user-data-dir=$CHROME_SESSION_PROFILE"` (must be exactly 1 **main** process — zygote/gpu/utility/renderer children inherit `--user-data-dir`, so counting them gives 8-12 and is not a problem; also require exactly 1 daemon for the session). Remedy: kill the phantoms + every stray agent-browser daemon for that session, delete the temp dirs, relaunch ONE Chrome pane bound to `$CHROME_SESSION_PROFILE`, then redo the step with the full attach triple. **The daemons ignore SIGTERM — use `kill -9`** (a plain `kill` leaves them alive and the next call spawns a replacement). **NEVER `rm -rf /run/user/1000/agent-browser*`** — that registry dir is shared by the host and every cage, so wiping it silently breaks the socket registry for *all* concurrent runs (<KEY-208>, 2026-10-07); remove only `<dir>/<CHROME_SESSION>.*`. **Build kill/grep patterns so they cannot match your own shell** (`pkill -f "<profile path>"`, `pgrep -f agent-browser-linux-x64` etc. match the invoking `bash -c` argv and SIGKILL the shell you are typing in — bracket-escape the pattern, e.g. `agent-browser[-]linux-x64`, or keep it in a script file and exclude `$$`/`$PPID`). **Scope the cleanup:** prefer the per-session `agent-browser --headed --session "$CHROME_SESSION" close` before falling back to a blunt `pkill -f agent-browser` — the blunt form also kills *sibling* stage panes' daemons inside the same cage (a build-fix pane killed the tour pane's daemon mid-setup, 2026-09-30), so only do it between stages, never while another pane is driving the browser.
- **⚠️ NEVER use headless browser. Chrome must ALWAYS be headed (visible on screen).** Never pass `--headless` to Chrome or `agent-browser`. The `cage` function starts Chrome in headed mode via Wayland. If Chrome is not visible on screen, something is wrong — do not fall back to headless. All browser interaction (screenshots, tours, uploads) must happen in the headed browser the human can see.
- **Chrome runs INSIDE the container** — same network namespace as dev servers. Chrome reaches dev servers via `localhost:3000`, `localhost:5173`, etc. No Docker bridge networking needed.
- **Dev servers bind to `localhost`** — the cage container has its own network namespace (bridge networking, not `--network=host`). `localhost` inside the cage is isolated from the host. Docker compose services, dev servers, and databases all bind to the cage's `localhost` and are unreachable from the host — this prevents port clashes with host services and other parallel cages.
- **Use `localhost` in URLs** — consistent and readable. All services run in the same cage network namespace, so `localhost` works for Chrome to reach dev servers, and for dev servers to reach DinD containers.
- NEVER run `agent-browser close` or `pkill chrome` on the host — the `cage` function handles cleanup on exit.
- The user's real daily Chrome is sacrosanct — never connect to it, never kill it.
- If Chrome inside the container dies, do NOT relaunch it by hand — run `bash ~/.agents/skills/workflow-do/scripts/chrome.sh status` (is it really down? on which port?) and then `... chrome.sh revive` (idempotent: one relaunch on the SAME profile, on the SAME recorded port). Then re-attach with `--cdp http://127.0.0.1:$CHROME_CDP_PORT` and re-verify the agent-browser connection (Phase 0.6) and GitHub login (Phase 1.3b). The script already probes + revives once before every browser-using stage. The org's persistent user-data-dir (mounted at `$HOME/chrome-org`) preserves login sessions across Chrome restarts within the same container run.

- If Chrome restarts after dying, the login session is usually preserved (the profile copy keeps cookies/session data). **Verify GitHub access after a Chrome restart with an authenticated-only page, never a `dashboard` URL grep:** `agent-browser --headed --session $CHROME_SESSION --pin-tab --profile $CHROME_SESSION_PROFILE --cdp "http://127.0.0.1:$CHROME_CDP_PORT" open https://github.com/settings/profile` and assert the resolved URL does **not** contain `/login`, `/session` or `/signup`. The logged-out redirect is `https://github.com/login?return_to=…dashboard`, so a `dashboard` grep matches the logged-OUT page too and passes an anonymous browser (false positive, <KEY-185> 2026-09-30). If the session IS lost, re-run the login flow in Phase 1.3b. `scripts/preflight.sh` performs the same check read-only, over cookies, before the tour.
- Monitor + viewport are pre-set by Phase 3.0.2 (Chrome moved to the leftmost landscape monitor **by the host, via `scripts/place-chrome.sh`** — in-cage `niri msg` cannot work; on macOS/X11 a fixed 1440×900 viewport is used instead). Verify/re-adjust in Phase 5.1.

### Persistent Ticket + PR Tabs (hard rule)

Every run keeps **three permanent browser tabs** for its whole duration — the
**ticket** tab, the **PR** tab, and the **pi** tab (the run's own pi-frontend
mirror UI). They are the human's handoff surface: the user must be able to look at
the run's Chrome at any moment and see the ticket, the PR, and the live session.

- **The ticket tab is opened as the FIRST browser action of the run** — before any
dev-server, DB, or screenshot work (prebuild P0.5/P1.2). Never wait until the
ticket URL is "convenient".
- **The PR tab is opened the moment the PR exists** — the draft PR at prebuild
  P3.11 — and re-pointed (same tab, not a new one) whenever the PR's state changes
  (e.g. when the human marks it ready). **No stage flips it: no mode marks a PR
  ready** (widened 2026-10; decision 2026-10-08).
- **The `pi` tab points at the run's own pi-frontend mirror UI** (`PI_FRONTEND_URL`
  in the run env; the script opens it at Chrome launch and discovers it from
  `~/.pi/tau-instances/<pid>.json` — the supervisor's port, else the instance whose
  cwd is this run's repo; the extension serves `http://127.0.0.1:3001` or the next
  free port, so a cage with several pi processes has one URL per process). If
  `PI_FRONTEND_URL` is empty, open `http://127.0.0.1:3001` and, if that is not the
  run's session, leave the tab alone — never invent a different port.
- **Both stay open for the ENTIRE run**: prebuild → build → tour → ship-p8 →
  wrap-up, and across iterate rounds. No stage may close them, and the run is not
  finished while either is missing.
- **Every other tab is scratch.** Dev-server/app browsing, test pages, PR-body
  screenshot capture, and anything else open their OWN tabs (e.g. an `app` /
  `tour` tab). Never navigate, never re-pin for scratch work inside the ticket or
  PR tab, and never reuse them as a scratch tab.
- **Idempotent open — never duplicate.** Use a labeled tab and re-focus it
  instead of calling `open <url>` again:

```bash
# ensure_tab <label> <url> — create the labeled tab once, then just refocus it.
# Verified against the live CLI (2026-09-30): `tab list --json` nests the tabs as
#   {success:true, data:{ ..., tabs:[{label, tabId:"t2", title, url, active}]}}
# so the old `.tabs[]? | select(.label==$l)` NEVER matched: every call fell through to
# `tab new --label`, which then died with "Label X is already used by another tab".
# Prefer the JSON `label`; fall back to a URL match (label-less tabs), and pin by tabId.
ensure_tab() {
  local label="$1" url="$2" ab tid
  ab="agent-browser --headed --session \"$CHROME_SESSION\" --pin-tab --profile \"$CHROME_SESSION_PROFILE\" --cdp \"http://127.0.0.1:$CHROME_CDP_PORT\""
  eval "$ab tab list --json" 2>/dev/null >/tmp/.ab-tabs.json
  tid=$(jq -r --arg l "$label" '(.data.tabs // .tabs // [])[] | select(.label == $l) | .tabId' /tmp/.ab-tabs.json 2>/dev/null | head -1)
  [ -z "$tid" ] && tid=$(jq -r --arg u "$url" '(.data.tabs // .tabs // [])[] | select(.url == $u) | .tabId' /tmp/.ab-tabs.json 2>/dev/null | head -1)
  if [ -n "$tid" ]; then
    eval "$ab --pin-tab tab $tid" >/dev/null 2>&1 || true   # refocus the existing tab
  else
    # fallback: clear any pin FIRST — `open` while pinned navigates the PINNED tab and can
    # clobber the permanent ticket/PR tab (<KEY-205> loose end, 2026-10-01).
    eval "$ab --no-pin-tab open \"$url\"" >/dev/null 2>&1 \
      || { eval "$ab tab list --json" >/dev/null 2>&1; eval "$ab --no-pin-tab open \"$url\"" >/dev/null 2>&1 || true; }
  fi
}

ensure_tab ticket "$TICKET_URL"   # first browser action of the run
ensure_tab pr     "$PR_URL"       # as soon as the PR exists (draft included)
```
- **Tab labels do NOT survive a daemon restart** (learned 2026-10-07, <KEY-200>): when the session's
  daemon is replaced, every user-assigned label is gone, so `ensure_tab`'s `.label` match misses and
  it falls through to the URL match — which is exactly why the URL fallback must never be removed.
  After any daemon restart, re-derive the permanent tabs **by URL** and re-label them
  (`tab new --label ticket <url>`), then close the stale unlabelled tab; a label-only check will
  otherwise report the ticket/PR tabs as missing when they are fine.
- **HEADED Chrome can stop binding DevTools fleet-wide (2026-10-07 ~19:47, Chrome 154.0.8037.97).**
  **THE OZONE PLATFORM FLAG IS THE FIX:** headed Chrome that never creates a window and never binds a
  debug port on the default X11 path works when launched with `--ozone-platform=wayland` plus
  `XDG_RUNTIME_DIR=/run/user/1000` and `WAYLAND_DISPLAY=wayland-1` — CDP then answers immediately
  (verified `curl http://127.0.0.1:<port>/json/version` -> Chrome/154.0.8037.97, <KEY> 2026-10-07).
  The script's launch (and `scripts/chrome.sh revive`) already uses exactly that recipe on a FIXED
  `CHROME_CDP_PORT`; do not hand-write another launch.
  Symptom: headed Chrome starts, stays alive, logs nothing but dbus noise, never writes
  `DevToolsActivePort` and never serves `http://127.0.0.1:<port>/json/*`. Recovery is one idempotent
  call — `bash ~/.agents/skills/workflow-do/scripts/chrome.sh status`, then `... revive` — which kills
  the stale mains, clears `Singleton*`/`DevToolsActivePort`, relaunches HEADED on the SAME profile and
  the SAME recorded port, and re-attaches the session. **Never fall back to headless** (a human must
  be able to log in in that window) and **never use agent-browser's own launch path** (`--args` cannot
  be trusted to win over its hardcoded `--remote-debugging-port=0`).
- **A stale Chrome holding the profile silently sabotages every relaunch:** Chrome writes
  `DevToolsActivePort` only for the process that OWNS the user-data-dir. If any Chrome still holds
  `SingletonLock`, the new launch hands its URL to the stale instance and exits — the log shows no
  "DevTools listening" line, the port file stays empty, yet `pgrep` looks healthy (<KEY>). Kill in a
  loop until `pgrep -u pc -f '^/usr/bin/google-chrome'` prints NOTHING, then launch exactly once.
- **NEVER call `agent-browser set viewport`** (0.36.0, <KEY> 2026-10-07): it wedges the session
  daemon outright — every later CLI call hangs until timeout, and the pane's own recovery then spawns
  a SECOND daemon + Chrome on the same user-data-dir and the run browser is orphaned for good (that
  cost one run ~5h). Set the window size at launch instead (or via CDP
  `Emulation.setDeviceMetricsOverride`) and record the intended size in the run env.
- **Double-instance race on the profile copy:** a leftover Chrome on the same `user-data-dir`
  survives the anchored pkill, so two mains fight over the profile, no `DevToolsActivePort` is
  written and every attach fails with ENOENT. Before any relaunch assert ZERO Chrome for the profile
  (`pgrep -u pc -af "user-data-dir=$CHROME_SESSION_PROFILE"` must print nothing), kill any daemons
  with `kill -9`, clear `Singleton*`/`DevToolsActivePort`, then launch exactly once.
- **Cage-stable Chrome launch (reproduced 3x on 2026-10-07, <KEY-200>/<KEY>/<KEY>).** The
  `agent-browser --profile ...` launch path does not stay up inside a cage: Chrome exits within ~2
  minutes, the daemon is orphaned, and worse, the launch kills whatever Chrome already holds the
  profile singleton lock — so a "revive" can take down a *working* browser. The stable recipe is to
  launch Chrome ONCE yourself and attach over CDP:
  `setsid google-chrome --remote-debugging-port=9222 --user-data-dir=$CHROME_SESSION_PROFILE &`
  then `agent-browser --headed --session "$CHROME_SESSION" --pin-tab --cdp http://127.0.0.1:9222 <subcommand>`.
  If Chrome is alive but `DevToolsActivePort` was deleted, rediscover the live port from
  `/proc/<chrome-pid>/cmdline` and rewrite `DevToolsActivePort` instead of relaunching.

> The text form of `tab list` prints the label glued to the title (`[t2] ticket Notion - https://…`);
> the JSON has a real `.label` field plus `tabId` — use the JSON, and pin by `tabId` (`t2`), not by label.

- **While the session is PINNED to a permanent tab, a navigation REPLACES that tab's URL.**
  `--pin-tab` makes the following subcommand act on the pinned tab, so `open <url>` while pinned
  to `ticket`/`pr` **navigates away from the ticket/PR** — this clobbered the ticket tab during the
  P1.3b GitHub-login check (which opens `github.com/settings/profile`) on <KEY-138>, 2026-09-30.
  Rule: before ANY navigation/check that is not about the ticket or the PR, clear the pin
  (`--no-pin-tab`) or pin a scratch tab first (`--pin-tab tab app`), then re-open/refocus the
  permanent tab with `ensure_tab` when you need it again.
- **Screenshots must not disturb them:** before any capture, pin to the scratch
  tab (e.g. `--pin-tab tab app`), take the screenshot, then return to whatever
  tab the step needs. `upload-screenshot.sh` and friends must never be pointed at
  the ticket/PR tab.
- **Labels are session-scoped:** if `tab list` shows no labels, find the tab by
  URL and switch by its `t` number — do not open a third copy.
- **Daemon hygiene — one daemon per session, verified before every browser step.** agent-browser
  spawns a NEW daemon+browser whenever it cannot reach the session's existing one, so a stale
  daemon, a wrong `--session`, a wrong/missing `--profile`, or a command block with several
  invocations can fan out into a swarm (<KEY-205> tour, 2026-09-30: **14 daemons** in one cage +
  a temp-profile phantom Chrome). Assert before and after a browser step:
  `pgrep -u pc -c -f 'agent-browser'` (expect 1), `pgrep -u pc -af '^/usr/bin/google-chrome --remote-debugging-port' | grep -c "user-data-dir=$CHROME_SESSION_PROFILE"`
  (expect 1) and `ls -d /tmp/agent-browser-chrome-*` (expect none); kill strays before continuing.
- **NEVER run a run's agent-browser commands from the HOST.** The cage's `/tmp/chrome-profile-<TICKET>`
  does not exist on the host, so every call creates a *host* Chrome on the same path name and the
  session silently drives the wrong browser (found 18 stray host processes for one run, 2026-09-30).
  In-cage commands belong to the cage (exec as user `pc` with the cage's Wayland/X env).
- **Do not relaunch the run's Chrome from a stage.** `agent-browser --init-script … open`
  (and any option that forces a fresh launch) **relaunches the run Chrome and drops
  every tab** — the permanent ticket/PR tabs included. Never pass `--init-script`
  to a command aimed at the run's Chrome; if the tabs do get dropped, re-open them
  with `ensure_tab` (sessions survive, because a profile copy keeps cookies and
  localStorage). Observed 2026-09-30 on <KEY-185>.
- **End-of-run check (ship-p8 / wrap-up):** both tabs still exist and show the
  ticket and the PR; print their URLs in the handoff. If either is missing,
  re-open it with `ensure_tab` before surrendering.
- **If `CHROME_SESSION` / `CHROME_SESSION_PROFILE` are missing from the run env, the
  check CANNOT run — say so, do not skip silently** (learned 2026-10-06, <KEY-145>
  iterate round: the resume path never launched Chrome, so no chrome process existed
  in the cage, both vars were absent, and a stage could not even build the mandated
  attach triple). A stage that finds them unset must (a) verify with
  `pgrep -u pc -af chrome` whether a run Chrome exists, (b) report the gap loudly to
  the chief of staff (`intercom ask`) and to the human in the handoff, and (c) record
  `CHROME_MISSING="1"` in the run env — never launch Chrome itself and never report
  a tab check as "done" when it was impossible.

### Screenshot Upload via agent-browser

Screenshots are uploaded to GitHub's `user-attachments` CDN (permanent URLs) via the **per-run Chrome** inside the Docker container. GitHub's upload endpoint has no public API — it requires a logged-in browser session, which the per-run Chrome's profile copy preserves.

- **Browser (agent-browser):** taking screenshots, uploading images to `user-attachments` (requires the user to be logged in to GitHub in the container Chrome — verified in Phase 1.3b; login sessions persist across runs via the persistent profile at `/chrome-profile`)
- **Annotations are IN-PAGE, and there is NO ImageMagick fallback** (user directive 2026-10-01,
  restated 2026-10-19): draw them with `~/.agents/skills/workflow-do/scripts/annotate.js` —
  `eval --stdin` it once per page, then `__wfAnnot.box/arrow/banner/label/cursor/click/clear/unmount`.
  Marks are then captured by BOTH `agent-browser screenshot` and the video capture, and follow the
  page on scroll/resize. Capture through `scripts/annotate-shot.sh`, which injects, proves the
  overlay mounted, draws, screenshots and records `{file, sha256, mounted, styleApplied, marks}` in
  `$SCREENSHOTS_DIR/annotations.json`; `scripts/check-annotations.sh` is the gate and rejects any
  `-annotated.png` without that evidence (stale sha, marks=0, blocked styles) — so a PNG is never
  accepted just because of its filename. **If the page refuses injected styles (CSP) or the target
  does not resolve, the annotation FAILS and the stage reports it** — never paint pixels onto a
  captured PNG, and never upload an unannotated file as annotated. Same palette everywhere: before
  `#EF4444`, after `#22C55E`, accent `#38BDF8`.
- **SVG rasterization (offline, no network):** the cage image ships `rsvg-convert`
  (`librsvg2-bin`). Use it for any SVG → PNG/ICO rasterization — brand/icon regeneration
  (e.g. `rsvg-convert -w 512 -h 512 logo.svg -o icon-512.png`) must never depend on a
  per-run fetch like `npx --yes sharp-cli`, which fails without network (<KEY>/182
  2026-09-30). ImageMagick 6's SVG delegate is unreliable here — prefer `rsvg-convert`
  over `convert foo.svg`.
- **Headless (`gh pr comment` / `gh api`):** composing and posting PR comments with the uploaded URLs


---

## Thinking Order (DB-First Principle)

Throughout all phases, reason about changes in this order:

1. **Database first** — schema structure, migrations, indexes, constraints, relationships
2. **Backend second** — API routes, services, RBAC/access control, mandatory side effects (emails, webhooks, audit logs), validation, error handling
3. **Frontend last** — state management (where state lives, how it flows), then visuals (components, layout, interactions)

This order ensures correctness propagates upward. A frontend built on a wrong schema wastes time. A backend built without understanding access patterns wastes effort. Always start from the data model.

### Implementation Style Pointers

These principles apply throughout all phases and should be checked during the DRY check (Phase 4):

1. **DRY above all** — If functionality is shared across two or more places (e.g., backend inline SQL + frontend query fetching the same data), it MUST go through common logic. Separate implementations WILL drift and cause bugs. Use shared SQL functions (`SECURITY DEFINER`) as the single source of truth.

2. **Database column naming consistency** — When designing or modifying database schemas, ensure column names follow a consistent convention across the table and related tables. Inconsistencies (e.g., `payment_id` in one table vs `transaction_id` in another) cause confusion and bugs down the line. If you identify an existing inconsistency, raise it as a ticket.

3. **Don't store what can be computed** — Avoid storing database columns for values that can be derived from other columns or a simple query, unless there's a specific performance or consistency reason. Stored computed values drift from their source and become silent bugs. If a computed column is unavoidable, document why.

4. **No useless comments** — Never write a comment whose content can be inferred from the code itself with general coding knowledge. Comments that restate what the code does are noise. Only comment to explain _why_ something non-obvious is done, to document a business rule that isn't evident from the code, or to warn about a non-obvious gotcha. If you have to ask "would a competent developer understand this without the comment?" and the answer is yes, delete the comment.

5. **Inline trivial functions — don't extract for the sake of it** — If a function is so simple that its body is shorter than its signature+call overhead, has only one call site, and doesn't benefit from abstraction or reuse, **inline it**. Wrapping a one-line expression (e.g. `return displayName`) in a named helper adds indirection and a thing to grep for, with no payoff. Only extract when there are **2+ call sites**, the logic is genuinely non-obvious, or a test needs to pin the behavior in isolation AND the behavior can't be tested through its caller. "Extracted for testability" is a valid reason only when the unit under test has real branching/validation worth asserting — not when the helper is a pass-through. (past feedback: a `resolveInvoiceFromName(x) { return x }` helper should have been an inline expression with a `// why` comment.)

6. **Decide on one-time scripts or migrations yourself, and record it** — If the implementation requires a new one-time script, data migration, or utility file that isn't part of the core codebase, decide from the repo's conventions whether it belongs in this PR, and **record the choice (and why) as an assumption/loose end**. The default is to NOT add a throwaway script unless it is genuinely needed. This stage is autonomous — there is no user in the pane to ask (decision 2026-10-08).

7. **Enforce integrity manually for any FK crossing a DB boundary** — Whenever a foreign key references an **external system** outside the database boundary (another service's API, a third-party system like Jira/Notion/TickTick, a Stripe customer, an external chargeplan, etc.), the database cannot enforce that relationship — you must do it **manually**. For every such cross-boundary FK, explicitly consider and handle all three directions: (1) **delete in our DB** — also delete/clean up the corresponding record in the external system (or explicitly decide not to); (2) **update of the referencing key** — make sure the external system is updated or the link is re-pointed, and that nothing dangles; (3) **delete in the EXTERNAL system** — do we need to recheck/reconcile and clean up our side? Always consider this. Surface the decision (and any intentional omission) in the PR summary so reviewers can challenge it.

---

## Zellij Tab Naming

Rename the zellij tab **just before a phase or substep starts** — at the transition point, right when you mark the task `in_progress`, before any work in that phase begins. The tab must **always show the phase that is currently in progress**, never the phase that just completed or is about to start next.

Format: `${TICKET_ID}: P{phase}.{substep} {Verb} · {nuance} ${FEATURE_TAG}` — **no emoji in the tab**: phase emojis now live on the pi-task `TaskCreate` subjects (see Task tracking). Use `$TICKET_ID` and `$FEATURE_TAG` (both set in Phase 1). This gives you visual progress tracking in the zellij tab bar.

**⚠️ Always use `workflow_rename_tab` — never bare `zellij action rename-tab`.** The `zellij action rename-tab` command renames the **currently focused** tab, but the user may have clicked to a different tab. `workflow_rename_tab` first focuses our tab by its tracked name (via `go-to-tab-name`), then renames it — so the right tab is always renamed regardless of where the user has clicked.

```bash
workflow_rename_tab "${TICKET_ID}: P<phase>.<substep> <Verb> · <nuance> ${FEATURE_TAG}"
```

The rename is the **first action** at each transition — do it before printing the phase banner, before any bash commands, before any tool calls. The sequence at every phase boundary is:

1. `workflow_rename_tab "${TICKET_ID}: P<phase> <Verb> ${FEATURE_TAG}"` ← rename tab FIRST (focuses our tab, then renames)
2. `TaskUpdate: P<phase> → in_progress` ← mark task in_progress
3. Print phase banner / start work

Examples (each shown at the point it should fire — the start of that phase/substep):

- `workflow_rename_tab "${TICKET_ID}: P0.1 Access ${FEATURE_TAG}"` ← Phase 0 begins
- `workflow_rename_tab "${TICKET_ID}: P1.1 Detect ${FEATURE_TAG}"` ← Phase 1 begins
- `workflow_rename_tab "${TICKET_ID}: P2.1 Groom ${FEATURE_TAG}"` ← Phase 2 begins
- `workflow_rename_tab "${TICKET_ID}: P3.0 Setup ${FEATURE_TAG}"` ← Phase 3 begins
- `workflow_rename_tab "${TICKET_ID}: P4.1 Implement ${FEATURE_TAG}"` ← Phase 4 begins
- `workflow_rename_tab "${TICKET_ID}: P5.1 Verify · tests ${FEATURE_TAG}"` ← Phase 5 begins
- `workflow_rename_tab "${TICKET_ID}: P7.1 Screenshot ${FEATURE_TAG}"` ← Phase 7 begins
- `workflow_rename_tab "${TICKET_ID}: P8 Finalize ${FEATURE_TAG}"` ← Phase 8 begins
- `workflow_rename_tab "${TICKET_ID}: P9 Ready for review ${FEATURE_TAG}"` ← Wrap-up review handoff begins (build mode ends here; iterate mode continues)
- `workflow_rename_tab "${TICKET_ID}: P10 Merge ${FEATURE_TAG}"` ← Phase 10 begins
- `workflow_rename_tab "${TICKET_ID}: P11 Watch ${FEATURE_TAG}"` ← Phase 11 begins

When there is no substep (phase-level transition), use just `P{phase}`. Within a phase, update the substep number as you move between substeps (e.g. `P6.1` → `P6.3` → `P6.4`) so the tab always reflects the exact substep in progress.

For long-running wait states, add a short suffix:

- `workflow_rename_tab "${TICKET_ID}: P9 Ready for review ${FEATURE_TAG}"`
- `workflow_rename_tab "${TICKET_ID}: P7.1 Screenshot · tour step 3/7 ${FEATURE_TAG}"`

---

## Pane Management Convention

The **pi agent pane stays on the left** and must ALWAYS remain visible. All task panes are stacked on the right, one visible at a time, switchable with `Ctrl+PageUp`/`Ctrl+PageDown`. **Never open a pane that covers or obscures the pi pane.** If the pi pane gets too narrow, resize it wider with `zellij action set-column-width "+20%"` while the pi pane is focused.

**Zellij runs on the HOST.** The cage container connects to the host's zellij server via the mounted socket (`/run/user/$uid/zellij/`). When opening panes from inside the container, the pane's command runs on the **host** — so it must `docker exec` back into the container to run cage-internal commands.

### Panes Are Script-Owned (no agent launch/close code)

**The workflow-do script owns ALL pane launching and closing.** Stage agents never run `zellij run`, `zellij action new-pane`, or any close-pane command — there is no pane-close helper for agents to define. Long-running processes a stage needs (dev servers, DB) run as `bg_run` background tasks, not panes.

For CONTEXT (what you will see on screen): the script launches one pane per stage (`workflow-<stage>-<TICKET>`, right-side, one pane per stage — never two) and runs the run's Chrome as a background process (per-org profile, FIXED CDP port — no Chrome pane). The **pi agent pane stays on the left** and must ALWAYS remain visible; stage panes are side by side on the right and switchable with `Ctrl+PageUp`/`Ctrl+PageDown`. **Never open a pane that covers or obscures the pi pane.**

**Tab ID facts (verified 2026-09-02):** tab IDs are stable across renames
and reordering and never reused (full zellij mechanics in the **zellij**
skill). `WORKFLOW_TAB_ID` captured at launch therefore stays valid for the
whole run no matter how the user reorganizes tabs — the script always
targets the run's tab with `--tab-id`.

### The Tab-Rename Helper — define once at the start of the run

`zellij action rename-tab` renames the **currently focused** tab — useless when
the user may have clicked elsewhere. Target by **stable tab ID** instead.

The cage function already derived the run's tab ID from its own
`$ZELLIJ_PANE_ID` (NOT from focus) and passes it in as `WORKFLOW_TAB_ID`. Use that;
fall back to the same pane-id derivation if unset. **Never use
`current-tab-info` to capture the ID — it answers "which tab is focused
right now", which is exactly the wrong question.**

```bash
# Define once, before any rename (P0.1):
if [ -z "${WORKFLOW_TAB_ID:-}" ] && [ -n "${ZELLIJ_PANE_ID:-}" ]; then
  WORKFLOW_TAB_ID=$(zellij action list-panes -j 2>/dev/null \
    | jq -r --argjson p "$ZELLIJ_PANE_ID" \
        '.[] | select(.is_plugin|not) | select(.id==$p) | .tab_id' 2>/dev/null)
fi

workflow_rename_tab() {
  local new_name="$1"
  [ -n "${WORKFLOW_TAB_ID:-}" ] || { echo "workflow_rename_tab: no WORKFLOW_TAB_ID — skipping" >&2; return 1; }
  zellij action rename-tab "$new_name" --tab-id "$WORKFLOW_TAB_ID" 2>/dev/null
}
```

### Tab Targeting Rules (never rely on focus)

Full zellij mechanics (launch commands, ID discovery, targeted variants,
focus caveats) live in the **zellij** skill. What stage agents need:

- **Bare `rename-tab` / `run` / `close-tab` / `close-pane` act on the FOCUSED
  tab/pane** — the user may be anywhere. Never use them bare when the target
  matters. (For stage agents this is mostly moot: the script owns pane
  launch/close; agents only ever rename tabs.)
- Targeted rename: `zellij action rename-tab <name> --tab-id <id>` — exactly
  what `workflow_rename_tab` does. `list-tabs` is the source of truth for
  discovering IDs.
- Never `go-to-tab`/`move-focus` as a side effect of renaming — targeting by
  ID never changes what the user is looking at.

---


