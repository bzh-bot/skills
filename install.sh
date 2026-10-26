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
#   TRIAGE_ORG=<key> the registry key for that org, if it differs from ORG
#   EXTRA_ENV="a.env b.env"  cross-org env files to copy too (none by default)
#   TRIAGE_DIR=<path>         source registry (defaults to ~/secrets/triage or ~/secrets/<org>/triage)
#
# Knobs: DEFAULT_PROVIDER, DEFAULT_MODEL, PI_PACKAGES, PI_AUTH_PROVIDERS,
#        PI_MODEL_PROVIDERS, GH_ACCOUNT, GH_EMAIL, MACHINE_NAME, SKILLS_REPO,
#        ZELLIJ_VERSION, NVIM_VERSION, NVM_VERSION.
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
    # Only this org's slice goes to the target. Never the whole org-config (it
    # holds every org), never the whole triage registry (an account file per org),
    # and never the cross-org helpers (cage-config / chrome-profiles / atlassian)
    # unless the caller asks for them via EXTRA_ENV.
    ORG="$ORG" TRIAGE_ORG="${TRIAGE_ORG:-$ORG}" LOCAL_SECRETS="$LOCAL_SECRETS" STAGE="$stage" \
    EXTRA_ENV="${EXTRA_ENV:-}" TRIAGE_SRC="${TRIAGE_SRC:-${TRIAGE_DIR:-}}" python3 - <<'PY'
import json, os, pathlib, re, shutil, sys

org = os.environ["ORG"]; torg = os.environ["TRIAGE_ORG"]
secrets = pathlib.Path(os.environ["LOCAL_SECRETS"]); stage = pathlib.Path(os.environ["STAGE"])
dest = stage / "secrets"; (dest / "env").mkdir(parents=True, exist_ok=True); (dest / org).mkdir(parents=True, exist_ok=True)

def load(p):
    t = p.read_text()
    t = re.sub(r'^\s*/\*.*?\*/\s*', '', t, flags=re.S)   # the registry allows a leading /* */
    return json.loads(t)

note = []
cfg = secrets / "org-config.json"
if cfg.exists():
    d = load(cfg)
    orgs = d.get("orgs") or []
    keep = [o for o in orgs if org in (o.get("org"), o.get("githubOrg"))]
    if keep:
        # `bot` is a single global block that usually names another org's machine
        # account; the org's own `poll.github.account` is the authoritative one.
        meta = {k: v for k, v in d.items() if k not in ("orgs", "bot")}
        meta["orgs"] = keep
        (dest / "org-config.json").write_text(json.dumps(meta, indent=2) + "\n")
        note.append(f"org-config.json (1 of {len(orgs)} orgs, global bot block dropped)")
    else:
        note.append(f"org-config.json (no entry for '{org}' — skipped)")

for name, src in (("reviewers.json", secrets / org / "reviewers.json"),
                  (f"gitconfig-{org}", secrets / org / f"gitconfig-{org}")):
    if src.exists():
        shutil.copy2(src, dest / org / name); note.append(f"{org}/{name}")

extra = {e for e in os.environ.get("EXTRA_ENV", "").split() if e}
envdir = secrets / "env"
if envdir.is_dir():
    for f in sorted(envdir.glob("*.env")):
        if org.lower() in f.name.lower() or f.name in extra:
            shutil.copy2(f, dest / "env" / f.name); note.append(f"env/{f.name}")

cands = [pathlib.Path(os.environ["TRIAGE_SRC"])] if os.environ.get("TRIAGE_SRC") else []
cands += [secrets / "triage", secrets / org / "triage"]
src_triage = next((c for c in cands if c.is_dir()), None)
if src_triage is None:
    note.append("triage: NOT FOUND (set TRIAGE_DIR to its path)")
else:
    out = dest / "triage"; (out / "accounts").mkdir(parents=True, exist_ok=True)
    # platforms.json — keep only the platform definitions this org's accounts use,
    # so no other org's reader-skill names ride along
    pl_path = src_triage / "platforms.json"
    if pl_path.exists():
        pl = load(pl_path)
        used = set()
        acc_src = src_triage / "accounts" / f"{torg}.json"
        if acc_src.exists():
            try:
                used = {a.get("platform") for a in load(acc_src)}
            except Exception:
                used = set()
        if isinstance(pl, dict) and used:
            keep = {k: v for k, v in pl.items() if k in used}
            (out / "platforms.json").write_text(json.dumps(keep, indent=2) + "\n")
            note.append(f"triage/platforms.json ({len(keep)} of {len(pl)})")
        elif isinstance(pl, dict):
            note.append("triage/platforms.json SKIPPED (no accounts file to scope it)")
        else:
            shutil.copy2(pl_path, out / "platforms.json")
    oj = load(src_triage / "orgs.json") if (src_triage / "orgs.json").exists() else None
    if isinstance(oj, dict):
        mine = {k: v for k, v in oj.items() if k == torg}
        if mine:
            (out / "orgs.json").write_text(json.dumps(mine, indent=2) + "\n")
            note.append(f"triage/orgs.json ({torg})")
        else:
            note.append(f"triage/orgs.json SKIPPED (no '{torg}' key)")
    acc = src_triage / "accounts" / f"{torg}.json"
    if acc.exists():
        shutil.copy2(acc, out / "accounts" / acc.name); note.append(f"triage/accounts/{acc.name}")
    bank = src_triage / "banks" / f"{torg}.json"
    if bank.exists():
        (out / "banks").mkdir(exist_ok=True); shutil.copy2(bank, out / "banks" / bank.name); note.append(f"triage/banks/{bank.name}")
    st = src_triage / "state.json"
    if st.exists():
        s = load(st)
        filt = {k: {kk: vv for kk, vv in (s.get(k) or {}).items() if kk.split("/")[0] == torg} for k in ("accounts", "banks")}
        if any(filt.values()):
            (out / "state.json").write_text(json.dumps(filt, indent=2) + "\n")
            note.append(f"triage/state.json ({sum(len(v) for v in filt.values())} entries)")

print("  staged: " + (", ".join(note) if note else "nothing"))
PY
  fi
  [ -f "$HOME/.config/zellij/config.kdl" ] && cp "$HOME/.config/zellij/config.kdl" "$stage/zellij.kdl"
  [ -d "$HOME/.config/nvim" ] && cp -R "$HOME/.config/nvim" "$stage/nvim"

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
NVIM_VERSION="${NVIM_VERSION:-latest}"
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
for b in jq git curl rsync wget ffmpeg; do command -v "$b" >/dev/null 2>&1 || missing="$missing $b"; done
# Fonts are for the video tours' chapter cards and annotation boxes; ffmpeg encodes
# every clip, the narration bed and the music overlay.
FONT_PKGS_NEEDED=""
if command -v apt-get >/dev/null 2>&1 && ! fc-list 2>/dev/null | grep -qi 'dejavu sans'; then
  FONT_PKGS_NEEDED="fonts-dejavu-core fonts-liberation"
fi
if [ -n "$missing" ] || [ -n "$FONT_PKGS_NEEDED" ]; then
  if command -v apt-get >/dev/null 2>&1; then
    sudo_if_needed apt-get update -qq 2>/dev/null || apt-get update -qq
    sudo_if_needed env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $missing $FONT_PKGS_NEEDED >/dev/null
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y -q $missing google-noto-sans-fonts >/dev/null
  else
    warn "no package manager for:$missing"
  fi
fi
command -v jq >/dev/null && echo "  jq    $(jq --version)"
command -v ffmpeg >/dev/null && echo "  ffmpeg $(ffmpeg -version | head -1 | cut -d' ' -f1-3)" || warn "ffmpeg missing — video tours/release videos cannot assemble"

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

# 5b. browser, speech, and video tooling --------------------------------------
# The video skills (workflow-do-tour, workflow-release-video) and every flow that
# drives a real site need these; without them a cage half-runs a tour and then stops.
# All three checks are cheap and idempotent, so a re-run only fills the gaps.
VTOUR="$SKILLS_DIR/.agents/skills/workflow-video-tour"
[ -d "$VTOUR" ] || VTOUR="$DEST/workflow-video-tour"

say "browser (agent-browser + headless Chrome)"
if command -v agent-browser >/dev/null 2>&1; then
  echo "  $(agent-browser --version 2>/dev/null | head -1)"
else
  # npm >= 11 blocks lifecycle scripts unless allowed by name, and agent-browser's
  # postinstall is what stages the CLI's own browser download.
  npm i -g --allow-scripts=agent-browser agent-browser >/dev/null 2>&1 \
    || npm i -g agent-browser >/dev/null 2>&1 \
    || warn "agent-browser install failed"
  command -v agent-browser >/dev/null && echo "  $(agent-browser --version 2>/dev/null | head -1)"
fi
CHROME_BIN="$(ls -d "$HOME"/.agent-browser/browsers/chrome-*/chrome-linux64/chrome 2>/dev/null | tail -1)"
if [ -n "$CHROME_BIN" ]; then
  echo "  chrome  $(basename "$(dirname "$(dirname "$CHROME_BIN")")")"
else
  say "downloading Chrome for agent-browser"
  agent-browser install >/dev/null 2>&1 || agent-browser install --with-deps >/dev/null 2>&1 \
    || warn "chrome download failed"
  CHROME_BIN="$(ls -d "$HOME"/.agent-browser/browsers/chrome-*/chrome-linux64/chrome 2>/dev/null | tail -1)"
  [ -n "$CHROME_BIN" ] && echo "  chrome  $(basename "$(dirname "$(dirname "$CHROME_BIN")")")" \
    || warn "no Chrome under ~/.agent-browser/browsers — mermaid renders and live capture will fail"
fi
# mmdc's puppeteer renders the diagrams with the same Chrome the capture uses.
if [ -n "$CHROME_BIN" ]; then
  grep -q '^export MMDC_CHROME=' "$HOME/.bashrc" 2>/dev/null \
    || echo "export MMDC_CHROME=\"$CHROME_BIN\"" >> "$HOME/.bashrc"
fi

say "speech (Phonon, voice Easton)"
PHONON_PORT="${PHONON_PORT:-11499}"
PHONON_URL="http://127.0.0.1:$PHONON_PORT"
if curl -sf -m 3 "$PHONON_URL/api/tags" >/dev/null 2>&1; then
  echo "  phonon up on :$PHONON_PORT"
elif [ -x /opt/ollama-phonon/bin/ollama ] && [ -x "$VTOUR/scripts/tts-phonon.py" ]; then
  say "starting the phonon service on :$PHONON_PORT"
  if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    sudo_if_needed tee /etc/systemd/system/ollama-phonon.service >/dev/null <<UNIT
[Unit]
Description=Ollama Phonon TTS for narration
After=network-online.target

[Service]
ExecStart=/opt/ollama-phonon/bin/ollama serve
Environment=OLLAMA_HOST=0.0.0.0:$PHONON_PORT
Environment=OLLAMA_MODELS=$HOME/.local/share/ollama-phonon/models
Environment=LD_LIBRARY_PATH=/opt/ollama-phonon/lib
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT
    sudo_if_needed systemctl daemon-reload
    sudo_if_needed systemctl enable --now ollama-phonon.service
  else
    OLLAMA_HOST="0.0.0.0:$PHONON_PORT" \
      OLLAMA_MODELS="$HOME/.local/share/ollama-phonon/models" \
      LD_LIBRARY_PATH=/opt/ollama-phonon/lib \
      nohup /opt/ollama-phonon/bin/ollama serve >/tmp/ollama-phonon.log 2>&1 &
  fi
  for _ in $(seq 1 30); do curl -sf -m 2 "$PHONON_URL/api/tags" >/dev/null 2>&1 && break; sleep 1; done
  echo "  phonon up on :$PHONON_PORT"
elif [ -x "$VTOUR/scripts/install-phonon.sh" ]; then
  say "installing Phonon (Ollama + MLX overlay + model)"
  bash "$VTOUR/scripts/install-phonon.sh" --host-shared 2>&1 | tail -3 \
    || warn "phonon install failed — narration will not render"
else
  warn "no phonon runtime and no install-phonon.sh — narration will not render"
fi
if [ -x "$VTOUR/scripts/tts-phonon.py" ]; then
  grep -q '^export PHONON_HOST=' "$HOME/.bashrc" 2>/dev/null \
    || echo "export PHONON_HOST=\"$PHONON_URL\"" >> "$HOME/.bashrc"
  PHONON_HOST="$PHONON_URL" PHONON_VOICE=Easton timeout 120 python3 "$VTOUR/scripts/tts-phonon.py" --check >/dev/null 2>&1 \
    && echo "  tts     ok (Easton)" || warn "tts check failed — run: PHONON_HOST=$PHONON_URL python3 $VTOUR/scripts/tts-phonon.py --check"
fi

say "video tooling (mermaid-cli)"
if command -v mmdc >/dev/null 2>&1 || [ -x "$HOME/.local/share/mermaid-cli/node_modules/.bin/mmdc" ]; then
  echo "  mmdc present"
elif [ -x "$VTOUR/scripts/setup-mermaid.sh" ]; then
  MMDC_CHROME="${CHROME_BIN:-${MMDC_CHROME:-}}" bash "$VTOUR/scripts/setup-mermaid.sh" 2>&1 | tail -3 \
    || warn "mermaid-cli install failed — diagram beats cannot render"
else
  warn "no setup-mermaid.sh — diagram beats cannot render"
fi

# 6. neovim -------------------------------------------------------------------
say "neovim"
if command -v nvim >/dev/null 2>&1; then
  echo "  $(nvim --version | head -1)"
else
  NVIM_REL="${NVIM_VERSION:-latest}"
  if [ "$NVIM_REL" = latest ]; then
    NVIM_URL="https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz"
  else
    NVIM_URL="https://github.com/neovim/neovim/releases/download/v${NVIM_REL#v}/nvim-linux-x86_64.tar.gz"
  fi
  tmp="$(mktemp -d)"
  if curl -fsSL "$NVIM_URL" -o "$tmp/nvim.tar.gz"; then
    sudo_if_needed rm -rf /opt/nvim
    sudo_if_needed mkdir -p /opt
    sudo_if_needed tar -xzf "$tmp/nvim.tar.gz" -C /opt
    sudo_if_needed ln -sf /opt/nvim-linux-x86_64/bin/nvim /usr/local/bin/nvim
    echo "  $(nvim --version | head -1)"
  else
    warn "could not download neovim ($NVIM_URL)"
  fi
  rm -rf "$tmp"
fi

NVIM_CONFIG="$HOME/.config/nvim"
if [ -d /root/.pisetup/nvim ]; then
  mkdir -p "$NVIM_CONFIG"
  cp -R /root/.pisetup/nvim/. "$NVIM_CONFIG/"
  echo "  config <- staged copy ($(find "$NVIM_CONFIG" -type f | wc -l) files)"
elif [ -d "$SKILLS_DIR/.config/nvim" ]; then
  mkdir -p "$NVIM_CONFIG"
  cp -R "$SKILLS_DIR/.config/nvim/." "$NVIM_CONFIG/"
  echo "  config <- repo copy ($(find "$NVIM_CONFIG" -type f | wc -l) files)"
elif [ -f "$NVIM_CONFIG/init.lua" ] || [ -f "$NVIM_CONFIG/init.vim" ]; then
  echo "  config already in place"
else
  warn "no nvim config at $NVIM_CONFIG"
fi


# 7. pi settings ---------------------------------------------------------------
say "pi settings (default $DEFAULT_PROVIDER/$DEFAULT_MODEL)"
DEF_PROVIDER="$DEFAULT_PROVIDER" DEF_MODEL="$DEFAULT_MODEL" PI_PKGS="$PI_PACKAGES" \
TEMPLATE="$SKILLS_DIR/.pi/agent/settings.template.json" python3 - <<'PY'
import json, os, pathlib
p = pathlib.Path.home() / '.pi/agent/settings.json'
p.parent.mkdir(parents=True, exist_ok=True)
s = json.loads(p.read_text()) if p.exists() else {}

# Machine-neutral preferences shipped with the repo (theme, UI, package list).
# Only keys the target does not already define are taken, so a re-run never
# clobbers this box's provider/model choices.
tpl = pathlib.Path(os.environ.get('TEMPLATE', ''))
if tpl.is_file():
    base = json.loads(tpl.read_text())
    added = []
    for k, v in base.items():
        if k == 'packages':
            pk = s.setdefault('packages', [])
            for item in v:
                if item not in pk: pk.append(item); added.append(item)
        elif k not in s:
            s[k] = v; added.append(k)
    print('  template:', ', '.join(added) if added else 'nothing new')

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

# 8. pi-intercom ---------------------------------------------------------------
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

# 9. git identity --------------------------------------------------------------
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

# 10. gh login ------------------------------------------------------------------
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

# 11. verify -------------------------------------------------------------------
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
