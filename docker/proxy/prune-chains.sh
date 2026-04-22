#!/bin/sh
# Remove orphaned CLAUDIUS_* iptables chains from sessions that crashed without cleanup.
# Runs inside a short-lived privileged container with network host access.
#
# Input: RUNNING_CHAINS env var – newline-separated list of chain names still in use.

stale=$(iptables -t nat -S | awk '/^-N CLAUDIUS_/{print $2}' | while read -r chain; do
    echo "$RUNNING_CHAINS" | grep -qxF "$chain" || echo "$chain"
done)

[ -z "$stale" ] && exit 0

# Delete all PREROUTING/FORWARD jumps targeting $chain, then flush & drop $chain.
# $1=iptables-bin  $2=table  $3=parent-chain  $4=child-chain-name
drop_chain() {
    ipt=$1; tbl=$2; parent=$3; target=$4
    "$ipt" -t "$tbl" -S "$parent" 2>/dev/null \
        | grep -- "-j $target" \
        | sed 's/^-A/-D/' \
        | while read -r rule; do "$ipt" -t "$tbl" $rule 2>/dev/null || true; done
    "$ipt" -t "$tbl" -F "$target" 2>/dev/null || true
    "$ipt" -t "$tbl" -X "$target" 2>/dev/null || true
}

for chain in $stale; do
    drop_chain iptables  nat    PREROUTING "$chain"             # IPv4 TCP REDIRECT
    drop_chain iptables  mangle PREROUTING "${chain}_FILTER"    # IPv4 UDP/ICMP NFQUEUE
    drop_chain ip6tables nat    PREROUTING "$chain"             # IPv6 TCP REDIRECT
    drop_chain ip6tables mangle PREROUTING "${chain}_FILTER6"   # IPv6 UDP/ICMPv6 NFQUEUE
    drop_chain ip6tables filter FORWARD    "${chain}_V6"        # IPv6 fallback DROP
done
