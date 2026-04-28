# Vision – claudius

## User Text (Distilled from README + Codebase)

> claudius is built to contain risk without getting in the way. A hardened sandbox for your local dev workstation that lets Claude Code do its job while keeping the host safe. Locked down by default at the container layer; Docker access, SSH, clipboard, and sudo are all opt-in risks you control. Outbound network is unrestricted — if you need filtering, run claudius behind your existing tooling.

## Distillation

**Core Purpose (one sentence):**
claudius is a curated Docker sandbox that runs Claude Code with a tight filesystem, capability, and Docker-socket boundary, plus optional gVisor — leaving network egress as the user's host-layer decision.

**Target Audience:**
Individual developers using Claude Code locally who want meaningful protection against accidental file access, runaway Docker commands, and host-environment leakage — without owning a network-filtering stack.

**Central Promise:**
"At the container layer, locked down by default. Every host-touching feature (clipboard, SSH, GPG, Docker writes, sudo) is opt-in and documented. Network filtering is explicitly out of scope — you bring your own."

**What Makes It Special:**
- Curated container image: Claude Code (native installer), language servers (pyright, typescript-language-server, bash-language-server, yaml-language-server, sql-language-server, vscode-langservers-extracted), Gemini MCP, ruff, starship, docker CLI — all pre-installed
- Read-only Docker socket via Tecnativa proxy — Claude can inspect (`docker ps`, `logs`, `inspect`) without being able to mutate
- Clipboard bridge over Unix socket — bidirectional clipboard without exposing X11 / Wayland sockets
- gVisor opt-in: user-space kernel intercepts every syscall, strongest isolation short of a VM
- Privilege drop via `gosu` + `setpriv --no-new-privs`, capability bounding set kept tight even with `CLAUDIUS_SUDO=1`
- Managed CLAUDE.md mounted read-only at `/etc/claude-code/CLAUDE.md` (highest precedence in Claude's config hierarchy) — prompt-level guardrails the user inside the container cannot mutate
- Linux + macOS: works the same on both (no platform-specific filtering layer)
- Extensible via Dockerfile inheritance (`FROM claudius`) or runtime init hook
- Minimal friction: `make install` + `claudius` — no allow-list to maintain, no config required for the default case

**What it explicitly is not:**
A network-filtering tool. The proxy that filtered TCP/UDP/ICMP and inspected SNI was removed in 2026-04-28 (ADR-007). If a user needs egress filtering, the right layer is the host firewall, a VPN, a DNS sinkhole, or runtime-layer policies — not claudius.
