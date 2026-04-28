# Architecture Documentation – claudius
> Phase 10: Re-derived from current code, 2026-04-28 (post-ADR-007 / proxy removal)

## System Context

claudius is a local developer tool — a Bash launcher that orchestrates two Docker containers per session:

```
Host (Linux or macOS)
└── claudius.sh (Launcher)
    ├── docker network create claudius-$$ (isolated, optional IPv6)
    ├── claudius-docker-$$ — Tecnativa docker-socket-proxy (read-only API by default)
    └── claudius-$$ (main container)
        ├── entrypoint.sh → gosu → claude
        └── /home/$USER/$project (bind mount from host)
```

Outbound network goes through Docker's bridge unmodified. There is no transparent proxy and no allow-list — the launcher does not install iptables rules. Isolation is provided by:

- The Docker container boundary (capabilities, PID/UID namespaces, mount whitelist)
- Optional gVisor as the runtime (`CLAUDIUS_RUNTIME=runsc`) — user-space kernel
- The Docker-socket-proxy sidecar (read-only Docker API; writes opt-in)
- `gosu` + `setpriv --no-new-privs` privilege drop
- Read-only managed `CLAUDE.md` at `/etc/claude-code/CLAUDE.md`

## Quality Attribute Achievement

| Scenario | Status | Evidence |
|---|---|---|
| S3 – Container OOM | ✅ | `--memory $MEMORY` in `claudius.sh` `cmd_run`; container OOM-killed cleanly |
| S4 – First-run < 3 min | ✅ | Auto-build path in `cmd_run` |
| S6 – Files persist on host | ✅ | Bind mount + UID/GID passthrough (`HOST_UID`, `HOST_GID`) |
| S7 – Multiple sessions coexist | ✅ | `claudius-$$` per-session naming for both container and network |
| S8 – Custom image | ✅ | `Dockerfile.go.example`, `Dockerfile.flutter.example`, `Dockerfile.rust.example` |
| S9 – CLAUDE.md not overridable | ✅ | Bind-mount read-only at highest-precedence path |
| S10 – gVisor blocks kernel exploits | ✅ | `--runtime $RUNTIME` opt-in |
| S11 – Docker socket read-only | ✅ | Tecnativa proxy with `POST=BUILD=0` by default |
| S12 – Privilege escalation blocked | ✅ | `setpriv --no-new-privs` in entrypoint when SUDO=0 |

## Out of scope (post-ADR-007)

Network egress filtering. claudius does not inspect or block outbound connections. Users who need filtering apply it at the host layer (firewall, VPN, DNS sinkhole) or at the runtime layer.
