# Market Research – claudius
> AI Agent Sandbox Landscape, re-evaluated 2026-04-28 after ADR-007.
>
> **Reframing note:** Earlier versions of this document positioned claudius around its in-process network proxy (transparent SNI relay, NFQUEUE UDP/ICMP, SNI anti-spoof). After ADR-007 those features are gone. claudius now competes on **isolation hygiene** (capabilities, privilege drop, gVisor option, Docker socket boundary, clipboard bridge) — not on egress filtering.

## Comparable Solutions

| Tool / Product | Isolation | Network Filtering | Local/Cloud | Setup | Strengths | Weaknesses | Differenzierungspotenzial vs. claudius |
|---|---|---|---|---|---|---|---|
| **Docker Sandboxes** (Docker Desktop ≥4.50) | MicroVM (macOS/Win) | HTTP/HTTPS proxy, domain allowlist | Local | Very low (`docker sandbox run`) | Official, zero-config, microVM isolation; built-in egress proxy | macOS/Win only for microVM; Linux gets container fallback; Docker Desktop license required | Docker Sandboxes ships network filtering; claudius does not. Different scope: filtering tool vs. isolation tool |
| **Claude Code native /sandbox** | Bubblewrap (Linux) / Seatbelt (macOS) | Unix socket → host proxy | Local | Zero (built-in) | Zero install; Anthropic-maintained; ~84% fewer prompts | Doesn't work inside Docker (breaks claudius `/sandbox`); Seatbelt deprecated; no container isolation | Different layer: claude-native sandboxes the Claude process, claudius sandboxes the whole shell environment |
| **anthropic-experimental/sandbox-runtime (srt)** | Bubblewrap / Seatbelt | Host proxy, domain allowlist | Local | Low (`npm install -g`) | Official beta; `SandboxManager` API for embedding | Bubblewrap ≠ strong isolation; beta/experimental | claudius offers the full container boundary plus optional gVisor |
| **textcortex/claude-code-sandbox** | Docker container | None | Local | Moderate | File-copy isolation (snapshot semantics) | Archived Feb 2026; no egress control; no privilege drop | claudius is actively maintained, has the privilege drop chain and the Docker-socket proxy |
| **mattolson/agent-sandbox** | Docker + mitmproxy sidecar | Domain allowlist via TLS termination | Local | Moderate | YAML policy; multi-agent support | TLS-terminating MITM (CA cert injected); early dev; no gVisor | If you want filtering, this is the local Docker-based alternative; claudius deliberately stays out of that space |
| **E2B** | Firecracker microVM | None (full egress) | Cloud | Low | Strongest isolation (Firecracker); SDK | Cloud-only; data leaves machine; latency ~200 ms; per-CPU pricing | claudius is local; no data leaves the host |
| **Daytona** | Docker container | None | Cloud | Moderate | Native Git, LSP, SSH access | Cloud; no egress control | claudius is local + has the docker-socket proxy boundary |
| **Modal** | Custom containers | Egress policies | Cloud | Low | Production scale; egress controls | Cloud platform, not local dev | Different audience |
| **Dagger container-use** | Docker + Git worktrees | Not documented | Local/CI | Low | Parallel agent execution; CI-native | Early dev; security hardening not the goal | claudius is security-first vs. parallelism-first |
| **gVisor (`runsc`)** | User-space kernel | None (layer separately) | Local runtime | Low | Strong syscall isolation; Google-maintained | Not a complete sandbox by itself | claudius integrates gVisor as an opt-in runtime — packaged solution rather than a primitive |
| **Lima / INNOQ approach** | Full VM | Manual iptables | Local (macOS) | High | Strongest overall isolation | Heavy; macOS-only; manual plumbing | claudius is lighter and Linux-native |

---

## Market Standards & Established Patterns

### Pattern 1: MicroVM on macOS, Containers on Linux
Docker Sandboxes uses microVMs (macOS/Windows) where containers don't provide kernel isolation. On Linux, gVisor is the standard upgrade path. claudius follows this pattern: runc by default, runsc opt-in.

### Pattern 2: Privilege drop with no root parent
`gosu`/`tini` based exec hand-off is the established Docker primitive — used by official images (postgres, redis, …) and by every serious agent sandbox. claudius matches.

### Pattern 3: Docker socket exposure via filtering proxy
Tools that need Docker-API access from inside an agent container converge on a filtering proxy (Tecnativa being the de-facto standard). claudius uses the same component.

### Pattern 4: No host display socket
The X11 / Wayland socket is a known escape vector. The current convention is to broker copy/paste over a separate Unix-socket bridge or skip clipboard entirely. claudius implements the bridge.

### Pattern 5: Network filtering — *not* a universal pattern
Looking at the table above: Claude Code native and anthropic srt do filter outbound; Docker Sandboxes does too. textcortex, Daytona, Dagger, Lima, gVisor itself, and now claudius do *not*. The space is genuinely split — there isn't one industry-standard answer to "should the sandbox filter egress or delegate to the host?"

---

## Insights for this Project

1. **Post-ADR-007 the differentiator changes.** Pre-ADR-007 claudius's value prop was "transparent egress proxy with SNI anti-spoof + UDP/ICMP fail-closed". That was unique. Post-refactor, claudius is "curated container + privilege drop + Docker-socket proxy + gVisor option + clipboard bridge". That's *not* unique — but it is a coherent, opinionated bundle. Communicate the bundle, not the pieces.

2. **The audience shifts slightly.** Alex (the security-conscious developer) was sold on "I can prove no traffic leaves the perimeter". Now Alex is sold on "the host is protected from a misbehaving Claude". Different sale; same persona. The README + docs/security.md need to reflect this.

3. **Docker Sandboxes is no longer a head-to-head competitor.** Pre-ADR-007 they overlapped on filtering. Now Docker Sandboxes (filtering + microVM) and claudius (curated isolation, Linux-first) live in different lanes. Comparison page should make that clear instead of competing on lanes claudius vacated.

4. **The extension story stays the strongest USP.** `FROM claudius` in a Dockerfile + the `CLAUDIUS_USER_INIT` hook is more flexible than any "official" Anthropic sandbox provides. Worth keeping prominent.

5. **Backlog opportunity (still open):** if the project ever wants egress filtering back, the right shape post-ADR-007 is probably a *separate* opt-in tool (`claudius-firewall` host service?) layered on top — not a re-merge into the launcher. Out of scope for now.
