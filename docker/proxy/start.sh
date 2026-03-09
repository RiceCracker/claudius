# claudius transparent proxy sidecar – sets up host-side iptables REDIRECT and
# runs the filtering proxy. Sourced by claudius.sh.
# Uses: ALLOW, CLAUDIUS_DIR, NET, SSH. Sets: FWPROXY, SUBNET, SUBNET6.

FWPROXY="claudius-proxy-$$"
CHAIN="CLAUDIUS_$$"       # host PID – unique per session, passed into sidecar
PROXY_PORT=$(( 20000 + ($$ % 40000) ))   # unique port per session (range 20000–59999)

# Build image if missing
if ! docker image inspect claudius-proxy &>/dev/null; then
  echo "📜 Image 'claudius-proxy' not found – building..."
  docker build -q -t claudius-proxy "$CLAUDIUS_DIR/docker/proxy" >/dev/null
fi

# Derive bridge interface and subnets from the claudius Docker network.
# Docker names bridges br-<first12 of network ID>.
_net_id=$(docker network inspect "$NET" --format '{{.Id}}')
BRIDGE_IF="br-${_net_id:0:12}"
_subnets=$(docker network inspect "$NET" --format '{{range .IPAM.Config}}{{.Subnet}} {{end}}')
SUBNET=$(for s in $_subnets; do echo "$s"; done | grep '\.' | head -1)
SUBNET6=$(for s in $_subnets; do echo "$s"; done | grep ':' | head -1)

prune_stale_chains() {
  # Remove CLAUDIUS_* chains whose proxy container is no longer running.
  local running_chains
  running_chains=$(docker ps --filter name=claudius-proxy --format '{{.Names}}' \
    | sed 's/claudius-proxy-/CLAUDIUS_/')
  docker run --rm --cap-add NET_ADMIN --network host \
    -v "$CLAUDIUS_DIR/docker/proxy/prune-chains.sh:/prune-chains.sh:ro" \
    -e "RUNNING_CHAINS=$running_chains" \
    claudius-proxy sh /prune-chains.sh 2>/dev/null || true
}

start_proxy_sidecar() {
  docker run -d --rm \
    --name "$FWPROXY" \
    --network host \
    --cap-add NET_ADMIN \
    --cap-add NET_RAW \
    --cap-add SYS_MODULE \
    -v /lib/modules:/lib/modules:ro \
    -e "CLAUDIUS_ALLOW=${ALLOW:-}" \
    -e "CLAUDIUS_BRIDGE_IF=$BRIDGE_IF" \
    -e "CLAUDIUS_SUBNET=$SUBNET" \
    -e "CLAUDIUS_SUBNET6=${SUBNET6:-}" \
    -e "CLAUDIUS_CHAIN=$CHAIN" \
    -e "CLAUDIUS_PROXY_PORT=$PROXY_PORT" \
    claudius-proxy >/dev/null
}

check_proxy_health() {
  local attempts=0
  while [ $attempts -lt 15 ]; do
    if nc -z 127.0.0.1 "$PROXY_PORT" 2>/dev/null; then
      return 0
    fi
    sleep 1
    attempts=$((attempts + 1))
  done
  echo "❌ Proxy sidecar (TCP :$PROXY_PORT) not reachable. Aborting." >&2
  exit 1
}

prune_stale_chains
start_proxy_sidecar
check_proxy_health

# If CLAUDIUS_PROXY_LOG_FILE is set, follow proxy logs to a host file.
# The follower PID is stored in PROXY_LOG_PID so cleanup() can kill it.
if [ -n "${CLAUDIUS_PROXY_LOG_FILE:-}" ]; then
  docker logs -f "$FWPROXY" >> "$CLAUDIUS_PROXY_LOG_FILE" 2>&1 &
  PROXY_LOG_PID=$!
fi
