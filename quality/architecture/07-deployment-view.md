# § 7 Deployment View

## Local Linux

```
Linux Host
├── Docker Engine (runc default, optional runsc/gVisor)
│   └── Network: claudius-$$ (isolated, IPv4 + optional IPv6)
│       ├── claudius-docker-$$ (Tecnativa socket proxy)
│       └── claudius-$$ (main container, node:22-bookworm-slim)
│           ├── Claude Code process (as HOST_USER)
│           ├── Language servers (pyright, ts, bash, yaml, sql, json/html/css/md)
│           ├── Gemini MCP (@rlabs-inc/gemini-mcp)
│           └── claudius-clip shim (xclip / wl-* / pbcopy aliased)
├── ~/.claude/  ──────────────▶ /home/$USER/.claude/  (rw bind mount)
├── ~/project/  ──────────────▶ /home/$USER/project/ (rw bind mount)
├── /tmp/claudius-clip.XXXX/sock ▶ /run/claudius/clipboard.sock (rw bind mount)
└── /var/run/docker.sock ─────▶ claudius-docker-$$ only (NOT mounted into main container)
```

**Optional:** `CLAUDIUS_RUNTIME=runsc` swaps runc for gVisor on the main container. Requires `--host-uds=open` and `--network=sandbox` in the daemon config (set by `make gvisor-install`).

## Local macOS

Identical topology — same containers, same mounts, same network. There is no longer a Linux-specific feature flag (`CLAUDIUS_NO_PROXY=1` was removed with the proxy in ADR-007).

What differs by platform:

| Concern | Linux | macOS |
|---|---|---|
| Docker runtime | runc / runsc | Docker Desktop (Linux VM) |
| gVisor | available | not available |
| Clipboard tooling | xclip + DISPLAY *or* wl-clipboard + WAYLAND_DISPLAY on host | `pbcopy` / `pbpaste` on host (wired identically through the bridge) |

## Non-interactive / CI

```bash
claudius bash -c 'claude -p "summarize this repo"'
```

Identical container setup. TTY detection (`[ -t 0 ] && [ -t 1 ]`) switches to `-i` (without `-t`) when stdin/stdout are not terminals. Suitable for `bash -c '...'` and heredoc invocations from scripts.

## Install

```
~/.local/bin/claudius  →  symlink  →  /path/to/claudius/claudius.sh
```

`make install` creates the symlink. `make build` builds `claudius:latest` (one image — the proxy image is gone).
