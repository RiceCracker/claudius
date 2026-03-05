#!/usr/bin/env bash
# claudius – sandboxed Claude Code shell
# Usage: make install  →  claudius

set -e

CLAUDIUS_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

if ! docker image inspect claudius &>/dev/null; then
  echo "📜 Image 'claudius' not found – building (this takes ~2 min once)..."
  docker build -t claudius -f "$CLAUDIUS_DIR/docker/claudius/Dockerfile" "$CLAUDIUS_DIR"
fi

if [ -n "$1" ] && [ -d "$1" ]; then
  PROJECT_DIR="$(cd "$1" && pwd)"
  shift
else
  PROJECT_DIR="$(pwd)"
fi

if [ -f "$CLAUDIUS_DIR/.env" ]; then
  # shellcheck source=/dev/null
  . "$CLAUDIUS_DIR/.env"
fi

host_user="$(id -un)"
project_name="$(basename "$PROJECT_DIR")"
NET="claudius-$$"
PROXY="claudius-docker-$$"
MEMORY="${CLAUDIUS_MEMORY:-4g}"
CPUS="${CLAUDIUS_CPUS:-4}"
DNS="${CLAUDIUS_DNS:-1.1.1.1 1.0.0.1 8.8.8.8 8.8.4.4}"
DOCKER_WRITE="${CLAUDIUS_DOCKER_WRITE:-}"
SSH="${CLAUDIUS_SSH:-0}"
GPG="${CLAUDIUS_GPG:-}"
# Anthropic API is always reachable – Claude Code requires it
ALLOW="*.anthropic.com:443/tcp ${CLAUDIUS_ALLOW:-}"
CLIPBOARD="${CLAUDIUS_CLIPBOARD:-1}"
SUDO="${CLAUDIUS_SUDO:-0}"
ENVOY="claudius-proxy-$$"
ENVOY_CONF_FILE=""
ENVOY_IP=""

XAUTH_FILE=""
cleanup() {
  docker rm -f "$PROXY" 2>/dev/null || true
  docker rm -f "$ENVOY" 2>/dev/null || true
  docker network rm "$NET" 2>/dev/null || true
  [ -n "$XAUTH_FILE" ] && rm -f "$XAUTH_FILE"
  [ -n "$ENVOY_CONF_FILE" ] && rm -f "$ENVOY_CONF_FILE"; true
}
trap cleanup EXIT

# Isolated network so proxy and claudius can talk
docker network create "$NET" >/dev/null

# ── Docker socket proxy ────────────────────────────────────────────────────────
# shellcheck source=docker/docker-socket-proxy/start.sh
. "$CLAUDIUS_DIR/docker/docker-socket-proxy/start.sh"

EXTRA_ARGS=()
[ "$DOCKER_WRITE" = "1" ] && EXTRA_ARGS+=(-e "DOCKER_WRITE=1")
[ -n "$ALLOW" ]        && EXTRA_ARGS+=(-e "CLAUDIUS_ALLOW=$ALLOW")
if [ "$SSH" = "1" ] && [ -n "${SSH_AUTH_SOCK:-}" ] && [ -S "$SSH_AUTH_SOCK" ]; then
  EXTRA_ARGS+=(-v "$SSH_AUTH_SOCK:$SSH_AUTH_SOCK" -e "SSH_AUTH_SOCK=$SSH_AUTH_SOCK" -e "CLAUDIUS_SSH=1")
fi
if [ "$GPG" = "1" ]; then
  GPG_SOCK="$(gpgconf --list-dirs agent-socket 2>/dev/null || true)"
  if [ -n "$GPG_SOCK" ] && [ -S "$GPG_SOCK" ]; then
    EXTRA_ARGS+=(-v "$GPG_SOCK:$GPG_SOCK" -e "GPG_SOCK=$GPG_SOCK")
  fi
fi
if [ "$CLIPBOARD" = "1" ]; then
  if [ -n "${WAYLAND_DISPLAY:-}" ] && [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]; then
    EXTRA_ARGS+=(
      -e "WAYLAND_DISPLAY=$WAYLAND_DISPLAY"
      -e "XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR"
      -v "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY:$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
    )
  elif [ -n "${DISPLAY:-}" ] && [ -d /tmp/.X11-unix ]; then
    XAUTH_FILE="$(mktemp /tmp/.claudius-xauth.XXXXXX)"
    xauth extract - "$DISPLAY" 2>/dev/null | xauth -f "$XAUTH_FILE" merge - 2>/dev/null || true
    EXTRA_ARGS+=(
      -e "DISPLAY=$DISPLAY"
      -e "XAUTHORITY=/tmp/.claudius-xauth"
      -v /tmp/.X11-unix:/tmp/.X11-unix
      -v "$XAUTH_FILE:/tmp/.claudius-xauth:ro"
    )
  fi
fi

# ── Envoy proxy ────────────────────────────────────────────────────────────────
# shellcheck source=docker/envoy/start.sh
. "$CLAUDIUS_DIR/docker/envoy/start.sh"


EXTRA_ARGS+=(
  -e "http_proxy=http://$ENVOY_IP:3128"
  -e "https_proxy=http://$ENVOY_IP:3128"
  -e "HTTP_PROXY=http://$ENVOY_IP:3128"
  -e "HTTPS_PROXY=http://$ENVOY_IP:3128"
  -e "ENVOY_IP=$ENVOY_IP"
)

# ── sudo opt-in ───────────────────────────────────────────────────────────────
if [ "$SUDO" = "1" ]; then
  EXTRA_ARGS+=(
    -e "CLAUDIUS_SUDO=1"
    -e "CLAUDIUS_SUDO_CMDS=${CLAUDIUS_SUDO_CMDS:-apt apt-get pip pip3 npm}"
  )
fi

TTY_FLAG="-i"; [ -t 0 ] && [ -t 1 ] && TTY_FLAG="-it"
docker run $TTY_FLAG --rm \
  --name "claudius-$$" \
  --cap-drop ALL \
  --cap-add CHOWN \
  --cap-add DAC_OVERRIDE \
  --cap-add FOWNER \
  --cap-add SETUID \
  --cap-add SETGID \
  --cap-add SETPCAP \
  --cap-add NET_ADMIN \
  --cap-add NET_RAW \
  --hostname claudius \
  --network "$NET" \
  --memory "$MEMORY" \
  --cpus "$CPUS" \
  --pids-limit 512 \
  -v "$HOME/.claude:/home/$host_user/.claude" \
  -v "$HOME/.claude.json:/home/$host_user/.claude.json" \
  -v "$PROJECT_DIR:/home/$host_user/$project_name" \
  -w "/home/$host_user/$project_name" \
  -e HOST_UID="$(id -u)" \
  -e HOST_GID="$(id -g)" \
  -e HOST_USER="$host_user" \
  -e DOCKER_HOST="tcp://$PROXY:2375" \
  -e DOCKER_PROXY_IP="$PROXY_IP" \
  -e CLAUDIUS_DNS="$DNS" \
  -e TERM=xterm-256color \
  -e COLORTERM=truecolor \
  "${EXTRA_ARGS[@]}" \
  claudius "$@"
