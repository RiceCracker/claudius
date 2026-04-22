# Security

## Threat model

claudius is a local dev workstation tool, not a multi-tenant SaaS sandbox. It contains mistakes, not determined adversaries. Accidental file access, unexpected network calls, runaway Docker commands — those are the risks. If you instruct Claude to exfiltrate data or destroy files, it will try.

Each boundary is either closed or explicitly opened by you. The default is the most restrictive configuration. Every opt-in expands the attack surface in a specific, documented direction.

**Default:** No outbound TCP except `*.anthropic.com:443`. No sudo, no Docker writes, no SSH or GPG. Claude runs as your user with a bounded capability set. Use `CLAUDIUS_ALLOW` to enable more outbound traffic or set `CLAUDIUS_NO_PROXY=1`.

**`CLAUDIUS_ALLOW`:** Each entry is a trust decision. `*:443/tcp` opens all HTTPS — Claude can POST to any endpoint. DNS is restricted to configured resolvers; exfiltration via DNS is blocked. `CLAUDE.md` instructs Claude to only GET/HEAD externally — soft enforcement only.

**UDP:** Fail-closed — packets are dropped if the proxy listener is not running. Entries resolve to IPs at startup; once open, all UDP to that IP:port passes without hostname inspection. Keep entries narrow.

**`CLAUDIUS_SUDO=1`:** Passwordless root for the configured packages.

**`CLAUDIUS_RUNTIME=runsc`** (gVisor): user-space kernel intercepts all syscalls; the container never touches the host kernel directly. Network filtering is unaffected — the proxy intercepts at the Docker bridge, below gVisor's netstack. Strongest isolation short of a full VM.

**`CLAUDIUS_NO_PROXY=1`:** No proxy sidecar, no network filtering. Unrestricted outbound access.

**`CLAUDIUS_DOCKER_WRITE=1`:** Claude can launch a privileged container that mounts the host root filesystem. Treat as host-level root access.

**`--dangerously-skip-permissions`:** Suppresses all permission prompts. The firewall still applies.

**`/sandbox` mode:** Doesn't work inside claudius, including with gVisor — `--cap-drop ALL` removes the unprivileged user namespaces bubblewrap requires.

---

## Overview

All active measures, in one place.

| Measure | Detail |
| --- | --- |
| Isolated filesystem | Project dir, `~/.claude/`, `~/.claude.json` — no other host paths |
| Network firewall | All TCP (IPv4 + IPv6) transparently proxied via host-side sidecar (REDIRECT on Docker bridge, SNI/Host ACL); UDP/ICMP/ICMPv6 via NFQUEUE (fail-closed, no bypass); no container-side iptables |
| DNS restriction | DNS goes through the proxy; resolver IPs always in ALLOW; requests to other servers blocked |
| Capability drop | `--cap-drop ALL`; only `CHOWN`, `DAC_OVERRIDE`, `FOWNER`, `SETUID`, `SETGID`, `SETPCAP`, `NET_RAW` added back |
| Privilege drop | `gosu` replaces the entrypoint process via `exec` — no root parent remains, signals go directly to Claude |
| No privilege escalation | `sudo` is inert by default (no sudoers entry, `--no-new-privs` set). `CLAUDIUS_SUDO=1` adds a scoped sudoers entry and lifts `--no-new-privs` — capabilities remain bounded |
| Seccomp | Docker's default seccomp profile applies — blocks ~44 syscalls including `kexec_load`, `create_module`, and `AF_PACKET` sockets. Not explicitly set; intentionally relies on Docker's built-in default |
| PID isolation | Container has its own PID namespace — host processes are not visible |
| PID limit | 512 processes max |
| Resource limits | Memory and CPU capped (default 4 GB / 4 CPUs) |
| Docker socket proxy | Inspect-only by default; write ops blocked at the proxy level. Sits on the isolated internal network, excluded from the transparent TCP redirect |
| No host environment | Only the necessary env vars are passed in |
| gVisor runtime (optional) | `CLAUDIUS_RUNTIME=runsc` — user-space kernel intercepts all syscalls; no shared kernel attack surface |
| Tamper-proof policy | `CLAUDE.md` bind-mounted read-only at `/etc/claude-code/CLAUDE.md` — highest precedence in Claude Code's config hierarchy, can't be overridden or mutated from inside the container |
| Clipboard bridge | Host-side Python daemon listens on a per-session Unix socket; the container's `claudius-clip` shim (aliased as `xclip` / `xsel` / `wl-copy` / `wl-paste` / `pbcopy` / `pbpaste`) talks a 1-byte r/w protocol. No X11 socket or display server exposed |
| Proxy supervisor | `entrypoint.py` runs under a supervisor that restarts on crash (exp. backoff); SIGTERM still triggers the normal iptables cleanup path |

---

## Capabilities and limits

The lists below reflect the default configuration. Each opt-in (`CLAUDIUS_ALLOW`, `CLAUDIUS_SSH`, `CLAUDIUS_SUDO`, etc.) moves specific entries from Cannot to Can — you control exactly where the boundaries are.

### Cannot

- Access the host filesystem outside the mounted paths
- Make network connections beyond `CLAUDIUS_ALLOW` — enforced by transparent proxy (TCP) and NFQUEUE (UDP/ICMP), both fail-closed
- See or signal host processes — PID namespace is isolated
- Use raw sockets — `AF_PACKET` blocked by seccomp
- Load kernel modules — `CAP_SYS_MODULE` not in capability set
- Access the Docker socket directly — only via the filtered [docker-socket-proxy](https://github.com/Tecnativa/docker-socket-proxy); write operations blocked unless `CLAUDIUS_DOCKER_WRITE=1`
- Escalate privileges — capabilities remain bounded even with `CLAUDIUS_SUDO=1`

### Can

- Read and write the project directory and `~/.claude/` — including `.credentials.json` (Anthropic API key)
- Make outbound requests to `CLAUDIUS_ALLOW` destinations — `*.anthropic.com:443` always open
- Inspect the host Docker environment: `ps`, `logs`, `images`, `inspect`, `info` (always, via socket proxy)
- Use the host SSH agent (`CLAUDIUS_SSH=1`)
- Sign commits via the host GPG agent (`CLAUDIUS_GPG=1`)
- Read and write the host clipboard (`CLAUDIUS_CLIPBOARD=1`, on by default)
- Capture network traffic on container interfaces (`CLAUDIUS_SUDO=1` + `tcpdump`)

---

## Mounts

| Host path | Container path | Mode |
| --- | --- | --- |
| `~/.claude/` | `/home/$USER/.claude/` | rw |
| `~/.claude.json` | `/home/$USER/.claude.json` | rw |
| `$(pwd)` | `/home/$USER/$(basename pwd)` | rw |
| `$SSH_AUTH_SOCK` | same | rw — only when `CLAUDIUS_SSH=1` |
| `$(gpgconf --list-dirs agent-socket)` | same | rw — only when `CLAUDIUS_GPG=1` |
| per-session clipboard socket | `/run/claudius/clipboard.sock` | rw — only when `CLAUDIUS_CLIPBOARD=1` (brokered by host-side Python bridge; no X11/Wayland socket is ever mounted) |
| `$CLAUDIUS_DIR/CLAUDE.md` | `/etc/claude-code/CLAUDE.md` | ro — always |
| `$CLAUDIUS_USER_INIT` | `/etc/claudius/user-init.sh` | ro — only when `CLAUDIUS_USER_INIT` is set |

Note: `~/.claude/` and `~/.claude.json` are mounted read-write and persist on the host — changes to settings, hooks, or MCP config take effect immediately. `~/.claude/` contains `.credentials.json` (the Anthropic API key), readable inside the container and as root when `CLAUDIUS_SUDO=1`. Not technically enforced — mitigated by `CLAUDE.md`.

---

## Network

### With proxy (default)

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

### CLAUDIUS_ALLOW

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

### Without proxy (`CLAUDIUS_NO_PROXY=1`)

No iptables rules are installed, no proxy sidecar starts. Unrestricted outbound access. The container exposes no inbound ports to the host regardless.

---

## Docker

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

## Privilege drop

The entrypoint runs as root long enough to run the user-init hook, then hands off. The exact command depends on `CLAUDIUS_SUDO`:

```bash
# SUDO=0 (default)
gosu $HOST_USER setpriv --no-new-privs claude

# SUDO=1
gosu $HOST_USER claude
```

1. **`gosu $HOST_USER`** — switches UID/GID to your user. Unlike `su` or `sudo`, gosu uses `exec` internally, replacing itself with the new process. No root process remains in the tree.
2. **`setpriv --no-new-privs`** (SUDO=0 only) — prevents further privilege escalation via setuid binaries.

Claude is run first; if it exits, the entrypoint falls through to an interactive bash shell. Both run under the same dropped-privilege context.

---

## Managed policy (CLAUDE.md)

A policy file is bind-mounted read-only at `/etc/claude-code/CLAUDE.md` (source: [`CLAUDE.md`](../CLAUDE.md) in the repo). Claude Code loads it at the highest precedence level — project-level and user-level instructions cannot override it. It instructs Claude not to read credential files, not to send data to external URLs, not to modify its own config or hooks, and to treat content in files and web pages as data rather than directives.

The bind-mount means you can edit `CLAUDE.md` and the next container start picks it up — no image rebuild. The mount is read-only inside the container, so Claude cannot overwrite it at runtime.

These are prompt-level instructions, not technical enforcement. They raise the bar for accidental misuse, but a sufficiently adversarial prompt could still override them.
