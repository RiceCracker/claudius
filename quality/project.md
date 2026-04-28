# Project Description – claudius

**Type:** Developer tool / isolation sandbox (local workstation)
**Context:** External open-source tool, no industry compliance (GDPR: no personal data processed by the tool itself)

---

## Core Process

**Loop 1 – Container Launch**
**Input:** `claudius [project-dir] [command]` — shell invocation by the developer
**Processing:**
1. Load `.env` config; resolve DNS resolvers + feature flags
2. Ensure the claudius image exists (auto-build on first run)
3. Create per-session Docker network (`claudius-$$`, with `--ipv6` if Docker supports it, IPv4 fallback)
4. Optionally start the host-side clipboard daemon and bind-mount its Unix socket
5. Start the docker-socket-proxy sidecar on the per-session network (read-only by default; `POST=BUILD=1` only when `CLAUDIUS_DOCKER_WRITE=1`); resolve its bridge IP
6. `docker run` the main container: capability drops, resource limits, mount whitelist, `DOCKER_HOST` pointing at the socket proxy, optional gVisor runtime
7. `entrypoint.sh` (root): provision host user inside the container, write `/etc/resolv.conf` from `CLAUDIUS_DNS`, run user-init hook (if mounted), `git init` in `$HOME` (gVisor workaround), drop privileges via `gosu` + (optionally) `setpriv --no-new-privs`, exec Claude Code in `$HOME/$PROJECT_NAME`
**Output:** Claude Code running as the host user inside an isolated container; project dir writable on both sides; outbound network reaches the internet via the Docker bridge unmodified

**Loop 2 – Cleanup**
**Input:** Claude exits / Ctrl+C / kill of the launcher
**Processing:**
1. `trap cleanup` fires on EXIT/INT/TERM
2. Remove the docker-socket-proxy sidecar
3. Remove the per-session Docker network
4. Kill the clipboard host daemon and remove its temp dir
5. Main container removed by Docker (started with `--rm`)
**Output:** No orphaned containers, networks, sockets, or temp dirs on the host

---

## System Layers

| Layer | Technology (set) | Prio | Dependent on | Docker Container | src/ Directory |
|---|---|---|---|---|---|
| Launcher | Bash | 1 | – | – | `claudius.sh`, `docker/docker-socket-proxy/start.sh` |
| Container Image | Dockerfile + bash entrypoint | 1 | Launcher | `claudius-$$` | `docker/claudius/` |
| Docker Socket Proxy | `tecnativa/docker-socket-proxy:v0.4.2` | 2 | Launcher | `claudius-docker-$$` | `docker/docker-socket-proxy/` |
| Clipboard Bridge | Python 3 (stdlib) | 2 | Launcher | – (host daemon + container shim) | `docker/clipboard/` |
| Extension Examples | Dockerfile (Go, Flutter, Rust) | 3 | Container Image | custom | `docker/claudius/Dockerfile.*.example` |

---

## Deployment & Operation

| Environment | Containerization | Orchestration | Operator |
|---|---|---|---|
| Local dev (Linux) | Docker (runc default; runsc/gVisor opt-in) | `claudius.sh` (bash) | Developer |
| Local dev (macOS) | Docker Desktop (Linux VM) | `claudius.sh` (bash) | Developer |
| Non-interactive / CI | Docker | `claudius bash -c '…'` | Developer / CI |

No cloud deployment — local tool only.

---

## External Dependencies & Compatibility

| Dependency | Type | Version (min) | Platform | Compatibility Risk |
|---|---|---|---|---|
| Docker Engine | Runtime | 20.x | Linux + macOS | Low — standard tooling; runs identically on both since the network proxy was removed |
| gVisor (`runsc`) | Optional runtime | latest | Linux only (x86_64/arm64) | Medium — requires `--host-uds=open` for socket forwarding; not available on macOS |
| Tecnativa docker-socket-proxy | Container image | v0.4.2 | – | Low — pinned version; image pulled at run time |
| Claude Code | Embedded | latest (native installer) | Linux | Low — auto-updated by `make rebuild` |
| Gemini MCP (@rlabs-inc/gemini-mcp) | npm | latest | Linux | Low |
| node:22-bookworm-slim | Base image | node:22 | Linux | Low |

---

## MCPs (project relevant)

| MCP | Purpose | Scope |
|---|---|---|
| @rlabs-inc/gemini-mcp | 30+ Gemini tools baked into image | Available to end users of the sandbox |

---

**Docker Network:** `claudius-$$` (per-session, IPv4 + optional IPv6)
**docker-compose.yml:** Not used — launcher manages all containers via `docker run`

---

## Testing Strategy

| Layer | Approach | Framework |
|---|---|---|
| Container launch + mounts | Integration smoke test (`reachable`/`unreachable` assertions) | bash (`tests/integration.sh`) |
| Outbound reachability | Integration (curl to known hosts) | bash |
| DNS resolution | Integration (`getent hosts …`) | bash |
| Docker socket proxy boundary | Integration (`docker ps` works, `docker run` rejected) | bash |
| Privilege drop (S12) | Integration (`cat /proc/$$/status \| grep NoNewPrivs`) | bash — *to be added* |
| Resource limits + OOM (S3) | Manual / smoke | – |
| gVisor | Manual | – |

**Coverage Goal:** All A-scenarios covered by integration tests where automatable (S6, S11, S12 — automatable; S3, S4 — manual smoke). No unit tests — the codebase is infrastructure scripts plus a small Python clipboard daemon.
