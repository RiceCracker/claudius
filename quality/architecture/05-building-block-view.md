# Building Block View – claudius
> Rebuilt 2026-04-28 from current code. The Network Proxy block is gone (ADR-007).

## Component Overview

| Component | Directory / File | Purpose |
|---|---|---|
| Launcher | `claudius.sh` | Main entrypoint: parse subcommands, load `.env`, create network, start docker-socket-proxy + clipboard bridge, run container with all flags assembled |
| Container Image | `docker/claudius/Dockerfile` | Base: `node:22-bookworm-slim`. Adds: Claude Code (native installer), language servers, ruff, starship, docker CLI, clipboard shim |
| Container Entrypoint | `docker/claudius/entrypoint.sh` | runs as root: provisions host user inside the container, copies dotfiles, writes resolv.conf, opt-in sudoers, prints banner, executes user-init hook, drops privileges via `gosu` (+ `setpriv --no-new-privs` unless `CLAUDIUS_SUDO=1`), starts Claude Code |
| Extension Examples | `docker/claudius/Dockerfile.go.example`, `Dockerfile.flutter.example`, `Dockerfile.rust.example` | Templates for `FROM claudius` — Go, Flutter, Rust toolchains |
| Docker Socket Proxy Startup | `docker/docker-socket-proxy/start.sh` | sourced by `claudius.sh`; runs Tecnativa `docker-socket-proxy` on the per-session network. Sets `CONTAINERS=IMAGES=INFO=NETWORKS=VOLUMES=VERSION=1`; adds `POST=BUILD=1` only when `CLAUDIUS_DOCKER_WRITE=1`. Captures the proxy IP for `DOCKER_HOST=tcp://$PROXY_IP:2375` |
| Clipboard Host Daemon | `docker/clipboard/host.py` | per-session Python daemon: binds a Unix socket on the host, brokers reads/writes via `xclip` / `wl-copy` / `wl-paste` |
| Clipboard Container Shim | `docker/clipboard/client.py` (installed as `claudius-clip`) | aliased into the container as `xclip`, `xsel`, `wl-copy`, `wl-paste`, `pbcopy`, `pbpaste`. Talks the bridge protocol |
| Managed Policy | `CLAUDE.md` → `/etc/claude-code/CLAUDE.md` | bind-mounted read-only; Claude Code's highest-precedence config layer |
| Tests | `tests/integration.sh` + `tests/integration.env` | end-to-end smoke check: container starts, mounts work, DNS resolves, outbound reaches the internet, docker-socket-proxy is read-only |

## Prio-1 Layer: Launcher (`claudius.sh`)

The launcher is a single bash script (~336 lines after the proxy refactor). Subcommands dispatch via `case`; bare `claudius [DIR] [CMD...]` falls through to `cmd_run`.

| Section | Lines (approx.) | Responsibility |
|---|---|---|
| Self-locate + `.env` load | 1–22 | Resolve own path through one symlink, source `.env` from the script dir (or `CLAUDIUS_ENV_FILE`) |
| Configuration defaults | 24–35 | All `CLAUDIUS_*` env vars get a default; assigns to short locals (`MEMORY`, `CPUS`, `DNS`, `RUNTIME`, …) |
| Helpers | 37–53 | `die`/`warn`/`ok`/`fail` echo helpers; `_have_clipboard_tool` detects host clipboard tooling |
| `cmd_help` | – | Prints subcommand and env-var summary |
| `cmd_version` | – | Reads `VERSION` file or `git describe` |
| `cmd_build` | – | `docker build` the claudius image |
| `cmd_doctor` | – | Checks: docker CLI, docker daemon, image present, `~/.claude/`, `~/.claude.json`, optional user-init script, optional runtime |
| `cmd_prune` | – | Stops orphaned `claudius-*` containers and networks |
| `cmd_run` | bulk of file | Session lifecycle: traps EXIT/INT/TERM, ensures image, resolves project dir, builds DNS args, conditionally adds SSH/GPG/clipboard/user-init/sudo/runtime/extra-volumes flags, creates per-session Docker network (with IPv6 fallback), sources `docker/docker-socket-proxy/start.sh`, runs `docker run` with capability/cgroup/seccomp/mount/env flags |

## Prio-1 Layer: Container Entrypoint (`docker/claudius/entrypoint.sh`)

Single bash script (~138 lines) running as PID 1 root inside the container.

| Section | Responsibility |
|---|---|
| User setup | Resolves UID/GID conflicts, creates the host user inside the container, copies `/root/.bashrc` + `/root/.config` + claude binary symlinks into `/home/$HOST_USER`, chowns to host UID/GID |
| GPG socket | When `GPG_SOCK` is set, links it into `~/.gnupg/S.gpg-agent` |
| sudo opt-in | When `CLAUDIUS_SUDO=1`, writes `/etc/sudoers.d/claudius` with `NOPASSWD: <paths from CLAUDIUS_SUDO_CMDS>` |
| DNS | Writes `/etc/resolv.conf` from `CLAUDIUS_DNS` (Docker's embedded `127.0.0.11` is unreliable, especially under gVisor) |
| Banner | Prints emperor banner + forwarding hints (SSH/GPG/clipboard/sudo) |
| User-init hook | Runs `/etc/claudius/user-init.sh` if mounted; sources optional `/etc/claudius/user-env.sh` for PATH/env additions |
| Git init in home | `git init -q -b main /home/$HOST_USER` to work around a Claude Code regression that hangs on startup in non-git directories on gVisor/9P mounts |
| Privilege drop | `exec gosu $HOST_USER setpriv --no-new-privs` (SUDO=0) or `exec gosu $HOST_USER` (SUDO=1) |
| Claude launch | If no args: starts Claude in `$PROJECT_NAME` subdir, falls back to interactive bash on Claude exit. With args: execs them after the privilege drop |

## Prio-2 Layer: Docker Socket Proxy (`docker/docker-socket-proxy/start.sh`)

Sourced helper, ~21 lines. Runs the Tecnativa `docker-socket-proxy:v0.4.2` image on the per-session Docker network with read-only verb flags. Captures the assigned bridge IP and writes it to `PROXY_IP` for `claudius.sh` to inject as `DOCKER_HOST=tcp://$PROXY_IP:2375` into the container.

## Prio-2 Layer: Clipboard Bridge

Two scripts. `docker/clipboard/host.py` runs on the host before the container starts; binds a Unix socket in a per-session temp dir; on read returns the host clipboard (`xclip -o` / `wl-paste`); on write writes the supplied bytes to the host clipboard. `docker/clipboard/client.py` is installed inside the container as `/usr/local/bin/claudius-clip` and symlinked from `/usr/local/bin/{xclip,xsel,wl-copy,wl-paste,pbcopy,pbpaste}`. The container speaks the same 1-byte-mode protocol over the bind-mounted socket at `/run/claudius/clipboard.sock`.

## Removed (post-ADR-007)

| Former component | What replaced it |
|---|---|
| `docker/proxy/entrypoint.py` (Python netfilter proxy) | nothing — outbound is unrestricted |
| `docker/proxy/start.sh`, `Dockerfile`, `supervisor.sh`, `prune-chains.sh` | nothing |
| `claudius logs` subcommand | nothing — there are no proxy logs to follow |
| `iptables NFQUEUE` rules | nothing |
| ALLOW string construction in `claudius.sh` | nothing |

The architectural surface shrank by one prio-1 layer. The remaining components form a flat composition: launcher prepares the environment, container runs Claude, two sidecars (socket proxy + clipboard bridge) provide brokered host access.
