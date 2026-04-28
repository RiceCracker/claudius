# Persona: Alex – Security-Conscious Developer

**Role:** Security engineer / developer at a company with strict data policies
**Goal:** Run Claude Code on internal projects with confidence that Claude cannot escalate beyond an isolated container, write to the host Docker daemon, or override the policy file. Audit the boundaries themselves rather than per-request traffic.
**Context:** Works with sensitive codebases (internal APIs, not public). Network egress filtering is handled at the corporate firewall and DNS layer — not the developer's responsibility. Claude needs to do its job without touching `~/.aws`, `~/.ssh`, or other host containers.
**Pain Points:**
- Standard Docker setups for AI agents leak host state through bind mounts, uncontrolled capabilities, or a shared Docker socket
- Many "sandboxes" run Claude as root inside the container — kernel exploits become practical
- Copy/paste is often "achieved" by exposing the X11 / Wayland socket, which trades isolation for usability
- `CLAUDIUS_DOCKER_WRITE=1` and `CLAUDIUS_SUDO=1` need to be visibly opt-in — the team must know before either flag is set
**Tech Level:** Expert
