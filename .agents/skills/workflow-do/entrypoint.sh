#!/bin/bash
# entrypoint.sh — Container entrypoint for cage-base image
#
# Runs Docker-in-Docker (DinD): a Docker daemon is started inside the container
# so that docker compose / docker run commands create containers in the cage's
# own network namespace — ports don't clash with the host or other cages.
#
# 1. Start Docker daemon (DinD)
# 2. Chrome profile (persistent volume mount — login sessions preserved)
# 3. Set NIRI_SOCKET for compositor IPC
# 4. Suppress lazygit first-run popup
# 5. Run the main command as user pc (UID 1000, matches host for file perms)
#
set -e

# ── 1. Start Docker daemon (DinD) ──
# The cage container runs with --privileged so dockerd can create bridges,
# cgroups, and iptables rules. This gives the cage its own isolated Docker
# environment — containers started here don't bind to host ports.
# Try overlay2 first (fast); fall back to vfs if the kernel doesn't support
# overlay inside a container (some setups need this).
echo "Starting Docker daemon (DinD)..."
dockerd --host=unix:///var/run/docker.sock \
  --storage-driver=overlay2 \
  > /tmp/dockerd.log 2>&1 &

# Wait briefly for overlay2 to initialize; if it fails, retry with vfs
sleep 2
if ! docker info >/dev/null 2>&1; then
  if grep -q "overlay" /tmp/dockerd.log 2>/dev/null; then
    echo "overlay2 not supported, falling back to vfs storage driver..."
    pkill dockerd 2>/dev/null || true; sleep 1
    dockerd --host=unix:///var/run/docker.sock \
      --storage-driver=vfs \
      > /tmp/dockerd.log 2>&1 &
  fi
fi

# Wait for the Docker daemon to be ready
for i in $(seq 1 30); do
  if docker info >/dev/null 2>&1; then
    echo "Docker ready (DinD — isolated from host)"
    break
  fi
  [ "$i" = "30" ] && {
    echo "WARNING: Docker daemon failed to start. Check /tmp/dockerd.log"
    echo "--- Last 10 lines of dockerd log: ---"
    tail -10 /tmp/dockerd.log 2>/dev/null
  }
  sleep 1
done

# ── 2. Chrome profile (persistent volume mount) ──
# The cage function mounts $HOME/.cage-chrome-profile at /chrome-profile so
# that login sessions (GitHub, Google, etc.) persist across container runs.
# Only create the directory structure if it doesn't already exist — NEVER
# wipe an existing profile, or the user will have to log in again.
mkdir -p $HOME/.agent-browser
if [ ! -d /chrome-profile/Default ]; then
  mkdir -p /chrome-profile/Default
  echo "Chrome profile ready (fresh — user will log in manually on first run)"
else
  echo "Chrome profile restored (persistent — login sessions preserved from previous run)"
fi
chown -R "${CAGE_UID:-1000}:${CAGE_GID:-1000}" /chrome-profile $HOME/.agent-browser

# ── 3. Set NIRI_SOCKET if available ──
# The host's /run/user/$uid is mounted, which contains the niri socket.
# Find it and export for use by niri msg inside the container.
if [ -z "$NIRI_SOCKET" ]; then
  NIRI_SOCK=$(find /run/user -maxdepth 1 -name 'niri.wayland-*' 2>/dev/null | head -1)
  if [ -n "$NIRI_SOCK" ]; then
    export NIRI_SOCKET="$NIRI_SOCK"
    echo "Niri socket: $NIRI_SOCKET"
  fi
fi

# ── 4. Suppress lazygit first-run welcome popup ──
# The "thanks for using lazygit" intro popup is gated by the state file's
# startuppopupversion field. Without a state file it defaults to 0 and the
# popup shows every time. Create the state file on every container start (not
# just at build time) so the popup is suppressed even on old images.
mkdir -p $HOME/.local/state/lazygit $HOME/.config/lazygit
printf 'startuppopupversion: 999\nlastupdatecheck: 0\n' > $HOME/.local/state/lazygit/state.yml
# Also write to the config-dir fallback path (some lazygit versions use this)
printf 'startuppopupversion: 999\nlastupdatecheck: 0\n' > $HOME/.config/lazygit/state.yml
chown -R $(id -u):$(id -g) $HOME/.local/state/lazygit $HOME/.config/lazygit

# ── 4.5 msmtp config (workflow-do Phase 13 email summaries) ──
# Symlink ~/.msmtprc from the host's dotfiles if it exists (mounted at runtime).
# The password is read via passwordeval from $ORG_CONFIG_DIR/env/resend.env which is
# also mounted. If ~/.msmtprc doesn't exist, Phase 13 will skip gracefully.
if [ -f $HOME/.msmtprc ]; then
  chmod 600 $HOME/.msmtprc
  chown $(id -u):$(id -g) $HOME/.msmtprc
fi

# ── 4.6 pi-intercom native module (macOS host → linux cage) ──
# The host's ~/.pi is bind-mounted, but its esbuild native binary is the host's
# platform (macOS/arm64 on M-series Macs). pi-intercom's broker uses tsx→esbuild
# and dies at load time if the native module is wrong arch. Overlay the linux-x64
# native binary that was preinstalled in $HOME/esbuild-linux into the mounted
# pi-intercom tree so tsx/esbuild find a valid linux-x64 module.
if [ -d $HOME/esbuild-linux/node_modules/@esbuild/linux-x64 ] \
   && [ -d $HOME/.pi/agent/npm/node_modules ]; then
  _target=$HOME/.pi/agent/npm/node_modules/@esbuild/linux-x64
  if [ ! -d "$_target" ] || [ ! -f "$_target/bin/esbuild" ]; then
    mkdir -p $HOME/.pi/agent/npm/node_modules/@esbuild 2>/dev/null || true
    cp -R $HOME/esbuild-linux/node_modules/@esbuild/linux-x64 \
          $HOME/.pi/agent/npm/node_modules/@esbuild/ 2>/dev/null \
      && echo "pi-intercom: shadowed @esbuild/linux-x64 into mounted ~/.pi" \
      || echo "pi-intercom: could not shadow @esbuild/linux-x64 (mount RO?)"
  fi
fi

# ── 4.7 pi-intercom broker bridge (cage → host) ──
# VirtioFS does not proxy Unix socket ops between macOS host and Linux cage:
# each side sees its own file, so cage's pi would spawn its own broker and be
# blind to host peers. Fix: present the cage-local expected socket path as a
# socat bridge to host TCP:9458, which the host proxies to the host broker's
# real Unix socket. Must run BEFORE any pi process so isBrokerRunning() sees
# the bridged socket answering and skips spawning a cage-local broker.
#
# Host side must be up: socat TCP-LISTEN:9458 UNIX-CONNECT:$HOME/.pi/agent/intercom/broker.sock
# See cage-boot helper on the host.
if [ "${CAGE_INTERCOM_BRIDGE:-1}" = "1" ] && command -v socat >/dev/null 2>&1; then
  _sock=$HOME/.pi/agent/intercom/broker.sock
  _pid=$HOME/.pi/agent/intercom/broker.pid
  _lock=$HOME/.pi/agent/intercom/broker.spawn.lock
  mkdir -p $HOME/.pi/agent/intercom
  # The entrypoint runs as root; chowning to $(id -u) would make this root-owned
  # and the pi sessions (user pc) then cannot bind the bridge socket
  # (Permission denied on bind — broke every cage until 2026-10-26).
  # Resolve the user the bridge must run as. cage() sets WORKFLOW_CAGE_USER=root on this
  # image (the default APP_USER is `agent`, not `pc`), and `gosu pc` failed hard on every
  # cage until 2026-10-26: the bridge never bound, pi then spawned a CAGE-LOCAL broker and
  # the run went intercom-blind (no handoffs, no gate asks, no finish notice).
  _bridge_user="${WORKFLOW_CAGE_USER:-${APP_USER:-pc}}"
  id "$_bridge_user" >/dev/null 2>&1 || _bridge_user=root
  chown -R "$(id -u "$_bridge_user"):$(id -g "$_bridge_user")" $HOME/.pi/agent/intercom 2>/dev/null || true
  chmod 700 $HOME/.pi/agent/intercom 2>/dev/null || true
  # Remove any stale files pi's spawnBrokerIfNeeded may key off
  rm -f "$_sock" "$_pid" "$_lock"
  # Start the bridge as the cage user so the socket ends up owned by them
  gosu "$_bridge_user" nohup socat \
    UNIX-LISTEN:"$_sock",fork,mode=666 \
    TCP:host.docker.internal:9458 \
    >/tmp/socat-intercom-cage.log 2>&1 &
  # Wait briefly so the socket file exists before pi starts
  for _i in 1 2 3 4 5 6 7 8 9 10; do
    [ -S "$_sock" ] && break
    sleep 0.2
  done
  if [ -S "$_sock" ]; then
    # BOUND ≠ WORKING. socat creates the Unix socket even when its TCP side is dead, and
    # the client then fails per-connection while `isBrokerRunning()` still sees a live
    # socket — so pi spawns its OWN broker and the cage goes blind to host sessions
    # (no handoffs, no asks, no finish notifications; the chief of staff has to sweep by hand).
    # Probe the TCP side once and say so loudly. Linux only resolves this name when the
    # container was created with --add-host=host.docker.internal:host-gateway (cage() does).
    if timeout 2 bash -c 'exec 3<>/dev/tcp/host.docker.internal/9458' 2>/dev/null; then
      echo "intercom bridge: cage $_sock → host.docker.internal:9458 (verified)"
    else
      echo "intercom bridge: WARN $_sock is bound but host.docker.internal:9458 is UNREACHABLE —"
      echo "intercom bridge: WARN this cage is isolated from host intercom sessions (handoffs/asks/finishes will not arrive)."
      echo "intercom bridge: WARN Linux fix: cage() must pass --add-host=host.docker.internal:host-gateway; the host must run the intercom-bridge socat on 9458."
    fi
  else
    echo "intercom bridge: WARN failed to bind $_sock (see /tmp/socat-intercom-cage.log)"
  fi
fi

# ── 5. Run main command as user pc ──
exec gosu pc "$@"