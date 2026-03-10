#!/bin/bash
set -e

# ── User setup ────────────────────────────────────────────────────────────────
# HOST_UID/HOST_GID/HOST_USER are passed by the launcher so that files in the
# mounted project directory are owned by the right user.

# Remove any existing user that already claims the same UID (avoids mount conflicts).
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

mkdir -p "/home/$HOST_USER/.local/bin" "/home/$HOST_USER/.local/share"
cp    /root/.bashrc "/home/$HOST_USER/.bashrc"
cp -r /root/.config "/home/$HOST_USER/.config"
ln -sf /usr/local/bin/claude   "/home/$HOST_USER/.local/bin/claude"
ln -sf /usr/local/share/claude "/home/$HOST_USER/.local/share/claude"
chown    "$HOST_UID:$HOST_GID" "/home/$HOST_USER"
chown -R "$HOST_UID:$HOST_GID" "/home/$HOST_USER/.config" "/home/$HOST_USER/.local"
chown    "$HOST_UID:$HOST_GID" "/home/$HOST_USER/.bashrc" "/home/$HOST_USER/.claude.json" 2>/dev/null || true

if [ -n "${GPG_SOCK:-}" ] && [ -S "$GPG_SOCK" ]; then
  mkdir -p "/home/$HOST_USER/.gnupg"
  chmod 700 "/home/$HOST_USER/.gnupg"
  chown "$HOST_UID:$HOST_GID" "/home/$HOST_USER/.gnupg"
  ln -sf "$GPG_SOCK" "/home/$HOST_USER/.gnupg/S.gpg-agent"
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
# Docker's embedded resolver (127.0.0.11) can be unreliable. Write resolv.conf
# directly from CLAUDIUS_DNS so the container always has working DNS.
if [ -n "${CLAUDIUS_DNS:-}" ]; then
  : > /etc/resolv.conf
  for resolver in $CLAUDIUS_DNS; do
    echo "nameserver $resolver" >> /etc/resolv.conf
  done
fi

# ── Banner ────────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════╗"
echo "║       🌿  claudius  🏛️       ║"
echo "║    sandboxed since 54 AD     ║"
echo "╚══════════════════════════════╝"
echo ""
echo "🪶 Imperial mandate: $HOST_USER"
echo ""

# ── Proxy status ──────────────────────────────────────────────────────────────
if [ "${CLAUDIUS_ALLOW_COUNT:-0}" = "unrestricted" ]; then
  echo "🌐 No proxy – unrestricted network access"
elif [ "${CLAUDIUS_ALLOW_COUNT:-0}" -gt 0 ]; then
  echo "🌍 Proxy active (${CLAUDIUS_ALLOW_COUNT} entries)"
else
  echo "🔒 Network blocked – no entries in CLAUDIUS_ALLOW"
fi
echo ""

# ── Hints ─────────────────────────────────────────────────────────────────────
showed_hints=false
[ -n "${SSH_AUTH_SOCK:-}" ] && { echo "🗝️ SSH agent forwarded"; showed_hints=true; }
[ -n "${GPG_SOCK:-}" ] && { echo "⚜️ GPG agent forwarded"; showed_hints=true; }
[ -n "${WAYLAND_DISPLAY:-}" ] && { echo "📜 Clipboard forwarded (Wayland)"; showed_hints=true; }
[ -n "${DISPLAY:-}" ] && { echo "📜 Clipboard forwarded (X11)"; showed_hints=true; }
[ "${CLAUDIUS_SUDO:-0}" = "1" ] && { echo "⚠️ sudo enabled (scope: ${CLAUDIUS_SUDO_CMDS:-apt apt-get pip pip3 npm})"; showed_hints=true; }
[ "$showed_hints" = true ] && echo ""

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
  echo ""
fi

if [ -n "${DOCKER_HOST:-}" ]; then
  _docker_cmds="ps | logs | images | inspect | info | network ls | volume ls"
  [ "${DOCKER_WRITE:-}" = "1" ] && _docker_cmds="$_docker_cmds | run | build | stop"
  echo "🐳 docker $_docker_cmds"
fi
echo "🐚 shell available after exiting claude"
echo ""

export PATH="/home/$HOST_USER/.local/bin:$PATH"

# ── Git init in home ───────────────────────────────────────────────────────────
# Claude Code (>=2.1.31) hangs on startup in non-git directories on gVisor/9P
# mounts. Source: https://github.com/anthropics/claude-code/issues/22049 
# Fix: init a bare git repo in the container home so Claude finds .git
# by traversing up from the project subdir – without touching the user's project.
git init -q "/home/$HOST_USER"
chown -R "$HOST_UID:$HOST_GID" "/home/$HOST_USER/.git"

# Privilege drop: switch to the host user. Without sudo opt-in, --no-new-privs
# prevents any further escalation via setuid binaries.
if [ "${CLAUDIUS_SUDO:-0}" = "1" ]; then
  drop="gosu $HOST_USER"
else
  drop="gosu $HOST_USER setpriv --no-new-privs"
fi

if [ $# -eq 0 ]; then
  $drop bash -c "cd \"/home/$HOST_USER/$PROJECT_NAME\" && claude" || true
  exec $drop bash -c "cd \"/home/$HOST_USER/$PROJECT_NAME\" && exec bash"
else
  exec $drop "$@"
fi
