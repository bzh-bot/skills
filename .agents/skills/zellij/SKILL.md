---
name: zellij
description: >
  Drive Zellij from any shell or agent: run commands in new panes or tabs,
  target tabs and panes by stable ID, manage pane layout, and type into or
  read TUI panes you are not focused in. Use when asked to open panes/tabs,
  rename or close tabs, target a specific tab, or send keystrokes to a pane.
---

# Zellij skill

Zellij runs on the HOST; `ZELLIJ` and `ZELLIJ_SESSION_NAME` must be set. From a
container, the CLI reaches the host server through the mounted socket.

## Launch

```bash
zellij run --direction right -- cmd        # pane; right|left|up|down
zellij run --stacked --in-place -- cmd     # stacked on the focused pane
zellij run --floating -- cmd               # floating pane
zellij action new-tab --name "name" -- cmd # prints the new TAB_ID
```

Flags: `--cwd`, `--close-on-exit`, `--start-suspended`, `--name`. `zellij run`
prints a pane id (`terminal_6`); the bare number works as an alias.

## Target by ID, never by focus

Bare actions (`rename-tab`, `close-tab`, `run`) hit whatever the **user** has
focused — if they switched tabs, your command lands in their tab.

```bash
zellij action list-tabs       # TAB_ID  POSITION  NAME
zellij action list-panes -j   # pane ids + tab_id (jq-friendly)
```

- Your own tab id comes from your pane id, not `current-tab-info`:

  ```bash
  MY_TAB_ID=$(zellij action list-panes -j | jq -r --argjson p "$ZELLIJ_PANE_ID" \
    '.[] | select(.is_plugin|not) | select(.id==$p) | .tab_id')
  ```

- `rename-tab <name> --tab-id <id>`, `close-tab-by-id <id>`,
  `go-to-tab-by-id <id>`, `run --tab-id <id> -- cmd`.
- Tab ids are stable and never reused: renames and moves do not change them.
  Capture the id `new-tab` prints.
- Targeted rename/close leave focus alone, but `run --tab-id <other-tab>`
  steals it — batch those, then `move-focus` back.

## Driving a pane you are not focused in

```bash
zellij action dump-screen -p terminal_3     # read what the pane shows
zellij action write -p terminal_3 13        # Enter (CR)
zellij action write -p terminal_3 1         # Ctrl+A
zellij action write -p terminal_3 27 79 81  # F2 (F1..F4 = 27 79 80..83)
zellij action write-chars -p terminal_3 'text'
```

- `write-chars` silently drops newlines — send `write 13` for Enter. Never
  send `10`: Textual apps read LF as ctrl+j, which often submits.
- Type in ~30-character chunks with `sleep 0.25` between calls; long pastes
  drop bytes and an early Enter accepts autocomplete.
- `dump-screen` can be stale for panes in inactive tabs. If keystrokes seem
  lost, check the app is consuming input before retrying blindly.
- `dump-screen` after every batch — blind multi-step typing compounds errors.

## Layout

- `move-focus right|left|up|down`, `set-column-width "+20%"`.
- Keep the user's primary pane visible: add panes beside or stacked, never on
  top of it.

## Radar (agent-status rail)

`zj-radar` is the sidebar that shows each agent/pane's status. It is a separate
program (CLI + `zj_radar.wasm` + a layout), **not** part of this repo, and a box
without it has a broken `Alt r` and silent status reporting.

```bash
zj-radar --version                  # must match the cage image's ZJ_RADAR_VERSION
zj-radar notify pi --status running # what the pi bridge extension calls
zj-radar setup zellij --check      # inspect wiring without writing
zellij -l radar                     # the Alt-r binding: new session with the rail
```

The three artefacts must all exist on the host:

| artefact | path |
|---|---|
| CLI | `zj-radar` on PATH (`/usr/local/bin`) |
| wasm | `~/.config/zellij/plugins/zj_radar.wasm` |
| layout | `~/.config/zellij/layouts/radar.kdl` |

`install.sh` provisions all three (pinned by `ZJ_RADAR_VERSION`) and the config
alias it depends on. Diagnose by symptom:

- **`zellij -l radar` → "layout not found"** — `layouts/radar.kdl` missing. Copy it
  from `~/.local/share/zj-radar/zellij/layouts/` after `zj-radar run --print-cmd`
  materializes that directory.
- **Radar tab opens but is empty** — the plugin cannot read its wasm: check
  `plugins/zj_radar.wasm` exists and the `radar location=` alias in `config.kdl`
  points at it. Do **not** run `zj-radar setup --force`: it rewrites the
  hand-owned alias and flips `naming` to `managed`.
- **No statuses at all, pi works** — `zj-radar` is not on PATH; the pi bridge
  swallows the ENOENT by design. Install the CLI, then restart pi.
- **Version drift** — the CLI and the loaded wasm must be the same release; a
  mismatch shows an empty rail with no error. Re-pin `ZJ_RADAR_VERSION` in both
  `install.sh` and `workflow-do/Dockerfile` together.

[1 more lines in file. Use offset=77 to continue.]

Flags here were checked against zellij 0.44–0.45; if one is rejected, see
`zellij action --help` for the current name.
