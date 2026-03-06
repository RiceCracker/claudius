# Docker socket proxy – read-only (or write) access to the host Docker daemon.
# Sourced by claudius.sh. Uses: DOCKER_WRITE, PROXY, NET. Sets: PROXY_IP.

DOCKER_WRITE_ARGS=()
[ "$DOCKER_WRITE" = "1" ] && DOCKER_WRITE_ARGS+=(-e "POST=1" -e "BUILD=1")

docker run -d --rm \
  --name "$PROXY" \
  --network "$NET" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -e CONTAINERS=1 \
  -e IMAGES=1 \
  -e INFO=1 \
  -e NETWORKS=1 \
  -e VOLUMES=1 \
  -e VERSION=1 \
  "${DOCKER_WRITE_ARGS[@]}" \
  tecnativa/docker-socket-proxy:v0.4.2 >/dev/null

PROXY_IP=$(docker inspect -f "{{(index .NetworkSettings.Networks \"$NET\").IPAddress}}" "$PROXY")
