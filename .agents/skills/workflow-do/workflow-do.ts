#!/usr/bin/env node
/**
 * workflow-do.ts — deterministic stage orchestrator for the workflow-do skill (v7, TypeScript).
 *
 * 1:1 port of workflow-do.sh (v6). Runs INSIDE the cage, launched by the supervisor
 * pi session (workflow-orch-<TICKET>) which stays alive as supervisor. The script —
 * not a model — decides stage order, launches exactly one interactive pi stage agent
 * per MAIN stage in a zellij pane of this run's tab, waits for the stage's
 * STAGE_DONE handoff block, verifies required vars, closes the pane, launches the
 * next stage.
 *
 * Stage agents are FULL INTERACTIVE pi sessions. The human works in the stage pane.
 * Surrender contract (see prompts/*.md) — the stage agent's final actions:
 *   1. append its STAGE_DONE block to $RUN_ENV (KEY="value", append-only)
 *   2. intercom-send its OUT handoff to the launch session (the chief of staff that
 *      started this cage — see WORKFLOW_ORCH_SESSION below)
 *   3. STOP — the stage agent does NOT exit or kill its pane; the SCRIPT closes
 *      the pane by pane-id once the stage is verified, then continues.
 *      (Stage-closure confirmation prompts were removed 2026-10-08.)
 *
 * v8 mechanics (script-owned, authoritative — agents read, never re-derive):
 *   - detectContext(): repo/org/integration-branch/pkg-mgr/HAS_* flags detected
 *     before prebuild, written to the run env + a project profile file
 *   - resolveReviewers(): per-org reviewers.json resolved before ship-p8
 *   - appendRunStats(): token/cost/prompt counters + wall-clock time at run end
 *   - waitCiGreen(): CI poll after build-fix, before review-state re-runs
 *   - ensurePrReadyForReview(): after ship-p8/build-fix, mark the PR ready for
 *     review (`gh pr ready`) and re-read isDraft — a finished run never hands off
 *     a draft PR (decision 2026-10-20), and a failed undraft fails the run loudly
 *   - pre-launch requires check: stage input vars verified BEFORE the pane spins
 *   - PHASE_ORDER: per-stage phase checklist rendered into each task file
 *
 * Modes:
 *   workflow-do.ts build "<brief>"        P0-P3 → P4-P5 → P6-P7 → P8 → Wrap-up
 *                                         → ask close-or-iterate → optional iterate loop
 *   workflow-do.ts iterate "<PR-ref>"     fresh-run iterate: hydrate → review-state
 *                                         → fix rounds → merge gate → P10 → P11-P13
 *
 * Options:
 *   --dry-run          print the full launch sequence, run nothing
 *   --resume           continue from the stage after the last OK STAGE_DONE
 *   --stage <name>     run a single stage (failure-fallback / human intervention)
 *   --fresh            start a new run even if /tmp/workflow-run.env has state
 *   --yes              (accepted, mirrors ASSUME_YES in the bash version)
 *
 * Required env (set by the cage() function in ~/.bashrc):
 *   WORKFLOW_TAB_ID, WORKFLOW_CWD, WORKFLOW_CONTAINER_ID, ZELLIJ_SESSION_NAME
 * Optional:
 *   WORKFLOW_ORCH_SESSION   intercom target for handoffs/reports — the value the
 *                           launching chief of staff session supplies at kickoff (authoritative)
 *   WORKFLOW_STAGE_TIMEOUT  seconds per stage (default 0 = no timeout)
 *   WORKFLOW_POLL_SECS      surrender-poll interval (default 5)
 *   WORKFLOW_RUN_ENV        run-state file (default /tmp/workflow-run.env)
 *   WORKFLOW_RUN_LOG        run log (default /tmp/workflow-do-run.log)
 *
 * Runtime: node + tsx (both already present on the host and inside the cage
 * image; tsx at ~/.pi/agent/npm/node_modules/tsx/dist/cli.mjs). Do NOT launch this
 * script detached, and do not launch it from a pi bash tool call: the run pane runs
 * the launcher, which runs the script in the FOREGROUND and falls back to pi only
 * when the exit code is non-zero (see ~/.agents/skills/workflow-do/run.sh):
 *   WORKFLOW_MODE=build WORKFLOW_TICKET_REF="<ref>" ~/.agents/skills/workflow-do/run.sh
 */

import { spawn } from 'node:child_process'
import {
  appendFileSync,
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  renameSync,
  rmSync,
  writeFileSync,
} from 'node:fs'
import { EOL } from 'node:os'

// ── constants ───────────────────────────────────────────────────────────────
const SKILL_DIR = `${process.env.HOME}/.agents/skills/workflow-do`
const PROMPTS_DIR = `${SKILL_DIR}/prompts`
const SHARED_POLICY = `${SKILL_DIR}/SHARED-POLICY.md`
const RUN_TAG = process.env.WORKFLOW_RUN_ID ?? '' // parallel-run isolation tag (empty = single-run defaults)
const RUN_ENV = process.env.WORKFLOW_RUN_ENV
  ?? (RUN_TAG ? `/tmp/workflow-run-${RUN_TAG}.env` : '/tmp/workflow-run.env')
const RUN_LOG = process.env.WORKFLOW_RUN_LOG ?? '/tmp/workflow-do-run.log'
const STATUS_FILE = process.env.WORKFLOW_STATUS_FILE ?? '/tmp/workflow-run.status'
// Preflight verdict file (scripts/preflight.sh writes it; the tour gate reads it).
const PREFLIGHT_ENV = process.env.WORKFLOW_PREFLIGHT_ENV ?? '/tmp/workflow-preflight.env'
const POLL_SECS = Number(process.env.WORKFLOW_POLL_SECS ?? '5')
const STAGE_TIMEOUT = Number(process.env.WORKFLOW_STAGE_TIMEOUT ?? '0')
const ASSUME_YES = process.env.WORKFLOW_ASSUME_YES === '1'

// pi-intercom broker client (same import intercom-send.mts uses; mounted into cages)
const INTERCOM_CLIENT_PATH =
  '$HOME/.pi/agent/npm/node_modules/pi-intercom/broker/client.ts'

// ── arg parsing ─────────────────────────────────────────────────────────────
interface Args {
  mode: 'build' | 'iterate' | 'review' | ''
  modeArg: string
  dryRun: boolean
  resume: boolean
  fresh: boolean
  singleStage: string
  hostMode: boolean
  hostReason: string
}
const argv = process.argv.slice(2)
const args: Args = {
  mode: '',
  modeArg: '',
  dryRun: argv.includes('--dry-run'),
  resume: argv.includes('--resume'),
  fresh: argv.includes('--fresh'),
  singleStage: '',
  hostMode: argv.includes('--host-mode'),
  hostReason: '',
}
for (let i = 0; i < argv.length; i++) {
  const a = argv[i]
  if (a === '--dry-run' || a === '--resume' || a === '--fresh' || a === '--yes' || a === '--host-mode') continue
  if (a === '--stage') {
    args.singleStage = argv[i + 1] ?? ''
    i++
    continue
  }
  if (a === '--host-reason') {
    args.hostReason = argv[i + 1] ?? ''
    i++
    continue
  }
  if (a === 'build' || a === 'iterate' || a === 'review') {
    args.mode = a
    args.modeArg = argv[i + 1] ?? ''
    i++
    continue
  }
  args.modeArg = args.modeArg ? `${args.modeArg} ${a}` : a
}
if (!args.mode) {
  console.error(
    'usage: workflow-do.ts [--dry-run] [--resume] [--stage <name>] [--fresh] [--host-mode --host-reason "<why the human authorised uncaged>"] build|iterate|review "<brief-or-PR-ref>"',
  )
  process.exit(1)
}
const { mode, modeArg, dryRun, resume, fresh, singleStage } = args

// ── run context (env + derived) ─────────────────────────────────────────────
const TICKET_LABEL = deriveTicketLabel()
const SUPPLIED_ORCH_SESSION = process.env.WORKFLOW_ORCH_SESSION?.trim() ?? ''
// Intercom target every stage handoff/report goes to. A value supplied by the
// chief of staff (the session that launched this cage) is authoritative — stages then talk
// to the launch session directly and the in-cage supervisor is not a relay. The env
// var name is unchanged for runs already in flight, and the legacy
// workflow-orch-<TICKET> name stays the fallback when nothing was supplied.
// Legacy read-back, older in-flight runs only: those recorded the name they had
// resolved. Never re-derive it ourselves — the old name-prefix resolution
// repeatedly failed to resolve and silently skipped sends.
const LEGACY_ORCH_SESSION = SUPPLIED_ORCH_SESSION ? '' : lastVar('ORCHESTRATOR_RESOLVED_NAME')
let ORCH_SESSION = SUPPLIED_ORCH_SESSION || LEGACY_ORCH_SESSION || `workflow-orch-${TICKET_LABEL}`

// ── logging / status / fail ─────────────────────────────────────────────────
function nowStamp(): string {
  return new Date().toISOString().slice(11, 19)
}
function log(msg: string): void {
  const line = `[${nowStamp()}] workflow-do: ${msg}`
  console.log(line)
  try {
    appendFileSync(RUN_LOG, `${line}${EOL}`)
  } catch {
    /* log file is best-effort */
  }
}
function writeStatus(kind: string, detail: string): void {
  try {
    writeFileSync(STATUS_FILE, `${kind}: ${detail}${EOL}`)
  } catch {
    /* best-effort */
  }
}
async function fail(msg: string): Promise<never> {
  log(`❌ ${msg}`)
  await notify(`❌ workflow-do stopped: ${msg} (log: ${RUN_LOG})`)
  writeStatus('failed', msg)
  process.exit(1)
}
function sleep(ms: number): Promise<void> {
  return new Promise(r => setTimeout(r, ms))
}

// ── notify (intercom, non-fatal: notifications must never block the run) ────
async function notify(message: string): Promise<void> {
  if (dryRun) return
  if (!ORCH_SESSION) return
  try {
    const { IntercomClient } = await import(INTERCOM_CLIENT_PATH)
    const client = new IntercomClient()
    try {
      await client.connect({
        name: 'workflow-do-script',
        cwd: process.cwd(),
        model: 'script',
        pid: process.pid,
        startedAt: Date.now(),
        lastActivity: Date.now(),
      })
      await client.send(ORCH_SESSION, { text: message })
    } finally {
      await client.disconnect().catch(() => {})
    }
  } catch (err) {
    log(`⚠️ intercom notification failed (non-fatal): ${(err as Error)?.message ?? err}`)
  }
}

// ── exec helpers (array argv core + bash string convenience) ────────────────
interface RunOpts {
  cwd?: string
  env?: NodeJS.ProcessEnv
  inherit?: boolean
}
interface RunResult {
  code: number
  stdout: string
  stderr: string
}
function run(argList: string[], opts: RunOpts = {}): Promise<RunResult> {
  const [cmd, ...rest] = argList
  return new Promise((resolve, reject) => {
    const child = spawn(cmd, rest, {
      stdio: opts.inherit ? 'inherit' : 'pipe',
      env: { ...process.env, ...opts.env },
      cwd: opts.cwd,
    })
    let out = ''
    let err = ''
    child.stdout?.on('data', d => (out += String(d)))
    child.stderr?.on('data', d => (err += String(d)))
    child.on('close', code =>
      code === 0
        ? resolve({ code: 0, stdout: out, stderr: err })
        : // stdout rides along on the rejection: callers that surface a failed
          // helper's output (preflight FAIL lines) need it, not just stderr.
          reject(Object.assign(new Error(`exit ${code} from: ${argList.join(' ')}`), { code, stdout: out, stderr: err })),
    )
    child.on('error', reject)
  })
}
/** Bash-ish one-liner (&&, $VAR, pipes) — mirrors `sh -c`. */
function sh(cmd: string, opts: RunOpts = {}): Promise<RunResult> {
  return run(['bash', '-c', cmd], opts)
}

// ── zellij wrapper (session-scoped; cage() exports ZELLIJ_SESSION_NAME) ─────
async function zj(zArgs: string[], opts: RunOpts = {}): Promise<RunResult> {
  const session = process.env.ZELLIJ_SESSION_NAME
  const argvFull = session ? ['zellij', '--session', session, ...zArgs] : ['zellij', ...zArgs]
  return run(argvFull, opts)
}
function zjArgs(zArgs: string[]): string[] {
  const session = process.env.ZELLIJ_SESSION_NAME
  return session ? ['zellij', '--session', session, ...zArgs] : ['zellij', ...zArgs]
}

// ── environment verification (fail loudly — the supervisor intervenes) ──
if (!dryRun) {
  if (!process.env.WORKFLOW_TAB_ID)
    await fail('WORKFLOW_TAB_ID not set — must run inside a cage tab (cage() exports it)')
  if (!process.env.WORKFLOW_CWD) await fail('WORKFLOW_CWD not set')
  if (!process.env.ZELLIJ_SESSION_NAME)
    await fail('ZELLIJ_SESSION_NAME not set — not attached to the host zellij session')
  try {
    await zj(['action', 'list-panes'])
  } catch {
    await fail(`zellij IPC unreachable from cage (session: ${process.env.ZELLIJ_SESSION_NAME ?? '?'})`)
  }
  // Cage-required guard (HARD DEFAULT): every workflow-do run must be launched
  // via cage() so parallel runs get isolated dev servers/DB/Chrome/ports. Host
  // mode caused the entire 2026-09-24 friction sequence (Chrome corruption,
  // gh-auth whiplash, shared /tmp/kong/edge-runtime collisions, port fights).
  // The only escape hatch is --host-mode --host-reason "<reason>", which must
  // be explicitly user-authorised and gets recorded in the run env for audit.
  if (!process.env.WORKFLOW_CONTAINER_ID && !args.hostMode)
    await fail('WORKFLOW_CONTAINER_ID not set — workflow-do runs in a cage by default. Kick off via cage() per chief of staff SKILL.md ("Kickoff flow — launch a task as a workflow-do run in a cage"). If the human EXPLICITLY authorised uncaged, pass --host-mode --host-reason "<why>" and the reason will be recorded in the run env.')
  if (args.hostMode && !args.hostReason)
    await fail('--host-mode requires --host-reason "<user-confirmed reason>" — record why the cage is being bypassed (this appears in the run env and every friction scan)')
  if (args.hostMode && process.env.WORKFLOW_CONTAINER_ID)
    await fail('--host-mode set but WORKFLOW_CONTAINER_ID is present — you are inside a cage, drop the flag')
}

// ── run state ───────────────────────────────────────────────────────────────
// /tmp/workflow-run.env is append-only KEY="value" blocks — never overwrite
// (same rule as .workflow-handoff.env; see SHARED-POLICY). Last value wins on read.
function readState(path: string): Record<string, string> {
  const state: Record<string, string> = {}
  if (!existsSync(path)) return state
  for (const line of readFileSync(path, 'utf8').split(EOL)) {
    const m = /^([A-Za-z0-9_]+)="([^"]*)"$/.exec(line)
    if (m) state[m[1]] = m[2]
  }
  return state
}
function appendState(path: string, kv: Record<string, string>): void {
  for (const [k, v] of Object.entries(kv)) {
    if (v.includes('"')) throw new Error(`appendState: value for ${k} contains a double quote (env values must stay single-line KEY="value")`)
    // Every stage does `set -a; source /tmp/workflow-run.env`, so a value containing a backtick or
    // `$(` is EXECUTED by every later stage — a hand-written backtick value once recursed into a
    // ~2600-process fork bomb and blocked a pane for 25 min (<KEY>, 2026-10-08). Refuse them.
    if (/[`]|\$\(/.test(v)) throw new Error(`appendState: value for ${k} contains a backtick or $( — run-env values are sourced, so this would execute (use plain text)`)
    if (v.includes('\n')) throw new Error(`appendState: value for ${k} contains a newline (env values must stay single-line)`)
  }
  mkdirSync(path.slice(0, path.lastIndexOf('/')), { recursive: true })
  appendFileSync(path, Object.entries(kv).map(([k, v]) => `${k}="${v}"`).join(EOL) + EOL)
}
/** Source-semantics read of one var (last value wins). */
function runVar(name: string): string {
  return readState(RUN_ENV)[name] ?? ''
}
/** Stages completed OK (STAGE_DONE=x followed by STAGE_STATUS=ok before next STAGE_DONE). */
function completeStages(path: string): string[] {
  const done: string[] = []
  let pending: string | null = null
  if (!existsSync(path)) return done
  for (const line of readFileSync(path, 'utf8').split(EOL)) {
    const d = /^STAGE_DONE="([^"]+)"/.exec(line)
    const s = /^STAGE_STATUS="([^"]+)"/.exec(line)
    if (d) pending = d[1]
    if (s && pending) {
      if (s[1] === 'ok') done.push(pending)
      pending = null
    }
  }
  return done
}

// ── script-owned SCREENSHOTS_DIR (v8.5 hardening — <KEY> incident) ──────────
// SCREENSHOTS_DIR must NEVER depend on a stage having run. In iterate mode no stage
// before the tour runs `build`, which used to be the only place that recorded it — an
// <KEY> fix round that pushed UI changes (UI_CHANGED=1) died at the tour's pre-launch
// check with "input vars missing: SCREENSHOTS_DIR" instead of capturing. The script owns
// the dir now: derived + mkdir -p'd at run start-up (both modes) and again before every
// stage launches, so the tour can never be blocked by a stage that did not run.
/** Script-owned, unconditional, idempotent. Records SCREENSHOTS_DIR + mkdir -p.
 *  $WORKTREE/screenshots is authoritative (SHARED-POLICY: run artifacts live inside
 *  the worktree); before any stage has resolved WORKTREE (fresh-run start-up) a
 *  run-scoped /tmp dir is used — also policy-sanctioned, never the user's checkout.
 *  A value a STAGE recorded wins, except our own provisional /tmp fallback, which is
 *  upgraded to $WORKTREE/screenshots the moment a stage resolves WORKTREE. */
function ensureScreenshotsDir(where: string): string {
  const recorded = runVar('SCREENSHOTS_DIR')
  const worktree = runVar('WORKTREE')
  const provisional = `/tmp/workflow-screenshots-${TICKET_LABEL}`
  const dir = recorded && !(recorded === provisional && worktree)
    ? recorded
    : worktree
      ? `${worktree}/screenshots`
      : provisional
  if (dryRun) {
    console.log(`  DRY-RUN: SCREENSHOTS_DIR would be "${dir}" (${where})`)
    return dir
  }
  if (dir !== recorded) {
    mkdirSync(dir, { recursive: true })
    appendState(RUN_ENV, { SCREENSHOTS_DIR: dir })
    log(`🗂️ SCREENSHOTS_DIR (script-owned, ${where}): ${dir}`)
  } else {
    mkdirSync(dir, { recursive: true })
  }
  return dir
}

// ── mandatory tour when UI changed (v8.5 hardening — <KEY>) ─────────────────
/** A fix round that pushed UI changes (UI_CHANGED=1) owes a tour. Epoch-based so a
 *  resumed run is not fooled by a tour that completed in an EARLIER round: the tour
 *  is pending when the last build-fix finished after the last tour. Epoch-less
 *  (legacy/resumed) runs fall back to "no completed tour at all". */
function tourPending(): boolean {
  if (runVar('UI_CHANGED') !== '1') return false
  const fix = Number(runVar('STAGE_BUILD_FIX_END_EPOCH') || '0')
  const tour = Number(runVar('STAGE_TOUR_END_EPOCH') || '0')
  if (fix > 0) return fix > tour
  return !completeStages(RUN_ENV).includes('tour')
}
/** No path may park, exit or report success past a mandatory tour: this runs the
 *  pending tour first. runStage fails LOUDLY if it cannot start — a tour that cannot
 *  start is a hard failure, never a silent skip. */
async function runTourIfPending(where: string): Promise<void> {
  if (!tourPending()) return
  log(`📸 UI_CHANGED=1 and the tour has not run yet (${where}) → running the mandatory tour`)
  await runStage('tour')
}

// ── proof-of-capture gate (v8.5 hardening) ───────────────────────────────────
/** Read the PR body + comment bodies at this point (no new state): the tour uploads
 *  screenshots to GitHub's user-attachments CDN, which is the only durable proof. */
async function readPrAttachmentText(): Promise<{ body: string; comments: string }> {
  const pr = runVar('PR_NUMBER')
  const slug = `${runVar('GITHUB_ORG') || runVar('ORG')}/${runVar('REPO_NAME')}`
  if (!pr || slug === '/') return { body: '', comments: '' }
  const tokenEnv = runVar('GH_TOKEN_ENV')
  const token = tokenEnv ? (process.env[tokenEnv] ?? '') : ''
  const auth = token ? `GH_TOKEN="${token}" ` : ''
  const body = await shSoft(`${auth}gh pr view ${pr} --repo "${slug}" --json body -q .body 2>/dev/null`)
  const comments = await shSoft(`${auth}gh pr view ${pr} --repo "${slug}" --json comments -q '.comments[].body' 2>/dev/null`)
  return { body, comments }
}
/** After the tour: the run may not proceed on a tour that produced nothing. Requires
 *  SCREENSHOTS_ANNOTATED=1, at least one image in SCREENSHOTS_DIR, and at least one
 *  user-attachments URL in the PR body (or its comments — the upload form creates a
 *  comment). Anything missing = loud failure with the reason. */
async function verifyTourCaptured(): Promise<void> {
  if (dryRun) {
    console.log('  DRY-RUN: tour proof-of-capture gate — require SCREENSHOTS_ANNOTATED=1, ≥1 image in SCREENSHOTS_DIR, ≥1 user-attachments URL in the PR body')
    return
  }
  const missing: string[] = []
  if (runVar('SCREENSHOTS_ANNOTATED') !== '1') {
    missing.push(`SCREENSHOTS_ANNOTATED=${runVar('SCREENSHOTS_ANNOTATED') || '<unset>'} (must be 1)`)
  }
  const dir = runVar('SCREENSHOTS_DIR')
  let files = 0
  if (!dir) missing.push('SCREENSHOTS_DIR unset')
  else if (!existsSync(dir)) missing.push(`SCREENSHOTS_DIR ${dir} does not exist`)
  else {
    files = readdirSync(dir).filter(f => /\.(png|jpe?g|webp|gif)$/i.test(f)).length
    if (files < 1) missing.push(`no image files in ${dir}`)
  }
  const { body, comments } = await readPrAttachmentText()
  const countUrls = (s: string): number => (s.match(/https:\/\/github\.com\/user-attachments\/assets\/[A-Za-z0-9-]+/g) ?? []).length
  const bodyUrls = countUrls(body)
  const commentUrls = countUrls(comments)
  if (bodyUrls < 1 && commentUrls < 1) {
    missing.push(`no user-attachments URL in the PR body or comments (PR #${runVar('PR_NUMBER') || '?'})`)
  }
  if (missing.length > 0) {
    await fail(`tour proof-of-capture gate failed: ${missing.join('; ')} — the tour MUST capture and upload; no run reports success past it`)
  }
  log(`✅ tour proof-of-capture: SCREENSHOTS_ANNOTATED=1, ${files} image(s) in ${dir}, user-attachments URLs — ${bodyUrls} in body, ${commentUrls} in comments`)
}

if (fresh && existsSync(RUN_ENV)) renameSync(RUN_ENV, `${RUN_ENV}.bak.${Math.floor(Date.now() / 1000)}`)
// Dry-run must not mutate the real run-state file.
if (!dryRun && !existsSync(RUN_ENV)) {
  // NOTE: pi session dirs have 2 leading AND 2 trailing dashes
  // (e.g. $HOME/repos/<githubOrg>/<repo> → --home-pc-repos-<githubOrg>-<repo>--). Strip the leading slash
  // BEFORE the '/'→'-' replacement, and append '--' at the end — prefixing '--'
  // onto the raw replaced string yields 3 leading dashes and a directory that
  // does not exist. (friction: recorded name lacked the trailing '--'
  // and P12.1's session scan found nothing.)
  const sessionDir = `--${process.cwd().replace(/^\//, '').replace(/\//g, '-')}--`
  appendState(RUN_ENV, {
    RUN_STARTED_AT_EPOCH: String(Math.floor(Date.now() / 1000)),
    RUN_SESSION_DIR: sessionDir,
    WORKFLOW_MODE: mode,
    WORKFLOW_CONTAINER_ID: process.env.WORKFLOW_CONTAINER_ID ?? '',
    WORKFLOW_CWD: process.env.WORKFLOW_CWD ?? '',
    WORKFLOW_TAB_ID: process.env.WORKFLOW_TAB_ID ?? '',
    WORKFLOW_ZELLIJ_SESSION: process.env.ZELLIJ_SESSION_NAME ?? '',
    // Definitive intercom target for stage panes: the launch session (chief of staff) when
    // it supplied WORKFLOW_ORCH_SESSION, else the legacy supervisor name — stage
    // agents had repeatedly failed to resolve the supervisor by name and silently
    // skipped handoff sends. Var name kept for in-flight runs.
    ORCHESTRATOR_SESSION: ORCH_SESSION,
    ...(args.hostMode ? { HOST_MODE: '1', HOST_MODE_REASON: args.hostReason } : {}),
  })
}

// v8.5 hardening (<KEY>): materialise the script-owned SCREENSHOTS_DIR at run
// start-up, for BOTH modes and every mode — the tour must never depend on a stage
// having created it (iterate mode never runs `build`). The per-stage call in
// runStage is the safety net; this is the primary derivation.
ensureScreenshotsDir('run start-up')

// ── stage machine ───────────────────────────────────────────────────────────
// ── org gate (step 0 — the run is always scoped to one org) ────────────────
// cage() exports WORKFLOW_ORG (chief-of-staff kickoff resolves it from the ticket/repo
// remote vs org-config.json githubOrg entries). The script re-reads the
// the registry mapping each run (chrome_user_data_dir + keepass_db) and exports
// CHROME_USER_DATA_DIR for later stages. Inside the cage gdrive is NOT mounted,
// so cage()'s exported env vars are authoritative; the sqlite read is the
// host/dry-run path (with /tmp-copy fallback for rclone disk I/O errors).
async function sqliteRead(sql: string): Promise<string> {
  const tdb = `${process.env.HOME}/gdrive/sqlite/the registry`
  const tryDb = async (path: string): Promise<string> => {
    try {
      const { stdout } = await run(['sqlite3', path, sql])
      return stdout.trim()
    } catch {
      return ''
    }
  }
  let out = await tryDb(tdb)
  if (!out) {
    const tmp = `/tmp/triage-wfdo-${process.pid}.db`
    try {
      await run(['cp', tdb, tmp])
      out = await tryDb(tmp)
    } catch {
      /* gdrive not mounted (inside cage) — env vars are authoritative */
    }
    try {
      await run(['rm', '-f', tmp])
    } catch {
      /* best effort */
    }
  }
  return out
}
async function readKnownOrgs(): Promise<string[]> {
  const out = await sqliteRead('SELECT name FROM orgs;')
  return out ? out.split('\n').map(s => s.trim()).filter(Boolean) : []
}
async function readOrgRow(org: string): Promise<{ chrome: string; keepass: string } | null> {
  const row = await sqliteRead(
    `SELECT COALESCE(chrome_user_data_dir,'')||'|'||COALESCE(keepass_db,'') FROM orgs WHERE name='${org}';`,
  )
  if (!row) return null
  const [chrome = '', keepass = ''] = row.split('|')
  return { chrome, keepass }
}

const WORKFLOW_ORG = process.env.WORKFLOW_ORG ?? ''
if (dryRun) {
  console.log(`org gate: WORKFLOW_ORG=${WORKFLOW_ORG || '<missing>'}  CHROME_USER_DATA_DIR=${process.env.CHROME_USER_DATA_DIR || '<unset>'}  KEEPASS_DB=${process.env.KEEPASS_DB || '<unset>'}`)
} else if (!WORKFLOW_ORG) {
  appendState(RUN_ENV, { ORG_PENDING: '1' })
  await fail(
    'WORKFLOW_ORG not set — ask the user which org this run is for, export WORKFLOW_ORG=<org> (cage() resolves the the registry mounts), then relaunch with --resume (ORG_PENDING=1 recorded in the run env)',
  )
} else {
  const known = await readKnownOrgs()
  // Inside the cage the db is unreachable — cage() only exports CHROME_USER_DATA_DIR
  // for orgs it resolved, so its presence proves the org is known. A relaunch inside
  // an EXISTING cage (run.sh started by hand in a fresh pane — e.g. the `--stage <n>`
  // recovery line run.sh prints, or a chief of staff-driven stage rerun) carries WORKFLOW_ORG
  // + WORKFLOW_CONTAINER_ID but not CHROME_USER_DATA_DIR, so treat a caged launch as
  // authoritative too: the cage was created for this org, i.e. cage() already resolved
  // it. Without this the gate fails on a valid org (<KEY-209>, 2026-10-16) and the
  // relaunch dies before any stage pane exists.
  const inCage = Boolean(process.env.WORKFLOW_CONTAINER_ID)
  const knownOrg = known.length > 0
    ? known.includes(WORKFLOW_ORG)
    : Boolean(process.env.CHROME_USER_DATA_DIR) || inCage
  if (!knownOrg) {
    appendState(RUN_ENV, { ORG_PENDING: '1' })
    await fail(
      `WORKFLOW_ORG="${WORKFLOW_ORG}" is not a known org in the registry — ask the user which org this run is for, export WORKFLOW_ORG=<org>, then relaunch with --resume (ORG_PENDING=1 recorded)`,
    )
  }
  const row = await readOrgRow(WORKFLOW_ORG)
  process.env.CHROME_USER_DATA_DIR ||= (
    process.env.WORKFLOW_CONTAINER_ID
      ? '$HOME/chrome-org'
      : row?.chrome || `${process.env.HOME}/secrets/${WORKFLOW_ORG}/chrome-user-data-dir`
  )
  const keepass = process.env.KEEPASS_DB || row?.keepass || ''
  log(`🏢 run org: ${WORKFLOW_ORG} — chrome profile: ${process.env.CHROME_USER_DATA_DIR} · keepass: ${keepass || 'none'} · secrets-org: $HOME/secrets-org`)
  appendState(RUN_ENV, { WORKFLOW_ORG, CHROME_USER_DATA_DIR: process.env.CHROME_USER_DATA_DIR, KEEPASS_DB: keepass })
}

// ── script-owned context detection (v8 — authoritative; agents read run env) ──
// Replaces prebuild P1.1/P1.4/P1.5/P1.7: repo root/name/org, integration branch,
// package manager, stack flags, project profile (package.json scripts dump).
// Detection failures are non-fatal: unset vars are left for prebuild to fill
// once (and record as a loose end, per SHARED-POLICY).
async function shSoft(cmd: string, opts: RunOpts = {}): Promise<string> {
  try {
    const { stdout } = await sh(cmd, opts)
    return stdout.trim()
  } catch {
    return ''
  }
}
function fileExistsIn(root: string, names: string[]): string {
  for (const n of names) if (existsSync(`${root}/${n}`)) return n
  return ''
}
async function detectContext(): Promise<void> {
  const cwd = process.env.WORKFLOW_CWD || process.cwd()
  const repoRoot = (await shSoft(`git -C "${cwd}" rev-parse --show-toplevel 2>/dev/null`)) || cwd
  const repoName = repoRoot.slice(repoRoot.lastIndexOf('/') + 1)
  const remoteUrl = await shSoft(`git -C "${repoRoot}" remote get-url origin 2>/dev/null`)
  const ghOrg = /github\.com[:/]([^/]+)\/([^/"'\s]+?)(?:\.git)?$/.exec(remoteUrl)?.[1] ?? ''

  // integration branch: prefer develop, else the remote HEAD
  let integrationBranch = ''
  if (await shSoft(`git -C "${repoRoot}" ls-remote --heads origin develop 2>/dev/null`)) {
    integrationBranch = 'develop'
  } else {
    const head = await shSoft(`git -C "${repoRoot}" ls-remote --symref origin HEAD 2>/dev/null`)
    integrationBranch = /refs\/heads\/(\S+)/.exec(head)?.[1] ?? ''
  }

  // package manager (lockfile probes)
  let pkgMgr = ''
  if (existsSync(`${repoRoot}/pnpm-lock.yaml`)) pkgMgr = 'pnpm'
  else if (existsSync(`${repoRoot}/yarn.lock`)) pkgMgr = 'yarn'
  else if (existsSync(`${repoRoot}/package-lock.json`)) pkgMgr = 'npm'
  else if (existsSync(`${repoRoot}/requirements.txt`) || existsSync(`${repoRoot}/pyproject.toml`)) pkgMgr = 'pip'

  // dir + monorepo detection (same probes the skill used)
  const frontendDir = fileExistsIn(repoRoot, ['frontend', 'dashboard', 'app'])
  const backendDir = fileExistsIn(repoRoot, ['backend', 'server', 'api'])
  let isMonorepo = ''
  if (existsSync(`${repoRoot}/package.json`)) {
    const ws = await shSoft(`find "${repoRoot}" -maxdepth 2 -name package.json -not -path "*/node_modules/*" | wc -l`)
    if (Number(ws) > 1) isMonorepo = 'true'
  }

  // deployment/monitoring flags
  const hasVercel = existsSync(`${repoRoot}/vercel.json`) || existsSync(`${repoRoot}/.vercel`) ? 'true' : ''
  const hasGhActions = existsSync(`${repoRoot}/.github/workflows`) ? 'true' : ''
  const hasCircleci = existsSync(`${repoRoot}/.circleci`) ? 'true' : ''
  const hasJenkins = existsSync(`${repoRoot}/Jenkinsfile`) ? 'true' : ''
  const pkgRaw = existsSync(`${repoRoot}/package.json`) ? readFileSync(`${repoRoot}/package.json`, 'utf8') : ''
  const hasSupabase = existsSync(`${repoRoot}/supabase`) || /supabase/.test(pkgRaw) ? 'true' : ''
  const hasDatadog = /dd-trace|datadog/.test(pkgRaw) ? 'true' : ''

  // project profile: detected vars + package.json scripts dump (agents read this
  // instead of re-probing; AGENTS.md/README reading stays agent-side)
  const profilePath = '/tmp/workflow-project-profile.md'
  const scriptsDump = (() => {
    try {
      const d = JSON.parse(pkgRaw) as { scripts?: Record<string, string> }
      return Object.entries(d.scripts ?? {}).map(([k, v]) => `- \`${k}\`: ${v}`).join(EOL) || '- (no scripts)'
    } catch {
      return '- (no package.json)'
    }
  })()
  if (dryRun) {
    console.log(`  DRY-RUN: detectContext → would write profile ${profilePath} (repo=${repoName} org=${ghOrg || '?'} branch=${integrationBranch || '?'} pkgmgr=${pkgMgr || '?'})`)
    return
  }
  writeFileSync(profilePath, [
    '# workflow-do project profile (script-detected — authoritative)',
    '',
    `REPO_ROOT=${repoRoot}`,
    `REPO_NAME=${repoName}`,
    `GITHUB_ORG=${ghOrg}`,
    `INTEGRATION_BRANCH=${integrationBranch}`,
    `PKG_MGR=${pkgMgr || '(undetected — prebuild fills + loose end)'}`,
    `FRONTEND_DIR=${frontendDir || '(none)'}`,
    `BACKEND_DIR=${backendDir || '(none)'}`,
    `IS_MONOREPO=${isMonorepo || 'false'}`,
    '',
    '## package.json scripts (root)',
    scriptsDump,
  ].join(EOL) + EOL)

  const kv: Record<string, string> = {
    REPO_ROOT: repoRoot,
    REPO_NAME: repoName,
    ORG: WORKFLOW_ORG,
    PROJECT_PROFILE_FILE: profilePath,
  }
  if (ghOrg) kv.GITHUB_ORG = ghOrg
  if (integrationBranch) kv.INTEGRATION_BRANCH = integrationBranch
  if (pkgMgr) kv.PKG_MGR = pkgMgr
  if (frontendDir) { kv.HAS_FRONTEND = 'true'; kv.FRONTEND_DIR = frontendDir }
  if (backendDir) kv.BACKEND_DIR = backendDir
  if (isMonorepo) kv.IS_MONOREPO = isMonorepo
  if (hasVercel) kv.HAS_VERCEL = hasVercel
  if (hasGhActions) kv.HAS_GH_ACTIONS = hasGhActions
  if (hasCircleci) kv.HAS_CIRCLECI = hasCircleci
  if (hasJenkins) kv.HAS_JENKINS = hasJenkins
  if (hasSupabase) kv.HAS_SUPABASE = hasSupabase
  if (hasDatadog) kv.HAS_DATADOG = hasDatadog
  appendState(RUN_ENV, kv)
  log(`🔎 context detected: ${repoName} · org ${ghOrg || '?'} · branch ${integrationBranch || '?'} · ${pkgMgr || '?'}`)
}

// ── script-owned reviewer resolution (v8 — replaces ship P8.3b resolution) ────
// The org's secrets dir comes from org-config.json (an org may set `secretsDir`
// when its secrets folder is named differently from its org key). Missing
// reviewers.json or missing entry = FATAL (fail before the pane spins);
// empty-string entry = explicit skip. The ship-p8 stage just applies $REVIEWERS
// with gh pr edit.
async function resolveReviewers(): Promise<void> {
  const org = runVar('WORKFLOW_ORG') || WORKFLOW_ORG
  const repoName = runVar('REPO_NAME')
  if (!repoName) {
    if (dryRun) { console.log('  DRY-RUN: resolveReviewers skipped (REPO_NAME unknown yet)'); return }
    await fail('resolveReviewers: REPO_NAME not in run env — cannot resolve reviewers')
  }
  // idempotent resume: if the resolver (or supervisor append) already recorded a
  // decision, re-resolution could overwrite it (runVar returns '' for missing).
  const resolved = runVar('REVIEWERS_DECISION')
  if (resolved !== '') {
    if (dryRun) { console.log(`  DRY-RUN: reviewers already resolved (${resolved}: ${runVar('REVIEWERS') || 'skip'}) — not re-resolving`); return }
    log(`👥 reviewers already resolved in run env: ${runVar('REVIEWERS') || '(explicit skip)'} (${resolved})`)
    return
  }
  // org → secrets dir via org-config (match `org` or `githubOrg`)
  let secretsDir = ''
  try {
    const cfg = JSON.parse(readFileSync(`${process.env.HOME}/secrets/org-config.json`, 'utf8')) as { orgs?: Array<{ org?: string; githubOrg?: string; secretsDir?: string }> }
    for (const o of cfg.orgs ?? []) {
      if (o.org === org || o.githubOrg === org) {
        secretsDir = `${process.env.HOME}/secrets/${o.secretsDir ?? o.org ?? ''}`
        break
      }
    }
  } catch {
    secretsDir = ''
  }
  // cage runs mount the org's secrets dir at $HOME/secrets-org — fall back
  // to it when the org-config path is unresolved or missing there (the run org
  // key can differ from the org-config key, which can differ from the GitHub org)
  const candidates = [secretsDir ? `${secretsDir}/reviewers.json` : '', '$HOME/secrets-org/reviewers.json']
    .filter((p, i, a) => p !== '' && a.indexOf(p) === i)
  const reviewersPath = candidates.find((p) => existsSync(p)) ?? ''
  const failMissing = async (why: string): Promise<void> => {
    if (dryRun) { console.log(`  DRY-RUN: resolveReviewers FATAL (${why})`); return }
    await fail(`reviewers config unresolved (${why}) — add the key to ${candidates.join(' or ') || '<org secrets dir>/reviewers.json'} or set it to an empty string for explicit skip, then relaunch with --resume`)
  }
  if (!reviewersPath) return failMissing(`no reviewers.json for org ${org} (looked in ${candidates.join(', ') || 'no candidate paths'})`)
  let map: Record<string, string>
  try {
    map = JSON.parse(readFileSync(reviewersPath, 'utf8')) as Record<string, string>
  } catch {
    return failMissing(`unparseable reviewers.json at ${reviewersPath}`)
  }
  // Keys use the ACTUAL GitHub remote owner — exact "$ORG/$REPO" first, then any
  // key ending in "/$REPO" (the remote owner may differ from the org-config key).
  let reviewers = map[`${org}/${repoName}`]
  if (reviewers === undefined) {
    const suffixKey = Object.keys(map).find(k => k.endsWith(`/${repoName}`))
    if (suffixKey !== undefined) reviewers = map[suffixKey]
  }
  if (reviewers === undefined) return failMissing(`no entry for ${org}/${repoName} (exact or /${repoName} suffix)`)
  if (dryRun) {
    console.log(`  DRY-RUN: would append REVIEWERS="${reviewers}" (${reviewers ? 'requested' : 'explicit skip'})`)
    return
  }
  appendState(RUN_ENV, { REVIEWERS: reviewers, REVIEWERS_DECISION: reviewers ? 'requested' : 'skip' })
  log(`👥 reviewers resolved: ${reviewers || '(explicit skip)'}`)
}

// ── script-owned run stats (v8 — replaces post P13.1b counters + timing) ──────
// Appended at every park/done exit. The post stage (P13) reads these from the
// run env instead of scanning session JSONLs itself.
let statsPrior: Record<string, number> | null = null
async function appendRunStats(): Promise<void> {
  if (dryRun) return
  const kv: Record<string, string> = { RUN_ENDED_AT_EPOCH: String(Math.floor(Date.now() / 1000)) }
  const startedAt = runVar('RUN_STARTED_AT_EPOCH')
  if (startedAt) {
    kv.TIME_TAKEN_MINUTES = String(Math.max(0, Math.floor((Number(kv.RUN_ENDED_AT_EPOCH) - Number(startedAt)) / 60)))
  }
  const sessionDirName = runVar('RUN_SESSION_DIR')
  if (sessionDirName) {
    const dir = `${process.env.HOME}/.pi/agent/sessions/${sessionDirName}`
    if (existsSync(dir)) {
      // Only THIS run's own session files: every pane of the run — the supervisor
      // and each stage — is named workflow-<something>-<TICKET_LABEL>, and that name
      // is embedded in its launch prompt. ORCH_SESSION is deliberately NOT matched
      // and its session file is excluded outright: it is the chief of staff/launch session,
      // a different session outside this run, so counting it would fold the chief of staff's
      // own tokens and cost into the run's totals. Without the filter, concurrent
      // runs in the same repo session dir bleed into each other's totals.
      const jq = `grep -l -e "workflow-[^\\"]*-${TICKET_LABEL}" "${dir}"/*.jsonl 2>/dev/null | grep -v -F "_${ORCH_SESSION}.jsonl" | xargs -r cat 2>/dev/null | jq -R 'fromjson? // empty' | jq -s 'map(select(.type == "message" and (.message.usage != null))) | {token_total: (map(.message.usage.totalTokens // 0) | add // 0), token_input: (map(.message.usage.input // 0) | add // 0), token_output: (map(.message.usage.output // 0) | add // 0), cost_total: (map(.message.usage.cost.total // 0) | add // 0), human_prompts: (map(select(.message.role == "user")) | length)}'`
      try {
        const { stdout } = await sh(jq)
        const s = JSON.parse(stdout) as Record<string, number>
        // Accumulate across rounds: the run env carries the prior round's
        // totals (hydrated from the durable worktree handoff). Keep the prior
        // in memory so repeated calls within one instance do not re-add it.
        if (statsPrior === null) {
          statsPrior = {
            token_total: Number(runVar('TOKEN_TOTAL') ?? '0'),
            token_input: Number(runVar('TOKEN_INPUT') ?? '0'),
            token_output: Number(runVar('TOKEN_OUTPUT') ?? '0'),
            cost_total: Number(runVar('COST_TOTAL') ?? '0'),
            human_prompts: Number(runVar('HUMAN_PROMPT_COUNT') ?? '0'),
          }
        }
        kv.TOKEN_TOTAL = String(statsPrior.token_total + (s.token_total ?? 0))
        kv.TOKEN_INPUT = String(statsPrior.token_input + (s.token_input ?? 0))
        kv.TOKEN_OUTPUT = String(statsPrior.token_output + (s.token_output ?? 0))
        kv.COST_TOTAL = String(statsPrior.cost_total + (s.cost_total ?? 0))
        kv.HUMAN_PROMPT_COUNT = String(statsPrior.human_prompts + (s.human_prompts ?? 0))
        // Durable: the next round of this ticket hydrates these totals from
        // the worktree handoff and accumulates on top.
        const worktree = runVar('WORKTREE')
        if (worktree && existsSync(worktree)) {
          appendState(`${worktree}/.workflow-handoff.env`, {
            TOKEN_TOTAL: kv.TOKEN_TOTAL, TOKEN_INPUT: kv.TOKEN_INPUT,
            TOKEN_OUTPUT: kv.TOKEN_OUTPUT, COST_TOTAL: kv.COST_TOTAL,
            HUMAN_PROMPT_COUNT: kv.HUMAN_PROMPT_COUNT,
          })
        }
      } catch {
        log('⚠️ run stats unavailable (jq/session dir) — post stage falls back to its own scan')
      }
    }
  }
  appendState(RUN_ENV, kv)
  log(`📊 run stats: ${kv.TIME_TAKEN_MINUTES ?? '?'}min · tokens ${kv.TOKEN_TOTAL ?? 'n/a'}`)
}

// ── script-owned CI wait (v8 — after build-fix, before review-state re-runs) ──
// gh pr checks exits 0 when all checks pass. Exit 127 (gh missing) skips the
// wait silently; review-state still fetches state itself either way.
async function waitCiGreen(): Promise<void> {
  const pr = runVar('PR_NUMBER')
  const org = runVar('ORG') || runVar('WORKFLOW_ORG')
  const repo = runVar('REPO_NAME')
  if (!pr || !repo) return
  const timeout = Number(process.env.WORKFLOW_CI_TIMEOUT ?? '600')
  if (dryRun) { console.log(`  DRY-RUN: poll CI green on PR #${pr} (max ${timeout}s)`); return }
  let waited = 0
  log(`⏳ waiting for CI green on PR #${pr} (max ${timeout}s)`)
  while (waited < timeout) {
    const r = await shSoft(`gh pr checks ${pr} --repo "${org}/${repo}" >/dev/null 2>&1; echo $?`)
    if (r === '0') { log('✅ CI green on fix round'); return }
    if (r === '127' || r === '') { log('⚠️ gh unavailable to script — skipping CI wait'); return }
    await sleep(30000)
    waited += 30
  }
  log(`⚠️ CI not green after ${timeout}s — continuing; review-state will classify`)
}

// ── script-owned ready-for-review gate (v8.6) ───────────────────────────────
// Decision 2026-10-20 (supersedes the 2026-10-08 "build never marks ready" rule):
// a finished build/iterate run hands off a PR that is READY FOR REVIEW. ship-p8
// and build-fix run `gh pr ready`; this gate re-reads `isDraft` from GitHub
// afterwards — the run never trusts the stage's own claim — and fails LOUDLY if
// the PR is still a draft, instead of reporting a complete handoff that needs a
// manual undraft. Ticket-status rules are untouched: the run still stops at the
// PRE-REVIEW status and never writes the review-pending status.
function ghRepoSlug(): string {
  const explicit = runVar('GH_REPO')
  if (explicit) return explicit
  const owner = runVar('GITHUB_ORG')
  const repo = runVar('REPO_NAME')
  return owner && repo ? `${owner}/${repo}` : ''
}
function ghTokenEnv(): NodeJS.ProcessEnv {
  // Never inline the token into a command string: run() embeds the argv in its
  // rejection message and fail() logs that message. Pass it through the child env.
  const tokenEnv = runVar('GH_TOKEN_ENV')
  const token = tokenEnv ? (process.env[tokenEnv] ?? '') : ''
  return token ? { GH_TOKEN: token } : {}
}
interface PrDraftState {
  state: string
  isDraft: string
}
async function readPrDraftState(repo: string, pr: string): Promise<PrDraftState | null> {
  const out = await shSoft(
    `gh pr view ${pr} --repo "${repo}" --json state,isDraft --jq '.state + " " + (.isDraft|tostring)'`,
    { env: ghTokenEnv() },
  )
  const [state, isDraft] = out.split(/\s+/)
  return state && isDraft ? { state, isDraft } : null
}
async function ensurePrReadyForReview(stage: StageName): Promise<void> {
  const pr = runVar('PR_NUMBER')
  const repo = ghRepoSlug()
  if (dryRun) {
    console.log(`  DRY-RUN: after ${stage} → assert PR #${pr || '<PR_NUMBER>'} in ${repo || '<repo unresolved>'} is ready for review (gh pr ready if draft, then verify isDraft=false)`)
    return
  }
  if (!pr) return
  if (!repo.includes('/')) {
    await fail(`PR ready gate (${stage}): repo slug unresolved in ${RUN_ENV} (need GITHUB_ORG+REPO_NAME or GH_REPO) — cannot verify PR #${pr}`)
  }
  const before = await readPrDraftState(repo, pr)
  if (!before) {
    await fail(`PR ready gate (${stage}): cannot read PR #${pr} from ${repo} (gh pr view failed) — refusing to report the handoff complete`)
    return
  }
  if (before.state === 'MERGED' || before.state === 'CLOSED') {
    log(`📮 PR #${pr} is ${before.state} — draft state no longer applies (no undraft)`)
    appendState(RUN_ENV, { PR_READY_FOR_REVIEW: before.state === 'MERGED' ? 'merged' : 'n/a' })
    return
  }
  if (before.isDraft === 'false') {
    log(`✅ PR #${pr} is already ready for review (isDraft=false)`)
  } else {
    log(`📮 PR #${pr} is still a DRAFT — marking ready for review (gh pr ready)`)
    try {
      await sh(`gh pr ready ${pr} --repo "${repo}"`, { env: ghTokenEnv() })
    } catch (err) {
      const e = err as { stderr?: string; stdout?: string; message?: string }
      await fail(`PR ready gate (${stage}): gh pr ready #${pr} failed — ${(e.stderr || e.stdout || e.message || '').trim().slice(0, 300)}. The PR is still a draft; fix the cause and relaunch with --resume.`)
    }
  }
  // Verify the real state afterwards — a gh exit code is not proof.
  const after = await readPrDraftState(repo, pr)
  if (!after) {
    await fail(`PR ready gate (${stage}): cannot re-read PR #${pr} after gh pr ready — isDraft=false unverified`)
    return
  }
  if (after.isDraft !== 'false') {
    await fail(`PR ready gate (${stage}): PR #${pr} is STILL a draft after gh pr ready (state=${after.state}, isDraft=${after.isDraft}) — refusing to report the handoff complete`)
  }
  appendState(RUN_ENV, {
    PR_READY_FOR_REVIEW: '1',
    PR_READY_AT: new Date().toISOString().replace(/\.\d+Z$/, 'Z'),
  })
  log(`✅ PR #${pr} verified ready for review (isDraft=false) — recorded PR_READY_FOR_REVIEW=1`)
}

// spec: kind | prompt file | required OUT vars
type StageName =
  | 'scout' | 'prebuild' | 'build' | 'tour' | 'ship-p8' | 'wrap-up'
  | 'hydrate' | 'review-state' | 'build-fix' | 'ship-p10' | 'post'
  | 'review-gather' | 'review-audit' | 'review-walkthrough' | 'review-verdict'
interface StageSpec {
  kind: 'interactive' | 'autonomous'
  requires: string[]
  // v8: input vars the script verifies BEFORE launching the pane (fail fast —
  // replaces the in-skill "FATAL: PR_NUMBER empty" guards)
  preRequires?: string[]
}
// Every stage pane opens SIDE BY SIDE (--direction right) — one uniform direction,
// user directive 2026-10-15; there is no per-stage right/stacked choice.
const STAGE_SPECS: Record<StageName, StageSpec> = {
  scout: {
    kind: 'autonomous',
    requires: ['SCOUT_FILE'],
    preRequires: [],
  },
  'review-gather': {
    kind: 'autonomous',
    requires: ['PR_NUMBER', 'ORG', 'REPO_NAME', 'GITHUB_ORG', 'FINDINGS_FILE', 'REVIEW_AREAS', 'WORKTREE', 'SCREENSHOTS_DIR'],
    preRequires: [],
  },
  'review-audit': {
    kind: 'autonomous',
    requires: ['AUDIT_DONE', 'STAGE_DONE'],
    preRequires: ['FINDINGS_FILE', 'REVIEW_AREAS', 'PR_NUMBER', 'WORKTREE'],
  },
  'review-walkthrough': {
    kind: 'interactive',
    requires: ['DECIDED_COUNT', 'REVIEW_TOUR_NEEDED', 'STAGE_DONE'],
    preRequires: ['FINDINGS_FILE', 'REVIEW_AREAS', 'PR_NUMBER'],
  },
  'review-verdict': {
    kind: 'interactive',
    requires: ['REVIEW_SUBMITTED', 'REVIEW_VERDICT', 'STAGE_DONE'],
    preRequires: ['FINDINGS_FILE', 'DECIDED_COUNT', 'PR_NUMBER'],
  },
  prebuild: {
    kind: 'interactive',
    requires: ['TICKET_ID', 'ORG', 'REPO_NAME', 'WORKTREE', 'BRANCH_NAME', 'PR_NUMBER', 'PR_URL', 'FEATURE_TAG', 'INTEGRATION_BRANCH'],
    preRequires: [],
  },
  build: {
    kind: 'autonomous',
    requires: ['TICKET_ID', 'WORKTREE', 'BRANCH_NAME', 'PR_NUMBER', 'PR_URL', 'SCREENSHOTS_DIR', 'IMPLEMENTATION_COMPLETE'],
    preRequires: ['BRIEF_FILE', 'WORKTREE', 'BRANCH_NAME'],
  },
  tour: {
    kind: 'autonomous',
    // v8.5 hardening (<KEY>): SCREENSHOTS_DIR is NOT an input requirement — the
    // script derives + creates it before the pane launches (ensureScreenshotsDir), so
    // listing it here could only re-introduce the pre-launch abort that killed the
    // iterate tour. SCREENSHOTS_ANNOTATED stays a required OUT var; the proof-of-capture
    // gate after the stage is the real check that the tour captured and uploaded.
    requires: ['TICKET_ID', 'PR_NUMBER', 'SCREENSHOTS_ANNOTATED'],
    preRequires: ['BRIEF_FILE', 'PR_NUMBER'],
  },
  'ship-p8': {
    kind: 'autonomous',
    requires: ['TICKET_ID', 'PR_NUMBER', 'PR_READY', 'PR_READY_FOR_REVIEW'],
    preRequires: ['TICKET_ID', 'PR_NUMBER', 'ORG', 'REPO_NAME'],
  },
  'wrap-up': {
    kind: 'interactive',
    requires: ['TICKET_ID', 'PR_NUMBER', 'DECISION_CLOSE_OR_ITERATE', 'FOLLOWUP_DECISION'],
    preRequires: ['TICKET_ID', 'PR_NUMBER'],
  },
  hydrate: {
    kind: 'autonomous',
    requires: ['TICKET_ID', 'ORG', 'REPO_NAME', 'WORKTREE', 'BRANCH_NAME', 'PR_NUMBER', 'PR_URL'],
    preRequires: [],
  },
  'review-state': {
    kind: 'interactive',
    requires: ['TICKET_ID', 'PR_NUMBER', 'RECOMMENDED_ACTION', 'LOOP_DECISION'],
    preRequires: ['PR_NUMBER', 'ORG', 'REPO_NAME'],
  },
  'build-fix': {
    kind: 'autonomous',
    requires: ['TICKET_ID', 'WORKTREE', 'PR_NUMBER', 'FIXES_PUSHED', 'UI_CHANGED', 'PR_READY_FOR_REVIEW'],
    preRequires: ['FIX_LIST_FILE', 'WORKTREE', 'PR_NUMBER'],
  },
  'ship-p10': {
    kind: 'autonomous',
    requires: ['TICKET_ID', 'PR_NUMBER', 'PR_MERGED'],
    preRequires: ['PR_NUMBER', 'ORG', 'REPO_NAME'],
  },
  post: {
    kind: 'autonomous',
    requires: ['TICKET_ID', 'PR_NUMBER', 'CLEANUP_DONE'],
    preRequires: ['TICKET_ID', 'PR_NUMBER', 'ORG', 'REPO_NAME', 'WORKTREE'],
  },
}
function stagePrompt(stage: StageName): string {
  const src = `${PROMPTS_DIR}/${stage}.md`
  if (!RUN_TAG) return src
  // Parallel-run isolation (WORKFLOW_RUN_ID set): prompt files hardcode the
  // default /tmp paths; render a per-run copy with the run's real paths so
  // concurrent runs never read or write each other's state.
  const tagged = `/tmp/workflow-prompt-${stage}-${RUN_TAG}.md`
  let body = readFileSync(src, 'utf8')
  body = body.split('/tmp/workflow-run.env').join(RUN_ENV)
  body = body.split('/tmp/workflow-fixlist.md').join(`/tmp/workflow-fixlist-${RUN_TAG}.md`)
  body = body.split('/tmp/workflow-task-').join(`/tmp/workflow-task-${RUN_TAG}-`)
  body = body.split('/tmp/workflow-brief.md').join(`/tmp/workflow-brief-${RUN_TAG}.md`)
  body = body.split('/tmp/workflow-scout.md').join(`/tmp/workflow-scout-${RUN_TAG}.md`)
  body = body.split('/tmp/workflow-loose-ends.md').join(`/tmp/workflow-loose-ends-${RUN_TAG}.md`)
  writeFileSync(tagged, body)
  return tagged
}

// ── task file ───────────────────────────────────────────────────────────────
// Per-stage phase checklist (v8): the order lives in THIS table — rendered into
// the task file — so the agent never relies on remembering the SKILL.md sequence.
const PHASE_ORDER: Record<StageName, string[]> = {
  scout: [
    '1. Resolve the ticket fully from the tracker',
    '2. Scan the repo for relevant code/files',
    '3. Load org conventions (AGENTS.md/README/workflowDo block)',
    '4. Check existing PRs/branches/CI for the ticket',
    '5. Write the context pack to /tmp/workflow-scout.md (script instructs the per-run path)',
  ],
  prebuild: [
    'P0.1 Read APPEND_SYSTEM.md',
    'P0.2 Update pi + extensions',
    'P0.3 Verify zellij + define workflow_rename_tab',
    'P0.4 Verify git signing (per org signCommits)',
    'P0.5 Attach to script-owned Chrome',
    'P0.6 Verify agent-browser (nav + screenshot)',
    'P1.2 Read tracker skill + workflowDo block',
    'P1.3a Verify GH token + repo access',
    'P1.3b Verify GH browser login',
    'P1.6 Discover project commands (package.json scripts are in PROJECT_PROFILE_FILE; read AGENTS.md/README for the rest)',
    'P1.8 Docs/wiki discovery',
    'P1.9 Resumability check (existing worktree/branch/PR → resume)',
    'P1.10 Ticket resolution — the ticket MUST already exist (runs never create tickets)',
    'P2.1 Set assignee to the implementer FIRST',
    'P2.2 Explore the codebase before asking',
    'P2.3 Grill — DB-first decision tree answered from code, assumptions recorded (autonomous; the only ask is the ticket-creation question for bare-idea runs)',
    'P2.4 Readiness checklist (all 8 must hold)',
    'P2.4b Write the 5-element brief → /tmp/workflow-brief.md',
    'P2.5 Write brief + decisions back to the ticket',
    'P2.6 Advance status to ready-to-start',
    'P2.7 Set story points',
    'P3.0 Monitor + Chrome viewport',
    'P3.1 Sync integration branch',
    'P3.2 Worktree + feature branch',
    'P3.3 Push branch',
    'P3.4 Symlink secrets',
    'P3.5 Install deps + codegen (MANDATORY before commits)',
    'P3.6 DB up + migrate + hydrate (bg_run)',
    'P3.7 Dev servers (bg_run + poll ready)',
    'P3.8 Baseline tests + lint',
    'P3.10 Ticket → in progress',
    'P3.11 Draft PR',
    'P3.12 PR link on ticket (fallback: append to ticket body)',
  ],
  build: [
    'P4.1 Implement — DB → backend → frontend (codegen on pre-commit failure)',
    'P5.1 Verify implementation (DB schema / API + RBAC / UI)',
    'P5.2 Automated tests + typecheck + lint (mocks are not the real API)',
    'P5.3 Screenshot dir + sample + edge-case data',
    'P5.4 DRY check',
    'P5.5 Quality check (silent failures / DB structure / security / UX)',
    'P5.6 Self-review + docs + sync base branch + CI green',
    'P5.7 Summary appended to PR body',
    'P5.8 AI-slop check',
  ],
  tour: [
    'P7.1 Plan the screenshots',
    'P7.2 Services + sample data + viewport',
    'P7.3 BEFORE captures + red annotate (restore the fix after)',
    'P7.4 AFTER captures + DB verify + persistence proof',
    'P7.5 Annotate remaining screenshots',
    'P7.6 Upload to PR body (scripts/upload-screenshot.sh; fold old comments)',
    'P7.7 Open ticket + PR in browser tabs',
    'P7.8 Video tour — workflow-video-tour V1-V7 (storyboard, screencast capture, narration, assemble, optional avatar + music bed, verify, attach to PR body)',
  ],
  'ship-p8': [
    'P8.1 Update PR description (Motivation / high-level change summary / Risk / Screenshots / Ticket - LEAN: no Approach, no acceptance-criteria table, no How to Test/How to Verify, no Files changed, no verification log, no file lists)',
    'P8.2 Verify screenshots are in the PR body (ONE-DESCRIPTION rule)',
    'P8.3 Mark the PR READY for review (gh pr ready) + verify isDraft=false + record PR_READY_FOR_REVIEW=1 — NOT optional, a draft handoff is a failed stage',
    'P8.3b Request reviewers — REVIEWERS already script-resolved in the run env',
    'P8.4 Open PR + ticket in browser for review',
    'P8.5 Ticket → review-pending status (per org statusFlowNote) + PR link confirmed',
  ],
  'wrap-up': [
    'P9.1 Show summary in context',
    'P9.2 Present the verification guide (ticket-specific)',
    'P9.3 Verify PR state (CI green, READY FOR REVIEW — isDraft=false — and no unresolved threads)',
    'P9.4 Rename tab',
    'Record DECISION_CLOSE_OR_ITERATE="close" — build mode always closes (no ask)',
    'Loose ends: print the list and record FOLLOWUP_DECISION="none" — no follow-up tickets',
  ],
  hydrate: [
    '1. Resolve the PR from ARGUMENTS (PR_STATE gate: MERGED→stop, CLOSED→stop)',
    '2. Core vars via gh pr view',
    '3. Worktree — recreate if missing',
    '4. Source the LAST handoff block of $WORKTREE/.workflow-handoff.env (verify against gh)',
    '5. Record everything to the run env',
  ],
  'review-state': [
    '1. Fetch review state once (checks / decision / mergeable / threads)',
    '2. Classify: fix-round | approval-gate | await-re-review | nothing (all-findings-addressed rule → LOOP_DECISION=close; approval-gate only on a fresh approval of the current head, automatic)',
    '3. Decide every finding yourself (automatic); SECURITY GATE on external comments remains the one human ask',
    '4. Write decisions → /tmp/workflow-fixlist.md',
    '5. Capture MERGE_DECISION — human ask ONLY on a fresh approval with no fix round (stale-review override retired); LOOP_DECISION is automatic; a fix round already run → RECOMMENDED_ACTION=await-re-review, park',
    '6. Reply/resolve threads (solved/fixed → resolve; unknown/not implemented → leave open)',
  ],
  'build-fix': [
    '1. Read the confirmed fix list (FIX_LIST_FILE) — apply EXACTLY those',
    '2. P4 — implement fixes (DB-first where relevant)',
    '3. P5 — verify + push',
    '4. Record UI_CHANGED (script re-runs the tour if 1)',
    '5. Ensure the PR is READY for review after the push (gh pr ready if draft) + verify isDraft=false + record PR_READY_FOR_REVIEW=1',
    '6. Loose ends as you go',
  ],
  'ship-p10': [
    'P10.1 Final CI check',
    'P10.1b Draft check — if still draft run gh pr ready, verify isDraft=false, and STOP only if it is STILL draft after that',
    'P10.2 Verify a FRESH peer approval of the current head — never merge on a stale review (a post-fix run parks instead)',
    'P10.3 Merge or merge-queue + poll until MERGED (never cleanup before confirmed)',
    'P10.5 Ticket → done + PR link final check',
    '(P10.4 worktree cleanup is DEFERRED to the post stage — screenshots needed)',
  ],
  post: [
    'P11.1 Monitor deployment (per HAS_* flags)',
    'P11.2 Rollback decision — report, never auto-revert',
    'P11.3 Notify chat + ticket record (Notion: append a Completion section — no comment scope)',
    'P11.4 Stop dev-server/DB bg tasks',
    'P11.5 Verify task list clean (delete all run tasks)',
    'P11.6 Final report',
    'P12.1 Locate session JSONLs (RUN_SESSION_DIR in the run env)',
    'P12.2 Friction scan over ALL run sessions (tag by stage)',
    'P12.3 Record friction for the periodic bulk scan — no ask, do NOT edit skills',
    'P13.1 Gather email data (TOKEN_*/TIME_TAKEN already in the run env)',
    'P13.2 Send email → THEN final worktree cleanup (screenshots survive until sent)',
  ],
  'review-gather': [
    '1. Resolve PR from ARGUMENTS + fetch full details (state, reviewDecision, mergeable, checks)',
    '2. Resolve the linked ticket + RECONCILE ticket status vs PR state — mismatch → align the ticket to the PR state + record',
    '3. Scan PR comments/threads — has the author self-resolved open questions? Note genuinely-open threads',
    '4. Check CI status (required checks vs holds) + merge-conflict state vs main',
    '5. Conventions pre-check on the PR body: ticket name + link, risk meter, tour photos',
    '6. Fetch the full diff, group into reviewable AREAS, scope-check vs ticket criteria',
    '7. Write findings file (per-run path) + set SCREENSHOTS_DIR + worktree for the audit',
  ],
  'review-audit': [
    '1. Check out the PR branch in the worktree — NEVER push, NEVER modify code',
    '2. Run the full local test suite + typecheck + lint + coverage (all green + good coverage)',
    '3. Security pass per area: auth/authz, injection, RLS/tenant scoping, secrets, data exposure',
    '4. Correctness vs ticket criteria + gaps/loopholes: edge cases, validation, races',
    '5. AI-slop sweep: generated phrasing, useless comments, defensive dead code, hallucinated APIs, scope creep',
    '6. DRY/quality sweep: duplication, missed reuse, naming, house style (repo AGENTS.md)',
    '7. Append one audit entry per finding (severity) to the findings file',
  ],
  'review-walkthrough': [
    '1. Decide EVERY finding yourself: hunk, the audit read, severity → LGTM / line-comment / blocker',
    '2. Record every decision in the findings file (no per-finding ask)',
    '3. Convention gaps: auto-post clear violations, slide the rest',
    '4. Ask the review-tour question → if yes run the review tour in-pane (read-only, no artifacts); record REVIEW_TOUR_NEEDED (yes|no)',
    '5. Decisions appended to the findings file; DECIDED_COUNT recorded',
  ],
  'review-verdict': [
    '1. Draft the complete GH review atomically: inline comments per decided finding + verdict (Approve if 0 blockers else Request changes / Comment if nits only)',
    '2. Show the full draft in-pane — PARK, post ONLY on explicit user confirmation',
    '3. Post inline comments, submit the review (APPROVE|REQUEST_CHANGES|COMMENT)',
    '4. Update EVERY ticket referenced by the PR (multi-ticket lesson) using the org statusFlowNote in org-config: approved → approved status, changes → denied status; review link on each',
    '5. NEVER touch the PR draft state (no mode, no stage runs gh pr ready): leave the PR exactly as it is — the HUMAN marks it ready, that is the author-acceptance gate',
    '6. Final summary to the chief-of-staff session — run complete (no merge, no push)',
  ],
}
function writeTaskFile(stage: StageName, extra: string): string {
  const taskFile = `/tmp/workflow-task-${stage}${RUN_TAG ? `-${RUN_TAG}` : ''}.md`
  const lines = [
    `# workflow-do stage task: ${stage}`,
    '',
    'Run this stage end-to-end, then surrender control (your prompt file defines the exact final actions).',
    `Run state (all handoff vars): ${RUN_ENV} — read/source it; NEVER overwrite it, append only.`,
    `chief of staff session (intercom target — the session that launched this cage): ${ORCH_SESSION}`,
    '',
    'Phase order (script-owned — follow in sequence, every step):',
    ...PHASE_ORDER[stage].map(s => `  ${s}`),
    '',
    'BROWSER — ONE CHROME PER RUN (hard rule, user directive 2026-10-07). The run Chrome is launched ONCE',
    'by the SCRIPT on a FIXED debug port with wayland ozone, and that port is recorded in the run env',
    '(CHROME_CDP_PORT). Do not launch Chrome yourself and never pass --remote-debugging-port=0:',
    '  setsid nohup env WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR=/run/user/1000 google-chrome --ozone-platform=wayland --remote-debugging-port="$CHROME_CDP_PORT" --user-data-dir="$CHROME_SESSION_PROFILE" --no-sandbox --disable-dev-shm-usage --window-position=0,0 --window-size="${CHROME_WINDOW_SIZE:-1920,1080}" about:blank',
    'EVERY agent-browser call must carry --cdp http://127.0.0.1:$CHROME_CDP_PORT IN ADDITION to the bindings,',
    'with all values read from the run env (never derived — check CHROME_CDP_PORT there):',
    '  XDG_DATA_HOME="$CHROME_XDG_DATA_HOME" agent-browser --headed --session "$CHROME_SESSION" --pin-tab --profile "$CHROME_SESSION_PROFILE" --cdp "http://127.0.0.1:$CHROME_CDP_PORT" <subcommand>',
    'A call missing --cdp makes the CLI launch its OWN Chrome on an EPHEMERAL port (silent exit, wedged',
    'daemon, no recorded port); a call missing --profile/--headed/--session starts a throwaway temp-profile',
    'window. If the browser is dead, do NOT improvise a launch — the script revives it once before every',
    'browser-using stage, and you can do the same safely with:',
    '  bash ~/.agents/skills/workflow-do/scripts/chrome.sh status   # alive? on which CDP port? which profile?',
    '  bash ~/.agents/skills/workflow-do/scripts/chrome.sh revive   # idempotent single relaunch on the SAME profile',
    'Never call `agent-browser set viewport` (it wedges the daemon). Keep exactly 1 daemon + 1 main chrome + 0 phantoms.',
    '',
  ]
  if (extra) lines.push(extra)
  writeFileSync(taskFile, lines.join(EOL))
  return taskFile
}

// ── pane launch ─────────────────────────────────────────────────────────────
// One-line, quote-free launch prompt — all state lives in files (SHARED-POLICY rule).
function launchPromptCmdline(stage: StageName, paneName: string, promptFile: string, taskFile: string): string {
  const model = process.env.WORKFLOW_PI_MODEL
  const modelFlag = model ? ` --model '${model}'` : ''
  return `pi --name ${paneName}${modelFlag} 'Read ${SHARED_POLICY}, then ${promptFile}, then ${taskFile} — follow them in order'`
}
function buildPaneCmd(stage: StageName, paneName: string, promptFile: string, taskFile: string): string[] {
  // TS array literals replace the bash array — quoting is explicit and reviewable.
  let paneCmd = ['bash', '-ic', `${launchPromptCmdline(stage, paneName, promptFile, taskFile)}; exit`]
  const containerId = process.env.WORKFLOW_CONTAINER_ID
  if (containerId) {
    // Zellij runs on the HOST (cage talks to it via the mounted socket), so pane
    // commands would run host-side where the run state files are invisible. Wrap
    // the command in docker exec to run the stage pi process inside the cage.
    paneCmd = [
      'docker', 'exec', '-it', '-u', 'pc', '-w', process.env.WORKFLOW_CWD ?? '',
      '-e', `WORKFLOW_CWD=${process.env.WORKFLOW_CWD ?? ''}`,
      '-e', `WORKFLOW_CONTAINER_ID=${containerId}`,
      '-e', `WORKFLOW_TAB_ID=${process.env.WORKFLOW_TAB_ID ?? ''}`,
      '-e', `WORKFLOW_ORCH_SESSION=${ORCH_SESSION}`,
      '-e', `WORKFLOW_PI_MODEL=${process.env.WORKFLOW_PI_MODEL ?? ''}`,
      '-e', 'ZELLIJ=1',
      '-e', `ZELLIJ_SESSION_NAME=${process.env.ZELLIJ_SESSION_NAME ?? 'pi'}`,
      // No value: docker reads it from the new host pane's env (its own pane id),
      // which zj-radar's pi bridge needs to attribute status to the right pane.
      '-e', 'ZELLIJ_PANE_ID',
      containerId, ...paneCmd,
    ]
  }
  return paneCmd
}
// ── pane launch (IDEMPOTENT — never start a second pane for the same stage) ──
// 2026-10-19 (<KEY-210>): the old launcher re-ran `zellij run` with the SAME flags
// after a single 1s list-panes check, so a pane that simply took longer than a
// second to appear produced TWO tour panes (launch 13:50:00, retry 13:50:02) —
// two tour agents driving one browser. Launching is now guarded at four levels:
//   1. no second launch for the same stage in this process;
//   2. adopt the pane id persisted in /tmp/workflow-panes-<stage> while it is alive;
//   3. adopt an existing pane by EXACT title or a live `pi --name <pane>` process;
//   4. after a launch, poll list-panes with short backoff (plus the process check)
//      before declaring the pane missing, and re-check BOTH signals right before the
//      one permitted retry. A verified second miss fails loudly — never a third pane.
function paneStatePath(stage: StageName): string {
  return `/tmp/workflow-panes-${stage}${RUN_TAG ? `-${RUN_TAG}` : ''}`
}
const launchedPaneNames = new Set<string>()
// zellij titles look like `π - workflow-tour-<KEY-210> - repo`; match the pane name
// as a WHOLE token so one stage can never be mistaken for another (or for a title
// that merely contains the string).
function paneTitleMatches(title: string, paneName: string): boolean {
  const t = (title ?? '').trim()
  if (!t) return false
  if (t === paneName) return true
  return t.split(/\s+-\s+/).includes(paneName) || t.split(/\s+/).includes(paneName)
}
async function listPanes(): Promise<any[]> {
  const { stdout } = await zj(['action', 'list-panes', '-j'])
  const data = JSON.parse(stdout) as unknown
  return Array.isArray(data) ? (data as any[]) : ((data as any)?.panes ?? [])
}
// Pane ids whose title matches paneName exactly. Throws when list-panes itself
// fails, so callers decide whether that is fatal (launch) or retryable (close).
async function paneIdsByName(paneName: string): Promise<string[]> {
  const panes = await listPanes()
  return panes.filter((p: any) => !p.is_plugin && paneTitleMatches(p.title ?? '', paneName)).map((p: any) => String(p.id))
}
// Is a `pi --name <paneName>` process alive INSIDE this cage? The stage pane runs
// inside the cage (the host zellij pane docker-execs back in), so a local pgrep sees
// it even while zellij has not updated the pane title yet. `[p]i` keeps the pattern
// from matching the bash -c wrapper that carries it (a self-match killed a pane once).
async function stageProcessAlive(paneName: string): Promise<boolean> {
  try {
    const { stdout } = await sh(`pgrep -u pc -af "[p]i --name ${paneName}( |$)" || true`)
    return Boolean(
      stdout
        .split(EOL)
        .map(l => l.trim())
        .find(l => {
          if (!l) return false
          const pid = Number(l.split(/\s+/, 1)[0])
          // never count this script (or the shell that ran pgrep) as the stage process
          return pid > 0 && pid !== process.pid && pid !== process.ppid
        }),
    )
  } catch {
    return false
  }
}
interface PaneLookup {
  id?: string
  title?: string
  via: 'id' | 'title' | 'process'
}
// Existing pane for this stage, by recorded id → exact title → live pi process.
// A live process with no matching title still counts: the pane exists, its title
// just has not refreshed, and launching another would be the duplicate-pane bug.
async function findStagePane(paneName: string, recordedId = ''): Promise<PaneLookup | null> {
  let panes: any[] = []
  try {
    panes = await listPanes()
  } catch (e: any) {
    log(`⚠️ list-panes failed while looking for ${paneName}: ${e?.message ?? e}`)
  }
  if (recordedId) {
    const byId = panes.find((p: any) => String(p.id) === recordedId && paneTitleMatches(p.title ?? '', paneName))
    if (byId) return { id: String(byId.id), title: byId.title, via: 'id' }
  }
  const byTitle = panes.find((p: any) => !p.is_plugin && paneTitleMatches(p.title ?? '', paneName))
  if (byTitle) return { id: String(byTitle.id), title: byTitle.title, via: 'title' }
  if (await stageProcessAlive(paneName)) return { via: 'process' }
  return null
}
function persistPane(stage: StageName, paneName: string, id: string, how: string): void {
  try {
    appendState(paneStatePath(stage), {
      PANE_ID: id,
      PANE_NAME: paneName,
      PANE_LAUNCHED_EPOCH: String(Math.floor(Date.now() / 1000)),
      PANE_LAUNCH_METHOD: how,
    })
  } catch (e: any) {
    log(`⚠️ could not persist pane state to ${paneStatePath(stage)}: ${e?.message ?? e}`)
  }
}
// Short backoff: zellij creates a pane asynchronously, so a single 1s check is a
// coin flip. ~12s of polling, cheapest first, is enough for a real pane to appear
// (and still fails fast when zellij truly no-ops the launch).
const PANE_POLL_DELAYS_MS = [300, 500, 800, 1200, 1600, 2000, 2500, 3000]
// A pane that exists but whose `pi --name …` process is gone is a CORPSE left by a
// crashed earlier run: adopting it would wait forever. Close it, then launch fresh.
async function closeDeadStagePane(paneName: string, lookup: PaneLookup): Promise<void> {
  if (lookup.via === 'process') return
  log(`🗑️ ${paneName}: pane ${lookup.id ?? '?'} exists but no live 'pi --name ${paneName}' process — closing the dead pane before launching a fresh one`)
  try {
    const ids = lookup.id ? [lookup.id] : await paneIdsByName(paneName)
    for (const id of ids) await zj(['action', 'close-pane', '--pane-id', id])
  } catch (e: any) {
    log(`⚠️ could not close the dead pane for ${paneName}: ${e?.message ?? e}`)
  }
}
async function pollForStagePane(paneName: string, recordedId: string, where: string): Promise<PaneLookup | null> {
  let waited = 0
  for (const delay of PANE_POLL_DELAYS_MS) {
    await sleep(delay)
    waited += delay
    const found = await findStagePane(paneName, recordedId)
    if (found) {
      log(`${where}: pane ${paneName} present after ~${waited}ms (via ${found.via}${found.id ? `, id ${found.id}` : ''})`)
      return found
    }
  }
  log(`${where}: pane ${paneName} still absent after ~${waited}ms of polling`)
  return null
}
async function launchStagePane(stage: StageName, taskFile: string): Promise<void> {
  const paneName = `workflow-${stage}-${TICKET_LABEL}`
  const promptFile = stagePrompt(stage)
  const dirflag = ['--direction', 'right']
  const paneCmd = buildPaneCmd(stage, paneName, promptFile, taskFile)
  if (dryRun) {
    console.log(
      `  DRY-RUN: zellij run --tab-id ${process.env.WORKFLOW_TAB_ID ?? 'TAB'} ${dirflag.join(' ')} --name ${paneName} --cwd ${process.env.WORKFLOW_CWD ?? '.'} -- ${paneCmd.join(' ')}`,
    )
    return
  }
  if (launchedPaneNames.has(paneName)) {
    log(`⏭️ pane ${paneName} was already launched by this run process — NOT starting a second one`)
    return
  }
  const statePath = paneStatePath(stage)
  const recordedId = readState(statePath).PANE_ID ?? ''
  if (recordedId) {
    const adopted = await findStagePane(paneName, recordedId)
    if (adopted && (adopted.via === 'process' || (await stageProcessAlive(paneName)))) {
      log(`♻️ ${stage}: adopting recorded pane ${paneName} (id ${adopted.id ?? recordedId}, via ${adopted.via}) — no launch`)
      launchedPaneNames.add(paneName)
      if (adopted.id) persistPane(stage, paneName, adopted.id, 'adopted-recorded')
      return
    }
    if (adopted) await closeDeadStagePane(paneName, adopted)
    else log(`⚠️ ${stage}: recorded pane id ${recordedId} for ${paneName} is gone — re-checking exact title and live pi process before any launch`)
  }
  const existing = await findStagePane(paneName)
  if (existing && (existing.via === 'process' || (await stageProcessAlive(paneName)))) {
    log(`♻️ ${stage}: pane ${paneName} already exists and is live (via ${existing.via}${existing.id ? `, id ${existing.id}` : ''}) — NOT launching a second one`)
    launchedPaneNames.add(paneName)
    if (existing.id) persistPane(stage, paneName, existing.id, `existing-${existing.via}`)
    return
  }
  if (existing) await closeDeadStagePane(paneName, existing)
  const runArgs = (flag: string[]): string[] => [
    'run', '--tab-id', process.env.WORKFLOW_TAB_ID ?? '', ...flag,
    '--name', paneName, '--cwd', process.env.WORKFLOW_CWD ?? '', '--', ...paneCmd,
  ]
  const attemptLaunch = async (flags: string[], label: string): Promise<boolean> => {
    log(`▶️ ${stage}: launching pane ${paneName} (${label})`)
    try {
      await zj(runArgs(flags))
    } catch (e: any) {
      log(`zellij run failed (${label}) — ${e?.message ?? e}`)
    }
    const found = await pollForStagePane(paneName, '', label)
    if (!found) return false
    launchedPaneNames.add(paneName)
    if (found.id) persistPane(stage, paneName, found.id, label)
    return true
  }
  if (await attemptLaunch(dirflag, '--direction right')) return
  // Re-check BOTH signals before the single retry: the pane may have appeared just
  // after the last poll. Only a verified miss may retry, so a slow pane can never
  // turn into a duplicate.
  log(`⚠️ ${stage}: pane ${paneName} missing after launch+poll — re-checking title AND pi process before the single retry`)
  const recheck = await findStagePane(paneName)
  if (recheck) {
    log(`♻️ ${stage}: pane ${paneName} appeared on re-check (via ${recheck.via}${recheck.id ? `, id ${recheck.id}` : ''}) — NOT retrying`)
    launchedPaneNames.add(paneName)
    if (recheck.id) persistPane(stage, paneName, recheck.id, `recheck-${recheck.via}`)
    return
  }
  if (await attemptLaunch(dirflag, 'single retry after a verified miss')) return
  log(`⚠️⚠️ ${stage}: pane ${paneName} missing after one launch + one verified retry — NOT launching a third pane`)
  const finalCheck = await findStagePane(paneName)
  if (finalCheck) {
    log(`♻️ ${stage}: pane ${paneName} appeared on the final re-check (via ${finalCheck.via}) — continuing`)
    launchedPaneNames.add(paneName)
    if (finalCheck.id) persistPane(stage, paneName, finalCheck.id, `final-recheck-${finalCheck.via}`)
    return
  }
  await fail(
    `cannot launch pane ${paneName} (one launch + one verified retry; no duplicate pane started). Check \`zellij --session ${process.env.ZELLIJ_SESSION_NAME ?? '?'} action list-panes\`; if zellij --direction is wedged, restart the zellij session, then relaunch with --resume`,
  )
}

// ── stage-pane cleanup (script-owned) ──────────────────────────────────────
// zellij does NOT auto-close panes when their command exits — a stage agent that
// runs exit/kill leaves a dead pane behind. So the stage contract is: the agent
// surrenders (run env + intercom) and STOPS; the script closes the pane itself.
// Matches pane TITLE (exact pane name token) across the session — also cleans up
// same-named panes lingering from earlier rounds of this ticket — then drops the
// persisted pane id so a legitimate re-run of that stage may launch a fresh pane.
async function closeStagePane(stage: StageName): Promise<void> {
  const paneName = `workflow-${stage}-${TICKET_LABEL}`
  if (dryRun) {
    console.log(`  DRY-RUN: close pane ${paneName} via zellij action close-pane`)
    return
  }
  let ids: string[] = []
  try {
    ids = await paneIdsByName(paneName)
  } catch (e: any) {
    // Do NOT swallow this silently — the pane will linger and the human only
    // finds out by looking. Log the cause, then retry once.
    log(`⚠️ list-panes failed while closing ${paneName}: ${e?.message ?? e}`)
    try {
      await sleep(2000)
      ids = await paneIdsByName(paneName)
    } catch (e2: any) {
      log(`⚠️ list-panes retry failed — pane ${paneName} left open; close it manually`)
      return
    }
  }
  if (ids.length === 0) {
    log(`⚠️ pane ${paneName} not found for closing — it may have already exited`)
    return
  }
  for (const id of ids) {
    try {
      await zj(['action', 'close-pane', '--pane-id', id])
      log(`🧹 closed pane ${paneName} (id ${id})`)
    } catch {
      log(`⚠️ could not close pane ${paneName} (id ${id})`)
    }
  }
  try {
    rmSync(paneStatePath(stage), { force: true })
  } catch {
    /* best-effort */
  }
  launchedPaneNames.delete(paneName)
}

// ── surrender-point wait + verification ─────────────────────────────────────
function lastVar(name: string): string {
  const lines = existsSync(RUN_ENV)
    ? readFileSync(RUN_ENV, 'utf8').split(EOL).filter(l => l.startsWith(`${name}=`))
    : []
  const last = lines[lines.length - 1]
  return last ? (new RegExp(`^${name}="([^"]*)"$`).exec(last)?.[1] ?? '') : ''
}
async function waitStageDone(stage: StageName): Promise<void> {
  if (dryRun) {
    console.log(
      `  DRY-RUN: poll ${RUN_ENV} for STAGE_DONE="${stage}" + STAGE_STATUS=ok, then verify: ${STAGE_SPECS[stage].requires.join(' ')}`,
    )
    return
  }
  let waited = 0
  const timeout = STAGE_TIMEOUT
  log(`⏳ waiting for ${stage} to surrender (STAGE_DONE in ${RUN_ENV}, poll ${POLL_SECS}s)...`)
  for (;;) {
    const lastDone = lastVar('STAGE_DONE')
    const lastStatus = lastVar('STAGE_STATUS')
    if (lastDone === stage) {
      if ((lastStatus || 'ok') !== 'ok') {
        await fail(
          `stage ${stage} surrendered with STAGE_STATUS=${lastStatus} — inspect /tmp/workflow-task-${stage}.md pane output, fix state, relaunch with --stage ${stage}`,
        )
      }
      break
    }
    if (timeout > 0 && waited >= timeout) {
      await fail(`stage ${stage} timed out after ${timeout}s without surrendering`)
    }
    // No-timeout stalls: a stage that reported success but never appended its
    // STAGE_DONE block (silent write failure) would otherwise hang the run forever.
    // Warn loudly + notify the supervisor once, then keep waiting.
    if (timeout === 0 && waited > 0 && waited % 1800 === 0) {
      log(`⚠️ stage ${stage} has been silent for ${Math.round(waited / 60)} min — no STAGE_DONE block yet. Check the stage pane: it may have reported success without appending (re-read ${RUN_ENV}; the supervisor can append the block by hand), or it may simply still be working.`)
      await notify(`⚠️ workflow-do: stage ${stage} silent for ${Math.round(waited / 60)} min without surrendering (run log ${RUN_LOG}). If the stage claims it appended STAGE_DONE, re-read ${RUN_ENV} and append the block by hand.`)
    }
    await sleep(POLL_SECS * 1000)
    waited += POLL_SECS
  }
  await verifyStageOut(stage)
}
async function verifyStageOut(stage: StageName): Promise<void> {
  // Ready-for-review gate FIRST: a stage that forgot the undraft (or claimed one
  // that never happened) gets its PR state corrected here and, if the undraft
  // cannot be completed + verified, the RUN fails loudly instead of parking a
  // "complete" handoff with a draft PR. Both stages own the transition; this is
  // the script's independent check of the real GitHub state.
  if (stage === 'ship-p8' || stage === 'build-fix') await ensurePrReadyForReview(stage)
  const state = readState(RUN_ENV)
  const missing = STAGE_SPECS[stage].requires.filter(v => !state[v])
  if (missing.length > 0) {
    await fail(
      `stage ${stage} surrendered but required vars empty: ${missing.join(' ')} — append them to ${RUN_ENV}, then resume`,
    )
  }
  log(`✅ ${stage} verified — ${STAGE_SPECS[stage].requires.length} required vars present`)
}

// ── P9.4 durable handoff (existing .workflow-handoff.env convention) ────────
async function writeIterateHandoffBlock(): Promise<void> {
  const worktree = runVar('WORKTREE')
  if (dryRun) {
    console.log(`  DRY-RUN: append P9.4 handoff block to ${worktree || '$WORKTREE'}/.workflow-handoff.env`)
    return
  }
  if (!worktree || !existsSync(worktree)) {
    await fail('WORKTREE not set/missing — cannot write iterate handoff')
  }
  const handoff = `${worktree}/.workflow-handoff.env`
  if (!existsSync(handoff)) {
    appendFileSync(handoff, '# workflow-do handoff blocks (append-only, newest last)' + EOL)
  }
  const s = readState(RUN_ENV)
  const keys = ['TICKET_ID', 'TICKET_URL', 'FEATURE_TAG', 'ORG', 'REPO_NAME', 'PR_NUMBER', 'PR_URL', 'BRANCH_NAME', 'WORKTREE', 'SOURCE_REPO', 'INTEGRATION_BRANCH'] as const
  const block = [
    `# handoff appended after P8 — ${new Date().toISOString().replace(/\.\d+Z$/, 'Z')}`,
    ...keys.map(k => `${k}="${s[k] ?? ''}"`),
  ]
  appendFileSync(handoff, block.join(EOL) + EOL)
  log(`✅ P9.4 iterate handoff appended to ${worktree}/.workflow-handoff.env`)
}

// ── ticket label ────────────────────────────────────────────────────────────
function deriveTicketLabel(): string {
  const state = existsSync(RUN_ENV) ? readState(RUN_ENV) : {}
  let t = state.TICKET_ID ?? ''
  if (!t) t = /[A-Za-z]+-[0-9]+/.exec(modeArg)?.[0] ?? ''
  if (!t) t = RUN_TAG ? RUN_TAG : `run-${String(Math.floor(Date.now() / 1000)).slice(-5)}`
  return t
}

// ── stage runner ────────────────────────────────────────────────────────────
function stageExtra(stage: StageName): string {
  switch (stage) {
    case 'scout':
      return [
        `ARGUMENTS (verbatim, quote-free): ${modeArg}`,
        '',
        `Write the context pack to ${RUN_TAG ? `/tmp/workflow-scout-${RUN_TAG}.md` : '/tmp/workflow-scout.md'} and record SCOUT_FILE="${RUN_TAG ? `/tmp/workflow-scout-${RUN_TAG}.md` : '/tmp/workflow-scout.md'}" in ${RUN_ENV} (append only) along with STAGE_DONE block.`,
      ].join(EOL)
    case 'prebuild':
      return [
        `ARGUMENTS (verbatim, quote-free): ${modeArg}`,
        '',
        'Script-detected (AUTHORITATIVE — read from the run env, do NOT re-derive): ORG, REPO_ROOT, REPO_NAME, GITHUB_ORG, INTEGRATION_BRANCH, PKG_MGR, HAS_FRONTEND/FRONTEND_DIR/BACKEND_DIR/IS_MONOREPO, HAS_VERCEL/HAS_GH_ACTIONS/HAS_CIRCLECI/HAS_JENKINS/HAS_SUPABASE/HAS_DATADOG, PROJECT_PROFILE_FILE (package.json scripts dump). P1.1/P1.4/P1.5/P1.7 are DONE by the script. If a detected value disagrees with reality or is missing, derive it once, append the value, and record a loose end — never silently re-derive in later steps.',
        '',
        `Write your OUT vars + STAGE_DONE block to ${RUN_ENV} (append only). Write the 5-element brief + acceptance criteria to ${RUN_TAG ? `/tmp/workflow-brief-${RUN_TAG}.md` : '/tmp/workflow-brief.md'} and record BRIEF_FILE="${RUN_TAG ? `/tmp/workflow-brief-${RUN_TAG}.md` : '/tmp/workflow-brief.md'}" in ${RUN_ENV}.`,
      ].join(EOL)
    case 'build':
      return `Implementation contract: the brief at the BRIEF_FILE path in ${RUN_ENV} + its acceptance criteria. Read ${RUN_ENV} for all handoff vars.`
    case 'build-fix':
      return [
        `Implementation contract: the brief at the BRIEF_FILE path in ${RUN_ENV} + its acceptance criteria. Read ${RUN_ENV} for all handoff vars.`,
        `After the fixes are pushed, mark the PR READY for review (\`gh pr ready "$PR_NUMBER" --repo "$GH_REPO"\` — a fix round must never hand back a draft), verify \`isDraft\` is false, and record PR_READY_FOR_REVIEW="1" in ${RUN_ENV}. A failed undraft is FATAL: report it to the chief of staff and do NOT write STAGE_STATUS="ok".`,
      ].join(EOL)
    case 'ship-p8':
      return [
        'P8.3 is a GATE, not a note: run `gh pr ready` on the PR, then re-read `gh pr view … --json isDraft` and confirm false before you surrender.',
        `Record PR_READY_FOR_REVIEW="1" in ${RUN_ENV} and print the verified isDraft value in your handoff. If the undraft or the verify fails, do NOT write STAGE_DONE/STAGE_STATUS="ok" — name the failure to the chief of staff and stop; the script independently re-reads isDraft and fails the stage if the PR is a draft.`,
      ].join(EOL)
    case 'ship-p10':
      return `P10.1b: the PR must be ready for review before merging. Re-read \`gh pr view "$PR_NUMBER" --repo "$GH_REPO" --json isDraft --jq .isDraft\`; if true, run \`gh pr ready\`, re-verify false, and record PR_READY_FOR_REVIEW="1" in ${RUN_ENV}. Never merge while isDraft is true.`
    case 'tour':
      return `Tour checklist: the acceptance criteria listed in the brief (BRIEF_FILE path in ${RUN_ENV}).`
    case 'wrap-up':
      return [
        `Loose ends (always, no ask): read /tmp/workflow-loose-ends.md (LOOSE_ENDS_FILE in ${RUN_ENV} if recorded). Print the numbered list in-pane and record FOLLOWUP_DECISION="none" and FOLLOWUP_TICKETS="" in ${RUN_ENV}. Do NOT create follow-up tickets — runs never create tracker tickets, and the ticket this run worked on already existed. Also record DECISION_CLOSE_OR_ITERATE="close" (build mode always closes; there is no close-or-iterate ask).`,
      ].join(EOL)
    case 'review-state':
      return [
        `Decisions go to /tmp/workflow-fixlist.md (record FIX_LIST_FILE="/tmp/workflow-fixlist.md" in ${RUN_ENV}). Every finding is decided automatically — no per-finding ask.`,
        `Record RECOMMENDED_ACTION (fix-round|approval-gate|await-re-review|nothing) and LOOP_DECISION (another-round|close — close when all findings are addressed, automatic) and MERGE_DECISION (merge|wait|fix|revert — the human ask, ONLY on a fresh approval of the current head with no fix round in this run; empty on await-re-review) in ${RUN_ENV}.`,
      ].join(EOL)
    case 'hydrate':
      // Fresh-run iterate entry: without the verbatim PR ref here, the hydrate
      // agent cannot resolve the PR and falls back to the newest worktree
      // handoff — which can belong to an unrelated ticket in the same cage.
      return `ARGUMENTS (verbatim, quote-free): ${modeArg}\n\nResolve the PR from these ARGUMENTS first, then verify any handoff block against that PR — never the other way around.`
    case 'review-gather':
      return [
        `ARGUMENTS (verbatim, quote-free): ${modeArg}`,
        '',
        `Deep knowledge: read ~/.agents/skills/workflow-do-review/SKILL.md (the review procedure) before starting. Findings file: a per-run path (e.g. /tmp/workflow-review-findings-<label>.md) — record FINDINGS_FILE and REVIEW_AREAS="<count>" in ${RUN_ENV}.`,
      ].join(EOL)
    case 'review-audit':
      return `Audit contract: the review procedure in ~/.agents/skills/workflow-do-review/SKILL.md + the areas in the FINDINGS_FILE path in ${RUN_ENV}. NEVER push, NEVER modify code, NEVER merge — review only. Run the full local verification suite in the WORKTREE.`
    case 'review-walkthrough':
      return `Walkthrough contract: decide every finding from the FINDINGS_FILE path in ${RUN_ENV} yourself (no per-finding ask) per the review procedure in ~/.agents/skills/workflow-do-review/SKILL.md; convention gaps: auto-post clear violations, slide the rest. Ask only the review-tour question; record REVIEW_TOUR_NEEDED (yes|no) + REVIEW_TOUR_DONE + DECIDED_COUNT in ${RUN_ENV}.`
    case 'review-verdict':
      return `Verdict contract: decisions from FINDINGS_FILE in ${RUN_ENV}. Post NOTHING without explicit user confirmation in this pane. Record REVIEW_SUBMITTED="1", REVIEW_VERDICT, REVIEW_URL in ${RUN_ENV}.`
    default:
      return ''
  }
}
// ── script-owned Chrome pane ────────────────────────────────────────────────
// The SCRIPT owns Chrome launch (per-org user-data-dir from the registry via
// cage()'s CHROME_USER_DATA_DIR mount at $HOME/chrome-org). The run drives it
// under an EXPLICIT named session (chrome-<TICKET>) — stage agents target that
// session directly (--session $CHROME_SESSION --pin-tab --cdp ...). NEVER
// auto-connect: attaching must always target this known instance, never whatever
// browser happens to be running.
let chromePaneLaunched = false // process-local idempotency (covers dry-run, which never persists CHROME_LAUNCHED)
let chromeRevives = 0 // automatic relaunches this process (policy: at most ONE)
// ── run Chrome: launched DIRECTLY by the script on a FIXED CDP port ─────────
// User directive 2026-09-30: the run's Chrome is started once, here, from the
// script itself — not in a dedicated pane — and NOTHING else may start another
// Chrome. 2026-10-19 (<KEY-209>/1210/1211/1212): the launch used to go through
// `agent-browser open`, whose launcher hardcodes `--remote-debugging-port=0`
// (an EPHEMERAL port). CHROME_CDP_PORT was therefore never recorded, and after a
// Chrome death every stage improvised its own relaunch — three of four runs lost
// their browser with no port on record. The script now launches Chrome itself on
// a FIXED per-run port (the cage-stable recipe in SHARED-POLICY), persists
// CHROME_CDP_PORT + CHROME_LAUNCHED to the run env, proves liveness over CDP, and
// stages ATTACH with the full triple PLUS `--cdp http://127.0.0.1:$CHROME_CDP_PORT`
// (a call without `--profile`/`--headed`/`--cdp` launches a second, logged-out
// Chrome — the phantom that plagued the 2026-09-29/30 runs).
const CHROME_PORT_BASE = Number(process.env.WORKFLOW_CHROME_PORT_BASE ?? '9301')
const CHROME_PORT_SPAN = 90
// The video tour films a 1600x900 frame (`workflow-video-tour` → `--viewport 1600x900`),
// so the run Chrome's window must be at least that big. `--window-size` alone is NOT
// sufficient: on 2026-10-19 a live run's Chrome came up 948x947 (niri tiles the window;
// the compositor sizes it, not the flag) and the tour captured a 948x947 screencast that
// was unusable for the cut. So the size is explicit here, overridable, refused below the
// minimum, recorded in the run env, and MEASURED afterwards by `chrome.sh viewport`.
const CHROME_MIN_WINDOW_W = 1600
const CHROME_MIN_WINDOW_H = 900
/** "W,H" for --window-size, or '' when the configured value is below the video minimum. */
function chromeWindowSize(): string {
  const raw = String(process.env.CHROME_WINDOW_SIZE ?? runVar('CHROME_WINDOW_SIZE') ?? '1920,1080').trim()
  const m = /^(\d+)\s*[x,]\s*(\d+)$/i.exec(raw)
  const w = Number(m?.[1] ?? 0)
  const h = Number(m?.[2] ?? 0)
  if (w < CHROME_MIN_WINDOW_W || h < CHROME_MIN_WINDOW_H) return ''
  return `${w},${h}`
}
// Stages whose work drives the browser. The probe runs BEFORE these panes; a dead
// Chrome gets ONE automatic relaunch on the same profile (which records the port).
const BROWSER_STAGES = new Set<StageName>([
  'prebuild', 'build', 'tour', 'build-fix', 'wrap-up', 'review-gather', 'review-walkthrough', 'review-verdict',
])
function chromeSession(): string {
  return runVar('CHROME_SESSION') || `chrome-${TICKET_LABEL}`
}
function chromeProfile(): string {
  return runVar('CHROME_SESSION_PROFILE') || `/tmp/chrome-profile-${TICKET_LABEL}`
}
function chromeXdg(): string {
  return runVar('CHROME_XDG_DATA_HOME') || `/tmp/xdg-${TICKET_LABEL}`
}
function chromeLog(): string {
  return `/tmp/chrome-${TICKET_LABEL}.log`
}
/** Is anything listening on this TCP port inside the cage? (/dev/tcp is bash-builtin.) */
async function tcpOpen(port: number): Promise<boolean> {
  try {
    await sh(`timeout 1 bash -c '</dev/tcp/127.0.0.1/${port}'`)
    return true
  } catch {
    return false
  }
}
/** A healthy CDP endpoint answers /json/version with a Browser version. */
async function chromeCdpAlive(port: number): Promise<boolean> {
  if (!(port > 0)) return false
  try {
    const { stdout } = await sh(`curl -s --max-time 2 http://127.0.0.1:${port}/json/version`)
    return stdout.includes('"Browser"')
  } catch {
    return false
  }
}
/** Deterministic per-ticket spread across the port span (parallel cages are isolated,
 *  but a fixed base keeps every run's port predictable and stable across resumes). */
function chromePortSeed(): number {
  let h = 0
  for (const ch of TICKET_LABEL) h = (h * 31 + ch.charCodeAt(0)) % 100003
  return h % CHROME_PORT_SPAN
}
async function pickChromePort(): Promise<number> {
  const recorded = Number(runVar('CHROME_CDP_PORT') || '')
  if (recorded > 0) {
    if (await chromeCdpAlive(recorded)) return recorded
    if (!(await tcpOpen(recorded))) return recorded // free → reuse the recorded port
    log(`⚠️ recorded CHROME_CDP_PORT ${recorded} is taken by another process — picking a free port`)
  }
  const seed = chromePortSeed()
  for (let i = 0; i < CHROME_PORT_SPAN; i++) {
    const p = CHROME_PORT_BASE + ((seed + i) % CHROME_PORT_SPAN)
    if (!(await tcpOpen(p))) return p
  }
  return await fail(`no free CDP port in ${CHROME_PORT_BASE}-${CHROME_PORT_BASE + CHROME_PORT_SPAN - 1} for the run Chrome`)
}
/** Discover the live port of an already-running Chrome: its own DevToolsActivePort
 *  file first, then the main process cmdline (the file can be deleted by a revive). */
async function discoverChromePort(): Promise<number> {
  try {
    const raw = readFileSync(`${chromeProfile()}/DevToolsActivePort`, 'utf8').split(EOL)[0]?.trim() ?? ''
    const p = Number(raw)
    if (p > 0) return p
  } catch {
    /* fall through to /proc */
  }
  try {
    const { stdout } = await sh(`pgrep -u pc -f "^/usr/bin/google-chrome.*user-data-dir=${chromeProfile()}" | head -1`)
    const pid = stdout.trim().split(EOL)[0]
    if (pid) {
      const arg = readFileSync(`/proc/${pid}/cmdline`, 'utf8')
        .split('\0')
        .find(a => a.startsWith('--remote-debugging-port='))
      const p = Number(arg?.split('=')[1] ?? '')
      if (p > 0) return p
    }
  } catch {
    /* unknown */
  }
  return 0
}
/** Discover the mirror (pi-frontend) URL of THIS run's pi session.
 *  pi-frontend registers ~/.pi/tau-instances/<pid>.json per running pi process
 *  ({port,pid,sessionFile,cwd}); prefer the script's parent (the supervisor pi),
 *  then any instance whose cwd is this run's repo, then nothing. */
function discoverPiFrontendUrl(): string {
  try {
    const dir = `${process.env.HOME}/.pi/tau-instances`
    if (!existsSync(dir)) return ''
    const want = process.env.WORKFLOW_CWD ?? process.cwd()
    const entries = readdirSync(dir)
      .filter((f) => f.endsWith('.json'))
      .map((f) => { try { return JSON.parse(readFileSync(`${dir}/${f}`, 'utf8')) as { port?: number; pid?: number; cwd?: string } } catch { return {} } })
    const byParent = entries.find((e) => e.pid && e.pid === process.ppid)
    const byCwd = entries.find((e) => e.cwd === want || (e.cwd ?? '').startsWith(want))
    const port = byParent?.port ?? byCwd?.port
    return port ? `http://127.0.0.1:${port}` : ''
  } catch {
    return ''
  }
}
async function launchChromePane(force = false): Promise<void> {
  if (!force && (chromePaneLaunched || runVar('CHROME_LAUNCHED') === '1')) return
  chromePaneLaunched = true
  const chromeDir = process.env.CHROME_USER_DATA_DIR || '$HOME/chrome-org'
  // Per-session profile COPY (parallel cages share one source profile; two Chromes on
  // one user-data-dir fight over SingletonLock). XDG_DATA_HOME must be writable in-cage
  // (~/.local/share is root-owned there).
  const sessionProfile = chromeProfile()
  const chromeSessionName = chromeSession()
  const xdg = chromeXdg()
  const logFile = chromeLog()
  const port = await pickChromePort()
  const windowSize = chromeWindowSize()
  if (!windowSize) {
    await fail(
      `CHROME_WINDOW_SIZE is "${process.env.CHROME_WINDOW_SIZE ?? runVar('CHROME_WINDOW_SIZE') ?? ''}" — the run Chrome must be at least ${CHROME_MIN_WINDOW_W}x${CHROME_MIN_WINDOW_H} (the video tour films a 1600x900 frame). Set CHROME_WINDOW_SIZE=${CHROME_MIN_WINDOW_W},${CHROME_MIN_WINDOW_H} (or larger, e.g. 1920,1080) and relaunch.`,
    )
  }
  const piFrontendUrl = discoverPiFrontendUrl()
  log(
    `🌐 launching the run Chrome on a FIXED CDP port (session ${chromeSessionName}, profile ${sessionProfile}, port ${port}, window ${windowSize}${piFrontendUrl ? `, pi-frontend ${piFrontendUrl}` : ', no pi-frontend instance found'})`,
  )
  const inner = [
    `mkdir -p ${xdg}`,
    `[ -d ${sessionProfile} ] || cp -a "${chromeDir}" ${sessionProfile}`,
    // A copied profile can carry the SOURCE profile's singleton triple (SingletonLock ->
    // <host-name>-<pid of the host's daily Chrome>). Chrome then refuses to start with
    // "The profile appears to be in use by another Google Chrome process (…) on another
    // computer" — every attach then fails and the stage reports "cannot launch the run
    // Chrome" (<KEY>, 2026-10-07: all parallel runs inherit it from the same source).
    `rm -f "${sessionProfile}"/SingletonLock "${sessionProfile}"/SingletonCookie "${sessionProfile}"/SingletonSocket "${sessionProfile}"/DevToolsActivePort`,
    // never leave competing daemons/Chromes for this session behind.
    // ⚠️ The pkill pattern MUST be anchored on the chrome executable. A bare
    // `pkill -u pc -f "user-data-dir=<profile>"` also matches the wrapping shell that
    // runs this very command — `bash -lc "<inner>"` carries the pattern text in its own
    // argv — so pkill SIGTERMs its own launcher, sh() sees a non-zero exit and the run
    // dies with "cannot launch the run Chrome" (diagnosed on <KEY-200>, 2026-10-07; it hit
    // every run entering prebuild). The wrapper cmdline starts with `bash -lc`, the
    // browser with the chrome binary path, so the anchor separates them.
    `pkill -u pc -f "^/usr/bin/google-chrome.*user-data-dir=${sessionProfile}" 2>/dev/null || true`,
    `pkill -u pc -f "^/opt/google/chrome/chrome.*user-data-dir=${sessionProfile}" 2>/dev/null || true`,
    `sleep 1`,
    // Clear singleton state again AFTER the kills: a dying Chrome can re-write it, and
    // two mains on one user-data-dir never write DevToolsActivePort (<KEY>).
    `rm -f "${sessionProfile}"/SingletonLock "${sessionProfile}"/SingletonCookie "${sessionProfile}"/SingletonSocket "${sessionProfile}"/DevToolsActivePort`,
    // The FIXED port is the whole point: never `--remote-debugging-port=0`. The window size
    // is explicit (>= 1600x900) because the video tour needs the frame; niri may still tile
    // it smaller, which `chrome.sh viewport` detects before a capture starts.
    `setsid nohup env WAYLAND_DISPLAY="${'${WAYLAND_DISPLAY:-wayland-1}'}" XDG_RUNTIME_DIR="${'${XDG_RUNTIME_DIR:-/run/user/1000}'}" /usr/bin/google-chrome --ozone-platform=wayland --remote-debugging-port=${port} --user-data-dir="${sessionProfile}" --no-sandbox --disable-setuid-sandbox --disable-dev-shm-usage --no-first-run --no-default-browser-check --window-position=0,0 --window-size=${windowSize} about:blank >>"${logFile}" 2>&1 &`,
  ].join('; ')
  if (dryRun) {
    console.log(
      `  DRY-RUN: run Chrome would launch on FIXED CDP port ${port} (never 0), window ${windowSize}:\n    ${inner}\n  then attach: agent-browser --headed --session ${chromeSessionName} --pin-tab --profile ${sessionProfile} --cdp http://127.0.0.1:${port} open about:blank`,
    )
    return
  }
  // Record the port BEFORE the launch: even a failed launch must leave a port on
  // record, so later stages/agents probe a known port instead of inventing one.
  appendState(RUN_ENV, {
    CHROME_SESSION: chromeSessionName,
    CHROME_SESSION_PROFILE: sessionProfile,
    CHROME_XDG_DATA_HOME: xdg,
    CHROME_CDP_PORT: String(port),
    CHROME_WINDOW_SIZE: windowSize,
    ...(piFrontendUrl ? { PI_FRONTEND_URL: piFrontendUrl } : {}),
  })
  try {
    await sh(`bash -lc ${JSON.stringify(inner)}`)
  } catch (e: any) {
    await fail(`cannot start the run Chrome on port ${port} (session ${chromeSessionName}) — see ${logFile}: ${e?.message ?? e}`)
  }
  // Prove the browser really came up on the port we recorded (30s budget).
  let alive = false
  for (let i = 0; i < 60; i++) {
    await sleep(500)
    if (await chromeCdpAlive(port)) {
      alive = true
      break
    }
  }
  if (!alive) {
    await fail(
      `the run Chrome did not answer CDP on http://127.0.0.1:${port} within 30s (profile ${sessionProfile}) — see ${logFile}. Diagnose with \`bash ${SKILL_DIR}/scripts/chrome.sh status\`, then \`bash ${SKILL_DIR}/scripts/chrome.sh revive\``,
    )
  }
  // Attach the run's session TO the browser we just launched (labels/pin live on the
  // agent-browser side). An attach hiccup must not kill the run — CDP is already proven.
  const ab = `XDG_DATA_HOME=${xdg} agent-browser --headed --session ${chromeSessionName} --pin-tab --profile ${sessionProfile} --cdp http://127.0.0.1:${port}`
  const attach = `${ab} open about:blank${piFrontendUrl ? `; ${ab} tab new --label pi "${piFrontendUrl}"` : ''}`
  try {
    await sh(`bash -lc ${JSON.stringify(attach)}`)
  } catch (e: any) {
    log(`⚠️ agent-browser could not attach to the run Chrome (CDP is up on ${port}) — ${e?.message ?? e}`)
  }
  let chromePid = ''
  try {
    const { stdout } = await sh(`pgrep -u pc -f "^/usr/bin/google-chrome.*user-data-dir=${sessionProfile}" | head -1`)
    chromePid = stdout.trim()
  } catch {
    /* pid is informational */
  }
  appendState(RUN_ENV, {
    CHROME_LAUNCHED: '1',
    CHROME_CDP_PORT: String(port),
    CHROME_WINDOW_SIZE: windowSize,
    CHROME_LAUNCH_EPOCH: String(Math.floor(Date.now() / 1000)),
    ...(chromePid ? { CHROME_PID: chromePid } : {}),
  })
  log(`🌐 run Chrome up: CDP http://127.0.0.1:${port}${chromePid ? ` (pid ${chromePid})` : ''} — window ${windowSize}; CHROME_CDP_PORT + CHROME_WINDOW_SIZE + CHROME_LAUNCHED recorded in ${RUN_ENV}`)
}
/** Liveness probe before every browser-using stage: one automatic relaunch on the
 *  SAME profile that (re-)records the port; a second failure fails the stage loudly
 *  instead of letting the pane improvise its own browser. */
async function ensureChromeLive(stage: StageName): Promise<void> {
  if (!BROWSER_STAGES.has(stage)) return
  if (dryRun) {
    console.log(`  DRY-RUN: probe the run Chrome over CDP (CHROME_CDP_PORT from ${RUN_ENV}) before ${stage}, revive once on the same profile if dead`)
    return
  }
  if (runVar('CHROME_LAUNCHED') !== '1' && !chromePaneLaunched) {
    log(`🌐 ${stage}: no run Chrome recorded (CHROME_LAUNCHED unset) — skipping the liveness probe`)
    return
  }
  let port = Number(runVar('CHROME_CDP_PORT') || '')
  if (!port) {
    port = await discoverChromePort()
    log(`⚠️ ${stage}: CHROME_LAUNCHED=1 but CHROME_CDP_PORT is unset — discovered live port ${port || '<none>'} from the profile`)
    if (port) appendState(RUN_ENV, { CHROME_CDP_PORT: String(port) })
  }
  if (port && (await chromeCdpAlive(port))) {
    log(`🌐 ${stage}: run Chrome alive on CDP ${port}`)
    return
  }
  if (chromeRevives >= 1) {
    await fail(
      `the run Chrome is dead before ${stage} (CDP ${port || '<unknown>'}) and this run already relaunched it once — NOT retrying. Run \`bash ${SKILL_DIR}/scripts/chrome.sh status\`, then \`revive\`, then relaunch with --resume`,
    )
  }
  chromeRevives++
  log(`⚠️ ${stage}: run Chrome is not answering on CDP ${port || '<unknown>'} — single automatic relaunch on the SAME profile (${chromeProfile()})`)
  chromePaneLaunched = false
  await launchChromePane(true)
}

// ── preflight (script-owned, run automatically BEFORE the tour) ─────────────
// The four live runs of 2026-10-19 (<KEY-209>/1210/1211/1212) all reached the tour
// with a dashboard missing NEXT_PUBLIC_MICROSOFT_CLIENT_ID, an expired AWS SSO
// session and a signed-out GitHub browser — each discovered mid-tour, after the
// pane had already started. scripts/preflight.sh checks those up front and this
// gate refuses to launch the tour pane on any FAIL.
async function runPreflight(): Promise<void> {
  const script = `${SKILL_DIR}/scripts/preflight.sh`
  if (!existsSync(script)) await fail(`preflight script missing: ${script}`)
  if (dryRun) {
    console.log(`  DRY-RUN: bash ${script}  (PASS/FAIL/SKIP → ${PREFLIGHT_ENV}); any FAIL aborts before the tour pane`)
    return
  }
  log(`🔎 preflight before the tour — dashboard env/NEXT_PUBLIC keys, AWS SSO, GitHub API + browser login, dashboard JWT (results → ${PREFLIGHT_ENV})`)
  let code = 0
  let output = ''
  try {
    const r = await sh(`bash ${JSON.stringify(script)}`, {
      env: { WORKFLOW_RUN_ENV: RUN_ENV, WORKFLOW_PREFLIGHT_ENV: PREFLIGHT_ENV },
    })
    output = `${r.stdout}${r.stderr}`
  } catch (e: any) {
    code = Number(e?.code ?? 1)
    output = `${e?.stdout ?? ''}${e?.stderr ?? ''}`
  }
  for (const line of output.split(EOL)) if (line.trim()) log(`preflight: ${line}`)
  const results = readState(PREFLIGHT_ENV)
  const fails = Object.entries(results)
    .filter(([k, v]) => k.startsWith('PREFLIGHT_') && !k.endsWith('_DETAIL') && v === 'FAIL')
    .map(([k]) => k.replace(/^PREFLIGHT_/, '').toLowerCase().replace(/_/g, '-'))
  appendState(RUN_ENV, {
    PREFLIGHT_STATUS: code === 0 ? 'ok' : 'failed',
    PREFLIGHT_FILE: PREFLIGHT_ENV,
    PREFLIGHT_AT: String(Math.floor(Date.now() / 1000)),
    PREFLIGHT_FAILS: fails.join(' '),
  })
  if (code !== 0) {
    await fail(
      `preflight FAILED before the tour (${fails.join(', ') || 'see log'}) — the tour will NOT start blind. Fix each one-line remediation above, re-check with \`bash ${script}\`, then relaunch with --resume`,
    )
  }
  log('✅ preflight passed — the tour may start')
}

async function runStage(stage: StageName): Promise<void> {
  const spec = STAGE_SPECS[stage]
  if (!spec) await fail(`unknown stage '${stage}' — known stages: ${Object.keys(STAGE_SPECS).join(' ')}`)
  if (!existsSync(stagePrompt(stage))) await fail(`prompt file missing: ${stagePrompt(stage)}`)
  // v8.5 hardening (2026-10-15, <KEY>): SCREENSHOTS_DIR is script-owned and
  // UNCONDITIONAL — derived + mkdir -p'd here, before the pre-launch input check, for
  // EVERY stage in every mode. In iterate mode no stage before the tour runs `build`
  // (which used to be the only place that recorded it), so a fix round that pushed UI
  // changes died at the tour's pre-launch check with "input vars missing:
  // SCREENSHOTS_DIR". The run-start-up derivation is the primary one; this per-stage
  // call is the safety net that guarantees the var before any pane spins and upgrades
  // the provisional /tmp fallback once a stage has resolved WORKTREE.
  ensureScreenshotsDir(`before stage ${stage}`)
  // v8: pre-launch input verification — fail fast BEFORE the pane spins
  const preMissing = (spec.preRequires ?? []).filter(v => !runVar(v))
  if (preMissing.length > 0) {
    if (dryRun) console.log(`  DRY-RUN: would fail pre-launch — ${stage} missing input vars: ${preMissing.join(' ')}`)
    else await fail(`stage ${stage} cannot start — input vars missing from ${RUN_ENV}: ${preMissing.join(' ')} — fix state, then relaunch with --resume`)
  }
  // v8: script-owned reviewer resolution (FATAL here if config is missing)
  if (stage === 'ship-p8') await resolveReviewers()
  // Chrome is script-owned: launch the pane before prebuild (P0.5 needs it up)
  // and before tour (idempotent — CHROME_LAUNCHED in the run env no-ops it).
  if (stage === 'prebuild' || stage === 'tour') await launchChromePane()
  // Liveness probe before every browser-using stage: a dead Chrome gets ONE
  // automatic relaunch on the same profile (which records the port) — a stage never
  // starts with no browser and never improvises its own.
  await ensureChromeLive(stage)
  // Preflight (script-owned) BEFORE the tour: dashboard env/NEXT_PUBLIC keys, AWS SSO,
  // GitHub API + browser login, local dashboard JWT. Fails loudly so the tour never
  // starts blind (<KEY-209>/1210/1211/1212 all hit these mid-run). Review mode's tour
  // is a read-only walkthrough with no uploads, so it is exempt.
  if (stage === 'tour' && mode !== 'review') await runPreflight()
  const taskFile = writeTaskFile(stage, stageExtra(stage))
  const paneName = `workflow-${stage}-${TICKET_LABEL}`
  if (!dryRun) appendState(RUN_ENV, { [`STAGE_${stage.toUpperCase().replace(/-/g, '_')}_START_EPOCH`]: String(Math.floor(Date.now() / 1000)) })
  log(`🚀 stage ${stage} (${spec.kind}) → pane ${paneName}`)
  await notify(`workflow-do ${TICKET_LABEL}: ${stage} starting (${spec.kind}) — pane ${paneName}`)
  await launchStagePane(stage, taskFile)
  writeStatus('waiting', `stage ${stage} (pane ${paneName})`)
  await waitStageDone(stage)
  // dry-run never reaches verifyStageOut (it returns before the surrender wait),
  // so surface the ready-for-review gate here — the operator must see that a
  // finished build/iterate stage is expected to undraft the PR.
  if (dryRun && (stage === 'ship-p8' || stage === 'build-fix')) await ensurePrReadyForReview(stage)
  log(`🏁 stage ${stage} surrendered + verified`)
  await closeStagePane(stage)
  // v8.5 hardening: proof-of-capture gate — a completed tour must have produced real,
  // uploaded artifacts. Build/iterate only: the review-mode local tour is a read-only
  // walkthrough by design (no artifacts), so it is exempt.
  if (stage === 'tour' && mode !== 'review') await verifyTourCaptured()
  if (!dryRun) appendState(RUN_ENV, { [`STAGE_${stage.toUpperCase().replace(/-/g, '_')}_END_EPOCH`]: String(Math.floor(Date.now() / 1000)) })
  await notify(`workflow-do ${TICKET_LABEL}: ${stage} complete ✅`)
}

// ── iterate loop (shared: in-run continuation after Wrap-up, and fresh iterate) ──
async function park(reason: string): Promise<void> {
  // v8.5 hardening: never park past a mandatory tour (a fix round that pushed UI
  // changes owes screenshots). Runs it first; a tour that cannot start fails loudly.
  await runTourIfPending('before parking')
  log(`⏸️ run parked: ${reason}`)
  await notify(`workflow-do ${TICKET_LABEL}: parked — ${reason}`)
  await appendRunStats()
  writeStatus('parked', reason)
}
async function iterateLoop(): Promise<void> {
  for (;;) {
    // v8.5 hardening: a pending tour (UI_CHANGED=1, last fix round after the last
    // tour) is owed before anything else in this iteration — no path skips it.
    await runTourIfPending('before review-state')
    await runStage('review-state')
    const recommended = runVar('RECOMMENDED_ACTION')
    if (recommended === 'fix-round') {
      await runStage('build-fix')
      await waitCiGreen() // v8: script-owned CI wait before review-state classifies
      // v8.5 hardening: the tour is MANDATORY whenever UI_CHANGED=1 — this path
      // must run it, never continue past it.
      await runTourIfPending('after fix round')
      if (runVar('LOOP_DECISION') === 'close') {
        await park('user chose close after fix round')
        return
      }
      continue
    }
    if (recommended === 'await-re-review') {
      // Post-fix park (policy 2026-10-15): a fix round already ran, so the run asks
      // nothing and never merges — the ticket is back at the review-pending status
      // and a re-review is expected. Read the fix round from the run env, no new state.
      const why = runVar('STAGE_BUILD_FIX_END_EPOCH')
        ? 'fix round ran in this run'
        : 'peer approval predates the current head'
      await park(`awaiting re-review — ${why}; ticket set to the review-pending status`)
      return
    }
    if (recommended === 'approval-gate') {
      const mergeDecision = runVar('MERGE_DECISION')
      if (mergeDecision === 'merge') {
        await runStage('ship-p10')
        await runStage('post')
        await runTourIfPending('before reporting done')
        await appendRunStats()
        log('✅ run complete: PR merged, post done')
        await notify(`workflow-do ${TICKET_LABEL}: merged + post complete ✅`)
        writeStatus('done', 'merged + post complete')
        return
      }
      if (mergeDecision === 'fix') {
        log('user chose fix at gate → another review round')
        continue
      }
      await park(`approval gate — decision: ${mergeDecision}`)
      return
    }
    await park('review state clean, nothing to do')
    return
  }
}

// ── main flow ───────────────────────────────────────────────────────────────
// The target is resolved once, above (supplied value → legacy recorded name →
// default). Re-export the effective value so every child process inherits it.
process.env.WORKFLOW_ORCH_SESSION = ORCH_SESSION

if (dryRun) {
  console.log('── workflow-do DRY RUN ─────────────────────────────────────────')
  console.log(`mode: ${mode}  arg: ${modeArg || '<none>'}  ticket-label: ${TICKET_LABEL}  intercom target (chief of staff/launch session): ${ORCH_SESSION}`)
  console.log(`run env: ${RUN_ENV}   log: ${RUN_LOG}   shared policy: ${SHARED_POLICY}`)
  console.log('')
}

// Fresh build run over leftover state is a mistake — force --resume or --fresh.
if (!dryRun && mode === 'build' && !singleStage && !resume && !fresh) {
  const done = completeStages(RUN_ENV)
  if (done.length > 0) {
    await fail(`${RUN_ENV} already has completed stages (${done.join(' ')}) — use --resume to continue or --fresh to restart`)
  }
}

// resume: skip stages already completed OK — keep only stages AFTER the last
// completed stage in plan order (iterate mode never uses a static plan here).
let plan: StageName[] = []
if (singleStage) {
  plan = [singleStage as StageName]
} else if (mode === 'build') {
  const fullPlan: StageName[] = ['scout', 'prebuild', 'build', 'tour', 'ship-p8', 'wrap-up']
  if (resume) {
    const done = completeStages(RUN_ENV)
    const remaining: StageName[] = []
    let keep = false
    for (const s of fullPlan) {
      if (keep || !done.includes(s)) {
        keep = true
        remaining.push(s)
      }
    }
    plan = remaining
    log(`resume: remaining plan:${plan.length ? ' ' + plan.join(' ') : ' <none>'}`)
    if (plan.length === 0) {
      log('nothing left to run')
      process.exit(0)
    }
  } else {
    plan = fullPlan
  }
}

// ── GitHub owner + credential preflight (fail-fast, before ANY stage pane) ──
// The triage org key (WORKFLOW_ORG, e.g. `<org>`) is NOT the GitHub owner (e.g.
// `<github-org>`), and the ambient gh account on this machine is usually the WRONG
// one for the repo. Every stage must read GITHUB_ORG + the credential from the run
// env instead of hand-deriving them — so resolve BOTH here, VERIFY real repo access,
// and append them BEFORE the first pane launches. Missing/unresolvable/failed access
// = FATAL, exactly like the REVIEWERS config gate. (User directive 2026-09-30.)
async function resolveGithubAccess(): Promise<void> {
  const org = WORKFLOW_ORG
  const cwd = process.env.WORKFLOW_CWD ?? process.cwd()
  const repo = runVar('REPO_NAME') || cwd.split('/').filter(Boolean).pop() || ''
  let ghOrg = runVar('GITHUB_ORG')
  let account = ''
  // 1) GitHub owner: the actual origin remote is authoritative for this repo (the
  //    triage key `<org>` never resolves — the owner is `<github-org>`).
  if (!ghOrg) {
    const remote = await shSoft(`git -C "${cwd}" remote get-url origin 2>/dev/null`)
    ghOrg = /github\.com[:\/]([^/]+)\/([^/"'\s]+?)(?:\.git)?$/.exec(remote)?.[1] ?? ''
  }
  // 2) credential account: match org-config by the triage org key, by that key as a
  //    githubOrg, or by the RESOLVED owner (e.g. githubOrg <github-org> -> mendelmodge).
  try {
    const cfg = JSON.parse(readFileSync(`${process.env.HOME}/secrets/org-config.json`, 'utf8')) as {
      bot?: { githubUsername?: string }
      orgs?: Array<{ org?: string; githubOrg?: string; poll?: { github?: { account?: string } } }>
    }
    const match = (cfg.orgs ?? []).find(
      (o) => o.org === org || o.githubOrg === org || (ghOrg !== '' && o.githubOrg === ghOrg),
    )
    ghOrg = ghOrg || match?.githubOrg || ''
    account =
      match?.poll?.github?.account ||
      (process.env[`GH_TOKEN_${org}`] ? org : '') ||
      (cfg.bot?.githubUsername && process.env[`GH_TOKEN_${cfg.bot.githubUsername}`] ? cfg.bot.githubUsername : '') ||
      ''
  } catch {
    /* resolved below or FATAL */
  }
  const tokenEnv = account ? `GH_TOKEN_${account}` : ''
  const token = (tokenEnv && process.env[tokenEnv]) || ''
  const kv: Record<string, string> = {}
  if (ghOrg) kv.GITHUB_ORG = ghOrg
  if (account) { kv.GH_ACCOUNT = account; kv.GH_TOKEN_ENV = tokenEnv }
  if (Object.keys(kv).length) appendState(RUN_ENV, kv)

  if (dryRun) {
    console.log(`  DRY-RUN: github preflight — org=${ghOrg || '<unresolved>'} account=${account || '<unresolved>'} tokenEnv=${tokenEnv || '-'} repo=${ghOrg}/${repo}`)
    return
  }
  if (!repo) await fail('GitHub preflight: REPO_NAME unresolved (no run var and no cwd basename) — cannot verify repo access; halt before any stage')
  if (!ghOrg)
    await fail(`GitHub preflight: GitHub owner unresolved for org '${org}' — add/fix \`githubOrg\` in $ORG_CONFIG_DIR/org-config.json (or a parseable origin remote), then relaunch with --resume`)
  if (!account || !token)
    await fail(`GitHub preflight: credential unresolved for org '${org}' (github owner '${ghOrg}') — expected ${tokenEnv || 'GH_TOKEN_<account>'} in the cage env; set \`poll.github.account\` for that org in $ORG_CONFIG_DIR/org-config.json (cage() exports GH_TOKEN_<account>), then relaunch with --resume`)
  const seen = await shSoft(`GH_TOKEN="${token}" gh repo view "${ghOrg}/${repo}" --json nameWithOwner -q .nameWithOwner 2>&1`)
  if (!seen.includes(`${ghOrg}/${repo}`))
    await fail(`GitHub preflight: ${tokenEnv} cannot read ${ghOrg}/${repo} (${seen.slice(0, 200) || 'no output'}) — halt before any stage pane; fix the token/repo access, then relaunch with --resume`)
  log(`🔐 GitHub access verified: ${ghOrg}/${repo} via ${tokenEnv}`)
}

// ── build mode ──────────────────────────────────────────────────────────────
if (mode === 'build') {
  await resolveGithubAccess() // fail-fast BEFORE scout/prebuild panes spin
  for (const stage of plan) {
    if (stage === 'prebuild') await detectContext() // v8: script-owned detection
    await runStage(stage)
    if (stage === 'wrap-up') {
      await writeIterateHandoffBlock()
      if (runVar('DECISION_CLOSE_OR_ITERATE') === 'close') {
        await park('PR ready for review — build run closed. Iterate later: workflow-do.ts iterate <PR-ref>')
        process.exit(0)
      }
      await iterateLoop() // state is live in this run — skip hydrate
      break
    }
  }
  // v8.5 hardening: never report a build run complete with a mandatory tour still
  // pending (e.g. a --stage intervention that reran build-fix and skipped the plan's
  // tour). Idempotent — a no-op when UI_CHANGED is unset or the tour already ran.
  await runTourIfPending('build run end')
  process.exit(0)
}

// ── iterate mode (fresh run) ────────────────────────────────────────────────
if (mode === 'iterate') {
  // Iterate path skips detectContext — verify the GitHub owner + credential up front
  // so stage agents read them from the run env and never re-derive them (triage org key
  // ≠ org-config.json key ≠ GitHub org; ambient gh account is often the wrong one).
  await resolveGithubAccess()
  const done0 = completeStages(RUN_ENV)
  // v8.5 (2026-10-15, <KEY>): the failure-fallback's documented remedy is
  // `--stage <name>` ("rerun a single stage"), but the iterate branch ignored it and
  // always ran hydrate → review-state — and review-state is INTERACTIVE, so a run that
  // died mid-loop could not be resumed without re-asking the human. Honour it here: run
  // the named stage, then CONTINUE the loop (the run must still finish — a fallback that
  // exits right after one stage would leave the run mid-flight while the chief of staff thinks
  // it completed).
  if (singleStage) {
    log(`single-stage intervention: ${singleStage} (then continue the iterate loop)`)
    await runStage(singleStage as StageName)
  } else if (resume && done0.includes('hydrate')) {
    log('resume: hydrate already done — re-entering the iterate loop')
  } else {
    await runStage('hydrate')
  }
  // v8.5 hardening (<KEY>): a fix round that pushed UI changes owes a tour — no path
  // may park, exit or report success past it, so the guard sits ABOVE the PR-state gates
  // (a resumed run whose PR has since merged must still tour). This subsumes the earlier
  // resume-only check: the tour runs whenever UI_CHANGED=1 and the last fix round ended
  // after the last tour. runStage fails LOUDLY if the tour cannot start — never a silent
  // skip.
  await runTourIfPending(singleStage ? `after --stage ${singleStage}` : 'iterate entry')
  const prState = runVar('PR_STATE')
  if (prState === 'MERGED') {
    log('PR already merged — nothing to do')
    writeStatus('done', 'PR already merged')
    process.exit(0)
  }
  if (prState === 'CLOSED') await fail('PR is closed unmerged — stopping')
  await iterateLoop()
  process.exit(0)
}

// ── review mode (peer review of someone else's PR) ──────────────────────────
// Cage-based like any run, but review-only: the script NEVER merges, pushes, or
// modifies code. Ends at the verdict gate (review posted + ticket statuses).
// Knowledge layer: ~/.agents/skills/workflow-do-review/SKILL.md.
if (mode === 'review') {
  if (!runVar('GITHUB_ORG')) {
    const remoteUrl = await shSoft(`git -C "${process.env.WORKFLOW_CWD || process.cwd()}" remote get-url origin 2>/dev/null`)
    const ghOrg = /github\.com[:\/]([^/]+)\/([^/"'\s]+?)(?:\.git)?$/.exec(remoteUrl)?.[1] ?? ''
    if (ghOrg) appendState(RUN_ENV, { GITHUB_ORG: ghOrg })
  }
  const reviewPlan: StageName[] = ['review-gather', 'review-audit', 'review-walkthrough']
  if (resume) {
    const done = completeStages(RUN_ENV)
    plan = reviewPlan.filter(s => !done.includes(s))
    log(`resume: remaining plan:${plan.length ? ' ' + plan.join(' ') : ' <none>'}`)
    if (plan.length === 0) { log('nothing left to run'); process.exit(0) }
  } else {
    plan = reviewPlan
  }
  for (const stage of plan) await runStage(stage)
  // Conditional local tour: only when the reviewer asked for it at the walkthrough
  if (runVar('REVIEW_TOUR_NEEDED') === 'yes' && !completeStages(RUN_ENV).includes('tour')) {
    log('reviewer requested a local tour → running tour stage')
    await runStage('tour')
  }
  await runStage('review-verdict')
  await appendRunStats()
  log('✅ review complete: verdict submitted, statuses updated')
  await notify(`workflow-do ${TICKET_LABEL}: review complete ✅`)
  writeStatus('done', 'review submitted')
  process.exit(0)
}