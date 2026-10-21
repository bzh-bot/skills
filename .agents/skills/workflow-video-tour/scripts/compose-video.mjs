#!/usr/bin/env node
// compose-video.mjs — segments + narration → one narrated, annotated MP4.
//
// Opens on a 4 s intro card (ticket + PR number over the ultra-brief title), then per beat:
// burn the ROI box (drawbox) and the caption bar (drawtext from a text file, so no
// escaping), fit the segment to the narration (freeze the last frame only when the line
// overruns), mix narration at -16 LUFS, then concat.
//
// Two kinds of beat carry no clip: a `static` card (heading/bullets/footer) and a
// `source: "image"` beat — a Mermaid diagram rendered to PNG by render-diagrams.mjs
// (see diagrams.md). The still path fits the diagram on the bed colour, adds a gentle
// 1.05 push-in and a kind chip, and keeps the caption in the same bottom band as a
// filmed beat so a diagram reads like the rest of the video.
//
// Usage:
//   compose-video.mjs --timeline out/timeline.json --tts out/tts --out out \
//     --slug ABC-45-example-feature \
//     --title "ABC-45 · PR #290" --subtitle "Email for every Stripe event" \
//     [--title-seconds 4] [--bg 0x0B1220] [--fontsize 28] [--accent 0xCBB9C2] [--music track.mp3]
import { execFileSync } from 'node:child_process'
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { isAbsolute, join } from 'node:path'

const argv = process.argv.slice(2)
const arg = (n, d) => { const i = argv.indexOf(`--${n}`); return i >= 0 && argv[i + 1] && !argv[i + 1].startsWith('--') ? argv[i + 1] : d }
const flag = (n) => argv.includes(`--${n}`)

const TIMELINE = arg('timeline', 'timeline.json')
const TTS = arg('tts', 'tts')
const OUT = arg('out', '.')
const SLUG = arg('slug', 'walkthrough')
const TITLE = arg('title', '')
const SUBTITLE = arg('subtitle', '')
const BG = arg('bg', '0x0B1220')
const FONTSIZE = Number(arg('fontsize', '28'))
const MUSIC = arg('music', '')
const FONT = arg('font', '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf')
const FPS = Number(arg('fps', '30'))
const ACCENT = arg('accent', '0xCBB9C2')
const TITLE_S = Number(arg('title-seconds', '4'))
const SUBTITLE_FOOTER = arg('intro-footer', '')   // e.g. "org/repo · TICKET-1 · PR #290"

const W = Number(arg('width', '0')) || null
const H = Number(arg('height', '0')) || null

const beats = JSON.parse(readFileSync(TIMELINE, 'utf8'))
const SEG = join(OUT, 'seg-final')
const CAPS = join(OUT, 'caps')
for (const d of [SEG, CAPS]) mkdirSync(d, { recursive: true })

// Defence in depth for the motivation contract. `capture-beats.mjs` refuses a storyboard
// whose first narrated beat is not `kind: "motivation"` (see that script's header), but a
// hand-edited timeline or a re-cut of an older run can still reach assembly. Composing a
// video that opens on technical detail is exactly the regression the gate exists for, so
// say it loudly here. Not fatal: re-cutting/re-voicing a finished video must keep working.
const motIdx = beats.findIndex((b) => b.kind === 'motivation')
if (motIdx === -1) {
  console.warn('\n⚠  no `kind: "motivation"` beat in this timeline — this cut opens on technical\n   detail. Every video must open on the problem, in the reporter\'s words (steps/1-storyboard.md).')
} else if (motIdx > 0) {
  console.warn(`\n⚠  the motivation beat (${beats[motIdx].id}) is beat #${motIdx + 1}, not the first — the\n   video opens on ${beats[0].id} before it says why. Put the motivation beat first.`)
} else {
  console.log(`motivation: "${(beats[0].quote ?? '').replace(/\s+/g, ' ').slice(0, 90)}…"`)
}

const run = (cmd, args, opts = {}) =>
  execFileSync(cmd, args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], ...opts })
const durationOf = (f) =>
  Number(run('ffprobe', ['-v', 'error', '-show_entries', 'format=duration', '-of', 'default=nw=1:nk=1', f]).trim())
const dimsOf = (f) => {
  const [w, h] = run('ffprobe', ['-v', 'error', '-select_streams', 'v', '-show_entries', 'stream=width,height', '-of', 'csv=p=0', f]).trim().split(',').map(Number)
  return { w, h }
}

const firstSeg = beats.find((b) => b.segment)
if (!firstSeg) throw new Error('no captured segments in the timeline')
const frame = dimsOf(firstSeg.segment)
const VW = W ?? frame.w
const VH = H ?? frame.h
console.log(`frame ${VW}x${VH} @ ${FPS}fps · ${beats.length} beats`)

// Intro backdrop: the first shot, blurred and dimmed, so the title card looks like the
// product rather than a slide. Override with --intro-bg, or --intro-bg none for flat BG.
let INTRO_BG = arg('intro-bg', '')
if (INTRO_BG && INTRO_BG !== 'none' && !existsSync(INTRO_BG)) {
  console.warn(`  ! --intro-bg ${INTRO_BG} not found — falling back to the first shot`)
  INTRO_BG = ''
}
if (INTRO_BG !== 'none' && !INTRO_BG) {
  const p = join(CAPS, 'intro-bg.png')
  // crop the burned-in caption band off the bottom first, or it blurs into a dark smear
  run('ffmpeg', ['-y', '-i', firstSeg.segment, '-frames:v', '1', '-vf',
    `crop=iw:ih-100:0:0,scale=${VW}:${VH}:force_original_aspect_ratio=increase,crop=${VW}:${VH},` +
    'boxblur=26:2,eq=brightness=-0.34:saturation=0.45', p])
  INTRO_BG = p
}
if (INTRO_BG === 'none') INTRO_BG = ''

// narration: trim/normalise once, then measure the same file the mix uses
const prepVoice = (raw) => {
  const norm = raw.replace(/\.wav$/, '.norm.wav')
  run('ffmpeg', ['-y', '-i', raw, '-af', 'loudnorm=I=-16:TP=-1.5:LRA=11', '-ar', '48000', '-ac', '1', norm])
  return norm
}
const voice = {}
for (const beat of beats) {
  const raw = join(TTS, `${beat.id}.wav`)
  if (!existsSync(raw)) throw new Error(`missing narration: ${raw}`)
  voice[beat.id] = durationOf(prepVoice(raw))
  writeFileSync(join(CAPS, `${beat.id}.txt`), beat.caption ?? '')
  console.log(`  voice ${beat.id.padEnd(18)} ${voice[beat.id].toFixed(1)}s  (clip ${(beat.durationMs / 1000).toFixed(1)}s)`)
}

const segments = []
let cursor = 0
const layout = []

// Greedy word wrap for the motivation card (drawtext does not wrap).
const wrapText = (text, max) => {
  const out = []
  let line = ''
  for (const w of String(text ?? '').split(/\s+/).filter(Boolean)) {
    if (!line) line = w
    else if ((line + ' ' + w).length <= max) line += ' ' + w
    else { out.push(line); line = w }
  }
  if (line) out.push(line)
  return out
}

const card = (beat, seconds, wav, isTitle = false) => {
  const seg = join(SEG, `${beat.id}.mp4`)
  const cap = join(CAPS, `${beat.id}.txt`)
  const txt = (name, body) => { const p = join(CAPS, `${beat.id}.${name}.txt`); writeFileSync(p, body); return p }
  const dt = (path, opts) => `drawtext=fontfile=${FONT}:textfile=${path}:${opts}`
  let vf

  if (isTitle) {
    // Intro: accent rule, TITLE, subtitle, and the provenance footer. The mascot is
    // composited over this later (V5), so keep the lower-right of the frame clear.
    const foot = [SUBTITLE_FOOTER].filter(Boolean).join(' · ')
    // a scrim over the blurred shot: the app is light-themed, so white text needs it
    vf = [
      `drawbox=x=0:y=0:w=iw:h=ih:color=${BG}@0.45:t=fill`,
      `drawbox=x=(w-140)/2:y=(h/2)-118:w=140:h=4:color=${ACCENT}@1:t=fill`,
      dt(txt('title', TITLE), `fontcolor=white:fontsize=52:x=(w-text_w)/2:y=(h/2)-96`),
      SUBTITLE ? dt(txt('sub', SUBTITLE), `fontcolor=${ACCENT}:fontsize=30:x=(w-text_w)/2:y=(h/2)-24`) : null,
      foot ? dt(txt('foot', foot), 'fontcolor=0xB9C4CE:fontsize=20:x=(w-text_w)/2:y=(h/2)+46') : null,
    ].filter(Boolean).join(',')
  } else if (beat.kind === 'motivation') {
    // The opening beat: the reporter's own sentence, quoted, on screen. No caption band —
    // the quote IS the text — and a plain `WHY THIS EXISTS` chip so the viewer knows these
    // are not the author's words. Long quotes wrap to at most four lines; the gate in
    // capture-beats.mjs keeps them short enough that four is never reached.
    const QUOTE_FS = 40
    const LH = 52
    const lines = wrapText(beat.quote ?? '', 46).slice(0, 4)
    const base = Math.round((VH - lines.length * LH) / 2) - 24
    const attribution = beat.reportedBy ? `— ${beat.reportedBy}` : '— reported in the ticket'
    const foot = [attribution, beat.footer].filter(Boolean).join(' · ')
    vf = [
      `drawtext=fontfile=${FONT}:textfile=${txt('chip', 'WHY THIS EXISTS')}:fontcolor=0x0B1220:fontsize=22:box=1:boxcolor=${ACCENT}@1:boxborderw=14:x=44:y=36`,
      `drawbox=x=(w-140)/2:y=${base - 46}:w=140:h=4:color=${ACCENT}@1:t=fill`,
      ...lines.map((line, i) =>
        dt(txt(`q${i}`, line), `fontcolor=white:fontsize=${QUOTE_FS}:x=(w-text_w)/2:y=${base + i * LH}`)),
      dt(txt('attrib', foot), `fontcolor=0xB9C4CE:fontsize=24:x=(w-text_w)/2:y=${base + lines.length * LH + 34}`),
    ].join(',')
    console.log(`  card  ${beat.id.padEnd(18)} motivation — "${(beat.quote ?? '').replace(/\s+/g, ' ')}…"`)
  } else if (Array.isArray(beat.bullets) && beat.bullets.length) {
    // Outro / static card: a real summary block, not one run-on line.
    const n = beat.bullets.length
    const LH = 56
    const top = `(h/2)-${(n * LH) / 2}`
    const head = beat.heading
      ? dt(txt('head', beat.heading), `fontcolor=${ACCENT}:fontsize=26:x=(w-text_w)/2:y=(h/2)-${(n * LH) / 2 + 82}`)
      : null
    const lines = beat.bullets.map((b, i) =>
      dt(txt(`b${i}`, `·  ${b}`), `fontcolor=white:fontsize=34:x=(w-text_w)/2:y=${top}+${i * LH}`))
    const foot = beat.footer
      ? dt(txt('foot', beat.footer), `fontcolor=0xB9C4CE:fontsize=20:x=(w-text_w)/2:y=(h/2)+${(n * LH) / 2 + 34}`)
      : null
    vf = [head, ...lines, foot].filter(Boolean).join(',')
    console.log(`  card  ${beat.id.padEnd(18)} summary — ${n} bullet(s)`)
  } else {
    writeFileSync(cap, beat.caption ?? '')
    vf = dt(cap, `fontcolor=white:fontsize=${FONTSIZE + 12}:line_spacing=22:x=(w-text_w)/2:y=(h-text_h)/2`)
  }

  const useBg = isTitle && INTRO_BG
  const input = useBg ? ['-loop', '1', '-framerate', String(FPS), '-i', INTRO_BG]
    : ['-f', 'lavfi', '-i', `color=c=${BG}:s=${VW}x${VH}:d=${seconds}`]
  run('ffmpeg', ['-y', ...input,
    ...(wav ? ['-i', wav] : ['-f', 'lavfi', '-i', 'anullsrc=r=48000:cl=stereo']),
    '-filter_complex', `[0:v]${useBg ? 'format=yuv420p,' : ''}${vf}[v];[1:a]aresample=48000,apad,adelay=400|400[a]`,
    '-map', '[v]', '-map', '[a]', '-t', String(seconds),
    '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '20', '-pix_fmt', 'yuv420p', '-r', String(FPS),
    '-c:a', 'aac', '-b:a', '128k', '-ar', '48000', '-ac', '2', seg])
  segments.push(seg)
  layout.push({ id: beat.id, start: cursor, end: cursor + seconds })
  cursor += seconds
}

if (TITLE && !flag('no-title')) {
  card({ id: '00-title', caption: TITLE }, TITLE_S, null, true)
  console.log(`  card  ${'00-title'.padEnd(18)} ${TITLE_S.toFixed(1)}s  intro — "${TITLE}" / "${SUBTITLE}"${INTRO_BG ? ' (blurred first shot)' : ''}`)
}

// ─── diagram stills (Mermaid → PNG) ─────────────────────────────────────────
// A diagram beat has no clip: it is a rendered PNG (see diagrams.md). Fit it and never
// crop it — a cut-off table is worse than a small one — then a slow 1.05 push-in so the
// frame is alive for the length of the line, a small kind chip top-left so a viewer knows
// what they are looking at, and the caption in the same band as every other beat.
const DIAGRAM_CHIP = { architecture: 'ARCHITECTURE', concept: 'CONCEPT', erd: 'DATA MODEL' }

const still = (beat) => {
  const seconds = Math.max(6, voice[beat.id] + 1.8)
  const img = isAbsolute(beat.image) ? beat.image : join(OUT, beat.image)
  if (!existsSync(img)) throw new Error(`missing diagram render: ${img} — run scripts/render-diagrams.mjs (see diagrams.md)`)
  const seg = join(SEG, `${beat.id}.mp4`)
  const capt = join(CAPS, `${beat.id}.txt`)
  writeFileSync(capt, beat.caption ?? '')
  const dt = (path, opts) => `drawtext=fontfile=${FONT}:textfile=${path}:${opts}`
  const chip = DIAGRAM_CHIP[beat.diagram]
  let chipPath = ''
  if (chip) { chipPath = join(CAPS, `${beat.id}.chip.txt`); writeFileSync(chipPath, chip) }
  const zoom = beat.zoom === false ? null
    : `zoompan=z='min(zoom+0.0006,1.05)':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=1:s=${VW}x${VH}:fps=${FPS}`
  // Fit inside 92 % of the frame: a 1.05 push-in crops 2.4 % off each side, so without
  // the inset it would eat the outer entity's left border by the end of a long beat.
  const IN = 0.92
  const vf = [
    `scale=${Math.round((VW * IN) / 2) * 2}:${Math.round((VH * IN) / 2) * 2}:force_original_aspect_ratio=decrease`,
    `pad=${VW}:${VH}:(ow-iw)/2:(oh-ih)/2:color=${BG}`,
    zoom,
    chipPath ? dt(chipPath, `fontcolor=${ACCENT}:fontsize=22:box=1:boxcolor=black@0.55:boxborderw=12:x=44:y=36`) : null,
    beat.caption ? dt(capt, `fontcolor=white:fontsize=${FONTSIZE}:box=1:boxcolor=black@0.7:boxborderw=18:x=(w-text_w)/2:y=h-${FONTSIZE + 60}`) : null,
  ].filter(Boolean).join(',')
  run('ffmpeg', ['-y', '-loop', '1', '-framerate', String(FPS), '-i', img,
    '-i', join(TTS, `${beat.id}.norm.wav`),
    '-filter_complex', `[0:v]format=yuv420p,${vf}[v];[1:a]adelay=400|400,apad,aresample=48000[a]`,
    '-map', '[v]', '-map', '[a]', '-t', seconds.toFixed(2),
    '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '20', '-pix_fmt', 'yuv420p', '-r', String(FPS),
    '-c:a', 'aac', '-b:a', '128k', '-ar', '48000', '-ac', '2', seg])
  segments.push(seg)
  layout.push({ id: beat.id, start: cursor, end: cursor + seconds })
  cursor += seconds
  console.log(`  still ${beat.id.padEnd(18)} ${seconds.toFixed(1)}s · ${beat.diagram ?? 'image'} · ${beat.image}`)
}

for (const beat of beats) {
  if (beat.image) { still(beat); continue }
  if (!beat.segment) {
    const seconds = Math.max(6, voice[beat.id] + 1.8)
    card(beat, seconds, join(TTS, `${beat.id}.norm.wav`))
    console.log(`  card  ${beat.id.padEnd(18)} ${seconds.toFixed(1)}s`)
    continue
  }
  const seg = join(SEG, `${beat.id}.mp4`)
  const clip = beat.durationMs / 1000
  // A beat runs for as long as its narration needs, plus a short tail: `clip` is
  // only the capture's hold window, so its excess (a second or two of a motionless
  // screen after the action) is dropped rather than left as dead air. When the line
  // outruns the clip, the last frame is frozen (tpad below) so the voice can finish;
  // a freeze longer than ~1 s means the narration is too long for its clip and the
  // storyboard should be re-cut, not that this bound should change.
  // The line itself is never truncated: `total` must cover it, and `-t` below uses
  // `total`, so a min() against the clip here would cut speech mid-word.
  const total = Math.max(6, voice[beat.id] + 1.5)
  const freeze = Math.max(0, total - clip)

  // box coordinates are viewport CSS pixels; scale if the frame differs
  const raw = dimsOf(beat.segment)
  // Box coordinates are viewport CSS pixels; the scale filter below normalises every
  // clip to VW×VH, so a rect only needs the viewport→output ratio. Using the raw
  // frame size here inverted that correction for a clip captured at a different
  // resolution than the viewport (a 1280×720 re-record for a 1600×900 viewport put
  // its box at 80% of the right position).
  const sx = VW / (beat.viewportW || raw.w)
  const sy = VH / (beat.viewportH || raw.h)
  const box = beat.rect
    ? { x: Math.round(beat.rect.x * sx), y: Math.round(beat.rect.y * sy), w: Math.round(beat.rect.w * sx), h: Math.round(beat.rect.h * sy) }
    : null

  const vf = [
    `scale=${VW}:${VH}:force_original_aspect_ratio=decrease,pad=${VW}:${VH}:(ow-iw)/2:(oh-ih)/2:color=${BG}`,
    box ? `drawbox=x=${box.x}:y=${box.y}:w=${box.w}:h=${box.h}:color=${beat.boxColor ?? '#22C55E'}@1:t=5` : null,
    beat.caption ? `drawtext=fontfile=${FONT}:textfile=${CAPS}/${beat.id}.txt:fontcolor=white:fontsize=${FONTSIZE}:box=1:boxcolor=black@0.7:boxborderw=18:x=(w-text_w)/2:y=h-${FONTSIZE + 60}` : null,
    freeze > 0.05 ? `tpad=stop_mode=clone:stop_duration=${(freeze + 1).toFixed(2)}` : null,
  ].filter(Boolean).join(',')

  run('ffmpeg', ['-y', '-i', beat.segment, '-i', join(TTS, `${beat.id}.norm.wav`),
    '-filter_complex', `[0:v]${vf}[v];[1:a]adelay=400|400,apad,aresample=48000[a]`,
    '-map', '[v]', '-map', '[a]', '-t', total.toFixed(2),
    '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '20', '-pix_fmt', 'yuv420p', '-r', String(FPS),
    '-c:a', 'aac', '-b:a', '128k', '-ar', '48000', '-ac', '2', seg])
  console.log(`  seg   ${beat.id.padEnd(18)} ${clip.toFixed(1)}s → ${total.toFixed(1)}s${freeze > 0.05 ? ` (+${freeze.toFixed(1)}s hold)` : ''}${box ? ` · box ${box.w}x${box.h}@${box.x},${box.y}` : ''}`)
  segments.push(seg)
  layout.push({ id: beat.id, start: cursor, end: cursor + total })
  cursor += total
}

const list = join(OUT, 'concat.txt')
writeFileSync(list, segments.map((f) => `file '${f}'`).join('\n') + '\n')
const final = join(OUT, `${SLUG}${MUSIC ? '-nomusic' : ''}.mp4`)
run('ffmpeg', ['-y', '-f', 'concat', '-safe', '0', '-i', list, '-c', 'copy', '-movflags', '+faststart', final])
const meta = {
  slug: SLUG, title: TITLE, subtitle: SUBTITLE, file: final, durationS: durationOf(final),
  width: VW, height: VH, fps: FPS, beats: layout,
}
// both: video.json keeps the familiar name, <slug>.video.json stays unambiguous when
// several variants are composed into one directory
writeFileSync(join(OUT, 'video.json'), JSON.stringify(meta, null, 2))
writeFileSync(join(OUT, `${SLUG}.video.json`), JSON.stringify(meta, null, 2))
console.log(`\n✅ ${final}  ${durationOf(final).toFixed(1)}s\n   boundaries → ${join(OUT, 'video.json')}`)

if (MUSIC) {
  const withMusic = join(OUT, `${SLUG}.mp4`)
  run('bash', [join(import.meta.dirname, 'add-music.sh'), '--video', final, '--music', MUSIC, '--out', withMusic], { stdio: 'inherit' })
  console.log(`✅ ${withMusic} (bed mixed)`)
}
