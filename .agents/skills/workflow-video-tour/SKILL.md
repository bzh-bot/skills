---
name: workflow-video-tour
version: 2.3.0
description: "workflow-do-tour sub-skill — phases V1–V7 (Storyboard + mandatory Mermaid diagrams; Screencast Capture; Narration; Assemble; Avatar; Music; Verify & Attach). Turns the guided tour into a 45–75 s narrated MP4 that opens on the ticket's motivation IN THE REPORTER'S WORDS — what is broken or missing, who is affected, what it costs — then the concept/architecture diagram, an ERD whenever the change touches the data model, BEFORE, AFTER, guard, close — voiced by an energetic Australian engineer with a lightly humorous script, an animated mascot in the corner, and a licensed music bed; placed at the top of the PR body. Diagrams are rendered from .mmd with mermaid-cli and are not optional; a motivation beat that is missing, misordered, empty or generic is refused at capture time. Loaded by the tour worker (workflow-do-tour P7.8). Not invoked directly."
---

# Video tour (V1–V7)

## What this is

A **45–75 s narrated screen recording a reviewer watches instead of reading the
diff.** It tells one story, in order: the ticket (intro card) → **the problem, in the
reporter's own words** → **the system and the data (two Mermaid diagrams)** → the pain
BEFORE → the fix AFTER → the one guard that matters → close. The voice is an energetic
Australian engineer; a small animated mascot sits in the corner over a quiet licensed
instrumental bed. Fast and funny-but-precise, never salesy; motion comes from real
clicks, smooth scrolls and the avatar, not from effects.

**Every video opens on the motivation, not on architecture.** The first narrated beat
after the intro card is a `kind: "motivation"` card that states, in the words the
reporter used in the ticket, what is broken or missing, who is affected and what the
impact is. Nothing technical — no diagram, no code, no screen — may come before it. An
architecture diagram as the opening beat explains *how* to a viewer who has not yet been
given a reason to care, in engineering language the reporter would not recognise; that
is the regression this contract exists to stop. The wording is copied from the ticket,
not paraphrased: `quote` is the reporter's sentence, and the spoken line has to reuse it.
**`capture-beats.mjs` refuses a storyboard whose motivation beat is missing, not first,
empty, generic, or silent on the symptom / the affected party / the impact — and there
is no waiver flag.** See `steps/1-storyboard.md` → "The motivation beat".

**The diagrams are mandatory, not garnish.** A viewer who has not read the diff cannot
understand a 20-second change from a screenshot of one page. So every tour carries a
**concept/architecture** diagram before the first filmed beat, and an **ERD of the tables
the change reads or writes** whenever the change touches the data model (migration, new
table/column/index, a session or interval entity, a report query). They are authored as
`.mmd`, rendered to PNG with mermaid-cli, looked at, and then referenced from the
storyboard — **`diagrams.md`** is the contract; `capture-beats.mjs` refuses a storyboard
that breaks it.

**The change is not always a UI.** Migrations, RLS/policies, middleware, routes, jobs,
webhooks and emails have no screenshot — for those the video films the *tool that makes
the change visible* (DB console, code diff, API client, mail catcher, spreadsheet,
log/metrics surface). Read **`non-ui-evidence.md`** at V1 and V2 whenever the diff is not
purely visual: it maps change class → surface → what to show, and states the security and
design points that must be narrated for backend work.

You are the tour worker that just ran P6/P7: the app, the DB and the signed-in
Chrome are still up. Run V1–V7 now; the video is a deliverable, not a nicety.

## Contract

**IN** (already in your P6/P7 state): `TICKET_ID TICKET_URL PR_NUMBER PR_URL
ORG REPO_NAME FEATURE_TAG WORKTREE SCREENSHOTS_DIR CHROME_SESSION
CHROME_SESSION_PROFILE`, the 5-element brief + acceptance criteria, the dev-server
URLs and whatever re-drives the BEFORE/AFTER states.

**OUT** — append to `/tmp/workflow-run.env`:

```bash
VIDEO_PATH="$VIDEO_DIR/<slug>.mp4"   VIDEO_ATTACHED="1"   VIDEO_DURATION_S="<n>"
VIDEO_NARRATION="qwen3-design/engineer"  VIDEO_AVATAR="mascot|pil|none"  VIDEO_MUSIC="<track|none>"
VIDEO_DIAGRAMS="<n> (concept/architecture + erd when touchesDataModel)"
VIDEO_MOTIVATION="<beat-id> — <the reported symptom, ≤8 words>"   # beat 1, from the ticket
VIDEO_SKIP_NOTE=""                   # only when the human authorised a skip
```

## Phases

| phase | doc | output |
|---|---|---|
| V1 Storyboard + diagrams | `steps/1-storyboard.md`, `diagrams.md` | `storyboard.json`, `diagrams/*.mmd` + `diagrams/png/*.png` |
| V2 Capture | `steps/2-capture.md` | `seg/*.mp4`, `timeline.json` |
| V3 Narration | `steps/3-narration.md` | `tts/*.wav` |
| V4 Assemble | `steps/4-assemble.md` | `<slug>.mp4` (intro card + beats, boxes + captions burned in) |
| V5 Avatar | `steps/5-avatar.md` | `<slug>-avatar.mp4` |
| V6 Music | `steps/6-music.md` | `<slug>-final.mp4` |
| V7 Verify & attach | `steps/7-verify-attach.md` | PR body updated, OUT vars |

Read a step's doc right before running it. Each starts with the command and
ends with the checks. `**→ TaskUpdate: V<n> → in_progress / completed**` around
each.

## Rules

- **Beat 1 is the motivation, in the reporter's words.** The first narrated beat after
  the intro card is `kind: "motivation"` with `quote` (the ticket's own sentence),
  `reportedSymptom`, `affected`, `impact` and a 12–28 word `narration` that names all
  three in the ticket's vocabulary. Copy the wording out of the ticket — do not translate
  "finance has no idea the money arrived" into "notification gap in the billing flow".
  `capture-beats.mjs` refuses the capture (exit 2, no waiver) when the beat is absent, not
  first, empty, generic, or never mentions the symptom / who is affected / the impact;
  `compose-video.mjs` renders it as a `WHY THIS EXISTS` card with the verbatim quote and
  warns loudly if a timeline it is given opens on technical detail. (`steps/1-storyboard.md`.)
- **Work in `$VIDEO_DIR=$WORKTREE/.workflow-video`, never `/tmp`** (a tmp-cleaner
  wiped a run mid-flight). Keep every artefact — storyboard, timeline, raw
  segments, WAVs — so a re-cut or re-voice is one command.
- **Capture the live page (`agent-browser stream`), never `agent-browser record`** —
  `record` re-creates the browser context and films a `/login` redirect.
- **Bring the demo tools up before the non-UI beats, and gate on them.**
  `scripts/demo-tools.sh up` (CloudBeaver for DB/schema, Hoppscotch for API, both
  self-hosted in the cage), then `demo-tools.sh require` before filming. A custom results
  table, a styled HTML page or pretty-printed `curl` is a failed beat when the real tool is
  available; Google Sheets needs the signed-in profile or an explicit question to the user.
  (`non-ui-evidence.md`.)
- **Diagrams are part of the video, not an appendix.** V1 writes the `.mmd`, renders it
  with `scripts/render-diagrams.mjs`, **looks at the PNG**, and puts the beat **before**
  the first filmed beat (concept/architecture) and **before** the first BEFORE beat (ERD).
  The order is fixed: intro card → motivation → concept/architecture → ERD → BEFORE →
  AFTER → guard → close. A storyboard without them is refused at capture time;
  `--allow-no-diagrams` only on a human's explicit say-so, and then the PR body says why.
  (`diagrams.md`.)
- **Prove headless changes in the real tool.** A migration, route, permission or email is
  filmed in the tool that shows it — **CloudBeaver** for schema/rows, **Hoppscotch** for
  API requests, **Google Sheets** for spreadsheet/export beats (login gate), Mailpit for
  mail, a log/metrics surface for jobs — never narrated over an unrelated app screen.
  **Never** a hand-built results table, a custom HTML page or pretty-printed `curl`: those
  are not evidence. `scripts/demo-tools.sh up` self-hosts CloudBeaver + Hoppscotch in the
  cage, pre-configures the run's own DB and API base, and records the URLs in
  `$VIDEO_DIR/demo-tools.json`; `demo-tools.sh require` is the gate. If the tools cannot
  run, stop and ask — do not substitute. Say in the PR body which surface you used, and
  stop extra containers afterwards. (`non-ui-evidence.md`.)
- **Backend beats carry their implications.** When the diff is backend/auth, the narration
  names the security consequence (authn vs authz, tenant scoping, validation, rate limits,
  PII) and the design choice a reviewer would ask about (idempotency, transactions,
  indexes, back-compat, rollback). One sentence each — not a lecture.
- **Narration is data.** Copy lives in `storyboard.json`; scripts never invent text.
- **Default voice: `--mode custom --speaker Ryan --stable --instruct ""`** (qwen3
  CustomVoice; Aiden is the second choice, both are the English-native presets). The
  empty `--instruct` is load-bearing — omitting it silently colours the delivery with
  the Australian-engineer persona. Clone mode only when the human supplies a voice
  asset; design mode only as an auditioning tool, never per-video. (`steps/3-narration.md`.)
  Other backends (kokoro/piper) only when a human has explicitly chosen them.
- **Default avatar: `assets/avatar.svg`**, animated (Rhubarb mouth + blink + a
  gentle bob). Fall back to `pil` or none only when asked — and say so in the
  PR body.
- **Music is always on and always licensed** (`steps/6-music.md`). Attribution
  goes in the PR body when the licence asks for it.
- **Never attach an unverified video.** `scripts/verify-video.sh` first, then
  **look at the contact sheet it writes** — a colour test proves a box was drawn,
  not that it is on the right element.
- **Annotations for the video's stills/screenshots are drawn IN THE PAGE — no ImageMagick
  fallback.** The capture path injects `workflow-do/scripts/annotate.js` into the live DOM,
  so the overlay is in the same frames the video uses and in the P7 screenshots. A captured
  PNG is never painted afterwards, and there is no "re-annotate the image" escape hatch: if
  the layer cannot mount (the page blocks injected styles, the target does not resolve, the
  wrong tab is pinned) the annotation **fails** and the stage reports it — recapture with
  `workflow-do/scripts/annotate-shot.sh`, then gate with `check-annotations.sh`. ImageMagick
  remains only for the contact-sheet montage and the box-landed pixel sampling in
  `verify-video.sh`, never for drawing.
- **Iterate cheaply:** re-record one beat with `--only`, re-voice with
  `revoice-video.mjs`, preview the avatar alone — never re-run the whole chain
  to fix one thing.

## Files

```
SKILL.md                 this file
phases.json              V1–V7 for the workflow-do phase table
non-ui-evidence.md       change class → browser surface (schema, code diff, API, mail, logs),
                         what to show and what to narrate — REQUIRED when the diff is not UI-only
diagrams.md              the diagram contract: which diagrams are mandatory, where the
                         .mmd sources live, the deterministic render, the visual check,
                         beat ordering, and the narration recipe for each diagram kind
settings.example.env     every knob, at its shipped default
storyboard.example.json  the PR-290 storyboard (motivation + architecture + ERD + 6 beats, 79 s)
steps/1..7-*.md          one doc per phase: command → what it does → checks → traps
prompts/narration.md     ticket + PR + tour → storyboard.json (title, subtitle, beats)
prompts/avatar-svg.md    brief/photo → a custom avatar.svg (optional, image-capable agent)
assets/
  avatar.svg             the mascot presenter (9 visemes + a blink pair)   ← V5 default
  music/house.mp3        the CC0 bed + .txt provenance line                ← V6 default
  voice/aiden-narration.md  the approved narrator (Aiden + per-beat clauses) ← V3 default
  voice/voice.wav        the frozen AU-engineer reference for clone mode + .txt transcript
  voice/cues.sample.json 15-cue fixture for smoke-testing the frames script
  SOURCES.md             provenance of everything above (no personal media)
scripts/
  setup-mermaid.sh       V1  install the pinned mermaid-cli (mmdc) into a WRITABLE prefix
                             (<worktree>/.video-tools or $VIDEO_TOOLS_DIR; never assume
                             ~/.local/share in the cage) + no bundled Chromium
  render-diagrams.mjs    V1  every diagram beat → diagrams/png/*.png, deterministic; --check;
                             fails with the paths it searched when mmdc is missing
  demo-tools.sh          V2  self-host the real demo tools in the cage (CloudBeaver, Hoppscotch),
                             seed the run's DB + API base, record URLs, gate with `require`
  capture-beats.mjs      V2  storyboard → seg/*.mp4 + timeline.json (fake cursor, ripple, box modes);
                             validates the diagram contract and passes stills through
  tts-qwen3.py           V3  clone|design|custom, --stable, per-beat instruct
  tts-kokoro.py          V3  Kokoro-82M, CPU                            (fallback)
  tts-piper.sh           V3  Piper, instant                             (draft)
  voice-stats.py         V3  per-beat pitch picture (F0 spread)
  voice-identity.py      V3  **is it the same speaker in every beat?** LPC formants + LTAS cosine
  make-reference-clip.sh V3  recording → loudnormed ref WAV + transcript
  compose-video.mjs      V4  intro card + segments + narration → mp4 (+ video.json)
  revoice-video.mjs      V4  swap narration on a finished mp4
  avatar/avatar-visemes.sh    V5 Rhubarb cues from the finished mix
  avatar/avatar-svg-frames.py V5 avatar.svg + cues → RGBA frames, mouth + blink (default)
  avatar/avatar-overlay.sh    V5 frames onto the video, above the caption band (+ bob)
  avatar/avatar-render.py     V5 alternative: drawn person from appearance.json
  avatar/avatar-headshot.py   V5 alternative: headshot → appearance.json
  add-music.sh           V6  ducked instrumental bed
  verify-video.sh        V7  codecs, loudness, dead air, boxes landed
```

## Verified end-to-end

2026-10-19 — the motivation contract: six fixture storyboards through
`capture-beats.mjs` (all with a valid diagram contract) — the passing case exits 0; no
motivation beat, motivation after the architecture diagram, empty `quote`/`narration`, a
generic engineering line, and a line that never names who is affected all exit 2 with the
reason named. `compose-video.mjs` renders the card: extracted frame at the beat midpoint
shows the `WHY THIS EXISTS` chip at the accent colour and the quoted line in white, and
`video.json` orders `00-title → m-motivation → filmed beats`. Also verified:
`setup-mermaid.sh` installing mmdc 12.0.0 into a worktree-local `.video-tools` (not
`~/.local/share`), `render-diagrams.mjs` rendering from that prefix with `HOME` pointed at
an empty dir, `--check` passing, and `--check` failing on a `.mmd` edited after render.

2026-10-16 — diagram path: `setup-mermaid.sh` (mmdc 12.0.0, system Chrome),
`render-diagrams.mjs` (3200 px landscape ERD + architecture flowchart, byte-identical
across two renders), the capture gate (missing ERD and misordered ERD both refused with
exit 2), `capture-beats.mjs --only <still>` (no browser touched), and `compose-video.mjs`
still beats (fit + 1.05 push-in + kind chip + caption band; confirmed on an extracted
frame at maximum zoom that nothing is cropped).

2026-09-30, on the PR-290 segments (81 s of live 1600×900 capture, six beats):
`compose-video.mjs` (4 s intro card + boxes + captions) → `add-music.sh` (CC0 bed,
mean −21.5 dB) → `verify-video.sh` (all five boxes landed, no stray silence) →
`avatar-visemes.sh` (356 cues) → `avatar-svg-frames.py` (2427 frames from 18
states = 9 visemes × blink, 23 blinks) → `avatar-overlay.sh` (240 px, above the
caption band, ±3 px bob). Also verified: the blink band differs open vs shut, and
the intro card renders title + subtitle correctly.
