#!/usr/bin/env bash
# install.sh — provision a machine for pi + these skills.
#
# One script, two jobs:
#   - install this repo's skills (and the theme/extensions/packages it ships)
#   - make a fresh box usable: gh, node via nvm, pi + extensions, docker where the
#     kernel allows it, a default model, and (optionally) the org configuration
#     copied in from the machine you run it on.
#
#   ./install.sh                      provision THIS machine
#   HOST=gpu-box ./install.sh         provision a remote box over ssh
#   ./install.sh --skills             only install the skills (old behaviour)
#   ./install.sh --skills slack zellij
#   DEST=/some/path ./install.sh --skills
#   PI=0 ./install.sh --skills        skip the .pi/agent themes/extensions/packages
#
# Flags for the full provision:
#   SKIP_SECRETS=1   don't copy ~/secrets (org-config, reviewers, env, gitconfig)
#   SKIP_GH=1        don't run the GitHub device flow
#   SKIP_DOCKER=1    don't try to install docker
#   ORG=<name>       which org's config to copy (default: none — skipped)
#
# Knobs: DEFAULT_PROVIDER, DEFAULT_MODEL, PI_PACKAGES, PI_AUTH_PROVIDERS,
#        PI_MODEL_PROVIDERS, GH_ACCOUNT, GH_EMAIL, MACHINE_NAME, SKILLS_REPO,
#        ZELLIJ_VERSION, NVM_VERSION.
#
# Nothing secret ships in this file: credentials and org config are copied from
# the caller at run time. A remote run stages them in a tarball and hands it to
# the copy of this script on the target.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The repo mirrors $HOME, so a plain clone holds .agents/skills/<name>/SKILL.md;
# a bare checkout used as a work-tree at $HOME has the skills at the same relative
# path. Support both by picking the directory that actually contains SKILL.md files.
if [ -d "$ROOT/.agents/skills" ]; then SRC="$ROOT/.agents/skills"; else SRC="$ROOT"; fi

DEST="${DEST:-$HOME/.agents/skills}"
MODE="link"
SKILLS_ONLY="${SKILLS_ONLY:-0}"
NAMES=()
for arg in "$@"; do
  case "$arg" in
    --skills) SKILLS_ONLY=1 ;;
    --copy)   MODE="copy" ;;
    -h|--help) sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)        NAMES+=("$arg") ;;
  esac
done

say()  { printf '==> %s\n' "$*"; }
warn() { printf '!!  %s\n' "$*" >&2; }

SUDO=""
if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then SUDO="sudo"; fi
sudo_if_needed() { if [ -n "$SUDO" ]; then sudo "$@"; else "$@"; fi; }

# ── skills ────────────────────────────────────────────────────────────────────
install_skills() {
  local targets=()
  if [ "${#NAMES[@]}" -eq 0 ]; then
    while IFS= read -r d; do targets+=("$d"); done < <(find "$SRC" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort)
  else
    targets=("${NAMES[@]}")
  fi
  mkdir -p "$DEST"
  for name in "${targets[@]}"; do
    [ -f "$SRC/$name/SKILL.md" ] || { warn "no skill named '$name'"; continue; }
    rm -rf "${DEST:?}/$name"
    if [ "$MODE" = copy ]; then cp -R "$SRC/$name" "$DEST/$name"; else ln -s "$SRC/$name" "$DEST/$name"; fi
  done

  if [ "${PI:-1}" = 1 ] && [ -d "$ROOT/.pi/agent" ]; then
    local target="$HOME/.pi/agent"
    mkdir -p "$target"
    for kind in themes extensions extensions-config packages; do
      [ -d "$ROOT/.pi/agent/$kind" ] || continue
      mkdir -p "$target/$kind"
      cp -R "$ROOT/.pi/agent/$kind/." "$target/$kind/" 2>/dev/null || true
      echo "  pi    $kind -> $target/$kind"
    done
    for file in APPEND_SYSTEM.md; do
      [ -f "$ROOT/.pi/agent/$file" ] || continue
      cp "$ROOT/.pi/agent/$file" "$target/$file"
      echo "  pi    $file -> $target/$file"
    done
  fi

  echo
  echo "${#targets[@]} skill(s) in $DEST"
  echo "restart pi (or start a new session) to pick them up"
}

if [ "$SKILLS_ONLY" = 1 ]; then
  install_skills
  exit 0
fi

# ── remote transport ─────────────────────────────────────────────────────────
# When HOST is set, stage everything the target needs and run this same script
# there. Secrets are copied as files because the target cannot read this machine.
ORG="${ORG:-}"
LOCAL_AGENT_DIR="$HOME/.pi/agent"
LOCAL_SECRETS="$HOME/secrets"

if [ -n "${HOST:-}" ] && [ "${REMOTE:-0}" != 1 ]; then
  stage="$(mktemp -d)"
  mkdir -p "$stage/pi"
  cp "${BASH_SOURCE[0]}" "$stage/install.sh"

  if [ "${SKIP_SECRETS:-0}" != 1 ] && [ -z "$ORG" ]; then
    warn "ORG is not set — skipping the org configuration copy"
  elif [ "${SKIP_SECRETS:-0}" != 1 ]; then
    mkdir -p "$stage/secrets/$ORG" "$stage/secrets/env"
    [ -f "$LOCAL_SECRETS/org-config.json" ] && cp "$LOCAL_SECRETS/org-config.json" "$stage/secrets/"
    [ -f "$LOCAL_SECRETS/$ORG/reviewers.json" ] && cp "$LOCAL_SECRETS/$ORG/reviewers.json" "$stage/secrets/$ORG/"
    [ -f "$LOCAL_SECRETS/$ORG/gitconfig-$ORG" ] && cp "$LOCAL_SECRETS/$ORG/gitconfig-$ORG" "$stage/secrets/$ORG/"
    shopt -s nullglob
    for f in "$LOCAL_SECRETS"/env/*.env; do
      case "$(basename "$f")" in
        *"$ORG"*|cage-config.env|chrome-profiles.env|atlassian.env) cp "$f" "$stage/secrets/env/" ;;
      esac
    done
    shopt -u nullglob
    for t in "$LOCAL_SECRETS/triage" "$LOCAL_SECRETS/$ORG/triage"; do [ -d "$t" ] && cp -R "$t" "$stage/secrets/" && break; done
  fi

  [ -f "$HOME/.config/zellij/config.kdl" ] && cp "$HOME/.config/zellij/config.kdl" "$stage/zellij.kdl"

  if [ -f "$LOCAL_AGENT_DIR/auth.json" ]; then
    PROV="${PI_AUTH_PROVIDERS:-ollama-cloud openrouter}" python3 - "$LOCAL_AGENT_DIR/auth.json" > "$stage/pi/auth.json" <<'PY'
import json, os, sys
src = json.load(open(sys.argv[1]))
want = set(os.environ.get("PROV", "").split())
print(json.dumps({k: v for k, v in src.items() if k in want}, indent=2))
PY
  fi

  say "staging to $HOST"
  tar czf - -C "$stage" . | ssh "$HOST" 'rm -rf /root/.pisetup && mkdir -p /root/.pisetup && tar xzf - -C /root/.pisetup'
  rm -rf "$stage"
  ssh "$HOST" "REMOTE=1 SKIP_SECRETS=1 ORG=$ORG ${GH_ACCOUNT:+GH_ACCOUNT=$GH_ACCOUNT} ${DEFAULT_PROVIDER:+DEFAULT_PROVIDER=$DEFAULT_PROVIDER} ${DEFAULT_MODEL:+DEFAULT_MODEL=$DEFAULT_MODEL} ${MACHINE_NAME:+MACHINE_NAME=$MACHINE_NAME} bash /root/.pisetup/install.sh; rc=\$?; rm -rf /root/.pisetup; exit \$rc"
  exit 0
fi

# ── target side ──────────────────────────────────────────────────────────────
PI_AUTH_PROVIDERS="${PI_AUTH_PROVIDERS:-ollama-cloud openrouter}"
PI_MODEL_PROVIDERS="${PI_MODEL_PROVIDERS:-ollama-cloud}"
DEFAULT_PROVIDER="${DEFAULT_PROVIDER:-ollama-cloud}"
DEFAULT_MODEL="${DEFAULT_MODEL:-deepseek-v4.1-flash:1017}"
PI_PACKAGES="${PI_PACKAGES:-npm:pi-ollama-cloud npm:pi-intercom npm:@tintinweb/pi-tasks npm:@tintinweb/pi-subagents npm:pi-goal npm:pi-fusion npm:pi-timer npm:pi-notifi npm:pi-context-usage npm:pi-token-meter npm:@juicesharp/rpiv-ask-user-question ./packages/zellij-tab-name}"
GH_ACCOUNT="${GH_ACCOUNT:-$(gh api user --jq .login 2>/dev/null || git config --global user.name || echo root)}"
GH_EMAIL="${GH_EMAIL:-}"
GH_CLIENT_ID="${GH_CLIENT_ID:-178c6fc778ccc68e1d6a}"
GH_SCOPES="${GH_SCOPES:-repo read:org workflow gist}"
MACHINE_NAME="${MACHINE_NAME:-${HOST:-$(hostname -s)}}"
SKILLS_REPO="${SKILLS_REPO:-https://github.com/mendeljacks/skills}"
NVM_VERSION="${NVM_VERSION:-v0.40.3}"
ZELLIJ_VERSION="${ZELLIJ_VERSION:-0.45.1}"
SKILLS_DIR="${SKILLS_DIR:-$HOME/src/skills}"

# staged files (remote runs): place them before anything tries to read them
if [ "${REMOTE:-0}" = 1 ] && [ -d /root/.pisetup ]; then
  say "installing staged credentials and org config"
  if [ -s /root/.pisetup/pi/auth.json ]; then
    mkdir -p "$HOME/.pi/agent"
    python3 - <<'PY'
import json, pathlib
new = json.load(open('/root/.pisetup/pi/auth.json'))
p = pathlib.Path.home() / '.pi/agent/auth.json'
d = json.loads(p.read_text()) if p.exists() else {}
d.update(new)
p.write_text(json.dumps(d, indent=2) + '\n'); p.chmod(0o600)
print('  pi    providers with credentials:', sorted(d))
PY
  fi
  if [ -d /root/.pisetup/secrets ]; then
    mkdir -p "$HOME/secrets"
    cp -a /root/.pisetup/secrets/. "$HOME/secrets/"
    echo "  cfg   copied: $(cd "$HOME/secrets" && find . -type f | tr '\n' ' ')"
  fi
fi

# 1. base packages -------------------------------------------------------------
say "base packages"
missing=""
for b in jq git curl rsync wget; do command -v "$b" >/dev/null 2>&1 || missing="$missing $b"; done
if [ -n "$missing" ]; then
  if command -v apt-get >/dev/null 2>&1; then
    sudo_if_needed apt-get update -qq 2>/dev/null || apt-get update -qq
    sudo_if_needed env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $missing >/dev/null
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y -q $missing >/dev/null
  else
    warn "no package manager for:$missing"
  fi
fi
command -v jq >/dev/null && echo "  jq    $(jq --version)"

# 2. gh ------------------------------------------------------------------------
if command -v gh >/dev/null 2>&1; then
  say "gh present: $(gh --version | head -1)"
else
  say "installing gh"
  VER=$(curl -fsSL https://api.github.com/repos/cli/cli/releases/latest | grep -oP '"tag_name": "v\K[^"]+')
  tmp=$(mktemp -d)
  curl -fsSL "https://github.com/cli/cli/releases/download/v${VER}/gh_${VER}_linux_amd64.tar.gz" | tar -xz -C "$tmp"
  sudo_if_needed install "$tmp/gh_${VER}_linux_amd64/bin/gh" /usr/local/bin/gh
  rm -rf "$tmp"
  gh --version | head -1
fi

# 3. nvm + node + pi -----------------------------------------------------------
if [ -s "$HOME/.nvm/nvm.sh" ]; then
  say "nvm present"
else
  say "installing nvm $NVM_VERSION"
  curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/$NVM_VERSION/install.sh" | bash >/dev/null
fi

say "node LTS and pi"
# shellcheck disable=SC1091
. "$HOME/.nvm/nvm.sh"
nvm install --lts >/dev/null
nvm alias default 'lts/*' >/dev/null
command -v pi >/dev/null 2>&1 || npm i -g @earendil-works/pi-coding-agent >/dev/null
echo "  node  $(node -v) · npm $(npm -v) · pi $(pi --version)"

say "exposing node/npm/pi on the default PATH"
BIN_DIR="$(dirname "$(nvm which default)")"
for b in node npm npx corepack pi; do
  [ -e "$BIN_DIR/$b" ] && sudo_if_needed ln -sf "$BIN_DIR/$b" /usr/local/bin/$b
done
grep -q 'NVM_DIR=' "$HOME/.bashrc" 2>/dev/null || cat >> "$HOME/.bashrc" <<EOF

# nvm/node/pi are not on the default PATH (and .bashrc returns early for
# non-interactive shells, hence the symlinks above)
export NVM_DIR="$HOME/.nvm"
[ -s "\$NVM_DIR/nvm.sh" ] && . "\$NVM_DIR/nvm.sh"
EOF

# 4. docker (only where the kernel allows it) ---------------------------------
if [ "${SKIP_DOCKER:-0}" = 1 ]; then
  warn "SKIP_DOCKER=1"
elif command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  say "docker present: $(docker --version)"
else
  say "docker"
  if unshare -m true 2>/dev/null; then
    if command -v apt-get >/dev/null 2>&1; then
      sudo_if_needed env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq docker.io >/dev/null || warn "docker.io install failed"
    fi
    if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
      sudo_if_needed systemctl enable --now docker >/dev/null 2>&1 || true
    fi
    docker info >/dev/null 2>&1 && echo "  docker $(docker --version)" || warn "docker installed but the daemon is not running"
  else
    warn "this host cannot run docker: unshare/mounts are denied (an unprivileged"
    warn "container, e.g. a Vast.ai container instance — Docker needs a VM rental)"
  fi
fi

# 4b. zellij + login hook ------------------------------------------------------
say "zellij"
if command -v zellij >/dev/null 2>&1; then
  echo "  $(zellij --version)"
else
  curl -fsSL "https://github.com/zellij-org/zellij/releases/download/v$ZELLIJ_VERSION/zellij-x86_64-unknown-linux-musl.tar.gz" \
    | sudo_if_needed tar -xz -C /usr/local/bin zellij
  sudo_if_needed chmod +x /usr/local/bin/zellij
  echo "  $(zellij --version)"
fi

ZELLIJ_CONFIG="$HOME/.config/zellij/config.kdl"
if [ -s /root/.pisetup/zellij.kdl ]; then
  mkdir -p "$(dirname "$ZELLIJ_CONFIG")"
  cp /root/.pisetup/zellij.kdl "$ZELLIJ_CONFIG"
  echo "  config <- staged copy"
elif [ -f "$ZELLIJ_CONFIG" ]; then
  echo "  config already in place"
else
  warn "no zellij config at $ZELLIJ_CONFIG — leaving the default"
fi
if [ -f "$ZELLIJ_CONFIG" ] && ! grep -q '^show_startup_tips' "$ZELLIJ_CONFIG"; then
  printf '\n// keep the login clean: no first-run tip panes\nshow_startup_tips false\nshow_release_notes false\n' >> "$ZELLIJ_CONFIG"
fi

# The Vast images auto-attach tmux from the login hook, and tmux is not installed,
# so the shell exits on connect. Point that hook at zellij instead. No-op elsewhere.
if [ -f "$HOME/.bashrc" ] && grep -q '.no_auto_tmux' "$HOME/.bashrc" && ! grep -q '.no_auto_zellij' "$HOME/.bashrc"; then
  say "patching the tmux login hook to zellij"
  cp "$HOME/.bashrc" "$HOME/.bashrc.bak" 2>/dev/null || true
  HOOK="$HOOK" sed -i '/\.no_auto_tmux/{s|.*|if [ -z "$ZELLIJ" ] \&\& [ -n "$SSH_CONNECTION" ] \&\& [ ! -e "$HOME/.no_auto_zellij" ] \&\& [ -t 0 ]; then zellij attach --create main; exit; fi|}' "$HOME/.bashrc"
  bash -n "$HOME/.bashrc" && echo "  hook patched" || warn "hook patch broke .bashrc — restore $HOME/.bashrc.bak"
fi

# 5. skills --------------------------------------------------------------------
say "skills from $SKILLS_REPO"
if [ -d "$SKILLS_DIR/.git" ]; then
  git -C "$SKILLS_DIR" pull -q --ff-only || warn "could not pull $SKILLS_DIR"
else
  rm -rf "$SKILLS_DIR"
  git clone -q --depth 1 "$SKILLS_REPO" "$SKILLS_DIR"
fi
bash "$SKILLS_DIR/install.sh" --skills --copy 2>&1 | tail -2
echo "  skills $(ls "$DEST" 2>/dev/null | wc -l)"

# 6. pi settings ---------------------------------------------------------------
say "pi settings (default $DEFAULT_PROVIDER/$DEFAULT_MODEL)"
DEF_PROVIDER="$DEFAULT_PROVIDER" DEF_MODEL="$DEFAULT_MODEL" PI_PKGS="$PI_PACKAGES" python3 - <<'PY'
import json, os, pathlib
p = pathlib.Path.home() / '.pi/agent/settings.json'
p.parent.mkdir(parents=True, exist_ok=True)
s = json.loads(p.read_text()) if p.exists() else {}
s['defaultProvider'] = os.environ['DEF_PROVIDER']
s['defaultModel'] = os.environ['DEF_MODEL']
pk = s.setdefault('packages', [])
for item in os.environ['PI_PKGS'].split():
    if item not in pk: pk.append(item)
p.write_text(json.dumps(s, indent=2) + '\n')
print('  packages:', len(pk))
PY

say "installing pi packages"
for p in $PI_PACKAGES; do
  case "$p" in ./*) continue ;; esac
  pi install "$p" 2>&1 | grep -E '^Installed|already' | tail -1 || warn "pi install $p failed"
done

# 7. pi-intercom ---------------------------------------------------------------
say "pi-intercom config (machineName: $MACHINE_NAME)"
MACHINE="$MACHINE_NAME" python3 - <<'PY'
import json, os, pathlib
p = pathlib.Path.home() / '.pi/agent/intercom/config.json'
p.parent.mkdir(parents=True, exist_ok=True)
cfg = json.loads(p.read_text()) if p.exists() else {"enabled": True, "inboundTrigger": "always", "busyDelivery": "steer"}
cfg.setdefault('crossMachine', {})['machineName'] = os.environ['MACHINE']
p.write_text(json.dumps(cfg, indent=2) + '\n')
print('  machineName:', cfg['crossMachine']['machineName'])
PY

# 8. git identity --------------------------------------------------------------
if [ -d "$HOME/secrets/triage" ]; then
  say "registry env for the skills"
  grep -q '^export TRIAGE_DIR=' "$HOME/.bashrc" 2>/dev/null || cat >> "$HOME/.bashrc" <<EOF
export TRIAGE_DIR="$HOME/secrets/triage"
export ORG_CONFIG_DIR="$HOME/secrets"
EOF
  echo "  TRIAGE_DIR=$HOME/secrets/triage"
fi

if [ -z "$GH_EMAIL" ]; then
  GH_EMAIL="$(gh api user --jq '.email // empty' 2>/dev/null || true)"
fi
say "git identity: ${GH_ACCOUNT:-unset} <${GH_EMAIL:-unset}>"
[ -n "$GH_ACCOUNT" ] && git config --global user.name "$GH_ACCOUNT"
[ -n "$GH_EMAIL" ] && git config --global user.email "$GH_EMAIL"

# 9. gh login ------------------------------------------------------------------
if [ "${SKIP_GH:-0}" = 1 ]; then
  warn "SKIP_GH=1 — gh left logged out"
elif gh auth status 2>&1 | grep -q "account $GH_ACCOUNT"; then
  say "gh already logged in as $GH_ACCOUNT"
elif [ -n "${GH_TOKEN_FILE:-}" ] && [ -f "$GH_TOKEN_FILE" ]; then
  say "gh login from $GH_TOKEN_FILE"
  gh auth login --hostname github.com --git-protocol https --with-token < "$GH_TOKEN_FILE"
  gh auth setup-git
else
  say "gh device flow — approve in a browser signed in as $GH_ACCOUNT"
  DC=$(curl -sS -X POST https://github.com/login/device/code -H 'Accept: application/json' \
        -d "client_id=$GH_CLIENT_ID" -d "scope=$GH_SCOPES")
  export DC
  printf '%s' "$DC" | python3 -c 'import sys,json;d=json.load(sys.stdin);print("\n    open https://github.com/login/device and enter: "+d["user_code"]+"\n")'
  python3 - "$GH_CLIENT_ID" <<'PY'
import json, os, subprocess, time, urllib.parse, urllib.request
cid = os.environ.get('GH_CLIENT_ID') or __import__('sys').argv[1]
body = urllib.parse.urlencode({'client_id': cid, 'device_code': os.environ['DC'],
        'grant_type': 'urn:ietf:params:oauth:grant-type:device_code'}).encode()
for _ in range(100):
    req = urllib.request.Request('https://github.com/login/oauth/access_token', data=body,
                                 headers={'Accept': 'application/json'})
    j = json.load(urllib.request.urlopen(req, timeout=20))
    if j.get('access_token'):
        subprocess.run(['gh', 'auth', 'login', '--hostname', 'github.com',
                        '--git-protocol', 'https', '--with-token'],
                       input=j['access_token'], text=True, check=True)
        subprocess.run(['gh', 'auth', 'setup-git'], check=False)
        print('  token installed'); break
    if j.get('error') not in ('authorization_pending', 'slow_down'):
        print('  device flow failed:', j.get('error')); break
    time.sleep(6)
PY
  gh auth status 2>&1 | head -4 || true
fi

# 10. verify -------------------------------------------------------------------
say "verification"
python3 - <<'PY'
import json, pathlib, subprocess
home = pathlib.Path.home()
def gh_account():
    out = subprocess.run(['gh', 'auth', 'status'], capture_output=True, text=True).stdout
    return out.split('account ')[-1].split()[0] if 'account ' in out else '-'
skills = home / '.agents/skills'
cfg_p = home / '.pi/agent/settings.json'
cfg = json.loads(cfg_p.read_text()) if cfg_p.exists() else {}
print('  gh       ', gh_account())
print('  skills   ', len(list(skills.glob('*'))) if skills.exists() else 0)
print('  pi       ', cfg.get('defaultProvider'), '/', cfg.get('defaultModel'),
      '· packages', len(cfg.get('packages', [])))
print('  secrets  ', 'yes' if (home / 'secrets/org-config.json').exists() else 'no')
d = subprocess.run(['sh', '-c', 'command -v docker >/dev/null && docker info >/dev/null 2>&1'], capture_output=True)
print('  docker   ', 'running' if d.returncode == 0 else 'not usable on this host')
PY
say "done — restart pi to pick up the extensions"
