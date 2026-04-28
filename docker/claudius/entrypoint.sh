#!/bin/bash
set -e

# ── User setup ────────────────────────────────────────────────────────────────
# HOST_UID/HOST_GID/HOST_USER come from the launcher so that files in the
# mounted project directory end up owned by the right user.

# Remove any existing user claiming the same UID (avoids mount conflicts).
conflicting="$(getent passwd "$HOST_UID" 2>/dev/null | cut -d: -f1 || true)"
if [ -n "$conflicting" ] && [ "$conflicting" != "$HOST_USER" ]; then
  userdel "$conflicting" 2>/dev/null || true
fi

if ! getent group "$HOST_GID" &>/dev/null; then
  groupadd -g "$HOST_GID" "$HOST_USER"
fi

if ! id "$HOST_USER" &>/dev/null; then
  useradd -u "$HOST_UID" -g "$HOST_GID" -M -s /bin/bash "$HOST_USER"
fi

HOME_DIR="/home/$HOST_USER"
mkdir -p "$HOME_DIR/.local/bin" "$HOME_DIR/.local/share"
cp    /root/.bashrc "$HOME_DIR/.bashrc"
cp -r /root/.config "$HOME_DIR/.config"
ln -sf /usr/local/bin/claude   "$HOME_DIR/.local/bin/claude"
ln -sf /usr/local/share/claude "$HOME_DIR/.local/share/claude"
chown    "$HOST_UID:$HOST_GID" "$HOME_DIR"
chown -R "$HOST_UID:$HOST_GID" "$HOME_DIR/.config" "$HOME_DIR/.local"
chown    "$HOST_UID:$HOST_GID" "$HOME_DIR/.bashrc" "$HOME_DIR/.claude.json" 2>/dev/null || true

if [ -n "${GPG_SOCK:-}" ] && [ -S "$GPG_SOCK" ]; then
  mkdir -p "$HOME_DIR/.gnupg"
  chmod 700 "$HOME_DIR/.gnupg"
  chown "$HOST_UID:$HOST_GID" "$HOME_DIR/.gnupg"
  ln -sf "$GPG_SOCK" "$HOME_DIR/.gnupg/S.gpg-agent"
fi

# ── sudo opt-in ───────────────────────────────────────────────────────────────
if [ "${CLAUDIUS_SUDO:-0}" = "1" ]; then
  : > /etc/sudoers.d/claudius
  for cmd in ${CLAUDIUS_SUDO_CMDS:-apt apt-get pip pip3 npm}; do
    cmd_path="$(command -v "$cmd" 2>/dev/null || true)"
    [ -n "$cmd_path" ] && printf '%s ALL=(root) NOPASSWD: %s\n' "$HOST_USER" "$cmd_path" \
      >> /etc/sudoers.d/claudius
  done
  chmod 440 /etc/sudoers.d/claudius
fi

# ── DNS ───────────────────────────────────────────────────────────────────────
# Write resolv.conf from CLAUDIUS_DNS. Always include 127.0.0.11 first so
# Docker's embedded resolver works as fallback when external servers are
# unreachable (e.g. network isolation, firewall rules on port 53).
{
  echo "nameserver 127.0.0.11"
  for resolver in ${CLAUDIUS_DNS:-}; do
    echo "nameserver $resolver"
  done
} > /etc/resolv.conf

# ── Banner ────────────────────────────────────────────────────────────────────
echo
echo "╔══════════════════════════════╗"
echo "║       🌿  claudius  🏛️       ║"
echo "║    sandboxed since 54 AD     ║"
echo "╚══════════════════════════════╝"
echo
echo "🪶 Imperial mandate: $HOST_USER"
echo

# Forwarding hints
hints=()
[ -n "${SSH_AUTH_SOCK:-}" ]            && hints+=("🗝️ SSH agent forwarded")
[ -n "${GPG_SOCK:-}" ]                 && hints+=("⚜️ GPG agent forwarded")
[ -S /run/claudius/clipboard.sock ]    && hints+=("📜 Clipboard bridge active")
[ "${CLAUDIUS_SUDO:-0}" = "1" ]        && hints+=("⚠️ sudo enabled (scope: ${CLAUDIUS_SUDO_CMDS:-apt apt-get pip pip3 npm})")
if [ "${#hints[@]}" -gt 0 ]; then
  printf '%s\n' "${hints[@]}"
  echo
fi

# ── User init hook ────────────────────────────────────────────────────────────
# Mount a custom script at /etc/claudius/user-init.sh to run setup as root
# before the privilege drop (e.g. apt install, npm install -g, go install).
if [ -f /etc/claudius/user-init.sh ]; then
  echo "🔧 Running user init..."
  bash /etc/claudius/user-init.sh
  # user-init.sh may write /etc/claudius/user-env.sh to export PATH additions
  # and other variables that Claude and the shell should inherit.
  if [ -f /etc/claudius/user-env.sh ]; then
    # shellcheck source=/dev/null
    . /etc/claudius/user-env.sh
  fi
  echo
fi

# Docker-in-sandbox hint
if [ -n "${DOCKER_HOST:-}" ]; then
  docker_cmds="ps | logs | images | inspect | info | network ls | volume ls"
  [ "${DOCKER_WRITE:-}" = "1" ] && docker_cmds="$docker_cmds | run | build | stop"
  echo "🐳 docker $docker_cmds"
fi
echo "🐚 shell available after exiting claude"
echo

export PATH="$HOME_DIR/.local/bin:$PATH"

# ── Git init in home ──────────────────────────────────────────────────────────
# Claude Code (>=2.1.31) hangs on startup in non-git directories on gVisor/9P
# mounts. Source: https://github.com/anthropics/claude-code/issues/22049
# Fix: init a bare git repo in the container home so Claude finds .git by
# traversing up from the project subdir – without touching the user's project.
git init -q -b main "$HOME_DIR"
chown -R "$HOST_UID:$HOST_GID" "$HOME_DIR/.git"

# ── Privilege drop ────────────────────────────────────────────────────────────
# Switch to the host user. Without sudo opt-in, --no-new-privs prevents any
# further escalation via setuid binaries.
if [ "${CLAUDIUS_SUDO:-0}" = "1" ]; then
  drop=(gosu "$HOST_USER")
else
  drop=(gosu "$HOST_USER" setpriv --no-new-privs)
fi

project_home="$HOME_DIR/$PROJECT_NAME"
if [ $# -eq 0 ]; then
  "${drop[@]}" bash -c "cd \"$project_home\" && claude" || true
  exec "${drop[@]}" bash -c "cd \"$project_home\" && exec bash"
else
  exec "${drop[@]}" "$@"
fi
