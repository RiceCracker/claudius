# § 12 Glossary

See `quality/glossary.md` for full definitions. Key terms:

| Term | Short Definition |
|---|---|
| Sandbox | Isolated Docker container running Claude Code with mount whitelist + capability drop |
| gVisor | Optional user-space kernel (`runsc`); intercepts all syscalls |
| Privilege Drop | `gosu` + optional `setpriv --no-new-privs`; no root parent after start |
| no_new_privs | Linux kernel flag (`PR_SET_NO_NEW_PRIVS`) blocking setuid escalation; set unless `CLAUDIUS_SUDO=1` |
| Docker Socket Proxy | Tecnativa filtered proxy on the per-session network; read-only by default |
| Capability Drop | `--cap-drop ALL` + selective re-add (CHOWN, DAC_OVERRIDE, FOWNER, SETUID, SETGID, SETPCAP, NET_RAW) |
| Managed Policy | `CLAUDE.md` at `/etc/claude-code/CLAUDE.md`; highest-precedence prompt instructions |
| User-Init Hook | Optional root shell script run before privilege drop |
| Clipboard Bridge | Host-side Python daemon brokering copy/paste over a per-session Unix socket |
| Per-Session Network | Isolated Docker network `claudius-$$` hosting the docker-socket-proxy and the main container |
| Opt-in Risk | Feature disabled by default; expands attack surface only when explicitly enabled (`CLAUDIUS_SSH`, `CLAUDIUS_GPG`, `CLAUDIUS_SUDO`, `CLAUDIUS_DOCKER_WRITE`) |
