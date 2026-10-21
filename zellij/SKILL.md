---
name: zellij
description: >
  Drive Zellij from any shell or agent: run commands in new panes or tabs,
  target tabs and panes by stable ID (never by focus), manage pane layout,
  and remote-control TUI panes you are not focused in (dump-screen,
  keystroke injection). Use when asked to open panes/tabs, rename or close
  tabs, target a specific tab, or type into another pane.
---

# Zellij skill

Zellij runs on the HOST. `ZELLIJ` / `ZELLIJ_SESSION_NAME` must be set. From
inside a Docker cage, the CLI reaches the host zellij server via the mounted
socket (or the `zellij-wrapper.sh` socat proxy on macOS) — targeting works
identically, capture command stdout as usual.

## Launch commands

```bash
zellij run --direction right -- cmd   # new pane; directions: right|left|up|down
zellij run --stacked --in-place -- cmd # stacked pane on the focused pane
zellij run --floating -- cmd           # floating pane
zellij action new-tab --name "name" -- cmd  # new tab running cmd — prints its TAB_ID
```

Flags: `--cwd <path>`, `--close-on-exit` (pane disappears when cmd exits),
`--start-suspended` (create the pane, wait for ENTER), `--name <pane-name>`.
`zellij run` prints the new pane's ID (e.g. `terminal_6`); plain numbers work
as pane-id aliases (`3` == `terminal_3`).

## Tab targeting rules (IDs, never focus) — READ THIS FIRST

Zellij's bare actions (`rename-tab`, `close-pane`, `close-tab`, `run`, …) act
on whatever the USER currently has focused. If the user clicked to another
tab, your rename/launch/close lands in THEIR tab. Never rely on focus when
the target matters — always target by **stable ID**:

```bash
# Discovering IDs — list-tabs is the source of truth
zellij action list-tabs          # TAB_ID  POSITION  NAME
zellij action list-panes -j      # pane ids + tab_id (jq-friendly)

# Your OWN tab id — from your pane id, never current-tab-info (that answers
# "what is focused right now", not "which tab is mine"):
MY_TAB_ID=$(zellij action list-panes -j 2>/dev/null \
  | jq -r --argjson p "$ZELLIJ_PANE_ID" \
      '.[] | select(.is_plugin|not) | select(.id==$p) | .tab_id')

# Targeted actions
zellij action rename-tab "$NAME" --tab-id "$MY_TAB_ID"
zellij action close-tab-by-id "$TAB_ID"
zellij action go-to-tab-by-id "$TAB_ID"            # only if you MEAN to focus it
zellij run --tab-id "$TAB_ID" --name "pane" -- cmd  # pane lands in THAT tab
```

- **`new-tab` prints the created tab's stable ID — capture it** if you'll
  rename/close/target that tab later (env var, handoff note). Bare `zellij
  run` adds a pane to the FOCUSED tab — `new-tab` is the only correct way to
  create a tab.
- **Tab IDs are auto-assigned, stable, and never reused.** Renames change the
  NAME, `move-tab` changes POSITION — the ID stays. Capture once and it stays
  valid through any reorganizing the user does; `list-tabs` is the source of
  truth.
- **Focus caveat:** targeted rename/close do NOT change what the user is
  looking at — but `zellij run --tab-id <other-tab>` gives the new pane FOCUS,
  jumping the user's viewport to that tab. Batch several panes in one go,
  then return focus (`zellij action move-focus left`). Renames/closes never
  need this.

## Pane layout

- `zellij action move-focus right|left|up|down`
- `zellij action set-column-width "+20%"` (resizes the focused pane)
- Keep a primary pane (e.g. the agent pane) always visible; stack task panes
  beside it, one visible at a time (Ctrl-PageUp / Ctrl-PageDown). Never open
  a pane that covers or obscures the primary pane.

## Remote-controlling another pane (TUIs)

To type into, read, or interact with a pane you are NOT focused in, use
`action` commands with `-p <pane-id>`:

```bash
# Find the app's pane: note its pid+tty (ps aux | grep <app>), dump candidates
zellij action dump-screen -p terminal_3   # read what a pane currently shows
zellij action write -p terminal_3 27 79 81 # raw bytes: F2 (F1..F4 = 27 79 80..83)
zellij action write -p terminal_3 13       # Enter = CR
zellij action write -p terminal_3 1        # Ctrl+A
zellij action write-chars -p terminal_3 'some text'
```

Gotchas (hard-won):

- **`write-chars` silently drops `\n`** — never embed newlines in text. To
  press Enter, send `write 13` (CR). Do NOT send `10` (LF): Textual apps
  (harlequin, etc.) map LF to ctrl+j, which often RUNS the query.
- **Type in ~30-char chunks with `sleep 0.25` between `write-chars` calls** —
  fast long pastes drop bytes, and Enter keypresses mid-typing can accept TUI
  autocomplete and mangle text.
- **`dump-screen` can be stale** for panes in inactive tabs. If dumps don't
  change but keystrokes seem delivered, verify the app consumes input: compare
  `grep rchar /proc/<app-pid>/io` before/after a test keystroke.
- **Read keybindings from the app's source instead of guessing** (e.g.
  harlequin: `site-packages/harlequin_vscode/*.py` — f2 = focus editor,
  ctrl+a = select all, ctrl+enter/ctrl+j = run).
- **Verify after every batch** with `dump-screen` — blind multi-step typing
  compounds errors fast.