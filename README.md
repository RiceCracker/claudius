# 🌿 claudius 🏛️

The Roman emperor Claudius (reigned 41–54 CE) spent much of his early life marginalized, kept from public office, mocked for his physical disabilities, and largely written off by his own family. When he unexpectedly became emperor after Caligula's assassination, he proved his detractors wrong. He reformed the imperial bureaucracy, presided personally over legal cases, built the harbour at Ostia, and conquered Britain. Ancient sources, written mostly by senatorial aristocrats who resented his reliance on freedmen administrators, tend to paint him as bumbling or manipulated. The reality is more interesting: a deeply learned man, shaped by years of enforced observation rather than action, who governed with procedural seriousness and got more done than most.

He was not without political violence. He authorized executions, navigated treacherous court intrigue, and was no stranger to ruthlessness when he felt it necessary. But he thought before he acted. A fitting patron for an agent that runs in a box — this is that box.

---


## Overview

As the story above suggests, claudius is built to contain risk without getting in the way. A hardened sandbox that lets Claude Code do its job while keeping the host safe. Locked down by default; network egress, Docker access, SSH, clipboard, and sudo are all opt-in risks you control. Language servers and Gemini MCP included out of the box; extensible via custom docker images or a runtime init hook. It protects the host from the agent. Your project files are another matter.

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

Symlinks `claudius` into `~/.local/bin`. First run builds the image (~2 min), after that it starts instantly.

```bash
make build      # build image (cached)
make rebuild    # rebuild without cache, updates Claude Code
make uninstall  # remove the symlink
```

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
| `CLAUDIUS_FIREWALL_VERBOSE` | `0` | `1` = log every firewall verdict (iptables LOG target) |

**Features**

| Variable | Default | Description |
| --- | --- | --- |
| `CLAUDIUS_SSH` | `0` | `1` = forward SSH agent and open TCP/22 |
| `CLAUDIUS_GPG` | `0` | `1` = forward GPG agent socket |
| `CLAUDIUS_CLIPBOARD` | `1` | `0` = disable clipboard forwarding (Wayland/X11) |
| `CLAUDIUS_DOCKER_WRITE` | `0` | `1` = enable docker write ops: run/build/stop/exec/kill/commit (default: inspect only) |
| `CLAUDIUS_SUDO` | `0` | `1` = enable sudo for package managers |
| `CLAUDIUS_SUDO_CMDS` | `apt apt-get pip pip3 npm` | Commands allowed via sudo when `CLAUDIUS_SUDO=1` |

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
| `$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY` | same | ro — only when `CLAUDIUS_CLIPBOARD=1`, Wayland |
| `/tmp/.X11-unix` | same | ro — only when `CLAUDIUS_CLIPBOARD=1`, X11 |
| `$CLAUDIUS_USER_INIT` | `/etc/claudius/user-init.sh` | ro — only when `CLAUDIUS_USER_INIT` is set |

Note: `~/.claude/` and `~/.claude.json` are mounted read-write and persist on the host — changes to settings, hooks, or MCP config take effect immediately. `~/.claude/` contains `.credentials.json` (the Anthropic API key), readable inside the container and as root when `CLAUDIUS_SUDO=1`. Not technically enforced — mitigated by `CLAUDE.md`.

---

### Network

iptables rules apply to the OUTPUT chain only (egress filtering). The container exposes no ports to the host — inbound traffic only comes from the two internal sidecars (Envoy proxy, Docker socket proxy).

All outbound TCP — including to the Docker socket proxy — routes through Envoy. The Docker proxy is reachable by hostname only; direct IP connections are intercepted by Envoy and rejected.

| Protocol | Port | Condition |
| --- | --- | --- |
| ICMP / ICMPv6 | — | always |
| UDP/TCP | 53 | DNS to configured resolvers only |
| TCP | 22 | only when `CLAUDIUS_SSH=1` |
| TCP | any | `CLAUDIUS_ALLOW` entries via Envoy |
| UDP | any | `CLAUDIUS_ALLOW` entries via iptables |

#### CLAUDIUS_ALLOW

All outbound TCP goes through an Envoy sidecar. The reason: iptables operates at the IP layer and can only filter by address — it has no concept of hostnames or wildcards like `*.anthropic.com`. Resolving domains to IPs at startup would be unreliable; CDN-backed services rotate through hundreds of addresses and the mapping changes constantly. Envoy operates at L7, where it can inspect the `CONNECT` target (for HTTPS) or the `Host` header (for HTTP) — the actual hostname, not the IP. iptables just redirects all outbound TCP to Envoy via DNAT; Envoy does the real filtering. Destinations not in the list get HTTP 403.

UDP cannot be proxied this way, so UDP entries are resolved to IPs at startup and added to iptables directly — keep UDP entries narrow. Protocol suffix is always required:

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

Port 80 uses Envoy's HTTP forward proxy mode; everything else uses CONNECT tunneling. Both are transparent to applications.

`*.anthropic.com:443` and `pypi.org:443` are always allowed regardless of `CLAUDIUS_ALLOW` — hardcoded in the launcher.

---

### Docker

claudius runs a [docker-socket-proxy](https://github.com/Tecnativa/docker-socket-proxy) sidecar on an isolated internal network. The Docker socket itself is never mounted into the container.

Available by default:

```
docker ps / logs / images / inspect / info / network ls / volume ls
```

All write ops are blocked at the proxy level by default. Set `CLAUDIUS_DOCKER_WRITE=1` to enable all POST endpoints: `run`, `build`, `stop`, `exec`, `kill`, `commit`.

The proxy is reachable by hostname through Envoy only — direct IP access is blocked. This prevents bypassing the method filter by connecting to the proxy IP with the system proxy disabled.

Note: `docker inspect` is permitted and returns `Config.Env` — environment variables of other containers on the host (e.g. database passwords) are visible. Keep this in mind if you run sensitive containers alongside claudius.

---

### Privilege drop

The entrypoint runs as root long enough to set up iptables and run the user-init hook, then hands off. The exact command depends on `CLAUDIUS_SUDO`:

```bash
# SUDO=0 (default)
setpriv --bounding-set=-net_admin gosu $HOST_USER setpriv --no-new-privs claude

# SUDO=1
setpriv --bounding-set=-net_admin gosu $HOST_USER claude
```

What happens:

1. **`setpriv --bounding-set=-net_admin`** — removes `NET_ADMIN` from the capability bounding set. This is a one-way door: no process in this container can ever re-acquire it, even if it regains root.
2. **`gosu $HOST_USER`** — switches UID/GID to your user. Unlike `su` or `sudo`, gosu uses `exec` internally, meaning it replaces itself with the new process rather than staying alive as a parent. No root process remains in the tree.
3. **`setpriv --no-new-privs`** (SUDO=0 only) — prevents any further privilege escalation via setuid binaries.

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
| Network firewall | iptables OUTPUT defaults to DROP; all TCP goes through Envoy; only `CLAUDIUS_ALLOW` entries pass |
| DNS restriction | DNS only reaches resolvers listed in `CLAUDIUS_DNS` |
| Capability drop | `--cap-drop ALL`; only `CHOWN`, `DAC_OVERRIDE`, `FOWNER`, `SETUID`, `SETGID`, `SETPCAP`, `NET_ADMIN`, `NET_RAW` added back |
| NET_ADMIN removal | Dropped from the process bounding set after firewall init — no child process can re-acquire it |
| Privilege drop | `gosu` replaces the entrypoint process via `exec` — no root parent remains, signals go directly to Claude. See [Privilege drop](#privilege-drop). |
| Seccomp | Docker's default seccomp profile applies — blocks ~44 syscalls including `kexec_load`, `create_module`, and `AF_PACKET` sockets. Not explicitly set; intentionally relies on Docker's built-in default |
| No privilege escalation | `sudo` is inert by default (no sudoers entry, `--no-new-privs` set). `CLAUDIUS_SUDO=1` adds a scoped sudoers entry and lifts `--no-new-privs` — capabilities remain bounded |
| PID isolation | Container has its own PID namespace — host processes are not visible |
| PID limit | 512 processes max |
| Resource limits | Memory and CPU capped (default 4 GB / 4 CPUs) |
| Docker socket proxy | Inspect-only by default; write ops blocked at the proxy level. Traffic routes through Envoy — the proxy IP is not reachable directly, only its hostname |
| No host environment | Only the necessary env vars are passed in |
| Tamper-proof policy | `CLAUDE.md` at `/etc/claude-code/CLAUDE.md` — highest precedence in Claude Code's config hierarchy, can't be overridden by project or user instructions |

These measures harden the sandbox. What they cannot do is protect against what you explicitly ask Claude to do — or against the risks that come with each opt-in. That's what the threat model is for.

---

### Capabilities and limits

#### Cannot

- Access the host filesystem outside the mounted paths
- Make network connections beyond `CLAUDIUS_ALLOW` — TCP enforced by Envoy, UDP by iptables; only DNS to configured resolvers, ICMP, and `*.anthropic.com:443` always pass
- Persist anything outside the mounted directories
- See or signal host processes — PID namespace is isolated
- Use raw ethernet sockets — `AF_PACKET` blocked by seccomp even with `CAP_NET_RAW`
- Load kernel modules — `CAP_SYS_MODULE` not in capability set
- Access the Docker socket directly — only via the filtered [docker-socket-proxy](https://github.com/Tecnativa/docker-socket-proxy)
- Escalate privileges beyond what `CLAUDIUS_SUDO=1` permits (capabilities remain bounded)
- Run Docker write operations unless `CLAUDIUS_DOCKER_WRITE=1`

#### Can

- Read and write the project directory
- Read and write `~/.claude/` and `~/.claude.json`, including `.credentials.json` (Anthropic API key)
- Make outbound requests to `CLAUDIUS_ALLOW` destinations (plus `*.anthropic.com:443`, always open)
- Use the host SSH agent (if `CLAUDIUS_SSH=1`)
- Sign commits via the host GPG agent (if `CLAUDIUS_GPG=1`)
- Read and write the host clipboard (if `CLAUDIUS_CLIPBOARD=1`, on by default)
- Capture network traffic on container interfaces (if `CLAUDIUS_SUDO=1` and `tcpdump` in `CLAUDIUS_SUDO_CMDS`)

---

### Threat model

claudius is built to contain mistakes, not to stop a determined adversary. Accidental file access outside the project, unexpected network calls, runaway Docker commands — those are covered. If you instruct Claude to exfiltrate data or destroy files, it will try.

**Default (no options set):** No outbound TCP except `*.anthropic.com:443` and `pypi.org:443`. No sudo. No Docker writes. No SSH or GPG. Claude runs as your user with a bounded capability set and no way back to root. This is the safest configuration.

**`CLAUDIUS_ALLOW`:** Each entry is a trust decision. Hard enforcement via Envoy for TCP, iptables for UDP — not convention. `*:443/tcp` opens all HTTPS, which means Claude can POST to any endpoint. DNS exfiltration is partially mitigated by locking resolvers to known IPs. `CLAUDE.md` instructs Claude to only GET/HEAD externally — soft enforcement, but it raises the bar.

**UDP:** Bypasses Envoy entirely. Entries are resolved at startup; iptables rules cover both IPv4 and IPv6. Once a destination IP:port is open, all UDP to it passes without per-packet inspection. Keep entries narrow — `*:port/udp` opens that port to the whole internet.

**`CLAUDIUS_SUDO=1`:** Gives Claude passwordless root for the configured package managers. Root can read any mounted path, install software, and modify the environment. Capabilities remain bounded — root cannot regain `NET_ADMIN`. Never combine with `CLAUDIUS_DOCKER_WRITE=1`; together they are equivalent to host root.

**`CLAUDIUS_DOCKER_WRITE=1`:** Enables all Docker write operations via the socket proxy. Claude can launch a privileged container that mounts the host root filesystem and escape the sandbox entirely. Treat this as host-level access.

**`--dangerously-skip-permissions`:** Suppresses all permission prompts. The firewall still applies, but Claude acts without asking. Useful for automated pipelines; know what you're enabling.

**`/sandbox` mode:** Doesn't work inside claudius. The container runs `--cap-drop ALL`, which removes the unprivileged user namespaces that bubblewrap requires. The container itself is the isolation layer.

**You decide what you ask it to do.**
