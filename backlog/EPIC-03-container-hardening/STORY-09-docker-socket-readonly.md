# STORY-09: Docker socket read-only by default
**As** Alex – Security-Conscious Developer
**I want to** the container to be unable to mutate the host Docker daemon by default
**so that** Claude can inspect what's running without being able to start, stop, or rebuild containers

**Acceptance Criteria:**
- [ ] Host `/var/run/docker.sock` is **never** bind-mounted into the claudius container
- [ ] A Tecnativa `docker-socket-proxy:v0.4.2` sidecar runs on the per-session network with `CONTAINERS=IMAGES=INFO=NETWORKS=VOLUMES=VERSION=1` (read flags) and `POST=BUILD=0` (write flags off)
- [ ] Container reaches the proxy at `tcp://$PROXY_IP:2375` via `DOCKER_HOST` env var
- [ ] `docker ps`, `docker logs`, `docker inspect` succeed inside the container
- [ ] `docker run`, `docker stop`, `docker build` fail with HTTP 403 (proxy returns "client is forbidden")
- [ ] Setting `CLAUDIUS_DOCKER_WRITE=1` adds `POST=1 BUILD=1` and unlocks writes
- [ ] Sidecar is removed automatically when the claudius session exits

**Layer:** Docker Socket Proxy
**Release:** MVP
**Reference:** QR-13, S11, ADR-003
**Priority:** A
**Dependent on:** STORY-01

**Technical Cut:**
Existing:
- `docker/docker-socket-proxy/start.sh` – sidecar launcher (sourced by `claudius.sh`)
- `claudius.sh` `cmd_run` cleanup trap – removes the sidecar on EXIT/INT/TERM

Tests (integration):
- `test_docker_ps_works` – `docker ps` inside container returns 0
- `test_docker_run_blocked` – `docker run --rm hello-world` returns non-zero with 403 in stderr
- `test_docker_write_opt_in` – with `CLAUDIUS_DOCKER_WRITE=1`, `docker run hello-world` succeeds

**Subtasks:**
- [ ] Verify the bind-mount of `/var/run/docker.sock` exists only on the **proxy** sidecar, not on the claudius container
- [ ] Verify `DOCKER_HOST` env var is injected into the container with the resolved proxy IP
- [ ] Verify `CLAUDIUS_DOCKER_WRITE=1` flips `POST` and `BUILD` to `1` and not other write flags
- [ ] Confirm cleanup removes the sidecar even on abnormal exit (`kill -9` of the launcher)

**Context for Implementation:** `docker/docker-socket-proxy/start.sh`, `claudius.sh` `cmd_run` cleanup trap
