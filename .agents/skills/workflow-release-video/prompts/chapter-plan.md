# Prompt — release manifest → chapters

Use in R2, before writing any narration. Feed it `release-manifest.json` (and
`release-notes.md` if the manifest is thin). Returns the chapter plan that
`prompts/release-narration.md` turns into beats.

---

You are planning the chapter structure of a **3:30–4:30 narrated release video** for
engineers and technical stakeholders who use this product but do not read its diff.

You are given a release manifest: every merged PR between the last tag and now, with
title, author, labels, changed-file directories, and a grouping hint per item
(`byArea`, `byType`, `smallAreas`). You have NOT read the diffs. That is the point —
plan from what the release *did*, not from how it was done.

## Rules

0. **Start from the problem, in the reporters' words.** Before planning a single chapter,
   find what was actually broken or missing for the people who filed the issues this
   release closes: the ticket/issue text, the customer report in the release notes, the
   `breaking` items. Extract one `problem` block — `quote` (verbatim), `reportedSymptom`,
   `affected`, `impact`, `source` (issue keys) — and return it at the TOP level, because
   it becomes beat 1 of the video and `capture-beats.mjs` refuses a storyboard without it.
   Never invent a complaint; if the release is purely internal, say so in `problem.quote`
   using the closest real statement from the manifest.
1. **7–9 chapters.** Fewer and a chapter is too big to narrate in 60 s; more and no
   chapter earns its divider card. Aim for 8.
2. **A chapter is an area, not a PR.** Group by what a user would call one thing
   ("Billing", "Authentication", "Fleet telemetry"), not by repository directory and not
   by conventional-commit type. `groupingHints.byArea` is a starting point, not an
   answer — if two areas are the same story to a user, merge them; if one area is two
   stories, split it.
3. **Order by consequence, not by count.** What changes what a user does, first. What
   changes what a user *must* do (breaking, migration, config) goes early and is called
   out. Internal refactors, dependency bumps and CI noise go last or nowhere.
4. **Every chapter gets 2–3 filmed beats.** A chapter that cannot support two
   filmable moments is not a chapter — fold it into "Also in this release", the final
   chapter that exists to name 4–8 small items in one breath over a single card.
5. **Name the one item in each chapter that a reviewer would ask about** (the guard).
   That is usually the riskiest or least obvious change in the area, and it is what makes
   the chapter worth its 30 seconds.
6. **A chapter must be filmable.** If the manifest's change cannot be seen in the app —
   a migration, a rate limit, a retry policy — say so explicitly and give the chapter a
   different shot in the **real tool**: CloudBeaver for schema/rows, Hoppscotch for an
   API request/response, Google Sheets for an export, a metrics panel for a job. Never a
   hand-built table, a custom HTML page or pretty-printed `curl` — those are not evidence
   (`workflow-video-tour/non-ui-evidence.md`). If none of the real tools can show it, mark
   the chapter `card-only: true` rather than inventing a surface.
7. **Plan the diagrams with the chapters, not after them.** Two rules:
   - the release opens with **one product architecture diagram** before the first filmed
     beat — the components the chapters will walk through (web app, API, worker, store,
     the external service that matters). One picture for the whole release.
   - **any chapter whose PRs touch the data model** (a migration, new table/column/index,
     a session or interval entity, a report query) gets **one ERD**, right after its
     divider: only the tables that chapter reads or writes, the FK, the cardinality. Not
     the whole schema, and never one shared "big ERD" for several chapters — a chapter's
     ERD is about that chapter's change.
   A diagram beat replaces one filmed beat in the chapter (2 filmed + 1 ERD); it does not
   add length.
8. **Nothing invented.** Every chapter and every item you name must trace to specific
   PR numbers in the manifest. If the release is too thin for 7 chapters, say so and
   return fewer — a 2-minute honest video beats a 4-minute padded one, and padding is
   the failure mode of release videos.

## Return

```
problem: {
  quote: "…",                                   // verbatim from the issue/ticket the release closes
  reportedSymptom: "…",                        // the symptom phrase as reported
  affected: "…",                               // who it hit
  impact: "…",                                 // what it cost
  source: ["<KEY>", "<KEY>"]                 // the issues/tickets the quote comes from
},
architectureDiagram: {
  shows: "…",                                          // ≤ 12 words: the components in the picture
  nodes: ["web app", "API", "worker", "Postgres"],
  why: "…one sentence — what a viewer needs before chapter 1"
},
chapters: [
  {
    n: 1,
    title: "Billing",                              // ≤ 3 words, a divider-card heading
    oneLine: "…",                                  // ≤ 10 words, the divider subtitle
    prs: [290, 301, 305],                          // traced to the manifest
    why: "…",                                      // why this is a chapter, one sentence
    diagram: null,                                 // or { kind: "erd", shows: "…", tables: ["…"], fk: "…" }
    filmBeats: [                                   // 2–3 total, INCLUDING the diagram
      { what: "…", route: "/invoices", keyElement: "…" }
    ],
    guard: "…",                                    // the one edge case worth a beat
    cardOnly: false
  }
],
alsoInThisRelease: [/* PR numbers for the final chapter */],
breaking: [/* PR numbers that require the user to do something, or [] */],
totalFilmBeats: <n>,
totalDiagramBeats: <n>,
notes: "…what the manifest could not support, and what you dropped"
```

## Inputs

- Repository: `<slug>` · release name: `<name>` · range: `<from> → <to>`
- **What was reported by users/customers for the issues this release closes** (verbatim
  tickets/issues, with keys — the source of `problem`): <quoted text + keys>
- Manifest: `release-manifest.json` (full JSON)
- Grouping hints: `<byArea>`, `<byType>`, `<smallAreas>`
