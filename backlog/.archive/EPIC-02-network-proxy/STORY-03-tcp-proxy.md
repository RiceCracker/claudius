# STORY-03: TCP transparent proxy with SNI/Host ACL
**As** Alex – Security-Conscious Developer
**I want to** have all outbound TCP filtered by hostname/SNI with wildcard support
**so that** Claude cannot make unauthorized HTTPS calls

**Acceptance Criteria:**
- [ ] `*.anthropic.com:443/tcp` always allowed
- [ ] Unmatched hosts refused in < 1s
- [ ] Wildcard (`*.npmjs.org`) and exact (`api.github.com`) ACL entries work
- [ ] HTTP Host header used as fallback when no TLS SNI
- [ ] Proxy log shows ALLOW/BLOCK for every decision

**Layer:** Network Proxy
**Release:** MVP
**Reference:** QR-01, S1
**Priority:** A
**Dependent on:** STORY-01

**Technical Cut:**
Existing:
- `build_rules(allow_env)` – `docker/proxy/entrypoint.py:124`
- `is_allowed(host, ip, port, proto)` – `docker/proxy/entrypoint.py:166`
- `parse_sni(data)` – `docker/proxy/entrypoint.py:266`
- `parse_http_host(data)` – `docker/proxy/entrypoint.py:296`
- `handle_tcp(reader, writer)` – `docker/proxy/entrypoint.py:333`

Tests:
- `test_blocked_host_refused` – Integration – connection to unmatched host refused in < 1s
- `test_allowed_wildcard` – Integration – `*.npmjs.org` wildcard match
- `test_proxy_log_entries` – Integration – ALLOW/BLOCK in proxy log

**Subtasks:**
- [ ] Verify wildcard ACL works in integration tests
- [ ] Verify HTTP Host fallback (non-TLS)
- [ ] Verify proxy log completeness (every verdict logged)
- [ ] Verify response time < 1s for blocked connections

**Context for Implementation:** `docker/proxy/entrypoint.py:124-380`
