# Quality Requirements – claudius
> Derived from ISO/IEC 25010
> Revised 2026-04-28 after ADR-007 (network proxy removed). QR-01, QR-02, QR-03, QR-06 retired.

## Security

### QR-04: Minimal Filesystem Exposure
Sub-characteristic: Confidentiality
Layer: Container
Description: Only the project dir, `~/.claude/`, and `~/.claude.json` are mounted from the host. Optional mounts (SSH agent socket, GPG socket, clipboard socket, user-init script) appear only when their respective env var is set. No other host paths are accessible.
Rationale: Daniel's primary concern: Claude reading `~/.aws`, `~/.ssh`, or `/etc/passwd`. The mount whitelist is the load-bearing boundary now that the proxy is gone.

### QR-05: Credential File Non-Disclosure (prompt-level)
Sub-characteristic: Confidentiality
Layer: Managed Policy
Description: `CLAUDE.md` mounted read-only at `/etc/claude-code/CLAUDE.md` instructs Claude not to read `.env`, `.pem`, `.key`, SSH keys, cloud credentials, etc. Highest precedence in Claude Code's config hierarchy.
Rationale: Prompt-level mitigation only — the Anthropic credentials file in `~/.claude/.credentials.json` is technically reachable. CLAUDE.md raises the bar for accidental misuse but not for an adversarial prompt.

### QR-11: Privilege Drop With No Lingering Root
Sub-characteristic: Integrity
Layer: Container Entrypoint
Description: After user-init the entrypoint executes `gosu $HOST_USER setpriv --no-new-privs` (SUDO=0) or `gosu $HOST_USER` (SUDO=1). No root parent process remains in the PID tree.
Rationale: Setuid escalation must be impossible without an explicit `CLAUDIUS_SUDO=1` opt-in.

### QR-12: Bounded Capability Set
Sub-characteristic: Integrity
Layer: Container Runtime
Description: `--cap-drop ALL` is applied; only `CHOWN`, `DAC_OVERRIDE`, `FOWNER`, `SETUID`, `SETGID`, `SETPCAP`, `NET_RAW` are added back. Even `CLAUDIUS_SUDO=1` does not add capabilities — it only lifts `--no-new-privs`.
Rationale: Capability bounding is the second line of defence after `--no-new-privs`.

### QR-13: Docker Socket Filtered, Not Exposed
Sub-characteristic: Integrity / Confidentiality
Layer: Docker Socket Proxy
Description: The host Docker socket is never bind-mounted into the claudius container. Access goes through a Tecnativa `docker-socket-proxy` sidecar with `CONTAINERS=1 IMAGES=1 INFO=1 NETWORKS=1 VOLUMES=1 VERSION=1`. Write operations require `CLAUDIUS_DOCKER_WRITE=1` (adds `POST=1 BUILD=1`).
Rationale: Read-only Docker access is genuinely useful (debugging running services) and cheap. Write access is an explicit opt-in because it equates to host root.

## Reliability

### QR-14: Session-Scoped Cleanup on Exit
Sub-characteristic: Recoverability
Layer: Launcher
Description: On EXIT, INT, or TERM signals the launcher must remove the docker-socket-proxy sidecar, remove the per-session Docker network, and tear down the clipboard bridge. No orphaned containers, networks, or temp dirs.
Rationale: Multiple sessions per day; cleanup mistakes accumulate fast.

## Performance Efficiency

### QR-07: Fast Startup (cached)
Sub-characteristic: Time Behaviour
Layer: Launcher
Description: After the first build, `claudius ~/project` must start Claude Code in under 5 seconds.
Rationale: Daniel uses claudius throughout the day. Slow startup breaks flow.

## Usability

### QR-08: Zero-Config Safe Default
Sub-characteristic: Operability
Layer: Launcher
Description: `make install && claudius` must work on any Linux or macOS system with Docker, without requiring any configuration file.
Rationale: claudius competes with "just run Claude Code directly" — friction must be near zero. Removing the proxy made true cross-platform parity achievable.

### QR-09: Opt-in Extensibility
Sub-characteristic: Operability / Modifiability
Layer: Container Image / Launcher
Description: Custom tools must be addable via Dockerfile inheritance (`FROM claudius`) or the runtime init hook (`CLAUDIUS_USER_INIT`), without modifying the core launcher or image.
Rationale: Ops engineers need to add Go/Flutter/Rust toolchains without forking.

## Maintainability

### QR-10: Per-Session Container Naming
Sub-characteristic: Modularity
Layer: Launcher
Description: Each claudius session uses `claudius-$$` for its container name and Docker network. Multiple sessions coexist without name collisions.
Rationale: Daniel may run claudius simultaneously across two or more projects.

## Out of Scope (post-ADR-007)

### Network egress filtering
claudius does **not** filter outbound traffic. Hosts are reached via the Docker bridge. Users who need filtering apply it at the host (firewall, VPN, DNS sinkhole) or at the runtime layer.
Rationale: ADR-007 — the cost of running a userspace netfilter proxy outweighed the value once `*:443/tcp` became the typical allow-list entry.

## GDPR Check
**No personal data processed by claudius itself.** The tool is a container launcher and Docker-socket sidecar. It does not collect, store, or transmit user data. Files in the mounted project directory may contain personal data — that is the user's responsibility.
