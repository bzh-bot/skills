# skills

Agent skills for [pi](https://github.com/earendil-works/pi) and compatible agent
harnesses. Each directory is one skill: a `SKILL.md` with YAML frontmatter (`name`,
`description`) plus whatever scripts, prompts or assets it needs.

The `description` is the only text an agent sees before deciding to load a skill, so
it says *when* to use it, not just what it does.

## Install

```sh
git clone https://github.com/mendeljacks/skills ~/src/skills
~/src/skills/install.sh          # symlink every skill into ~/.agents/skills/
~/src/skills/install.sh slack zellij
~/src/skills/install.sh --copy   # copy instead of symlink (containers, throwaway VMs)
```

Skills resolve from `~/.agents/skills/<name>/SKILL.md`. Symlinks are the default so
edits in the clone are live immediately. Re-run `install.sh` after pulling.

## Environment

Some skills read a private configuration instead of hardcoding yours. Nothing here
ships credentials; these are the names they expect:

| variable | used by | meaning |
|---|---|---|
| `TRIAGE_DIR` | `chief-of-staff`, `triage-*` | directory holding the accounts registry (`orgs.json`, `platforms.json`, `accounts/`, `banks/`, `state.json`) |
| `ORG_CONFIG` | `chief-of-staff`, `workflow-do` | file mapping repository/owner names to registry org keys |
| `ORG_CONFIG_DIR` | `workflow-do`, `triage-bank-account` | per-org private config (git identity, env files) |
| `BACKEND_ENV_FILE` | `triage-bank-account` | env file with the accounting backend URL/db/user/key |
| `VAULT_PATH` | `workflow-do` | path to the secret store, if your flow mounts one |
| `CLICKUP_TOKEN`, `SLACK_*`, `NOTION_API_TOKEN`, `TICKTICK_TOKEN` | the matching integrations | API credentials |
| `OPENROUTER_API_KEY` (or your provider's) | anything calling a model | provider key |

The registry shape is documented in `chief-of-staff/SKILL.md`. It is read with the
`triage` CLI shipped in `chief-of-staff/scripts/triage` (bash + jq only — no python,
no sqlite):

```sh
ln -s ~/src/skills/.agents/skills/chief-of-staff/scripts/triage ~/.local/bin/triage
triage orgs                 # org -> tag, chrome profile, vault, ledger url
triage accounts --json      # every enabled account
triage get <org>            # one org in full
triage due --days 7         # what has not been swept
triage swept <key>          # stamp state.json
```

## The skills

**Browser and terminals** — `agent-browser` (drive the user's real Chrome over CDP),
`zellij` (panes/tabs by id, typing into TUIs you are not focused in).

**Integrations** — `slack`, `notion-api`, `atlassian`, `clickup`, `ticktick`,
`outlook`, `gmail-web`, `whatsapp`. Mechanics only: each expects credentials in the
environment and a signed-in browser where relevant.

**Orchestration** — `chief-of-staff` (asks which flow to run, delegates to worker panes,
reads the registry). It ships the orchestrator, not the readers.

**Readers it drives** — `triage-email`, `triage-chat`, `triage-calendar`,
`triage-monitor`, `triage-ticket-board`, `triage-snapshot`, `triage-goals`,
`triage-confluence-reconcile`, `triage-bank-account`.

**Delivery pipeline** — `workflow-do` (sequencer + prompts, 35 files) and its stages
`workflow-do-prebuild`, `-build`, `-tour`, `-review`, `-ship`, `-post`.

**Media** — `workflow-video-tour` (screencast + narration + avatar overlay),
`workflow-release-video` (chaptered release video). Both ship their assets.

**Utility** — `workflow-flightplan`, `workflow-groceries`, `workflow-update-deps`.

## Writing one

1. One job per skill. If the description needs "and", it is two skills.
2. Put trigger conditions in `description`; that is what the agent matches.
3. Prefer exact commands and selectors over prose.
4. Record the failure mode you actually hit — that is the value, not the happy path.
5. No secrets in the file: read an env var, or a path under the user's own config.

Before committing, check for identifiers you did not mean to publish:

```sh
grep -rniE "(token|secret|api[_-]?key|password)|/home/|~/secrets|@[a-z0-9.-]+\.(com|net)" . | grep -v example
```

## Licence

MIT.
