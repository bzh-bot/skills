---
name: workflow-do
description: >
  Execute an EXISTING ticket (never created by the run) through grooming, implementation
  in a worktree, testing, screenshots + video, a PR marked ready for review, and — in iterate mode —
  review fixes, merge, and post-merge. Two entry modes: build (ticket → P0–P8, ends
  at a PR READY FOR REVIEW — ship-p8 undrafts and verifies isDraft=false — no polling) and iterate (PR link or "iterate": rehydrate from
  the worktree handoff + PR, apply review fixes, then either merge on a fresh peer approval
  of the current head or park awaiting re-review; post-merge). Writes the PR link back to the ticket. v8.5: the sequencer is a
  DETERMINISTIC SCRIPT (workflow-do.ts, node+tsx) run in the FOREGROUND by the run
  pane's bash launcher (run.sh) — the run pane is not a pi session, and pi appears
  only as the FAILURE FALLBACK. One interactive stage agent per MAIN stage, in zellij
  panes of the run's tab. Stage agents report to the chief of staff session that launched the
  cage (WORKFLOW_ORCH_SESSION).
  Requires zellij + pi-intercom.
metadata:
  version: "8.5.4"
---

# Workflow: Workflow Do (script-sequenced run, launcher in the run pane)

Drive a ticket from idea (or existing reference) to a merged PR. **Since v7 the
orchestration is a deterministic TypeScript script** —
`~/.agents/skills/workflow-do/workflow-do.ts` — run directly with `node + tsx`
(both present on the host and inside the cage image; tsx at
`~/.pi/agent/npm/node_modules/tsx/dist/cli.mjs`).
Since v8.5 the **run pane runs the bash launcher**
`~/.agents/skills/workflow-do/run.sh`, which runs the script in the foreground — no
detached pi supervisor session. The script owns stage order and launches one
interactive stage agent per MAIN stage. It is **not** the stage handoff target: when the
cage was launched by the chief of staff, the chief of staff supplies that target as
`WORKFLOW_ORCH_SESSION` and stages address the chief of staff directly.

## Where the knowledge lives (do not duplicate it)

| What | Where |
|---|---|
| Shared policy (hard prerequisites, DB-first, tab naming, pane management, **v7 script contract**) | `~/.agents/skills/workflow-do/SHARED-POLICY.md` |
| P0–P3 phase knowledge | `~/.agents/skills/workflow-do-prebuild/SKILL.md` |
| P4–P5 | `~/.agents/skills/workflow-do-build/SKILL.md` |
| P6–P7 | `~/.agents/skills/workflow-do-tour/SKILL.md` |
| P8 + P10 | `~/.agents/skills/workflow-do-ship/SKILL.md` |
| P11–P13 | `~/.agents/skills/workflow-do-post/SKILL.md` |
| Wrap-up, hydrate (9.6), review-state (9.7–9.9) | `~/.agents/skills/workflow-do/prompts/{wrap-up,hydrate,review-state}.md` |
| Stage surrender instructions (per stage) | `~/.agents/skills/workflow-do/prompts/<stage>.md` |

## Inputs

`$ARGUMENTS` is one of:
- a **ticket reference** (URL, ID, or search term) → **build mode**
- a **free-form idea with no ticket** → NOT supported: **workflow-do never creates
  tickets.** Tell the user to create the ticket first (manually or via the chief of staff),
  then re-run with the ticket reference. Do not spin up a run without a ticket.
- a **PR link / number** or "iterate" → **iterate mode**
- a **PR link / number with "review"** → **review mode** (peer review of
  another author's PR: reconcile → audit → walkthrough → verdict gate; cage-based
  like any run but NEVER merges/pushes/modifies code; ends when the review posts
  and ticket statuses update — review mode never changes the draft state (the author's
  own build/iterate run owns draft→ready); someone
  else's PR is never touched. Knowledge: workflow-do-review sub-skill)

Routing: PR given → iterate (if merged, report and stop; closed unmerged, tell the
user). Ticket in progress with draft PR → build (resumable). PR ready for review /
changes requested → iterate. Free-form idea → **reject: no ticket, no run.** User wording overrides
("do/build" → build; "fix/merge/address comments" → iterate; **"review X" → review**).

## Hard Prerequisites (run-pane level)

- **Zellij is active** (`$ZELLIJ` / `$ZELLIJ_SESSION_NAME` set). If not: FAIL LOUDLY — no background-process fallback.
- **pi-intercom available** (the `intercom` tool). Stage agents coordinate via intercom; the script sends progress via its own broker client.
- Detailed access checks (system prompt, pi update, git signing, Chrome, agent-browser, GitHub login) are **Phase 0** — owned by the prebuild stage, not by you.

## The run pane — the launcher, not a pi session

The run pane runs **`~/.agents/skills/workflow-do/run.sh`** (bash), not a pi session.
On a chief of staff kickoff `cage()` sees `WORKFLOW_LAUNCHER` and runs the launcher instead of
`pi`; the launcher runs the deterministic sequencer in the **foreground**, tee'd into
the run log, so the pane shows the run live. It takes its inputs from the environment,
never from argv quoting:

| Var | Meaning |
|---|---|
| `WORKFLOW_MODE` | `build` / `iterate` / `review` (required) |
| `WORKFLOW_TICKET_REF` | ticket reference, or PR ref/number (required) |
| `WORKFLOW_RESUME=1` | `--resume` — continue after the last OK stage |
| `WORKFLOW_STAGE=<name>` | `--stage <name>` — rerun one stage |
| `WORKFLOW_FRESH=1` | `--fresh` — discard stale run state |
| `WORKFLOW_PI_NAME` | fallback pi session name (`pi --name`) |
| `WORKFLOW_PI_MODEL` | model pin (cage() default; stage panes inherit it too) |
| `WORKFLOW_FALLBACK_PI` | `1` (default) → hand over to pi on a non-zero exit; `0` → just exit |
| `WORKFLOW_RUN_LOG` | run log (default `/tmp/workflow-do-run.log`) |
| `WORKFLOW_RUN_ENV` | run state (default `/tmp/workflow-run.env`) |
| `WORKFLOW_CHECK=1` | print the resolved launch, exit 0, run **nothing** (self-check) |

**pi is the failure fallback, never a retry loop.** When the sequencer exits non-zero
the launcher prints a failure banner (exit code, run log, run env, the exact resume
command) and, unless `WORKFLOW_FALLBACK_PI=0`, `exec`s `pi --name "$WORKFLOW_PI_NAME"`
with a short prompt: read the run log and run env, diagnose, fix the root cause,
relaunch with `--resume` or `--stage <name>`, and intercom the chief of staff when done. The
launcher never loops, never retries blind, never blocks on intercom, and never flips
a PR's draft state by hand — the stages own that (`gh pr ready` + verified `isDraft=false`).

Who does what:

- **Stage panes are still pi agents** (`workflow-<stage>-<T>`), launched and closed by
  the script — exactly as the stage map below and the sub-skills describe. Unchanged.
- **Human gates are answered in the stage panes** in the run's tab (grill, security
  gate, the conditional merge gate — fresh peer approval of the current head, no fix
  round — and the optional review tour) — the human works them in-pane.
- **The chief of staff is the notification and cage-cleanup target** (`WORKFLOW_ORCH_SESSION`,
  recorded as `ORCHESTRATOR_SESSION` in the run env): stage agents intercom it for
  handoffs and blocked questions, the script notifies it at transitions/failures, and it
  removes the cage once the run reports complete. The run pane is a bash process and
  cannot intercom.
- **The failure-fallback pi session** (non-zero exit only) diagnoses, relaunches and
  reports. It does not re-ask gates and does not touch the PR's ready state.

Verify the wiring without launching a run (inside a cage):
`WORKFLOW_CHECK=1 WORKFLOW_MODE=build WORKFLOW_TICKET_REF=<T> ~/.agents/skills/workflow-do/run.sh`
prints the resolved command and exits 0 without running anything.

## Your job — when a pi session IS driving the run (fallback or manual kickoff)

On a chief of staff kickoff no pi session is involved. These steps apply to the two cases where
one is: (a) the **failure fallback** the launcher starts after a non-zero exit, and
(b) a **manual, launcher-less kickoff** where someone runs this skill in a pi session.

1. **Identity.** The launcher names the fallback session `WORKFLOW_PI_NAME` (`workflow-orch-<TICKET_ID>`) — the legacy in-cage supervisor name; verify with a quick intercom status instead of renaming. The intercom target is NOT derived from that name: the chief of staff supplies `WORKFLOW_ORCH_SESSION` in the launch env and the script records the resolved value as `ORCHESTRATOR_SESSION="<id>"` in `/tmp/workflow-run.env` at run start (resolution order: supplied value → recorded `ORCHESTRATOR_RESOLVED_NAME` from an older run's env → `workflow-orch-<TICKET_ID>`), so with a chief of staff kickoff this session receives no handoffs. Only when nothing was supplied (manual kickoff) does the `workflow-orch-<TICKET_ID>` name become the last-resort target — stage panes use `ORCHESTRATOR_SESSION` as their definitive handoff target. Named sessions are what the post-stage P12 friction scan uses to find every session for this ticket.
2. **Launch the sequencer — in a pane, never detached.** Run the launcher in a pane of the run's tab so the run is visible and the failure fallback works:

```bash
# in a zellij pane of the run's tab (NOT in a blocking bash tool call — a run lasts hours):
WORKFLOW_MODE=build WORKFLOW_TICKET_REF="<TICKET-XXX>" ~/.agents/skills/workflow-do/run.sh
# iterate mode instead:  WORKFLOW_MODE=iterate WORKFLOW_TICKET_REF="<PR-ref>"
```

   **The old detached launch is retired** (2026-10-15): a backgrounded script has no pane
   to show the run, no failure banner, and no fallback — do not `setsid`/`nohup` it. The
   launcher runs the script in the foreground and hands over to the fallback pi in the
   same pane when it exits non-zero.

   The script needs the cage env (`WORKFLOW_TAB_ID`, `WORKFLOW_CWD`,
   `WORKFLOW_CONTAINER_ID`, `ZELLIJ_SESSION_NAME`) — it runs inside the cage, so
   run it in an environment that has them (export from your own env if missing;
   cage() exports them to your session).
3. **Supervise** (end your turn after launching — wake-ups come to you):
   - Stage agents `intercom send` their handoffs to the **chief of staff** (the session that
     launched the cage) at each stage start/finish — you do not receive them when a
     chief of staff supplied `WORKFLOW_ORCH_SESSION`.
   - The script also notifies you directly (broker client, non-fatal) at stage transitions and failures.
   - The user watches stage panes in this tab and works the in-pane gates (security gate, the conditional merge gate — fresh peer approval, no fix round — and the optional review tour) there.
   - **Human gates are addressed to the chief of staff (policy changed 2026-10-15, superseding the
     2026-10-07 <KEY-200> relay policy).** With a chief of staff kickoff the chief of staff is the only bridge
     for a remote human: stages `intercom ask` it directly, so this pi session must NOT expect
     gate questions and must NOT re-ask them. You still see gates the human works in-pane in
     this tab (security gate, the conditional merge gate — fresh peer approval, no fix round — and the optional review tour) and keep the run moving. Only
     when the chief of staff supplied no target (manual kickoff) does this session remain the fallback
     target and relay — in that case `intercom ask` the chief of staff with the gate's exact prompt +
     options and wait for the decision, then inject it into the pane.
   - **Injecting a decision into a parked pane.** A pane blocked in `ask_user_question`
     cannot read intercom. Release it first — `zellij --session <s> action write -p
     <pane-id> 27` (Esc) — then `intercom send` the decision; or, when the human has
     explicitly chosen, take the highlighted option with `zellij --session <s> action
     write -p <pane-id> 13` (Enter). Check the cursor first (`dump-screen | grep '❯'`),
     and **never press Enter on a gate the human has not answered**. Re-present the gate
     if the Esc cancelled it; an Esc is never an answer.
   - **Stage closure is automatic** (2026-10-08): the mechanical "close this stage?" prompts were removed from every interactive stage. The script verifies the stage's OUT block and closes the pane — no session confirms closure.
   - **Late-arriving decisions.** A human decision can arrive after the script already took
     the equivalent action (<KEY-200>: a reviewer-request hold landed 9 min *after* ship-p8
     had requested the reviewer). Apply the human's intent to the current state — e.g.
     `gh pr edit --remove-reviewer` — record the timeline in the run env, and report what
     already happened instead of claiming the instruction was honoured.
4. **Intervene when the script halts** (it fails loudly + notifies you):
   - Read `$RUN_LOG` and `/tmp/workflow-run.status`; inspect `/tmp/workflow-run.env` (append-only) for the missing/`blocked` stage.
   - **Access failures have two purpose-built scripts — use them instead of improvising:**
     - `bash ~/.agents/skills/workflow-do/scripts/preflight.sh` (also `run.sh preflight`) prints
       PASS/FAIL/SKIP for dashboard env + `NEXT_PUBLIC_*` sign-in keys, AWS SSO, GitHub API auth,
       browser GitHub login (over the run Chrome's CDP port) and local dashboard `JWT_SECRET`, with a
       one-line fix per FAIL. The script runs it automatically BEFORE the tour and refuses to launch
       the tour pane on a FAIL; re-run it after fixing anything. Repo-aware: checks that do not apply
       are SKIP, and `PREFLIGHT_SKIP="aws-sso github-api"` / `PREFLIGHT_REQUIRED_ENV_KEYS="…"` scope
       it for a repo with no AWS/GitHub/frontend dependency.
     - `bash ~/.agents/skills/workflow-do/scripts/chrome.sh status` then `... chrome.sh revive` for the
       run's browser: the port is FIXED and recorded as `CHROME_CDP_PORT`, revive is idempotent and
       relaunches on the SAME profile that recorded port. Never launch Chrome by hand and never pass
       `--remote-debugging-port=0`.
   - Fix the root cause (append missing vars, ask the user, fix the pane's blocker), then relaunch: `workflow-do.ts --resume` (continue after last OK stage) or `workflow-do.ts --stage <name>` (rerun one stage). Use `--fresh` to discard stale run state.
   - If a stage pane is stuck with the user away, do not kill it — check `/tmp/workflow-run.status`.
   - **Stage panes are launched idempotently** (2026-10-19, <KEY-210> showed two tour panes):
     `launchStagePane` adopts a persisted pane id from `/tmp/workflow-panes-<stage>`, then an existing
     pane by exact title, then a live `pi --name <pane>` process; it polls `list-panes` with short
     backoff and re-checks both signals before its one permitted retry. It never starts a second pane
     for the same stage — if it fails, read the log and restart the zellij session rather than
     launching a pane yourself.
   - **Container loss (e.g. disk-full cage death):** if /tmp state vanished but the worktree survived, rehydrate instead of restarting: point hydrate at the surviving `$WORKTREE` — it re-derives the brief and run state from `$WORKTREE/.workflow-build-out-handoff.md`, `$WORKTREE/.workflow/`, and the PR body (worktree handoff files survive the cage; /tmp does not). Mark `BRIEF_STALE="1"` so downstream stages re-derive rather than trust it. (Proven 2026-09-06: prior build run lost to disk-full container; iterate run recovered fully via hydrate from the worktree handoff.)
5. **When the script exits**: build mode parks at a **PR READY FOR REVIEW** (ship-p8 marked it ready and the script independently verified `isDraft=false`; Wrap-up handoff written; the build run always closes). Iterate mode ends merged + post done ONLY on a fresh peer approval of the current head with no fix round; after a fix round it parks awaiting re-review (PR ready for review, ticket back at the PRE-REVIEW status — `ready to test`, another org `working` — no merge). **Review mode ends at the verdict gate** — review posted, ticket statuses updated, nothing merged. Print the final report (Output Format below) and stop — no session-close prompt (removed 2026-10-08).
6. **Report the cage name to the HOST session the moment the run is FINISHED, and let the host remove the cage immediately** — FINISHED means **completed** (build: PR ready + Wrap-up done; iterate: merged + post done), **PARKED** (awaiting re-review, approval gate, blocked), or **failed**. **A cage never outlives its run**: a parked run is a finished run, so its cage is removed at once, never left sitting open. The run reports its cage name (`cage-<4digits>-<4hex>`) in the same message that announces the park or completion — the host removes it immediately: it closes the run's tab (which fires `cage()`'s exit trap), then explicitly `docker rm -f`s the cage and re-checks that it is gone. The cage's DinD layers are the disk cost — a finished run no longer needs the in-container /tmp state.

   **A parked run expects its cage to be gone.** Nothing may depend on in-container `/tmp` state after a park — that state is gone with the cage by design. All durable state lives in the worktree plus `$WORKTREE/.workflow-handoff.env`, which is the resume path.

   **⚠️ You cannot do this yourself.** A pi session in the run's pane runs INSIDE the run's cage, so its `docker` CLI talks to the cage's own DinD daemon and never sees the cage container itself: `docker rm -f cage-…` either fails with "container not found" or — if forced — **deletes the container you are running in and kills your own session mid-report** (the same in-cage `docker ps` blindness noted in SHARED-POLICY).

   **Do this instead:** `intercom send` the completion/park notice to the launching/host session (the chief of staff — `chief of staff`, or the target recorded as `ORCHESTRATOR_SESSION` in `/tmp/workflow-run.env`) **with the cage name**, and let that out-of-cage session run the cleanup:
   ```bash
   # HOST-SIDE (run by the launching/chief-of-staff session, NOT inside the cage):
   docker rm -f cage-<id> && rm -rf /mnt/external/cage-dind/cage-<id>
   ```
   If intercom is unavailable, simply state the cage name in your final report — the host session reclaims it. Never block on this: cleanup is the host's job, not a stage's.

   Resume after cleanup uses the **worktree plus its `$WORKTREE/.workflow-handoff.env`** (the worktree-rehydrate path), NOT the in-container `/tmp` state — that state is gone with the cage by design. Also do NOT remove the worktree, the screenshots, or browser panes on completion — iterate mode / post-merge needs those.

## Handoff / state contract (summary)

- `/tmp/workflow-run.env` — append-only `KEY="value"` blocks; live run state; last value wins. **Never overwrite.**
- `$WORKTREE/.workflow-handoff.env` — durable cross-session carrier (append-only, newest last); written at P9.4 by the script, read by iterate-mode hydrate.
- Prose (brief, fix lists) lives in files (`/tmp/workflow-brief.md`, `/tmp/workflow-fixlist.md`), paths recorded as vars.
- Full contract: SHARED-POLICY.md → "Stage Orchestration (script model, v7)".

## Stage map (what the script runs)

The script owns two pre-stage gates: a **Chrome liveness probe** before every browser-using stage
(one automatic relaunch on the same profile, recording `CHROME_CDP_PORT`) and the **preflight**
before the tour (`scripts/preflight.sh`) — a FAIL there stops the run before the tour pane spins.

| Stage pane | Phases | Kind | Surrender → |
|---|---|---|---|
| `workflow-scout-<T>` | context gathering (build mode only) | autonomous | prebuild |
| `workflow-prebuild-<T>` | P0–P3 | interactive | build |
| `workflow-build-<T>` | P4–P5 | autonomous | tour |
| `workflow-tour-<T>` | P7 (screenshots + video) | autonomous | ship-p8 |
| `workflow-ship-p8-<T>` | P8 (finalize + mark ready for review) | autonomous | wrap-up |
| `workflow-wrap-up-<T>` | P9.1–9.5 | interactive | script: handoff (always closes) |
| `workflow-hydrate-<T>` | 9.6 | autonomous (iterate fresh run only) | review-state |
| `workflow-review-state-<T>` | 9.7–9.9 | interactive | script: fix round / conditional merge gate (fresh approval, no fix round) / park awaiting re-review |
| `workflow-build-fix-<T>` | P4–P5 fix round | autonomous (+tour if UI changed) | review-state (fix round already ran → parks for re-review) |
| `workflow-ship-p10-<T>` | P10 | autonomous (only after a fresh-approval merge gate) | post |
| `workflow-post-<T>` | P11–P13 | autonomous | run complete |
| `workflow-review-gather-<T>` | reconcile + context scan | autonomous | review-audit |
| `workflow-review-audit-<T>` | local verification + 4-pass audit | autonomous | review-walkthrough |
| `workflow-review-walkthrough-<T>` | finding decisions + optional review tour | interactive | review-verdict |
| `workflow-review-verdict-<T>` | atomic GH review post + ticket statuses (review mode never touches the draft state — the author's run owns draft→ready) | interactive | run complete |

**Status gate (policy 2026-10-15):** the **pre-review → review-pending transition is HUMAN-ONLY.**
A run stops at the pre-review status — `ready to test` in one org / `working` in a ClickUp org — and may
never write the review-pending status (`Review Pending` / `testing / in review`). The human makes
that move when they hand the work to the reviewer; the reviewer's verdict then drives the
approved/denied statuses. See SHARED-POLICY.md.

## Host notification (pi-intercom)

Keep the launching host session (= the chief of staff, `WORKFLOW_ORCH_SESSION`) in the loop —
stage agents intercom-send progress at each transition and `intercom ask` at parked
gates; the script notifies the same target on failures and at completion. The run pane
itself (the launcher, a bash process) never intercoms. If intercom is unavailable, skip
silently — never block on it.

## Session close note

When the run finishes (PR ready for review in build mode; merged + post done in
iterate mode), the script exits 0, the launcher prints the completion line and the pane
returns to a shell prompt. A pi session in that pane (failure fallback / manual kickoff)
prints the final report (Output Format below) and stops — do **not** ask whether to close
the session (removed 2026-10-08). Do NOT clean up the worktree or browser panes —
iterate mode / post-merge needs them. DO let the chief of staff remove the run's cage container
per step 6 above, so its DinD layer does not linger on the host disk.

## Output Format

```
## Workflow Do — <ticket-id> <title>

| Stage | Status | Notes |
|---|---|---|
| Prebuild (P0–P3) | ✅ | org resolved, tracker read, ticket created, worktree + draft PR |
| Build (P4–P5) | ✅ | implemented, tests green, summary posted |
| Tour (P6–P7) | ✅ | <N>/<N> criteria passed, screenshots on PR |
| Ship P8 | ✅ | PR marked READY FOR REVIEW (isDraft=false verified), ticket at pre-review (`ready to test` / another org `working`) |
| Wrap-up | ✅ | guide presented; iterate later: workflow-do.ts iterate <PR> |
| Review fixes / P10 / Post | ✅/— | iterate mode only |

**Ticket:** <URL>
**PR:** <URL>
**Branch/Worktree:** <kept in build mode; removed after merge in iterate mode>
```