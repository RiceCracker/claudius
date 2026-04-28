# Glossary – claudius

**Sandbox**
Definition: An isolated Docker container that runs Claude Code with a restricted filesystem mount whitelist, dropped Linux capabilities, and (optionally) gVisor as the runtime. The sandbox is the core product unit.
Distinction: Not a VM — shares the host kernel unless gVisor is used. Not a general-purpose container — purpose-built for Claude Code with a curated toolchain.

**gVisor**
Definition: Google's user-space kernel (`runsc`) that intercepts all syscalls between the container and the host kernel. In claudius an optional runtime (`CLAUDIUS_RUNTIME=runsc`) — strongest isolation short of a full VM.

**Privilege Drop**
Definition: The handoff in `entrypoint.sh` from the root entrypoint process to the unprivileged host user via `gosu $HOST_USER` (and `setpriv --no-new-privs` unless `CLAUDIUS_SUDO=1`). No root parent remains in the container's PID tree afterwards.

**no_new_privs**
Definition: A Linux kernel flag (`PR_SET_NO_NEW_PRIVS`) that prevents a process and its descendants from acquiring new privileges via `execve()` — including disabling the setuid bit on binaries like `sudo` and `mount`. Set by claudius via `setpriv --no-new-privs` during the privilege drop unless `CLAUDIUS_SUDO=1` (in which case it's omitted so sudo's setuid bit can fire).
Distinction: A kernel guarantee, not a policy convention — it cannot be lifted from inside the container, only at launch time.

**Docker Socket Proxy**
Definition: A `docker-socket-proxy` (Tecnativa) sidecar reachable via the per-session Docker network. Provides filtered access to the host Docker daemon — read-only by default (`docker ps`, `logs`, `inspect`, `info`); writes (`run`, `build`, `stop`) require `CLAUDIUS_DOCKER_WRITE=1`. The raw socket is never bind-mounted into the claudius container.

**Capability Drop**
Definition: `--cap-drop ALL` plus selective re-add applied to the claudius container. Retained: `CHOWN`, `DAC_OVERRIDE`, `FOWNER`, `SETUID`, `SETGID`, `SETPCAP`, `NET_RAW`. Capabilities stay bounded even with `CLAUDIUS_SUDO=1`.

**Managed Policy**
Definition: The `CLAUDE.md` file in the repo root, bind-mounted read-only at `/etc/claude-code/CLAUDE.md`. Claude Code loads it at the highest precedence — project-level and user-level instructions cannot override it. Prompt-level enforcement only, not technical.

**User-Init Hook**
Definition: An optional shell script (`CLAUDIUS_USER_INIT=...`) bind-mounted read-only at `/etc/claudius/user-init.sh` and executed as root before the privilege drop. Used for per-session config (git identity, aliases, env vars). Not for package installation — use a custom image (`FROM claudius`) for that.

**Clipboard Bridge**
Definition: A host-side Python daemon (`docker/clipboard/host.py`) listening on a per-session Unix socket; the container's `claudius-clip` shim (aliased as `xclip`/`xsel`/`wl-copy`/`wl-paste`/`pbcopy`/`pbpaste`) talks a 1-byte protocol to it. No X11 or Wayland socket is ever exposed.

**Per-Session Network**
Definition: An isolated Docker network named `claudius-$$` (host PID) created at session start. Hosts the docker-socket-proxy sidecar and the claudius container so the container can reach the proxy by IP. Removed at exit.

**Opt-in Risk**
Definition: A feature that expands the attack surface but is disabled by default. Examples: `CLAUDIUS_SSH=1` (mounts the host SSH agent socket), `CLAUDIUS_GPG=1` (mounts the host GPG agent socket), `CLAUDIUS_SUDO=1` (sudoers entry + lifts `--no-new-privs`), `CLAUDIUS_DOCKER_WRITE=1` (enables Docker writes).
