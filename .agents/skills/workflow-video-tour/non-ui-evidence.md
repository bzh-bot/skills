# Non-UI evidence — film the surfaces that make headless changes visible

**Read this at V1 (storyboard) and again at V2 (capture), and whenever the diff is not
purely a UI change.**

## Why

A migration, an RLS policy, a middleware, a queue job or an outbound email has **no UI
screenshot**. A tour that only films the app for such a change proves nothing about the
change — it shows an app that merely still works. The reviewer learns the change from the
*tool that makes it visible*: the DB console, the code diff, the API client, the mail
catcher, the spreadsheet, the log/metrics surface. Those surfaces are part of the video,
not an appendix.

Same rule as everywhere else in this skill: **show it, don't tell it.** Never narrate a
schema change, a permission rule or a payload shape over a screenshot of an unrelated
page.

## Tooling rule — hard: real tools, never an ad-hoc UI

A hand-built "results" table, a styled HTML page, or pretty-printed `curl` output is **not
evidence**. It proves the presenter can format JSON, not that the product does the thing.
When a beat needs one of these surfaces it is filmed in the real tool, self-hosted inside
the cage:

| beat | tool | fixed URL |
|---|---|---|
| HTTP / API request, payload, status code, auth failure | **Hoppscotch** (self-hosted) | `http://127.0.0.1:3300` (API base from `$DEMO_API_BASE`) |
| database rows, table state, DDL, indexes | **CloudBeaver** (self-hosted) | `http://127.0.0.1:8978`, connection **Run DB (workflow)** |
| spreadsheet, CSV/table export, report | **Google Sheets** in the browser | the run's signed-in Chrome profile |

Bring them up once, before the storyboard's non-UI beats are captured:

```bash
S=~/.agents/skills/workflow-video-tour
export DEMO_API_BASE="http://localhost:<api-port>"   # the run's own API
bash $S/scripts/demo-tools.sh up       # idempotent; waits for readiness, records the URLs
bash $S/scripts/demo-tools.sh status   # containers + health + URLs
bash $S/scripts/demo-tools.sh require  # exit 1 = the evidence gate fails
bash $S/scripts/demo-tools.sh down     # after the capture (--purge also drops the data)
```

- It writes `$VIDEO_DIR/demo-tools.json` and a `# >>> workflow demo tools >>>` block in
  `/tmp/workflow-run.env` (`DEMO_CLOUDBEAVER_URL`, `DEMO_HOPPSCOTCH_URL`,
  `DEMO_HOPPSCOTCH_COLLECTION`, `DEMO_API_BASE`, …). **Read the URLs from there — never
  hardcode a port in a beat or a doc.**
- It **pre-configures the run's own Postgres** as the CloudBeaver connection (JDBC URL,
  user, dev password) and writes a Hoppscotch import file with the run's real API base
  (`$VIDEO_DIR/demo-tools/hoppscotch-collection.json` → Collections → Import). Both point
  at the thing under test, not at mock data.
- **The evidence gate fails a beat that falls back to a custom UI while these tools are
  up.** If `demo-tools.sh require` is green, the only acceptable surface is the real tool.
  If the tools genuinely cannot run (no DinD, no images, no browser), **stop and ask the
  user** — do not substitute.
- **Google Sheets has a login gate.** It is a Google account in the run's Chrome profile.
  Check it is signed in before writing the beat; if it is not, **ask the user** (they may
  sign in) — never swap in a hand-built table. Everything else here is local and
  password-free.
- Images (pre-pull them into the cage for offline runs) and cost: `dbeaver/cloudbeaver`
  705 MB, `hoppscotch/hoppscotch` 832 MB, `postgres:16` 451 MB; ~2 GB RAM for the three
  containers. First `up` pulls (~2–4 min); later runs start in seconds because the
  containers, the CloudBeaver workspace volume and Hoppscotch's Postgres volume persist.

## Which surface for which change

**Before any of the surfaces below, the diagram carries the structure.** A schema or
architecture change gets a Mermaid ERD / architecture beat in the video (see
`diagrams.md`) — mandatory, rendered from source, before the BEFORE beat. The surfaces
here are for the *behaviour* the diagram cannot show: the real row, the real payload, the
real email. A diagram plus one live surface beats three screenshots of the same page.

Read the diff (and the P6 tour notes) and pick a surface for **every headless change
class** you find. One beat per class is enough; a purely headless ticket may spend all
4–6 beats here.

| change in the diff | surface (first resort) | what to show | BEFORE / AFTER |
|---|---|---|---|
| migration, new table/column/index, type change | **the ERD beat first** (`diagrams.md`), then **CloudBeaver** against the run's own database (the preconfigured `Run DB (workflow)` connection) | the ERD shows the objects and the FK the change relies on; CloudBeaver shows the object itself: table → columns, the new index, the DDL the migration ran; then a real `SELECT` on real rows in its SQL editor | BEFORE = pre-migration DB (revert the migration / reset to the base-branch state), AFTER = migrated. Same screen, polarity in the caption |
| RLS, grants, tenant scoping, policies | Studio's table policies / SQL editor (`pg_policies`) | the policy row, then the *same* query returning 0 rows for the wrong tenant and rows for the right one | two SQL tabs, or BEFORE = policy absent → rows leak |
| backend route, permission, middleware, job, cron, webhook | **VS Code for the Web** diff (`github.dev`) or the PR **Files changed** view | scroll file by file; expand the one hunk that matters; name the function and what it now does | open base vs head (or the PR diff), same file twice |
| API surface, request/response shape, validation, status codes | **Hoppscotch** (self-hosted, `demo-tools.sh`) | the URL → request body → response body; then the failure case (`401`/`403`/`422`) when the diff touches auth | BEFORE = old payload shape / the endpoint that was open; AFTER = new shape / the denial |
| email, notification, reminder | **Mailpit** (or Inbucket / the repo's catcher) | the rendered message, its headers, its links | trigger the flow in both states, keep both messages |
| spreadsheet, CSV export, report | **Google Sheets** (signed in — login gate) — never a hand-built table | the rows the feature writes, the new column | export before/after |
| logs, queue, background jobs, metrics, traces | Dozzle / a BullMQ board / Grafana / Jaeger / the org's APM | the lines that prove the new path ran, filtered on the new event | before = event absent |
| object storage, uploads, files | MinIO console, or the app's file surface | the object written/read | |
| CLI tool, script, generator | a terminal pane (**last resort** — prefer a browser surface) | the command and its legible output | run it twice |

**Order of preference, every time:** (1) a service the repo already ships → (2) an OSS
container the cage can run → (3) a hosted app, only if the target is reachable from the
local browser and CORS allows it → (4) a raw GitHub/API surface. **Prefer open source.**
If the best surface is unreachable, use the next one and say which one you used and why
in the PR body — never fake a surface, never invent numbers.

## Recipes (what to open, and how)

- **CloudBeaver** (OSS, Apache-2.0): `bash scripts/demo-tools.sh up` starts it on
  `127.0.0.1:8978` with the run's Postgres already configured as **Run DB (workflow)**.
  Open the connection → SQL editor. Do not `psql` into a terminal for the beat: a
  terminal is a formatting choice, CloudBeaver is the tool a reviewer recognises.
  **⛔ Do NOT demo through Supabase Studio** (or any Supabase-local-only console), even when the
  repo's *dev* stack happens to be Supabase: it is a dev-only vendor surface that the product does
  not ship, so it misrepresents the change to a reviewer (user directive 2026-10-16). When the dev
  stack is Supabase, point the preconfigured CloudBeaver connection at that same Postgres URL
  (`postgresql://…@127.0.0.1:<db-port>/postgres` — read the live mapped port from `docker ps`
  inside the cage) and film that instead. Same database, vendor-neutral surface.
- **Mailpit** (repo compose): `docker compose -f docker-compose.<dev>.yml up -d mailpit`
  → UI `http://127.0.0.1:8025`, SMTP `1025`. Show the rendered message, not the JSON.
- **Hoppscotch** (OSS): `bash scripts/demo-tools.sh up` starts the AIO image on
  `127.0.0.1:3300` with its own Postgres and the API base you passed in `DEMO_API_BASE`.
  Import `$VIDEO_DIR/demo-tools/hoppscotch-collection.json` (Collections → Import) to get
  the run's real requests in the app. Request from the **browser** (the cage's Chrome),
  not from a terminal: Hoppscotch shows method, URL, payload and response exactly as a
  reviewer would see them. If the backend ships OpenAPI, its own Swagger/Redoc/Scalar
  page (`/docs`, `/api-docs`, `/reference`) is an acceptable alternative — generated from
  the code the PR changed.
- **VS Code for the Web**: `https://github.dev/<org>/<repo>` — open the PR's branch, split
  the editor, scroll each changed file. The run's Chrome is already signed in to GitHub as
  the run's account. **Never type credentials for an external service** (SHARED-POLICY):
  if a sign-in prompt appears, stop and use the always-available
  `https://github.com/<org>/<repo>/pull/<N>/files` instead. A self-hosted `code-server` on
  the worktree (`code-server --bind-addr 127.0.0.1:<port> <worktree>`) is the OSS
  alternative when it is available.
- **Google Sheets**: an external service — only when the account is already signed in;
  otherwise use a local CSV/table surface and say so.

Start any extra container **inside the cage**, publish to `127.0.0.1` only, and stop it
after the capture. Never touch the run's own dev-server/DB containers.

## What to narrate

- **One sentence per file (or table), in plain language**: what it does now that it did
  not before. Name the function, not the line number; name the failure it prevents.
- **Backend changes: state the security implications explicitly** — authentication vs
  authorization, tenant/org scoping, input validation, rate limiting, secrets handling,
  PII in logs, and what an attacker could do before vs now. If the change touches
  permissions and you did not show a denial, you have not shown the change.
- **Highlight the design choices that matter** for a reviewer: idempotency, transaction
  boundaries, index/N+1 cost, backwards compatibility, feature flags, rollback path,
  migration reversibility, and anything deliberately *not* done (and why).
- Never narrate code line by line, and never read the diff aloud — tell the story of the
  change and let the scrolling carry the detail.

## Storyboard and capture rules for these beats

- Model them as ordinary beats with `source: "web"` and a real `url` (see V1/V2). They are
  **cross-origin**, so the capture does a real `open`, and re-logs-in when the beat needs
  the app session.
- **Prime the tab before the pump.** A web IDE or DB console can take 10–20 s on first
  load; that belongs *before* the beat, not inside it. Open it, wait for `readyText`, then
  start the beat.
- `readyText` must be content you have actually seen on that screen: a table name, a
  column name, the ticket id in a filename, the response body's text. Never a guess.
- Keep the tool's own chrome visible (URL bar or title) so the reviewer can tell which
  surface they are looking at. Bump the page zoom (`ctrl+=`) when the text would be
  unreadable at 1600×900.
- Move slowly and **hold on the hunk/row you are narrating** — the injected fake cursor is
  what makes the scroll followable.
- Budget: 45–75 s total, so after the 1–2 mandatory diagram beats **at most ~1 non-UI
  surface beat** fits in a mixed video. When the change is purely headless, the filmed
  beats are all non-UI (schema console → API → guard) after the diagrams.
- The same surfaces belong in the **P7 screenshots** (annotated in the page, never painted
  onto the PNG) — see `workflow-do-tour` P7.1/P7.5 and `workflow-do/scripts/annotate-shot.sh`
  + `check-annotations.sh` for the evidence gate. The video and the PR's screenshots should
  not tell two different stories.

## Checks (V7)

- [ ] every non-UI change class in the diff is filmed on a real surface, or explicitly
      excused in the PR body (with the reason)
- [ ] **no beat shows a custom table/HTML page or pretty-printed `curl`** when
      `demo-tools.sh require` is green; API beats are in Hoppscotch, DB beats in
      CloudBeaver, spreadsheet beats in Google Sheets
- [ ] the URLs used in the beats came from `$VIDEO_DIR/demo-tools.json` (no hardcoded ports)
- [ ] a schema / migration / report change has its **ERD beat** (`diagrams.md`), and the
      tables in it are the ones the diff actually reads and writes
- [ ] any schema beat shows the **same object** before and after, not two unrelated screens
- [ ] any auth-adjacent API beat includes a failure response (`401`/`403`/`422`)
- [ ] security implications are in the narration whenever the diff is backend/auth
- [ ] every tool surface on screen is identifiable, and its text is readable at 1600×900
- [ ] no extra container or browser tab is left running after the capture
