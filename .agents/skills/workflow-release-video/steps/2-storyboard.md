# R2 — Storyboard → `storyboard.json` + `budget.json`

**→ TaskUpdate: R2 → in_progress**

Two prompts, in order. Neither is optional — a release video that goes straight to
beats is a PR video with filler in it.

```bash
S=~/.agents/skills/workflow-release-video
jq '{release, stats, groupingHints, items: [.items[] | {number,title,author,labels,dirs,scope,type}]}' \
  "$VIDEO_DIR/release-manifest.json" > "$VIDEO_DIR/manifest-input.json"
# 1. prompts/chapter-plan.md   → $VIDEO_DIR/chapters.json
# 2. prompts/release-narration.md (chapters + manifest + surfaces) → storyboard.json
```

## Shape of the video

The video opens on the **problem this release answers**, in the words of the people who
reported it, and only then explains the system. Diagrams are part of the shape, not an
appendix (`workflow-video-tour/diagrams.md`):

| # | beat | kind | says |
|---|---|---|---|
| 0 | intro card (auto, 4 s) | — | `PRODUCT version` + one line + `slug · from → to` |
| 1 | **motivation** (`kind: "motivation"`, `source: "static"`, always first) | card | what was broken or missing, who it hit, what it cost — quoted from the release's own tickets/issues, not paraphrased |
| 2 | **product architecture diagram** (`source: "image"`, always) | still | the system this release lands in — services, store, the surfaces the chapters will show |
| 3..n | **chapter**: divider card, then an **ERD** if the chapter touches the schema, then 2–3 filmed beats | card + still + red/green | one area per chapter: what it is, what data it reads/writes, what changed, and the one risk |
| last | close card | `static` + bullets | the shape of the release, and what to do about it |

**1 motivation + 7–9 chapters · 26–30 narrated beats · 2–4 diagram beats · 13–17 filmed
beats · 460–560 narration words · 230–260 s.**

Seconds ≈ `words / 2.5 + 44 + 2 × diagram beats` — see the budget section of `../SKILL.md`
for why the `+44` is fixed, why a diagram beat is a card (`voice + 1.8`), and why 100 words
over budget is 40 s over. **Every diagram beat you add replaces one filmed beat**, not a
word of narration.

### Beat 1 is the motivation, not the architecture

`workflow-video-tour/steps/1-storyboard.md` → **The motivation beat** is the authority.
For a release, the wording comes from the release itself: the issues/tickets the merged
PRs close, the customer reports quoted in the release notes, the `breaking` items — the
complaint that made these PRs necessary. It is **not** the release theme, not the PR
titles, and not a summary written in engineering language.

- `quote`: the reporter/user sentence, verbatim (≥ 6 words) — rendered on screen.
- `reportedSymptom`: the symptom phrase as reported.
- `affected`: who was affected, from the tickets/issues.
- `impact`: what it cost, from the tickets/issues.
- `narration`: 12–28 words naming all three in the ticket's vocabulary.

`capture-beats.mjs` exits 2 when the motivation beat is missing, not first, empty,
generic, or never mentions the symptom / who is affected / the impact. There is no waiver.
If the manifest carries no reported problem (a pure internal refactor release), say so and
quote the closest real statement — never invent a customer complaint, and never substitute
a theme sentence for the ticket's words.

## Beat schema

Same as `workflow-video-tour/steps/1-storyboard.md` (that is the authority — read it),
with three additions used only by this skill:

```jsonc
{
  "title": "the product 2.4",                     // intro card line 1
  "subtitle": "Billing, auth, faster sync", // intro card line 2 — ≤ 8 words
  "fps": 30, "viewport": [1600, 900],
  "touchesDataModel": true,                  // any chapter changes the schema → ERDs mandatory
  "beats": [
    {
      "id": "m-motivation", "kind": "motivation", "source": "static",   // ← beat 1, ALWAYS
      "quote": "Every time a client pays by bank transfer, the invoice stays open and finance has no idea the money arrived.",
      "reportedSymptom": "the invoice stays open and finance has no idea",
      "affected": "the finance team",
      "impact": "money sits unreconciled for days",
      "reportedBy": "the finance lead",
      "narration": "The finance team said it plainly: when a client pays by bank transfer, the invoice stays open, finance has no idea, and money sits unreconciled for days."
    },
    {
      "id": "d0-architecture", "source": "image", "kind": "diagram",
      "diagram": "architecture",             // ← always, before the first filmed beat
      "mmd": "diagrams/d0-architecture.mmd",
      "image": "diagrams/png/d0-architecture.png",
      "caption": "ARCHITECTURE — web app → API → worker → Postgres",
      "narration": "…18–24 words…"
    },
    {
      "id": "c3-erd", "source": "image", "kind": "diagram",
      "diagram": "erd", "chapter": 3,       // ← right after the divider, before c3's filmed beats
      "mmd": "diagrams/c3-erd.mmd",
      "image": "diagrams/png/c3-erd.png",
      "caption": "DATA MODEL — invoice raises billing_notification",
      "narration": "…18–24 words: reads / writes / FK / cardinality…"
    },
    {
      "id": "c3-card", "source": "static",           // ← a CHAPTER DIVIDER
      "chapter": 3,
      "heading": "Billing",                          // rendered in the accent colour
      "bullets": ["Own Stripe account", "Refunds"],  // 2–4, ≤ 6 words each
      "footer": "PRs #290 #301",
      "caption": "Billing",                          // fallback if bullets are dropped
      "narration": "…18–24 words…",                // dividers ARE narrated
      "holdMs": 6000                               // ignored for cards: max(6, voice + 1.8)
    },
    {
      "id": "c3-b1-invoice", "source": "app", "route": "/invoices",
      "chapter": 3, "phase": "after",
      "readyText": "INV-001035",
      "box": { "mode": "row", "text": "INV-001035" },
      "boxColor": "#22C55E",
      "holdMs": 12000,                              // narration + ~2.2 s
      "caption": "…6–12 words…",
      "narration": "…18–24 words…"
    }
  ],
  "budget": { "targetS": 253, "plannedWords": 500, "cards": 11, "filmBeats": 14, "chapters": 8 }
}
```

### What is new versus the tour

- **Beat 1 is the motivation**, before the architecture diagram — a `kind: "motivation"`
  card quoting the reported problem (see above). `capture-beats.mjs` refuses the storyboard
  without it, in any other position, or with a generic line; there is no waiver flag.
- **A diagram beat is `source: "image"`** — a `.mmd` rendered to PNG by
  `workflow-video-tour/scripts/render-diagrams.mjs`. `capture-beats.mjs` copies it into
  `timeline.json` with `segment: null` + an absolute `image` path (no browser work), and
  `compose-video.mjs` draws it as a fitted still with a kind chip and the caption band.
  Author them in `$VIDEO_DIR/diagrams/<beat-id>.mmd`, render, **look at the PNG**, then
  reference it. Rules and narration recipes: `workflow-video-tour/diagrams.md`.
- **The product architecture beat is always the first diagram**, right after the
  motivation and before the first filmed beat. It is the release's concept picture: the
  components the chapters will walk through.
- **An ERD belongs to a chapter** (`"chapter": 3`) and sits between that chapter's divider
  and its first filmed beat. Only chapters whose PRs touch the schema get one — a
  migration, a new table/column/index, a session or interval entity, a report query.
  `"touchesDataModel": true` at the top level makes at least one ERD mandatory.
- **`source: "static"` is now the chapter divider**, not just the close. `capture-beats.mjs`
  pushes those into `timeline.json` with `segment: null`, and `compose-video.mjs` renders
  them as narrated cards with `heading` + `bullets` + `footer`. Both paths already work;
  this is the one structural change the whole skill rests on.
- **`chapter`** is documentation for you and for `--only`; nothing reads it.
- **`holdMs` must exceed the line**, see the budget rules in `../SKILL.md`.

## Write the budget first, in the open

Print the table and fill it as you write. Do not write narration and then discover the
total.

```
📋 BUDGET for <release>
  chapters:       8
  narrated cards: 9    (8 dividers + the close)
  diagram beats:  3    (architecture + 2 ERDs, counted as cards)
  filmed beats:   14   (2 per chapter, minus one per diagram)
  ───────────────────────────────────────────────────────
  narration:     500 words      (18–24 per beat, 25–29 narrated beats)
  seconds ≈      500 / 2.5 + 44 + 2 × 3 = 250 s  →  4:10   status: OK
```

Write it to `$VIDEO_DIR/budget.json` so R4 can compare planned against measured:

```json
{ "targetS": 250, "plannedWords": 500, "cards": 11, "filmBeats": 14, "chapters": 8 }
```

R2 and R4 both compute the total as
`plannedWords / 2.5 + cards × 1.8 + filmBeats × 1.5 + 4` — planned from the storyboard, then
again from the rendered voice. **`cards` includes the diagram beats** (they carry no clip:
`voice + 1.8 s`), which is what keeps the estimate honest.

## Checks

- [ ] **beat 1 is `kind: "motivation"`** — the reported problem quoted from the release's
      own tickets/issues (`quote` verbatim, plus `reportedSymptom` / `affected` / `impact` /
      `narration`), before the architecture diagram. `capture-beats.mjs` refuses otherwise
- [ ] the motivation line names the symptom, who was affected and the impact in the
      reporter's words — not "this release improves billing"
- [ ] 7–9 chapters, each with 2–3 filmed beats, each chapter's PR numbers traced to the
      manifest (spot-check three at random)
- [ ] **a product `architecture` diagram beat before the first filmed beat**, and an
      **ERD for every chapter whose PRs touch the schema**, each with a `.mmd` + a rendered
      PNG (`render-diagrams.mjs --check`), each PNG looked at (`diagrams.md`)
- [ ] **every narration is 18–24 words.** Count them; a 38-word beat is a 5-minute video
- [ ] **every filmed beat's `holdMs >= words × 400 + 2200`** (at 2.5 w/s plus 2.2 s)
- [ ] planned total (`plannedWords / 2.5 + cards × 1.8 + filmBeats × 1.5 + 4`) lands in
      230–260 s — compute it, do not eyeball it
- [ ] ≥ 1 filmed BEFORE beat *if* a previous-release worktree is available; if not, no
      beat pretends to be BEFORE (see `../SKILL.md` — the BEFORE state is the previous
      release, not a mock)
- [ ] every filmed beat has `route` + `readyText` seen on that screen, a `box` target that
      exists there, and a caption of 6–12 words
- [ ] `groupingHints.smallAreas` items appear in the close chapter, not as chapters
- [ ] the close has `heading` + 2–4 `bullets` + `footer` — not one run-on caption
- [ ] nothing in any narration is absent from the manifest **and** absent from a screen
      you have actually seen

## Traps

- **Padding is the failure mode.** Six thin chapters narrated for four minutes sound
  exactly like four minutes of padding. If the plan comes in under 200 s, ship the
  shorter video and say so in the release body.
- **A diagram is not a divider, and a divider is not a diagram.** The divider is a card
  with a heading and narration; the diagram is a picture of the system or the tables. A
  chapter has at most one ERD — two diagrams in one chapter means the chapter is really
  two chapters, or the diagram is doing the divider's job.
- **The motivation is not the theme.** "Billing, auth and faster sync" is an intro
  subtitle. The motivation is the complaint that made the release necessary, in the
  reporter's words; a release video that opens on its own theme has skipped the only
  sentence that makes a viewer care.
- **Never re-derive the schema from memory.** The ERD's tables, FKs and cardinality come
  from the migrations in the manifest's PRs (and the previous-release worktree when it
  exists), not from what the app "probably" does.
- **A chapter divider is not a title card.** It carries the chapter's opening
  narration, so it is 5–7 s, not 2 s.
- **Beat ids must stay stable across a re-cut** — `--only <id>` and `revoice-video.mjs`
  both key on them. Renaming a beat throws away its segment.

**→ TaskUpdate: R2 → completed**
