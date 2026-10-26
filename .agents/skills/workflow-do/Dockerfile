# cage-base — Docker image for parallel workflow-do runs
# pi + Node + agent-browser come from the host's ~/.nvm (mounted at runtime).
# This image provides: Docker (DinD), Chrome, zellij, ImageMagick, gh, lazygit, Wayland/GPU libs.
# DinD: the cage runs --privileged and starts its own dockerd — containers
# inside the cage get their own network namespace, so ports don't clash with
# the host or other parallel cages.
#
# Build:
#   docker buildx build -t cage-base ~/.agents/skills/workflow-do/
#
FROM ubuntu:24.04

# Container account. Override to match your host uid/gid if you mount your home:
#   docker build --build-arg APP_USER=$(id -un) --build-arg APP_UID=$(id -u) ...
ARG APP_USER=agent
ARG APP_UID=1000
ARG APP_HOME=/home/agent

ENV DEBIAN_FRONTEND=noninteractive
ENV HOME=${APP_HOME}

# ── Create user pc (UID 1000, matches host) — replace default ubuntu user ──
RUN userdel -r ubuntu 2>/dev/null || true; useradd -m -u ${APP_UID} -d ${APP_HOME} -s /bin/bash ${APP_USER}
# Pre-create .config/.cache/.local so Node.js update-notifiers etc. can write to them
# (Docker mounts like .config/gh create the parent as root — this fixes ownership)
RUN mkdir -p ${APP_HOME}/.config ${APP_HOME}/.cache ${APP_HOME}/.local && chown ${APP_USER}:${APP_USER} ${APP_HOME}/.config ${APP_HOME}/.cache ${APP_HOME}/.local

# ── System packages ──
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl wget gnupg ca-certificates lsb-release \
    git rsync python3 jq gosu sudo openssh-client socat \
    # Editor (in-container skill edits, committed manually via the ~/.dotfiles bare repo)
    neovim \
    # PostgreSQL client (DB verification in Phase 5)
    postgresql-client \
    # Docker (for DinD — dockerd needs iptables for bridge networking)
    docker.io docker-compose-v2 iptables \
    # Chrome runtime dependencies
    libwayland-client0 libwayland-server0 libxkbcommon0 \
    libdbus-1-3 libgbm1 libasound2t64 libnss3 libnspr4 \
    # Chrome audio: it talks to PipeWire/PulseAudio through libpulse (NOT libpipewire).
    # Without libpulse0 the cage's Chrome has NO audio output device at all — silent
    # playback, silent video tours (found 2026-09-30). pulseaudio-utils gives pactl/paplay
    # so a stage can actually verify the sink (pactl info) instead of guessing.
    libpulse0 pulseaudio-utils \
    libatk1.0-0t64 libatk-bridge2.0-0t64 libcups2t64 libdrm2 \
    libxcomposite1 libxdamage1 libxfixes3 libxrandr2 \
    libpango-1.0-0 libcairo2 libxshmfence1 \
    fonts-liberation fonts-noto-color-emoji fonts-dejavu fonts-ubuntu \
    # GPU / Mesa
    libgl1 libegl1 libgles2 mesa-va-drivers \
    # Chrome keyring access (decrypt cookies from host's gnome-keyring via D-Bus)
    libsecret-1-0 \
    # Screenshot annotation (ImageMagick 6). NOTE: IM's SVG delegate is not reliable here —
    # for SVG input use rsvg-convert (librsvg2-bin, installed below) instead of `convert foo.svg`.
    imagemagick \
    # Full ffmpeg (distro build) — the npm ffmpeg-static build has NO drawtext/libfreetype,
    # so video-tour compose fails with "No such filter: 'drawtext'" (<KEY>, 2026-10-01).
    ffmpeg \
    # C compiler for Triton (legacy qwen3-tts narration compiles CUDA kernels JIT) — without
    # cc/clang triton dies with 'Failed to find C compiler' (<KEY>, 2026-10-01).
    gcc libc6-dev \
    # Offline SVG rasterization (rsvg-convert). Icon/brand regeneration must NEVER depend on
    # a per-run network fetch (`npx --yes sharp-cli`) — <KEY>/182 lost that path offline.
    librsvg2-bin \
    # Email sending (workflow-do Phase 13 — msmtp + Resend SMTP)
    msmtp msmtp-mta \
    # File watching (hot reload)
    inotify-tools \
    # Monitor detection from inside container (uses Wayland socket)
    wlr-randr \
    # niri msg dependencies (IPC with host compositor for window placement)
    libinput10 libseat1 libwacom9 libdisplay-info1 \
    libpipewire-0.3-0t64 libgudev-1.0-0 libmtdev1t64 libevdev2 \
    && rm -rf /var/lib/apt/lists/*

# ── Google Chrome ──
RUN wget -qO- https://dl.google.com/linux/linux_signing_key.pub \
    | gpg --dearmor -o /usr/share/keyrings/google-chrome.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] https://dl.google.com/linux/chrome/deb/ stable main" \
       > /etc/apt/sources.list.d/google-chrome.list \
    && apt-get update && apt-get install -y google-chrome-stable \
    && rm -rf /var/lib/apt/lists/*

# ── gh CLI (via official apt repo) ──
RUN wget -qO /etc/apt/keyrings/githubcli-archive-keyring.gpg https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
       > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# ── gh extensions (needed by pi-ghpr-monitor for Phase 9 PR monitoring) ──
RUN gh extension install elecnix/gh-monitor \
    && gh extension install enthus-appdev/gh-attach \
    && gh extension install v2nic/gh-pr-review

# ── lazygit (from GitHub releases) ──
RUN LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/') \
    && curl -sL "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz" \
       | tar xz -C /usr/local/bin lazygit \
    && chmod +x /usr/local/bin/lazygit

# ── supabase CLI (from GitHub releases) ──
RUN SUPABASE_VERSION=$(curl -s "https://api.github.com/repos/supabase/cli/releases/latest" | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/') \
    && curl -sL "https://github.com/supabase/cli/releases/download/v${SUPABASE_VERSION}/supabase_${SUPABASE_VERSION}_linux_amd64.tar.gz" \
       | tar xz -C /usr/local/bin supabase \
    && chmod +x /usr/local/bin/supabase

# ── zellij (CLI only — used to control host's zellij via TCP proxy) ──
# On macOS, the host's zellij Unix socket can't be mounted into the container
# (VirtioFS limitation). Instead, the cage function starts a socat TCP proxy on
# the host. The wrapper script below forwards `zellij action` commands to that
# TCP proxy; other zellij commands fall through to the real binary.
# Pinned to the host's version (scripts/install.sh): the client talks to the
# host's zellij server over its socket, and `zellij pipe` (zj-radar) needs a
# matching client/server pair.
ARG ZELLIJ_VERSION=0.44.3
RUN base=https://github.com/zellij-org/zellij/releases/download/v${ZELLIJ_VERSION}/zellij-x86_64-unknown-linux-musl \
    && wget -qO /tmp/zellij.tar.gz "$base.tar.gz" \
    && sha=$(wget -qO- "$base.sha256sum" | awk '{print $1}') \
    && tar -xzf /tmp/zellij.tar.gz -C /tmp zellij \
    && echo "$sha  /tmp/zellij" | sha256sum -c --quiet \
    && install -m755 /tmp/zellij /usr/local/bin/zellij.real \
    && rm -f /tmp/zellij.tar.gz /tmp/zellij
COPY zellij-wrapper.sh /usr/local/bin/zellij
RUN chmod +x /usr/local/bin/zellij

# ── zj-radar (agent-status sidebar producer) ──
# The pi bridge (~/.pi/agent/extensions/zj-radar.js) spawns `zj-radar notify`,
# which `zellij pipe`s status to the host's sidebar. Keep in step with the
# host's `zj-radar --version` (its wasm) — rebuild the image after `zj-radar update`.
ARG ZJ_RADAR_VERSION=v0.9.0
RUN curl --proto '=https' --tlsv1.2 -LsSf \
       "https://github.com/marktoda/zj-radar/releases/download/${ZJ_RADAR_VERSION}/install.sh" \
       | ZJ_RADAR_VERSION="$ZJ_RADAR_VERSION" ZJ_RADAR_BIN_DIR=/usr/local/bin sh \
    && /usr/local/bin/zj-radar --version

# ── Suppress lazygit first-run popup ──
# The welcome popup is gated by the state file's startuppopupversion field, not
# just the config. Without a state file, startuppopupversion defaults to 0 and
# lazygit shows its intro popup every time. Create both config and state so the
# popup is suppressed from the very first launch inside the cage container.
RUN mkdir -p ${APP_HOME}/.config/lazygit ${APP_HOME}/.local/state/lazygit \
    && printf 'gui:\n  showRandomTip: false\n  showCommandLog: false\n  showFileTree: false\n' > ${APP_HOME}/.config/lazygit/config.yml \
    && printf 'startuppopupversion: 999\nlastupdatecheck: 0\n' > ${APP_HOME}/.local/state/lazygit/state.yml \
    && chown ${APP_USER}:${APP_USER} ${APP_HOME}/.config/lazygit/config.yml ${APP_HOME}/.local/state/lazygit/state.yml

# ── Add pc to docker group ──
RUN usermod -aG docker pc

# ── ImageMagick 6 uses 'convert', not 'magick' (IM7). Symlink for compatibility. ──
RUN ln -s /usr/bin/convert /usr/local/bin/magick

# ── nvm + Node.js (installed in-image so arch always matches the container) ──
ENV NVM_DIR=${APP_HOME}/.nvm
RUN mkdir -p $NVM_DIR && chown ${APP_USER}:${APP_USER} $NVM_DIR
USER ${APP_USER}
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash \
    && . "$NVM_DIR/nvm.sh" \
    && nvm install 24 \
    && nvm alias default 24 \
    && npm install -g pnpm @earendil-works/pi-coding-agent @juicesharp/rpiv-ask-user-question

# ── Preinstall @esbuild/linux-x64 (native module) into a location pi-intercom will find ──
# pi-intercom's broker uses tsx→esbuild at runtime. The host's ~/.pi is bind-mounted
# into the cage, but its esbuild native binary is macOS/arm64 (host arch), unusable
# under linux/amd64 in the cage. Install a linux-x64 copy inside the image at a path
# node's module resolver will discover regardless of the host mount overlay.
RUN . "$NVM_DIR/nvm.sh" \
    && mkdir -p ${APP_HOME}/esbuild-linux \
    && cd ${APP_HOME}/esbuild-linux \
    && npm init -y >/dev/null \
    && npm install --no-save --no-audit --no-fund @esbuild/linux-x64@0.28.2
USER root

# ── .bashrc — source nvm so pi/node/pnpm are on PATH ──
# Pi itself is the host's managed install, mounted at ~/.pi/agent/bin. The nvm
# mount (:ro) shadows the in-image npm-installed pi, so the managed bin dir is
# prepended AFTER the nvm lines so it wins the PATH lookup.
RUN echo 'export NVM_DIR="$HOME/.nvm"' >> ${APP_HOME}/.bashrc \
    && echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >> ${APP_HOME}/.bashrc \
    && echo '[ -d "$HOME/.pi/agent/bin" ] && export PATH="$HOME/.pi/agent/bin:$PATH"' >> ${APP_HOME}/.bashrc \
    && chown ${APP_USER}:${APP_USER} ${APP_HOME}/.bashrc

# ── Chrome profile dir (persistent volume mount at runtime) ──
# The cage function mounts $HOME/.cage-chrome-profile here so login sessions
# persist across container runs. This mkdir is a fallback for when no volume
# is mounted; the entrypoint.sh handles the fresh-vs-existing logic.
RUN mkdir -p /chrome-profile && chown ${APP_USER}:${APP_USER} /chrome-profile

# ── Suppress Chrome "unsupported command-line flag" banner ──
RUN mkdir -p /etc/opt/chrome/policies/managed \
    && echo '{"CommandLineFlagSecurityWarningsEnabled": false}' \
       > /etc/opt/chrome/policies/managed/policies.json

# ── agent-browser (installed to /opt/agent-browser — NOT ~/.nvm) ──
# The host's ~/.nvm is mounted read-only at runtime (Linux) and shadows the
# in-image nvm, so agent-browser must live OUTSIDE ~/.nvm to be present in the
# container. /opt/agent-browser is never mounted over, so the binary is always
# there on both Linux and macOS.
#
# The previous /usr/local/bin/agent-browser was a bash wrapper that fell back
# to `command -v agent-browser` when the nvm glob was empty — but that resolves
# to the wrapper itself → execs itself forever → every call hung (the
# "agent-browser --version times out" symptom). A direct symlink replaces it.
RUN mkdir -p /opt/agent-browser && chown ${APP_USER}:${APP_USER} /opt/agent-browser
USER ${APP_USER}
RUN . "$NVM_DIR/nvm.sh" \
    && npm install -g --prefix /opt/agent-browser agent-browser \
    && /opt/agent-browser/bin/agent-browser --version
USER root
RUN ln -sf /opt/agent-browser/bin/agent-browser /usr/local/bin/agent-browser

# ── Video-tour deps (V4/V5) ──
# The tour's avatar scripts need PIL/numpy; avatar-visemes.sh installs Rhubarb Lip
# Sync on demand, but it installs into ~/.local/share (container-local — lost on
# every run) and the image had no unzip, so that path silently failed. Bake both in
# (Rhubarb 1.14.0 is a static build — no Qt/X libs needed, verified 2026-10-14).
RUN apt-get update \
    && apt-get install -y --no-install-recommends python3-pil python3-numpy unzip \
    && rm -rf /var/lib/apt/lists/* \
    && curl -sL -o /tmp/rhubarb.zip \
       https://github.com/DanielSWolf/rhubarb-lip-sync/releases/download/v1.14.0/Rhubarb-Lip-Sync-1.14.0-Linux.zip \
    && mkdir -p /opt/rhubarb \
    && unzip -q -o /tmp/rhubarb.zip -d /opt/rhubarb \
    && rm -f /tmp/rhubarb.zip \
    && ln -sf "$(find /opt/rhubarb -type f -name rhubarb | head -1)" /usr/local/bin/rhubarb \
    && chmod +x /usr/local/bin/rhubarb \
    && rhubarb --version \
    && python3 -c "import PIL, numpy; print('PIL', PIL.__version__, 'numpy', numpy.__version__)"

# ── cage-pane helper: opens a new zellij pane that docker-execs into this container ──
# Usage: cage-pane [command...]
# When zellij runs on the host and the cage is a tab, new panes must docker-exec back in.
RUN printf '#!/bin/bash\n# Open a new zellij pane that execs into this cage container\nif [ -z "$WORKFLOW_CONTAINER_ID" ]; then echo "ERROR: WORKFLOW_CONTAINER_ID not set"; exit 1; fi\nlocal_cmd="${@:-bash}"\nzellij action new-pane -d right -- docker exec -it -u pc -w "$(pwd)" -e WORKFLOW_CWD="$WORKFLOW_CWD" -e WORKFLOW_CHROME_PORT="$WORKFLOW_CHROME_PORT" -e WORKFLOW_CONTAINER_ID="$WORKFLOW_CONTAINER_ID" -e ZELLIJ=1 -e ZELLIJ_SESSION_NAME="$ZELLIJ_SESSION_NAME" -e ZELLIJ_PANE_ID "$WORKFLOW_CONTAINER_ID" bash -ic "$local_cmd"\n' > /usr/local/bin/cage-pane \
    && chmod +x /usr/local/bin/cage-pane

# ── Email sending (workflow-do Phase 13) ──
# msmtp is installed via apt above. send-summary-email.sh is now a thin shim that
# execs send-summary-email.ts (the real email script, run with npx tsx); it is copied
# in so the container path below keeps working.
# The ~/.msmtprc is mounted from host at runtime (or created by entrypoint).
COPY send-summary-email.sh /usr/local/bin/send-summary-email.sh
RUN chmod +x /usr/local/bin/send-summary-email.sh

# ── Entrypoint ──
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["sleep", "infinity"]