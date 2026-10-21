#!/usr/bin/env node
// render-diagrams.mjs — render every Mermaid diagram beat of a storyboard to a PNG
// the compose step can use, with settings that are stable across runs.
//
// Why this exists: a diagram is the only way a viewer understands the system before
// they see the change (see ../diagrams.md). A diagram pasted from a drawing tool is
// not reviewable, cannot be diffed and cannot be fixed in one character; a .mmd can.
//
// Usage:
//   render-diagrams.mjs --storyboard <VIDEO_DIR>/storyboard.json --out <VIDEO_DIR>
//     [--only <beat-id>] [--check] [--size 1600] [--scale 2] [--allow-small]
//
//   --check   render nothing; fail if a PNG is missing, or if its .mmd changed since
//             the render (sha256 in diagrams/renders.json). Run it in V2 and V7.
//   --only    re-render one beat (same idempotence as capture-beats.mjs --only)
//
// Determinism: pinned mmdc version (scripts/setup-mermaid.sh), fixed --size/--scale,
// dark theme, fixed background, DejaVu Sans (the font compose burns captions with),
// `deterministicIds` seeded from the .mmd content, system Chrome, no icon packs.
// Same input + same version ⇒ same PNG. That is what makes re-rendering one diagram
// mid-cut safe.
import { execFileSync, spawnSync } from 'node:child_process'
import { createHash } from 'node:crypto'
import { existsSync, mkdirSync, readFileSync, statSync, writeFileSync } from 'node:fs'
import { dirname, isAbsolute, join, relative } from 'node:path'
import { homedir } from 'node:os'

// ─── args ───────────────────────────────────────────────────────────────────
const argv = process.argv.slice(2)
const arg = (name, dflt) => {
  const i = argv.indexOf(`--${name}`)
  return i >= 0 && argv[i + 1] && !argv[i + 1].startsWith('--') ? argv[i + 1] : dflt
}
const flag = (name) => argv.includes(`--${name}`)

const STORY = arg('storyboard', 'storyboard.json')
const OUT = arg('out', dirname(STORY) || '.')
const ONLY = arg('only', '')
const CHECK = flag('check')
const SIZE = Number(arg('size', '1600'))
const SCALE = Number(arg('scale', '2'))
const ALLOW_SMALL = flag('allow-small')
const BG = arg('background', '#0B1220')          // == compose-video.mjs --bg 0x0B1220
const CSS_FONT = 'DejaVu Sans, Helvetica, Arial, sans-serif'
const MMDC_VERSION = '12.0.0'

const story = JSON.parse(readFileSync(STORY, 'utf8'))
const RENDER_DIR = join(OUT, 'diagrams', '.render')
const MANIFEST = join(OUT, 'diagrams', 'renders.json')

const sha256 = (file) => createHash('sha256').update(readFileSync(file)).digest('hex')
const rel = (p) => relative(OUT, p) || p
const abs = (p) => (isAbsolute(p) ? p : join(OUT, p))

// ─── locate the toolchain ───────────────────────────────────────────────────
const which = (bin) => {
  const r = spawnSync('bash', ['-lc', `command -v ${bin}`], { encoding: 'utf8' })
  return r.status === 0 ? r.stdout.trim() : ''
}
// Walk up from the video dir and from the cwd looking for the worktree-local install.
// `setup-mermaid.sh` puts mermaid-cli in <worktree>/.video-tools (or $VIDEO_TOOLS_DIR)
// because ~/.local/share is root-owned INSIDE THE CAGE — a live run on 2026-10-19 could
// not install there and had to vendor mermaid-cli into the worktree mid-tour.
const worktreeInstallCandidates = () => {
  const out = []
  const roots = [OUT, process.cwd()]
  for (const root of roots) {
    let dir = root
    for (let i = 0; i < 8; i++) {
      out.push(join(dir, '.video-tools/mermaid-cli/node_modules/.bin/mmdc'))
      const parent = dirname(dir)
      if (parent === dir) break
      dir = parent
    }
  }
  return out
}
// A `mermaid-cli.path` file (written by setup-mermaid.sh) names the prefix that was
// actually installed, so a re-render uses the same binary the render was made with.
const recordedPrefix = () => {
  const pointers = [
    process.env.VIDEO_TOOLS_DIR ? join(process.env.VIDEO_TOOLS_DIR, 'mermaid-cli.path') : '',
    ...worktreeInstallCandidates().map((p) => join(dirname(dirname(dirname(dirname(p)))), 'mermaid-cli.path')),
  ].filter(Boolean)
  for (const f of pointers) {
    try {
      const prefix = readFileSync(f, 'utf8').trim()
      if (prefix) return join(prefix, 'node_modules/.bin/mmdc')
    } catch { /* no pointer */ }
  }
  return ''
}
const mmdcCandidates = [...new Set([
  process.env.MMDC ?? '',
  which('mmdc'),
  process.env.VIDEO_TOOLS_DIR ? join(process.env.VIDEO_TOOLS_DIR, 'mermaid-cli/node_modules/.bin/mmdc') : '',
  recordedPrefix(),
  ...worktreeInstallCandidates(),
  join(homedir(), '.local/share/mermaid-cli/node_modules/.bin/mmdc'),
  join(homedir(), '.cache/mermaid-cli/node_modules/.bin/mmdc'),
].filter(Boolean))]
const mmdc = mmdcCandidates.find((p) => existsSync(p)) ?? ''

const chrome = (() => {
  const candidates = [
    process.env.MMDC_CHROME ?? '',
    process.env.CHROME_PATH ?? '',
    process.env.GOOGLE_CHROME_BIN ?? '',
    '/usr/bin/google-chrome',
    '/usr/bin/google-chrome-stable',
    '/usr/bin/chromium',
    '/usr/bin/chromium-browser',
    '/snap/bin/chromium',
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  ].filter(Boolean)
  return candidates.find((p) => existsSync(p)) ?? ''
})()

// ─── the diagram beats ──────────────────────────────────────────────────────
const isDiagram = (b) => b.source === 'image' || b.kind === 'diagram'
const diagrams = story.beats.filter(isDiagram)
if (!diagrams.length) {
  console.error(`FAIL: ${STORY} has no diagram beat (source: "image").
Every tour needs a concept/architecture beat before the first filmed beat, and an ERD
when the change touches the data model — see diagrams.md. Nothing to render.`)
  process.exit(2)
}

const selected = ONLY ? diagrams.filter((b) => b.id === ONLY) : diagrams
if (ONLY && !selected.length) {
  console.error(`FAIL: no diagram beat with id "${ONLY}" (have: ${diagrams.map((b) => b.id).join(', ')})`)
  process.exit(2)
}

const sourcePath = (b) => abs(b.mmd ?? `diagrams/${b.id}.mmd`)
const imagePath = (b) => abs(b.image ?? `diagrams/png/${b.id}.png`)

// ─── check mode ─────────────────────────────────────────────────────────────
const pngDims = (file) => {
  const buf = readFileSync(file)
  if (buf.toString('ascii', 1, 4) !== 'PNG') throw new Error(`${file} is not a PNG`)
  return { w: buf.readUInt32BE(16), h: buf.readUInt32BE(20) }
}
const legibility = ({ w, h }) => {
  // The frame reserves the bottom 88 px for captions and a little breathing room.
  const USABLE_H = 900 - 88 - 40
  return Math.min(1600 / w, USABLE_H / h)
}
const manifest = existsSync(MANIFEST) ? JSON.parse(readFileSync(MANIFEST, 'utf8')) : {}

if (CHECK) {
  let fail = 0
  const note = (ok, msg) => { console.log(`  ${ok ? 'OK  ' : 'FAIL'} ${msg}`); if (!ok) fail++ }
  console.log(`── diagram check · ${diagrams.length} beat(s) ─────────────────`)
  for (const b of diagrams) {
    const src = sourcePath(b)
    const img = imagePath(b)
    if (!existsSync(src)) { note(false, `${b.id} · missing source ${rel(src)}`); continue }
    if (!existsSync(img)) { note(false, `${b.id} · missing render ${rel(img)} — run render-diagrams.mjs`); continue }
    const want = sha256(src)
    const got = manifest[b.id]?.mmdSha256
    const stale = got && got !== want
    // statSync keeps the lint honest; the hash is the authority (mtime lies after a checkout)
    statSync(img)
    note(!stale, `${b.id} · ${rel(img)} ${stale ? 'STALE — the .mmd changed since it was rendered' : 'up to date'}`)
  }
  if (fail) { console.error(`\n❌ ${fail} diagram problem(s) — render before capturing (see diagrams.md)`); process.exit(1) }
  console.log('\n✅ every diagram is rendered and current')
  if (!chrome) console.log('   (note: no system Chrome found — a re-render would fail; set MMDC_CHROME)')
  process.exit(0)
}

if (!mmdc) {
  console.error(`FAIL: mmdc (mermaid-cli ${MMDC_VERSION}) not found.

Looked for it here:
${mmdcCandidates.map((p) => `  · ${p}${existsSync(p) ? '  (missing binary)' : ''}`).join('\n') || '  (no candidate path — is node on PATH?)'}

Install the pinned renderer into a WRITABLE location — inside the workflow cage
~/.local/share is root-owned, so the worktree-local default is the one that works:

  bash ${join(dirname(new URL(import.meta.url).pathname), 'setup-mermaid.sh')}

  # or name the location yourself:
  VIDEO_TOOLS_DIR=<writable dir> bash ${join(dirname(new URL(import.meta.url).pathname), 'setup-mermaid.sh')}
  MMDC=/path/to/mmdc node render-diagrams.mjs …

setup-mermaid.sh installs <worktree>/.video-tools/mermaid-cli by default and records the
prefix, so this script finds the same binary on the next run. See diagrams.md.`)
  process.exit(2)
}
if (!chrome) {
  console.error(`FAIL: no Chrome/Chromium found for mmdc's puppeteer.
Set MMDC_CHROME=/path/to/chrome.`)
  process.exit(2)
}

const version = execFileSync(mmdc, ['--version'], { encoding: 'utf8' }).trim().split('\n').pop()
if (version !== MMDC_VERSION) {
  console.warn(`  ! mmdc ${version} (skill pins ${MMDC_VERSION}) — rendering will work, but the PNG is not guaranteed byte-stable against a pinned re-render`)
}

// ─── deterministic render config ────────────────────────────────────────────
mkdirSync(RENDER_DIR, { recursive: true })
mkdirSync(join(OUT, 'diagrams', 'png'), { recursive: true })

const pptrConfig = join(RENDER_DIR, 'puppeteer.json')
const cssFile = join(RENDER_DIR, 'mermaid.css')
const baseConfig = join(RENDER_DIR, 'mermaid.base.json')

writeFileSync(pptrConfig, JSON.stringify({
  executablePath: chrome,
  args: ['--no-sandbox', '--disable-dev-shm-usage', '--font-render-hinting=none', '--hide-scrollbars'],
  defaultViewport: { width: SIZE, height: Math.round((SIZE * 9) / 16) },
}, null, 2))

writeFileSync(cssFile, `:root { --mermaid-font-family: "${CSS_FONT}"; }
.nodeLabel, .edgeLabel, .label, .entityLabel, .actor, .messageText, text {
  font-family: "${CSS_FONT}" !important;
}
`)

const mermaidConfig = (seed) => ({
  deterministicIds: true,
  deterministicIDSeed: seed,
  theme: 'dark',
  themeVariables: { fontFamily: CSS_FONT, fontSize: '20px', background: BG },
  // Landscape is not a taste: a portrait diagram is fitted to the frame and becomes
  // unreadable (see the legibility gate below). For ER diagrams the `direction LR`
  // DIRECTIVE IN THE .mmd is what mmdc 12 actually honours — `er.layoutDirection` stays
  // as belt-and-braces (verified 2026-10-19: without the directive a two-entity ERD
  // rendered 1380x3200 and the legibility gate rejected it).
  er: { layoutDirection: 'LR', minEntityWidth: 120 },
  flowchart: { curve: 'linear', htmlLabels: true, padding: 12 },
  sequence: { mirrorActors: false, wrap: true, actorFontFamily: CSS_FONT, noteFontFamily: CSS_FONT, messageFontFamily: CSS_FONT },
})

// ─── render ─────────────────────────────────────────────────────────────────
let fail = 0
console.log(`── rendering ${selected.length} diagram(s) · mmdc ${version} · ${SIZE}px @${SCALE}x · ${BG} ──`)

for (const b of selected) {
  const src = sourcePath(b)
  const img = imagePath(b)
  if (!existsSync(src)) {
    console.error(`  FAIL ${b.id} · missing source ${rel(src)}`)
    fail++
    continue
  }
  mkdirSync(dirname(img), { recursive: true })
  const seed = sha256(src).slice(0, 16)
  const cfg = join(RENDER_DIR, `${b.id}.mermaid.json`)
  writeFileSync(cfg, JSON.stringify(mermaidConfig(seed), null, 2))

  const args = ['-i', src, '-o', img, '-t', 'dark', '-b', BG, '-s', String(SCALE),
    '--size', String(SIZE), '-c', cfg, '-C', cssFile, '-p', pptrConfig, '-q']
  const t0 = Date.now()
  const r = spawnSync(mmdc, args, { encoding: 'utf8', timeout: 180000 })
  if (r.status !== 0) {
    const tail = `${r.stderr ?? ''}${r.stdout ?? ''}`.trim().split('\n').slice(-4).join('\n')
    console.error(`  FAIL ${b.id} · mmdc exit ${r.status}\n${tail}`)
    fail++
    continue
  }

  const dims = pngDims(img)
  const fit = legibility(dims)
  const onScreen = `${Math.round(dims.w * fit)}×${Math.round(dims.h * fit)} in frame`
  const kind = b.diagram ?? 'diagram'
  const note = (msg) => console.log(`  ${msg}`)

  // A diagram fitted at <45 % is unreadable at 1600×900 no matter how good the source
  // is. Fix the .mmd (direction LR, split it), do not accept it and hope.
  if (fit < 0.45) {
    if (ALLOW_SMALL) note(`WARN ${b.id} · ${kind} · ${dims.w}×${dims.h} → ${onScreen} (--allow-small)`)
    else {
      console.error(`  FAIL ${b.id} · ${kind} · ${dims.w}×${dims.h} → ${onScreen}
        too small to read in a 1600×900 frame. Make it landscape (\`direction LR\`), cut it
        to ≤ 6 entities / ≤ 8 nodes, or split it into two diagrams. Use --allow-small only
        if the content is genuinely short (e.g. two nodes and one arrow).`)
      fail++
      continue
    }
  } else if (fit > 1.6) {
    note(`WARN ${b.id} · ${kind} · ${dims.w}×${dims.h} → ${onScreen} (upscaled; the PNG is @${SCALE}x so it stays sharp)`)
  } else {
    note(`OK   ${b.id} · ${kind} · ${dims.w}×${dims.h} → ${onScreen} · ${Date.now() - t0} ms`)
  }

  manifest[b.id] = {
    mmd: rel(src), image: rel(img), mmdSha256: sha256(src), pngSha256: sha256(img),
    width: dims.w, height: dims.h, fit, scale: SCALE, size: SIZE,
    mmdc: version, renderedAt: new Date().toISOString(),
  }
}

mkdirSync(dirname(MANIFEST), { recursive: true })
writeFileSync(MANIFEST, JSON.stringify(manifest, null, 2) + '\n')

if (fail) {
  console.error(`\n❌ ${fail} diagram(s) failed — fix the .mmd and re-run (never edit the PNG)`)
  process.exit(1)
}

// The renderer cannot see. This is the part no script can do for you.
console.log(`\n✅ rendered ${selected.length} diagram(s) → ${rel(join(OUT, 'diagrams', 'png'))}
   manifest → ${rel(MANIFEST)}
   LOOK AT EVERY PNG before capturing. The script checks size and aspect, not meaning:
   clipped/overlapping labels, tofu glyphs, arrows that miss their box, the wrong table
   highlighted, real names from the diff (not pet names), the changed node in the accent
   colour. A diagram you did not look at is a diagram that ships broken.`)
