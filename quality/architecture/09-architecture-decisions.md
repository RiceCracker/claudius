# § 9 Architecture Decisions

| ADR | Title | Status | Key Decision |
|---|---|---|---|
| ADR-001 | Host-side iptables proxy | **Superseded** by ADR-007 (2026-04-28) | All iptables rules on a proxy sidecar with `--network host`; no container-side rules — *removed* |
| ADR-002 | gVisor as optional runtime | Accepted | `CLAUDIUS_RUNTIME=runsc`; `--host-uds=open` + `--network=sandbox` required in daemon config |
| ADR-003 | Docker socket proxy (inspect-only) | Accepted | Tecnativa docker-socket-proxy; write ops blocked unless `CLAUDIUS_DOCKER_WRITE=1` |
| ADR-004 | CLAUDE.md managed policy | Accepted | `/etc/claude-code/CLAUDE.md` bind-mounted read-only; prompt-level only (not technical enforcement) |
| ADR-005 | gosu + setpriv privilege drop | Accepted | exec-based; no root parent; `--no-new-privs` when SUDO=0 |
| ADR-006 | SNI anti-spoof DNS verify | **Superseded** by ADR-007 (2026-04-28) | Async DNS check when allowed by SNI but not by IP — *removed* |
| ADR-007 | Drop in-process network filtering | Accepted (2026-04-28) | claudius is an isolation sandbox, not a filtering sandbox; outbound network is unrestricted by design |

Full ADR text in `quality/adr/ADR-NNN.md`.
