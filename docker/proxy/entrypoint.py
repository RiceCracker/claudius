#!/usr/bin/env python3
"""claudius-proxy – iptables setup (root) then transparent proxy.

TCP:  REDIRECT'd connections → peek TLS SNI / HTTP Host → ACL → relay.
UDP:  NFQUEUE intercept → check original dst IP:port → ACCEPT or DROP.
ICMP: NFQUEUE intercept → check original dst IP → ACCEPT or DROP.
IPv6: same as IPv4 when CLAUDIUS_SUBNET6 is set; blocked otherwise.
"""

import atexit
import asyncio
import contextlib
import fnmatch
import os
import signal
import socket
import struct
import subprocess
import sys
from datetime import datetime, timezone

from netfilterqueue import NetfilterQueue


def ts() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")


# ── Config ────────────────────────────────────────────────────────────────────

SO_ORIGINAL_DST = 80  # getsockopt option number for original dst (SOL_IP and SOL_IPV6 both use 80)
SOL_IPV6        = 41

BRIDGE_IF  = os.environ["CLAUDIUS_BRIDGE_IF"]
SUBNET     = os.environ["CLAUDIUS_SUBNET"]
SUBNET6    = os.environ.get("CLAUDIUS_SUBNET6", "")
CHAIN      = os.environ["CLAUDIUS_CHAIN"]
PROXY_PORT = int(os.environ.get("CLAUDIUS_PROXY_PORT", "1081"))
QUEUE_NUM  = PROXY_PORT  # unique per session (PROXY_PORT is unique per host PID)


# ── iptables ──────────────────────────────────────────────────────────────────

def _ipt(cmd: str, table: str):
    def run(*args: str) -> None:
        subprocess.run([cmd, "-t", table, *args], check=False,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return run

ipt_nat      = _ipt("iptables",  "nat")
ipt_mangle   = _ipt("iptables",  "mangle")
ipt6_nat     = _ipt("ip6tables", "nat")
ipt6_mangle  = _ipt("ip6tables", "mangle")
ipt6_filter  = _ipt("ip6tables", "filter")

def setup() -> NetfilterQueue:
    subprocess.run(["modprobe", "br_netfilter"], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["sysctl", "-w", "net.bridge.bridge-nf-call-iptables=1"],
                   check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["sysctl", "-w", "net.bridge.bridge-nf-call-ip6tables=1"],
                   check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    # IPv4 TCP: REDIRECT → proxy (SNI/Host ACL, proxy relays traffic)
    ipt_nat("-N", CHAIN)
    ipt_nat("-A", CHAIN, "-d", SUBNET, "-j", "RETURN")   # intra-net direct
    ipt_nat("-A", CHAIN, "-p", "tcp",  "-j", "REDIRECT", "--to-ports", str(PROXY_PORT))
    ipt_nat("-A", "PREROUTING", "-i", BRIDGE_IF, "-s", SUBNET, "-j", CHAIN)

    # IPv4 UDP + ICMP: NFQUEUE → Python ACL
    # No --queue-bypass: fail-closed (packets dropped if listener is unavailable).
    ipt_mangle("-N", f"{CHAIN}_FILTER")
    ipt_mangle("-A", f"{CHAIN}_FILTER", "-d", SUBNET, "-j", "RETURN")   # intra-net direct
    ipt_mangle("-A", f"{CHAIN}_FILTER", "-p", "udp",  "-j", "NFQUEUE", "--queue-num", str(QUEUE_NUM))
    ipt_mangle("-A", f"{CHAIN}_FILTER", "-p", "icmp", "-j", "NFQUEUE", "--queue-num", str(QUEUE_NUM))
    ipt_mangle("-A", "PREROUTING", "-i", BRIDGE_IF, "-s", SUBNET, "-j", f"{CHAIN}_FILTER")

    if SUBNET6:
        # IPv6 TCP: REDIRECT → same proxy port
        ipt6_nat("-N", CHAIN)
        ipt6_nat("-A", CHAIN, "-d", SUBNET6, "-j", "RETURN")   # intra-net direct
        ipt6_nat("-A", CHAIN, "-p", "tcp",   "-j", "REDIRECT", "--to-ports", str(PROXY_PORT))
        ipt6_nat("-A", "PREROUTING", "-i", BRIDGE_IF, "-s", SUBNET6, "-j", CHAIN)

        # IPv6 UDP + ICMPv6: NFQUEUE → same Python ACL
        ipt6_mangle("-N", f"{CHAIN}_FILTER6")
        ipt6_mangle("-A", f"{CHAIN}_FILTER6", "-d", SUBNET6, "-j", "RETURN")
        ipt6_mangle("-A", f"{CHAIN}_FILTER6", "-p", "udp",        "-j", "NFQUEUE", "--queue-num", str(QUEUE_NUM))
        ipt6_mangle("-A", f"{CHAIN}_FILTER6", "-p", "ipv6-icmp",  "-j", "NFQUEUE", "--queue-num", str(QUEUE_NUM))
        ipt6_mangle("-A", "PREROUTING", "-i", BRIDGE_IF, "-s", SUBNET6, "-j", f"{CHAIN}_FILTER6")
    else:
        # No IPv6 subnet – block all IPv6 from bridge
        ipt6_filter("-N", f"{CHAIN}_V6")
        ipt6_filter("-A", f"{CHAIN}_V6", "-j", "DROP")
        ipt6_filter("-A", "FORWARD", "-i", BRIDGE_IF, "-j", f"{CHAIN}_V6")

    # NFQUEUE verdicts require CAP_NET_ADMIN on each send, so no privilege drop.
    nfq = NetfilterQueue()
    nfq.bind(QUEUE_NUM, on_nfqueue_packet)
    return nfq

def cleanup() -> None:
    ipt_nat("-D", "PREROUTING", "-i", BRIDGE_IF, "-s", SUBNET, "-j", CHAIN)
    ipt_nat("-F", CHAIN)
    ipt_nat("-X", CHAIN)
    ipt_mangle("-D", "PREROUTING", "-i", BRIDGE_IF, "-s", SUBNET, "-j", f"{CHAIN}_FILTER")
    ipt_mangle("-F", f"{CHAIN}_FILTER")
    ipt_mangle("-X", f"{CHAIN}_FILTER")
    if SUBNET6:
        ipt6_nat("-D", "PREROUTING", "-i", BRIDGE_IF, "-s", SUBNET6, "-j", CHAIN)
        ipt6_nat("-F", CHAIN)
        ipt6_nat("-X", CHAIN)
        ipt6_mangle("-D", "PREROUTING", "-i", BRIDGE_IF, "-s", SUBNET6, "-j", f"{CHAIN}_FILTER6")
        ipt6_mangle("-F", f"{CHAIN}_FILTER6")
        ipt6_mangle("-X", f"{CHAIN}_FILTER6")
    else:
        ipt6_filter("-D", "FORWARD", "-i", BRIDGE_IF, "-j", f"{CHAIN}_V6")
        ipt6_filter("-F", f"{CHAIN}_V6")
        ipt6_filter("-X", f"{CHAIN}_V6")


# ── ACL ───────────────────────────────────────────────────────────────────────

def build_rules(allow_env: str) -> list[tuple[str, int, str]]:
    rules = []
    for entry in allow_env.split():
        if entry.endswith("/tcp"):
            proto, entry = "tcp", entry[:-4]
        elif entry.endswith("/udp"):
            proto, entry = "udp", entry[:-4]
        else:
            continue
        host, _, port_s = entry.rpartition(":")
        try:
            rules.append((host, int(port_s), proto))
        except ValueError:
            pass
    return rules


def resolve_ip_map(rules: list[tuple[str, int, str]]) -> dict[str, set[str]]:
    """Pre-resolve exact (non-wildcard) hostnames to IP sets for UDP/ICMP matching."""
    ip_map: dict[str, set[str]] = {}
    for pattern, _port, _proto in rules:
        if pattern in ip_map or "*" in pattern or "?" in pattern:
            continue
        try:
            socket.inet_aton(pattern)
            continue  # IPv4 literal
        except OSError:
            pass
        try:
            socket.inet_pton(socket.AF_INET6, pattern)
            continue  # IPv6 literal
        except OSError:
            pass
        try:
            ips = {ai[4][0] for ai in socket.getaddrinfo(pattern, None)}
            if ips:
                ip_map[pattern] = ips
        except Exception as e:
            print(f"{ts()} WARN resolve {pattern}: {type(e).__name__}: {e} – UDP rule ineffective", flush=True)
    return ip_map


def is_allowed(host: str | None, ip: str, port: int, proto: str) -> bool:
    for pattern, rule_port, rule_proto in RULES:
        if rule_port != port or rule_proto != proto:
            continue
        if pattern == "*":
            return True
        if host and fnmatch.fnmatch(host, pattern):
            return True
        if fnmatch.fnmatch(ip, pattern):
            return True
        if pattern in IP_MAP and ip in IP_MAP[pattern]:
            return True
    return False


def is_icmp_allowed(ip: str) -> bool:
    """ICMP/ICMPv6 is allowed if the destination IP matches any rule pattern."""
    for pattern, _port, _proto in RULES:
        if pattern == "*":
            return True
        if fnmatch.fnmatch(ip, pattern):
            return True
        if pattern in IP_MAP and ip in IP_MAP[pattern]:
            return True
    return False


# ── NFQUEUE (UDP + ICMP, IPv4 + IPv6) ────────────────────────────────────────

def on_nfqueue_packet(pkt) -> None:
    try:
        data    = pkt.get_payload()
        version = data[0] >> 4

        if version == 4:
            ip_hdr_len = (data[0] & 0xF) * 4
            proto  = data[9]
            dst_ip = socket.inet_ntoa(data[16:20])
        elif version == 6:
            ip_hdr_len = 40
            proto  = data[6]
            dst_ip = socket.inet_ntop(socket.AF_INET6, data[24:40])
        else:
            pkt.accept()
            return

        if proto == 17:  # UDP
            dst_port = struct.unpack_from("!H", data, ip_hdr_len + 2)[0]
            allowed  = is_allowed(None, dst_ip, dst_port, "udp")
            label    = f"udp {dst_ip}:{dst_port}"
        elif proto in (1, 58):  # ICMP / ICMPv6
            allowed = is_icmp_allowed(dst_ip)
            label   = f"{'icmpv6' if proto == 58 else 'icmp'} {dst_ip}"
        else:
            pkt.accept()
            return

        if allowed:
            print(f"{ts()} ALLOW {label}", flush=True)
            pkt.accept()
        else:
            print(f"{ts()} BLOCK {label}", flush=True)
            pkt.drop()
    except Exception:
        pkt.drop()  # fail closed


async def run_nfqueue(nfq: NetfilterQueue) -> None:
    print(f"{ts()} claudius-proxy NFQUEUE queue:{QUEUE_NUM}", flush=True)
    await asyncio.get_running_loop().run_in_executor(None, nfq.run)


# ── TCP (IPv4 + IPv6) ─────────────────────────────────────────────────────────

def get_tcp_original_dst(sock: socket.socket) -> tuple[str, int]:
    if sock.family == socket.AF_INET6:
        data = sock.getsockopt(SOL_IPV6, SO_ORIGINAL_DST, 28)
        # sockaddr_in6: family(2) + port(2) + flowinfo(4) + addr(16) + scope(4)
        port = struct.unpack_from("!H", data, 2)[0]
        addr = socket.inet_ntop(socket.AF_INET6, data[8:24])
        return addr, port
    data = sock.getsockopt(socket.SOL_IP, SO_ORIGINAL_DST, 16)
    _, port, a, b, c, d = struct.unpack_from("!HHBBBBxxxxxxxx", data)
    return f"{a}.{b}.{c}.{d}", port


def parse_sni(data: bytes) -> str | None:
    try:
        if len(data) < 6 or data[0] != 0x16:
            return None
        pos = 5
        if data[pos] != 0x01:
            return None
        pos += 4
        pos += 2 + 32
        pos += 1 + data[pos]
        cs_len = struct.unpack_from("!H", data, pos)[0]
        pos += 2 + cs_len
        pos += 1 + data[pos]
        if pos + 2 > len(data):
            return None
        ext_end = pos + 2 + struct.unpack_from("!H", data, pos)[0]
        pos += 2
        while pos + 4 <= ext_end and pos + 4 <= len(data):
            ext_type, ext_len = struct.unpack_from("!HH", data, pos)
            pos += 4
            if ext_type == 0 and pos + 5 <= len(data):
                name_len = struct.unpack_from("!H", data, pos + 3)[0]
                if pos + 5 + name_len <= len(data):
                    return data[pos + 5: pos + 5 + name_len].decode("ascii")
            pos += ext_len
    except Exception:
        pass
    return None


def parse_http_host(data: bytes) -> str | None:
    try:
        for line in data.decode("latin-1", errors="ignore").split("\r\n")[1:]:
            if line.lower().startswith("host:"):
                return line[5:].strip().split(":")[0]
    except Exception:
        pass
    return None


async def relay(src: asyncio.StreamReader, dst: asyncio.StreamWriter) -> None:
    try:
        while chunk := await src.read(65536):
            dst.write(chunk)
            await dst.drain()
    except Exception:
        pass
    finally:
        try:
            dst.close()
        except Exception:
            pass


async def handle_tcp(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
    sock = writer.get_extra_info("socket")
    try:
        orig_ip, orig_port = get_tcp_original_dst(sock)
    except OSError:
        writer.close()
        return

    try:
        head = await asyncio.wait_for(reader.read(4096), timeout=5.0)
    except (asyncio.TimeoutError, ConnectionError):
        writer.close()
        return

    if not head:
        writer.close()
        return

    sni = parse_sni(head)
    http_host = parse_http_host(head) if not sni else None
    host = sni or http_host

    if not is_allowed(host, orig_ip, orig_port, "tcp"):
        print(f"{ts()} BLOCK tcp {host or orig_ip}:{orig_port}", flush=True)
        writer.close()
        return

    print(f"{ts()} ALLOW tcp {host or orig_ip}:{orig_port}", flush=True)
    try:
        out_r, out_w = await asyncio.wait_for(
            asyncio.open_connection(orig_ip, orig_port), timeout=15.0
        )
    except Exception:
        writer.close()
        return

    out_w.write(head)
    await out_w.drain()
    await asyncio.gather(relay(reader, out_w), relay(out_r, writer))


# ── Main ──────────────────────────────────────────────────────────────────────

async def main(nfq: NetfilterQueue) -> None:
    servers = [await asyncio.start_server(handle_tcp, "0.0.0.0", PROXY_PORT)]
    if SUBNET6:
        servers.append(await asyncio.start_server(handle_tcp, "::", PROXY_PORT))

    ipv_label = "ipv4+ipv6" if SUBNET6 else "ipv4"
    print(f"{ts()} claudius-proxy TCP  listening on :{PROXY_PORT} ({ipv_label})", flush=True)

    async with contextlib.AsyncExitStack() as stack:
        for srv in servers:
            await stack.enter_async_context(srv)
        await asyncio.gather(*[srv.serve_forever() for srv in servers], run_nfqueue(nfq))


RULES  = build_rules(os.environ.get("CLAUDIUS_ALLOW", ""))
IP_MAP = resolve_ip_map(RULES)

if __name__ == "__main__":
    signal.signal(signal.SIGTERM, lambda s, f: sys.exit(0))
    nfq = setup()
    atexit.register(cleanup)
    asyncio.run(main(nfq))
