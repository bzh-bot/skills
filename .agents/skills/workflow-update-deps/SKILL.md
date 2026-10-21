---
name: workflow-update-deps
description: >
  Update this machine's tooling in one pass: the pi CLI, pi's installed
  extensions, pi's model catalogs, then apt update + apt upgrade. Use when the
  user asks to update pi, update extensions/packages, refresh dependencies,
  upgrade the system, or run the chief of staff's "update pi" flow.
allowed-tools: Bash(pi:*), Bash(apt:*), Bash(sudo:*), Bash(~/.agents/skills/workflow-update-deps/scripts/update-deps:*)
---

# workflow-update-deps

One script, run in order:

```bash
~/.agents/skills/workflow-update-deps/scripts/update-deps
```

1. `env -u PI_OFFLINE pi update` — the CLI itself
2. `env -u PI_OFFLINE pi update --extensions` — installed packages
3. `env -u PI_OFFLINE pi update --models` — provider model catalogs (failure tolerated: a stale catalog is not worth aborting on)
4. `sudo apt update` — refresh package lists
5. `sudo apt upgrade -y` — upgrade installed packages

Each pi call clears `PI_OFFLINE`. If your shell rc exports it (a common way to skip
pi's startup update checks), pi's self-update — which is a managed install — honours
the flag too, and the step fails with "Could not determine latest pi version". The
`env -u` makes it work whether or not you export it.

It prints the `old -> new` pi version at the end.

## Run it in a terminal, never in the background

`apt` needs sudo; **if sudo requires a password here**, the flow cannot run
unattended. The script refuses up front if stdin is not a TTY rather
than hanging on the password prompt. Run it from a zellij pane / terminal, and
expect it to take minutes.

Override the apt auto-confirm with `APT_YES= update-deps` if you want to review
the upgrade list before it proceeds.

## After it finishes, report one line

The pi version change, and whether the package steps succeeded. If a later
headless run shows scoped-model warnings for cursor models, open `/model` once
in a TUI session to force live discovery.
