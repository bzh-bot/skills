---
name: workflow-do-build
version: 1.5.0
description: "workflow-do sub-skill — phases P4–P5 (Implement; Verify: test, DRY, quality, self-review, summary, AI-slop). Loaded by a workflow-do worker session the script launches as a named zellij pane (pi --name), coordinated via pi-intercom. Not invoked directly."
---

# Build agent — workflow-do-build (Phases P4–P5)

> **`workflow-do` worker sub-skill.** You are a full pi session launched by the
`workflow-do` script as a **named zellij pane** (`pi --name workflow-build-...`),
NOT a subagent tool call. Your launch prompt tells you which phase(s) to run
and inlines the handoff. Load this skill by reading its SKILL.md first.

**Your session name is in your launch prompt** (e.g. `workflow-p4-<TICKET>`).
Every report/question goes to the **chief-of-staff session** — the session that launched this
cage. Your task file prints its intercom target (`ORCHESTRATOR_SESSION` in the run env,
supplied by the chief of staff at kickoff). Pass `--name` once; the name persists.

## Handoff contract

> **v7 script model:** the sequencer is the deterministic script
> `~/.agents/skills/workflow-do/workflow-do.ts`. Your OUT vars are appended to
> `/tmp/workflow-run.env` (append-only) plus a `STAGE_DONE` block; your pane is
> launched and closed by the script. Read `~/.agents/skills/workflow-do/SHARED-POLICY.md`
> -> "Stage Orchestration (script model, v7)" for the full contract, and your stage
> prompt file (`~/.agents/skills/workflow-do/prompts/`) for the exact surrender steps.

You are **autonomous**: no human in your pane. Run to completion, then send your OUT handoff to the chief-of-staff session via `intercom send` (target: the intercom target in your task file / `ORCHESTRATOR_SESSION` in the run env). You do NOT converse with the user in your pane.

**IN — variables in your `task` prompt:**
- everything from the `workflow-do-prebuild` OUT handoff: `TICKET_ID`, `TICKET_URL`, `FEATURE_TAG`, `ORG`, `REPO_NAME`, `REPO_ROOT`, `SOURCE_REPO`, `INTEGRATION_BRANCH`, `PKG_MGR`, `BRANCH_NAME`, `WORKTREE`, `PR_NUMBER`, `PR_URL`, `WORKFLOW_*` env, `SCREENSHOTS_DIR`, `DB_URL`, detected flags, running dev-server state
- the **5-element brief** + acceptance criteria (your implementation contract — implement against the brief's done-criteria)

**OUT — your final message (handoff back to the chief-of-staff session):**
- implementation complete (DB → backend → frontend, DB-first order)
- tests / lint / typecheck pass; DRY check, quality check, self-review done
- summary written to a LOCAL file (never in the PR body); AI-slop check passed
- branch pushed; `PR_NUMBER` / `PR_URL` confirmed
- `SCREENSHOTS_DIR` created; dev servers + DB still running (leave them up for the tour worker)

## Operating rules

- **Read the shared policy first:** `~/.agents/skills/workflow-do/SHARED-POLICY.md` (see its FIRST ACTION note). Do this before any phase task.
- Run phases P4 → P5 in order, every substep.
- **Task tracking:** `TaskList`, then `TaskCreate` for only `P4.*` and `P5.*` substeps; mark `in_progress`/`completed` as you go. Prefix every sub-step `TaskCreate` subject with the phase emoji (🔐 P0, 🔍 P1, ❓ P2, 📦 P3, 💻 P4, 🧪 P5, 📸 P6, 🖥️ P7, 🚀 P8, ⏳ P9, ✅ P10, 📡 P11, 🔄 P12, 📧 P13) — emojis no longer go in zellij tab names; they live on the pi-task subjects.
- Rename your zellij tab at each transition: `workflow_rename_tab "${TICKET_ID}: P<n>.<sub> <Verb> ${FEATURE_TAG}"`.
- Access verification (P0) was already completed by `workflow-do-prebuild` — the Hard Prerequisites below are already satisfied; do not re-run P0.
- **No human in your pane.** If you hit a decision boundary you cannot resolve from the codebase (merge conflict, design trade-off, failing CI with unclear cause), send `intercom({ action: "ask", to: "<chief-of-staff session from your task file>", message: "<question>" })` — it blocks until the chief of staff replies with the answer — the chief of staff is the only bridge to the human outside the cage. Do not block silently and do not guess on non-trivial decisions.
- **`file` is NOT installed in the cage image.** Don't use it for MIME/type detection (screenshots, attachments) — it fails with "command not found". Use ImageMagick's `identify` (present for image inspection — dimensions/format, and the video contact sheet) instead. ImageMagick is **not** used to annotate: annotations are drawn in the page (`scripts/annotate-shot.sh`).
- When P4–P5 are done, return your **OUT** handoff summary. Do NOT start the tour — the script spawns `workflow-do-tour` next.

## Shared policy

**FIRST ACTION before any phase work:** read
`~/.agents/skills/workflow-do/SHARED-POLICY.md` and follow it for the entire run
(Hard Prerequisites, DB-First Thinking Order, implementation style pointers,
Zellij tab naming, pane management). It applies to every workflow-do worker —
this file no longer duplicates it.
## Your phases

## Phase 4 — Implement

```bash
workflow_rename_tab "${TICKET_ID}: P4.1 Implement ${FEATURE_TAG}"
```

### 4.1 Implement (DB-First Order)

**→ TaskUpdate: P4.1 → in_progress**

Work inside the worktree. Implement in DB-first order:

1. **Database changes first** — migrations, schema updates, seed data adjustments
2. **Backend changes second** — API routes, services, RBAC, validation, side effects
3. **Frontend changes last** — state management, then components/visuals

For each layer:

- **Implement incrementally** — small, reversible changes
- **Run tests continuously** after each meaningful change
- **Run lint/type checks**: discover from `package.json` scripts or project docs
- **Commit frequently**: `git commit -S -m "<ticket-id>: <what changed>"` (use `-S` only if signing is configured). **If the commit fails with typecheck/lint errors from a pre-commit hook (Husky, lint-staged), run codegen first** (`pnpm run generate` or project equivalent) — see Phase 3.5. Do NOT use `--no-verify` to bypass hooks.
- **Git identity must never be guessed**: the cage env wires the org gitconfig (`$ORG_CONFIG_DIR/gitconfig-*`) so `user.name`/`user.email` are always set. If `git commit` fails with a missing identity, that is a wiring bug — STOP and ask the user; never invent an identity and never copy one from the branch's commit history (a mismatched identity corrupts attribution). (Learned 2026-09-22.)
- **Push to branch**: `git push origin $BRANCH_NAME`

**→ TaskUpdate: P4.1 → completed**

---

## Phase 5 — Verify (Test, DRY, Quality, Review, Summary)

**→ TaskUpdate: P5 → in_progress**

```bash
workflow_rename_tab "${TICKET_ID}: P5.1 Verify · tests ${FEATURE_TAG}"
```

### 5.1 Verify Implementation (DB-First)

**→ TaskUpdate: P5.1 → in_progress**

The test environment (DB, dev servers, baseline checks) was set up in **Phase 3.6–3.8** before implementation started. DB is running with seed data, dev servers are live, and baseline test/lint results were recorded. This phase verifies the **changes** made in Phase 4 — not the infrastructure.

Verify correctness in the same order as implementation:

#### 5.1.1 Database Verification

**→ Remember: Update task P5.1 in TaskList as you work through this substep.**

- Connect to the DB and verify schema changes exist:
  ```bash
  psql "$DB_URL" -c "\d <table_name>"
  psql "$DB_URL" -c "SELECT * FROM information_schema.table_constraints WHERE table_name = '<table>';"
  ```
- Run queries that exercise the new schema
- Verify seed data is correct for the new structures

#### 5.1.2 Backend Verification

**→ Remember: Update task P5.1 in TaskList as you work through this substep.**

- Test API endpoints directly (curl/httpie):
  - Correct responses for valid requests
  - Proper error codes for invalid requests
  - RBAC enforcement (try with different auth levels)
  - Side effects fire correctly (check DB state after mutations)
- Run automated backend tests:
  ```bash
  cd "$WORKTREE/$BACKEND_DIR" && $PKG_MGR test
  ```

#### 5.1.3 Frontend Verification

**→ Remember: Update task P5.1 in TaskList as you work through this substep.**

- Verify state management works
- Visual verification with agent-browser (see 4.4)
  - **If a login screen appears**, this is a LOCAL dev service — find or create test credentials per the **Browser Login Handling** policy in Hard Prerequisites. Check `.env.local`, `.env.development`, seed scripts, or create a test user via the DB. Auto-fill the login form and proceed. Do NOT ask the user.
- Run frontend tests:
  ```bash
  cd "$WORKTREE/$FRONTEND_DIR" && $PKG_MGR test
  ```

**→ TaskUpdate: P5.1 → completed**

### 5.2 Automated Tests

**→ TaskUpdate: P5.2 → in_progress**

Run ALL relevant test suites:

```bash
cd "$WORKTREE"

# Unit tests
$PKG_MGR test 2>&1

# Type checking (if TypeScript)
$PKG_MGR run typecheck 2>&1 || npx tsc --noEmit 2>&1

# Linting
$PKG_MGR run lint 2>&1

# E2E tests (if they exist)
$PKG_MGR run test:e2e 2>&1 || true
```

⚠️ **Mocks are not the real API.** If a new code path's behavior depends on
external-API semantics (Stripe attach/detach, webhook payloads, OAuth flows,
3DS, etc.), passing unit tests proves NOTHING about that branch — mocks encode
your assumptions, not the provider's rules. Real-world example: unit
tests mocked Stripe's `paymentMethods.attach` as always succeeding, but real
Stripe **rejects attach on a PM already attached to another customer** (and
detach is permanent) — the mock hid an impossible re-attach design until the
tour's live test-mode verification caught it, forcing a mid-tour redesign. When
you mock an external client: (1) state the real-world rule you're assuming in a
`// why` comment next to the mock, and (2) flag the branch in your P5 summary
so the tour stage verifies it live against the provider's test/sandbox mode.

### 5.3 Prepare Screenshot Directory + Sample Data

**→ TaskUpdate: P5.3 → in_progress**

Screenshots and the video are captured in **Phase 7** (autonomous). The interactive tour is **not** part of the build flow — it lives in review mode (`workflow-do-review`). This phase only sets up the screenshot directory and ensures sample data is seeded so Phase 7 can run smoothly.

The `SCREENSHOTS_DIR` is created here so it's ready for Phase 7:

```bash
SCREENSHOTS_DIR="$WORKTREE/screenshots"
mkdir -p "$SCREENSHOTS_DIR"

# Ensure screenshots directory is gitignored
if ! grep -q "screenshots/" "$WORKTREE/.gitignore" 2>/dev/null; then
  echo "screenshots/" >> "$WORKTREE/.gitignore"
fi
```

See **Phase 7** for the full screenshot capture + annotation + upload workflow.

### 5.3.1 Sample Data Requirements

Seed enough data to make the feature's effect **obvious** during the Guided Tour — not just one row, but enough to see patterns:

- If adding a filter: seed 10+ items where the filter would show a meaningful subset
- If adding a column: seed data with varied values in that column
- If adding a form: seed data that the form would create/edit

### 5.3.2 Seed Edge-Case Data

If testing requires specific data states:

| Scenario              | What to seed                                           |
| --------------------- | ------------------------------------------------------ |
| Happy path            | Normal data with all fields populated                  |
| Empty state           | No related records                                     |
| Boundary values       | Min/max values, zero, null optional fields             |
| Error states          | Invalid/corrupt data that should be handled gracefully |
| Permission boundaries | Data visible to different roles                        |

**→ TaskUpdate: P5.3 → completed**

---

### 5.4 DRY Check

**→ TaskUpdate: P5.4 → in_progress**

**→ Print: "Phase 5.4: Checking code is as DRY as possible..."**

```bash
workflow_rename_tab "${TICKET_ID}: P5.5 Verify · DRY ${FEATURE_TAG}"
```

Before reviewing, verify the implementation doesn't duplicate logic that already exists or should be shared. This prevents the exact class of bug we found during invoicing testing — where the manual invoice UI and the backend schedule job had separate entry-gathering logic that drifted apart.

#### 5.4.1 Check for Duplicated Functionality

**→ Remember: Update task P5.4 in TaskList as you work through this substep.**

Scan the codebase for logic that appears in more than one place and could share a common function:

```bash
cd "$WORKTREE"
# Search for functions/queries that fetch the same data in different places.
# Replace the grep terms below with entities relevant to THIS ticket's domain.
grep -rn "<feature-specific-tables-or-functions>" \
  backend/src frontend/src --include=*.ts --include=*.tsx \
  | grep -v node_modules | grep -v .test.
```

Ask these questions for each piece of logic found in multiple places:

- **Is the same query/logic duplicated?** If two code paths fetch the same data with different SQL/queries, they WILL drift. Extract a shared SQL function.
- **Do they have different RLS behavior?** A direct SQL query (service role) and an authenticated query can return different results for the same logical query. This is a bug waiting to happen — unify behind a `SECURITY DEFINER` function.
- **Could a future change break one path but not the other?** If yes, they should share common logic.

#### 5.4.2 Check for Shared Logic Opportunities

**→ Remember: Update task P5.4 in TaskList as you work through this substep.**

Look for patterns where functionality is implemented separately but conceptually shared:

| Pattern                                          | Example                                                       | Fix                                                        |
| ------------------------------------------------ | ------------------------------------------------------------- | ---------------------------------------------------------- |
| Same query, different callers                    | Backend inline SQL + frontend query fetching the same records | Shared `SECURITY DEFINER` SQL function                     |
| Same business rule, different enforcement points | A calculation done in 3 separate places                       | Unify behind one shared function — check for similar cases |
| Same validation, different layers                | Frontend + backend both validating the same thing             | Extract to a shared module or SQL constraint               |

#### 5.4.3 Database Schema Convention Check

**→ Remember: Update task P5.4 in TaskList as you work through this substep.**

Review any new or modified database columns for consistency:

- **Naming convention**: Are column names consistent with existing conventions in the same table and related tables? (e.g., if one table uses `payment_id`, don't use `transaction_id` for the same concept elsewhere — pick one and stick to it)
- **Type consistency**: Are similar columns the same type across tables? (e.g., if `amount` is `NUMERIC(12,2)` in one table, it should be in all tables)
- **Don't store computable values**: If a column's value can be derived from other columns or a simple query, don't store it unless there's a specific performance or consistency reason. Computed columns that can drift from their source are a source of bugs.
- **Flag any inconsistencies found** — raise them as a note in the PR or as a separate ticket if they affect existing code outside this PR's scope.

#### 5.4.4 Report Findings

**→ Remember: Update task P5.4 in TaskList as you work through this substep.**

If DRY issues or schema inconsistencies are found:

1. **Fixable in this PR** → fix them now (extract shared function, rename column, remove computed column)
2. **Out of scope but important** → record it in `/tmp/workflow-loose-ends.md` (severity-prefixed) and note it in the PR description
3. **Intentional duplication** → document why in a code comment

**→ TaskUpdate: P5.4 → completed**

### 5.5 Quality Check

**→ TaskUpdate: P5.5 → in_progress**

**→ Print: "Phase 5.5: Quality check — silent failures, DB structure, security, UX..."**

```bash
workflow_rename_tab "${TICKET_ID}: P5.6 Verify · quality ${FEATURE_TAG}"
```

A holistic quality pass before review. Check for issues that automated tests miss.

#### 5.5.1 Silent Failure Check

**→ Remember: Update task P5.5 in TaskList as you work through this substep.**

Verify that nothing fails silently — every error path should be visible, logged, or surfaced:

- **Backend**: Check all `catch` blocks, error handlers, and promise rejections — are errors swallowed or logged and surfaced?
- **Database**: Check for `ON DELETE` without `CASCADE`/`SET NULL` that could silently orphan rows
- **Frontend**: Check for unhandled promise rejections, missing error boundaries, and `try/catch` that eats errors
- **API**: Check for endpoints that return 200 with empty/error payloads instead of proper error codes

#### 5.5.2 Database Structure Check

**→ Remember: Update task P5.5 in TaskList as you work through this substep.**

Verify the DB structure makes sense:

- **Foreign keys**: Are all FKs indexed? Are `ON DELETE` actions correct (CASCADE/SET NULL/RESTRICT)?
- **Constraints**: Are NOT NULL, UNIQUE, CHECK constraints present where needed?
- **Naming**: Are column names consistent across tables? (e.g., `user_id` everywhere, not `userId` in one place)
- **Indexes**: Are query patterns supported by indexes? No missing indexes for hot paths?
- **Migrations**: Are migrations reversible? Do they handle the existing data correctly?

#### 5.5.3 Security Check

**→ Remember: Update task P5.5 in TaskList as you work through this substep.**

Verify no security issues:

- **RBAC**: Are access controls enforced on every endpoint? No bypass paths?
- **SQL injection**: Are all queries parameterized? No string concatenation for SQL?
- **XSS**: Is user input properly escaped in the frontend? No `dangerouslySetInnerHTML` without sanitization?
- **Secrets**: Are any secrets exposed in the code, logs, or API responses?
- **CORS**: Are CORS policies restrictive enough?
- **Auth**: Are session tokens validated on every request?

#### 5.5.4 UX Check

**→ Remember: Update task P5.5 in TaskList as you work through this substep.**

Verify the user experience is satisfactory:

- **Loading states**: Are loading spinners/skeletons shown during async operations?
- **Error states**: Are error messages user-friendly? No raw stack traces shown to users?
- **Empty states**: Are empty states handled with helpful messages and CTAs?
- **Accessibility**: Are form labels present? Are interactive elements keyboard-navigable?
- **Responsive**: Does the UI work on different screen sizes?
- **Feedback**: Does the user get confirmation after actions (create/update/delete)?

#### 5.5.5 Report and Fix

**→ Remember: Update task P5.5 in TaskList as you work through this substep.**

For each issue found:

1. **Fixable in this PR** → fix it now
2. **Out of scope** → record it in `/tmp/workflow-loose-ends.md` (severity-prefixed) and note it in the PR
3. **Intentional** → document why in a code comment

**→ TaskUpdate: P5.5 → completed**

---

---

### 5.6 Self-Review the Worktree

**→ TaskUpdate: P5.6 → in_progress**

**→ Print: "Phase 5.6: Self-reviewing changes..."**

```bash
workflow_rename_tab "${TICKET_ID}: P5.7 Verify · self-review ${FEATURE_TAG}"
```

Self-review the changes as a senior engineer before requesting external review.

#### 5.6.1 Diff Review

**→ Remember: Update task P5.6 in TaskList as you work through this substep.**

```bash
cd "$WORKTREE"
git diff "origin/$INTEGRATION_BRANCH"...HEAD
```

Review for:

1. **Correctness** — logic errors, off-by-one, mishandled error paths
2. **Security** — injection, auth bypass, secret exposure, XSS
3. **Convention violations** — project patterns broken without justification
4. **API/contract breakage** — changed signatures without updated callers
5. **Dead code** — unused exports, commented-out blocks, ownerless TODOs
6. **Clean code** — misleading names, duplicated logic, excessive complexity
7. **Env defaults** — never hardcode production values (URLs, API keys, emails). Missing env must throw, not silently fall back to localhost or a guessed address.
8. **Email/HTML injection** — escape all user-provided values interpolated into HTML (emails, templates). Strip CR/LF from header fields.
9. **Silent error swallowing** — no empty `.catch(() => {})`. At minimum log the error; if the caller needs to know, throw or fail the request.
10. **External API contracts** — verify endpoint paths, methods, and response shapes against the actual API docs or source before coding. Never guess.
11. **Project utilities** — grep for existing URL resolution, auth, and permission utilities before writing new ones. Use `getBackendUrl()`, `check_invoice_access()`, etc.
12. **Transaction scope** — wrap related multi-INSERT/UPDATE loops in a single transaction with ROLLBACK + cleanup on failure. Fire-and-forget cleanup after COMMIT is not enough.
13. **Permission enforcement** — if adding a new frontend permission gate, enforce the same permission in the backend (the backend bypasses RLS via the pool, so frontend-only gates are bypassable via direct API calls).
14. **Schema edit blast radius** — when removing or renaming columns in shared schema files (e.g. `01-tables.sql`), grep the column name across ALL tables in the file first. A sed/replace that matches too broadly can break unrelated tables.

#### 5.6.2 Update Documentation

**→ Remember: Update task P5.6 in TaskList as you work through this substep.**

Check and update if relevant:

- **CHANGELOG.md** — if it exists, add an entry for this change
- **API documentation** — if OpenAPI/Swagger specs exist and endpoints changed, update them
- **README** — if setup steps or usage changed, update
- **ADRs** — if an architectural decision was made, document it in `docs/adr/`

#### 5.6.3 Apply Fixes

**→ Remember: Update task P5.6 in TaskList as you work through this substep.**

Fix obvious and mechanical issues directly. For anything non-trivial or with multiple approaches, `intercom({ action: "ask", to: "<chief-of-staff session from your task file>", message })` and await the reply — this stage has no human in its pane.

#### 5.6.4 Sync with Target Branch

**→ Remember: Update task P5.6 in TaskList as you work through this substep.**

```bash
cd "$WORKTREE"
git fetch origin "$INTEGRATION_BRANCH"
BEHIND=$(git log HEAD.."origin/$INTEGRATION_BRANCH" --oneline | wc -l)
if [ "$BEHIND" -gt 0 ]; then
  git merge "origin/$INTEGRATION_BRANCH"
  # Resolve conflicts inside the MERGE commit — never rebase at this point
  # (a rebase rewrites the SHAs the PR's reviews/approvals are attached to). Then push.
fi
```

#### 5.6.5 Verify CI & Quality Gates

**→ Remember: Update task P5.6 in TaskList as you work through this substep.**

```bash
PR_NUMBER=$(gh pr view --json number -q .number)
gh pr checks "$PR_NUMBER"
```

All checks must pass. If any fail: diagnose, fix, push, re-check.

**Quality gates and PR review comments:**

- Check for **code quality gate failures** (coverage, complexity, duplication) by inspecting GitHub check run output. Use the project's quality-gate skill or preferences if available.
- Check for **automated review comments** (Copilot, static analysis inline annotations) and address or respond to each.
- Check for **human reviewer comments** and address all blocking feedback before proceeding.

If the project has a configured quality gate, its checks appear in `gh pr checks` output. A failing quality gate is a blocker — fix the underlying issue (add tests for coverage, extract functions for complexity) rather than ignoring it.

**→ TaskUpdate: P5.6 → completed**

---

### 5.7 Summary (LOCAL artifact — never appended to the PR body)

**→ TaskUpdate: P5.7 → in_progress**

**→ Print: "Phase 5.7: Generating summary for human review..."**

```bash
workflow_rename_tab "${TICKET_ID}: P5.8 Verify · summary ${FEATURE_TAG}"
```

Write a structured summary **to a LOCAL file only** — it is the stage's own detail sheet for the tour and the wrap-up verification guide. It must NOT be appended to the PR body and must not be posted as a PR comment: the PR body is written by ship-p8 P8.1 and carries only Motivation / Summary of changes (high level) / Risk / Screenshots / Ticket. (User directive 2026-09-30: no how-to-test, how-to-verify, files-changed or verified-in-this-pass sections in PR bodies.)

#### 5.7.1 Write the Summary to a Local File

**→ Remember: Update task P5.7 in TaskList as you work through this substep.**

```bash
SUMMARY_FILE="/tmp/workflow-do-summary-$(date +%s).md"
# (write summary content to $SUMMARY_FILE — see 5.7.2 below)

# Record the path for the tour / wrap-up; do NOT `gh pr edit` or `gh pr comment` with it:
printf 'SUMMARY_FILE="%s"\n' "$SUMMARY_FILE" >> /tmp/workflow-run.env
```

**NEVER put this summary in the PR body** — no `gh pr edit --body-file`, no `gh pr comment`.

#### 5.7.2 Summary Content Structure

**→ Remember: Update task P5.7 in TaskList as you work through this substep.**

Write the summary in this exact order (DB-first), including only sections relevant to the change:

````markdown
# <ticket-id> — <title>

## Database Changes

### Schema

| Table   | Column | Type   | Nullable | Default   | Notes                  |
| ------- | ------ | ------ | -------- | --------- | ---------------------- |
| <table> | <col>  | <type> | Y/N      | <default> | Added/Modified/Removed |

### Relationships

- <table_a>.<col> → <table_b>.<col> (FK, ON DELETE CASCADE)

### Migrations

- `<migration-file>`: <one-line description>

### Example Data

```sql
-- What a typical row looks like after this change:
SELECT * FROM <table> WHERE <condition> LIMIT 1;
-- → { id: 1, new_col: 'value', ... }
```

## Backend Changes

### Endpoints

| Method | Path                | Auth          | Description        |
| ------ | ------------------- | ------------- | ------------------ |
| POST   | /api/<resource>     | admin         | Create new <thing> |
| GET    | /api/<resource>/:id | authenticated | Get <thing> by ID  |

### RBAC / Access Control

- **Create**: Only `admin` role can create
- **Read**: Any authenticated user can read their own; admins can read all
- **Update**: Owner or admin
- **Delete**: Admin only

### Side Effects

- On create: sends email notification to <who>
- On delete: cascades to <related table>, invalidates cache

### Edge Cases Handled

- Concurrent writes: uses optimistic locking via `updated_at`
- Empty state: returns 404 with `{ error: "not_found" }`
- Invalid input: returns 422 with field-level errors

## Frontend Changes

### State Management

- **Server state**: React Query / SWR key `['<resource>', id]`
- **Local state**: `useState` for form fields in `<Component>`
- **URL state**: Route param `/:id` maps to resource fetch

### Components

| Component | File                    | Change                  |
| --------- | ----------------------- | ----------------------- |
| `<Name>`  | `src/components/<path>` | New — renders <what>    |
| `<Name>`  | `src/components/<path>` | Modified — added <what> |

### UI States

- **Loading**: Skeleton placeholder in `<Component>`
- **Empty**: "No <things> yet" message with CTA
- **Error**: Toast notification with retry action
- **Success**: Optimistic update + background refetch

### Routes

| Route               | Component         | Auth          |
| ------------------- | ----------------- | ------------- |
| `/settings/<thing>` | `<PageComponent>` | authenticated |

````

#### 5.7.3 Key Principles for the Summary

**→ Remember: Update task P5.7 in TaskList as you work through this substep.**

- **Be concrete** — show actual column names, actual endpoint paths, actual component names
- **Show examples** — a SQL query result, a curl command, a component render
- **Highlight RBAC** — who can do what is critical information for review
- **Show state flow** — where data comes from, where it's stored, how it reaches the UI
- **Keep it scannable** — tables over paragraphs, code blocks over descriptions
- **Only include relevant sections** — if there are no DB changes, omit that section

### 5.8 AI-Slop Check on Changed/Created Files

**→ TaskUpdate: P5.8 → in_progress**

```bash
workflow_rename_tab "${TICKET_ID}: P5.8 Verify · AI-slop ${FEATURE_TAG}"
```

Scan every file changed or created by this run (against the integration branch) for **AI-slop** — telltale AI-generated phrasing that a human reviewer would flag. This covers code comments, docstrings/READMEs, commit messages, and the PR description/summary you just wrote. Slop is noise at best and a review smell at worst; remove it before the PR is marked ready.

There is **no script for this** — check it yourself directly. Gather the surface:

```bash
cd "$WORKTREE"
git diff --name-only ${INTEGRATION_BRANCH:-origin/main}...HEAD
git ls-files --others --exclude-standard          # new untracked files
git log --no-merges --format="%B" ${INTEGRATION_BRANCH:-origin/main}..HEAD   # commit messages
gh pr view "$PR_NUMBER" --json body --jq .body 2>/dev/null                    # PR body
```

Mechanical pre-filter, then judge every hit yourself:

```bash
# em-dash as prose punctuation + the usual AI filler phrases
grep -rn $'\u2014' --include='*' $FILES
grep -rniE "Certainly|I'd be happy to|Let me (help|explain)|It's (important|worth) (to note|noting)|delve (into|deeper)|navigate (the|through)|leverage|in the realm of|under the hood|Overall,|In summary,|As an AI|Furthermore,|Moreover,|It's crucial|a testament to|seamless|robust and|comprehensive|In conclusion|game-changer|supercharge|Let's dive" $FILES
```

**What counts as slop** — read the flagged lines in context and rephrase or delete:
- Em-dashes `—` used as prose punctuation in comments/docs (replace with ` - ` or rephrase).
- AI filler phrases: "Certainly", "I'd be happy to", "Let me", "It's important to note", "It's worth noting", "delve into", "navigate", "leverage", "realm of", "tapestry", "Overall,", "In summary,", "As an AI".
- Overly wordy or over-formal comments/docs; comments that restate what the code does with general coding knowledge (the skill's own rule #4: "No useless comments").
- **Leaked ticket names/IDs in the code** — comments, strings, log lines, or branch/PR metadata referencing OTHER tickets (e.g. copied code still saying `// <PREFIX>-97: ...`). Comments explaining a decision should reference the current ticket or nothing at all.
- Oxford-comma lists and generated-marketing README tone.

**If you find anything:**
1. Rephrase/remove the offending text — comments should explain *why* (non-obvious decisions), not *what* (restating code) and never in AI voice.
2. Strip em-dashes from prose; use plain hyphens or rewrite the sentence.
3. Re-check the changed lines until clean (or every remaining hit is a justified false positive you note in the summary).
4. Amend commits if commit messages had slop (`git commit --amend` for the tip, or `git rebase -i` to reword older messages — never `--no-verify`).

**If you intentionally keep a flagged phrase** (e.g. a domain term that happens to match), note it in the loose-ends file (`/tmp/workflow-loose-ends.md`) and/or your own run log — **never in the PR body/summary comment.** The PR description is user-facing product documentation; it must never mention AI-slop checks, this workflow's internal QA steps, or any other meta-process commentary. Keep the PR body scoped to what changed and why, for a human reviewer.

```bash
workflow_rename_tab "${TICKET_ID}: P5.8 Verify · conventions ${FEATURE_TAG}"
```

**→ TaskUpdate: P5.8 → completed**

**→ TaskUpdate: P5 → completed. Print: "✅ Phase 5 complete. Verified: tests pass, DRY check done, quality checked, self-reviewed, summary posted, AI-slop check passed, conventions swept. Surrendering — the script spawns the tour stage next."**

---

