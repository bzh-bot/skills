# Prompt — draft the video-tour storyboard narration

Use this to turn the ticket + PR + the tour's 5-element brief into the
`storyboard.json` beats. Feed it the acceptance criteria, the PR body's
Motivation/Approach sections, and the BEFORE/AFTER states you actually proved in
P6/P7. The diagram beats (concept/architecture, and the ERD when the change touches the
data model) are authored in V1 before this prompt runs — see `../diagrams.md`; the prompt
writes their narration, it does not invent them.

---

You are writing the narration and shot list for a **45–75 second** engineering
demo video that a reviewer will watch *instead of* reading the diff. The voice is
an Australian engineer **brimming with energy**, showing a colleague what he just
shipped: fast, bright, precise, genuinely pleased — with a light dry wit. Write
for that delivery: the energy has to be in the rhythm of the sentences, because a
flat script will read flat no matter how good the voice is. The visuals
are already decided (the diagram beats and filmed beats listed below, each with a
caption); your job is the narration text and the box targets.

Rules:

1. **Punchy and specific.** Short sentences — aim for 6–14 words, and never two
   subordinate clauses in one line. Active voice, verbs first. Name the actor, the
   object and the outcome. If a word does no work, cut it.2. **Write for momentum.** Vary the sentence length and end each beat on a short,
   hard sentence ("Nothing in the app."). The energy comes from the facts landing
   fast, not from adjectives or exclamations. Read it aloud: if you run out of
   breath, split it.
3. One beat = one idea, and the video always opens with an intro card (ticket +
   PR number over an ultra-brief title — you supply `title`/`subtitle`, not a
   beat). **Then the motivation beat (beat 1, see below)**, then **1–2 diagram
   beats** (a concept/architecture intro and, when the change touches the data
   model, an ERD), then 2–5 filmed beats: context → BEFORE (the pain) → AFTER (the
   fix, one beat per surface) → the guard that matters → close (static card).

## The motivation beat (beat 1, mandatory, in the reporter's words)

The first narrated beat states the problem the ticket is about, and it must sound like
the person who reported it, not like the engineer who fixed it. `capture-beats.mjs`
checks this and refuses the storyboard otherwise (exit 2, no waiver).

Return exactly one beat with `"kind": "motivation"` and `"source": "static"`, placed
**first** in `beats[]` (before every diagram), containing:

- `quote`: the reporter/user sentence copied **verbatim** from the ticket (≥ 6 words).
  This is rendered on screen — do not clean up their grammar, do not summarise it.
- `reportedSymptom`: the symptom phrase as reported, e.g. `"the invoice stays open and
  finance has no idea"`.
- `affected`: who is affected, from the ticket, e.g. `"the finance team"`.
- `impact`: what it costs, from the ticket, e.g. `"money sits unreconciled for days"`.
- `reportedBy`: who reported it, if the ticket says (optional; shown as the attribution).
- `narration`: **12–28 words** that say, in the ticket's own vocabulary, what is broken or
  missing, who is affected and what the impact is. It must reuse at least two content
  words from `quote`/`reportedSymptom`/`affected`/`impact`, name the symptom (80 % of its
  content words) and name who is affected and the impact.

Rules for this beat:

- **Quote, do not translate.** "Finance has no idea the money arrived" — not "there is no
  notification on the payment_intent.processing event". The mechanism belongs in the
  BEFORE beat, thirty seconds later.
- **No architecture, no file names, no event names, no statuses** in this line. And never
  open with "In this video…".
- **No generic summary.** "This PR fixes the billing bug and improves the flow", "minor
  fixes and improvements", "seamless", "robust", "enhance" all fail the gate. So does a
  line that never mentions the reported symptom.
- If the ticket's report is one terse line ("payments fail silently since Tuesday"), use
  it as the quote and build the line around it — a real quotation beats a polished summary.
- Keep the dry aside for a later beat: this one is the plain statement of the problem.

Example (ABC-45):

> `quote`: "Every time a client pays by bank transfer, the invoice stays open and finance
> has no idea the money arrived."
> `narration`: "The finance lead put it plainly: when a client pays by bank transfer the
> invoice stays open, finance has no idea the money arrived, and money sits unreconciled
> for days."

4. Each narration is **18–28 words** (≈ 2.8 words/second, so 28 words ≈ 10 s).
5. **A little humour is welcome — one dry aside per video, maximum.** It has to
   come from the situation itself ("the owner only found out by refreshing the
   dashboard"), never from a pun, an exclamation, an emoji, or a joke at the
   expense of a person, a team or a competitor. A reviewer should smile once,
   not wince. If nothing is genuinely funny, skip it — precision is funnier.
6. Every line does exactly one job: the **motivation**, the **before**, the
   **after**, or the **guard**. No filler, no "as you can see", no restating the
   caption.7. Be precise about the mechanism once — the event name, the status transition,
   the job — then stop. Do not enumerate files.
8. Speak to a reviewer who has never seen the codebase. No marketing adjectives
   ("seamless", "powerful", "robust"), no hype, and never claim anything that
   was not verified in the tour.
9. The close states what changed in one breath: how many new things, and what was
   deliberately left alone.
10. `caption` is a 6–12 word on-screen line in the same voice (it is burned in);
   prefix BEFORE/AFTER beats with `BEFORE —` / `AFTER —` so a skimmer sees the
   polarity instantly.

## Diagram beats (mandatory — write their lines, do not skip them)

The storyboard you are handed already contains 1–2 `source: "image"` beats: a
`concept`/`architecture` intro before the first filmed beat, and an `erd` when the change
touches the data model. They are the viewer's only map of the system; the pain means
nothing without them. For each one write `narration` (20–30 words) and `caption`
(6–12 words). Do **not** return a `box`, `boxColor` or `click` for a diagram — there is no
page to point at.

- **architecture / concept:** name the parts in flow order, then the one consequence that
  matters. “Here is the shape of it: the product bills through its own Stripe account,
  Stripe calls our webhook, and the webhook is the only place this fix lives.”
- **ERD:** say **reads / writes**, name the FK, and give the cardinality the guard depends
  on. “The change reads invoice, writes billing_notification, and keys the row on
  invoice_id. One event, one row — that makes a redelivery cheap to ignore.”
- Never read the diagram box by box, never “as you can see”, never restate the caption,
  and never spend a diagram line on the bug — the BEFORE beat does that.
- Captions: prefix `ARCHITECTURE —`, `CONCEPT —` or `DATA MODEL —`.

A diagram's line is *setup*, so it may name a table or component the filmed beats never
show. It may not claim anything the diff does not do.

## What each beat returns

For a filmed beat:

- `box`: what to point at, as `{mode, text}` — `deepest` for a label, `row` for a
  table row, `wide` (+`minWidth`/`minHeight`) for a card/list item, or
  `{mode:"selector", selector:"…"}` for a stable container.
- `boxColor`: `#EF4444` for BEFORE, `#22C55E` for AFTER.
- `click` / `click2` (optional): a JS expression that returns the element to
  click when the beat needs a panel opened first.

For a diagram beat: `narration` + `caption` only (see the recipe above).

For the motivation beat: `quote`, `reportedSymptom`, `affected`, `impact`, `narration`
(and `reportedBy` when the ticket names the reporter) — no `box`, no `boxColor`, no
`click`.

Also return the intro card fields:

- `title`: `"<TICKET_ID> · PR #<N>"`
- `subtitle`: the ultra-brief title, **≤ 6 words**

Output **only** a JSON object in the schema of `storyboard.example.json`
(`title`, `subtitle`, `fps`, `viewport`, `touchesDataModel`, `beats[]`) — with the
motivation beat as `beats[0]`, and the diagram beats copied through unchanged except for
their `narration`/`caption`.

## Inputs

- Ticket: <TICKET_ID> — <title> — <url>
- **The reporter's own words, verbatim from the ticket description + comments** (paste
  them; this is the only source for `quote` / `reportedSymptom` / `affected` / `impact`):
  <quoted ticket text>
- Acceptance criteria proved in the tour: <list>
- What the PR changes (from the PR body): <Motivation / Approach>
- Does it touch the data model? `touchesDataModel` = <true/false — migration, new table/
  column/index, session/interval entity, report query>
- The diagram beats already in the storyboard: <id + kind + the nodes/tables each shows>
- BEFORE state observed: <what the broken/old behaviour was, step by step>
- AFTER state observed: <what the fixed behaviour was, step by step>
- Surfaces available to film: <app routes, mail catcher, logs, studio, DB>
- Guard/edge case worth showing: <e.g. redelivery idempotency>
