#!/bin/bash
set -e

# ── User setup ────────────────────────────────────────────────────────────────
# HOST_UID/HOST_GID/HOST_USER kommen vom Launcher, damit Dateien
# im gemounteten Projektordner dem richtigen User gehören.

# 1. Anderen User mit gleicher UID entfernen (verhindert mount-Konflikte)
conflicting="$(getent passwd "$HOST_UID" 2>/dev/null | cut -d: -f1 || true)"
if [ -n "$conflicting" ] && [ "$conflicting" != "$HOST_USER" ]; then
  userdel "$conflicting" 2>/dev/null || true
fi

# 2. Gruppe anlegen
if ! getent group "$HOST_GID" &>/dev/null; then
  groupadd -g "$HOST_GID" "$HOST_USER"
fi

# 3. User anlegen
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

# ── Banner ────────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════╗"
echo "║       🌿  claudius  🏛️       ║"
echo "║    sandboxed since 54 AD     ║"
echo "╚══════════════════════════════╝"
echo ""
echo "🪶 Imperial mandate: $HOST_USER"
echo ""

# ── Firewall ──────────────────────────────────────────────────────────────────
echo "🔥 Firewall initializing..."
if /usr/local/bin/init-firewall.sh; then
  firewall_ok=1
else
  firewall_ok=0
fi

echo ""
if [ "$firewall_ok" = "0" ]; then
  echo "💀 Firewall failed – no network restrictions active"
else
  allow_count="$(printf '%s\n' ${CLAUDIUS_ALLOW:-} | grep -c '/tcp' 2>/dev/null || true)"
  if [ "$allow_count" -gt 0 ]; then
    echo "🌍 Envoy proxy active ($allow_count TCP entries)"
  else
    echo "🔒 TCP blocked – no entries in CLAUDIUS_ALLOW"
  fi
fi
echo ""

# ── Hints ─────────────────────────────────────────────────────────────────────
[ -n "${SSH_AUTH_SOCK:-}" ] && echo "🗝️ SSH agent forwarded"
[ -n "${GPG_SOCK:-}" ] && echo "⚜️ GPG agent forwarded"
[ -n "${WAYLAND_DISPLAY:-}" ] && echo "📜 Clipboard forwarded (Wayland)"
[ -n "${DISPLAY:-}" ] && echo "📜 Clipboard forwarded (X11)"
[ "${CLAUDIUS_SUDO:-0}" = "1" ] && echo "⚠️  sudo enabled (scope: ${CLAUDIUS_SUDO_CMDS:-apt apt-get pip pip3 npm})"
echo ""
if [ -n "${DOCKER_HOST:-}" ]; then
  _docker_cmds="ps | logs | images | inspect | info | network ls | volume ls"
  [ "${DOCKER_WRITE:-}" = "1" ] && _docker_cmds="$_docker_cmds | run | build | stop"
  echo "🐳 docker $_docker_cmds"
fi
echo "🐚 shell available after exiting claude"
echo ""

export PATH="/home/$HOST_USER/.local/bin:$PATH"
# drop: Wechselt zum Host-User und entzieht NET_ADMIN (Firewall läuft noch als root).
# Ohne sudo-Opt-in kommt --no-new-privs dazu – kein setuid mehr möglich.
if [ "${CLAUDIUS_SUDO:-0}" = "1" ]; then
  drop="setpriv --bounding-set=-net_admin gosu $HOST_USER"
else
  drop="setpriv --bounding-set=-net_admin gosu $HOST_USER setpriv --no-new-privs"
fi

if [ $# -eq 0 ]; then
  $drop claude || true
  exec $drop bash
else
  exec $drop "$@"
fi
