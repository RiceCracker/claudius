# § 11 Risks & Technical Debt

## Open Risks

| Risk | Severity | Context | Mitigation |
|---|---|---|---|
| Outbound network is unrestricted (post-ADR-007) | Medium | Removed by design; users who assume claudius blocks egress will be surprised | Documented prominently in README + `docs/security.md` + ADR-007 itself |
| `NET_RAW` capability in default config | Low | Allows raw sockets (tcpdump) but also ARP-spoofing within container network | Documented; only relevant within the container's own bridge, not the host |
| `docker inspect` exposes `Config.Env` of other containers | Medium | Passwords of co-running containers visible to Claude (ADR-003) | Documented in README threat model; cannot be fixed without restricting inspect |
| `CLAUDE.md` is prompt-level only | Low | A sufficiently adversarial prompt could override security instructions | Documented; technical enforcement not possible with the current Claude Code config API |
| `CLAUDIUS_SUDO=1` lifts `--no-new-privs` | Medium | Setuid escalation becomes possible (the whole point), but capabilities still bounded | Documented; explicit opt-in; `CLAUDIUS_SUDO_CMDS` narrows which binaries get sudoers entries |
| `CLAUDIUS_DOCKER_WRITE=1` ≈ host root | High | Claude can `docker run --privileged -v /:/host` | Documented; explicit opt-in; warned against combining with `CLAUDIUS_SUDO=1` |

## Technical Debt

| Item | Layer | Notes |
|---|---|---|
| No automated gVisor tests | Infrastructure | gVisor needs a privileged Linux host; manual smoke test for now |
| `tests/cases/` directory is empty | Tests | All tests are inline in `integration.sh`; either populate or remove |
| Claude Code auto-update disabled globally (`DISABLE_AUTOUPDATER=1`) | Container | Users must `make rebuild` to update Claude Code; no in-place update path |
| `docs/architecture.svg` shows the old proxy sidecar | Docs | Needs regeneration to match the post-ADR-007 topology |
| `quality/journeys/`, `quality/project.md`, `quality/market-research.md`, `personas/alex-security-conscious.md` not refreshed | Quality artefacts | Flagged ⚪ Stale in `STATUS.md`; non-blocking but reads weirdly post-refactor |
| No `quality/constitution.md`, no `quality/tasks.md`, no `docs/tree.md` | Quality artefacts | Phase 0 + tasks graph + file map were never generated; would help future agents reading the project cold |

## Deferred Quality Attributes (from `quality/conflicts.md`)

| Trade-off | Decision |
|---|---|
| Usability (clipboard on by default) vs. Security (clipboard channel) | Usability wins — documented as opt-in risk |
| Docker write access vs. privilege isolation | User responsibility when enabling — documented |
| gVisor vs. Wayland clipboard | Resolved by per-session Unix-socket bridge + `--host-uds=open`; not a conflict in practice anymore |
| ~~Security (SNI DNS check) vs. Performance (latency)~~ | Retired with the proxy (ADR-007) |
