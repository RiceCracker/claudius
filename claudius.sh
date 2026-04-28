#!/usr/bin/env bash
# claudius – sandboxed Claude Code shell
#
# Usage: claudius [SUBCOMMAND] [ARGS...]
#
# Run `claudius help` for details.

set -e

# ── Locate ourselves (resolve one level of symlink for `make install`) ────────
_self="${BASH_SOURCE[0]:-$0}"
[ -L "$_self" ] && _self="$(readlink "$_self")"
CLAUDIUS_DIR="$(cd "$(dirname "$_self")" && pwd)"
unset _self

# ── Load config from .env ─────────────────────────────────────────────────────
_env_file="${CLAUDIUS_ENV_FILE:-$CLAUDIUS_DIR/.env}"
if [ -f "$_env_file" ]; then
  # shellcheck source=/dev/null
  . "$_env_file"
fi
unset _env_file

# ── Configuration (all overridable via env) ───────────────────────────────────
CLAUDIUS_IMAGE="${CLAUDIUS_IMAGE:-claudius}"
MEMORY="${CLAUDIUS_MEMORY:-4g}"
CPUS="${CLAUDIUS_CPUS:-4}"
DNS="${CLAUDIUS_DNS:-1.1.1.1 1.0.0.1 8.8.8.8 8.8.4.4}"
CLIPBOARD="${CLAUDIUS_CLIPBOARD:-1}"
SUDO="${CLAUDIUS_SUDO:-0}"
SSH="${CLAUDIUS_SSH:-0}"
GPG="${CLAUDIUS_GPG:-}"
DOCKER_WRITE="${CLAUDIUS_DOCKER_WRITE:-}"
RUNTIME="${CLAUDIUS_RUNTIME:-}"
USER_INIT="${CLAUDIUS_USER_INIT:-}"

# ── Helpers ───────────────────────────────────────────────────────────────────
die()   { echo "❌ $*" >&2; exit 1; }
warn()  { echo "⚠️  $*" >&2; }
ok()    { echo "✓ $*"; }
fail()  { echo "✗ $*"; }

_have_clipboard_tool() {
  if [ -n "${WAYLAND_DISPLAY:-}" ] && command -v wl-paste >/dev/null && command -v wl-copy >/dev/null; then
    return 0
  fi
  if [ -n "${DISPLAY:-}" ] && command -v xclip >/dev/null; then
    return 0
  fi
  return 1
}

_build_image() {
  docker build -t "$CLAUDIUS_IMAGE" -f "$CLAUDIUS_DIR/docker/claudius/Dockerfile" "$CLAUDIUS_DIR"
}

# Append `-v sock:sock -e env_name=sock` (and optionally `-e sentinel=1`) to
# EXTRA_ARGS, but only when the socket actually exists. Used for SSH and GPG.
_forward_socket() {  # _forward_socket SOCK_PATH ENV_NAME [SENTINEL_NAME]
  local sock="$1" env_name="$2" sentinel="${3:-}"
  [ -n "$sock" ] && [ -S "$sock" ] || return 0
  EXTRA_ARGS+=(-v "$sock:$sock" -e "$env_name=$sock")
  [ -n "$sentinel" ] && EXTRA_ARGS+=(-e "$sentinel=1")
  return 0
}

# ── Subcommands ───────────────────────────────────────────────────────────────

cmd_help() {
  cat <<EOF
Usage: claudius [SUBCOMMAND] [ARGS...]

Subcommands:
  run [DIR] [CMD...]    Launch the sandboxed shell (default if omitted)
  build                 Build/rebuild the container image
  prune                 Remove orphaned claudius containers and networks
  doctor                Check configuration sanity (paths, image, runtime)
  version               Print the claudius version
  help                  Show this help

Environment:
  Configure via \$CLAUDIUS_DIR/.env or export variables manually.
  See .env.example for the full list. Key ones:
    CLAUDIUS_SSH / CLAUDIUS_GPG / CLAUDIUS_CLIPBOARD
    CLAUDIUS_SUDO / CLAUDIUS_DOCKER_WRITE
    CLAUDIUS_RUNTIME (e.g. runsc for gVisor)

Examples:
  claudius                              # run in current directory
  claudius ~/src/myproject              # run in a specific directory
  claudius ~/src/app npm test           # run a command non-interactively
  claudius doctor                       # diagnose configuration
  claudius prune                        # clean up orphans
EOF
}

cmd_version() {
  local v
  if [ -f "$CLAUDIUS_DIR/VERSION" ]; then
    v="$(cat "$CLAUDIUS_DIR/VERSION")"
  else
    v="$(cd "$CLAUDIUS_DIR" && git describe --tags --always 2>/dev/null || echo "unversioned")"
  fi
  echo "claudius $v"
}

cmd_build() {
  _build_image
  ok "image built: $CLAUDIUS_IMAGE"
}

cmd_doctor() {
  local status=0
  _check() {  # _check "label" command...
    local label="$1"; shift
    if "$@" >/dev/null 2>&1; then ok "$label"; else fail "$label"; status=1; fi
  }

  _check "docker CLI installed"          command -v docker
  _check "docker daemon reachable"       docker info

  if docker image inspect "$CLAUDIUS_IMAGE" &>/dev/null; then
    ok "image '$CLAUDIUS_IMAGE' present"
  else
    warn "image '$CLAUDIUS_IMAGE' not found – run 'claudius build'"
  fi

  _check "~/.claude/ exists"      test -d "$HOME/.claude"
  _check "~/.claude.json exists"  test -f "$HOME/.claude.json"

  if [ -n "$USER_INIT" ]; then
    if [ -f "$USER_INIT" ]; then
      ok "CLAUDIUS_USER_INIT: $USER_INIT"
    else
      fail "CLAUDIUS_USER_INIT: file not found: $USER_INIT"
      status=1
    fi
  fi

  if [ -n "$RUNTIME" ]; then
    if docker info 2>/dev/null | grep -qi "$RUNTIME"; then
      ok "runtime '$RUNTIME' registered"
    else
      fail "runtime '$RUNTIME' not registered in Docker"
      status=1
    fi
  fi

  exit "$status"
}

cmd_prune() {
  echo "→ containers:"
  docker ps -a --filter name=claudius- --format '{{.Names}}' | while read -r name; do
    [ -z "$name" ] && continue
    docker rm -f "$name" >/dev/null 2>&1 && echo "  removed $name"
  done

  echo "→ networks:"
  docker network ls --filter name=claudius- --format '{{.Name}}' | while read -r name; do
    [ -z "$name" ] && continue
    docker network rm "$name" >/dev/null 2>&1 && echo "  removed $name"
  done
}

# ── The main run flow ─────────────────────────────────────────────────────────
cmd_run() {
  # Session-scoped state (globals so the trap can see them)
  NET="claudius-$$"
  PROXY="claudius-docker-$$"
  CLIP_PID=""
  CLIP_DIR=""

  cleanup() {
    docker rm -f "$PROXY" 2>/dev/null || true
    docker network rm "$NET" 2>/dev/null || true
    [ -n "$CLIP_PID" ] && kill "$CLIP_PID" 2>/dev/null || true
    [ -n "$CLIP_DIR" ] && rm -rf "$CLIP_DIR"
    return 0
  }
  trap cleanup EXIT INT TERM

  # Ensure image exists
  if ! docker image inspect "$CLAUDIUS_IMAGE" &>/dev/null; then
    if [ "$CLAUDIUS_IMAGE" = "claudius" ]; then
      echo "📜 Image 'claudius' not found – building (this takes ~2 min once)..."
      _build_image
    else
      die "Image '$CLAUDIUS_IMAGE' not found. Build it first:
   docker build -t $CLAUDIUS_IMAGE -f /path/to/your/Dockerfile ."
    fi
  fi

  # Resolve project directory
  if [ -n "${1:-}" ] && [ -d "$1" ]; then
    PROJECT_DIR="$(cd "$1" && pwd)"
    shift
  else
    PROJECT_DIR="$(pwd)"
  fi
  local host_user project_name
  host_user="$(id -un)"
  project_name="$(basename "$PROJECT_DIR" | tr ':' '-')"

  # ── Assemble docker run arguments ───────────────────────────────────────────
  local DNS_ARGS=()
  for resolver in $DNS; do
    DNS_ARGS+=(--dns "$resolver")
  done

  local EXTRA_ARGS=()

  [ "$DOCKER_WRITE" = "1" ] && EXTRA_ARGS+=(-e "DOCKER_WRITE=1")

  # SSH + GPG agent forwarding (silently skipped if the socket isn't there)
  [ "$SSH" = "1" ] && _forward_socket "${SSH_AUTH_SOCK:-}" SSH_AUTH_SOCK CLAUDIUS_SSH
  [ "$GPG" = "1" ] && _forward_socket "$(gpgconf --list-dirs agent-socket 2>/dev/null || true)" GPG_SOCK

  # Clipboard forwarding via host-side bridge (no X11 socket exposure).
  # A Python daemon on the host speaks a tiny protocol over a Unix socket;
  # inside the container, the `claudius-clip` shim (aliased as xclip/wl-copy/
  # wl-paste/pbcopy/pbpaste) talks to that socket.
  if [ "$CLIPBOARD" = "1" ]; then
    if _have_clipboard_tool; then
      CLIP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/claudius-clip.XXXXXX")"
      local clip_sock="$CLIP_DIR/sock"
      python3 "$CLAUDIUS_DIR/docker/clipboard/host.py" "$clip_sock" &
      CLIP_PID=$!
      # Wait briefly for the socket to appear (bind is synchronous in the daemon).
      local _i
      for _i in 1 2 3 4 5 6 7 8 9 10; do [ -S "$clip_sock" ] && break; sleep 0.1; done
      if [ -S "$clip_sock" ]; then
        EXTRA_ARGS+=(-v "$clip_sock:/run/claudius/clipboard.sock")
      else
        warn "clipboard bridge failed to start – continuing without clipboard"
        kill "$CLIP_PID" 2>/dev/null || true
        CLIP_PID=""
        rm -rf "$CLIP_DIR"; CLIP_DIR=""
      fi
    else
      warn "no host clipboard tool (xclip+DISPLAY or wl-clipboard+WAYLAND_DISPLAY) – clipboard disabled"
    fi
  fi

  # User init hook
  if [ -n "$USER_INIT" ]; then
    USER_INIT="$(cd "$(dirname "$USER_INIT")" && pwd)/$(basename "$USER_INIT")"
    [ -f "$USER_INIT" ] || die "CLAUDIUS_USER_INIT: file not found: $USER_INIT"
    EXTRA_ARGS+=(-v "$USER_INIT:/etc/claudius/user-init.sh:ro")
  fi

  # sudo opt-in
  if [ "$SUDO" = "1" ]; then
    EXTRA_ARGS+=(
      -e "CLAUDIUS_SUDO=1"
      -e "CLAUDIUS_SUDO_CMDS=${CLAUDIUS_SUDO_CMDS:-apt apt-get pip pip3 npm}"
    )
  fi

  # Alternate runtime (gVisor etc.)
  if [ -n "$RUNTIME" ]; then
    EXTRA_ARGS+=(--runtime "$RUNTIME" -e "CLAUDIUS_RUNTIME=$RUNTIME")
  fi

  # Extra volumes – space-separated list of host:container[:options] specs
  local _vol
  for _vol in ${CLAUDIUS_EXTRA_VOLUMES:-}; do
    EXTRA_ARGS+=(-v "$_vol")
  done

  # ── Isolated network (try IPv6, fall back to IPv4-only) ─────────────────────
  # The container reaches the docker-socket-proxy sidecar through this network;
  # outbound internet flows out via the bridge to the host (no filtering).
  docker network create --ipv6 "$NET" >/dev/null 2>&1 \
    || docker network create "$NET" >/dev/null

  # ── Docker socket proxy ─────────────────────────────────────────────────────
  # shellcheck source=docker/docker-socket-proxy/start.sh
  . "$CLAUDIUS_DIR/docker/docker-socket-proxy/start.sh"

  # ── Run the container ───────────────────────────────────────────────────────
  # Docker's default seccomp profile applies intentionally (blocks ~44 syscalls
  # like kexec_load, create_module, AF_PACKET sockets). A custom profile would
  # add maintenance cost without clear security benefit here.
  local TTY_FLAG="-i"
  [ -t 0 ] && [ -t 1 ] && TTY_FLAG="-it"

  docker run $TTY_FLAG --rm \
    --name "claudius-$$" \
    --hostname claudius \
    --network "$NET" \
    --memory "$MEMORY" \
    --cpus "$CPUS" \
    --pids-limit 512 \
    --cap-drop ALL \
    --cap-add CHOWN \
    --cap-add DAC_OVERRIDE \
    --cap-add FOWNER \
    --cap-add SETUID \
    --cap-add SETGID \
    --cap-add SETPCAP \
    --cap-add NET_RAW \
    "${DNS_ARGS[@]}" \
    -v "$HOME/.claude:/home/$host_user/.claude" \
    -v "$HOME/.claude.json:/home/$host_user/.claude.json" \
    -v "$CLAUDIUS_DIR/CLAUDE.md:/etc/claude-code/CLAUDE.md:ro" \
    -v "$PROJECT_DIR:/home/$host_user/$project_name" \
    -w "/home/$host_user" \
    -e HOST_UID="$(id -u)" \
    -e HOST_GID="$(id -g)" \
    -e HOST_USER="$host_user" \
    -e PROJECT_NAME="$project_name" \
    -e DOCKER_HOST="tcp://$PROXY_IP:2375" \
    -e CLAUDIUS_DNS="$DNS" \
    -e TERM=xterm-256color \
    -e COLORTERM=truecolor \
    "${EXTRA_ARGS[@]}" \
    "$CLAUDIUS_IMAGE" "$@"
}

# ── Dispatch ──────────────────────────────────────────────────────────────────
# Known subcommands are matched explicitly. Anything else (including no args
# at all, or a directory path) falls through to `run`, so `claudius ~/proj`
# and bare `claudius` both just work.
case "${1-}" in
  help|--help|-h)       cmd_help ;;
  version|--version|-V) cmd_version ;;
  doctor)               shift; cmd_doctor "$@" ;;
  build)                shift; cmd_build  "$@" ;;
  prune)                shift; cmd_prune  "$@" ;;
  run)                  shift; cmd_run    "$@" ;;
  *)                    cmd_run           "$@" ;;
esac
