#!/usr/bin/env bash
# claudius integration tests – end-to-end network filtering.
#
# Two runs:
#   Run 1 (with proxy)    – allowed hosts reachable, blocked hosts blocked,
#                           proxy log confirms every decision was made by the proxy.
#   Run 2 (NO_PROXY=1)    – hosts that were blocked in Run 1 must be reachable
#                           without the proxy, proving the proxy is the gatekeeper.
#
# Requirements: Docker running with NET_ADMIN. Images built (auto-built if missing).
# Usage: bash tests/integration.sh

set -u

CLAUDIUS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0
LOGFILE=""

ok()  { PASS=$((PASS + 1)); printf '\033[32m  ✓ %s\033[0m\n' "$*"; }
err() { FAIL=$((FAIL + 1)); printf '\033[31m  ✗ %s\033[0m\n' "$*"; }

_run() {
  LOGFILE="$(mktemp /tmp/claudius-proxy.XXXXXX)"
  CLAUDIUS_ENV_FILE="$CLAUDIUS_DIR/tests/integration.env" \
  CLAUDIUS_PROXY_LOG_FILE="$LOGFILE" \
    "$CLAUDIUS_DIR/claudius.sh" bash -c "$1" >/dev/null 2>&1
}

_run_noproxy() {
  CLAUDIUS_ENV_FILE="$CLAUDIUS_DIR/tests/integration.env" \
  CLAUDIUS_NO_PROXY=1 \
    "$CLAUDIUS_DIR/claudius.sh" bash -c "$1" >/dev/null 2>&1
}

_proxy_logged() {
  grep -qi "$1.*$2" "$LOGFILE" 2>/dev/null
}

allows() {
  local name="$1" cmd="$2" host="$3"
  if _run "$cmd"; then
    ok "$name"
  else
    err "$name  (curl failed – connection was blocked or timed out)"
  fi
  if _proxy_logged ALLOW "$host"; then
    ok "  proxy: ALLOW $host"
  else
    err "  proxy: no ALLOW entry for $host – traffic may have bypassed the proxy"
  fi
}

blocks() {
  local name="$1" cmd="$2" host="$3"
  if _run "$cmd"; then
    err "$name  (curl succeeded – connection was not blocked)"
  else
    ok "$name"
  fi
  if _proxy_logged BLOCK "$host"; then
    ok "  proxy: BLOCK $host"
  else
    err "  proxy: no BLOCK entry for $host – traffic may have bypassed the proxy"
  fi
}

# Build a bash -c compatible UDP DNS query command for the given host IP.
# Sends a minimal DNS A query for example.com and asserts a response is received.
_dns_udp_cmd() {
  echo "python3 -c 'import socket; s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM); s.settimeout(4); s.sendto(bytes.fromhex(\"aabb01000001000000000000076578616d706c6503636f6d0000010001\"),(\"$1\",53)); assert len(s.recv(512))>12'"
}

reachable() {
  local name="$1" cmd="$2"
  if _run_noproxy "$cmd"; then
    ok "$name"
  else
    err "$name  (expected: reachable without proxy – network issue or host down?)"
  fi
}

# ── Run 1: with proxy ─────────────────────────────────────────────────────────

echo "claudius · integration tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Run 1: with proxy"
echo ""

echo "TCP – always allowed"
allows "api.anthropic.com:443" \
  "curl -so /dev/null --max-time 10 https://api.anthropic.com/" \
  "api.anthropic.com"

echo ""
echo "TCP – CLAUDIUS_ALLOW"
allows "httpbin.org:443 (via CLAUDIUS_ALLOW)" \
  "curl -so /dev/null --max-time 10 https://httpbin.org/get" \
  "httpbin.org"

echo ""
echo "TCP – blocked"
blocks "example.com:443" \
  "curl -so /dev/null --max-time 5 https://example.com/" \
  "example.com"
blocks "registry.npmjs.org:443" \
  "curl -so /dev/null --max-time 5 https://registry.npmjs.org/" \
  "registry.npmjs.org"
blocks "github.com:443" \
  "curl -so /dev/null --max-time 5 https://github.com/" \
  "github.com"

echo ""
echo "DNS"
if _run "getent hosts api.anthropic.com"; then
  ok "resolves api.anthropic.com via allowed resolver"
else
  err "resolves api.anthropic.com  (DNS failed)"
fi
if _run "getent hosts example.com"; then
  ok "resolves example.com (DNS allowed, TCP blocked separately)"
else
  err "resolves example.com  (DNS failed)"
fi

echo ""
echo "UDP – CLAUDIUS_ALLOW"
allows "9.9.9.9:53/udp (DNS, via CLAUDIUS_ALLOW)" \
  "$(_dns_udp_cmd 9.9.9.9)" \
  "9.9.9.9"

echo ""
echo "UDP – blocked"
blocks "208.67.222.222:53/udp (DNS, not in ALLOW)" \
  "$(_dns_udp_cmd 208.67.222.222)" \
  "208.67.222.222"

# ── Run 2: without proxy ──────────────────────────────────────────────────────

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Run 2: without proxy (NO_PROXY=1)"
echo "(hosts blocked in Run 1 must be reachable – proves proxy is the gatekeeper)"
echo ""

reachable "example.com:443" \
  "curl -so /dev/null --max-time 10 https://example.com/"
reachable "registry.npmjs.org:443" \
  "curl -so /dev/null --max-time 10 https://registry.npmjs.org/"
reachable "github.com:443" \
  "curl -so /dev/null --max-time 10 https://github.com/"

reachable "208.67.222.222:53/udp (DNS)" \
  "$(_dns_udp_cmd 208.67.222.222)"

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf '%d passed · %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
