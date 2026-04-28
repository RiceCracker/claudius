# Quality STATUS – claudius

**Current Phase:** Post-refactor stabilisation (Phase 1/6/7 manually re-run after ADR-007)
**Last Updated:** 2026-04-28 — proxy refactor + quality artefacts re-aligned
**Next Step:** Re-run `/artifex-heavy-analyze`; then `/artifex-heavy-review` for a fresh Phase 11 score against the new baseline.

---

## Phase Progress

| Phase | Status | Artifact | Notes |
|---|---|---|---|
| 1 Vision | ✅ Re-run 2026-04-28 | `quality/vision.md` | Reframed as isolation tool (ADR-007) |
| 2 Glossary | ✅ Re-run 2026-04-28 | `quality/glossary.md` | Removed Proxy Sidecar, ACL, SNI, SNI Spoofing, NFQUEUE |
| 3 Market Research | ✅ Re-run 2026-04-28 | `quality/market-research.md` | Reframed: filtering tool → isolation tool |
| 4 Project Description | ✅ Re-run 2026-04-28 | `quality/project.md` | Loop 2/3 dropped; system layers reflect post-ADR-007 |
| 5 Personas | ✅ Re-run 2026-04-28 | `quality/personas/alex-security-conscious.md` | Pain Points refreshed for isolation focus |
| 5b User Journeys | ✅ Re-run 2026-04-28 | `quality/journeys/daily-dev-session.md` | Steps now describe socket-proxy + privilege-drop flow |
| 6a Quality Requirements | ✅ Re-run 2026-04-28 | `quality/requirements.md` | Dropped QR-01/02/03/06; added QR-11/12/13/14 |
| 6b Quality Scenarios | ✅ Re-run 2026-04-28 | `quality/scenarios.md` | Dropped S1/S2/S5; added S11/S12 |
| 7 Conflict Analysis | ✅ Re-run 2026-04-28 | `quality/conflicts.md` | C1 retired |
| 8 Backlog | ✅ Updated 2026-04-28 | `backlog/` | EPIC-02 archived; STORY-09 (S11), STORY-10 (clipboard) added; STORY-06 re-keyed; STORY-02 rewritten |
| 9 Build | ✅ Code matches new vision | `claudius.sh`, `docker/claudius/`, `docker/clipboard/`, `docker/docker-socket-proxy/` | -330 lines net post-refactor |
| 10 Architecture (arc42) | ✅ Re-run 2026-04-28 | `quality/architecture/01..12 + README` | All 13 files refreshed; ADR-007 reflected |
| 11 Review | ⚪ Awaiting re-run | (old `quality/review.md` archived to `quality/.archive/review-2026-03.md`) | Trigger fresh Phase 11 via `/artifex-heavy-review` |

⚪ = not in scope of this refactor pass; address before next major release if needed.

---

## A-Scenarios (post-refactor)

| ID | Layer | Measure |
|---|---|---|
| S3 | Container | Container OOM-killed; host stable |
| S4 | Infrastructure | First run < 3 min; cached < 5 s |
| S6 | Container | Bind mount: file changes visible on host with correct UID/GID |
| S11 | Docker Socket Proxy | `docker run` blocked by default; `docker ps` works |
| S12 | Container Entrypoint | sudo refuses with `no_new_privs` unless `CLAUDIUS_SUDO=1` |

---

## ADRs

| ADR | Title | Status |
|---|---|---|
| ADR-001 | Host-side iptables proxy (no container-side rules) | **Superseded** by ADR-007 (2026-04-28) |
| ADR-002 | gVisor as optional runtime | Accepted |
| ADR-003 | Docker socket proxy (inspect-only default) | Accepted |
| ADR-004 | CLAUDE.md managed policy (prompt-level, not technical) | Accepted |
| ADR-005 | gosu + setpriv privilege drop | Accepted |
| ADR-006 | SNI anti-spoof DNS verify | **Superseded** by ADR-007 (2026-04-28) |
| ADR-007 | Drop in-process network filtering — isolation-only sandbox | **Accepted** (2026-04-28) |

---

## Confirmed Decisions
<!-- LOCKED — only a new explicit ADR can change these -->

- claudius is an **isolation sandbox**, not a **filtering sandbox** (ADR-007).
- Outbound network is unrestricted by design; users apply filtering at the host or runtime layer.
- Per-session Docker network is kept solely for hosting the docker-socket-proxy sidecar.
- `--no-new-privs` is the load-bearing escalation barrier; the capability set is the second.
- `CLAUDE.md` mounted read-only at `/etc/claude-code/CLAUDE.md` is the single managed-policy mechanism.

---

## Open Points

- `docs/architecture.svg` shows the old proxy sidecar — needs regeneration.
- `tests/cases/` remains empty — either populate or delete.
- No `quality/constitution.md`, no `quality/tasks.md`, no `docs/tree.md`; all optional but would help future agents reading this project cold.
- No fresh Phase 11 review yet (the pre-refactor one is archived). Run `/artifex-heavy-review` for a current Quality Score against the new baseline when desired.
