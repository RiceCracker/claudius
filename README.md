# 🌿 claudius 🏛️

The Roman emperor Claudius (reigned 41–54 CE) spent much of his early life marginalized, kept from public office, mocked for his physical disabilities, and largely written off by his own family. When he unexpectedly became emperor after Caligula's assassination, he proved his detractors wrong. He reformed the imperial bureaucracy, presided personally over legal cases, built the harbour at Ostia, and conquered Britain. Ancient sources, written mostly by senatorial aristocrats who resented his reliance on freedmen administrators, tend to paint him as bumbling or manipulated. The reality is more interesting: a deeply learned man, shaped by years of enforced observation rather than action, who governed with procedural seriousness and got more done than most.

He was not without political violence. He authorized executions, navigated treacherous court intrigue, and was no stranger to ruthlessness when he felt it necessary. But he thought before he acted. A fitting patron for an agent that runs in a box — this is that box.

---

## Overview

claudius runs Claude Code inside a hardened, throwaway Docker container so a misbehaving agent — yours, an injected prompt's, an LLM having a bad day's — can't trash your `~`, leak credentials, or `docker run` itself onto the host. Locked down at the container layer by default; SSH agent, GPG agent, clipboard, sudo, and Docker writes are individually opt-in.

**What it is not:** a network-filtering tool. Outbound traffic flows through Docker's bridge unmodified. If you need egress filtering, do it at the host firewall, VPN, or DNS layer.

| Component | Details |
| --- | --- |
| Base image | `node:22-bookworm-slim` |
| Claude Code | native installer (`claude.ai/install.sh`) |
| Gemini MCP | [`@rlabs-inc/gemini-mcp`](https://github.com/RLabs-Inc/gemini-mcp) — 30+ tools (image/video gen, deep research, code execution, …) |
| Language servers | `pyright`, `typescript-language-server`, `bash-language-server`, `vscode-langservers-extracted` (JSON/HTML/CSS/Markdown), `yaml-language-server`, `sql-language-server` |
| Shell | bash + [Starship](https://starship.rs) prompt |
| Tools | git, curl, wget, vim, less, ping, mtr, jq, make, python3, pip, sqlite3, sudo, tree, unzip, netcat, lsof, strace, tcpdump, ssh, docker CLI, gnupg |
| Clipboard | socket-brokered bridge — `claudius-clip` aliased as `xclip` / `wl-copy` / `wl-paste` / `pbcopy` / `pbpaste`, no X11/Wayland socket exposed |

---

## Quick start

```bash
make install            # symlinks `claudius` into ~/.local/bin
claudius doctor         # sanity-check: docker reachable, ~/.claude present, runtime OK
claudius                # run Claude on the current directory (builds the image on first run, ~2 min)
claudius ~/my-project   # …or on a different one
```

`/exit` or Ctrl+C drops you into a bash shell inside the container; exiting that closes everything.

The project directory is mounted at `/home/$USER/<dirname>` and is writable on both sides — files appear on the host with correct UID/GID immediately. `~/.claude/` and `~/.claude.json` are also mounted, so authentication and Claude Code settings persist across runs.

```bash
make build              # rebuild image (cached)
make rebuild            # rebuild without cache, picks up the latest Claude Code
make uninstall          # remove the symlink
```

---

## Hardening (optional)

**gVisor.** [gVisor](https://gvisor.dev) puts a user-space kernel between the container and the host — strongest isolation short of a full VM. Works with SSH, GPG, and clipboard forwarding. Linux only.

```bash
make gvisor-install     # install runsc, register with Docker, configure daemon
make gvisor-check       # verify the install
# then per-session:  CLAUDIUS_RUNTIME=runsc claudius   (or set in .env)
```

**Rootless Docker.** [Rootless mode](https://docs.docker.com/engine/security/rootless/) means a container escape lands in your user account, not host root. claudius works rootless out of the box.

```bash
make rootless-check     # verify your Docker daemon is rootless
```

---

## Usage

```bash
claudius                                       # mount current directory, start claude
claudius ~/my-project                          # mount a specific directory
claudius bash                                  # shell only, no claude
claudius bash -c 'git log --oneline -5'        # one-shot command, also non-interactive friendly
```

Bare `claudius [DIR] [CMD…]` dispatches to `claudius run` under the hood — the explicit form is available too (`claudius run …`), mostly for scripts.

```bash
claudius doctor    # diagnose configuration (paths, image, runtime)
claudius build     # build/rebuild image
claudius prune     # clean up orphaned containers and networks
claudius help      # full usage
```

---

## Configuration

Set variables in a `.env` next to `claudius.sh` (see `.env.example`), or pass them inline:

```bash
CLAUDIUS_MEMORY=8g CLAUDIUS_CPUS=8 claudius
```

| Variable | Default | Description |
| --- | --- | --- |
| `CLAUDIUS_MEMORY` | `4g` | Container memory limit |
| `CLAUDIUS_CPUS` | `4` | Container CPU limit |
| `CLAUDIUS_DNS` | `1.1.1.1 1.0.0.1 8.8.8.8 8.8.4.4` | DNS resolvers (space-separated; IPv6 supported) |
| `CLAUDIUS_SSH` | `0` | `1` = forward the host SSH agent into the container |
| `CLAUDIUS_GPG` | `0` | `1` = forward the host GPG agent socket |
| `CLAUDIUS_CLIPBOARD` | `1` | `0` = disable clipboard bridge. Host needs `xclip+DISPLAY` or `wl-clipboard+WAYLAND_DISPLAY` |
| `CLAUDIUS_DOCKER_WRITE` | `0` | `1` = enable docker write ops; default is inspect-only |
| `CLAUDIUS_SUDO` | `0` | `1` = allow `sudo` for the listed commands; lifts `--no-new-privs` |
| `CLAUDIUS_SUDO_CMDS` | `apt apt-get pip pip3 npm` | Commands allowed via `sudo` when `CLAUDIUS_SUDO=1` |
| `CLAUDIUS_RUNTIME` | unset | Docker runtime — set `runsc` for gVisor; default is `runc` |
| `CLAUDIUS_IMAGE` | `claudius` | Docker image to run; point at a custom image to extend |
| `CLAUDIUS_USER_INIT` | unset | Path to a host script — mounted read-only, run as root before Claude starts |

> **Outbound network is unrestricted.** There is no allow-list, no proxy, no SNI inspection. If you need filtering, layer it on the host (firewall, VPN, DNS sinkhole) — claudius does not.

---

## Extending

The base image is intentionally minimal. Two ways to add tools:

### Custom image (recommended for tooling)

Extend the image with `FROM claudius`, build once, point `CLAUDIUS_IMAGE` at it:

```bash
docker build -t claudius-go -f docker/claudius/Dockerfile.go.example .
CLAUDIUS_IMAGE=claudius-go claudius ~/my-go-project
```

Ready-made templates in `docker/claudius/`:

| File | Adds |
| --- | --- |
| `Dockerfile.go.example` | Go 1.24 (multi-stage) + `gopls` |
| `Dockerfile.flutter.example` | Flutter SDK + Dart language server + Android SDK |
| `Dockerfile.rust.example` | Rust stable + `rust-analyzer` |

```dockerfile
FROM claudius
# add your tools here
ENV PATH="/your/tool/bin:${PATH}"
```

### Runtime init hook (recommended for per-session config)

Mount a host script at `/etc/claudius/user-init.sh`. It runs as root before the privilege drop — useful for git identity or shell aliases. Don't install packages here; use a custom image for that.

```bash
# user-init.sh
git config --file "/home/${HOST_USER}/.gitconfig" user.email "me@example.com"
git config --file "/home/${HOST_USER}/.gitconfig" user.name "My Name"
echo "alias ll='ls -lah'" >> "/home/${HOST_USER}/.bashrc"
```

Need env vars or PATH additions visible to Claude? Write them to `/etc/claudius/user-env.sh` from your init script — the entrypoint sources it before the privilege drop:

```bash
echo 'export MY_TOKEN=xyz' >> /etc/claudius/user-env.sh
```

Wire it up:

```bash
CLAUDIUS_USER_INIT=./user-init.sh claudius ~/my-project
# or in .env:
# CLAUDIUS_USER_INIT=/home/you/dotfiles/claudius-init.sh
```

A template lives at `user-init.sh.example`.

---

## Security

claudius protects the host from the agent. Your project files and your prompting are a different problem.

| Measure | Detail |
| --- | --- |
| Mount whitelist | Only the project dir, `~/.claude/`, `~/.claude.json` (and the optional sockets when their feature is on) |
| Capability drop | `--cap-drop ALL` + a minimal set re-added; capabilities stay bounded even with `CLAUDIUS_SUDO=1` |
| Privilege drop | `gosu` + `setpriv --no-new-privs` — no root parent process, setuid escalation blocked unless `CLAUDIUS_SUDO=1` |
| gVisor (optional) | `CLAUDIUS_RUNTIME=runsc` — user-space kernel, strongest isolation short of a VM |
| Docker socket | Read-only Tecnativa proxy on a per-session network; raw socket is never bind-mounted; writes opt-in via `CLAUDIUS_DOCKER_WRITE=1` |
| Managed policy | `CLAUDE.md` bind-mounted read-only at `/etc/claude-code/CLAUDE.md` — highest-precedence Claude Code config; prompt-level guardrails |
| Clipboard bridge | Per-session Unix-socket daemon brokers reads/writes; the host display server (X11/Wayland) is never exposed |

Each opt-in (`CLAUDIUS_SSH`, `CLAUDIUS_GPG`, `CLAUDIUS_SUDO`, `CLAUDIUS_DOCKER_WRITE`) expands the attack surface in a documented direction. `CLAUDIUS_DOCKER_WRITE=1` plus `CLAUDIUS_SUDO=1` is effectively host root — combine deliberately.

Outbound network is **not** filtered. See the configuration note above.

Full details — mounts, privilege drop, threat model: [docs/security.md](docs/security.md).
