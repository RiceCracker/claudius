# EPIC-01: Infrastructure & Dev Environment
**Layer:** Launcher
**Layer-Prio:** 1
**Release:** MVP
**Dependent on:** –
**Goal:** `make install && claudius ~/project` works on any Linux system with Docker, without configuration. First run builds image automatically.
**Reference:** QR-07, QR-08, S4
**Acceptance Criteria:**
- [ ] `make install` symlinks `claudius` into `~/.local/bin`
- [ ] First invocation auto-builds image if missing
- [ ] Cached startup < 5 seconds
- [ ] `make uninstall` removes symlink cleanly
- [ ] `make test-integration` passes all A-scenario tests

**Planned Modules / Components:**
- `claudius.sh` – Launcher entrypoint (already exists)
- `docker/claudius/Dockerfile` – Base image (already exists)
- `docker/claudius/entrypoint.sh` – Privilege drop + init hook
- `Makefile` – build, rebuild, install, uninstall, gvisor targets
- `tests/integration.sh` – End-to-end network filtering tests
