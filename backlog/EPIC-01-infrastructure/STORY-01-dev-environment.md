# STORY-01: Set up development environment
**As** Ops Engineer
**I want to** build and install claudius with a single command
**so that** any developer can start using it in under 3 minutes without configuration

**Acceptance Criteria:**
- [ ] `make install` succeeds; `claudius` binary available in PATH
- [ ] First `claudius ~/project` auto-builds image and starts Claude Code
- [ ] Cached run starts in < 5 seconds
- [ ] `make rebuild` force-rebuilds without cache (updates Claude Code to latest)

**Layer:** Infrastructure
**Release:** MVP
**Reference:** QR-07, QR-08, S4
**Priority:** A
**Dependent on:** –

**Technical Cut:**
Existing:
- `claudius.sh` – auto-build on first run (lines 18-27)
- `Makefile` – build, rebuild, install, uninstall targets
- `docker/claudius/Dockerfile` – base image

**Subtasks:**
- [ ] Verify `make install` creates correct symlink
- [ ] Verify auto-build triggers on first run with user-friendly progress message
- [ ] Verify cached startup < 5 seconds
- [ ] Verify `make rebuild` fetches latest Claude Code
- [ ] Add `make help` target documentation

**Context for Implementation:** `claudius.sh:18-27`, `Makefile:28-34`
