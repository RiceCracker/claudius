# Security

## Threat model

claudius is a local dev workstation tool, not a multi-tenant SaaS sandbox. It contains mistakes, not determined adversaries. Accidental file access, unexpected network calls, runaway Docker commands — those are the risks. If you instruct Claude to exfiltrate data or destroy files, it will try.

Each boundary is either closed or explicitly opened by you. The default is the most restrictive configuration. Every opt-in expands the attack surface in a specific, documented direction.

**Default:** Unrestricted outbound network. No sudo, no Docker writes, no SSH or GPG. Claude runs as your user with a bounded capability set inside an isolated Docker network. The Docker socket is exposed read-only via a sidecar proxy.

**Network:** No firewall, no allow-list. The container reaches the internet through Docker's bridge — same as any other container. If you need filtering, do it at the host (firewall, VPN) or at the runtime layer.

**`CLAUDIUS_SUDO=1`:** Passwordless root for the configured packages.

**`CLAUDIUS_RUNTIME=runsc`** (gVisor): user-space kernel intercepts all syscalls; the container never touches the host kernel directly. Strongest isolation short of a full VM.

**`CLAUDIUS_DOCKER_WRITE=1`:** Claude can launch a privileged container that mounts the host root filesystem. Treat as host-level root access.

**`--dangerously-skip-permissions`:** Suppresses all permission prompts.

**`/sandbox` mode:** Doesn't work inside claudius, including with gVisor — `--cap-drop ALL` removes the unprivileged user namespaces bubblewrap requires.

---

## Overview

All active measures, in one place.

| Measure | Detail |
| --- | --- |
| Isolated filesystem | Project dir, `~/.claude/`, `~/.claude.json` — no other host paths |
| Capability drop | `--cap-drop ALL`; only `CHOWN`, `DAC_OVERRIDE`, `FOWNER`, `SETUID`, `SETGID`, `SETPCAP`, `NET_RAW` added back |
| Privilege drop | `gosu` replaces the entrypoint process via `exec` — no root parent remains, signals go directly to Claude |
| No privilege escalation | `sudo` is inert by default (no sudoers entry, `--no-new-privs` set). `CLAUDIUS_SUDO=1` adds a scoped sudoers entry and lifts `--no-new-privs` — capabilities remain bounded |
| Seccomp | Docker's default seccomp profile applies — blocks ~44 syscalls including `kexec_load`, `create_module`, and `AF_PACKET` sockets. Not explicitly set; intentionally relies on Docker's built-in default |
| PID isolation | Container has its own PID namespace — host processes are not visible |
| PID limit | 512 processes max |
| Resource limits | Memory and CPU capped (default 4 GB / 4 CPUs) |
| Docker socket proxy | Inspect-only by default; write ops blocked at the proxy level. Sits on the isolated internal Docker network, never exposes the raw socket to the container |
| No host environment | Only the necessary env vars are passed in |
| gVisor runtime (optional) | `CLAUDIUS_RUNTIME=runsc` — user-space kernel intercepts all syscalls; no shared kernel attack surface |
| Tamper-proof policy | `CLAUDE.md` bind-mounted read-only at `/etc/claude-code/CLAUDE.md` — highest precedence in Claude Code's config hierarchy, can't be overridden or mutated from inside the container |
| Clipboard bridge | Host-side Python daemon listens on a per-session Unix socket; the container's `claudius-clip` shim (aliased as `xclip` / `xsel` / `wl-copy` / `wl-paste` / `pbcopy` / `pbpaste`) talks a 1-byte r/w protocol. No X11 socket or display server exposed |

---

## Capabilities and limits

The lists below reflect the default configuration. Each opt-in (`CLAUDIUS_SSH`, `CLAUDIUS_SUDO`, `CLAUDIUS_DOCKER_WRITE`, etc.) moves specific entries from Cannot to Can — you control exactly where the boundaries are.

### Cannot

- Access the host filesystem outside the mounted paths
- See or signal host processes — PID namespace is isolated
- Use raw sockets — `AF_PACKET` blocked by seccomp
- Load kernel modules — `CAP_SYS_MODULE` not in capability set
- Access the Docker socket directly — only via the filtered [docker-socket-proxy](https://github.com/Tecnativa/docker-socket-proxy); write operations blocked unless `CLAUDIUS_DOCKER_WRITE=1`
- Escalate privileges — capabilities remain bounded even with `CLAUDIUS_SUDO=1`

### Can

- Read and write the project directory and `~/.claude/` — including `.credentials.json` (Anthropic API key)
- Make outbound network requests to anywhere — there is no firewall
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

The container is attached to a per-session isolated Docker network (`claudius-$$`). This network exists so the container can reach the docker-socket-proxy sidecar by IP — it doesn't filter outbound traffic. From the container's perspective, the internet is reachable just like from any default-bridge Docker container.

There is no transparent proxy, no allow-list, no DNS restriction. If you need any of that, run claudius behind a host-level firewall, VPN, or DNS sinkhole. The Anthropic API, GitHub, package registries, etc. — all reachable.

The container exposes no inbound ports to the host.

**DNS** is configured via `--dns` flags pointing at `CLAUDIUS_DNS`. The entrypoint also writes `/etc/resolv.conf` directly because Docker's embedded resolver (`127.0.0.11`) can be unreliable inside gVisor.

**IPv6** is enabled when Docker can create the network with `--ipv6` (Docker assigns a ULA subnet automatically). Falls back to IPv4-only otherwise. Either works.

---

## Docker

claudius runs a [docker-socket-proxy](https://github.com/Tecnativa/docker-socket-proxy) sidecar on an isolated internal network. The Docker socket itself is never mounted into the container and Claude reaches it only through the filtered proxy.

This lets Claude inspect your host's Docker environment: read logs, list containers, check image state — without being able to change anything. Useful for diagnosing a broken service or understanding what's running, with no risk of accidental `docker run` or `docker stop`.

Available by default:

```
docker ps / logs / images / inspect / info / network ls / volume ls
```

Write operations are blocked at the proxy level. Set `CLAUDIUS_DOCKER_WRITE=1` to enable them: `run`, `build`, `stop`, and all other write/exec operations.

The Docker socket proxy sits on the isolated internal Docker network and is reachable by the container at its bridge IP.

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
