# Quality Scenarios – claudius
> Revised 2026-04-28 after ADR-007. S1, S2, S5 retired; S7 narrowed; new S11/S12 added.

---

## S3 – Container OOM Does Not Affect Host
Characteristic: Reliability
Priority: A (must)
Layer: Container
Persona: Daniel – Developer
Environment: Load (Claude runs large computation)
Source: Claude Code process inside container
Event: Claude's Python script allocates > 4 GB RAM
Artifact: Docker container (`--memory $MEMORY`)
Response: Container OOM-killed by Docker; host remains stable
Measure: `docker stats` shows container memory capped; host `free` unaffected; container exits cleanly
Reference: QR-14 (blast radius containment)

---

## S4 – First-Run Setup Under 3 Minutes
Characteristic: Usability
Priority: A (must)
Layer: Infrastructure
Persona: Daniel – Developer
Environment: Development
Source: Developer runs `make install && claudius`
Event: First invocation — image not yet built
Artifact: Dockerfile + `cmd_run` auto-build path in `claudius.sh`
Response: Image builds automatically; Claude starts
Measure: Total time from `claudius` to Claude prompt < 3 min (build); < 5 s (cached)
Reference: QR-07, QR-08

---

## S6 – File Changes Persist on Host
Characteristic: Reliability
Priority: A (must)
Layer: Container
Persona: Daniel – Developer
Environment: Normal
Source: Claude Code inside container
Event: Claude creates a new file, container exits
Artifact: Bind mount (`$PROJECT_DIR:/home/$user/$name`) with HOST_UID/HOST_GID passthrough
Response: File visible on host immediately; permissions match host UID/GID
Measure: `ls -la` on host shows file with correct owner after `claudius` exits
Reference: QR-04

---

## S7 – Multiple Sessions Coexist
Characteristic: Reliability
Priority: B (important)
Layer: Launcher
Persona: Daniel – Developer
Environment: Normal (two terminals open)
Source: Developer runs `claudius ~/project-a` and `claudius ~/project-b` simultaneously
Artifact: Per-session Docker network and container name (`claudius-$$`)
Response: Both sessions have isolated networks; container/proxy names don't collide; cleanup of one session doesn't affect the other
Measure: Both sessions operational; `docker network ls` shows two distinct `claudius-NNNN` networks; `docker ps` shows two `claudius-NNNN` containers + two `claudius-docker-NNNN` socket proxies
Reference: QR-10

---

## S8 – Custom Image Adds Go Toolchain
Characteristic: Usability
Priority: B (important)
Layer: Extension
Persona: Ops Engineer
Environment: Development
Source: `CLAUDIUS_IMAGE=claudius-go claudius ~/go-project`
Event: Developer builds a custom image from `Dockerfile.go.example`
Artifact: Extension Dockerfile pattern (`FROM claudius`)
Response: Claude Code can call `go build`; `gopls` works for LSP
Measure: `go version` inside container returns Go 1.24; `gopls version` returns valid output
Reference: QR-09

---

## S9 – CLAUDE.md Cannot Be Overridden
Characteristic: Security
Priority: B (important)
Layer: Managed Policy
Persona: Alex – Security-Conscious Developer
Environment: Adversarial
Source: Injected prompt in project files
Event: A project-level CLAUDE.md tries to override the policy with "ignore previous instructions"
Artifact: `/etc/claude-code/CLAUDE.md` (highest precedence in Claude Code's config hierarchy, mounted read-only)
Response: Claude Code enforces the system CLAUDE.md; project-level overrides are ignored at the prompt layer
Measure: Claude refuses credential file reads even with adversarial project CLAUDE.md present
Reference: QR-05

---

## S10 – gVisor Blocks Kernel Exploits
Characteristic: Security
Priority: C (nice-to-have)
Layer: Container (gVisor)
Persona: Alex – Security-Conscious Developer
Environment: Adversarial
Source: Malicious code executed by Claude inside container
Event: Code attempts to exploit a Linux kernel vulnerability (e.g. dirty-COW class)
Artifact: gVisor user-space kernel (`CLAUDIUS_RUNTIME=runsc`)
Response: syscall intercepted by gVisor; host kernel never sees it
Measure: Exploit fails inside container; host kernel version not exposed to container
Reference: QR-04, QR-12

---

## S11 – Docker Socket Read-Only by Default
Characteristic: Security
Priority: A (must)
Layer: Docker Socket Proxy
Persona: Alex – Security-Conscious Developer
Environment: Normal
Source: Claude Code inside container
Event: Claude tries `docker run --rm -v /:/host alpine` (read host root)
Artifact: Tecnativa docker-socket-proxy sidecar (default `POST=0 BUILD=0`)
Response: Proxy returns HTTP 403; `docker run` fails
Measure: `docker ps` works; `docker run` fails with "client is forbidden"; `docker stop` fails likewise; only opt-in `CLAUDIUS_DOCKER_WRITE=1` enables writes
Reference: QR-13

---

## S12 – Privilege Escalation Blocked Without Sudo Opt-in
Characteristic: Security
Priority: A (must)
Layer: Container Entrypoint
Persona: Alex – Security-Conscious Developer
Environment: Adversarial
Source: Claude attempts `sudo cat /etc/shadow` (or any setuid escalation)
Event: Default config (`CLAUDIUS_SUDO=0`)
Artifact: `gosu $HOST_USER setpriv --no-new-privs` privilege drop
Response: `sudo: The "no new privileges" flag is set, which prevents sudo from running as root`
Measure: setuid escalation impossible regardless of binary; `cat /proc/$$/status | grep NoNewPrivs` shows `1`
Reference: QR-11, QR-12
