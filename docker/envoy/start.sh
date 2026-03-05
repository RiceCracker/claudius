# Envoy forward proxy – generiert Config aus Template und startet den Sidecar.
# Sourced by claudius.sh. Uses: ALLOW, CLAUDIUS_DIR, ENVOY, NET. Sets: ENVOY_CONF_FILE, ENVOY_IP.

generate_envoy_conf() {
  ENVOY_CONF_FILE="/tmp/claudius-envoy-$$.yaml"
  # CONNECT (non-80): exact ["host:port"], wildcards [":port" or ".domain:port"]
  # HTTP forward proxy (port 80): http_exact ["host"], http_wildcards [".domain"],
  #                                allow_all_http for *:80/tcp
  local exact_entries=() wildcard_entries=()
  local http_exact_entries=() http_wildcard_entries=()
  local allow_all_http="false"
  for entry in $ALLOW; do
    case "$entry" in */tcp) ;; *) continue ;; esac
    local h="${entry%/tcp}"; local p="${h##*:}"; h="${h%:*}"
    if [ "$p" = "80" ]; then
      case "$h" in
        \*.*) http_wildcard_entries+=("\"${h#\*}\"") ;;
        \*)   allow_all_http="true" ;;
        *)    http_exact_entries+=("[\"${h}\"] = true") ;;
      esac
    else
      case "$h" in
        \*.*) wildcard_entries+=("\"${h#\*}:${p}\"") ;;
        \*)   wildcard_entries+=('":'${p}'"') ;;
        *)    exact_entries+=("[\"${h}:${p}\"] = true") ;;
      esac
    fi
  done

  while IFS= read -r line; do
    case "$line" in
      "##EXACT##")          [ ${#exact_entries[@]}         -gt 0 ] && printf '                    %s,\n' "${exact_entries[@]}" ;;
      "##WILDCARDS##")      [ ${#wildcard_entries[@]}      -gt 0 ] && printf '                    %s,\n' "${wildcard_entries[@]}" ;;
      "##HTTP_EXACT##")     [ ${#http_exact_entries[@]}    -gt 0 ] && printf '                    %s,\n' "${http_exact_entries[@]}" ;;
      "##HTTP_WILDCARDS##") [ ${#http_wildcard_entries[@]} -gt 0 ] && printf '                    %s,\n' "${http_wildcard_entries[@]}" ;;
      "##ALLOW_ALL_HTTP##")  printf '                  local allow_all_http = %s\n' "$allow_all_http" ;;
      *) printf '%s\n' "$line" ;;
    esac
  done < "$CLAUDIUS_DIR/docker/envoy/envoy.yaml.tpl" > "$ENVOY_CONF_FILE"
}

start_envoy_sidecar() {
  docker run -d --rm \
    --name "$ENVOY" \
    --network "$NET" \
    -v "$ENVOY_CONF_FILE:/etc/envoy/envoy.yaml:ro" \
    envoyproxy/envoy-distroless:v1.32-latest \
    -c /etc/envoy/envoy.yaml >/dev/null
  ENVOY_IP=$(docker inspect -f "{{(index .NetworkSettings.Networks \"$NET\").IPAddress}}" "$ENVOY")
}

check_envoy_health() {
  local attempts=0
  while [ $attempts -lt 15 ]; do
    if nc -z "$ENVOY_IP" 3128 2>/dev/null; then
      return 0
    fi
    sleep 1
    attempts=$((attempts + 1))
  done
  echo "❌ Envoy proxy not reachable. Aborting." >&2
  exit 1
}

generate_envoy_conf
start_envoy_sidecar
check_envoy_health
