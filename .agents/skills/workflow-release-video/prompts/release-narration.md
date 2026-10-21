# Prompt — release chapters → `storyboard.json`

Use in R2, after `chapter-plan.md`. The output is the file `capture-beats.mjs` and
`compose-video.mjs` consume; schema and checks are in `../steps/2-storyboard.md`.

---

You are writing the narration and shot list for a **3:30–4:30 narrated release video**
that a colleague watches to learn what changed in this release and what they have to do
about it. The voice is an Australian engineer **brimming with energy**, showing the team
what just went out: fast, bright, precise, genuinely pleased — with a light dry wit.
Write for that delivery: the energy has to be in the rhythm, because a flat script reads
flat no matter how good the voice is.

The visuals are decided (the chapter plan below, each beat with a target element on a
screen); your job is the narration text, the captions and the box targets.

## Rules

1. **Punchy and specific.** Short sentences — 6–14 words, never two subordinate clauses
   in one line. Active voice, verbs first. Name the actor, the object, the outcome. If a
   word does no work, cut it.
2. **Write for momentum.** Vary sentence length; end a beat on a short, hard sentence
   ("Nothing in the app."). Energy comes from facts landing fast, not from adjectives.
   Read it aloud — if you run out of breath, split it.
3. **18–24 words per beat, and 460–560 words in the whole script.** This is a hard
   budget, not a style note. `seconds ≈ total words / 2.5 + 44 + 2 × diagram beats`: 500
   words is ~4:14, and 620 words is 5:03. Count the words per beat *and* keep a running
   total — nine beats that each run one second long is forty extra seconds, which is how a
   4-minute video becomes a 5-minute one. The diagram lines are inside that total, and a
   diagram replaces one filmed beat rather than adding one.

## Beat 1 is the motivation, in the reporter's words

Before any chapter, the video states the **problem this release answers** — the complaint
that made these PRs necessary — in the words of the people who reported it.
`capture-beats.mjs` refuses the storyboard otherwise (exit 2, no waiver).

Return exactly one beat, **first in `beats[]`**, with `"kind": "motivation"` and
`"source": "static"`:

- `quote`: the reporter/user sentence copied **verbatim** from the issue or ticket the
  release closes (≥ 6 words). Rendered on screen — do not tidy it up.
- `reportedSymptom`: the symptom phrase as reported, e.g. `"the invoice stays open and
  finance has no idea"`.
- `affected`: who was affected, from those tickets.
- `impact`: what it cost, from those tickets.
- `reportedBy`: who reported it, when known (optional; shown as the attribution).
- `narration`: **12–28 words** that name the symptom, the affected party and the impact in
  the ticket's vocabulary. It must reuse ≥ 2 content words from the fields above, 80 % of
  the symptom's content words, and one word of `affected` and of `impact`.

Rules:

- **Quote, do not translate.** "Finance has no idea the money arrived" — not "billing
  notification coverage was incomplete". The mechanism belongs in the chapter that shipped it.
- **Never a theme sentence.** "Billing, auth and faster sync" is the intro subtitle; a
  release that opens on its own theme has skipped the only sentence that earns attention.
- **No generic summary** ("this release improves stability and adds several fixes") and no
  invented complaint: if the manifest carries no reported problem (a pure internal
  refactor), say so in the narration in plain terms and quote the closest real statement.
- No architecture, file names, event names or statuses in this line.
4. **One beat does exactly one job**: what this area is, what it did before, what it does
   now, or the one risk a reviewer would ask about. No filler, no "as you can see", no
   restating the caption, no enumerating files.
5. **Open each chapter on its divider card, not on a screen.** The divider's narration
   states the area and what changed in it in two sentences; the filmed beats that follow
   show it. A chapter is: `divider → 2–3 film beats`.
6. **Speak to someone who has never seen this codebase.** No marketing adjectives
   ("seamless", "powerful", "robust"), no hype, and **never claim anything that is not in
   the manifest or that you did not see on screen**. If you cannot see it, do not say it.
7. **Say what the user must do, once, plainly.** If anything in `breaking` requires a
   migration, a config change or a new permission, one beat says so without hedging.
8. **A little humour is welcome — one dry aside in the whole video, maximum.** It has to
   come from the situation ("the owner only found out by refreshing the dashboard"),
   never a pun, an exclamation or a joke at the expense of a person or a team.
9. **The close names the shape of the release**: how many of what, what the user must do,
   and what was deliberately left alone. It is a card with bullets, not a film beat.
10. **Captions are 6–12 words**, a skimmer's version of the line, no prefix noise. On a
    filmed beat that shows a *change*, prefix `BEFORE —` / `AFTER —` so polarity is
    obvious; on a plain "here is the new thing" beat, do not. Diagram captions are prefixed
    `ARCHITECTURE —` or `DATA MODEL —`.
11. **Write the diagram beats, and never read them aloud box by box.** The plan already
    has one product architecture beat and an ERD for each chapter that touches the schema.
    - architecture: name the components in flow order, then the one consequence the release
      turns on. “Stripe calls our webhook, the webhook writes the notification, and that
      writer is the only thing this release touches.”
    - ERD: say **reads / writes**, name the FK and the cardinality. “Billing now reads
      invoice and writes billing_notification, one row per event, keyed on invoice_id.”
    Never “as you can see”, never a tour of every box, never a bug story — the filmed beats
    do that. A diagram line may name a table the filmed beats never show; it may not claim
    anything the manifest does not contain.

## Also return

- `title`: `<PRODUCT> <version-or-range>` — e.g. `the product 2.4` or `Orma · Oct 2026`
- `subtitle`: what the release is, **≤ 8 words** — e.g. `Billing, auth, and faster sync`
- `introFooter` (→ `compose-video.mjs --intro-footer`): `<slug> · <from> → <to>`

For the motivation beat return `quote`, `reportedSymptom`, `affected`, `impact`, `narration`
(and `reportedBy` when known) — no `box`, no `boxColor`, no `click`. It is `beats[0]`.

## Per filmed beat return

- `box`: what to point at — `{mode:"deepest", text:"…"}` for a label, `{mode:"row",
  text:"…"}` for a table row, `{mode:"wide", text:"…", minWidth, minHeight}` for a card,
  or `{mode:"selector", selector:"…"}` for a stable container.
- `boxColor`: `#EF4444` for a BEFORE/old state, `#22C55E` for the AFTER/new state.
- `click` / `click2` (optional): a JS expression returning the element to click when the
  beat needs a panel opened first.
- `holdMs`: `narration_words × 400 + 2200`, rounded up to the nearest 500 — i.e. ~2.2 s
  more than the line needs at 2.5 words/s.
Per divider and close card return `heading`, `bullets` (2–4, ≤ 6 words each) and
`footer`.

**Per diagram beat return `narration` and `caption` only** — no `box`, no `boxColor`, no
`click`. Copy `id`, `source`, `kind`, `diagram`, `mmd`, `image` and `chapter` through
unchanged; they are already rendered or about to be (see
`workflow-video-tour/diagrams.md`).

Output **only** a JSON object in the schema of `../steps/2-storyboard.md` (`title`,
`subtitle`, `fps`, `viewport`, `beats[]`), with `budget` alongside it as described
there — motivation beat first, then the architecture diagram, then the chapters.

## Inputs

- Repository: `<slug>` · release: `<name>` · range: `<from> → <to>`
- **The problem this release answers, in the reporters' own words** (verbatim quotes from
  the issues/tickets the merged PRs close, and any customer report in the manifest):
  <quoted text + issue keys>
- Chapter plan: `<the chapter-plan output>`
- Manifest items behind each chapter: `<PR titles, authors, labels, dirs>`
- Surfaces available to film: `<app routes, logs, metrics, mail catcher, exports>`
- Tooling for the non-UI beats: `<CloudBeaver URL for the run's DB, Hoppscotch URL + API
  base, Google Sheets signed in? — from scripts/demo-tools.sh>`
- BEFORE worktree (previous release): `<url or "none">`
- Counted words per beat and the running total: `<the budget table you filled in>`