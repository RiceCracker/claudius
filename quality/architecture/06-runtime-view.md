# § 6 Runtime View

## RT-1: Container Launch (S4)

```
Developer          claudius.sh        docker              claudius-docker-$$    claudius-$$
    │                   │                │                       │                  │
    │ claudius ~/proj   │                │                       │                  │
    │──────────────────▶│                │                       │                  │
    │                   │ load .env       │                       │                  │
    │                   │ ensure image    │                       │                  │
    │                   │ network create  │                       │                  │
    │                   │────────────────▶│                       │                  │
    │                   │ start clipboard daemon (host)           │                  │
    │                   │ start docker-socket-proxy               │                  │
    │                   │────────────────▶│ run sidecar           │                  │
    │                   │ resolve PROXY_IP from socket-proxy      │                  │
    │                   │ docker run (cap-drop, resource limits, mounts, DOCKER_HOST=…) │
    │                   │────────────────▶│                       │                  │
    │                   │                 │ entrypoint.sh (root)  │                  │
    │                   │                 │──────────────────────────────────────▶  │
    │                   │                 │ user setup → resolv.conf → user-init →  │
    │                   │                 │ git init home → gosu (setpriv) → claude │
    │◀──────────────────────────────────────────────────────────────────────────────│
```

## RT-2: Outbound Request (post-ADR-007)

```
Claude Code        Docker bridge          Internet
    │                    │                    │
    │ HTTPS / DNS / etc.  │                    │
    │───────────────────▶│ NAT to host IP     │
    │                    │───────────────────▶│
    │                    │ response           │
    │◀────────────────────────────────────────│
```

There is no proxy in the path. Outbound traffic is NAT'd through the Docker bridge like any other container. If host-layer filtering exists (firewall, VPN), it applies; otherwise traffic is unrestricted.

## RT-3: Docker Socket Read

```
Claude Code        Docker bridge       claudius-docker-$$    Docker daemon
    │                    │                    │                  │
    │ docker ps          │                    │                  │
    │───────────────────▶│                    │                  │
    │                    │ TCP :2375          │                  │
    │                    │───────────────────▶│                  │
    │                    │                    │ verb allowed?    │
    │                    │                    │ (CONTAINERS=1)   │
    │                    │                    │───── yes ───────▶│
    │                    │                    │ result            │
    │◀────────────────────────────────────────│                  │
    │                                         │                  │
    │ docker run …       │                    │ verb allowed?    │
    │───────────────────▶│                    │ (POST=0 default) │
    │                    │                    │──── 403 ─────▶ X │
    │◀── 403 forbidden ─────────────────────── │                  │
```

## RT-4: Cleanup on Exit

```
Developer         claudius.sh         claudius-docker-$$        claudius-$$
    │ Ctrl+C / exit   │                       │                      │
    │────────────────▶│                       │                      │
    │             trap cleanup                │                      │
    │                 │ docker rm -f socket-proxy                    │
    │                 │──────────────────────▶│                      │
    │                 │ docker network rm claudius-$$                │
    │                 │ kill clipboard host daemon                    │
    │                 │ rm -rf clipboard tempdir                     │
```

The main `claudius-$$` container is started with `--rm`; Docker removes it automatically when the entrypoint exits or is signalled.
