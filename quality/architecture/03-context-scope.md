# § 3 Context & Scope

## System Context

```
┌─────────────────────────────────────────────────────┐
│                Host (Linux or macOS)                 │
│                                                      │
│  Developer ──▶ claudius.sh ──▶ Docker Engine         │
│                    │                                 │
│             ┌──────┴──────┐                          │
│             ▼             ▼                          │
│   claudius-docker-$$    claudius-$$                  │
│   (socket proxy,        (main container)             │
│    read-only API)                                    │
│                                                      │
│  ~/.claude/  ◀────────── bind mount (rw) ────────    │
│  ~/project/  ◀────────── bind mount (rw) ────────    │
│  clipboard.sock ◀───── per-session UDS ─────────     │
└─────────────────────────────────────────────────────┘
        │
        ▼
   Internet (unrestricted egress via Docker bridge)
```

## External Systems

| System | Interaction | Direction | Controlled by |
|---|---|---|---|
| Anthropic API (`*.anthropic.com`) | Claude Code sends requests | out | Always reachable — outbound is unfiltered |
| Arbitrary outbound destinations | Any Claude tool call (HTTPS, git, npm, pip) | out | Reachable — outbound is unfiltered |
| DNS resolvers (`CLAUDIUS_DNS`) | Container DNS resolution | out | Configured via `--dns` flags + `/etc/resolv.conf` |
| Host Docker daemon | Container inspection (and writes if `CLAUDIUS_DOCKER_WRITE=1`) | out | Tecnativa docker-socket-proxy sidecar |
| Host SSH agent | Git operations via `SSH_AUTH_SOCK` | out | `CLAUDIUS_SSH=1` |
| Host GPG agent | Commit signing | out | `CLAUDIUS_GPG=1` |
| Host clipboard (Wayland/X11) | Copy/paste | bidirectional | `CLAUDIUS_CLIPBOARD=1` (default), brokered via Unix socket |

## Inside / Outside

**Inside claudius (container):** Claude Code process, all tool executions, language servers, Gemini MCP, file I/O on the project dir and `~/.claude/`.

**Outside claudius (host):** All other host processes, `~/.ssh`, `~/.aws`, other Docker containers (except via the socket proxy), host filesystem outside the mounted paths.
