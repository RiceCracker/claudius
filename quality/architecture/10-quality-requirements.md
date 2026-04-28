# § 10 Quality Requirements

> Re-derived 2026-04-28 from `quality/scenarios.md` after ADR-007.
> Retired: S1, S2, S5 (Network Proxy scenarios — proxy removed).

## Priority A Scenarios (Must)

| ID | Characteristic | Scenario | Measure |
|---|---|---|---|
| S3 | Reliability | Container OOM | Container killed at memory limit; host unaffected |
| S4 | Usability | First-run setup | First run < 3 min; cached < 5 s |
| S6 | Reliability | File persistence | Files created in container visible on host with correct ownership after exit |
| S11 | Security | Docker socket read-only | `docker run` blocked by default (HTTP 403); `docker ps` works; opt-in via `CLAUDIUS_DOCKER_WRITE=1` |
| S12 | Security | Privilege escalation blocked | `cat /proc/$$/status \| grep NoNewPrivs` returns `1` by default; sudo refuses with `no new privileges` |

## Priority B Scenarios (Important)

| ID | Characteristic | Scenario | Measure |
|---|---|---|---|
| S7 | Reliability | Multiple sessions coexist | Per-session Docker network and container/proxy names; no collisions |
| S8 | Usability | Custom image | Go/Flutter/Rust toolchain works via `FROM claudius` |
| S9 | Security | CLAUDE.md not overridable | Project-level override attempt fails (highest-precedence config layer) |

## Priority C Scenarios (Nice-to-have)

| ID | Characteristic | Scenario | Measure |
|---|---|---|---|
| S10 | Security | gVisor blocks kernel exploits | Syscall intercepted by gVisor; host kernel not exposed |
