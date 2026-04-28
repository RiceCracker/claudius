# STORY-10: Clipboard bridge without exposing the host display server
**As** Daniel – Developer
**I want to** copy and paste between the container and the host
**so that** Claude Code's tool output is usable in everyday workflows without exposing the X11 / Wayland socket

**Acceptance Criteria:**
- [ ] When `CLAUDIUS_CLIPBOARD=1` (default) and the host has `xclip+DISPLAY` *or* `wl-clipboard+WAYLAND_DISPLAY`, the launcher starts a per-session host daemon (`docker/clipboard/host.py`) bound to a Unix socket in a session-scoped temp dir
- [ ] The Unix socket is bind-mounted at `/run/claudius/clipboard.sock` inside the container
- [ ] Inside the container, `claudius-clip` (`docker/clipboard/client.py`) is symlinked as `xclip`, `xsel`, `wl-copy`, `wl-paste`, `pbcopy`, `pbpaste`; all six proxy through the socket
- [ ] Read protocol: container sends `r` byte, daemon returns clipboard bytes
- [ ] Write protocol: container sends `w` byte + payload, daemon writes to host clipboard
- [ ] No X11 or Wayland socket is bind-mounted into the container at any point
- [ ] On launcher exit, the trap kills the daemon and deletes the temp dir
- [ ] Setting `CLAUDIUS_CLIPBOARD=0` skips the bridge entirely; the shims fail gracefully

**Layer:** Clipboard Bridge
**Release:** MVP
**Reference:** QR-04 (minimal host exposure), QR-08 (zero-config)
**Priority:** B
**Dependent on:** STORY-01

**Technical Cut:**
Existing:
- `docker/clipboard/host.py` – host-side daemon (asyncio + socket, stdlib only)
- `docker/clipboard/client.py` – container-side shim (installed as `claudius-clip` and aliased)
- `claudius.sh` `cmd_run` – clipboard tool detection + daemon lifecycle + bind-mount wiring

Tests:
- `test_clipboard_round_trip` – Manual or shell-driven: write a string from the container, read it back; verify host clipboard has it
- `test_clipboard_disabled` – `CLAUDIUS_CLIPBOARD=0` → shim fails, no daemon process running
- `test_no_x11_socket` – container `ls /tmp/.X11-unix/` returns empty; container `env | grep DISPLAY` is empty

**Subtasks:**
- [ ] Verify `_have_clipboard_tool` correctly detects Wayland *and* X11 environments
- [ ] Verify the daemon is killed on launcher SIGTERM (no zombie processes)
- [ ] Verify the temp dir is removed even on `kill -9` of the launcher (best-effort acceptable)

**Context for Implementation:** `docker/clipboard/host.py`, `docker/clipboard/client.py`, `claudius.sh` `cmd_run` — clipboard section
