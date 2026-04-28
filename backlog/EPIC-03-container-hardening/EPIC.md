# EPIC-03: Container Hardening & Privilege Drop
**Layer:** Container
**Layer-Prio:** 2
**Release:** MVP
**Dependent on:** EPIC-01
**Goal:** claudius container runs as minimal user with dropped capabilities, bounded resources, and correct privilege drop chain. gVisor optionally adds syscall-level isolation.
**Reference:** QR-04, QR-08, QR-11, QR-12, QR-13, S3, S6, S11, S12, ADR-002, ADR-003, ADR-005
**Acceptance Criteria:**
- [ ] `--cap-drop ALL` + selective re-add applied
- [ ] gosu privilege drop: no root process in PID tree after start
- [ ] `--no-new-privs` set when SUDO=0; setuid escalation blocked at the kernel
- [ ] Memory/CPU limits enforced (container OOM-killed, host unaffected)
- [ ] gVisor runtime works with SSH and GPG forwarding
- [ ] PID limit 512 enforced
- [ ] Docker socket exposed read-only by default via Tecnativa proxy; writes opt-in only
- [ ] Clipboard forwarded via Unix-socket bridge with no X11 / Wayland socket exposure

**Planned Modules / Components:**
- `docker/claudius/entrypoint.sh` – Privilege drop + user-init hook
- `claudius.sh` – docker run capability + resource flags + clipboard bridge wiring
- `docker/docker-socket-proxy/start.sh` – read-only Docker API sidecar
- `docker/clipboard/host.py` + `docker/clipboard/client.py` – clipboard bridge daemon + container shim
- `CLAUDE.md` / `/etc/claude-code/CLAUDE.md` – Managed policy
