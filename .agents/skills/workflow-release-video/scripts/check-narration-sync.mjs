#!/usr/bin/env node
// check-narration-sync.mjs — fail if timeline.json and storyboard.json disagree on
// anything a viewer hears or reads.
//
// Why this exists: `capture-beats.mjs` copies each beat into `timeline.json`, and
// `tts-phonon.py` and `compose-video.mjs` both read the *timeline*. Editing a narration,
// caption, divider heading, bullet or footer in `storyboard.json` after a capture is
// therefore invisible to the render — the first build of this release shipped audio that
// was one revision behind the storyboard for 11 of 19 beats, and the only thing that
// caught it was an ASR pass outside the cage.
//
// Run it before `tts-phonon.py` and again before `compose-video.mjs`:
//
//   node scripts/check-narration-sync.mjs storyboard.json timeline.json \
//     && node scripts/sync-timeline-from-storyboard.mjs storyboard.json timeline.json
import {readFileSync} from "node:fs";

const [, , storyPath, timelinePath] = process.argv;
if (!storyPath || !timelinePath) {
  console.error("usage: check-narration-sync.mjs <storyboard.json> <timeline.json>");
  process.exit(2);
}

// Everything a viewer hears or reads. Geometry and capture measurements are deliberately
// excluded — those belong to the timeline, and the storyboard is not their source.
const SPOKEN_OR_SHOWN = ["narration", "caption", "heading", "bullets", "footer"];

const story = JSON.parse(readFileSync(storyPath, "utf8"));
const timeline = JSON.parse(readFileSync(timelinePath, "utf8"));
const recorded = new Map(timeline.map((beat) => [beat.id, beat]));

const drift = [];
const missing = [];
for (const beat of story.beats) {
  const got = recorded.get(beat.id);
  if (!got) {
    missing.push(beat.id);
    continue;
  }
  for (const key of SPOKEN_OR_SHOWN) {
    const want = JSON.stringify(beat[key] ?? null);
    if (JSON.stringify(got[key] ?? null) !== want) {
      drift.push(`${beat.id}.${key}\n    storyboard: ${beat[key]}\n    timeline:   ${got[key]}`);
    }
  }
}

for (const id of missing) console.error(`✗ ${id}: in the storyboard, never captured`);
for (const d of drift) console.error(`✗ drift ${d}`);

if (missing.length || drift.length) {
  console.error(
    `\n✗ ${missing.length} uncaptured beat(s), ${drift.length} drifted field(s).\n` +
      "  The render reads timeline.json: sync it from the storyboard and RE-RENDER the\n" +
      "  narration before composing, or the video will speak the old text."
  );
  process.exit(1);
}
console.log(`✅ ${story.beats.length} beats: timeline narration matches storyboard.json`);
