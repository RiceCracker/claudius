#!/usr/bin/env bash
# claudius integration tests – end-to-end smoke check.
#
# Verifies the container starts, mounts work, DNS resolves, and outbound
# network is reachable (no firewall in place – container has unrestricted
# egress through the Docker bridge).
#
# Requirements: Docker running. Image built (auto-built on first run).
# Usage: bash tests/integration.sh

set -u

CLAUDIUS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

ok()  { PASS=$((PASS + 1)); printf '\033[32m  ✓ %s\033[0m\n' "$*"; }
err() { FAIL=$((FAIL + 1)); printf '\033[31m  ✗ %s\033[0m\n' "$*"; }

_run() {
  CLAUDIUS_ENV_FILE="$CLAUDIUS_DIR/tests/integration.env" \
    "$CLAUDIUS_DIR/claudius.sh" bash -c "$1" >/dev/null 2>&1
}

reachable() {
  local name="$1" cmd="$2"
  if _run "$cmd"; then
    ok "$name"
  else
    err "$name  (command failed – network or container issue)"
  fi
}

unreachable() {
  local name="$1" cmd="$2"
  if _run "$cmd"; then
    err "$name  (expected failure but command succeeded)"
  else
    ok "$name"
  fi
}

echo "claudius · integration tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Container & mounts"
reachable "container starts and exits cleanly" "true"
reachable "project dir mounted (rw)"            "test -w \"\$HOME\"/* 2>/dev/null || test -w \"\$HOME\""
reachable "claude binary on PATH"               "command -v claude"

echo ""
echo "DNS"
reachable "resolves api.anthropic.com" "getent hosts api.anthropic.com"
reachable "resolves example.com"       "getent hosts example.com"

echo ""
echo "Outbound network (unrestricted)"
reachable "api.anthropic.com:443"       "curl -so /dev/null --max-time 10 https://api.anthropic.com/"
reachable "github.com:443"              "curl -so /dev/null --max-time 10 https://github.com/"
reachable "registry.npmjs.org:443"      "curl -so /dev/null --max-time 10 https://registry.npmjs.org/"

echo ""
echo "Docker socket proxy (read-only)"
reachable "docker ps via socket proxy"  "docker ps"
unreachable "docker run blocked (read-only proxy)" \
  "docker run --rm hello-world"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf '%d passed · %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
