# EPIC-04: Extensibility (Custom Images + Init Hook)
**Layer:** Container Image / Launcher
**Layer-Prio:** 4
**Release:** MVP
**Dependent on:** EPIC-03
**Goal:** Developers can add language-specific toolchains (Go, Flutter, Rust) and per-session config (git identity) without modifying the core image or launcher.
**Reference:** QR-09, S8
**Acceptance Criteria:**
- [ ] `FROM claudius` + `CLAUDIUS_IMAGE=custom` works
- [ ] Example Dockerfiles for Go, Flutter, Rust provided and tested
- [ ] `CLAUDIUS_USER_INIT` hook runs as root before privilege drop
- [ ] Init hook can set git identity, add aliases
- [ ] `user-init.sh.example` template provided

**Planned Modules / Components:**
- `docker/claudius/Dockerfile.go.example`
- `docker/claudius/Dockerfile.flutter.example`
- `docker/claudius/Dockerfile.rust.example`
- `user-init.sh.example` – Init hook template
- `docker/claudius/entrypoint.sh` – Hook execution path
