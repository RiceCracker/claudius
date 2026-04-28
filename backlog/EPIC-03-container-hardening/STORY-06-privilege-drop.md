# STORY-06: Privilege drop and capability hardening
**As** Daniel – Developer
**I want to** Claude Code to run as my user with minimal capabilities and no path to setuid escalation
**so that** even if Claude does something unexpected, it has no root privileges and cannot acquire them

**Acceptance Criteria:**
- [ ] `gosu $HOST_USER` replaces the entrypoint via `exec` (no root parent in the PID tree)
- [ ] `setpriv --no-new-privs` applied when `CLAUDIUS_SUDO=0` (the default)
- [ ] `cat /proc/$$/status | grep NoNewPrivs` returns `1` inside the container by default
- [ ] `sudo` (when present in the image) refuses with `no new privileges flag` unless `CLAUDIUS_SUDO=1`
- [ ] `--cap-drop ALL` with only `CHOWN`, `DAC_OVERRIDE`, `FOWNER`, `SETUID`, `SETGID`, `SETPCAP`, `NET_RAW` re-added
- [ ] Capability set is identical regardless of `CLAUDIUS_SUDO` value (sudo only lifts no-new-privs)
- [ ] PID limit 512 enforced
- [ ] Memory/CPU capped (default 4 g / 4 CPUs)
- [ ] Container OOM-killed cleanly when memory limit exceeded; host unaffected

**Layer:** Container
**Release:** MVP
**Reference:** QR-04, QR-11, QR-12, S3, S12, ADR-005
**Priority:** A
**Dependent on:** STORY-01

**Technical Cut:**
Existing:
- `docker/claudius/entrypoint.sh` – gosu + setpriv chain, sudoers writer
- `claudius.sh` `cmd_run` – `--cap-drop ALL`, `--cap-add` list, `--memory`, `--cpus`, `--pids-limit`

Tests (integration):
- `test_no_root_process` – `ps -eo user,pid,comm` inside container shows no root-owned long-running processes
- `test_no_new_privs_set` – `cat /proc/1/status | grep NoNewPrivs` is `1` when SUDO=0
- `test_sudo_blocked_default` – `sudo cat /etc/shadow` errors with `no new privileges`
- `test_sudo_unlocked_with_optin` – with `CLAUDIUS_SUDO=1`, sudoers entry exists for the configured commands and they work
- `test_memory_limit` – allocating > `CLAUDIUS_MEMORY` triggers OOM-kill of the container; `free` on the host is unchanged
- `test_caps_bounded_with_sudo` – capability set is the same with `CLAUDIUS_SUDO=1` as without (caps stay bounded)

**Subtasks:**
- [ ] Verify `gosu` is `exec`'d (no parent root process visible to ps)
- [ ] Verify `--no-new-privs` set in SUDO=0 case AND that `CLAUDIUS_SUDO=1` is the only path to lifting it
- [ ] Verify capability set matches the documented list (drop-all + 7 re-adds)
- [ ] Verify PID limit and resource limit enforcement under load

**Context for Implementation:** `docker/claudius/entrypoint.sh`, `claudius.sh` `cmd_run`
