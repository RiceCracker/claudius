# § 4 Solution Strategy

## Key Decisions & Rationale

| Decision | Pattern | Rationale | ADR |
|---|---|---|---|
| Drop in-process network filtering | Isolation-only sandbox | Userspace netfilter proxy carried high maintenance cost; users typically opened `*:443/tcp` anyway, gutting the value | ADR-007 |
| Docker socket proxy (Tecnativa) | Filtered Unix socket via sidecar | Read-only Docker API by default; raw socket never bind-mounted into the claudius container | ADR-003 |
| gVisor as opt-in runtime | User-space kernel | Syscall interception without full VM overhead; strongest isolation short of a VM | ADR-002 |
| `gosu` + `setpriv` privilege drop | exec-based handoff | No root parent process remains; signals go directly to Claude Code; `--no-new-privs` blocks setuid escalation | ADR-005 |
| `CLAUDE.md` managed policy | Highest-precedence config file, read-only bind mount | Prompt-level guardrails that cannot be overridden by project-level instructions | ADR-004 |
| Per-session Docker network | `claudius-$$` named network with optional `--ipv6` | Hosts the docker-socket-proxy sidecar at a stable IP; lets multiple sessions coexist without name collisions | – |
| Clipboard via host-side Unix socket bridge | Per-session UDS broker, no X11 / Wayland exposure | Brokers copy/paste without exposing the host display server to the container | – |
| Bash launcher + sourced helpers | Shell orchestration | Zero runtime dependencies; leverages Docker CLI directly; `~336` LOC after ADR-007 | – |

## Technology Choices

| Component | Technology | Why |
|---|---|---|
| Launcher | Bash | Zero dependencies; ubiquitous; matches Docker CLI workflow |
| Base image | `node:22-bookworm-slim` | Claude Code requires Node; Bookworm for apt package compatibility |
| Privilege drop | `gosu` | exec semantics (no root parent); battle-tested Docker primitive |
| Container runtime | Docker (runc default, runsc opt-in) | Standard tooling; gVisor integrates as drop-in Docker runtime |
| Docker-socket-proxy | Tecnativa `docker-socket-proxy:v0.4.2` | Maintained, widely deployed, env-flag config matches our needs |
| Clipboard bridge | Python 3 stdlib (asyncio + socket) | Single-file daemon, no third-party deps, runs on the host |
