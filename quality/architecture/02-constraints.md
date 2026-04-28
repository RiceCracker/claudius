# § 2 Constraints

## Technical Constraints

| Constraint | Reason |
|---|---|
| Docker Engine required | claudius is a Docker orchestration tool; no fallback runtime |
| Linux for gVisor | gVisor (`runsc`) has no Docker integration on macOS/Windows; gVisor is opt-in |
| Node.js 22 base image | Claude Code's native installer targets Node 22; Debian Bookworm for apt compatibility |
| Host UID/GID must be passed explicitly | Container runs as the host user to avoid file ownership mismatches on bind mounts |
| `--cap-drop ALL` baseline | Capabilities are bounded even with `CLAUDIUS_SUDO=1`; only `CHOWN`, `DAC_OVERRIDE`, `FOWNER`, `SETUID`, `SETGID`, `SETPCAP`, `NET_RAW` are added back |
| `--host-uds=open` for gVisor | Required so the clipboard / SSH / GPG Unix sockets forward through `runsc` (set by `make gvisor-install`) |

## Organisational Constraints

| Constraint | Reason |
|---|---|
| Single developer / small team | No distributed ownership; no review process enforced |
| No cloud deployment | Local dev tool only; no SaaS infrastructure, no CI/CD environment |
| Claude Code is a black box | claude binary from official installer; no source access; behaviour documented via CLAUDE.md policy |

## Conventions

- Shell scripts: `set -e` (fail-fast); `set -u` (unbound variable guard) where appropriate
- Docker containers: `--rm` always set; no persistent container state outside bind mounts
- Cleanup: always via `trap cleanup EXIT INT TERM` in launcher
- Configuration: env vars with `CLAUDIUS_` prefix; `.env` file optional
