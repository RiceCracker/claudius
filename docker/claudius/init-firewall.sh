#!/bin/bash
# claudius – network firewall
# Strategy: DNS + ICMP always direct; all TCP via Envoy (only CLAUDIUS_ALLOW entries pass);
#           UDP entries direct via iptables; * host opens port to all IPs.
set -euo pipefail

# ── Helper functions ───────────────────────────────────────────────────────────

fw_both() { iptables "$@"; [ "$IPV6" = "1" ] && ip6tables "$@"; }

fw_line() { if [ "${CLAUDIUS_FIREWALL_VERBOSE:-0}" = "1" ]; then printf "   →  %-20s – %s\n" "$1" "$2"; fi; }

parse_allow_entry() {
  # Sets proto, host, port as globals. Returns 1 and skips if proto is missing.
  local _entry="$1"
  case "$_entry" in
    */udp) proto="udp"; _entry="${_entry%/udp}" ;;
    */tcp) proto="tcp"; _entry="${_entry%/tcp}" ;;
    *)
      echo "   ⚠  '$_entry': missing /tcp or /udp – skipped"
      proto="" host="" port=""; return 1
      ;;
  esac
  host="${_entry%:*}"
  port="${_entry##*:}"
}

# Löst einen Hostnamen auf und öffnet den UDP-Port in iptables (IPv4 + IPv6).
add_udp_rule() {
  local host="$1" port="$2" ips4="" ips6=""
  if echo "$host" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
    ips4="$host"
  elif echo "$host" | grep -qE '^[0-9a-fA-F:]+$'; then
    ips6="$host"
  else
    ips4="$(getent ahostsv4 "$host" 2>/dev/null | awk '{print $1}' | sort -u | paste -sd' ' || true)"
    ips6="$(getent ahostsv6 "$host" 2>/dev/null | awk '{print $1}' | sort -u | paste -sd' ' || true)"
  fi
  if [ -z "$ips4" ] && [ -z "$ips6" ]; then
    echo "   ⚠  could not resolve $host – skipped"; return
  fi
  for ip in $ips4; do
    iptables  -A OUTPUT -d "$ip" -p udp --dport "$port" -j ACCEPT
    if [ "${CLAUDIUS_FIREWALL_VERBOSE:-0}" = "1" ]; then printf "   →    %-20s – %s\n" "$host:$port/udp" "$ip"; fi
  done
  [ "$IPV6" = "1" ] && for ip in $ips6; do
    ip6tables -A OUTPUT -d "$ip" -p udp --dport "$port" -j ACCEPT
    if [ "${CLAUDIUS_FIREWALL_VERBOSE:-0}" = "1" ]; then printf "   →    %-20s – %s\n" "$host:$port/udp" "$ip"; fi
  done
}

# When sourced (e.g. from tests), only define the functions above.
[ "${BASH_SOURCE[0]}" != "$0" ] && return 0

# ── Firewall setup ─────────────────────────────────────────────────────────────

iptables -F OUTPUT; iptables -P OUTPUT DROP
if ip6tables -F OUTPUT 2>/dev/null; then
  ip6tables -P OUTPUT DROP; IPV6=1
else
  IPV6=0
fi

# Infrastructure
fw_both -A OUTPUT -o lo -j ACCEPT
fw_both -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# DNS – always direct to fixed resolvers
for resolver in ${CLAUDIUS_DNS:-1.1.1.1 1.0.0.1 8.8.8.8 8.8.4.4}; do
  if echo "$resolver" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
    tbl=iptables
  else
    [ "$IPV6" = "0" ] && continue
    tbl=ip6tables
  fi
  for proto in udp tcp; do
    $tbl -A OUTPUT -d "$resolver" -p "$proto" --dport 53 -j ACCEPT
  done
done

# ICMP (different protocol names for ipv4/ipv6 – can't use fw_both)
iptables -A OUTPUT -p icmp -j ACCEPT
[ "$IPV6" = "1" ] && ip6tables -A OUTPUT -p ipv6-icmp -j ACCEPT

# SSH – always direct (SSH doesn't tunnel through an HTTP CONNECT proxy)
[ "${CLAUDIUS_SSH:-0}" = "1" ] && fw_both -A OUTPUT -p tcp --dport 22 -j ACCEPT

# ── TCP routing – always via Envoy ─────────────────────────────────────────────
iptables -t nat -A OUTPUT -d "$ENVOY_IP"                           -j RETURN
iptables -t nat -A OUTPUT -p tcp --dport 53                        -j RETURN
[ "${CLAUDIUS_SSH:-0}" = "1" ] && \
  iptables -t nat -A OUTPUT -p tcp --dport 22                      -j RETURN
iptables -t nat -A OUTPUT -p tcp -j DNAT --to-destination "$ENVOY_IP:3128"
iptables        -A OUTPUT -d "$ENVOY_IP" -p tcp --dport 3128       -j ACCEPT

# ── Status: always-on ──────────────────────────────────────────────────────────
if [ "${CLAUDIUS_FIREWALL_VERBOSE:-0}" = "1" ]; then
  fw_line "icmp/icmpv6" "open"
  fw_line "udp+tcp/53  (DNS)" "${CLAUDIUS_DNS:-1.1.1.1 1.0.0.1 8.8.8.8 8.8.4.4}"
  [ "${CLAUDIUS_SSH:-0}" = "1" ] && fw_line "tcp/22  (SSH)" "open"
  fw_line "Envoy  (tcp)" "$ENVOY_IP:3128"
  for entry in ${CLAUDIUS_ALLOW:-}; do
    case "$entry" in */tcp) printf "   →    %s\n" "${entry%/tcp}" ;; esac
  done
fi

# ── UDP routing ────────────────────────────────────────────────────────────────
_has_udp=0
for _e in ${CLAUDIUS_ALLOW:-}; do case "$_e" in */udp) _has_udp=1; break ;; esac; done
if [ "$_has_udp" = "1" ] && [ "${CLAUDIUS_FIREWALL_VERBOSE:-0}" = "1" ]; then printf "   →  iptables  (udp)\n"; fi
for entry in ${CLAUDIUS_ALLOW:-}; do
  parse_allow_entry "$entry" || continue
  [ "$proto" = "tcp" ] && continue
  if [ "$host" = "*" ]; then
    fw_both -A OUTPUT -p udp --dport "$port" -j ACCEPT
    if [ "${CLAUDIUS_FIREWALL_VERBOSE:-0}" = "1" ]; then printf "   →    udp/%-6s *\n" "$port"; fi
  else
    add_udp_rule "$host" "$port"
  fi
done

if [ "${CLAUDIUS_FIREWALL_VERBOSE:-0}" = "1" ]; then printf "   ✕  %-22s – %s\n" "other" "blocked"; fi
