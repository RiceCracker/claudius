# STORY-02: Integration test suite for the post-refactor sandbox
**As** Ops Engineer
**I want to** run `make test-integration` to verify the container, mounts, network, Docker socket boundary and privilege drop
**so that** regressions in the isolation guarantees are caught before shipping

**Acceptance Criteria:**
- [ ] Container starts and exits cleanly with `claudius bash -c true`
- [ ] Project dir is mounted writable; files created inside appear on the host with correct UID/GID (S6)
- [ ] Claude binary is on `PATH` inside the container
- [ ] DNS resolves both `api.anthropic.com` and an arbitrary external host (`example.com`)
- [ ] Outbound network is reachable to `api.anthropic.com`, `github.com`, `registry.npmjs.org` (no firewall — proves egress is open)
- [ ] `docker ps` works inside the container (read access via socket proxy)
- [ ] `docker run --rm hello-world` is **rejected** with HTTP 403 by default (S11)
- [ ] `cat /proc/$$/status | grep NoNewPrivs` returns `1` by default (S12 sentinel)
- [ ] Test exit code: 0 = all pass, 1 = any failure

**Layer:** Infrastructure
**Release:** MVP
**Reference:** QR-08, QR-13, QR-11, S6, S11, S12
**Priority:** A
**Dependent on:** STORY-01

**Technical Cut:**
Existing:
- `tests/integration.sh` – test harness (rebuilt 2026-04-28 after proxy removal)
- `tests/integration.env` – test configuration (`CLAUDIUS_MEMORY=256m`, `CPUS=1`, clipboard/SSH/GPG off)

Tests (in `tests/integration.sh`):
- `Container & mounts` – `reachable "container starts"`, `reachable "project dir mounted"`, `reachable "claude on PATH"`
- `DNS` – `reachable "resolves api.anthropic.com"`, `reachable "resolves example.com"`
- `Outbound network` – `reachable api.anthropic.com:443`, `reachable github.com:443`, `reachable registry.npmjs.org:443`
- `Docker socket proxy` – `reachable "docker ps via socket proxy"`, `unreachable "docker run blocked"`

**Subtasks:**
- [ ] Add a test for `NoNewPrivs=1` (S12) — runs `cat /proc/$$/status` and greps; not yet in `tests/integration.sh`
- [ ] Verify exit-code propagation: a forced failure (e.g. `_run "false"`) must make the script exit 1
- [ ] Decide whether to remove `tests/cases/` (currently empty)

**Context for Implementation:** `tests/integration.sh`, `tests/integration.env`
