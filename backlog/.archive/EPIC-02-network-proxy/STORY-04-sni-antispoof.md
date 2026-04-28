# STORY-04: SNI anti-spoofing protection
**As** Alex – Security-Conscious Developer
**I want to** have SNI-spoofing attacks blocked and logged
**so that** a blocked IP cannot be reached by presenting an allowed hostname in TLS SNI

**Acceptance Criteria:**
- [ ] Connection to blocked IP with allowed SNI is rejected
- [ ] Log entry: `BLOCK tcp SNI-spoof api.anthropic.com → 93.184.216.34`
- [ ] Legitimate traffic not broken by DNS errors (fail-open on DNS timeout)
- [ ] Anti-spoof check only triggered when allowed by SNI but not by IP

**Layer:** Network Proxy
**Release:** MVP
**Reference:** QR-02, S2, ADR-006
**Priority:** A
**Dependent on:** STORY-03

**Technical Cut:**
Existing:
- `is_allowed_by_ip(ip, port, proto)` – `docker/proxy/entrypoint.py:181`
- `sni_ip_matches(host, ip)` – `docker/proxy/entrypoint.py:306` (async DNS verify)
- `handle_tcp` SNI-spoof check – `docker/proxy/entrypoint.py:363-367`

Tests:
- `test_sni_spoof_blocked` – Integration – blocked IP + allowed SNI → rejected + logged
- `test_sni_spoof_log_entry` – Integration – log contains "SNI-spoof"
- `test_legitimate_sni_passes` – Integration – legitimate connection still works after DNS verify

**Subtasks:**
- [ ] Verify SNI-spoof integration test is in `tests/cases/`
- [ ] Verify fail-open behavior on DNS timeout (5s timeout in sni_ip_matches)
- [ ] Verify check is NOT triggered when IP already matches ACL directly

**Context for Implementation:** `docker/proxy/entrypoint.py:181-193`, `306-316`, `363-367`
