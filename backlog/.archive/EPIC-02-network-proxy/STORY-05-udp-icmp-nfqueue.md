# STORY-05: UDP/ICMP fail-closed filtering via NFQUEUE
**As** Alex – Security-Conscious Developer
**I want to** have UDP and ICMP filtered fail-closed
**so that** DNS exfiltration and UDP-based leaks are impossible even if the proxy crashes

**Acceptance Criteria:**
- [ ] UDP to unresolved hosts is blocked
- [ ] UDP packets dropped (not passed) when NFQUEUE listener not running
- [ ] ICMP allowed only to IPs matching any ACL rule
- [ ] IPv6 UDP and ICMPv6 filtered identically

**Layer:** Network Proxy
**Release:** MVP
**Reference:** QR-03, S5
**Priority:** A
**Dependent on:** STORY-01

**Technical Cut:**
Existing:
- `on_nfqueue_packet(pkt)` – `docker/proxy/entrypoint.py:209`
- `is_allowed(None, dst_ip, dst_port, "udp")` – UDP ACL (IP-only)
- `is_icmp_allowed(ip)` – ICMP ACL
- iptables NFQUEUE rules (no --queue-bypass) – `docker/proxy/entrypoint.py:74-76`

Tests:
- `test_udp_fail_closed` – Integration – UDP dropped when listener not running
- `test_dns_blocked_to_non_allowed_resolver` – Integration – DNS to non-configured resolver blocked
- `test_dns_allowed_to_configured_resolver` – Integration – DNS to CLAUDIUS_DNS resolvers allowed

**Subtasks:**
- [ ] Verify NFQUEUE configured without --queue-bypass
- [ ] Add/verify UDP fail-closed test case
- [ ] Verify DNS resolver auto-added to ALLOW in launcher
- [ ] Verify IPv6 UDP handling (SUBNET6 path)

**Context for Implementation:** `docker/proxy/entrypoint.py:70-100`, `209-244`
