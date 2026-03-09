#!/bin/sh
# Remove orphaned CLAUDIUS_* iptables chains from sessions that crashed without cleanup.
# Runs inside a short-lived privileged container with network host access.
#
# Input: RUNNING_CHAINS env var — newline-separated list of chain names still in use.

stale=$(iptables -t nat -S | awk '/^-N CLAUDIUS_/{print $2}' | while read -r chain; do
    echo "$RUNNING_CHAINS" | grep -qxF "$chain" || echo "$chain"
done)

[ -z "$stale" ] && exit 0

for chain in $stale; do
    # IPv4 nat (TCP REDIRECT)
    iptables -t nat -S PREROUTING | grep -- "-j $chain" | sed 's/^-A/-D/' | \
        while read -r rule; do iptables -t nat $rule 2>/dev/null || true; done
    iptables -t nat -F "$chain" 2>/dev/null || true
    iptables -t nat -X "$chain" 2>/dev/null || true

    # IPv4 mangle (UDP + ICMP NFQUEUE)
    iptables -t mangle -S PREROUTING | grep -- "-j ${chain}_FILTER" | sed 's/^-A/-D/' | \
        while read -r rule; do iptables -t mangle $rule 2>/dev/null || true; done
    iptables -t mangle -F "${chain}_FILTER" 2>/dev/null || true
    iptables -t mangle -X "${chain}_FILTER" 2>/dev/null || true

    # IPv6 nat (TCP REDIRECT)
    ip6tables -t nat -S PREROUTING | grep -- "-j $chain" | sed 's/^-A/-D/' | \
        while read -r rule; do ip6tables -t nat $rule 2>/dev/null || true; done
    ip6tables -t nat -F "$chain" 2>/dev/null || true
    ip6tables -t nat -X "$chain" 2>/dev/null || true

    # IPv6 mangle (UDP + ICMPv6 NFQUEUE)
    ip6tables -t mangle -S PREROUTING | grep -- "-j ${chain}_FILTER6" | sed 's/^-A/-D/' | \
        while read -r rule; do ip6tables -t mangle $rule 2>/dev/null || true; done
    ip6tables -t mangle -F "${chain}_FILTER6" 2>/dev/null || true
    ip6tables -t mangle -X "${chain}_FILTER6" 2>/dev/null || true

    # IPv6 filter (fallback DROP chain when no IPv6 subnet)
    ip6tables -t filter -S FORWARD | grep -- "-j ${chain}_V6" | sed 's/^-A/-D/' | \
        while read -r rule; do ip6tables -t filter $rule 2>/dev/null || true; done
    ip6tables -t filter -F "${chain}_V6" 2>/dev/null || true
    ip6tables -t filter -X "${chain}_V6" 2>/dev/null || true
done
