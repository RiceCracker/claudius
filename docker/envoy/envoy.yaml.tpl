static_resources:
  listeners:
  - address:
      socket_address: {address: 0.0.0.0, port_value: 3128}
    filter_chains:
    - filters:
      - name: envoy.filters.network.http_connection_manager
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
          stat_prefix: ingress_http
          access_log:
          - name: envoy.access_loggers.file
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.access_loggers.file.v3.FileAccessLog
              path: /dev/stdout
              log_format:
                text_format_source:
                  inline_string: "[%START_TIME%] %REQ(:METHOD)% %REQ(:AUTHORITY)% %RESPONSE_CODE% %BYTES_SENT%B\n"
          upgrade_configs:
          - upgrade_type: CONNECT
          route_config:
            name: local_route
            virtual_hosts:
            - name: local_service
              domains: ["*"]
              routes:
              - match:
                  connect_matcher: {}
                route:
                  cluster: dynamic_forward_proxy_cluster
                  upgrade_configs:
                  - upgrade_type: CONNECT
                    connect_config: {}
              - match:
                  prefix: "/"
                route:
                  cluster: dynamic_forward_proxy_cluster
          http_filters:
          - name: envoy.filters.http.lua
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.http.lua.v3.Lua
              default_source_code:
                inline_string: |
                  local exact = {
##EXACT##
                  }
                  local wildcards = {
##WILDCARDS##
                  }
                  local http_exact = {
##HTTP_EXACT##
                  }
                  local http_wildcards = {
##HTTP_WILDCARDS##
                  }
##ALLOW_ALL_HTTP##
                  function envoy_on_request(h)
                    local auth = h:headers():get(":authority") or ""
                    if exact[auth] then return end
                    for _, sfx in ipairs(wildcards) do
                      if auth:sub(-#sfx) == sfx then return end
                    end
                    if not auth:find(":") then
                      if allow_all_http then return end
                      if http_exact[auth] then return end
                      for _, sfx in ipairs(http_wildcards) do
                        if auth:sub(-#sfx) == sfx then return end
                      end
                    end
                    h:respond({[":status"] = "403"}, "Forbidden")
                  end
          - name: envoy.filters.http.dynamic_forward_proxy
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.http.dynamic_forward_proxy.v3.FilterConfig
              dns_cache_config:
                name: dynamic_forward_proxy_cache_config
                dns_lookup_family: V4_ONLY
          - name: envoy.filters.http.router
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router
  clusters:
  - name: dynamic_forward_proxy_cluster
    lb_policy: CLUSTER_PROVIDED
    cluster_type:
      name: envoy.clusters.dynamic_forward_proxy
      typed_config:
        "@type": type.googleapis.com/envoy.extensions.clusters.dynamic_forward_proxy.v3.ClusterConfig
        dns_cache_config:
          name: dynamic_forward_proxy_cache_config
          dns_lookup_family: V4_ONLY
