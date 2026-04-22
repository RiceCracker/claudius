#!/bin/sh
# claudius-proxy supervisor – keeps entrypoint.py running, restarts on crash.
# SIGTERM forwards to child and exits without restart, so atexit() runs the
# iptables cleanup path. Crash (non-zero exit) triggers restart with backoff.

set -eu

graceful_exit() {
    [ -n "${child:-}" ] && kill -TERM "$child" 2>/dev/null || true
    [ -n "${child:-}" ] && wait "$child" 2>/dev/null || true
    exit 0
}
trap graceful_exit TERM INT

ts() { date -u '+%Y-%m-%d %H:%M:%S'; }

backoff=1
max_backoff=30
while :; do
    started=$(date +%s)
    python3 /entrypoint.py &
    child=$!
    wait "$child" && rc=0 || rc=$?

    # Exit 0 = clean shutdown initiated from inside Python (signal handler) → don't restart.
    [ "$rc" -eq 0 ] && exit 0

    ran=$(( $(date +%s) - started ))
    # If the proxy ran stably for ≥10s, reset backoff so transient crashes don't escalate.
    [ "$ran" -ge 10 ] && backoff=1

    echo "$(ts) SUPERVISOR proxy exited rc=$rc after ${ran}s – restart in ${backoff}s" >&2
    sleep "$backoff"
    backoff=$(( backoff * 2 ))
    [ "$backoff" -gt "$max_backoff" ] && backoff="$max_backoff"
done
