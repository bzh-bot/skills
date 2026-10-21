#!/usr/bin/env node
// collect-release.mjs — build a repo-agnostic release manifest for the release video.
//
// Turns "everything that landed between the last tag and now" into one JSON file the
// storyboard step can read: merged PRs (when the remote is GitHub and `gh` is authed),
// the commits that never got a PR, a grouping hint per item (directory / conventional
// scope) so R2 can propose chapters without reading the whole diff, and a markdown
// notes draft.
//
// Node ESM, no dependencies. Every git/gh call is best-effort: a missing tag, a
// shallow clone or an offline gh degrades to `git log` rather than failing.
//
//   node collect-release.mjs --repo ~/work/<org> --out release-manifest.json --notes release-notes.md
//
// See steps/1-collect.md for the checks.

import { execFileSync } from 'node:child_process'
import { writeFileSync, existsSync } from 'node:fs'
import { resolve, join } from 'node:path'

// ── args ───────────────────────────────────────────────────────────────────────
const argv = process.argv.slice(2)
const arg = (name, dflt = '') => {
  const i = argv.indexOf(`--${name}`)
  return i >= 0 && argv[i + 1] && !argv[i + 1].startsWith('--') ? argv[i + 1] : dflt
}

const REPO = resolve(arg('repo', process.cwd()))
const FROM = arg('from', '')
const TO = arg('to', 'HEAD')
const SINCE = arg('since', '')                 // used only when the repo has no tags
const OUT = resolve(arg('out', join(process.cwd(), 'release-manifest.json')))
const NOTES = arg('notes', '')
const GH = arg('gh', 'auto')                   // auto | off
const LIMIT = Number(arg('limit', '300'))
const NAME = arg('name', '')                   // override the release name, e.g. "the product 2.4"
const FETCH = argv.includes('--fetch')         // git fetch --tags first (stale clones are the #1 cause of an empty range)
const ALLOW_EMPTY = argv.includes('--allow-empty')

if (!existsSync(REPO)) {
  console.error(`✖ repo not found: ${REPO}`)
  process.exit(2)
}

// ── small helpers ───────────────────────────────────────────────────────────────
// stdio is pinned to pipes: without it, node echoes a failing child's stderr into
// ours, so `git describe` on a tagless repo dumps git's usage text into the output.
const capture = (bin, a) => {
  try {
    const out = execFileSync(bin, a, { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024, stdio: ['ignore', 'pipe', 'pipe'] })
    return { ok: true, out: out.trim(), err: '' }
  } catch (e) {
    return { ok: false, out: String(e.stdout ?? '').trim(), err: String(e.stderr ?? e.message ?? '').trim() }
  }
}
const git = (...a) => capture('git', ['-C', REPO, ...a]).out
const gh = (a) => capture('gh', a)
const note = (kind, msg) => console.log(`${kind === 'WARN' ? '⚠️ ' : kind === 'OK' ? '✅' : '  '} ${msg}`)

// ── classification (hoisted: typeArea is needed by the grouping below) ──────────
const TYPE_AREA = {
  feat: 'Features', fix: 'Fixes', perf: 'Performance', refactor: 'Refactoring',
  docs: 'Docs', chore: 'Chores', test: 'Tests', build: 'Build', ci: 'CI', style: 'Style', revert: 'Reverts',
}
const typeArea = (t) => TYPE_AREA[t] ?? 'Other'

function classify(title) {
  const m = title.match(/^(\w+)(?:\(([^)]+)\))?(!?):/)
  return { type: m ? m[1].toLowerCase() : '', scope: m ? (m[2] || '').toLowerCase() : '', breaking: Boolean(m && m[3] === '!') }
}

function topDirs(paths) {
  const out = new Set()
  for (const p of paths) {
    const seg = p.split('/')
    // monorepo-aware: packages/x/** and apps/x/** are one area, not one area called "packages"
    out.add(['packages', 'apps', 'services', 'libs'].includes(seg[0]) && seg.length > 1 ? `${seg[0]}/${seg[1]}` : seg[0])
  }
  return [...out]
}

if (!capture('git', ['-C', REPO, 'rev-parse', '--git-dir']).ok) {
  console.error(`✖ not a git repository: ${REPO}`)
  process.exit(2)
}

// A stale clone is the #1 reason the range comes out empty; --fetch makes the run
// self-sufficient on a machine that has not pulled in weeks.
if (FETCH) {
  const f = capture('git', ['-C', REPO, 'fetch', '--tags', '--prune', 'origin'])
  note(f.ok ? 'OK' : 'WARN', f.ok ? 'git fetch --tags done' : `git fetch failed: ${f.err.split('\n')[0]}`)
}

// ── range ──────────────────────────────────────────────────────────────────────
// Prefer the newest tag reachable from TO. `--tags` so lightweight tags count.
const fromTag = FROM || git('describe', '--tags', '--abbrev=0', TO)
let fromDate = fromTag ? git('log', '-1', '--format=%cI', fromTag) : ''

if (!fromTag) {
  // No tags anywhere: fall back to a time window so the run is still deterministic.
  fromDate = SINCE || new Date(Date.now() - 90 * 864e5).toISOString().slice(0, 10)
  note('WARN', `no git tag reachable — falling back to --since=${fromDate}. Pass --from <tag> or --since <date> to pin the window.`)
} else {
  note('OK', `range ${fromTag}..${TO}  (tag dated ${fromDate.slice(0, 10)})`)
}

const RANGE = fromTag ? `${fromTag}..${TO}` : `--since=${fromDate}`
const toSha = git('rev-parse', TO)
const toDate = git('log', '-1', '--format=%cI', TO)

// The set of commits in range — used to prove a PR's merge commit actually belongs here.
const rangeShas = new Set(git('rev-list', RANGE).split('\n').filter(Boolean))
const shallow = git('rev-parse', '--is-shallow-repository') === 'true'
// On a shallow or stale clone the commit set is untrustworthy, so filtering PRs by
// merge-commit membership would silently drop the whole release. Fall back to the
// merge date and say so, loudly.
const usableShaSet = !shallow && rangeShas.size > 0
if (shallow) note('WARN', 'SHALLOW clone — re-run with --fetch (or `git fetch --unshallow --tags`); filtering PRs by merge date instead of merge commit.')
if (fromDate && toDate && fromDate > toDate) {
  note('WARN', `the window starts AFTER the tip (${fromDate.slice(0, 10)} > ${toDate.slice(0, 10)}) — this clone is stale. Re-run with --fetch.`)
}
if (!rangeShas.size && !ALLOW_EMPTY) {
  // Refuse loudly. Continuing would fall through to a merge-DATE filter and produce a
  // manifest full of PRs that are not in this clone at all — a plausible-looking lie,
  // which is the worst possible output for a release video.
  console.error([
    `\n✖ the range ${fromTag || fromDate}..${TO} is EMPTY for ${REPO}.`,
    `  tip ${toSha.slice(0, 8)} is dated ${toDate.slice(0, 10)}; the window starts ${String(fromDate).slice(0, 10)}.`,
    '  Fix one of:',
    '    · re-run with --fetch               (pulls tags + commits)',
    '    · --from <tag> --to <ref>           (pin the range explicitly)',
    '    · --since <YYYY-MM-DD>              (pin the window explicitly)',
    '    · --allow-empty                     (you really do expect nothing here)',
  ].join('\n'))
  process.exit(1)
}

// ── identity ───────────────────────────────────────────────────────────────────
const remoteUrl = git('remote', 'get-url', 'origin')
const slug = (remoteUrl.match(/github\.com[:/]([^/\s]+\/[^/\s]+?)(?:\.git)?$/)?.[1]) || ''
const isGitHub = Boolean(slug)
const defaultBranch = (() => {
  const head = git('symbolic-ref', 'refs/remotes/origin/HEAD')
  return head ? head.replace('refs/remotes/origin/', '') : 'main'
})()

// ── commits ────────────────────────────────────────────────────────────────────
const SEP = '\u001f'
const logArgs = (extra) => ['log', ...extra, '--pretty=format:%H' + SEP + '%h' + SEP + '%s' + SEP + '%an' + SEP + '%aI', RANGE]

const commits = git(...logArgs(['--no-merges'])).split('\n').filter(Boolean).map((l) => {
  const [sha, short, subject, author, date] = l.split(SEP)
  return { sha, short, subject, author, date }
})
const merges = git(...logArgs(['--merges'])).split('\n').filter(Boolean).map((l) => l.split(SEP)[2])

// ── PRs ─────────────────────────────────────────────────────────────────────────
// Primary: `gh pr list` (accurate merge date, labels, files). Fallback: squash-merge
// subjects, which carry the PR number even without `gh`.
let items = []
let source = 'git-log'

const ghUsable = isGitHub && GH !== 'off' && capture('gh', ['auth', 'status']).ok
if (isGitHub && GH !== 'off' && !ghUsable) note('WARN', 'gh is not authenticated on this machine — falling back to git log')

if (ghUsable) {
  const res = gh(['pr', 'list', '--repo', slug, '--state', 'merged', '--base', defaultBranch,
    '--limit', String(LIMIT), '--json', 'number,title,url,author,labels,mergedAt,mergeCommit,body,files'])
  let prs = []
  if (res.ok && res.out) {
    try { prs = JSON.parse(res.out) } catch { prs = [] }
  }
  if (!prs.length) note('WARN', `gh pr list returned no rows for ${slug} (base ${defaultBranch})${res.ok ? '' : `: ${res.err.split('\n')[0]}`}`)
  const kept = prs.filter((p) => {
    if (fromDate && p.mergedAt && p.mergedAt < fromDate) return false
    // mergedAt alone is a guess when the base branch is long-lived; the merge commit
    // being IN the range is the actual proof (and it also drops cherry-picks).
    if (!usableShaSet) return true
    const mc = p.mergeCommit?.oid
    return mc ? rangeShas.has(mc) : true
  })
  items = kept.map((p) => ({
    number: p.number,
    title: p.title,
    url: p.url,
    author: p.author?.login ?? '',
    labels: (p.labels ?? []).map((l) => l.name),
    mergedAt: p.mergedAt,
    body: (p.body ?? '').slice(0, 4000),
    mergeCommit: p.mergeCommit?.oid ?? null,
    changedFiles: (p.files ?? []).length,
    dirs: topDirs((p.files ?? []).map((f) => f.path)),
    ...classify(p.title),
  }))
  source = 'gh'
  note(kept.length ? 'OK' : 'WARN', `${kept.length}/${prs.length} merged PRs are in range (${slug}, base ${defaultBranch})`
    + (usableShaSet ? '' : '  [merge-date filter]'))
  if (prs.length >= LIMIT) note('WARN', `hit --limit ${LIMIT}; raise it or narrow the range`)
}

if (!items.length) {
  const re = /\(#(\d+)\)\s*$/
  for (const c of commits) {
    const m = c.subject.match(re)
    if (!m) continue
    items.push({
      number: Number(m[1]), title: c.subject.replace(re, '').trim(),
      url: isGitHub ? `https://github.com/${slug}/pull/${m[1]}` : null,
      author: c.author, labels: [], mergedAt: c.date, body: '',
      mergeCommit: c.sha, changedFiles: null, dirs: [],
      ...classify(c.subject),
    })
  }
  note(items.length ? 'OK' : 'WARN',
    items.length ? `parsed ${items.length} PR number(s) from ${merges.length} merge commit(s)`
                 : 'no PR references found — the notes will be built from raw commits')
}

// Commits that never made it into a PR — the "silent" part of a release.
const prShas = new Set(items.map((i) => i.mergeCommit).filter(Boolean))
const commitsWithoutPr = commits.filter((c) => !prShas.has(c.sha)).slice(0, 400)

// ── stats ───────────────────────────────────────────────────────────────────────
const shortstat = git('diff', '--shortstat', RANGE)
const authors = [...new Set(commits.map((c) => c.author))].sort()

// ── grouping hints ───────────────────────────────────────────────────────────────
const groupKey = (i) => i.scope || i.dirs[0] || (i.type ? typeArea(i.type) : 'Other')
const byArea = {}
for (const i of items) (byArea[groupKey(i)] ??= []).push(i.number)
const byType = {}
for (const i of items) (byType[i.type || 'other'] ??= []).push(i.number)

// Areas with only one small item read as noise in a 4-minute video; flag them so R2
// can fold them into an "Also in this release" chapter instead of giving each a beat.
const smallAreas = Object.entries(byArea).filter(([, v]) => v.length < 2).map(([k]) => k)

const manifest = {
  generatedAt: new Date().toISOString(),
  source,
  repo: { path: REPO, slug: slug || null, remote: remoteUrl || null, defaultBranch, isGitHub, shallow },
  release: {
    name: NAME || (fromTag ? `${fromTag}..${TO}` : `since ${fromDate}`),
    fromTag: fromTag || null,
    fromDate: fromDate || null,
    toRef: TO,
    toSha,
    toDate,
  },
  filterMode: usableShaSet ? 'merge-commit-in-range' : 'merged-date',
  confidence: usableShaSet ? 'high' : 'low',
  stats: {
    prs: items.length,
    mergeCommits: merges.length,
    commits: commits.length,
    commitsWithoutPr: commitsWithoutPr.length,
    authors,
    shortstat: shortstat || null,
  },
  groupingHints: { byArea, byType, smallAreas },
  items,
  commitsWithoutPr,
}

writeFileSync(OUT, JSON.stringify(manifest, null, 2))
note('OK', `manifest → ${OUT}  (${items.length} PRs · ${commits.length} commits · ${authors.length} authors)`)
if (shortstat) console.log(`   ${shortstat}`)

if (NOTES) {
  const md = renderNotes(manifest)
  writeFileSync(NOTES, md)
  note('OK', `notes draft → ${NOTES} (${md.split('\n').length} lines)`)
}

if (!items.length && !commits.length) {
  note('WARN', 'the range is EMPTY — check --from/--to, or fetch first (`git fetch --tags`)')
  process.exit(1)
}

// ── markdown notes draft ────────────────────────────────────────────────────────
function renderNotes(m) {
  const groups = {}
  for (const i of m.items) {
    const k = i.scope ? `${typeArea(i.type)} · ${i.scope}` : (i.type ? typeArea(i.type) : (i.dirs[0] || 'Other'))
    ;(groups[k] ??= []).push(i)
  }
  const order = Object.keys(groups).sort((a, b) => groups[b].length - groups[a].length || a.localeCompare(b))
  const head = m.release.fromTag
    ? `# ${m.release.name}\n\n\`${m.release.fromTag}\` → \`${m.release.toRef}\` (${m.release.toSha.slice(0, 8)})`
    : `# ${m.release.name}\n\nSince ${String(m.release.fromDate).slice(0, 10)}`
  const lines = [head, '', `**${m.stats.prs}** pull requests · **${m.stats.commits}** commits · by ${m.stats.authors.length} author(s)`, '']
  for (const k of order) {
    lines.push(`## ${k} (${groups[k].length})`, '')
    for (const i of groups[k]) {
      const link = i.url ? `[#${i.number}](${i.url})` : `#${i.number}`
      const tags = i.labels.length ? ` _(${i.labels.join(', ')})_` : ''
      lines.push(`- ${i.title.replace(/\s*\(#\d+\)\s*$/, '')} — ${link} · @${i.author}${tags}`)
    }
    lines.push('')
  }
  if (m.commitsWithoutPr.length) {
    lines.push(`## Commits without a PR (${m.commitsWithoutPr.length})`, '')
    for (const c of m.commitsWithoutPr.slice(0, 60)) lines.push(`- ${c.subject} — ${c.short} · @${c.author}`)
    if (m.commitsWithoutPr.length > 60) lines.push(`- … and ${m.commitsWithoutPr.length - 60} more`)
    lines.push('')
  }
  return lines.join('\n')
}
