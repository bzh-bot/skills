#!/usr/bin/env node
// sync-timeline-from-storyboard.mjs — refresh the narrative fields of every beat in
// timeline.json from storyboard.json, keeping the capture measurements.
//
// `storyboard.json` is the source of truth for what a beat SAYS; `timeline.json` is
// the record of what was RECORDED (segment, durationMs, rect, framesPushed, the
// frame/viewport geometry). The TTS and compose steps read the timeline, not the
// storyboard — so editing a narration or caption in the storyboard after a capture
// silently has no effect on the rendered video. This copies the narrative fields
// across and reports what it changed.
//
// Usage: node sync-timeline-from-storyboard.mjs <storyboard.json> <timeline.json>
import {readFileSync, writeFileSync} from "node:fs";

const [, , storyPath, timelinePath] = process.argv;
if (!storyPath || !timelinePath) {
  console.error("usage: sync-timeline-from-storyboard.mjs <storyboard.json> <timeline.json>");
  process.exit(2);
}

// Narrative fields only. Everything else in the timeline is a capture measurement.
const NARRATIVE = [
  "chapter",
  "phase",
  "source",
  "route",
  "url",
  "readyText",
  "click",
  "click2",
  "box",
  "boxColor",
  "holdMs",
  "caption",
  "narration",
  "heading",
  "bullets",
  "footer",
];

const story = JSON.parse(readFileSync(storyPath, "utf8"));
const timeline = JSON.parse(readFileSync(timelinePath, "utf8"));
const byId = new Map(timeline.map((beat) => [beat.id, beat]));

const changed = [];
const synced = story.beats.map((beat) => {
  const recorded = byId.get(beat.id);
  if (!recorded) throw new Error(`storyboard beat ${beat.id} was never captured`);
  const merged = {...recorded};
  for (const key of NARRATIVE) {
    const next = JSON.stringify(beat[key]);
    if (key === "phase" && beat[key] === undefined) continue; // keep a captured phase
    if (JSON.stringify(recorded[key]) !== next) changed.push(`${beat.id}.${key}`);
    if (beat[key] === undefined) delete merged[key];
    else merged[key] = beat[key];
  }
  return merged;
});

writeFileSync(timelinePath, JSON.stringify(synced, null, 2) + "\n");
console.log(
  changed.length
    ? `synced ${new Set(changed.map((c) => c.split(".")[0])).size} beat(s); fields updated:\n  ` +
        changed.join("\n  ")
    : "timeline already matches the storyboard"
);
