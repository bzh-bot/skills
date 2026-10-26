# Vendored copy — do not edit here

This directory is a **copy** of
[`mendeljacks/pi-tool-display`](https://github.com/mendeljacks/pi-tool-display),
vendored so a fresh machine gets the extension from this repo alone (the previous
form was a symlink to `~/repos/mendeljacks/pi-tool-display`, which does not exist
on servers).

- source commit: `1615a80` — "feat(bash): render authored intent/tool comments as the bash call header"
- vendored: 2026-10-26
- excluded: `node_modules/`, `.git/`

There are no runtime dependencies — only peer deps on
`@earendil-works/pi-coding-agent` / `@earendil-works/pi-tui`, which pi provides —
so no `npm install` is needed for this copy to load.

## Updating

```bash
rsync -a --exclude node_modules --exclude .git \
  ~/repos/mendeljacks/pi-tool-display/ ~/.pi/agent/extensions/pi-tool-display/
```

Then commit `pi: re-vendor tool display from <new-sha>` in this repo.

## Config

pi reads the **live** config from `~/.pi/agent/extensions-config/pi-tool-display.json`
(tracked in this repo). The `config.json` shipped inside the copy is upstream's
default/example and is not what pi loads.
