---
name: workflow-release-video
version: 1.2.0
description: "Produce a ~4 minute narrated release video for a repository — repo-agnostic, driven by the merged PRs between the last git tag and now. Collect the release, open on the reported problem in the reporters' own words (beat 1, from the release's tickets/issues), plan 7–9 chapters, render the mandatory Mermaid diagrams (product architecture up front, an ERD per chapter that touches the schema), capture the app live, narrate with the approved Phonon voice (Easton), assemble with chapter cards + annotation boxes, and publish the MP4 to the GitHub Release. Reuses the workflow-video-tour engine (V1–V7) unchanged; adds a release collector, the motivation beat and a chaptered storyboard convention. Invoked directly, or by the chief of staff's release flow."
---

# Release video (R1–R7)

## What this is

A **three-and-a-half to four-and-a-half minute narrated walkthrough of one release**:
what was broken, what shipped, why anyone cares, and what it looks like now. Not a demo
of one PR — a tour of a release, chaptered by feature area, told in the same voice as the
PR video tours so a viewer who has watched one knows what they are getting.

The engine is **`workflow-video-tour` (V1–V7), unchanged** — motivation, diagrams,
capture, TTS, assemble, avatar, music, verify. This skill owns the five things that
differ for a release:

1. **Where the content comes from** — a release manifest (merged PRs since the last
   tag), not one ticket's acceptance criteria.
2. **The opening beat** — the problem the release answers, quoted from the tickets and
   issue reports it closes, before the architecture diagram (see **Motivation** below).
3. **The shape** — chapters with divider cards, ~15× more beats, sized to a real
   minute budget instead of "45–75 s or it is a recording".
4. **The diagrams** — one product **architecture** beat right after the motivation and
   before the first filmed beat, then an **ERD per chapter that touches the schema**,
   right after that chapter's divider. The tour's contract applies at this length too,
   and `capture-beats.mjs` enforces it (`diagrams.md`).
5. **Where it goes** — a GitHub **Release** asset, not the top of a PR body.

## Contract

**IN** — a repository and a range:

```
REPO=/path/to/repo          # any repo, any host; GitHub unlocks PR metadata
RELEASE_FROM=""             # tag/branch/sha; empty = newest reachable tag
RELEASE_TO="HEAD"
PRODUCT_NAME=""             # e.g. "Acme"; empty = derive from the repo name
APP_URL=""                  # the running app to film; empty = cards-only video
VIDEO_DIR=<REPO>/.release-video
```

**OUT** — `$VIDEO_DIR/`:

```
release-manifest.json  release-notes.md  storyboard.json  budget.json
seg/*.mp4  timeline.json  tts/*.wav  video.json  contact-sheet.png
diagrams/*.mmd  diagrams/png/*.png  diagrams/renders.json
<slug>-final.mp4        <slug>-chapters.txt
```

plus the MP4 uploaded to the GitHub Release, and its URL in `release-notes.md`
under `## Video`.

## The budget — do the arithmetic before writing a word of narration

A 4-minute video is not a 60-second video with more beats; the *rhythm* is different.
Target **230–260 s**, and check it twice: once at storyboard time (words ÷ 2.5), once
against the rendered voice (R4) — the rendered number is the only one that is true.

> ### `seconds ≈ total narration words / 2.5 + 44 + 2 × diagram beats`
>
> The `+44` is fixed overhead: 4 s of silent intro, ~1.8 s of tail on each of the ~9
> narrated cards, ~1.5 s on each of the ~16 filmed beats. It is worth memorising, because
> it is the whole reason a release video overshoots: **every extra word is 0.4 s, and 100
> extra words is 40 s — ten percent over, from nine beats that each ran a second long.**
> Diagram beats are cards (`voice + 1.8`): each costs its own words plus ~2 s, so the
> tail count and the word count both rise — **cut one filmed beat for every diagram beat
> you add**, or the video grows by ~10 s per diagram.

| section | count | how long | total |
|---|---|---|---|
| intro card | 1 | 4 s, silent | 4 s |
| motivation card (`kind: "motivation"`) | 1 | `22 words → 8.8 + 1.8 s` | 11 s |
| architecture diagram (`source: "image"`) | 1 | `20 words → 8.0 + 1.8 s` | 10 s |
| chapter ERDs (`source: "image"`, chapters that touch the schema) | 2 | `18 words → 7.2 + 1.8 s` | 18 s |
| chapter divider (`source: "static"`, narrated) | 8 | `20 words → 8.0 + 1.8 s` | 78 s |
| filmed beat | 13 | `20 words → 8.0 + 1.5 s` | 124 s |
| close card (`static`, bullets, narrated) | 1 | `8.0 + 1.8 s` | 10 s |
| **total** | **27 beats** | **~507 words** | **253 s (4:13)** |

The diagram rows AND the motivation row replace filmed beats one-for-one in this table;
their narration words
are inside the 500.

Rules that fall out of this:

- **7–9 chapters · 10–11 narrated cards · 13–17 filmed beats · 2–4 diagram beats ·
  26–30 narrated beats.** The motivation is card #1 and is inside those counts.
- **460–560 words of total narration** → 3:45 to 4:25. This is the number to count,
  not the per-beat number. The diagram lines are inside it.
- **18–24 words per narrated beat** (Easton measures ~3.0 words/s; digits spelled out
  are slow). At 20 words a filmed beat is 9.5 s, at 24 it is 11.1 s — either is fine, but
  you must multiply it out.
- **2 filmed beats per chapter.** Three is better if the chapter is the headline feature
  and you cut elsewhere; one means the chapter is not a chapter.
- **`holdMs >= narration + 2.2 s` on filmed beats.** `compose-video.mjs` drops clip
  excess but *freezes* the last frame when the line outruns the clip; a freeze over ~1 s
  means the storyboard is wrong. Re-cut the beat, never trim the speech.
- **The close is a card, not a beat.** `heading` + 2–4 `bullets` + `footer`.
- **One idea per chapter.** A chapter with a single small PR in it is noise — fold it
  into a final "Also in this release" chapter that the collector already flags for you
  in `groupingHints.smallAreas`.
- **A 3-minute video is a valid outcome.** If the manifest only supports 8 filmable
  moments, ship 3 minutes. Padding is the failure mode of release videos and it is
  invisible from the inside.

## Phases

| phase | doc | output |
|---|---|---|
| R1 Collect | `steps/1-collect.md` | `release-manifest.json`, `release-notes.md` |
| R2 Storyboard | `steps/2-storyboard.md` | `storyboard.json`, `budget.json` |
| R3 Capture | `steps/3-capture.md` | `seg/*.mp4`, `timeline.json` |
| R4 Narration | `steps/4-narration.md` | `tts/*.wav` + the measured budget |
| R5 Assemble | `steps/5-assemble.md` | `<slug>.mp4`, `video.json` |
| R6 Avatar + music | `steps/6-avatar-music.md` | `<slug>-final.mp4` |
| R7 Verify + publish | `steps/7-verify-publish.md` | release asset, chapters, `release-notes.md` |

Read a step's doc right before running it. Each starts with the command and ends with
the checks. **→ TaskUpdate: R<n> → in_progress / completed** around each.

R3–R7 delegate to the tour's steps; read
`~/.agents/skills/workflow-video-tour/steps/<n>-*.md` alongside them — this skill does
not restate the traps (there are twenty of them and they are all still live).

## Rules

**Inherited from `workflow-video-tour` — none of these are relaxed by length:**

- **The video opens on the reported problem, in the reporters' words.** Beat 1 is
  `kind: "motivation"` — `quote` (verbatim from the tickets/issues the release closes),
  `reportedSymptom`, `affected`, `impact`, `narration` — and nothing technical may come
  before it. Not the release theme (`"Billing, auth and faster sync"` is the intro
  subtitle), not the PR titles, not a paraphrase into engineering language. The wording
  comes from R1's manifest issues / release notes; if the release closes no reported
  problem, quote the closest real statement and say so — never invent a complaint.
  `capture-beats.mjs` refuses a storyboard whose motivation beat is missing, not first,
  empty or generic (exit 2, **no waiver**); `compose-video.mjs` draws it as a
  `WHY THIS EXISTS` card with the verbatim quote and its attribution. The contract is
  `workflow-video-tour/steps/1-storyboard.md` → "The motivation beat".

- **Diagrams are mandatory.** One product **architecture** `source: "image"` beat right
  after the motivation and before the first filmed beat, and an **ERD** for every chapter
  whose PRs touch the data model (migration, new table/column/index, session/interval
  entity, report query), placed right after that chapter's divider and before its filmed
  beats. Set `"touchesDataModel": true` on the storyboard; write the `.mmd` in
  `$VIDEO_DIR/diagrams/`, render with `scripts/render-diagrams.mjs`, **look at every PNG**,
  then put it in the cut. `capture-beats.mjs` refuses a storyboard that breaks this
  (`workflow-video-tour/diagrams.md`).

- **Work in `$VIDEO_DIR`, never `/tmp`** (a tmp-cleaner wiped a run mid-flight).
- **Capture the live page (`agent-browser stream`), never `agent-browser record`** —
  `record` re-creates the context and films a `/login` redirect.
- **Narration is data, and `storyboard.json` is its source — but the render reads `timeline.json`.**
  `capture-beats.mjs` copies each beat into `timeline.json`, and **both** `tts-phonon.py` and
  `compose-video.mjs` read the *timeline*. So a narration, caption or divider edit made in
  the storyboard **after** a capture is silently invisible: the render simply uses the old
  text, with no warning. This shipped one revision of stale audio on 11 of 19 beats in the
  first release video, and only a host-side ASR pass caught it.
  **Run `scripts/check-narration-sync.mjs` before TTS and again before compose**, and
  `scripts/sync-timeline-from-storyboard.mjs` to push the storyboard's spoken/shown fields
  across without touching capture geometry. Step 4 owns the detail.
- **Voice: `--voice Easton` on Phonon** (the same engine and voice as the tour). Phonon
  takes no style/speed input, so a beat's energy comes from its words; speaker
  identity is fixed by the voice value, so there is no drift to police at 26 beats.
- **Music: always on, always licensed.** Attribution into the release body.
- **Never publish an unverified video.** `verify-video.sh` first, then **look at the
  contact sheet it writes.**
- **Never descend to a fallback on your own.** If the GPU, the browser or the app is
  unavailable, STOP and ask — with the specific blocker, the options and their costs,
  and "fix the default" first.
- **Iterate cheaply:** re-record one beat with `--only`, re-voice with
  `revoice-video.mjs`, preview the avatar alone. At 26 beats a full re-run is 20+
  minutes, so `--only` is the difference between a good video and a mediocre one.

**New here:**

- **Non-UI beats use the real tools, at release scale too.** DB beats in CloudBeaver, API
  beats in Hoppscotch, spreadsheet beats in Google Sheets — `workflow-video-tour/scripts/demo-tools.sh up`
  once per cage, URLs from `$VIDEO_DIR/demo-tools.json`. A custom table/HTML page or
  pretty-printed `curl` is a failed beat when the tools are up, and `demo-tools.sh require`
  is the gate. At 26 beats this matters more, not less: a release video with three
  hand-formatted surfaces reads as marketing, not as a release.

- **Never invent a release item that is not in `release-manifest.json`.** If the video
  needs a story the manifest does not have, the release does not have it. Say so.
- **Film the previous release as BEFORE.** A release video's BEFORE state is the last
  release, so a second worktree on `$RELEASE_FROM` is the honest comparison — not a
  hand-built mock. Without one, drop the BEFORE framing and narrate the change instead.
- **Chapter titles come from the manifest, not from vibes.** `groupingHints.byArea`
  is what a chapter is made of; a chapter title must be a name the manifest supports.
- **`verify-video.sh` warns over 40 MB — that is expected at 4 minutes.** It is a WARN
  about GitHub *user-attachment* limits, and a release asset may be 2 GB. Read it, do
  not chase it. Do chase a >2× overshoot: lower the CRF or the FPS in R5.

## Files

```
SKILL.md                  this file
phases.json               R1–R7 for the workflow-do / chief of staff phase table
settings.example.env      every knob, at its shipped default
steps/1..7-*.md           one doc per phase: command → what it does → checks → traps
prompts/chapter-plan.md   release-manifest.json → chapters (areas, order, which PRs get a beat)
prompts/release-narration.md  chapters + manifest → the storyboard beats
scripts/
  collect-release.mjs          R1  last tag → HEAD → merged PRs → manifest + notes draft
  avatar-overlay-ranges.sh     R6  the mascot over the *card* beats only (see the docstring)
```

Diagrams are the tour's: `workflow-video-tour/scripts/setup-mermaid.sh` (install the
pinned mmdc once per worktree — it picks a **writable** prefix, `<worktree>/.video-tools`
by default or `$VIDEO_TOOLS_DIR`, because `~/.local/share` is root-owned inside the cage)
and `render-diagrams.mjs` (render every `source: "image"` beat deterministically,
`--check` in R3/R7, failing with the searched paths when the install is missing). The
contract is `workflow-video-tour/diagrams.md`.

Everything else is `~/.agents/skills/workflow-video-tour/`. Do not fork those scripts
into this directory — a fixed capture trap should fix both skills at once.

## Verified

R1 is verified against real repositories (tagged, untagged, shallow, stale, GitHub and
non-GitHub): `collect-release.mjs` refuses an empty range rather than emitting a
plausible-looking manifest of unrelated PRs, and reports `confidence: high|low` with
the filter mode it used. R2–R7 are the tour's paths, verified end-to-end on 2026-09-30
at 6 beats / 81 s; **the 4-minute sizing and the card-only avatar overlay are NOT yet
proven end-to-end** — budget an extra iteration on the first real run and expect the
narration to come in ±15 % off the 2.5 words/s estimate.
