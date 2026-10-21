#!/usr/bin/env node
// capture-beats.mjs — record a storyboard as 30 fps MP4 segments using the CDP
// screencast of the LIVE page.
//
// Why not `agent-browser record`: it re-creates the browser context, so the
// logged-in app session is gone and every app beat captures a redirect to
// /login. The screencast (`agent-browser stream`) reads the live page instead.
//
// Usage:
//   capture-beats.mjs --storyboard storyboard.json --out .workflow-video \
//     [--app http://localhost:5173] [--session NAME] [--profile DIR] \
//     [--viewport 1600x900] [--fps 30] [--only <beat-id>] \
//     [--login-email a@b.c] [--login-password pw] \
//     [--before-cmd 'git stash && ./deliver.sh before'] \
//     [--after-cmd  'git stash pop && ./deliver.sh after'] \
//     [--allow-no-diagrams]   (human-authorised exception only — see diagrams.md)
//
// Phase hooks: a beat's `phase` (before|after|any) selects a shell command that
// runs ONCE when capture reaches that phase — that is where the caller swaps the
// fix in/out and re-triggers the event under test.
//
// Gates (both exit 2, both before any browser work):
//   · motivation — beat 1 must be `kind: "motivation"` with quote / reportedSymptom /
//     affected / impact / narration, and the spoken line must use the ticket's words.
//   · diagrams   — concept/architecture before the first filmed beat, ERD before the
//     change it explains when `touchesDataModel` (`--allow-no-diagrams` on human say-so).
//
// Beats with `source: "image"` are rendered Mermaid diagrams, not captures: they are
// validated (the PNG must exist) and copied into timeline.json with `segment: null`.
// Before any browser work this script enforces TWO contracts:
//   1. the motivation contract (../steps/1-storyboard.md): the FIRST narrated beat is a
//      `kind: "motivation"` card stating the problem in the reporter's own words — what
//      is broken or missing, who is affected, what the impact is — taken from the ticket.
//   2. the diagram contract (../diagrams.md): a concept/architecture intro beat before the
//      first filmed beat, and an ERD before the first BEFORE beat when `touchesDataModel`.
// Both refuse the capture (exit 2) rather than let a video open on how before it says why.
import { execFileSync, spawn } from 'node:child_process'
import { existsSync, mkdirSync, readFileSync, writeFileSync, rmSync } from 'node:fs'
import { once } from 'node:events'
import { isAbsolute, join } from 'node:path'
import { homedir } from 'node:os'

// ─── args ───────────────────────────────────────────────────────────────────
const argv = process.argv.slice(2)
const arg = (name, dflt) => {
  const i = argv.indexOf(`--${name}`)
  return i >= 0 && argv[i + 1] && !argv[i + 1].startsWith('--') ? argv[i + 1] : dflt
}
const flag = (name) => argv.includes(`--${name}`)

const STORY = arg('storyboard', 'storyboard.json')
const OUT = arg('out', join(process.cwd(), '.workflow-video'))
const APP = arg('app', 'http://localhost:5173')
const SESSION = arg('session', process.env.CHROME_SESSION ?? 'tour')
const PROFILE = arg('profile', process.env.CHROME_SESSION_PROFILE ?? '')
const VIEWPORT = arg('viewport', '1600x900')
const LOGIN_EMAIL = arg('login-email', process.env.LOGIN_EMAIL ?? '')
const LOGIN_PASSWORD = arg('login-password', process.env.LOGIN_PASSWORD ?? '')
const ONLY = arg('only', '')
const HOOKS = { before: arg('before-cmd', ''), after: arg('after-cmd', '') }
const [VW, VH] = VIEWPORT.split('x').map(Number)

const story = JSON.parse(readFileSync(STORY, 'utf8'))
const FPS = Number(arg('fps', String(story.fps ?? 30)))
const FRAME_MS = Math.round(1000 / FPS)
const SEG = join(OUT, 'seg')

// ─── diagram contract ───────────────────────────────────────────────────────
// Mandatory in every tour (see ../diagrams.md). A diagram is the only thing that
// tells a viewer what the system is and what data the change touches before they
// watch the change itself, so a storyboard without one is refused here rather than
// discovered at review time. `--allow-no-diagrams` is for a human-authorised
// exception only, and the PR body must say so.
const diagramProblems = () => {
  const beats = story.beats
  const isImg = (b) => !!b && (b.source === 'image' || b.kind === 'diagram')
  const filmed = (b) => !!b && (b.source === 'app' || b.source === 'web')
  const firstFilmed = beats.findIndex(filmed)
  const firstPolar = beats.findIndex((b) => filmed(b) && (b.phase === 'before' || b.phase === 'after'))
  const introIdx = beats.findIndex((b) => isImg(b) && (b.diagram === 'concept' || b.diagram === 'architecture'))
  const erdIdx = beats.findIndex((b) => isImg(b) && b.diagram === 'erd')
  const problems = []

  const diagrams = beats.filter(isImg)
  if (!diagrams.length) problems.push('no diagram beat at all (`source: "image"`, `diagram: "concept"|"architecture"|"erd"`)')
  for (const b of diagrams) {
    if (!['concept', 'architecture', 'erd'].includes(b.diagram)) {
      problems.push(`${b.id}: \`diagram\` must be concept | architecture | erd`)
    }
    if (!b.mmd) problems.push(`${b.id}: no \`mmd\` source path — the .mmd is the reviewable artefact`)
    else if (!existsSync(isAbsolute(b.mmd) ? b.mmd : join(OUT, b.mmd))) problems.push(`${b.id}: source ${b.mmd} is missing — write the .mmd (see diagrams.md)`)
    if (!b.image) problems.push(`${b.id}: no \`image\` path for the render`)
    else if (!existsSync(isAbsolute(b.image) ? b.image : join(OUT, b.image))) problems.push(`${b.id}: ${b.image} is not rendered — run scripts/render-diagrams.mjs`)
  }
  if (diagrams.length && introIdx === -1) problems.push('no `concept` or `architecture` intro diagram (one is always required)')
  if (introIdx >= 0 && firstFilmed >= 0 && introIdx > firstFilmed) {
    problems.push(`the intro diagram (${beats[introIdx].id}) comes after the first filmed beat (${beats[firstFilmed].id}) — it is the introduction, put it first`)
  }
  if (story.touchesDataModel === true && erdIdx === -1) {
    problems.push('`touchesDataModel` is true but there is no `erd` beat — the ERD must show the tables the change reads or writes')
  }
  // Placement: an ERD belongs before the change it explains. In a single-PR tour that is
  // before the first BEFORE/AFTER beat; in a chaptered release video (beats carry
  // `chapter`) it is before the first filmed beat of its OWN chapter, right after the
  // divider.
  for (const [i, b] of beats.entries()) {
    if (!isImg(b) || b.diagram !== 'erd') continue
    const limit = b.chapter != null
      ? beats.findIndex((o) => filmed(o) && o.chapter === b.chapter)
      : firstPolar
    if (limit >= 0 && i > limit) {
      problems.push(`the ERD (${b.id}) comes after ${beats[limit].id} — order is intro → motivation → concept/architecture → ERD → BEFORE → AFTER → guard → close${b.chapter != null ? ` (within chapter ${b.chapter})` : ''}`)
    }
  }
  return problems
}
// The diagram contract is checked after the motivation contract (which governs beat 1),
// so a storyboard that is wrong in both places reports the opening beat first.
const enforceDiagramContract = () => {
  const DIAGRAM_PROBLEMS = diagramProblems()
  if (!DIAGRAM_PROBLEMS.length) return
  if (flag('allow-no-diagrams')) {
    console.warn('\n! diagram contract waived with --allow-no-diagrams (human-authorised only):')
    for (const p of DIAGRAM_PROBLEMS) console.warn(`  · ${p}`)
    return
  }
  console.error(`\nREFUSING to capture ${STORY} — the diagram contract is not met:\n${DIAGRAM_PROBLEMS.map((p) => `  · ${p}`).join('\n')}

Every tour opens with a concept/architecture diagram and, when it touches the data
model, an ERD showing the tables the change reads or writes. See
~/.agents/skills/workflow-video-tour/diagrams.md, add the beats, render them with
scripts/render-diagrams.mjs, then re-run. (--allow-no-diagrams only on human say-so.)`)
  process.exit(2)
}

// ─── motivation contract ────────────────────────────────────────────────────
// THE VIDEO OPENS ON THE PROBLEM, IN THE REPORTER'S WORDS (user directive 2026-10-19).
// A tour that starts on an architecture diagram — "here is the shape of it" — explains
// HOW before the viewer knows WHY, so the first twenty seconds are spent on a system
// nobody has a reason to care about yet, in engineering language that the person who
// reported the bug would not recognise. Every video therefore opens with a
// `kind: "motivation"` card BEFORE the concept/architecture diagram, and its line comes
// from the ticket: the symptom as reported, who is affected, and the impact.
//
// The gate is deliberately not waivable. A missing, misordered, empty or generic
// motivation is exactly the failure it exists to catch, so there is no
// `--allow-*` escape hatch: fix the storyboard from the ticket instead.
const STOPWORDS = new Set((
  'a an and are as at be been but by can could did do does for from had has have how i if in into is it its ' +
  'just me my no not of on or our so some than that the their them then there these they this to too us was we ' +
  'were what when where which while who why will with would you your also after before about all any because ' +
  'been being both each more most other over same should still such through under until up very'
).split(' '))
const normText = (s) => String(s ?? '').toLowerCase().replace(/[\u2019']/g, '').replace(/[^a-z0-9]+/g, ' ').trim()
const allWords = (s) => normText(s).split(' ').filter(Boolean)
const contentWords = (s) => allWords(s).filter((w) => w.length >= 3 && !STOPWORDS.has(w))
const uniq = (a) => [...new Set(a)]
// A line built out of these says nothing a reviewer could not have guessed from the PR
// title. Matched against the WHOLE narration; one hit is a failure.
const GENERIC_LINE = [
  /\b(seamless|robust|powerful|leverage|enhance|various|miscellaneous|general improvement|minor (fix|update|tweak))\b/i,
  /\b(this (pr|ticket|change)|the (ticket|issue|pr))\b[^.]*\b(fixes|improves|adds|updates|refactors|implements|addresses)\b/i,
  /^(fix(es|ed)?|improve(s|d)?|update(s|d)?|refactor(s|ed)?|implement(s|ed)?|support(s|ed)?|add(s|ed)?)\b[^.]{0,40}\.?$/i,
]
// The three things the opening beat must say, in the ticket's vocabulary. `quote` is the
// reporter's own words (shown on the card); `reportedSymptom`, `affected` and `impact` are
// the extraction the gate checks the spoken line against. All are required fields.
const MOTIVATION_FIELDS = ['quote', 'reportedSymptom', 'affected', 'impact', 'narration']
const MOTIVATION_MIN_NARRATION_WORDS = 12
const MOTIVATION_MIN_QUOTE_WORDS = 6

const motivationProblems = () => {
  const beats = Array.isArray(story.beats) ? story.beats : []
  const isMot = (b) => !!b && b.kind === 'motivation'
  const isDiagramBeat = (b) => !!b && (b.source === 'image' || b.kind === 'diagram')
  const problems = []
  const idx = beats.findIndex(isMot)

  if (idx === -1) {
    problems.push('no `kind: "motivation"` beat — every video opens on the problem, in the reporter\'s words, before any technical detail')
    return problems
  }
  const m = beats[idx]
  if (idx > 0) {
    const before = beats.slice(0, idx)
    const tech = before.find((b) => isDiagramBeat(b) || b.source === 'app' || b.source === 'web' || b.source === 'static' || !!b.heading || !!b.bullets)
    const offender = tech ? `the technical beat \`${tech.id}\`` : `\`${beats[0].id}\``
    problems.push(
      `the motivation beat (${m.id}) is beat #${idx + 1}, not the first narrated beat — it comes after ${offender}.` +
      ' Order is fixed: intro card → MOTIVATION → concept/architecture → ERD → BEFORE → AFTER → guard → close.',
    )
  }
  for (const f of MOTIVATION_FIELDS) {
    if (!String(m[f] ?? '').trim()) {
      problems.push(`${m.id}: \`${f}\` is required on a motivation beat — ${MOTIVATION_FIELD_HELP[f]}`)
    }
  }
  const spoken = allWords(m.narration)
  if (spoken.length && spoken.length < MOTIVATION_MIN_NARRATION_WORDS) {
    problems.push(`${m.id}: the motivation line is ${spoken.length} words — needs ≥ ${MOTIVATION_MIN_NARRATION_WORDS} so it can say what is broken, who is affected and what it costs`)
  }
  const quoted = allWords(m.quote)
  if (quoted.length && quoted.length < MOTIVATION_MIN_QUOTE_WORDS) {
    problems.push(`${m.id}: \`quote\` is ${quoted.length} word(s) — paste the reporter's sentence from the ticket (≥ ${MOTIVATION_MIN_QUOTE_WORDS} words), do not summarise it`)
  }
  if (String(m.narration ?? '').trim()) {
    for (const re of GENERIC_LINE) {
      if (re.test(String(m.narration))) {
        problems.push(`${m.id}: the motivation line is generic (\`${re.source}\`) — restate the reported symptom in the reporter's words, not a PR-title summary`)
        break
      }
    }
  }
  const spokenSet = new Set(contentWords(m.narration))
  // The reported symptom must actually be named, not implied.
  const symptom = uniq(contentWords(m.reportedSymptom))
  if (symptom.length) {
    const hit = symptom.filter((w) => spokenSet.has(w)).length
    if (hit / symptom.length < 0.8) {
      problems.push(`${m.id}: the motivation does not mention the reported symptom "${m.reportedSymptom}" — say what is broken in the words the reporter used (matched ${hit}/${symptom.length} of its content words)`)
    }
  }
  // Who is affected and what the impact is: at least one content word of each must be spoken.
  for (const [field, label] of [['affected', 'who is affected'], ['impact', 'what the impact is']]) {
    const want = uniq(contentWords(m[field]))
    if (want.length && !want.some((w) => spokenSet.has(w))) {
      problems.push(`${m.id}: the motivation does not say ${label} (\`${field}: "${m[field]}"\`) — name it in the spoken line`)
    }
  }
  // Taken from the ticket, not paraphrased into engineering language: the spoken line has
  // to reuse at least two of the ticket's own content words.
  const ticketVocab = new Set(uniq([
    ...contentWords(m.quote), ...contentWords(m.reportedSymptom),
    ...contentWords(m.affected), ...contentWords(m.impact),
  ]))
  const reused = uniq(contentWords(m.narration)).filter((w) => ticketVocab.has(w))
  if (ticketVocab.size && reused.length < 2) {
    problems.push(`${m.id}: the motivation line is not in the reporter's words — only ${reused.length} word(s) come from the ticket quote/symptom/affected/impact; quote the reporter (\`quote\`) instead of paraphrasing into engineering language`)
  }
  return problems
}
const MOTIVATION_FIELD_HELP = {
  quote: 'the reporter/user sentence copied from the ticket, verbatim (what is broken or missing)',
  reportedSymptom: 'the symptom phrase as reported, e.g. "payments silently fail"',
  affected: 'who is affected, per the ticket, e.g. "the finance team"',
  impact: 'what the impact is, per the ticket, e.g. "invoices go unpaid for days"',
  narration: 'the 12–28 word spoken line that opens the video',
}
const MOTIVATION_PROBLEMS = motivationProblems()
if (MOTIVATION_PROBLEMS.length) {
  console.error(`\nREFUSING to capture ${STORY} — the motivation contract is not met:
${MOTIVATION_PROBLEMS.map((p) => `  · ${p}`).join('\n')}

Every video opens with a \`kind: "motivation"\` card as the FIRST narrated beat (the intro
card is generated, not a beat). It states, in the reporter's own words from the ticket, what
is broken or missing, who is affected and what the impact is. Only then come the
concept/architecture diagram, the ERD, BEFORE, AFTER, guard and close.
See ~/.agents/skills/workflow-video-tour/steps/1-storyboard.md ("The motivation beat").
This gate has no waiver: take the wording from the ticket.`)
  process.exit(2)
}

// Beat 1 is checked first (motivation), then the technical opening (diagrams).
enforceDiagramContract()

// ─── helpers ────────────────────────────────────────────────────────────────
// The caps are daemon-wide and read once at startup: without them the screencast
// silently falls back to the window size and the frames are the wrong shape.
const AB_ENV = {
  ...process.env,
  AGENT_BROWSER_STREAM_MAX_WIDTH: String(VW),
  AGENT_BROWSER_STREAM_MAX_HEIGHT: String(VH),
  AGENT_BROWSER_STREAM_QUALITY: process.env.AGENT_BROWSER_STREAM_QUALITY ?? '80',
}
// Attach mode: when CHROME_CDP_URL is set, drive the ALREADY-RUNNING run Chrome over CDP.
// Passing --profile on this path would make the CLI launch its own browser (the silent
// "exited early without DevToolsActivePort" failure) and could kill the run's Chrome, so
// --profile is deliberately omitted in CDP mode. Cage runs should always export
// CHROME_CDP_URL (e.g. http://127.0.0.1:9222) — see SHARED-POLICY.
const abArgs = ['--session', SESSION]
const CDP = process.env.CHROME_CDP_URL
if (CDP) abArgs.push('--cdp', CDP)
if (flag('headed') || !PROFILE) abArgs.push('--headed')
if (PROFILE && !CDP) abArgs.push('--profile', PROFILE)
const ab = (...args) =>
  execFileSync('agent-browser', [...abArgs, ...args], {
    encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], timeout: 180000, env: AB_ENV,
  }).trim()
// A page can reach `interactive` and still never fire `load` (a third-party iframe that
// never settles), which makes `open` itself throw. Readiness for a beat is gated by
// `readyText` — the data on screen, not the load event — so a navigation timeout is a
// warning here, not a stop. (a staging environment once: the authenticated SPA sat at
// readyState=interactive for minutes with every request complete.)
const openSoft = (url) => {
  try { ab('open', url) } catch (e) { console.log(`  ! open ${url} did not settle (${String(e.message).split('\n')[0]}) — continuing; readyText gates the beat`) }
}
const sh = (cmd) => execFileSync('bash', ['-lc', cmd], { encoding: 'utf8' }).trim()
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
const safeWait = () => { try { ab('wait', '--load', 'networkidle') } catch {} }
const path_ = () => JSON.parse(ab('eval', 'location.pathname'))
const origin_ = () => JSON.parse(ab('eval', 'location.origin'))
const pageText = () => JSON.parse(ab('eval', 'document.body.innerText.slice(0,200000)'))
// The screencast frames come from the PAGE, so a window smaller than the storyboard
// viewport silently produces a smaller video (2026-10-19: 948x947 frames for a 1600x900
// cut). `set viewport` is not a safe fix here — it wedges the daemon in this
// agent-browser build — so warn with the real remedy and let the caller decide.
const pageViewport = () => {
  try {
    const [w, h] = JSON.parse(ab('eval', 'JSON.stringify([innerWidth, innerHeight])'))
    return w > 0 && h > 0 ? { w, h } : null
  } catch { return null }
}
const warnSmallViewport = (vp) => {
  if (!vp || (vp.w >= VW && vp.h >= VH)) return
  console.warn(`\n! the page viewport is ${vp.w}x${vp.h}, smaller than the storyboard's ${VW}x${VH}.\n  Frames are captured at the page size, so the video will be ${vp.w}x${vp.h}. Fix the WINDOW,\n  not the storyboard: bash ~/.agents/skills/workflow-do/scripts/chrome.sh viewport\n  then widen the niri column (or run .../workflow-do/scripts/place-chrome.sh) and re-run.`)
}

const waitForText = async (text, timeoutMs = 45000) => {
  const t0 = Date.now()
  for (;;) {
    if (pageText().includes(text)) return true
    if (Date.now() - t0 > timeoutMs) throw new Error(`"${text}" never appeared on the page`)
    await sleep(1200)
  }
}

const ensureLogin = async () => {
  if (!LOGIN_EMAIL) return
  if (path_() !== '/login' && !pageText().includes('Welcome Back')) return
  console.log('  · signing in')
  ab('type', 'input[type=email]', LOGIN_EMAIL)
  ab('type', 'input[type=password]', LOGIN_PASSWORD)
  ab('press', 'Enter')
  safeWait()
  await sleep(9000)
  if (path_() === '/login') throw new Error('sign-in did not take (check LOGIN_EMAIL/PASSWORD)')
  console.log('  · session ok')
}

// ─── in-page demo layer: fake cursor + click ripple ─────────────────────────
// SINGLE SOURCE OF TRUTH (2026-10-01): the layer comes from
// ~/.agents/skills/workflow-do/scripts/annotate.js (ids `demo-cursor`/`demo-ripple`, palette
// before #EF4444 / after #22C55E / accent #38BDF8). Screenshots annotate through the same
// __wfAnnot object, so a screenshot and its video beat look identical. Boxes/arrows/labels
// are available to the video path too: call __wfAnnot.box/arrow/banner next to cursorTo().
// Loads the shared in-page annotation layer (same file the tour uses for screenshots).
// Falls back to a no-op if the skill moved, so the capture never dies on a missing helper.
const ANNOTATE_JS = join(homedir(), '.agents/skills/workflow-do/scripts/annotate.js')
const injectLayer = () => {
  try {
    const src = readFileSync(ANNOTATE_JS, 'utf8')
    const out = ab('eval', `(() => { ${src} ; return 'loaded'; })()`)
    return out
  } catch (err) {
    console.log(`  ! annotation layer unavailable (${err.message.split('\n')[0]}) — beats will record unannotated`)
    return 'missing'
  }
}

const cursorTo = async (x, y, settle = 700) => {
  ab('eval', `(() => { if (window.__wfAnnot) return __wfAnnot.cursor(${Math.round(x)}, ${Math.round(y)}); const c = document.getElementById('demo-cursor'); if (c) c.style.transform = 'translate(${Math.round(x)}px, ${Math.round(y)}px)'; return 'ok'; })()`)
  await sleep(settle)
}
const rippleAt = (x, y) => ab('eval', `(() => {
  if (window.__wfAnnot) return __wfAnnot.click(${Math.round(x)}, ${Math.round(y)});
  const d = document.createElement('div'); d.className = 'demo-ripple';
  d.style.left = '${Math.round(x)}px'; d.style.top = '${Math.round(y)}px';
  document.body.appendChild(d); setTimeout(() => d.remove(), 900); return 'ok';
})()`)

const elementCentre = (finder) => {
  const out = ab('eval', `(() => { const el = ${finder}; if (!el) return 'none'; const r = el.getBoundingClientRect(); return JSON.stringify({ x: Math.round(r.x + r.width / 2), y: Math.round(r.y + r.height / 2) }); })()`)
  if (out === 'none' || out === '"none"') return null
  try { const u = JSON.parse(out); return typeof u === 'string' ? JSON.parse(u) : u } catch { return null }
}
const clickWithCursor = async (finder) => {
  const c = elementCentre(finder)
  if (!c) return false
  await cursorTo(c.x, c.y)
  rippleAt(c.x, c.y)
  ab('eval', `(() => { const el = ${finder}; if (el) el.click(); return 'clicked'; })()`)
  await sleep(1000)
  return true
}

const smoothScrollToText = async (text) => {
  ab('eval', `(() => {
    const want = ${JSON.stringify(text)};
    const all = [...document.querySelectorAll('body *')].filter(el => {
      const r = el.getBoundingClientRect();
      return r.width > 6 && r.height > 6 && (el.innerText || el.textContent || '').includes(want);
    });
    const deepest = all.filter(el => !all.some(o => o !== el && el.contains(o)));
    if (!deepest.length) return 'not found';
    deepest.sort((a, b) => { const ra = a.getBoundingClientRect(), rb = b.getBoundingClientRect(); return ra.width * ra.height - rb.width * rb.height; });
    deepest[0].scrollIntoView({ behavior: 'smooth', block: 'center' });
    return 'scrolled';
  })()`)
  await sleep(1200)
}

// ─── annotation box, chosen by intent ───────────────────────────────────────
const boxRect = (spec) => {
  const out = ab('eval', `(() => {
    const spec = ${JSON.stringify(spec)};
    let el = null;
    if (spec.mode === 'selector') {
      el = document.querySelector(spec.selector);
    } else {
      const all = [...document.querySelectorAll('body *')].filter(e => {
        const r = e.getBoundingClientRect();
        if (r.width < 6 || r.height < 6) return false;
        return (e.innerText || e.textContent || '').includes(spec.text);
      });
      const deepest = all.filter(e => !all.some(o => o !== e && e.contains(o)));
      if (!deepest.length) return null;
      deepest.sort((a, b) => { const ra = a.getBoundingClientRect(), rb = b.getBoundingClientRect(); return ra.width * ra.height - rb.width * rb.height; });
      el = deepest[0];
      if (spec.mode === 'row') {
        el = el.closest('tr, [role=row]') || el;
      } else if (spec.mode === 'wide') {
        const minW = spec.minWidth || 400, minH = spec.minHeight || 0;
        let cur = el;
        while (cur && cur.parentElement) {
          const r = cur.getBoundingClientRect();
          if (r.width >= minW && r.height >= minH) break;
          cur = cur.parentElement;
        }
        el = cur || el;
      }
    }
    if (!el) return null;
    const r = el.getBoundingClientRect();
    return JSON.stringify({ x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.width), h: Math.round(r.height) });
  })()`)
  try { const u = JSON.parse(out); return typeof u === 'string' ? JSON.parse(u) : u } catch { return null }
}

// ─── screencast + encoder ───────────────────────────────────────────────────
let latestFrame = null
let frameW = 0
let frameH = 0
const openStream = () => {
  let port = JSON.parse(ab('stream', 'status', '--json')).data.port
  if (!port) { try { ab('stream', 'enable') } catch {}; port = JSON.parse(ab('stream', 'status', '--json')).data.port }
  const ws = new WebSocket(`ws://127.0.0.1:${port}`)
  ws.addEventListener('message', (ev) => {
    try {
      const m = JSON.parse(ev.data)
      if (m.type === 'frame' && m.data) {
        latestFrame = m.data
        if (m.metadata) { frameW = m.metadata.deviceWidth; frameH = m.metadata.deviceHeight }
      }
    } catch {}
  })
  return new Promise((res) => ws.addEventListener('open', res))
}

const startEncoder = (file) =>
  spawn('ffmpeg', ['-y', '-f', 'image2pipe', '-framerate', String(FPS), '-i', '-',
    // libx264 + yuv420p need EVEN dimensions, so an odd-width capture (375px, i.e.
    // mobile viewports) fails with "width not divisible by 2" — and the pump then
    // waits forever on a stdin 'drain' that never comes (<KEY>, 2026-10-07).
    // Round both dimensions down to an even number.
    '-vf', 'scale=trunc(iw/2)*2:trunc(ih/2)*2',
    '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '18', '-pix_fmt', 'yuv420p', '-r', String(FPS), file],
    { stdio: ['pipe', 'ignore', 'pipe'] })

const timeline = []

const prepare = async (beat) => {
  if (beat.source === 'app') {
    if (path_() !== '/login' && pageText().includes('Welcome Back')) await ensureLogin()
    if (origin_() !== APP) {
      openSoft(`${APP}${beat.route}`); safeWait(); await sleep(3500)
      await ensureLogin()
      if (path_() !== beat.route) { openSoft(`${APP}${beat.route}`); await sleep(3500) }
    } else if (beat.route.includes('#')) {
      // Hash-routed SPA (dashboard-style `#/tab` routes): navigation happens on
      // `hashchange`, which a pushState does NOT fire, so driving the hash directly
      // is the only way to move the app. When the target is already active the hash
      // is toggled away and back, which remounts the view and re-runs its data fetch
      // (a same-hash assignment fires nothing and would film stale rows).
      const hash = beat.route.slice(beat.route.indexOf('#'))
      const current = JSON.parse(ab('eval', 'location.hash'))
      if (current !== hash) {
        ab('eval', `location.hash = ${JSON.stringify(hash)}`)
        await sleep(2600)
      } else {
        ab('eval', "location.hash = '#/'")
        await sleep(1600)
        ab('eval', `location.hash = ${JSON.stringify(hash)}`)
        await sleep(2600)
      }
    } else if (path_() !== beat.route) {
      ab('pushstate', `${APP}${beat.route}`)
      await sleep(2600)
    } else {
      // force a data refetch without reloading the app shell
      ab('pushstate', `${APP}${beat.route === '/dashboard' ? '/invoices' : '/dashboard'}`)
      await sleep(1300)
      ab('pushstate', `${APP}${beat.route}`)
      await sleep(2600)
    }
    await waitForText(beat.readyText)
  } else if (beat.source === 'web') {
    openSoft(beat.url)
    safeWait()
    await sleep(2200)
    if (beat.readyText) await waitForText(beat.readyText)
  }
}

const runBeat = async (beat) => {
  console.log(`\n▸ ${beat.id} (${beat.source}${beat.phase ? ` · ${beat.phase}` : ''})`)
  await prepare(beat)
  injectLayer()
  await sleep(300)

  const file = join(SEG, `${beat.id}.mp4`)
  const ff = startEncoder(file)
  // Resolve-once exit promise: racing against it stops the pump hanging when the
  // encoder dies early (e.g. an ffmpeg argument error) — a plain once(ff,'exit')
  // added after the event already fired would never resolve.
  const encoderExit = new Promise((res) => ff.once('exit', res))
  let encoderDead = false
  ff.once('exit', () => { encoderDead = true })
  let pushed = 0
  let pumping = true
  const pump = (async () => {
    while (pumping) {
      if (encoderDead) { pumping = false; break }
      if (latestFrame) {
        const ok = ff.stdin.write(Buffer.from(latestFrame, 'base64'))
        pushed++
        if (!ok) await Promise.race([once(ff.stdin, 'drain'), encoderExit])
      }
      await sleep(FRAME_MS)
    }
    return pushed
  })()

  const started = Date.now()
  if (beat.click) {
    if (beat.box?.text) await smoothScrollToText(beat.box.text)
    if (!(await clickWithCursor(beat.click.finder))) console.log('  ! click target not found')
    await sleep(1200)
    if (beat.click2) {
      if (!(await clickWithCursor(beat.click2.finder))) console.log('  ! second click target not found')
      await sleep(1400)
    }
    if (beat.box?.text) await smoothScrollToText(beat.box.text)
  } else if (beat.box) {
    if (beat.box.text) await smoothScrollToText(beat.box.text)
    else if (beat.box.selector) {
      ab('eval', `(() => { const el = document.querySelector(${JSON.stringify(beat.box.selector)}); if (el) el.scrollIntoView({ behavior: 'smooth', block: 'center' }); return 'ok'; })()`)
      await sleep(1200)
    }
    if (beat.box.text) {
      const c = elementCentre(`(() => { const want = ${JSON.stringify(beat.box.text)}; const all = [...document.querySelectorAll('body *')].filter(e => { const r = e.getBoundingClientRect(); return r.width > 6 && r.height > 6 && (e.innerText || '').includes(want); }); const deepest = all.filter(e => !all.some(o => o !== e && e.contains(o))); if (!deepest.length) return null; deepest.sort((a, b) => { const ra = a.getBoundingClientRect(), rb = b.getBoundingClientRect(); return ra.width * ra.height - rb.width * rb.height; }); return deepest[0]; })()`)
      if (c) await cursorTo(c.x, c.y)
    }
  }

  const hold = beat.holdMs ?? 14000
  const elapsed = Date.now() - started
  if (elapsed < hold) await sleep(hold - elapsed)
  const rect = beat.box ? boxRect(beat.box) : null

  pumping = false
  await pump
  try { ff.stdin.end() } catch {}
  const code = await encoderExit
  if (code !== 0) throw new Error(`ffmpeg failed for ${beat.id} (exit ${code})`)

  const durationMs = Date.now() - started
  timeline.push({ ...beat, segment: file, durationMs, rect, fps: FPS, framesPushed: pushed, frameW, frameH, viewportW: VW, viewportH: VH })
  console.log(`  ${(durationMs / 1000).toFixed(1)}s · ${pushed} frames · rect=${rect ? `${rect.w}x${rect.h}@${rect.x},${rect.y}` : 'NONE — fix box/readyText and re-record with --only'}`)
}

// ─── drive ──────────────────────────────────────────────────────────────────
mkdirSync(SEG, { recursive: true })
const timelinePath = join(OUT, 'timeline.json')

// A still beat (a summary card, or a Mermaid diagram rendered to PNG) has no segment:
// compose draws it from the card fields or the image itself. Validate the render now —
// a missing PNG found at compose time means a wasted assembly run.
const isStill = (b) => b.source === 'static' || b.source === 'image'
const stillEntry = (beat) => {
  if (beat.source === 'image') {
    const img = isAbsolute(beat.image) ? beat.image : join(OUT, beat.image)
    if (!beat.image) throw new Error(`${beat.id}: source "image" needs an \`image\` path (see diagrams.md)`)
    if (!existsSync(img)) throw new Error(`${beat.id}: ${img} is missing — run scripts/render-diagrams.mjs first`)
    return { ...beat, segment: null, image: img, durationMs: 0, rect: null, fps: FPS }
  }
  return { ...beat, segment: null, durationMs: 0, rect: null, fps: FPS }
}

// Merge entries into timeline.json, sorted by the storyboard but keeping the position of
// any beat the storyboard does not know. `story.beats` can legitimately be a SUBSET of the
// timeline (the release-video skill captures the phone-viewport beats in a second run with
// its own storyboard), and indexOf() would hand those beats -1 and park every one of them
// at the front of the video. Unknown ids keep the slot they already had.
const mergeEntries = (entries) => {
  let prior = []
  if (existsSync(timelinePath)) {
    prior = JSON.parse(readFileSync(timelinePath, 'utf8')).filter((b) => !entries.some((e) => e.id === b.id))
  }
  const order = story.beats.map((b) => b.id)
  const pos = new Map(order.map((id, i) => [id, i]))
  const priorIndex = new Map(prior.map((b, i) => [b.id, i]))
  const key = (b, fallback) => (pos.has(b.id) ? pos.get(b.id) : priorIndex.get(b.id) ?? fallback)
  const merged = [...prior, ...entries]
    .map((b, i) => [b, key(b, order.length + i)])
    .sort((a, b) => a[1] - b[1])
    .map(([b]) => b)
  writeFileSync(timelinePath, JSON.stringify(merged, null, 2))
  return merged
}

const mergeOnly = async (beat) => {
  await runBeat(beat)
  const merged = mergeEntries(timeline)
  console.log(`\n✅ re-recorded ${beat.id} (timeline now ${merged.length} beats)`)
}

if (ONLY) {
  const beat = story.beats.find((b) => b.id === ONLY)
  if (!beat) throw new Error(`unknown beat: ${ONLY}`)
  // Re-creating a still needs no browser at all (and must not open a tab over it).
  if (isStill(beat)) {
    const merged = mergeEntries([stillEntry(beat)])
    console.log(`✅ ${beat.id} is a ${beat.source} beat — re-indexed without capture (timeline now ${merged.length} beats)`)
    process.exit(0)
  }
  openSoft(beat.source === 'app' ? `${APP}${beat.route}` : beat.url ?? `${APP}/`)
  safeWait(); await sleep(3500); await ensureLogin()
  // `agent-browser set viewport` WEDGES the session daemon in this agent-browser build
  // (<KEY>/<KEY>, 2026-10-07), so it is opt-in only: set the window size on the host
  // (place-chrome.sh) or via CDP Emulation.setDeviceMetricsOverride instead. Enable with
  // AB_ALLOW_SET_VIEWPORT=1 only if a future build fixes the wedge.
  if (process.env.AB_ALLOW_SET_VIEWPORT === '1') { ab('set', 'viewport', String(VW), String(VH)); await sleep(1500) }
  warnSmallViewport(pageViewport())
  await openStream(); await sleep(1500)
  await mergeOnly(beat)
} else {
  openSoft(`${APP}/`)
  ab('set', 'viewport', String(VW), String(VH))
  safeWait(); await sleep(3500)
  await ensureLogin()
  warnSmallViewport(pageViewport())
  await openStream()
  await sleep(2000)
  console.log(`stream open · viewport ${VW}x${VH} · ${FPS} fps · out ${OUT}`)

  let phase = null
  for (const beat of story.beats) {
    const p = beat.phase ?? 'any'
    if (p !== 'any' && p !== phase) {
      phase = p
      const hook = HOOKS[p]
      if (hook) {
        console.log(`\n▶ phase ${p}: ${hook}`)
        sh(hook)
      }
    }
    if (isStill(beat)) {
      timeline.push(stillEntry(beat))
      continue
    }
    await runBeat(beat)
  }
  writeFileSync(timelinePath, JSON.stringify(timeline, null, 2))
  try { ab('stream', 'disable') } catch {}
  console.log(`\n✅ captured ${timeline.filter((b) => b.segment).length} segments → ${SEG}\n   timeline → ${timelinePath}`)
}
