# STORY-07: Managed policy (CLAUDE.md)
**As** Alex – Security-Conscious Developer
**I want to** Claude Code to always follow the security policy regardless of project instructions
**so that** injected prompts in project files cannot override credential access restrictions

**Acceptance Criteria:**
- [ ] `CLAUDE.md` baked into image at `/etc/claude-code/CLAUDE.md`
- [ ] File permissions: 444 (root read-only)
- [ ] Claude refuses to read `.env`, `.pem`, `~/.ssh` even with adversarial project CLAUDE.md
- [ ] Policy clearly instructs: no credential reads, no external POST/PUT, no exfiltration

**Layer:** Container
**Release:** MVP
**Reference:** QR-05, S9, ADR-004
**Priority:** B
**Dependent on:** STORY-01

**Technical Cut:**
Existing:
- `CLAUDE.md` – source policy file (repo root)
- `docker/claudius/Dockerfile:85-88` – COPY + chmod 444

Tests:
- `test_policy_not_overridable` – Integration – project CLAUDE.md override attempt fails (manual)

**Subtasks:**
- [ ] Verify CLAUDE.md is chmod 444 in built image
- [ ] Verify Claude Code loads it at system level (highest precedence)
- [ ] Document acknowledged limitation (prompt-level only) in README

**Context for Implementation:** `CLAUDE.md`, `docker/claudius/Dockerfile:85-88`
