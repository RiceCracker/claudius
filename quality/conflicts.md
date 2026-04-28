# Conflict Analysis – claudius
> Revised 2026-04-28 after ADR-007. C1 (SNI vs latency) retired — proxy removed.

---

## C2: Usability (clipboard on by default) ↔ Security (clipboard access = bidirectional host channel)
Conflict: QR-08 (zero-config) ↔ QR-04 (minimal exposure)
Type: Direct
Tension: Clipboard forwarding (`CLAUDIUS_CLIPBOARD=1` default) gives Claude read/write access to the host clipboard via the bridge socket. This is a data channel to/from the host outside any other isolation boundary.
Severity: Medium
Resolution: Documented explicitly in the threat model. Clipboard is on by default for usability (Daniel's need). Alex can disable with `CLAUDIUS_CLIPBOARD=0`. Not a technical enforcement gap — a documented opt-in risk.
Conflict Resolution: ADR-004 — conscious trade-off; documented, not mitigated.

---

## C3: Docker Write Access ↔ Privilege Isolation
Conflict: QR-04 (host isolation) ↔ Ops engineer use case (building images from inside)
Type: Direct (irreconcilable)
Tension: `CLAUDIUS_DOCKER_WRITE=1` allows `docker run` with arbitrary flags, including `--privileged` or mounting the host root filesystem. This effectively gives host-level access. Combined with `CLAUDIUS_SUDO=1` it is unconditionally equivalent to host root.
Severity: High
Resolution: Documented in the threat model. Never combine with `CLAUDIUS_SUDO=1` unless that is intended. The user bears responsibility when enabling either. No technical enforcement is possible (Docker's architecture limitation).
Conflict Resolution: ADR-003 — documented risk; warned in README.

---

## C4: gVisor (runsc) ↔ Wayland Clipboard
Conflict: S10 (gVisor isolation) ↔ S6 (clipboard usability — *via Wayland*)
Type: Direct
Tension: gVisor's netstack handled Unix socket forwarding for Wayland inconsistently. With the new clipboard bridge (Unix socket on the host), this is no longer an issue at the Wayland layer — but `--host-uds=open` must be set in the Docker daemon config when `CLAUDIUS_RUNTIME=runsc`, otherwise the bridge socket forwarding fails with "Connection refused".
Severity: Low
Resolution: `make gvisor-install` configures `--host-uds=open --network=sandbox` in `/etc/docker/daemon.json`. `make gvisor-check` verifies this. Documented in `docs/security.md` and the gVisor section of the README.
Conflict Resolution: ADR-002 — gVisor optional, well-documented setup requirements.

---

## Removed conflicts

- **C1: Security (SNI anti-spoof) ↔ Performance (TCP latency)** — retired 2026-04-28. The proxy is gone; there is no DNS round-trip during connection establishment to balance against. ADR-006 (the resolution) is superseded by ADR-007.
