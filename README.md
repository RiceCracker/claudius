# 🌿 claudius 🏛️

The Roman emperor Claudius (reigned 41–54 CE) spent much of his early life marginalized – kept from public office, mocked for his physical disabilities, and largely written off by his own family. When he unexpectedly became emperor after Caligula's assassination, he proved his detractors wrong. He reformed the imperial bureaucracy, presided personally over legal cases, built the harbour at Ostia, and conquered Britain. Ancient sources, written mostly by senatorial aristocrats who resented his reliance on freedmen administrators, tend to paint him as bumbling or manipulated. The reality is more interesting: a deeply learned man, shaped by years of enforced observation rather than action, who governed with procedural seriousness and got more done than most.

He was not without political violence – he authorized executions, navigated treacherous court intrigue, and was no stranger to ruthlessness when he felt it necessary. But he thought before he acted. A fitting patron for an agent that runs in a box – this is that box.

Runs Claude Code in a Docker container. Credentials, skills, hooks, memory and MCP config are passed through from the host, so the full Claude Code experience works inside.

## Requirements

- Docker
- `~/.claude/` and `~/.claude.json` – Claude Code itself doesn't need to be installed on the host

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

The project directory is mounted at `/home/$USER/<dirname>`. Files you create or edit show up on the host immediately – permissions are correct because the container runs as your UID/GID.

### Configuration

| Variable | Default | Description |
|---|---|---|
| `CLAUDIUS_MEMORY` | `4g` | Container memory limit |
| `CLAUDIUS_CPUS` | `4` | Container CPU limit |
| `CLAUDIUS_DNS` | `1.1.1.1 1.0.0.1 8.8.8.8 8.8.4.4` | DNS resolvers (space-separated; IPv6 supported) |
| `CLAUDIUS_ALLOW` | unset | Allowed outbound destinations. Format: `host:port/tcp` or `host:port/udp`. All TCP routes through Envoy; unlisted destinations get HTTP 403. UDP entries are resolved at startup and opened via iptables. Wildcards: `*:443/tcp` (any host), `*.npmjs.org:443/tcp` (subdomain). |
| `CLAUDIUS_SSH` | `0` | `1` = forward SSH agent and open TCP/22 |
| `CLAUDIUS_GPG` | `0` | `1` = forward GPG agent socket |
| `CLAUDIUS_DOCKER_WRITE` | `0` | `1` = enable docker run/build/stop (default: inspect only) |
| `CLAUDIUS_CLIPBOARD` | `1` | `0` = disable clipboard forwarding (Wayland/X11) |
| `CLAUDIUS_SUDO` | `0` | `1` = enable sudo for package managers |
| `CLAUDIUS_SUDO_CMDS` | `apt apt-get pip pip3 npm` | Commands allowed via sudo when `CLAUDIUS_SUDO=1` |

Put these in a `.env` file next to `claudius.sh` (see `.env.example`), or pass inline:

```bash
CLAUDIUS_MEMORY=8g CLAUDIUS_CPUS=8 claudius
```

## What's inside

| Thing | Detail |
|---|---|
| Base image | `node:20-bookworm-slim` |
| Claude Code | native installer (`claude.ai/install.sh`) |
| Shell | bash + [Starship](https://starship.rs) prompt (Imperial Rome theme) |
| Packages | git, curl, wget, vim, less, ping, mtr, jq, make, python3, pip3, sqlite3, sudo, tree, unzip, netcat, lsof, strace, docker CLI, gnupg, wl-clipboard, xclip |

## Security

### Measures

| Measure | Detail |
|---|---|
| Isolated filesystem | Only three host paths are mounted: project dir, `~/.claude/`, `~/.claude.json` |
| Network firewall | iptables/ip6tables OUTPUT defaults to DROP; only DNS, ICMP, and `CLAUDIUS_ALLOW` entries pass; all TCP goes through Envoy |
| DNS restriction | DNS only reaches resolvers in `CLAUDIUS_DNS` |
| Capability drop | `--cap-drop ALL`; only CHOWN, DAC_OVERRIDE, FOWNER, SETUID, SETGID, SETPCAP, NET_ADMIN, NET_RAW added back |
| NET_ADMIN removal | Dropped from the process bounding set after firewall init – no child process can re-acquire it |
| No privilege escalation | `sudo` is installed but inert by default: no sudoers entry, `no-new-privs` set. `CLAUDIUS_SUDO=1` writes a scoped sudoers entry and lifts `no-new-privs` – capabilities are still bounded |
| PID limit | 512 processes max |
| Resource limits | Memory and CPU capped (default 4 GB / 4 CPUs) |
| Docker socket proxy | Inspect only by default; write ops blocked at API level. `CLAUDIUS_DOCKER_WRITE=1` to enable run/build/stop |
| No host environment | Only the necessary env vars are passed in |
| Tamper-proof guardrails | `CLAUDE.md` installed at `/etc/claude-code/CLAUDE.md` – highest precedence in Claude Code's config hierarchy, can't be overridden by project or user instructions |

### CLAUDE.md

A managed policy file is installed at `/etc/claude-code/CLAUDE.md` inside the image. Claude Code loads it at the highest precedence level – it can't be overridden by project-level or user-level instructions.

Key rules it enforces:

- Don't read `~/.claude.json`, SSH keys, cloud credentials, or `.env` files
- Don't build tools that search for credentials or high-entropy strings
- Don't send file contents or API keys to external URLs
- Only GET/HEAD requests to external URLs – no POSTing data outward
- Only work inside the mounted project directory
- Don't modify `~/.claude/` config, hooks, or MCP settings unless asked
- Docker access is read-only by default; sudo is scoped to package managers

These are prompt-level instructions, not technical enforcement. They raise the bar for accidental or instruction-following misuse, but a sufficiently adversarial prompt could still override them.

### Network

iptables and ip6tables rules are applied to the OUTPUT chain only – this is egress filtering. Ingress is not restricted, but the container exposes no ports to the host, so the only inbound traffic comes from the two sidecars on the internal Docker network (Envoy proxy, Docker socket proxy).

What passes outbound:

| Protocol | Port | Condition |
|---|---|---|
| ICMP / ICMPv6 | – | always |
| UDP/TCP | 53 | DNS to configured resolvers only |
| TCP | 22 | only when `CLAUDIUS_SSH=1` |
| TCP | any | `CLAUDIUS_ALLOW` entries via Envoy |
| UDP | any | `CLAUDIUS_ALLOW` entries via iptables |

#### `CLAUDIUS_ALLOW`

All outbound TCP goes through an Envoy sidecar. Destinations not in the list get HTTP 403. UDP entries are resolved at startup and added to iptables directly. Protocol suffix is always required:

```bash
CLAUDIUS_ALLOW="
  *:443/tcp                          # all HTTPS
  *:80/tcp                           # all HTTP
  *.npmjs.org:443/tcp                # subdomain wildcard
  api.github.com:443/tcp             # exact domain
  1.2.3.4:5432/tcp                   # IP
  gameserver.example.com:27015/udp   # UDP
  *:123/udp                          # UDP, any host
" claudius
```

Port 80 uses Envoy's HTTP forward proxy mode; everything else uses CONNECT tunneling. Both are transparent to applications.

`*.anthropic.com:443` is always allowed regardless of `CLAUDIUS_ALLOW` – Claude Code needs it to function.

### Mounts

| Host | Container | Mode |
|---|---|---|
| `~/.claude/` | `/home/$USER/.claude/` | rw – settings, skills, hooks, memory, MCP, history |
| `~/.claude.json` | `/home/$USER/.claude.json` | rw |
| `$(pwd)` | `/home/$USER/$(basename pwd)` | rw |
| `$SSH_AUTH_SOCK` | same | rw – only when `CLAUDIUS_SSH=1` |
| `$(gpgconf --list-dirs agent-socket)` | same | rw – only when `CLAUDIUS_GPG=1` |
| `$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY` | same | ro – only when `CLAUDIUS_CLIPBOARD=1`, Wayland |
| `/tmp/.X11-unix` | same | ro – only when `CLAUDIUS_CLIPBOARD=1`, X11 |

### Docker visibility

claudius runs a [docker-socket-proxy](https://github.com/Tecnativa/docker-socket-proxy) sidecar on an isolated internal network. The Docker socket itself is never mounted into the container.

Available by default:

```
docker ps / logs / images / inspect / info / network ls / volume ls
```

`exec`, `run`, `build`, `commit`, `kill` and other write ops are blocked at the proxy level. Set `CLAUDIUS_DOCKER_WRITE=1` to enable `run`, `build`, and `stop`.

### What the container can and cannot do

**Cannot:**
- Access the host filesystem outside the mounted paths
- Make network connections beyond `CLAUDIUS_ALLOW`
- Persist anything outside the mounted directories
- Escalate privileges (unless `CLAUDIUS_SUDO=1`, scoped to package managers)
- Run Docker write operations (unless `CLAUDIUS_DOCKER_WRITE=1`)

**Can:**
- Read and write the project directory
- Read and write `~/.claude/` and `~/.claude.json`
- Make outbound requests to `CLAUDIUS_ALLOW` destinations
- Use the host SSH agent (if `CLAUDIUS_SSH=1`)
- Sign commits via the host GPG agent (if `CLAUDIUS_GPG=1`)
- Read and write the host clipboard (if `CLAUDIUS_CLIPBOARD=1`, on by default)

### Threat model

claudius is built to contain mistakes, not to stop a determined adversary. Accidental file access outside the project, unexpected network calls, runaway Docker commands – those are covered. If you tell Claude to exfiltrate something, it will try.

**No `CLAUDIUS_ALLOW`:** Envoy blocks all TCP (empty ACL tables → HTTP 403 for everything). No outbound access except DNS and ICMP. Good for fully offline runs.

**With `CLAUDIUS_ALLOW`:** Only listed destinations pass. Hard enforcement via Envoy, not convention. `*:443/tcp` opens all HTTPS – the remaining risk is exfiltration, since Claude can POST to any endpoint. DNS exfiltration is partially mitigated by locking resolvers to known IPs. `CLAUDE.md` instructs Claude to only GET/HEAD externally and never POST data out – soft, but it raises the bar.

**UDP:** Bypasses Envoy entirely. Entries are resolved at startup; both IPv4 and IPv6 rules are written. Once a destination IP:port is open, all UDP to it passes – there's no per-packet inspection. Keep UDP entries narrow. `*:port/udp` opens that port to the whole internet.

**`--dangerously-skip-permissions`:** The shell inside the container lets you relaunch Claude with `claude --dangerously-skip-permissions`, which suppresses all permission prompts across every tool. The firewall still applies, but Claude will act without asking. Useful for automated runs; just know what you're enabling.

**`/sandbox` mode:** `/sandbox` would add OS-level isolation via bubblewrap, but it doesn't work here. The container runs `--cap-drop ALL`, which removes the unprivileged user namespaces that bubblewrap requires. That's intentional – the container itself is the isolation layer.

Write access to `~/.claude/` and `~/.claude.json` is the main residual risk in all modes. Changes there persist on the host. Not technically enforced – mitigated by `CLAUDE.md`.

**You decide what you ask it to do.**
