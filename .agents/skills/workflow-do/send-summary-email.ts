#!/usr/bin/env npx tsx
// send-summary-email.ts — fetch → verify → process → send, as three functions.
//
//   fetch()   gathers everything (run env, pi session logs, Notion, GitHub API,
//             phases.json) and outputs a single JSON object — the verified
//             source of truth. Run with --fetch-only to get it for human
//             verification.
//   process() turns the verified JSON into a multipart MIME email (text
//             fallback + styled HTML: risk meter, phases table, headline totals
//             table and a one-row-per-session table).
//   send()    pipes the MIME message to msmtp.
//
// Session scope: EVERY pi session belonging to the ticket since its first
// session — all dirs under ~/.pi/agent/sessions plus RUN_SESSION_DIR, accepting
// a session when its directory, its recorded cwd (the session header line) or
// its label mentions the ticket label or ticket number. Earlier runs of the same
// ticket, sibling worktrees (…-review, …-before) and earlier days all count;
// there is no span-overlap restriction. The count and the files used are printed
// and recorded (sessionSources).
//
// Totals: days since started = now − earliest first timestamp across ALL ticket
// sessions; total time taken = SUM of the per-session durations (never the
// wall-clock span first-start → last-end); review iterations = how many times the
// ticket went to Review Denied and back into a fix round.
//
// Usage:
//   tsx send-summary-email.ts --fetch-only [--out /tmp/summary.json]
//   tsx send-summary-email.ts --render /tmp/body.html --json /tmp/summary.json
//   tsx send-summary-email.ts --send --json /tmp/summary-verified.json
//
// ⚠️ Verification NEVER sends mail: use --fetch-only + --render and inspect the
// rendered body. No email is sent unless the user explicitly asks for one in
// that session.
//
// Phases come from the shared phases.json (same file the skills read).

import { execSync, spawnSync } from 'node:child_process';
import {
  readFileSync,
  writeFileSync,
  existsSync,
  readdirSync,
  statSync,
  mkdirSync,
  rmSync,
} from 'node:fs';
import * as path from 'node:path';

// ─────────────────────── shared phase list ───────────────────────

interface AgentDef {
  agent: string;
  icon: string;
  name: string;
  stage?: string;
  stages?: string[];
  phases: { id: string; icon: string; name: string }[];
}

function loadAgents(): AgentDef[] {
  const p1 = path.join(path.dirname(process.argv[1] ?? '.'), 'phases.json');
  const p2 = path.join(process.env.HOME ?? '', '.agents', 'skills', 'workflow-do', 'phases.json');
  const file = [p1, p2].find(existsSync) ?? p2;
  return (JSON.parse(readFileSync(file, 'utf8')) as { agents: AgentDef[] }).agents;
}

// ───────────────────────── helpers ─────────────────────────

function sh(cmd: string): string {
  try {
    return execSync(cmd, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
  } catch {
    return '';
  }
}

function safeJson(text: string | undefined | null): any {
  if (text === undefined || text === null) return null;
  if (typeof text !== 'string') return text;
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

function fmtInt(n: number): string {
  return n.toLocaleString('en-US');
}

function fmtDuration(minutes: number): string {
  const h = Math.floor(minutes / 60);
  const m = Math.round(minutes - h * 60);
  return h > 0 ? `${h}h ${m}m` : `${m}m`;
}

// Download each screenshot (gh-token auth for private attachments), resize to
// max 800px wide when ImageMagick is available, and return inline CID entries.
function prepareInlineImages(d: SummaryData, tmpDir: string): { cid: string; file: string; caption: string }[] {
  const out: { cid: string; file: string; caption: string }[] = [];
  let idx = 0;
  let rawIdx = 0;
  for (const s of d.screenshots) {
    let bytes: Buffer | null = null;
    try {
      if (s.path && existsSync(s.path)) bytes = readFileSync(s.path);
      else if (s.url) {
        const local = path.join(tmpDir, `shot-raw-${++rawIdx}.bin`);
        spawnSync('curl', ['-sL', '--max-time', '60', '-H', `Authorization: Bearer ${process.env.GH_TOKEN ?? sh('gh auth token 2>/dev/null')}`, s.url, '-o', local]);
        if (existsSync(local)) bytes = readFileSync(local);
      }
    } catch {}
    if (!bytes || bytes.length === 0 || bytes.length > 5242880) continue;
    const looksImage = bytes.slice(0, 8).toString('hex') === '89504e470d0a1a0a' || bytes.slice(0, 3).toString() === String.fromCharCode(0xff, 0xd8, 0xff);
    if (!looksLikeImage(bytes)) continue;
    idx++;
    const cid = `screenshot-${idx}`;
    const file = path.join(tmpDir, `screenshot-${idx}.png`);
    writeFileSync(file, bytes);
    out.push({ cid, file, caption: s.caption });
  }
  console.error('DBG inline: downloaded', out.length, 'of', d.screenshots.length, 'screenshots');
  return out;
}

function looksLikeImage(bytes: Buffer): boolean {
  const png = bytes.slice(0, 8).toString('hex') === '89504e470d0a1a0a';
  const jpeg = bytes.slice(0, 3).toString() === String.fromCharCode(0xff, 0xd8, 0xff);
  const gif = bytes.slice(0, 3).toString() === 'GIF';
  const webp = bytes.slice(8, 12).toString() === 'WEBP';
  return png || jpeg || gif || webp;
}

function esc(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function loadRunEnv(): Record<string, string> {
  const envPath = process.env.WORKFLOW_RUN_ENV || '/tmp/workflow-run.env';
  const out: Record<string, string> = {};
  if (!existsSync(envPath)) return out;
  for (const line of readFileSync(envPath, 'utf8').split('\n')) {
    const m = line.match(/^([A-Z_0-9]+)="(.*)"$/);
    if (m) out[m[1]] = m[2];
  }
  return out;
}

// ───────────────────────── 1. FETCH ─────────────────────────

interface SessionSpan {
  file: string;
  name: string;
  cwd: string;
  tokensIn: number;
  tokensOut: number;
  cacheRead: number;
  cost: number;
  first: string;
  last: string;
  minutes: number;
  humanMsgs: number;
}

function scanSessionFile(file: string): {
  tokensIn: number;
  tokensOut: number;
  cacheRead: number;
  cost: number;
  first: string;
  last: string;
  name: string;
  cwd: string;
  humanMsgs: number;
} {
  let tokensIn = 0,
    tokensOut = 0,
    cacheRead = 0,
    cost = 0,
    userMsgCount = 0,
    humanMsgs = 0;
  let first = '',
    last = '',
    name = '',
    cwd = '';
  const lines = readFileSync(file, 'utf8').split('\n').filter(Boolean);
  for (const line of lines) {
    const tsM = line.match(/"timestamp":"([^"]+)"/);
    const ts = tsM ? tsM[1] : null;
    if (ts) {
      if (!first || ts < first) first = ts;
      if (!last || ts > last) last = ts;
    }
    // the session header line carries the recorded cwd of the session
    if (!cwd && line.includes('"type":"session"')) {
      const c = line.match(/"cwd":"([^"]*)"/);
      if (c) cwd = c[1];
    }
    if (line.includes('"session_info"')) {
      const d = safeJson(line);
      if (d?.name) name = d.name;
    }
    if (line.includes('"input":')) {
      const i = line.match(/"input":(\d+)/);
      const o = line.match(/"output":(\d+)/);
      const c = line.match(/"cacheRead":(\d+)/);
      if (i) tokensIn += parseInt(i[1]);
      if (o) tokensOut += parseInt(o[1]);
      if (c) cacheRead += parseInt(c[1]);
    }
    if (line.includes('"cost":')) {
      const c = line.match(/"cost":(\{[^}]*\})/);
      if (c) {
        const o = safeJson(c[1]);
        if (o)
          cost += (o.input ?? 0) + (o.output ?? 0) + (o.cacheRead ?? 0) + (o.cacheWrite ?? 0) + (o.reasoning ?? 0);
      }
    }
    if (line.includes('"role":"user"')) userMsgCount++;
  }
  // sessions are launched automatically — the first user message is the launch prompt
  humanMsgs = Math.max(0, userMsgCount - 1);
  return { tokensIn, tokensOut, cacheRead, cost, first, last, name, cwd, humanMsgs };
}

function escapeRegExp(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

/** Ticket-label / ticket-number matchers (org-neutral: any "<PREFIX>-<n>" id). */
function ticketMatchers(ticketId: string): { label: RegExp; number: RegExp | null } {
  const label = new RegExp(escapeRegExp(ticketId), 'i');
  const num = ticketId.match(/(\d+)\s*$/)?.[1] ?? null;
  const number = num ? new RegExp(`(^|[^0-9])${num}([^0-9]|$)`) : null;
  return { label, number };
}

/** True when the text (dir path, recorded cwd or session label) names the ticket. */
function mentionsTicket(text: string, m: { label: RegExp; number: RegExp | null }): boolean {
  if (!text) return false;
  return m.label.test(text) || (m.number !== null && m.number.test(text));
}

/**
 * EVERY pi session belonging to the ticket: scan all dirs under
 * ~/.pi/agent/sessions plus RUN_SESSION_DIR, with NO span-overlap restriction,
 * so earlier runs of the same ticket, sibling worktrees of that ticket
 * (…-review, …-before) and earlier days are all included. The accept decision
 * (dir / recorded cwd / label mentions the ticket) is applied in the caller
 * after the full scan, so renamed sessions are matched on their latest name.
 */
function findSessionFiles(ticketId: string, runSessionDir: string | undefined): string[] {
  const sessRoot = path.join(process.env.HOME ?? '$HOME', '.pi', 'agent', 'sessions');
  const m = ticketMatchers(ticketId);
  const num = ticketId.match(/(\d+)\s*$/)?.[1] ?? null;
  const pre = [escapeRegExp(ticketId), num ? `(^|[^0-9])${num}([^0-9]|$)` : ''].filter(Boolean).join('|');
  const candidates = new Set<string>();
  // cheap prefilter: any session file that mentions the label or the number at all
  for (const h of sh(`grep -rlE --include='*.jsonl' '${pre}' '${sessRoot}'`).split('\n')) {
    if (h) candidates.add(h);
  }
  // every session dir (matched by directory name) + the run's own session dir
  const dirs: string[] = [];
  try {
    for (const d of readdirSync(sessRoot)) dirs.push(path.join(sessRoot, d));
  } catch {}
  if (runSessionDir) {
    dirs.push(path.isAbsolute(runSessionDir) ? runSessionDir : path.join(sessRoot, runSessionDir));
  }
  for (const dir of dirs) {
    let names: string[] = [];
    try {
      if (!statSync(dir).isDirectory()) continue;
      names = readdirSync(dir).filter((f: string) => f.endsWith('.jsonl'));
    } catch {
      continue;
    }
    if (names.length === 0) continue;
    const dirMatch = mentionsTicket(dir, m);
    if (!dirMatch) continue;
    for (const n of names) candidates.add(path.join(dir, n));
  }
  return [...candidates].filter((f) => existsSync(f)).sort();
}

function fetch(opts: {
  repoRoot: string;
  repoSlug: string;
  ghToken: string;
  notionToken: string;
  notionPageId: string | null;
  ticketId: string;
}): SummaryData {
  const agents = loadAgents();
  const runVars = loadRunEnv();
  const files = findSessionFiles(opts.ticketId, runVars.RUN_SESSION_DIR ?? '');

  // scan every candidate once and keep EVERY session that belongs to the ticket:
  // its directory, its recorded cwd or its label mentions the ticket label or
  // ticket number. No span-overlap restriction — earlier runs of the same ticket,
  // sibling worktrees (-review, -before) and earlier days all count.
  const spans: SessionSpan[] = [];
  const t = ticketMatchers(opts.ticketId);
  for (const f of files) {
    const s = scanSessionFile(f);
    const isTicketSession =
      mentionsTicket(path.dirname(f), t) || mentionsTicket(s.cwd, t) || mentionsTicket(s.name, t);
    if (!isTicketSession) continue;
    let t0: number | null = null, t1: number | null = null;
    try { t0 = s.first ? new Date(s.first).getTime() : null; t1 = s.last ? new Date(s.last).getTime() : null; if (t1 !== null && isNaN(t1)) t1 = null; if (t0 !== null && isNaN(t0)) t0 = null; } catch { }
    spans.push({
      file: f,
      name: s.name || `${path.basename(path.dirname(f))}/${path.basename(f, '.jsonl')}`,
      cwd: s.cwd,
      tokensIn: s.tokensIn,
      tokensOut: s.tokensOut,
      cacheRead: s.cacheRead,
      cost: s.cost,
      first: s.first,
      last: s.last,
      minutes: t0 !== null && t1 !== null ? Math.round((t1 - t0) / 60000) : 0,
      humanMsgs: s.humanMsgs,
    });
  }
  // sorted by start time — the per-session table is rendered in this order
  spans.sort((a, b) => (a.first || '').localeCompare(b.first || ''));
  console.error(`DBG sessions: ${spans.length} ticket session(s) for ${opts.ticketId} (scanned ${files.length} candidate file(s))`);
  for (const s of spans) console.error(`DBG session: ${s.first || '?'}  ${s.name}  ${s.file}`);

  // map sessions to AGENTS via the stage prefix in the session name
  const byAgent = new Map<string, { tokens: number; minutes: number; human: number }>();
  let tokensIn = 0, tokensOut = 0, cacheRead = 0, costTotal = 0;
  let firstTs: string | null = null, lastTs: string | null = null;

  for (const s of spans) {
    const stg = sessionStage(s.name);
    const agent = agents.find((a) => a.stage === stg || (a.stages ?? []).includes(stg ?? ''));
    const tokens = s.tokensIn + s.tokensOut + s.cacheRead;
    if (agent) {
      const agg = byAgent.get(agent.agent) ?? { tokens: 0, minutes: 0, human: 0 };
      agg.tokens += tokens;
      agg.minutes += s.minutes;
      agg.human += s.humanMsgs;
      byAgent.set(agent.agent, agg);
    }
    tokensIn += s.tokensIn;
    tokensOut += s.tokensOut;
    cacheRead += s.cacheRead;
    costTotal += s.cost;
    if (s.first && (!firstTs || s.first < firstTs)) firstTs = s.first;
    if (s.last && (!lastTs || s.last > lastTs)) lastTs = s.last;
  }

  const steps: StepRow[] = agents.map((a) => {
    const agg = byAgent.get(a.agent);
    return {
      agent: a.agent,
      icon: a.icon,
      name: a.name,
      ran: agg !== undefined,
      phases: a.phases,
      substeps: agg ? a.phases.map((p) => `${p.icon} ${p.id} ${p.name}`).join('\n') : '',
      tokens: agg ? fmtInt(agg.tokens) : '—',
      time: agg ? fmtDuration(agg.minutes) : '—',
      human: agg ? String(agg.human) : '—',
    };
  });

  const totalMinutes = spans.reduce((acc, s) => acc + s.minutes, 0);

  // one row per session, sorted by start time — the per-session table is the
  // source of truth for tokens / human prompts / cost / time taken
  const sessions: SessionRow[] = spans.map((s) => ({
    name: s.name,
    file: s.file,
    start: s.first,
    end: s.last,
    minutes: s.minutes,
    timeFormatted: fmtDuration(s.minutes),
    tokens: s.tokensIn + s.tokensOut + s.cacheRead,
    tokensFormatted: fmtInt(s.tokensIn + s.tokensOut + s.cacheRead),
    cost: s.cost,
    costFormatted: s.cost > 0 ? `$${s.cost.toFixed(2)}` : '—',
    humanMsgs: s.humanMsgs,
  }));

  // Notion: created time, title, motivation (Task description paragraph)
  let notionCreatedTime: string | null = null;
  let title = '';
  let motivation = '';
  const assignees: string[] = [];
  if (opts.notionPageId && opts.notionToken) {
    const page = safeJson(
      sh(`curl -s -H "Authorization: Bearer ${opts.notionToken}" -H "Notion-Version: 2022-06-28" https://api.notion.com/v1/pages/${opts.notionPageId}`),
    );
    if (page?.created_time) {
      notionCreatedTime = page.created_time;
      const props = page.properties ?? {};
      for (const [k, v] of Object.entries(props as Record<string, any>)) {
        if (v?.type === 'title') title = v.title.map((t: any) => t.plain_text).join(' ');
        if (v?.type === 'people') for (const p of v.people) assignees.push(p.name ?? '');
      }
      const blocks = safeJson(
        sh(`curl -s -H "Authorization: Bearer ${opts.notionToken}" -H "Notion-Version: 2022-06-28" https://api.notion.com/v1/blocks/${opts.notionPageId}/children`),
      );
      if (blocks?.results) {
        let grabbing = false;
        for (const b of (blocks as any).results) {
          const t = b.type;
          const txt = (b[t]?.rich_text ?? []).map((x: any) => x.plain_text).join(' ');
          if (t === 'heading_2') {
            grabbing = txt.includes('Task description');
            continue;
          }
          if (grabbing && t === 'paragraph' && txt.trim()) {
            motivation = txt;
            break;
          }
        }
      }
    }
  }

  // GitHub: PR reviews (non-owner rounds) + PR body (risk meter)
  let reviewRoundsByOthers = 0;
  let changesRequestedRounds = 0;
  const owner = process.env.TICKET_OWNER_ACCOUNT ?? orgGithubAccount();
  const prNum = prNumberFromUrl(process.env.PR_URL ?? '') ?? Number(runVars.PR_NUMBER ?? 0);
  if (opts.ghToken && opts.repoSlug && prNum) {
    const reviews = safeJson(
      sh(
        `gh api repos/${opts.repoSlug}/pulls/${prNum}/reviews --jq '[.[] | {author: .user.login, state: .state}]'`,
      ),
    ) as { author?: string; state?: string }[];
    for (const r of reviews ?? []) {
      const login = r.author ?? '';
      if (loginIsOwner(login, owner)) continue;
      reviewRoundsByOthers++;
      if (r.state?.toUpperCase() === 'CHANGES_REQUESTED') changesRequestedRounds++;
    }
  }

  // Changes + risk from the PR body when not provided via env
  let dbSummary = process.env.DB_SUMMARY ?? '';
  let backendSummary = process.env.BACKEND_SUMMARY ?? '';
  let frontendSummary = process.env.FRONTEND_SUMMARY ?? '';
  let riskMeter = process.env.RISK_METER ?? '';
  let deploymentStatus = process.env.DEPLOYMENT_STATUS ?? '';
  let friction = process.env.FRICTION ?? '';
  let ticketScreenshots: Screenshot[] = parseScreenshots(process.env.SCREENSHOTS ?? '');
  const prBody = opts.ghToken && opts.repoSlug && prNum ? sh(`gh pr view ${prNum} -R ${opts.repoSlug} --json body --jq .body`) : '';
  if (prBody) {
    if (!riskMeter) {
      const m = prBody.match(/## Risk Assessment\n\n(.+)/);
      if (m) riskMeter = m[1].split('\n')[0].replace(/`/g, '');
    }
    if (!dbSummary) dbSummary = prSection(prBody, 'Database Changes');
    if (!backendSummary) backendSummary = prSection(prBody, 'Migrations') || prSection(prBody, 'Backend Changes');
    if (!frontendSummary) frontendSummary = prSection(prBody, 'Client Changes') || prSection(prBody, 'Frontend Changes');
    // guided-tour screenshots: the PR body's inline images (tour evidence) —
    // used whenever the tour agent's SCREENSHOTS env lines are not provided
    if (ticketScreenshots.length === 0) {
      const imgRe = /!\[([^\]]*)\]\((https:\/\/[^)\s]+)\)/g;
      let im: RegExpExecArray | null;
      while ((im = imgRe.exec(prBody)) !== null) {
        ticketScreenshots.push({ path: '', url: im[2], caption: im[1] });
      }
    }
  }
  const motivationFinal = motivation || process.env.MOTIVATION || '';

  // review iterations: how many times the ticket went to Review Denied and back
  // into a fix round — handoff → run env/state → PR review history
  const worktree = process.env.WORKTREE ?? runVars.WORKTREE ?? '';
  const reviewIter = resolveReviewIterations(worktree, opts.ticketId, changesRequestedRounds);

  return {
    ticket: {
      id: opts.ticketId,
      title,
      url: process.env.TICKET_URL ?? (opts.notionPageId ? `https://app.notion.com/p?id=${opts.notionPageId}` : ''),
      notionCreatedTime,
      assignees,
    },
    pr: {
      url: process.env.PR_URL ?? runVars.PR_URL ?? '',
      number: prNum ?? prNumberFromUrl(process.env.PR_URL ?? ''),
      reviewRoundsByOthers,
      changesRequestedRounds,
      reviewIterations: reviewIter.count,
      reviewIterationsSource: reviewIter.source,
      riskMeter,
    },
    metrics: {
      sessionCount: spans.length,
      timeTakenMinutes: totalMinutes,
      timeTakenFormatted: fmtDuration(totalMinutes),
      tokensTotal: tokensIn + tokensOut + cacheRead,
      tokensInput: tokensIn,
      tokensOutput: tokensOut,
      tokensCacheRead: cacheRead,
      costTotal: costTotal.toFixed(2),
      humanPromptCount: spans.reduce((a, s) => a + s.humanMsgs, 0),
      reviewFeedbackCount: reviewRoundsByOthers,
    },
    daysSinceCreated: daysSince(notionCreatedTime, lastTs),
    // days since started = now minus the earliest first-timestamp across ALL ticket sessions
    daysSinceStarted: daysSinceNow(firstTs),
    content: {
      motivation: motivationFinal,
      dbSummary,
      backendSummary,
      frontendSummary,
      deploymentStatus,
      friction,
    },
    screenshots: ticketScreenshots,
    steps,
    sessions,
    sessionSources: spans.map((s) => s.file),
  };
}

/** Days from an ISO timestamp to now (used for "days since started"). */
function daysSinceNow(firstIso: string | null): number | string {
  if (!firstIso) return 'unknown';
  const f = new Date(firstIso).getTime();
  if (isNaN(f)) return 'unknown';
  return Math.floor((Date.now() - f) / 86400000);
}

/** Counts review-denial → fix-round events recorded in a KEY="value" state file. */
function deniedReviewEvents(text: string): number {
  const events = new Set<string>();
  for (const line of text.split('\n')) {
    const m = line.match(/^([A-Z_0-9]+)="?(.*?)"?$/);
    if (!m) continue;
    const [, k, v] = m;
    if (k === 'LOOP_DECISION' && /another-round/i.test(v)) events.add(`loop:${v.toLowerCase()}`);
    if (/REVIEW|LOOP|GATE|PARK|TICKET_STATUS|TICKET_STATUS_/i.test(k) && /denied|changes_requested|request_changes/i.test(v)) {
      events.add(`${k}=${v.slice(0, 60).toLowerCase()}`);
    }
  }
  return events.size;
}

/**
 * Review iterations = how many times the ticket went to Review Denied and back
 * into a fix round. Best data first: the worktree handoff, then the run env and
 * /tmp state files, then the PR's CHANGES_REQUESTED reviews (the Notion API
 * exposes no page history). Returns null (rendered as a dash) when absent.
 */
function resolveReviewIterations(
  worktree: string,
  ticketId: string,
  changesRequested: number,
): { count: number | null; source: string } {
  // 1. worktree handoff file
  let handoff = worktree ? path.join(worktree, '.workflow-handoff.env') : '';
  if (!handoff || !existsSync(handoff)) {
    const found = sh(`ls -d ${process.env.HOME ?? '$HOME'}/worktrees/*/*/${ticketId}*/.workflow-handoff.env 2>/dev/null`)
      .split('\n')
      .filter(Boolean)
      .sort()
      .pop();
    handoff = found ?? '';
  }
  if (handoff && existsSync(handoff)) {
    const txt = readFileSync(handoff, 'utf8');
    const rounds = txt.match(/^REVIEW_ROUNDS="?(\d+)/m)?.[1] ?? txt.match(/^FIX_ROUNDS="?(\d+)/m)?.[1];
    if (rounds !== undefined) {
      const n = Math.max(0, parseInt(rounds, 10) - 1);
      return { count: n, source: `worktree handoff REVIEW_ROUNDS=${rounds}` };
    }
    const n = deniedReviewEvents(txt);
    if (n > 0) return { count: n, source: 'worktree handoff denial records' };
  }

  // 2. run env + /tmp state files (the globbed extras are ticket-scoped so a
  //    concurrent run's state file can never supply another ticket's count)
  const ownEnv = process.env.WORKFLOW_RUN_ENV ?? '/tmp/workflow-run.env';
  const ownStatus = process.env.WORKFLOW_STATUS_FILE ?? '/tmp/workflow-run.status';
  const stateFiles = [
    ownEnv,
    ownStatus,
    ...(() => {
      try {
        return readdirSync('/tmp')
          .filter((f: string) => /^workflow-run.*\.(env|status|env\.bak\.\d+)$/.test(f))
          .map((f: string) => path.join('/tmp', f))
          .filter((f: string) => f === ownEnv || f === ownStatus || readFileSync(f, 'utf8').includes(ticketId));
      } catch {
        return [];
      }
    })(),
  ].filter((f) => f && existsSync(f));
  for (const f of stateFiles) {
    const n = deniedReviewEvents(readFileSync(f, 'utf8'));
    if (n > 0) return { count: n, source: `run env ${path.basename(f)}` };
  }

  // 3. PR review history
  if (changesRequested > 0) {
    return { count: changesRequested, source: 'GitHub PR reviews (CHANGES_REQUESTED)' };
  }
  return { count: null, source: 'no review-denied record available' };
}

function prSection(body: string, heading: string): string {
  const re = new RegExp(`### ${heading}\\n\\n([\\s\\S]*?)(?=\\n### |\\n## |$)`);
  const m = body.match(re);
  if (!m) return '';
  // condense: strip markdown tables to the first meaningful line
  const lines = m[1].split('\n').filter((l) => l.trim() && !l.startsWith('|'));
  return lines.join(' ').slice(0, 300);
}

function sessionStage(name: string): string | null {
  const base = name.replace(/-run-\d+$/, '');
  // Ticket labels are "<PREFIX>-<number>" with an uppercase prefix from ANY org —
  // never hardcode org prefixes here.
  const m = base.match(/^workflow-([a-z0-9-]+?)(?:-[A-Z][A-Z0-9]*(?:-[0-9]+)?[^ ]*)?$/);
  const stage = m ? m[1] : null;
  if (!stage) return null;
  // the orchestrator spans everything — never double-counted as a phase
  if (stage === 'orch') return null;
  return stage;
}

/** Resolve the GitHub account that authors this org's PRs — from org-config, org-neutral. */
function orgGithubAccount(): string {
  const org = process.env.WORKFLOW_ORG ?? process.env.ORG ?? loadRunEnv().ORG ?? '';
  try {
    const cfg = JSON.parse(
      readFileSync(path.join(process.env.HOME ?? '', 'secrets', 'org-config.json'), 'utf8'),
    ) as {
      bot?: { githubUsername?: string };
      orgs?: Array<{ org?: string; githubOrg?: string; poll?: { github?: { account?: string } } }>;
    };
    const match = (cfg.orgs ?? []).find((o) => o.org === org || o.githubOrg === org);
    return match?.poll?.github?.account ?? cfg.bot?.githubUsername ?? '';
  } catch {
    return '';
  }
}

/** Notion token from the workspace env file in $ORG_CONFIG_DIR/env (any workspace, org-neutral). */
function notionTokenFromSecretsEnv(): string | null {
  const dir = path.join(process.env.HOME ?? '', 'secrets', 'env');
  try {
    for (const f of readdirSync(dir)) {
      if (!/^notion.*\.env$/.test(f)) continue;
      const m = readFileSync(path.join(dir, f), 'utf8').match(/NOTION_[A-Z_]*ACCESS_TOKEN=(\S+)/);
      if (m) return m[1].replace(/["']/g, '');
    }
  } catch {
    /* not configured */
  }
  return null;
}

function loginIsOwner(login: string, ownerAccount: string | undefined): boolean {
  if (!ownerAccount) return false;
  const ownerLower = ownerAccount.toLowerCase();
  return login.toLowerCase() === ownerLower || login.toLowerCase().startsWith(ownerLower.slice(0, 7));
}

function daysSince(createdIso: string | null, completedIso: string | null): number | string {
  if (!createdIso || !completedIso) return 'unknown';
  const c = new Date(createdIso).getTime();
  const d = new Date(completedIso).getTime();
  if (isNaN(c) || isNaN(d)) return 'unknown';
  return Math.floor((d - c) / 86400000);
}

function prNumberFromUrl(url: string | undefined | null): number | null {
  if (!url) return null;
  const m = url.match(/\/pull\/(\d+)/);
  return m ? parseInt(m[1]) : null;
}

function parseScreenshots(spec: string): Screenshot[] {
  const out: Screenshot[] = [];
  if (!spec) return out;
  for (const line of spec.split('\n')) {
    if (!line.trim()) continue;
    const [p, u, c] = line.split('|');
    out.push({ path: p, url: u ?? '', caption: c ?? '' });
  }
  return out;
}

// ───────────────────────── 2. PROCESS ─────────────────────────

const TH = {
  font: "-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Oxygen,Ubuntu,'Fira Sans','Droid Sans','Helvetica Neue',sans-serif",
  dark: '#1a1a1a',
  heading: '#262626',
  dim: '#808080',
  border: '#e5e5e5',
  bodyBg: '#ffffff',
  tableBg: '#f0f0f0',
  link: '#2563eb',
};

function buildText(d: SummaryData): string {
  const lines = [
    `${d.ticket.id} — ${d.ticket.title}`,
    '',
    'This ticket has been completed and the PR merged.',
    '',
    `PR: ${d.pr.url}`,
    `Ticket: ${d.ticket.url}`,
    '',
    'Totals:',
    `Days since created: ${d.daysSinceCreated}`,
    `Days since started: ${d.daysSinceStarted}`,
    `Total time taken: ${d.metrics.timeTakenFormatted}`,
    `Review iterations: ${d.pr.reviewIterations == null ? '—' : d.pr.reviewIterations}`,
    '',
    'Why This Ticket:',
    d.content.motivation || 'N/A',
    '',
    'Risk:',
    d.pr.riskMeter || 'N/A',
    '',
    'Changes:',
    `- DB: ${d.content.dbSummary || 'none'}`,
    `- Backend: ${d.content.backendSummary || 'none'}`,
    `- Frontend: ${d.content.frontendSummary || 'none'}`,
    '',
    'Workflow Phases:',
    ...d.steps.map((s) => `${s.icon} ${s.id} ${s.name}: ${s.tokens} tok · ${s.time}`),
    '',
    `Sessions (${d.metrics.sessionCount}):`,
    `Session | Tokens | Human prompts | Cost | Time taken`,
    ...(d.sessions ?? []).map(
      (s) => `${s.name} | ${s.tokensFormatted} | ${s.humanMsgs} | ${s.costFormatted} | ${s.timeFormatted}`,
    ),
    `TOTAL (${d.metrics.sessionCount} sessions) | ${fmtInt(d.metrics.tokensTotal)} | ${d.metrics.humanPromptCount} | ${d.metrics.costTotal === '0.00' ? '—' : '$' + d.metrics.costTotal} | ${d.metrics.timeTakenFormatted}`,
    '',
    `Deployment: ${d.content.deploymentStatus || 'N/A'}`,
    `Friction: ${condenseFriction(d.content.friction).join('; ') || 'none'}`,
  ];
  return lines.join('\n');
}

/**
 * The friction section is a VERY high-level summary: one short bullet per item
 * (≈12 words), top 5 by impact plus a "N more recorded" line. Verbose stage
 * write-ups are condensed here so the email stays terse regardless of input.
 */
function condenseFriction(text: string): string[] {
  if (!text) return [];
  const out: string[] = [];
  const seen = new Set<string>();
  for (const raw of text.split(/\n+|(?<=[.;])\s+/)) {
    let s = raw
      .replace(/`[^`]*`/g, ' ')
      .replace(/\/\S*\/[\w./@-]*/g, ' ')
      .replace(/\b(?:in|at|from|to|of|into)?\s*[\w./-]+\.(?:json|env|md|ts|tsx|js|sh|yml|yaml|log|zip|png|txt|sql)\b/gi, ' ')
      .replace(/\[([^\]]*)\]\([^)]*\)/g, '$1')
      .replace(/\([^)]*\)/g, ' ')
      .replace(/^\s*(?:[-*•]+|\d+[.)])\s*/, '')
      .replace(/\s+/g, ' ')
      .replace(/\s+([,.;:!?])/g, '$1')
      .replace(/\s+(?:in|at|to|from|writing|of|for|with)\s*(?=[,;])/gi, '')
      .trim();
    s = s.replace(/\s*[\u2014\u2013-]{1,2}\s*,?\s*$/, '').trim();
    if (s.length < 8) continue;
    // continue-fragments from a split clause are detail, not a top-level point
    if (out.length > 0 && /^[a-z]/.test(s)) continue;
    const key = s.toLowerCase().slice(0, 40);
    if (seen.has(key)) continue;
    seen.add(key);
    const words = s.split(' ');
    if (words.length > 12) s = `${words.slice(0, 12).join(' ')}…`;
    out.push(s);
  }
  return out;
}

function buildHtml(d: SummaryData, images: { cid: string; file: string; caption: string }[]): string {
  const risk = d.pr.riskMeter
    ? `<div style="margin-bottom:20px;">
  <div style="margin-bottom:8px;font-size:14px;font-weight:600;color:${TH.heading};">Risk Assessment</div>
  <div style="padding:12px 16px;background:${TH.tableBg};border:1px solid ${TH.border};font-size:14px;">${esc(d.pr.riskMeter)}</div>
</div>`
    : '';

  // Agents table: one row per agent (icon + agent name); subtext = each phase
  // on its own line with its emoji; aggregated tokens/time/human.
  const agentRows = d.steps
    .map((s) => {
      const titleLine = `<span style="font-size:14px;font-weight:600;">${s.icon} ${esc(s.agent)}</span><span style="margin-left:8px;font-size:12px;color:${TH.dim};">${esc(s.name)}</span>`;
      const subLines = s.phases.map((p) => `<div style="font-size:11px;color:${TH.dim};">${p.icon} ${esc(p.id)} ${esc(p.name)}</div>`).join('');
      const sub = s.ran ? `<div style="margin-top:4px;">${subLines}</div>` : `<div style="margin-top:4px;font-size:11px;color:${TH.dim};">— not run in this run —</div>`;
      return `<tr>
  <td style="padding:10px 12px;border-bottom:1px solid ${TH.border};">${titleLine}${sub}</td>
  <td style="padding:10px 12px;border-bottom:1px solid ${TH.border};vertical-align:top;">${esc(s.tokens)}</td>
  <td style="padding:10px 12px;border-bottom:1px solid ${TH.border};vertical-align:top;">${esc(s.time)}</td>
  <td style="padding:10px 12px;border-bottom:1px solid ${TH.border};vertical-align:top;">${esc(s.human)}</td>
</tr>`;
    })
    .join('\n');
  const stepsHtml = `
  <div style="margin-bottom:20px;">
    <div style="margin-bottom:8px;font-size:14px;font-weight:600;color:${TH.heading};">Agents</div>
    <table style="width:100%;border-collapse:collapse;background:${TH.tableBg};border:1px solid ${TH.border};font-size:13px;">
      <thead><tr style="text-align:left;">
        <th style="padding:8px 12px;border-bottom:2px solid ${TH.border};color:${TH.dim};">Agent</th>
        <th style="padding:8px 12px;border-bottom:2px solid ${TH.border};color:${TH.dim};">Tokens</th>
        <th style="padding:12px;border-bottom:2px solid ${TH.border};color:${TH.dim};">Time</th>
        <th style="padding:12px;border-bottom:2px solid ${TH.border};color:${TH.dim};">Human</th>
      </tr></thead>
      <tbody>
${agentRows}
      </tbody>
    </table>
  </div>`;

  // Headline totals — days since created, days since started (now − earliest
  // first session timestamp), total time taken (SUM of per-session durations),
  // review iterations (Review Denied → fix round)
  const totals = `
  <div style="margin-bottom:20px;">
    <div style="margin-bottom:8px;font-size:14px;font-weight:600;color:${TH.heading};">Totals</div>
    <table style="width:100%;border-collapse:collapse;background:${TH.tableBg};border:1px solid ${TH.border};font-size:14px;">
      <thead><tr style="text-align:left;">
        <th style="padding:10px 12px;border-bottom:2px solid ${TH.border};color:${TH.dim};font-weight:500;">Days since created</th>
        <th style="padding:10px 12px;border-bottom:2px solid ${TH.border};color:${TH.dim};font-weight:500;">Days since started</th>
        <th style="padding:10px 12px;border-bottom:2px solid ${TH.border};color:${TH.dim};font-weight:500;">Total time taken</th>
        <th style="padding:10px 12px;border-bottom:2px solid ${TH.border};color:${TH.dim};font-weight:500;">Review iterations</th>
      </tr></thead>
      <tbody><tr>
        <td style="padding:10px 12px;font-size:16px;font-weight:600;">${esc(String(d.daysSinceCreated))}</td>
        <td style="padding:10px 12px;font-size:16px;font-weight:600;">${esc(String(d.daysSinceStarted))}</td>
        <td style="padding:10px 12px;font-size:16px;font-weight:600;">${esc(d.metrics.timeTakenFormatted)}</td>
        <td style="padding:10px 12px;font-size:16px;font-weight:600;">${d.pr.reviewIterations == null ? '—' : esc(String(d.pr.reviewIterations))}</td>
      </tr></tbody>
    </table>
  </div>`;

  // One row per session, sorted by start time; the TOTAL row is the sum of the
  // rows above (and equals the headline totals)
  const sessionRows = (d.sessions ?? [])
    .map((s) => `<tr>
  <td style="padding:8px 12px;border-bottom:1px solid ${TH.border};">${esc(s.name)}</td>
  <td style="padding:8px 12px;border-bottom:1px solid ${TH.border};text-align:right;">${esc(s.tokensFormatted)}</td>
  <td style="padding:8px 12px;border-bottom:1px solid ${TH.border};text-align:right;">${s.humanMsgs}</td>
  <td style="padding:8px 12px;border-bottom:1px solid ${TH.border};text-align:right;">${esc(s.costFormatted)}</td>
  <td style="padding:8px 12px;border-bottom:1px solid ${TH.border};text-align:right;">${esc(s.timeFormatted)}</td>
</tr>`)
    .join('\n');
  const sessionsHtml = `
  <div style="margin-bottom:20px;">
    <div style="margin-bottom:8px;font-size:14px;font-weight:600;color:${TH.heading};">Sessions (${d.metrics.sessionCount})</div>
    <table style="width:100%;border-collapse:collapse;background:${TH.tableBg};border:1px solid ${TH.border};font-size:13px;">
      <thead><tr style="text-align:left;">
        <th style="padding:8px 12px;border-bottom:2px solid ${TH.border};color:${TH.dim};font-weight:500;">Session</th>
        <th style="padding:8px 12px;border-bottom:2px solid ${TH.border};color:${TH.dim};font-weight:500;text-align:right;">Tokens</th>
        <th style="padding:8px 12px;border-bottom:2px solid ${TH.border};color:${TH.dim};font-weight:500;text-align:right;">Human prompts</th>
        <th style="padding:8px 12px;border-bottom:2px solid ${TH.border};color:${TH.dim};font-weight:500;text-align:right;">Cost</th>
        <th style="padding:8px 12px;border-bottom:2px solid ${TH.border};color:${TH.dim};font-weight:500;text-align:right;">Time taken</th>
      </tr></thead>
      <tbody>
${sessionRows}
        <tr>
          <td style="padding:10px 12px;font-weight:600;">Total (${d.metrics.sessionCount} sessions)</td>
          <td style="padding:10px 12px;font-weight:600;text-align:right;">${fmtInt(d.metrics.tokensTotal)}</td>
          <td style="padding:10px 12px;font-weight:600;text-align:right;">${d.metrics.humanPromptCount}</td>
          <td style="padding:10px 12px;font-weight:600;text-align:right;">${d.metrics.costTotal === '0.00' ? '—' : '$' + d.metrics.costTotal}</td>
          <td style="padding:10px 12px;font-weight:600;text-align:right;">${esc(d.metrics.timeTakenFormatted)}</td>
        </tr>
      </tbody>
    </table>
  </div>`;

  const shotsHtml = images.length
    ? images
        .map((im, i) => {
          const cap = d.screenshots[i]?.caption ?? '';
          const eu = d.screenshots[i]?.url ?? '';
          const last = i === images.length - 1 ? 'border-bottom:none;' : '';
          let card = `<div style="padding:16px;border-bottom:1px solid ${TH.border};${last}">`;
          if (cap) card += `<div style="margin-bottom:10px;font-size:14px;font-weight:600;color:${TH.heading};">${esc(cap)}</div>`;
          card += `<img src="cid:${im.cid}" alt="${esc(cap)}" style="max-width:100%;height:auto;display:block;" />`;
          if (eu) card += `<div style="margin-top:8px;font-size:12px;"><a href="${esc(eu)}" style="color:${TH.link};text-decoration:none;">View on GitHub →</a></div>`;
          card += '</div>';
          return card;
        })
        .join('')
    : `<div style="color:${TH.dim};font-size:14px;">No screenshots available.</div>`;
  const screenshots = `<div style="background:${TH.tableBg};border:1px solid ${TH.border};">${shotsHtml}</div>`;

  // Friction: a very high-level bullet list — one short line per item, top 5
  const frictionItems = condenseFriction(d.content.friction);
  const frictionShown = frictionItems.slice(0, 5);
  const frictionMore = frictionItems.length - frictionShown.length;
  const frictionHtml = frictionShown.length
    ? `<div style="margin-bottom:20px;">
      <div style="margin-bottom:8px;font-size:14px;font-weight:600;color:${TH.heading};">Friction / skill observations</div>
      <ul style="margin:0;padding:12px 16px 12px 32px;background:${TH.tableBg};border:1px solid ${TH.border};font-size:14px;">
        ${frictionShown.map((f) => `<li style="margin:0 0 4px;">${esc(f)}</li>`).join('\n        ')}
        ${frictionMore > 0 ? `<li style="margin:0;color:${TH.dim};">${frictionMore} more recorded</li>` : ''}
      </ul>
    </div>`
    : '';

  return `<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1.0"></head>
<body style="margin:0;padding:0;background:${TH.bodyBg};font-family:${TH.font};color:${TH.heading};line-height:1.5;">
<div style="width:700px;margin:24px auto;font-family:${TH.font};color:${TH.heading};line-height:1.5;">
  <div style="background:${TH.dark};padding:16px 0;">
    <div style="margin:0 auto;width:652px;color:#fff;font-size:13px;font-weight:600;letter-spacing:0.5px;text-transform:uppercase;">✅ Ticket Completed</div>
  </div>
  <div style="padding:24px;background:#f0f0f0;">
    <h2 style="font-size:24px;font-weight:600;margin:0 0 8px;">${esc(d.ticket.id)} — ${esc(d.ticket.title)}</h2>
    <p style="font-size:14px;font-weight:600;margin:0 0 24px;">This ticket has been completed and the PR merged. Summary below:</p>
    ${totals}
    <table style="width:100%;margin-bottom:24px;border-collapse:collapse;font-size:14px;">
      <tbody>
        <tr><td style="padding:10px 8px;border-bottom:1px solid ${TH.border};font-weight:500;color:${TH.dim};width:160px;">PR</td><td style="padding:10px 8px;border-bottom:1px solid ${TH.border};"><a href="${esc(d.pr.url)}" style="color:${TH.link};text-decoration:none;">${esc(d.pr.url)}</a></td></tr>
        <tr><td style="padding:10px 8px;color:${TH.dim};font-weight:500;">Ticket</td><td style="padding:10px 8px;"><a href="${esc(d.ticket.url)}" style="color:${TH.link};text-decoration:none;">${esc(d.ticket.url)}</a></td></tr>
      </tbody>
    </table>
    <div style="margin-bottom:20px;">
      <div style="margin-bottom:8px;font-size:14px;font-weight:600;color:${TH.heading};">Why This Ticket</div>
      <div style="padding:12px 16px;background:${TH.tableBg};border:1px solid ${TH.border};font-size:14px;">${esc(d.content.motivation || 'N/A')}</div>
    </div>
    ${risk}
    <div style="margin-bottom:20px;">
      <div style="margin-bottom:8px;font-size:14px;font-weight:600;color:${TH.heading};">Changes</div>
      <table style="width:100%;border-collapse:collapse;background:${TH.tableBg};border:1px solid ${TH.border};font-size:14px;">
        <tbody>
          <tr><td style="padding:10px 16px;font-weight:500;color:${TH.dim};width:160px;vertical-align:top;">Database</td><td style="padding:10px 16px;">${esc(d.content.dbSummary || 'none')}</td></tr>
          <tr><td style="padding:10px 16px;font-weight:500;color:${TH.dim};vertical-align:top;">Backend</td><td style="padding:10px 16px;">${esc(d.content.backendSummary || 'none')}</td></tr>
          <tr><td style="padding:10px 16px;color:${TH.dim};font-weight:500;vertical-align:top;">Frontend</td><td style="padding:10px 16px;">${esc(d.content.frontendSummary || 'none')}</td></tr>
        </tbody>
      </table>
    </div>
    ${sessionsHtml}
    ${stepsHtml}
    <div style="margin-bottom:20px;">
      <div style="margin-bottom:14px;font-size:14px;font-weight:600;color:${TH.heading};">Guided Tour Results</div>
      ${screenshots}
    </div>
    ${frictionHtml}
    <div style="margin-bottom:20px;">
      <div style="margin-bottom:8px;font-size:14px;font-weight:600;color:${TH.heading};">Deployment</div>
      <div style="padding:12px 16px;background:${TH.tableBg};border:1px solid ${TH.border};font-size:14px;">${esc(d.content.deploymentStatus || 'N/A')}</div>
    </div>
  </div>
</div>
</body></html>`;
}

// ───────────────────────── 3. SEND ─────────────────────────

function send(d: SummaryData, html: string, text: string, to: string, images: { cid: string; file: string; caption: string }[]): void {
  const boundary = `${Date.now()}_rel_${Math.random().toString(16).slice(2)}`;
  const alt = `${Date.now()}_alt_${Math.random().toString(16).slice(2)}`;
  const subject = `✅ ${d.ticket.id} — ${d.ticket.title}`;
  const parts: string[] = [];
  parts.push(`From: ${process.env.MSMTP_FROM ?? ''}`);
  parts.push(`To: ${to}`);
  parts.push(`Subject: ${subject}`);
  parts.push('MIME-Version: 1.0');
  parts.push(`Content-Type: multipart/related; boundary="${boundary}"; type="text/html"`);
  parts.push('');
  parts.push(`--${boundary}`);
  parts.push(`Content-Type: multipart/alternative; boundary="${alt}"`);
  parts.push('');
  parts.push(`--${alt}`);
  parts.push('Content-Type: text/plain; charset=utf-8');
  parts.push('Content-Transfer-Encoding: 8bit');
  parts.push('');
  parts.push(text);
  parts.push('');
  parts.push(`--${alt}`);
  parts.push('Content-Type: text/html; charset=utf-8');
  parts.push('Content-Transfer-Encoding: 8bit');
  parts.push('');
  parts.push(html);
  parts.push('');
  parts.push(`--${alt}--`);
  // inline screenshot images (base64 CID parts)
  for (const im of images) {
    parts.push(`--${boundary}`);
    parts.push('Content-Type: image/png');
    parts.push('Content-Transfer-Encoding: base64');
    parts.push(`Content-ID: <${im.cid}>`);
    parts.push(`Content-Disposition: inline; filename="${im.cid}.png"`);
    parts.push('');
    parts.push(readFileSync(im.file).toString('base64').replace(/(.{76})/g, '$1\n'));
    parts.push('');
  }
  parts.push(`--${boundary}--`);
  const p = spawnSync('msmtp', [to], { input: parts.join('\n'), encoding: 'utf8' });
  if (p.status !== 0) throw new Error(`msmtp failed: ${p.stderr}`);
}

// ───────────────────────── types ─────────────────────────

interface Screenshot {
  path: string;
  url: string;
  caption: string;
}

interface StepRow {
  id: string;
  icon: string;
  stage: string;
  name: string;
  ran: boolean;
  substeps: string;
  tokens: string;
  time: string;
  cost: string;
  human: string;
}

interface SessionRow {
  name: string;
  file: string;
  start: string;
  end: string;
  minutes: number;
  timeFormatted: string;
  tokens: number;
  tokensFormatted: string;
  cost: number;
  costFormatted: string;
  humanMsgs: number;
}

interface SummaryData {
  ticket: {
    id: string;
    title: string;
    url: string;
    notionCreatedTime: string | null;
    assignees: string[];
  };
  pr: {
    url: string;
    number: number | null;
    reviewRoundsByOthers: number;
    changesRequestedRounds: number;
    reviewIterations: number | null;
    reviewIterationsSource: string;
    riskMeter: string;
  };
  metrics: {
    sessionCount: number;
    timeTakenMinutes: number | null;
    timeTakenFormatted: string;
    tokensTotal: number;
    tokensInput: number;
    tokensOutput: number;
    tokensCacheRead: number;
    costTotal: string;
    humanPromptCount: number;
    reviewFeedbackCount: number;
  };
  daysSinceCreated: number | string;
  daysSinceStarted: number | string;
  content: {
    motivation: string;
    dbSummary: string;
    backendSummary: string;
    frontendSummary: string;
    deploymentStatus: string;
    friction: string;
  };
  screenshots: Screenshot[];
  steps: StepRow[];
  sessions: SessionRow[];
  sessionSources: string[];
}

// ───────────────────────── main ─────────────────────────


function main() {
  const args = process.argv.slice(2);
  const sendFlag = args.includes('--send');
  const fetchOnly = args.includes('--fetch-only');
  const jsonIdx = args.indexOf('--json');
  const jsonFile = jsonIdx >= 0 ? args[jsonIdx + 1] : undefined;
  const outIdx = args.indexOf('--out');
  const outFile = outIdx >= 0 ? args[outIdx + 1] : undefined;
  // --render <file>: render the HTML body to a file (verification path, never sends mail)
  const renderIdx = args.indexOf('--render');
  const renderFile = renderIdx >= 0 ? args[renderIdx + 1] : undefined;

  // env sources: notify.env (EMAIL_TO, MSMTP_FROM, NOTIFY_EMAIL)
  const notifyEnv = path.join(process.env.HOME ?? '', 'secrets', 'env', 'notify.env');
  if (existsSync(notifyEnv)) {
    for (const line of readFileSync(notifyEnv, 'utf8').split('\n')) {
      const m = line.match(/^(?:export )?([A-Z_0-9]+)=["']?(.+?)["']?$/);
      if (m) process.env[m[1]] = m[2];
    }
  }
  const runVars = loadRunEnv();
  const notionToken =
    process.env.NOTION_TOKEN ??
    notionTokenFromSecretsEnv() ??
    null;
  const notionPageId = process.env.NOTION_PAGE_ID ?? notionPageIdFromEnv(runVars);
  const ghToken = process.env.GH_TOKEN ?? sh('gh auth token 2>/dev/null');
  const repoSlug =
    process.env.REPO_SLUG ??
    [runVars.GITHUB_ORG, runVars.REPO_NAME].filter(Boolean).join('/') ??
    '';

  const data =
    jsonFile && (sendFlag || renderFile !== undefined)
      ? (JSON.parse(readFileSync(jsonFile, 'utf8')) as SummaryData)
      : fetch({
          repoRoot: runVars.SOURCE_REPO ?? process.cwd(),
          repoSlug,
          ghToken,
          notionToken,
          notionPageId,
          ticketId: process.env.TICKET_ID ?? runVars.TICKET_ID ?? 'Ticket',
        });

  if (fetchOnly) {
    const json = JSON.stringify(data, null, 2);
    if (outFile) {
      writeFileSync(outFile, json);
      console.log(`JSON written to ${outFile} — verify, then run with --send --json ${outFile}`);
    } else console.log(json);
    return;
  }

  if (renderFile) {
    const html = buildHtml(data, []);
    writeFileSync(renderFile, html);
    writeFileSync(`${renderFile}.txt`, buildText(data));
    console.log(`HTML body rendered to ${renderFile} (text: ${renderFile}.txt) — no email sent`);
    return;
  }

  const tmpDir = '/tmp/workflow-email-images';
  if (!existsSync(tmpDir)) mkdirSync(tmpDir, { recursive: true });
  const images = prepareInlineImages(data, tmpDir);
  const html = buildHtml(data, images);
  const to = process.env.EMAIL_TO ?? process.env.NOTIFY_EMAIL ?? '';
  send(data, html, buildText(data), to, images);
  rmSync(tmpDir, { recursive: true, force: true });
  console.log(`email sent to ${to}`);
}

function notionPageIdFromEnv(runVars: Record<string, string>): string | null {
  const url = runVars.TICKET_URL ?? '';
  const m = url.match(/([0-9a-f]{32})/);
  return m ? m[1] : null;
}

main();