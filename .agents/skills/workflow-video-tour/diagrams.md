# Mermaid diagrams — mandatory in every video tour

**Read this at V1 (storyboard) and again at V2 (render + capture).**

## Why

A reviewer watching a 60-second video has not read the diff. A screenshot of one page
cannot tell them *what the system is* or *what data the change touches* — so the first
half of a tour is usually spent guessing. Two rendered diagrams fix that in twelve
seconds: a high-level picture of the system, and the tables (or entities) the change
reads or writes.

**The diagrams are not the opening beat.** Before them comes the motivation — the problem
in the reporter's words, taken from the ticket (see `steps/1-storyboard.md` → "The
motivation beat"). A diagram explains the system to someone who now knows *why* it
matters; without that beat the viewer is asked to care about architecture before being
told what is broken.

They are **rendered from source**. A diagram drawn in a drawing tool cannot be
diffed, reviewed, or fixed in one character, and it silently drifts from the schema.
Mermaid is the only diagram language this skill uses — no hand-drawn SVG, no exported
whiteboard, no screenshot of a slide.

## What is required

| beat | `diagram` | when | job |
|---|---|---|---|
| intro concept / architecture | `concept` or `architecture` | **always**, immediately after the **motivation** beat and **before the first filmed (BEFORE) beat** | what the system is and how the idea works: actor → surface → worker → store, the request path, the event flow. `architecture` for backend / multi-service / infra / auth / job changes; `concept` for a domain or workflow idea. A video with both is fine; zero is not. |
| ERD | `erd` | whenever the change touches the data model — a migration, a new table/column/index, a **session or interval entity**, or a report query | the tables the change **reads and writes**, their keys, and the FK/cardinality the change (and its guard) depends on. In a chaptered release video, one ERD per chapter that touches the schema, right after that chapter's divider |

`touchesDataModel: true` in the storyboard is what makes the ERD mandatory. Set it from
the diff in V1, not from memory: does the change add/alter an entity, a session, an
interval, or the query behind a report? Then it is `true`.

**Fixed beat order for the whole video:**

```
intro card  →  MOTIVATION (reporter's words)  →  concept/architecture  →  ERD (if touchesDataModel)  →  BEFORE  →  AFTER  →  guard  →  close
```

The motivation is the problem; the diagrams are the system. Never reorder them to
"get to the point faster" — the point is unreadable without the picture, and the picture
is uninteresting without the problem. `capture-beats.mjs` checks the motivation first
(exit 2, no waiver) and the diagrams second, so a storyboard wrong in both places
reports the opening beat first.

## Where the sources live

```
$VIDEO_DIR/
  diagrams/
    d1-architecture.mmd      ← the source, one per diagram beat, named after the beat id
    d2-erd.mmd
    png/
      d1-architecture.png    ← the render the video uses
      d2-erd.png
    renders.json             ← hashes + dims + mmdc version (written by the script)
    .render/                 ← generated puppeteer/mermaid/css config (never hand-edited)
```

- In `$VIDEO_DIR` (the worktree's `.workflow-video`), **never `/tmp`** — the sources belong
  with the video, and V7 copies them to the PR's screenshots dir so a reviewer can read
  them after the video.
- **File name = beat id.** Beat ids are stable across a re-cut; that is what lets
  `--only <id>` re-render or re-record exactly one diagram.
- Never edit `png/` by hand. Edit the `.mmd` and re-render.

## Layout rules for a 16:9 frame

- **Landscape.** Put `direction LR` in every `erDiagram` and `flowchart`. A portrait
  diagram is fitted to the frame, lands at ~28 % scale, and is unreadable — the render
  script fails it.
- **≤ 6 entities / ≤ 8 nodes / ≤ 12 edges** per diagram. Two readable diagrams beat one
  wall of boxes; split it.
- **Real names from the diff**, not pet names: `billing_notification`, `invoice_id`,
  `interval_start`. A reviewer maps the diagram onto the migration by name.
- **Highlight the change, mute the rest.** Give the table/node the change touches a
  `classDef`/`style` in the accent colour `#38BDF8` (and its edge `stroke:#38BDF8`);
  everything else stays default. The diagram shows what the change *reads or writes*, not
  the whole schema.
- **No prose in nodes** ("handles the events after payment…") — that is the narration's
  job. Node labels are names, edge labels are verbs (`raises`, `owns`, `writes`).
- No emoji or exotic unicode in labels: they render as tofu boxes at 1600×900.

## Render — command and deterministic settings

Install once per machine or worktree (mmdc is **not** on `PATH` by default, and a global npm
install drifts between runs):

```bash
S=~/.agents/skills/workflow-video-tour
bash $S/scripts/setup-mermaid.sh
#   → <worktree>/.video-tools/mermaid-cli   (pinned @mermaid-js/mermaid-cli 12.0.0)
#   or $VIDEO_TOOLS_DIR/mermaid-cli when you set VIDEO_TOOLS_DIR
#   or $MERMAID_CLI_PREFIX when you name one explicitly
```

**The prefix is chosen from WRITABLE locations, worktree first.** Inside the workflow cage
`~/.local/share` is **root-owned**, so the old default install there failed with `EACCES`
and a live run (2026-10-19) had to vendor mermaid-cli into the worktree by hand mid-tour.
The installer now:

1. honours `MERMAID_CLI_PREFIX` (must be writable),
2. then `$VIDEO_TOOLS_DIR/mermaid-cli`,
3. then `<worktree>/.video-tools/mermaid-cli` (`$WORKTREE`, else the git toplevel of `$PWD`),
4. and only then `~/.local/share/mermaid-cli`, and only if it is writable.

It records the chosen prefix in `$VIDEO_TOOLS_DIR/mermaid-cli.path`, so
`render-diagrams.mjs` resolves the **same** install (it also walks up from `$VIDEO_DIR`
looking for `.video-tools/mermaid-cli`, and honours `MMDC=/path/to/mmdc`). When nothing is
found it fails with the full list of paths it tried and the exact install command — never
silently rendering with a different binary. Add `.video-tools/` to the repo's
`.gitignore` so the vendored toolchain never lands in a PR.

Render (V1, after the storyboard, and again after any `.mmd` edit):

```bash
timeout 300 node $S/scripts/render-diagrams.mjs \
  --storyboard "$VIDEO_DIR/storyboard.json" --out "$VIDEO_DIR"
# one diagram:  --only d2-erd
# audit only:   --check      (fails on a missing render or a .mmd changed since it was rendered)
```

The script renders every `source: "image"` beat with settings that are stable across
runs, so a re-render can be spliced into a finished cut:

| setting | value | why |
|---|---|---|
| mmdc version | **12.0.0** (pinned by `setup-mermaid.sh`) | layout algorithms change between majors |
| theme / background | `-t dark -b '#0B1220'` | matches `compose-video.mjs --bg`, so the diagram sits in the frame instead of on a white card |
| size / scale | `--size 1600 -s 2` | long edge 1600 CSS px, rendered at 2× (3200 px) so the push-in stays sharp |
| ids | `deterministicIds: true`, seed = `sha256(.mmd)` | no random element ids → same input, same output |
| font | `DejaVu Sans` via theme + `--cssFile` | the font compose burns captions with; no silent fallback |
| ER layout | `direction LR` in the `.mmd` (plus `er.layoutDirection: "LR"` in the config) | landscape; the source directive is the one mmdc 12 honours |
| browser | system Chrome/Chromium (`MMDC_CHROME` overrides) | no second 150 MB Chromium download |
| icon packs | none | not reproducible offline |

It writes `diagrams/renders.json` (sha256 of the `.mmd` and of the PNG, dims, fit, mmdc
version). `--check` compares hashes — mtime is not enough after a checkout.

**Legibility gate:** the script computes how the PNG fits a 1600×900 frame with the
caption band reserved, and **fails** when the content would land below 45 % scale. That
failure is the signal to make the diagram landscape, cut entities, or split it.

## Look at every render — it is not optional

The script checks size, aspect and hashes. It cannot see:

- clipped or overlapping labels, text running outside a box,
- tofu glyphs (an unsupported character in a name),
- an arrow that starts or ends in empty space,
- the **wrong** table/node highlighted,
- a schema that no longer matches the migration.

Open each PNG (`read` the file, or `xdg-open`) and check those five things. Fix the
`.mmd` and re-render. A diagram with a clipped label is worse than no diagram — it
teaches the viewer something false and looks careless.

In V7, look at the diagram frames again **in the contact sheet**: that is the real
1600×900 rendering, caption included, not the 3200 px PNG you just approved.

## Storyboard + capture wiring

A diagram is an ordinary beat with `source: "image"` (see `steps/1-storyboard.md` for the
full schema):

```jsonc
{
  "id": "d2-erd",
  "source": "image",                     // still rendered from a .mmd — no browser, no capture
  "kind": "diagram",
  "diagram": "erd",                      // concept | architecture | erd
  "mmd": "diagrams/d2-erd.mmd",          // source, relative to $VIDEO_DIR
  "image": "diagrams/png/d2-erd.png",    // render, relative to $VIDEO_DIR
  "zoom": true,                          // optional gentle 1.05 push-in (default on)
  "holdMs": 0,                           // ignored: the beat lives max(6, voice + 1.8) s
  "caption": "DATA MODEL — invoice → billing_notification, one row per event",
  "narration": "The change reads invoice and writes billing_notification …"
}
```

and the storyboard carries `"touchesDataModel": true|false` at the top level.

- **`capture-beats.mjs` does no browser work for these beats.** It validates that the PNG
  exists (resolving it against `$VIDEO_DIR`), copies the beat into `timeline.json` with
  `segment: null` and an absolute `image` path, and keeps the order.
- **It also refuses the whole capture when the contract is broken:** no
  `concept`/`architecture` beat, that beat not before the first filmed beat,
  `touchesDataModel: true` without an `erd` beat, or an ERD placed after the change it
  explains (after the first BEFORE/AFTER beat; in a chaptered release video, after the
  first filmed beat of its own `chapter`). `--allow-no-diagrams` exists only for a
  human-authorised exception and must be recorded in the PR body
  (`VIDEO_DIAGRAMS: none — <reason>`).
- **`compose-video.mjs` renders the still:** fit (never crop) on the `#0B1220` background,
  a 1.05 push-in, a small `ARCHITECTURE` / `CONCEPT` / `DATA MODEL` chip top-left, and the
  caption in the same bottom band as every filmed beat. No box is drawn — there is no
  measured rect.
- Diagram beats are **cards, not clips** in the budget: `max(6, voice + 1.8)` s, counted
  with the cards in `workflow-release-video`'s arithmetic.

## Narration for diagram beats

One idea, 20–30 words, doing the diagram's job — and nothing else. Never read the diagram
aloud box by box, never say "as you can see", never restate the caption.

- **architecture / concept:** name the parts in flow order and the one consequence that
  matters for this change.
  > "Here is the shape of it: the product bills through its own Stripe account, Stripe
  > calls our webhook, and the webhook is the only place this fix lives."
- **ERD:** say **reads / writes**, name the FK, and give the cardinality the guard depends
  on.
  > "The change reads invoice and writes billing_notification. One event is one row,
  > keyed on invoice_id — that is what makes a redelivery cheap to ignore."
- Caption: 6–12 words, prefixed `ARCHITECTURE —`, `CONCEPT —` or `DATA MODEL —`.
- The diagram beat is the **setup**; the BEFORE beat is the pain. Do not spend the
  diagram's line on the bug.

## Checks

- [ ] beat 1 is `kind: "motivation"` in the reporter's words (`steps/1-storyboard.md`) — before every diagram
- [ ] ≥ 1 `concept`/`architecture` beat, **before the first filmed beat**
- [ ] `touchesDataModel: true` → ≥ 1 `erd` beat, before the change it explains
      (before the first BEFORE beat; in a release video, before its chapter's filmed beats)
- [ ] every diagram beat has a `.mmd` **and** a rendered PNG; `render-diagrams.mjs --check` passes
- [ ] `setup-mermaid.sh` installed into a writable prefix (`$VIDEO_TOOLS_DIR`, `<worktree>/.video-tools`) — never assume `~/.local/share` is writable in the cage
- [ ] every PNG was **looked at** after rendering (clipping, overlap, tofu, arrows, highlight)
- [ ] landscape, ≤ 6 entities / ≤ 8 nodes, real names from the diff, the changed object highlighted
- [ ] each diagram beat has its own narration line + a prefixed caption
- [ ] the tables/nodes match what the change actually reads or writes (check the diff, not the plan)
- [ ] no `.png` was hand-edited, and the `.mmd` files are still in `$VIDEO_DIR/diagrams/`
