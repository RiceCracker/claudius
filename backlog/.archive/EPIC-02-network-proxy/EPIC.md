# EPIC-02: Network Proxy (TCP/UDP/ICMP Filtering)
**Layer:** Network Proxy
**Layer-Prio:** 1
**Release:** MVP
**Dependent on:** EPIC-01
**Goal:** All outbound network traffic is filtered via ACL. TCP uses transparent REDIRECT + SNI/Host inspection. UDP/ICMP use NFQUEUE fail-closed. IPv6 supported.
**Reference:** QR-01, QR-02, QR-03, S1, S2, S5
**Acceptance Criteria:**
- [ ] TCP: blocked hosts refused, proxy log BLOCK
- [ ] TCP: SNI spoof rejected, proxy log SNI-spoof
- [ ] UDP: fail-closed when listener not running
- [ ] IPv6 TCP and UDP filtered identically to IPv4
- [ ] iptables rules cleaned up on container exit

**Planned Modules / Components:**
- `docker/proxy/entrypoint.py` – Single-file Python proxy (already exists)
  - Contains: `build_rules`, `resolve_ip_map`, `is_allowed`, `is_allowed_by_ip`, `is_icmp_allowed`, `on_nfqueue_packet`, `setup`, `cleanup`, `handle_tcp`, `sni_ip_matches`, `relay`, `main`
- `docker/proxy/Dockerfile` – Python + netfilterqueue image
- `docker/proxy/start.sh` – Proxy startup helper
- `docker/proxy/prune-chains.sh` – Emergency iptables chain cleanup
