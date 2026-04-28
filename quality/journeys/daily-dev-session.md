# Journey: Daily Dev Session

**Persona:** Daniel – Developer
**Goal:** Work on a project with Claude Code; files changed on host; container drops cleanly when done.
**Trigger:** `claudius ~/my-project`
**Release:** MVP

## Steps

1. Developer runs `claudius ~/my-project` → launcher loads `.env`, builds image if missing (~2 min once)
2. Network setup: launcher creates `claudius-$$` Docker network and starts the docker-socket-proxy sidecar (read-only by default)
3. Container starts: entrypoint provisions the host user inside the container, writes `/etc/resolv.conf` from `CLAUDIUS_DNS`, drops privileges via `gosu` + `setpriv --no-new-privs`, execs Claude Code in the project subdirectory
4. Claude modifies files → changes visible on host immediately via the bind mount, ownership matches host UID/GID
5. Claude makes outbound calls (Anthropic API, GitHub, npm, pip, …) → reach the internet through the Docker bridge unmodified; if the host has firewall / VPN / DNS filtering, that applies
6. `docker ps` from inside the container works (read-only socket proxy); `docker run` is rejected with HTTP 403 unless `CLAUDIUS_DOCKER_WRITE=1`
7. Developer types `/exit` → drops to bash shell → exits → trap `cleanup` removes the socket-proxy sidecar and the Docker network; the main container removed itself via `--rm`

## Variants / Exceptions

- Image not yet built → auto-build triggered (~2 min); developer sees progress message
- `CLAUDIUS_RUNTIME=runsc` set → main container runs under gVisor; clipboard/SSH/GPG forwarding still work via Unix-socket bridges (requires `--host-uds=open` in daemon config — set by `make gvisor-install`)
- `CLAUDIUS_SUDO=1` → sudoers entry written for `CLAUDIUS_SUDO_CMDS`; `--no-new-privs` is not set so `sudo` works; capability set still bounded
- Clipboard host tooling missing (no `xclip+DISPLAY` and no `wl-clipboard+WAYLAND_DISPLAY`) → launcher warns, clipboard disabled; Claude runs without copy/paste
- Two parallel sessions — both work; `claudius-$$` per-session naming prevents collisions

## Open Questions

- (none — all edge cases covered in README + `docs/security.md`)
