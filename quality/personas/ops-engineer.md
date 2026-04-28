# Persona: Ops Engineer (DevOps / Maintainer)

**Role:** The person building, extending, or maintaining the claudius image
**Goal:** Add language servers or custom tools (Go, Flutter, Rust) to the base image without breaking the security model. Needs to understand which opt-ins are safe to combine.
**Context:** Typically the same person as Daniel or Alex — hat-switching. Creates custom Dockerfiles, writes `user-init.sh` hooks, sets up gVisor.
**Pain Points:**
- Custom Dockerfile changes that silently break the privilege drop chain (`gosu` missing, `setpriv` not in PATH, etc.)
- Forgetting `--host-uds=open` in the Docker daemon config after a reinstall — clipboard / SSH / GPG forwarding silently fails under gVisor
- Understanding the risk model before enabling `CLAUDIUS_SUDO=1` + `CLAUDIUS_DOCKER_WRITE=1` — combined, this is host-root
**Tech Level:** Expert (Docker/Linux internals)
