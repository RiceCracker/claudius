# STORY-08: Custom image via Dockerfile inheritance
**As** Ops Engineer
**I want to** add language toolchains via `FROM claudius` + `CLAUDIUS_IMAGE=my-image`
**so that** I can use Go/Flutter/Rust projects without modifying the core image

**Acceptance Criteria:**
- [ ] `Dockerfile.go.example`: `go build` and `gopls` work
- [ ] `Dockerfile.flutter.example`: `flutter analyze` and Dart LSP work
- [ ] `Dockerfile.rust.example`: `cargo build` and `rust-analyzer` work
- [ ] Network proxy and security model unchanged in extended images

**Layer:** Container Image
**Release:** MVP
**Reference:** QR-09, S8
**Priority:** B
**Dependent on:** STORY-01

**Technical Cut:**
Existing:
- `docker/claudius/Dockerfile.go.example`
- `docker/claudius/Dockerfile.flutter.example`
- `docker/claudius/Dockerfile.rust.example`

Tests:
- `test_go_toolchain` – Integration (manual) – `go version` in custom image
- `test_gopls_available` – Integration (manual) – `gopls version` returns output

**Subtasks:**
- [ ] Verify Go example builds cleanly on x86_64 and arm64
- [ ] Verify Flutter example includes Android SDK
- [ ] Verify Rust example includes rust-analyzer
- [ ] Verify proxy/security not broken in extended images

**Context for Implementation:** `docker/claudius/Dockerfile.*.example`
