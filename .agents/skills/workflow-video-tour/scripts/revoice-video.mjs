#!/usr/bin/env node
// revoice-video.mjs — re-voice a FINISHED video without re-capturing.
//
// The captions and annotation boxes are already burned into the source video, so
// all that changes is the audio: cut the source at the recorded beat boundaries
// (video.json), fit each beat to its new narration, mux, concat.
//
// Because the new narration is usually a different length, the resulting video is a
// different length: this script writes `<slug>.video.json` with the NEW beat
// boundaries. Pass THAT file to verify-video.sh — the source's video.json describes
// the old timing and will make the box checks sample the wrong frames.
//
// Usage:
//   revoice-video.mjs --source out/slug-nomusic.mp4 --video-json out/video.json \
//     --tts out/tts-v2 --out out --slug slug-v2
import { execFileSync } from 'node:child_process'
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'

const argv = process.argv.slice(2)
const arg = (n, d) => { const i = argv.indexOf(`--${n}`); return i >= 0 && argv[i + 1] && !argv[i + 1].startsWith('--') ? argv[i + 1] : d }

const SOURCE = arg('source')
const VIDEO_JSON = arg('video-json')
const TTS = arg('tts')
const OUT = arg('out', '.')
const SLUG = arg('slug', 'revoice')
const FPS = Number(arg('fps', '30'))
if (!SOURCE || !VIDEO_JSON || !TTS) throw new Error('usage: revoice-video.mjs --source s.mp4 --video-json video.json --tts dir --out dir --slug name')

const meta = JSON.parse(readFileSync(VIDEO_JSON, 'utf8'))
const SEG = join(OUT, 'seg-revoice')
mkdirSync(SEG, { recursive: true })

const run = (cmd, args) => execFileSync(cmd, args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] })
const durationOf = (f) =>
  Number(run('ffprobe', ['-v', 'error', '-show_entries', 'format=duration', '-of', 'default=nw=1:nk=1', f]).trim())

const segments = []
const layout = []
let cursor = 0

for (const beat of meta.beats) {
  const raw = join(TTS, `${beat.id}.wav`)
  // The title card has no narration by design — handle it BEFORE the existence check,
  // or it gets silently dropped and the video opens on beat 1.
  if (beat.id === '00-title') {
    const slice = beat.end - beat.start
    const seg = join(SEG, `${beat.id}.mp4`)
    run('ffmpeg', ['-y', '-ss', String(beat.start), '-t', String(slice), '-i', SOURCE, '-an',
      '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '20', '-pix_fmt', 'yuv420p', '-r', String(FPS), seg])
    const withAudio = join(SEG, `${beat.id}-a.mp4`)
    run('ffmpeg', ['-y', '-i', seg, '-f', 'lavfi', '-i', 'anullsrc=r=48000:cl=stereo', '-shortest',
      '-map', '0:v', '-map', '1:a', '-c:v', 'copy', '-c:a', 'aac', '-b:a', '128k', '-ar', '48000', '-ac', '2', withAudio])
    segments.push(withAudio)
    layout.push({ id: beat.id, start: cursor, end: cursor + slice })
    cursor += slice
    console.log(`  card  ${beat.id.padEnd(18)} ${slice.toFixed(1)}s (kept)`)
    continue
  }
  if (!existsSync(raw)) { console.log(`  skip ${beat.id} (no narration at ${raw})`); continue }
  const norm = raw.replace(/\.wav$/, '.norm.wav')
  run('ffmpeg', ['-y', '-i', raw, '-af', 'loudnorm=I=-16:TP=-1.5:LRA=11', '-ar', '48000', '-ac', '1', norm])
  const narr = durationOf(norm)
  const slice = beat.end - beat.start
  const total = Math.max(6, Math.min(slice, narr + 1.5))
  const freeze = Math.max(0, Math.max(6, narr + 1.5) - slice)
  const seg = join(SEG, `${beat.id}.mp4`)

  run('ffmpeg', ['-y', '-ss', String(beat.start), '-t', String(slice), '-i', SOURCE, '-i', norm,
    '-filter_complex', `[0:v]tpad=stop_mode=clone:stop_duration=${(freeze + 1).toFixed(2)}[v];[1:a]adelay=400|400,apad,aresample=48000[a]`,
    '-map', '[v]', '-map', '[a]', '-t', total.toFixed(2),
    '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '20', '-pix_fmt', 'yuv420p', '-r', String(FPS),
    '-c:a', 'aac', '-b:a', '128k', '-ar', '48000', '-ac', '2', seg])
  console.log(`  seg   ${beat.id.padEnd(18)} slice ${slice.toFixed(1)}s · narration ${narr.toFixed(1)}s → ${total.toFixed(1)}s${freeze > 0.05 ? ` (+${freeze.toFixed(1)}s hold)` : ''}`)
  segments.push(seg)
  layout.push({ id: beat.id, start: cursor, end: cursor + total })
  cursor += total
}

const list = join(OUT, 'concat-revoice.txt')
writeFileSync(list, segments.map((f) => `file '${f}'`).join('\n') + '\n')
const final = join(OUT, `${SLUG}.mp4`)
run('ffmpeg', ['-y', '-f', 'concat', '-safe', '0', '-i', list, '-c', 'copy', '-movflags', '+faststart', final])
// The boundaries moved: write them next to the new video so V5/V7 measure the right frames.
// (The title card is kept above, so the intro survives a re-voice.)
const outJson = join(OUT, `${SLUG}.video.json`)
writeFileSync(outJson, JSON.stringify({
  ...meta, file: final, durationS: durationOf(final), beats: layout,
}, null, 2))
console.log(`\n✅ ${final}  ${durationOf(final).toFixed(1)}s`)
console.log(`   boundaries → ${outJson}   (pass this to verify-video.sh, not the source's video.json)`)
if (Math.abs(meta.durationS - durationOf(final)) > 1) {
  console.log(`   ! length changed ${meta.durationS.toFixed(1)}s → ${durationOf(final).toFixed(1)}s: re-run` +
    ` the avatar (its cues are cut against the mix) and verify with the new boundaries`)
}
