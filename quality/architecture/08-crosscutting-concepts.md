# § 8 Crosscutting Concepts

## Naming Conventions

Derived from `quality/glossary.md`:

| Context | Convention | Examples |
|---|---|---|
| Env vars | `CLAUDIUS_` prefix, UPPER_SNAKE | `CLAUDIUS_DNS`, `CLAUDIUS_SUDO`, `CLAUDIUS_RUNTIME`, `CLAUDIUS_DOCKER_WRITE` |
| Docker container names | `claudius-$$` (session-scoped with host PID) | `claudius-1234` (main), `claudius-docker-1234` (socket proxy) |
| Docker network names | `claudius-$$` | `claudius-1234` |
| Shell functions | snake_case, imperative verbs | `cleanup`, `cmd_run`, `cmd_doctor`, `_have_clipboard_tool` |
| Python (clipboard daemon) | snake_case, stdlib only | `host.py`, `client.py` |
| Sourced helpers | `start.sh` for sidecar startup | `docker/docker-socket-proxy/start.sh` |

## Code Structure Guidelines

- **Single responsibility per file:** `claudius.sh` orchestrates only — sources `start.sh` helpers for sidecar lifecycle. `entrypoint.sh` owns user setup + privilege drop. `Dockerfile` owns image composition.
- **No framework dependencies:** every tool used is stdlib (bash, Python `socket`/`asyncio`, Docker CLI). No Flask, no Twisted, no requests.
- **Sourced scripts over functions in launcher:** `start.sh` helpers are sourced into the launcher's shell context to share variables (`PROXY`, `NET`, `PROXY_IP`).
- **Docker-first:** every component is a container or a host-side bridge daemon. No systemd services, no host package installs (except Docker itself).

## Error Handling

| Layer | Pattern |
|---|---|
| Launcher (`claudius.sh`) | `set -e` — any error exits immediately; `trap cleanup EXIT INT TERM` ensures cleanup always runs |
| Socket-proxy startup (`docker-socket-proxy/start.sh`) | Failure to resolve `PROXY_IP` makes the launcher exit; cleanup trap removes partial state |
| `entrypoint.sh` | `set -e`; individual commands use `|| true` where failure is expected (e.g. `userdel`, `chown .claude.json`) |
| Clipboard daemon (`host.py`) | Bind failures cause the launcher to warn and disable clipboard; container side falls back gracefully |

## Logging

| Layer | Format | Level |
|---|---|---|
| Launcher | Human-readable status to stdout (`✓` / `⚠` / `✗`) | Startup, errors |
| Entrypoint | Banner + forwarding hints to stdout | Startup only |
| Docker socket proxy | Tecnativa default (HTTP request log) | Per request — viewable via `docker logs claudius-docker-$$` |

No structured logging (JSON). No log aggregation. Outbound network traffic produces no logs at all by design — there is no proxy in the path.

## Security Model

- **Least privilege by default:** all opt-ins disabled. `--cap-drop ALL` baseline. `--no-new-privs` set. Docker socket read-only.
- **Defence in depth:** CLAUDE.md (prompt) + capability drop (kernel) + privilege drop (user) + Docker-socket filter (Docker API) + gVisor optional (syscall).
- **No secrets in code or logs:** `entrypoint.sh` never echoes `CLAUDIUS_*` values; the docker-socket-proxy logs verbs, not bodies.
- **Network is explicitly out of scope** (ADR-007). Users who need egress filtering apply it at the host or runtime layer.

## Session Isolation

Each `claudius` invocation creates a unique container name (`claudius-$$`), unique socket-proxy name (`claudius-docker-$$`), unique Docker network (`claudius-$$`), and unique clipboard temp dir. Multiple concurrent sessions on the same host do not interfere.
