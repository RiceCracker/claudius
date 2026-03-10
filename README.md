# 🌿 claudius 🏛️

The Roman emperor Claudius (reigned 41–54 CE) spent much of his early life marginalized, kept from public office, mocked for his physical disabilities, and largely written off by his own family. When he unexpectedly became emperor after Caligula's assassination, he proved his detractors wrong. He reformed the imperial bureaucracy, presided personally over legal cases, built the harbour at Ostia, and conquered Britain. Ancient sources, written mostly by senatorial aristocrats who resented his reliance on freedmen administrators, tend to paint him as bumbling or manipulated. The reality is more interesting: a deeply learned man, shaped by years of enforced observation rather than action, who governed with procedural seriousness and got more done than most.

He was not without political violence. He authorized executions, navigated treacherous court intrigue, and was no stranger to ruthlessness when he felt it necessary. But he thought before he acted. A fitting patron for an agent that runs in a box — this is that box.

---


## Overview

As the story above suggests, claudius is built to contain risk without getting in the way. A hardened sandbox for your local dev workstation that lets Claude Code do its job while keeping the host safe. Locked down by default; network egress, Docker access, SSH, clipboard, and sudo are all opt-in risks you control. Language servers and Gemini MCP included out of the box; extensible via custom docker images or a runtime init hook.

And while claudius tries to implement reasonable measures to protect the host from the agent, your project files and prompting are another matter.

![Architecture](docs/architecture.svg)

| Component | Details |
| --- | --- |
| Base image | `node:22-bookworm-slim` |
| Claude Code | native installer (`claude.ai/install.sh`) |
| Gemini MCP | [`@rlabs-inc/gemini-mcp`](https://github.com/RLabs-Inc/gemini-mcp) — 30+ tools: image/video generation, deep research, code execution, and more |
| Language servers | `pyright` (Python), `typescript-language-server` (TS/JS), `bash-language-server`, `vscode-langservers-extracted` (JSON/HTML/CSS/Markdown), `yaml-language-server`, `sql-language-server` |
| Shell | bash + [Starship](https://starship.rs) prompt (Imperial Rome theme) |
| Packages | git, curl, wget, vim, less, ping, mtr, jq, make, python3, pip3, sqlite3, sudo, tree, unzip, netcat, lsof, strace, tcpdump, ssh, docker CLI, gnupg, wl-clipboard, xclip |

---

## Setup

```bash
make install
```

Symlinks `claudius` into `~/.local/bin`. First run builds the image (~2 min once), after that it starts instantly.

```bash
make build      # build image (cached)
make rebuild    # rebuild without cache, updates Claude Code
make uninstall  # remove the symlink
```

**Optional: gVisor runtime**

[gVisor](https://gvisor.dev) adds a user-space kernel between the container and the host — the strongest isolation available without a full VM. Works with SSH, GPG, and clipboard forwarding.

```bash
make gvisor-install   # install runsc, register with Docker, configure daemon
make gvisor-configure # update daemon flags only (no reinstall)
make gvisor-uninstall # remove gVisor runtime
make gvisor-check     # verify installation
```

Then use it per-session with `CLAUDIUS_RUNTIME=runsc claudius ~/myproject`, or set it in `.env`.

## Usage

```bash
claudius              # mount current directory, start claude
claudius ~/my-project # mount a specific directory
claudius bash         # shell only
```

Claude starts automatically. `/exit` or Ctrl+C drops you into a shell; exiting that closes the container.

Non-interactive use works too:

```bash
claudius bash -c 'git log --oneline -5'
claudius bash -c 'claude -p "summarize this repo in one paragraph"'
```

The project directory is mounted at `/home/$USER/<dirname>`. Files you create or edit show up on the host immediately — permissions are correct because the container runs as your UID/GID.

## Configuration

Set variables in a `.env` file next to `claudius.sh` (see `.env.example`), or pass them inline:

```bash
CLAUDIUS_MEMORY=8g CLAUDIUS_CPUS=8 claudius
```

**Resources**

| Variable | Default | Description |
| --- | --- | --- |
| `CLAUDIUS_MEMORY` | `4g` | Container memory limit |
| `CLAUDIUS_CPUS` | `4` | Container CPU limit |

**Network**

| Variable | Default | Description |
| --- | --- | --- |
| `CLAUDIUS_DNS` | `1.1.1.1 1.0.0.1 8.8.8.8 8.8.4.4` | DNS resolvers (space-separated; IPv6 supported) |
| `CLAUDIUS_ALLOW` | unset | Allowed outbound destinations — see [Network](#network) |

**Features**

| Variable | Default | Description |
| --- | --- | --- |
| `CLAUDIUS_NO_PROXY` | `0` | `1` = skip proxy sidecar entirely — unrestricted outbound network |
| `CLAUDIUS_SSH` | `0` | `1` = forward SSH agent and open `*:22/tcp` |
| `CLAUDIUS_GPG` | `0` | `1` = forward GPG agent socket |
| `CLAUDIUS_CLIPBOARD` | `1` | `0` = disable clipboard forwarding (Wayland/X11) |
| `CLAUDIUS_DOCKER_WRITE` | `0` | `1` = enable docker write ops (default: inspect only) |
| `CLAUDIUS_SUDO` | `0` | `1` = enable sudo for package managers |
| `CLAUDIUS_SUDO_CMDS` | `apt apt-get pip pip3 npm` | Commands allowed via sudo when `CLAUDIUS_SUDO=1` |
| `CLAUDIUS_RUNTIME` | unset | Docker runtime: `runsc` (gVisor). Default uses runc. |

**Extending**

| Variable | Default | Description |
| --- | --- | --- |
| `CLAUDIUS_IMAGE` | `claudius` | Docker image to run — set to a custom image name to use an extended image (see [Extending](#extending)) |
| `CLAUDIUS_USER_INIT` | unset | Path to a shell script on the host — mounted read-only and run as root before Claude starts (see [Extending](#extending)) |

---

## Extending

The base image is intentionally minimal. Two ways to add your own tools:

### Custom image (recommended)

Create a `Dockerfile` that extends `claudius`, build it once, and point `CLAUDIUS_IMAGE` at it:

```bash
docker build -t claudius-go -f docker/claudius/Dockerfile.go.example .
CLAUDIUS_IMAGE=claudius-go claudius ~/my-go-project
```

Ready-made examples in `docker/claudius/`:

| File | Adds |
| --- | --- |
| `Dockerfile.go.example` | Go 1.24 (multi-stage) + `gopls` |
| `Dockerfile.flutter.example` | Flutter SDK (includes Dart + language server) + Android SDK + `flutter analyze/build apk/linux/web` |
| `Dockerfile.rust.example` | Rust stable + `rust-analyzer` |

All examples follow the same pattern — copy the file, adjust as needed, build once:

```dockerfile
FROM claudius

# add your tools here

ENV PATH="/your/tool/bin:${PATH}"
```

### Runtime init hook

Mount a shell script at `/etc/claudius/user-init.sh`. It runs as root before Claude starts — useful for lightweight per-start config like git identity or aliases. Not for installing packages (use a custom image for that).

```bash
# user-init.sh
git config --file "/home/${HOST_USER}/.gitconfig" user.email "me@example.com"
git config --file "/home/${HOST_USER}/.gitconfig" user.name "My Name"
echo "alias ll='ls -lah'" >> "/home/${HOST_USER}/.bashrc"
```

To export env vars or PATH additions to Claude, write to `/etc/claudius/user-env.sh` — the entrypoint sources it before the privilege drop:

```bash
echo 'export MY_TOKEN=xyz' >> /etc/claudius/user-env.sh
```

Pass it via `CLAUDIUS_USER_INIT`:

```bash
CLAUDIUS_USER_INIT=./user-init.sh claudius ~/my-project
# or in .env:
# CLAUDIUS_USER_INIT=/home/you/dotfiles/claudius-init.sh
```

A template is at `user-init.sh.example`.

---

## Security

### Mounts

| Host path | Container path | Mode |
| --- | --- | --- |
| `~/.claude/` | `/home/$USER/.claude/` | rw |
| `~/.claude.json` | `/home/$USER/.claude.json` | rw |
| `$(pwd)` | `/home/$USER/$(basename pwd)` | rw |
| `$SSH_AUTH_SOCK` | same | rw — only when `CLAUDIUS_SSH=1` |
| `$(gpgconf --list-dirs agent-socket)` | same | rw — only when `CLAUDIUS_GPG=1` |
| `$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY` | same | rw — only when `CLAUDIUS_CLIPBOARD=1`, Wayland |
| `/tmp/.X11-unix` | same | rw — only when `CLAUDIUS_CLIPBOARD=1`, X11 |
| `$CLAUDIUS_USER_INIT` | `/etc/claudius/user-init.sh` | ro — only when `CLAUDIUS_USER_INIT` is set |

Note: `~/.claude/` and `~/.claude.json` are mounted read-write and persist on the host — changes to settings, hooks, or MCP config take effect immediately. `~/.claude/` contains `.credentials.json` (the Anthropic API key), readable inside the container and as root when `CLAUDIUS_SUDO=1`. Not technically enforced — mitigated by `CLAUDE.md`.

---

### Network

#### Without proxy (`CLAUDIUS_NO_PROXY=1`)

The container has unrestricted outbound access. No iptables rules are installed, no proxy sidecar starts. Use this when you need full network access and accept the risk, or for testing. The container exposes no inbound ports to the host regardless.

#### With proxy (default)

All enforcement is host-side — the container has no iptables rules of its own. The proxy sidecar (`claudius-proxy`) runs with `--network host` and installs iptables/ip6tables rules on the Docker bridge before the claudius container starts. This works identically with runc and gVisor: with gVisor's netstack, packets still traverse the veth pair and bridge, so PREROUTING REDIRECT (TCP) and NFQUEUE (UDP/ICMP) intercept them the same way.

**TCP** (IPv4 + IPv6) is intercepted via PREROUTING REDIRECT. The proxy reads the TLS ClientHello SNI extension (for HTTPS) or the HTTP `Host` header to get the actual destination hostname and applies fnmatch ACL — enabling wildcards like `*.anthropic.com` without pre-resolving IPs. The proxy relays bytes without TLS termination.

**UDP and ICMP** (IPv4 + IPv6) are filtered via NFQUEUE without `--queue-bypass`. If the proxy listener is not running, the kernel drops all packets (fail-closed). UDP ACL is IP-based: non-wildcard hostnames are pre-resolved to IPs at startup.

**DNS** goes through the proxy like all other traffic. The launcher auto-adds each `CLAUDIUS_DNS` resolver to `CLAUDIUS_ALLOW` as `$r:53/udp` and `$r:53/tcp`. Queries to any other resolver are blocked.

**IPv6** is supported when Docker can create the network with `--ipv6` (Docker assigns a ULA subnet automatically). If that fails, the launcher falls back to IPv4-only and the proxy blocks all IPv6 forwarding at the bridge. The same `CLAUDIUS_ALLOW` entries cover both address families when IPv6 is active.

| Protocol | Port | Enforcement |
| --- | --- | --- |
| TCP (IPv4 + IPv6) | any | transparent REDIRECT — proxy reads SNI/Host, fnmatch ACL, relays bytes |
| UDP (IPv4 + IPv6) | any | NFQUEUE — IP-based ACL, fail-closed (no `--queue-bypass`) |
| ICMP / ICMPv6 | — | NFQUEUE — allowed if dst IP matches any rule pattern |

#### CLAUDIUS_ALLOW

Protocol suffix (`/tcp` or `/udp`) is always required. TCP entries support wildcard hostnames (`*.example.com`). UDP entries are resolved to IPs at startup — wildcard hostnames are not supported for UDP since only the destination IP is available at the NFQUEUE layer. Keep UDP entries narrow:

```bash
CLAUDIUS_ALLOW="
  *:443/tcp                          # all HTTPS
  *:80/tcp                           # all HTTP
  *.npmjs.org:443/tcp                # subdomain wildcard
  api.github.com:443/tcp             # exact domain
  1.2.3.4:5432/tcp                   # IP address
  gameserver.example.com:27015/udp   # UDP
  *:123/udp                          # UDP, any host
" claudius
```

Always allowed regardless of `CLAUDIUS_ALLOW` (hardcoded in the launcher):

- `*.anthropic.com:443/tcp` — Claude Code requires it
- DNS resolvers from `CLAUDIUS_DNS` on port 53 (tcp + udp)
- `*:22/tcp` — only when `CLAUDIUS_SSH=1`

`pypi.org:443/tcp` and `files.pythonhosted.org:443/tcp` are included in `.env.example` but not hardcoded — add them to `CLAUDIUS_ALLOW` when you need pip.

To watch proxy verdicts in real time:

```bash
docker logs -f $(docker ps -q --filter name=claudius-proxy)
# ALLOW tcp api.anthropic.com:443
# BLOCK tcp registry.npmjs.org:443
# ALLOW udp 8.8.8.8:53
```

---

### Docker

claudius runs a [docker-socket-proxy](https://github.com/Tecnativa/docker-socket-proxy) sidecar on an isolated internal network. The Docker socket itself is never mounted into the container and Claude reaches it only through the filtered proxy.

This lets Claude inspect your host's Docker environment: read logs, list containers, check image state — without being able to change anything. Useful for diagnosing a broken service or understanding what's running, with no risk of accidental `docker run` or `docker stop`.

Available by default:

```
docker ps / logs / images / inspect / info / network ls / volume ls
```

Write operations are blocked at the proxy level. Set `CLAUDIUS_DOCKER_WRITE=1` to enable them: `run`, `build`, `stop`, and all other write/exec operations.

The Docker socket proxy sits on the isolated internal Docker network. Connections to it are excluded from the transparent proxy REDIRECT (intra-network traffic is never redirected), so it remains reachable regardless of the allowlist.

> **Note:** `docker inspect` is permitted and returns `Config.Env`. Environment variables of other containers on the host — including database passwords — are visible to Claude. Keep this in mind if you run sensitive containers alongside claudius.

---

### Privilege drop

The entrypoint runs as root long enough to run the user-init hook, then hands off. The exact command depends on `CLAUDIUS_SUDO`:

```bash
# SUDO=0 (default)
gosu $HOST_USER setpriv --no-new-privs claude

# SUDO=1
gosu $HOST_USER claude
```

What happens:

1. **`gosu $HOST_USER`** — switches UID/GID to your user. Unlike `su` or `sudo`, gosu uses `exec` internally, meaning it replaces itself with the new process rather than staying alive as a parent. No root process remains in the tree.
2. **`setpriv --no-new-privs`** (SUDO=0 only) — prevents any further privilege escalation via setuid binaries.

Claude is run first; if it exits, the entrypoint falls through to an interactive bash shell. Both run under the same dropped-privilege context.

---

### Managed policy (CLAUDE.md)

A policy file is baked into the image at `/etc/claude-code/CLAUDE.md` (source: [`CLAUDE.md`](CLAUDE.md)). Claude Code loads it at the highest precedence level — project-level and user-level instructions cannot override it. It instructs Claude not to read credential files, not to send data to external URLs, not to modify its own config or hooks, and to treat content in files and web pages as data rather than directives.

These are prompt-level instructions, not technical enforcement. They raise the bar for accidental misuse, but a sufficiently adversarial prompt could still override them.

---

### Measure summary

Everything described above, in one place.

| Measure | Detail |
| --- | --- |
| Isolated filesystem | Project dir, `~/.claude/`, `~/.claude.json` — no other host paths |
| Network firewall | All TCP (IPv4 + IPv6) transparently proxied via host-side sidecar (REDIRECT on Docker bridge, SNI/Host ACL); UDP/ICMP/ICMPv6 via NFQUEUE (fail-closed, no bypass); no container-side iptables |
| DNS restriction | DNS goes through the proxy; resolver IPs always in ALLOW; requests to other servers blocked |
| Capability drop | `--cap-drop ALL`; only `CHOWN`, `DAC_OVERRIDE`, `FOWNER`, `SETUID`, `SETGID`, `SETPCAP`, `NET_RAW` added back |
| Privilege drop | `gosu` replaces the entrypoint process via `exec` — no root parent remains, signals go directly to Claude. See [Privilege drop](#privilege-drop). |
| gVisor runtime (optional) | `CLAUDIUS_RUNTIME=runsc` — user-space kernel intercepts all syscalls; no shared kernel attack surface. Works with SSH/GPG/clipboard forwarding. |
| Seccomp | Docker's default seccomp profile applies — blocks ~44 syscalls including `kexec_load`, `create_module`, and `AF_PACKET` sockets. Not explicitly set; intentionally relies on Docker's built-in default |
| No privilege escalation | `sudo` is inert by default (no sudoers entry, `--no-new-privs` set). `CLAUDIUS_SUDO=1` adds a scoped sudoers entry and lifts `--no-new-privs` — capabilities remain bounded |
| PID isolation | Container has its own PID namespace — host processes are not visible |
| PID limit | 512 processes max |
| Resource limits | Memory and CPU capped (default 4 GB / 4 CPUs) |
| Docker socket proxy | Inspect-only by default; write ops blocked at the proxy level. Sits on the isolated internal network, excluded from the transparent TCP redirect |
| No host environment | Only the necessary env vars are passed in |
| Tamper-proof policy | `CLAUDE.md` at `/etc/claude-code/CLAUDE.md` — highest precedence in Claude Code's config hierarchy, can't be overridden by project or user instructions |

These measures harden the sandbox. What they cannot do is protect against what you explicitly ask Claude to do — or against the risks that come with each opt-in. That's what the threat model is for.

---

### Capabilities and limits

The lists below reflect the default configuration. Each opt-in (`CLAUDIUS_ALLOW`, `CLAUDIUS_SSH`, `CLAUDIUS_SUDO`, etc.) moves specific entries from Cannot to Can — you control exactly where the boundaries are.

#### Cannot

- Access the host filesystem outside the mounted paths
- Make network connections beyond `CLAUDIUS_ALLOW` — enforced by transparent proxy (TCP) and NFQUEUE (UDP/ICMP), both fail-closed
- See or signal host processes — PID namespace is isolated
- Use raw sockets — `AF_PACKET` blocked by seccomp
- Load kernel modules — `CAP_SYS_MODULE` not in capability set
- Access the Docker socket directly — only via the filtered [docker-socket-proxy](https://github.com/Tecnativa/docker-socket-proxy); write operations blocked unless `CLAUDIUS_DOCKER_WRITE=1`
- Escalate privileges — capabilities remain bounded even with `CLAUDIUS_SUDO=1`

#### Can

- Read and write the project directory and `~/.claude/` — including `.credentials.json` (Anthropic API key)
- Make outbound requests to `CLAUDIUS_ALLOW` destinations — `*.anthropic.com:443` always open
- Inspect the host Docker environment: `ps`, `logs`, `images`, `inspect`, `info` (always, via socket proxy)
- Use the host SSH agent (`CLAUDIUS_SSH=1`)
- Sign commits via the host GPG agent (`CLAUDIUS_GPG=1`)
- Read and write the host clipboard (`CLAUDIUS_CLIPBOARD=1`, on by default)
- Capture network traffic on container interfaces (`CLAUDIUS_SUDO=1` + `tcpdump`)

---

### Threat model

claudius is a local dev workstation tool, not a multi-tenant SaaS sandbox. It contains mistakes, not determined adversaries. Even though, accidental file access, unexpected network calls, runaway Docker commands are covered. If you instruct Claude to exfiltrate data or destroy files, it will try.

Each boundary is either closed or explicitly opened by you. The default is the most restrictive configuration. Every opt-in expands the attack surface in a specific, documented direction.

**Default:** No outbound TCP except `*.anthropic.com:443`. No sudo, no Docker writes, no SSH or GPG. Claude runs as your user with a bounded capability set. Use `CLAUDIUS_ALLOW` to enable more outbound traffic or set `CLAUDIUS_NO_PROXY=1`.

**`CLAUDIUS_ALLOW`:** Each entry is a trust decision. `*:443/tcp` opens all HTTPS — Claude can POST to any endpoint. DNS is restricted to configured resolvers; exfiltration via DNS is blocked. `CLAUDE.md` instructs Claude to only GET/HEAD externally — soft enforcement only.

**UDP:** Fail-closed — packets are dropped if the proxy listener is not running. Entries resolve to IPs at startup; once open, all UDP to that IP:port passes without hostname inspection. Keep entries narrow.

**`CLAUDIUS_SUDO=1`:** Passwordless root for the configured packages. Never combine with `CLAUDIUS_DOCKER_WRITE=1` — together they are equivalent to host root.

**`CLAUDIUS_RUNTIME=runsc`** (gVisor): user-space kernel intercepts all syscalls; the container never touches the host kernel directly. Network filtering is unaffected — the proxy intercepts at the Docker bridge, below gVisor's netstack. Strongest isolation short of a full VM.

**`CLAUDIUS_NO_PROXY=1`:** No proxy sidecar, no network filtering. Unrestricted outbound access.

**`CLAUDIUS_DOCKER_WRITE=1`:** Claude can launch a privileged container that mounts the host root filesystem. Treat as host-level access.

**`--dangerously-skip-permissions`:** Suppresses all permission prompts. The firewall still applies.

**`/sandbox` mode:** Doesn't work inside claudius, including with gVisor — `--cap-drop ALL` removes the unprivileged user namespaces bubblewrap requires.
