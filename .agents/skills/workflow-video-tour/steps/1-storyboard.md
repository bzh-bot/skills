# V1 — Storyboard → `storyboard.json`

**Output:** `$VIDEO_DIR/storyboard.json`. Worked example: `../storyboard.example.json`.

## Shape of the video

The video opens on the **problem**, in the reporter's words, and only then explains the
system. A viewer who has never seen the codebase needs the *why* before the *how* — see
**The motivation beat** below (and `../diagrams.md` for the diagrams that follow).

| # | beat | colour | hold | says |
|---|---|---|---|---|
| 0 | intro card (auto, 4 s) | — | 4 s | `TICKET · PR #N` + ultra-brief title, over a blurred first shot. No narration. |
| 1 | **motivation** (`kind: "motivation"`, `source: "static"`) | — | 6–11 s | **always, first**: what is broken or missing, who is affected, what the impact is — in the reporter's words from the ticket |
| 2 | **concept / architecture diagram** (`source: "image"`) | — | 6–11 s | **always**: what the system is and how the idea works — one picture, one narrated line |
| 3 | **ERD** (`source: "image"`) | — | 6–11 s | when `touchesDataModel`: the tables the change **reads or writes**, keys and cardinality |
| 4 | context | red | 8–10 s | who the actor is and what they were trying to do |
| 5 | BEFORE | red | 9–11 s | the pain, shown live |
| 6–7 | AFTER (one per surface) | green | 9–11 s | the fix, shown live |
| 8 | guard | green | 7–9 s | the one edge case a reviewer would ask about |
| 9 | close (static) | — | 6–8 s | a **summary card**: `heading` + 2–4 `bullets` + `footer` |

**2–5 filmed beats + 1 motivation + 1–2 diagram beats + the close, in 45–80 s total.** The
motivation and the diagrams cost 22–26 s of that, so a video that used to film five beats
films three and keeps them: they are the only beats that explain *why* the rest matters.
Longer than 80 s is a recording, not a proof.

## The motivation beat (mandatory, first, from the ticket)

**Why.** Reviewers do not have the ticket open. A video that opens on "here is the shape
of it: web app → API → worker" asks them to care about architecture before telling them
what is broken, and it does it in the engineer's vocabulary. The person who reported the
bug said something much more specific and much more persuasive — "finance has no idea the
money arrived" — and that sentence belongs in the first ten seconds, before anything
technical.

**The contract** (`capture-beats.mjs` refuses the capture, exit 2, **no waiver flag**):

- beat **1** — the first narrated beat after the intro card. Nothing technical may precede
  it: not the architecture diagram, not a screen, not a chapter divider.
- `kind: "motivation"`, `source: "static"` (a narrated card; `compose-video.mjs` draws a
  `WHY THIS EXISTS` chip, the verbatim quote and its attribution).
- five required fields, all **copied from the ticket**, never invented:
  | field | what it is |
  |---|---|
  | `quote` | the reporter/user sentence, **verbatim** (≥ 6 words) — shown on screen |
  | `reportedSymptom` | the symptom phrase as reported, e.g. `"invoice stays open and finance has no idea"` |
  | `affected` | who is affected, per the ticket, e.g. `"the finance team"` |
  | `impact` | what the impact is, per the ticket, e.g. `"money sits unreconciled for days"` |
  | `narration` | the spoken line, 12–28 words (≥ 12 enforced) |
- the **spoken line must reuse the ticket's vocabulary**: at least two content words from
  `quote`/`reportedSymptom`/`affected`/`impact`, 80 % of the symptom's content words, and
  at least one word of `affected` and one of `impact`. Rewording the ticket into
  engineering language — "notification gap in the billing flow" — **fails the gate**.
- **generic lines fail**: "This PR fixes the billing bug and improves the flow", "minor
  fixes and improvements", "seamless/robust/enhance", a bare verb sentence
  ("Fixes the bug") and anything that does not name the reported symptom.

```jsonc
{
  "id": "m-motivation",
  "kind": "motivation",
  "source": "static",
  "quote": "Every time a client pays by bank transfer, the invoice stays open and finance has no idea the money arrived.",
  "reportedSymptom": "the invoice stays open and finance has no idea",
  "affected": "the finance team",
  "impact": "money sits unreconciled for days",
  "reportedBy": "the finance lead",        // optional attribution line on the card
  "ticketUrl": "https://…/<KEY>",        // optional, provenance
  "narration": "The finance lead put it plainly: when a client pays by bank transfer the invoice stays open, finance has no idea the money arrived, and money sits unreconciled for days."
}
```

**Where the wording comes from:** the ticket description and comments, verbatim — not the
PR body (already translated into engineering language), not the acceptance criteria
(already abstracted), and never the model's paraphrase. If the ticket's report is a single
terse line, use it; a short quotation in the reporter's voice beats a polished summary.

### Diagrams are mandatory (V1)

- **One `architecture` or `concept` beat, always**, positioned before the first filmed
  beat. `architecture` when the change involves services, jobs, auth, webhooks or infra;
  `concept` when it is a domain/workflow idea.
- **One `erd` beat whenever the change touches the data model** — a migration, a new
  table/column/index, a **session or interval entity**, or the query behind a report. Set
  `"touchesDataModel": true` at the top level of the storyboard; that flag is what makes
  the ERD mandatory (and `capture-beats.mjs` refuses to run without it).
- Order is fixed: **intro card → motivation → concept/architecture → ERD → BEFORE →
  AFTER → guard → close.** The capture script enforces all three positions (motivation
  first, then the two diagrams); do not reorder them to "get to the point faster".
- Author the `.mmd` in `$VIDEO_DIR/diagrams/<beat-id>.mmd`, render it with
  `scripts/render-diagrams.mjs`, **look at the PNG**, then reference it from the beat. Full
  rules, layout limits and the deterministic settings: **`../diagrams.md`**.

### Non-UI changes → film the tool, not the app

If the diff changes a schema/migration, a permission or middleware, a route/payload, a
job, or an outbound email, an app screenshot does not show it. Add a beat on the surface
that does — CloudBeaver (schema/rows), Hoppscotch (API request/response), Google Sheets
(tabular export), the PR Files-changed view for backend code, Mailpit, a log/metrics
board — using `source: "web"` + `url` (see `2-capture.md`). Start the self-hosted tools
with `scripts/demo-tools.sh up` and record their URLs from `$VIDEO_DIR/demo-tools.json`;
**never** film a hand-built results table, a custom HTML page or pretty-printed `curl`
(that is not evidence, and the gate fails it). Read **`../non-ui-evidence.md`** for the
change-class → surface map, the tool recipes, and what a backend beat must narrate
(security implications + the design choices a reviewer will ask about). Budget: the 1–2
diagram beats already cost 16–20 s of a 45–75 s video, so at most **~1** additional
non-UI surface beat in a mixed video; a purely headless ticket spends its filmed beats on
2–3 surfaces (schema, API, mail/logs) after the diagrams.

## Write the narration

Fill `../prompts/narration.md` with the ticket, PR body, the acceptance criteria you
just proved in P6 and the BEFORE/AFTER states you actually drove. It returns the
beats array. Rules it enforces (check them yourself too):

- 20–30 words per line (≈2.8 words/s → 7–11 s). The video follows the voice.
- Each line does exactly one job: context, before, after, or guard.
- Name actor → object → outcome; name the mechanism once (event, status, job).
- No "as you can see", no restating the caption, no marketing adjectives, nothing
  you did not verify in the tour.
- Captions: 6–12 words, prefixed `BEFORE —` / `AFTER —` so a skimmer sees polarity.

## Beat schema

```jsonc
{
  "title": "ABC-45 · PR #290",                 // intro card line 1 — ticket + PR number
  "subtitle": "Email for every Stripe event",  // intro card line 2 — ultra-brief title (≤ 6 words)
  "fps": 30, "viewport": [1600, 900],
  "touchesDataModel": true,     // true → an `erd` diagram beat is mandatory (diagrams.md)
  "beats": [{
    "id": "b2-before-gap",         // file-safe, ordered
    "phase": "before",             // before | after — selects the --before-cmd/--after-cmd hook (V2)
    "source": "app",               // app (SPA route) | web (other origin) | static (card) | image (diagram)
    "route": "/invoices",          // app: SPA route      web: "url": "http://127.0.0.1:55324"
    "readyText": "INV-001035",     // must be on screen before the pump starts (data, not clock)
    "click":  { "finder": "<js expr → element>" },   // optional; click2 for a second click
    "box":    { "mode": "row", "text": "INV-001035" },
    "boxColor": "#EF4444",         // red BEFORE · #22C55E green AFTER
    "holdMs": 10000,
    "caption": "BEFORE — payment landed, invoice pending, Billing is empty",
    "narration": "…20–30 words…"
  }]
}
```

**Diagram beats** (`source: "image"`) are stills rendered from a `.mmd` — no browser, no
capture. They carry `diagram`, `mmd` and `image`, and their `holdMs` is ignored:

```jsonc
{
  "id": "d2-erd",
  "source": "image",
  "kind": "diagram",
  "diagram": "erd",                     // concept | architecture | erd
  "mmd": "diagrams/d2-erd.mmd",           // source, relative to $VIDEO_DIR
  "image": "diagrams/png/d2-erd.png",     // render, relative to $VIDEO_DIR
  "zoom": true,                           // optional 1.05 push-in (default on)
  "caption": "DATA MODEL — invoice raises billing_notification rows",
  "narration": "…20–30 words: what it reads, what it writes, the FK…"
}
```

**The motivation beat** (`kind: "motivation"`, `source: "static"`) is beat 1 and carries
`quote` / `reportedSymptom` / `affected` / `impact` / `narration` — see **The motivation
beat** above for the contract and the reason.

Full diagram rules, narration recipes and checks: **`../diagrams.md`**.

**Box modes** (pick by intent — "smallest element containing the text" picks the page
container): `deepest` (label), `row` (nearest `tr`/`[role=row]`), `wide` +
`minWidth`/`minHeight` (card/list item), `selector` (stable container, e.g. `#nav-html`).

**Click finders** are JS expressions returning an element. MUI trap: at zero unread a
`Badge` renders no badge node, so match the icon path instead:
`[...document.querySelectorAll('button.MuiIconButton-root')].find(e => (e.querySelector('svg path')?.getAttribute('d')||'').startsWith('M10.268'))`.

## Cards: intro and close

- **Intro** (automatic, from `title`/`subtitle`): accent rule, `title` at 52 px,
  `subtitle` in the accent colour, an optional provenance footer
  (`compose-video.mjs --intro-footer "org/repo · TICKET-1 · PR #N"`), over the first
  shot blurred + dimmed + scrimmed (`--intro-bg <png>` to supply your own, or
  `--intro-bg none` for a flat background). The mascot is composited over it in V5.
- **Close** (`source: "static"`): use `heading` + `bullets` + `footer`. Without
  `bullets` it falls back to the old single centred `caption` — which reads as a
  run-on line and is the weaker card.

## Checks

- [ ] **beat 1 is `kind: "motivation"`**, with `quote` copied verbatim from the ticket and
      `reportedSymptom` / `affected` / `impact` / `narration` filled in — and it is the
      first beat (nothing technical before it). `capture-beats.mjs` refuses otherwise
- [ ] the motivation line **names the reported symptom, who is affected and the impact**
      in the ticket's words — not "fixes the billing bug". Read it against the ticket
- [ ] intro `title` = `<TICKET> · PR #<N>`, `subtitle` ≤ 6 words
- [ ] **≥ 1 `concept`/`architecture` diagram beat, before the first filmed beat**, with a
      `.mmd` and a rendered PNG (run `render-diagrams.mjs --check`)
- [ ] **`touchesDataModel: true` → an `erd` beat before the first BEFORE beat**, and the ERD
      shows the tables the change actually reads/writes (check the diff, not the plan)
- [ ] every diagram PNG was looked at after rendering (`../diagrams.md` — clipping, overlap,
      tofu, arrows, highlight)
- [ ] 2–5 filmed beats, ≥1 BEFORE (red), ≥1 AFTER (green), 1 guard, 1 static close
- [ ] **beat length = rendered narration + 1.5 s** (`max(6, voice + 1.5)`) — the captured clip's hold is not content and its excess after the voice ends is dropped; `sum of holds ≤ 70 s` was the old framing and no longer governs
- [ ] every `box` is visible only while its target is on screen — no box over pre-render/post-navigation frames, and a frozen tail longer than ~1 s means the narration is too long for its clip: **re-cut the storyboard / shorten the line**, never trim the speech
- [ ] every narration's duration is measured on the rendered voice, not a words-per-second assumption (Ryan measured 1.9–3.2 words/s across lines; digits spelled out are slow)
- [ ] every beat's `durationMs`/viewport matches its actual capture; box coordinates are viewport CSS pixels of the same viewport, so resolution mismatches in `timeline.json` must be caught before assembly
- [ ] every `readyText` is text you saw on that screen during P6
- [ ] **every non-UI change class is covered by a beat on its real surface** (or excused in
      the PR body) — see `../non-ui-evidence.md`; at most ~2 such beats when the video also
      films the UI
