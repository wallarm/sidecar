initContainers:
{{- if ((getAnnotation .ObjectMeta (withAP "sidecar-injection-iptables-enable") .Config.injectionStrategy.iptablesEnable) | toBool) -}}
  {{- template "initIptablesContainer" . }}
{{- end }}
{{- if eq (getAnnotation .ObjectMeta (withAP "sidecar-injection-schema") .Config.injectionStrategy.schema) "split" -}}
  {{- template "initHelperContainer" . }}
{{- end }}

containers:
{{- if eq (getAnnotation .ObjectMeta (withAP "sidecar-injection-schema") .Config.injectionStrategy.schema) "split" -}}
  {{ template "helperContainer" . }}
{{- end -}}
  {{ template "proxyContainer" . }}

volumes:
{{ template "volumes" . }}


{{ define "proxyContainer" }}
- name: sidecar-proxy
  image: {{ template "image" . }}
  imagePullPolicy: {{ .Config.sidecar.image.pullPolicy }}
  {{ if eq (getAnnotation .ObjectMeta (withAP "sidecar-injection-schema") .Config.injectionStrategy.schema) "split" -}}
  command: ["/usr/local/run-nginx.sh"]
  {{- else }}
  command: ["/usr/local/run-node.sh", "run", {{ template "wcli-args" . }}]
  {{- end }}
  env:
    {{ if ne (getAnnotation .ObjectMeta (withAP "sidecar-injection-schema") .Config.injectionStrategy.schema) "split" -}}
    {{ template "wallarmApiVariables" . }}
    {{ template "wallarmVersion" . }}
    {{ template "wallarmApiFwVariables" . }}
    {{- end  }}
    {{ if (isSet .ObjectMeta.Annotations (withAP "wallarm-application")) -}}
    - name: WALLARM_APPLICATION
      value: "{{ index .ObjectMeta.Annotations (withAP `wallarm-application`) }}"
    {{- end  }}
    {{ if (isSet .ObjectMeta.Annotations (withAP "wallarm-block-page")) -}}
    - name: WALLARM_BLOCK_PAGE
      value: "{{ index .ObjectMeta.Annotations (withAP `wallarm-block-page`) }}"
    {{- end  }}
    {{ if (isSet .ObjectMeta.Annotations (withAP "wallarm-parser-disable")) -}}
    - name: WALLARM_PARSER_DISABLE
      value: "{{ index .ObjectMeta.Annotations (withAP `wallarm-parser-disable`) }}"
    {{- end  }}
    - name: WALLARM_FALLBACK
      value: "{{ getAnnotation .ObjectMeta (withAP `wallarm-fallback`) .Config.wallarm.fallback }}"
    - name: WALLARM_MODE
      value: "{{ getAnnotation .ObjectMeta (withAP `wallarm-mode`) .Config.wallarm.mode }}"
    - name: WALLARM_MODE_ALLOW_OVERRIDE
      value: "{{ getAnnotation .ObjectMeta (withAP `wallarm-mode-allow-override`) .Config.wallarm.modeAllowOverride }}"
    - name: WALLARM_ENABLE_LIB_DETECTION
      value: "{{ getAnnotation .ObjectMeta (withAP `wallarm-enable-libdetection`) .Config.wallarm.enableLibDetection }}"
    - name: WALLARM_PARSE_RESPONSE
      value: "{{ getAnnotation .ObjectMeta (withAP `wallarm-parse-response`) .Config.wallarm.parseResponse }}"
    - name: WALLARM_PARSE_WEBSOCKET
      value: "{{ getAnnotation .ObjectMeta (withAP `wallarm-parse-websocket`) .Config.wallarm.parseWebsocket }}"
    - name: WALLARM_UNPACK_RESPONSE
      value: "{{ getAnnotation .ObjectMeta (withAP `wallarm-unpack-response`) .Config.wallarm.unpackResponse }}"
    - name: WALLARM_ACL_EXPORT_ENABLE
      value: "{{ getAnnotation .ObjectMeta (withAP `wallarm-acl-export-enable`) .Config.wallarm.aclExportEnable }}"
    - name: WALLARM_TARANTOOL_HOST
      value: "{{ .Config.tarantool.host }}"
    - name: WALLARM_TARANTOOL_PORT
      value: "{{ .Config.tarantool.port }}"
    - name: WALLARM_UPSTREAM_CONNECT_ATTEMPTS
      value: "{{ getAnnotation .ObjectMeta (withAP `wallarm-upstream-connect-attempts`) .Config.wallarm.upstream.connectAttempts }}"
    - name: WALLARM_UPSTREAM_RECONNECT_INTERVAL
      value: "{{ getAnnotation .ObjectMeta (withAP `wallarm-upstream-reconnect-interval`) .Config.wallarm.upstream.reconnectInterval }}"
    - name: NGINX_LISTEN_PORT
      value: "{{ getAnnotation .ObjectMeta (withAP `nginx-listen-port`) .Config.nginx.listenPort }}"
    - name: NGINX_PROXY_PASS_PORT
      value: "{{ template `applicationPort` . }}"
    - name: NGINX_STATUS_PORT
      value: "{{ getAnnotation .ObjectMeta (withAP `nginx-status-port`) .Config.nginx.statusPort }}"
    - name: NGINX_STATUS_PATH
      value: "{{ getAnnotation .ObjectMeta (withAP `nginx-status-path`) .Config.nginx.statusPath }}"
    - name: NGINX_HEALTH_PATH
      value: "{{ getAnnotation .ObjectMeta (withAP `nginx-health-path`) .Config.nginx.healthPath }}"
    - name: NGINX_WALLARM_STATUS_PATH
      value: "{{ getAnnotation .ObjectMeta (withAP `nginx-wallarm-status-path`) .Config.nginx.wallarmStatusPath }}"
    - name: NGINX_WALLARM_METRICS_PORT
      value: "{{ getAnnotation .ObjectMeta (withAP `nginx-wallarm-metrics-port`) .Config.nginx.wallarmMetricsPort }}"
    - name: NGINX_WALLARM_METRICS_PATH
      value: "{{ getAnnotation .ObjectMeta (withAP `nginx-wallarm-metrics-path`) .Config.nginx.wallarmMetricsPath }}"
    - name: NGINX_REAL_IP_HEADER
      value: "{{ .Config.nginx.realIpHeader }}"
    - name: NGINX_SET_REAL_IP_FROM
      value: '{{ toJson .Config.nginx.setRealIpFrom }}'
    - name: NGINX_WORKER_PROCESSES
      value: "{{ getAnnotation .ObjectMeta (withAP `nginx-worker-processes`) .Config.nginx.workerProcesses }}"
    - name: NGINX_WORKER_CONNECTIONS
      value: "{{ getAnnotation .ObjectMeta (withAP `nginx-worker-connections`) .Config.nginx.workerConnections }}"
    - name: NGINX_TARANTOOL_UPSTREAM_KEEPALIVE
      value: "{{ .Config.nginx.tarantoolUpstream.keepalive }}"
    - name: NGINX_TARANTOOL_UPSTREAM_KEEPALIVE_REQUESTS
      value: "{{ .Config.nginx.tarantoolUpstream.keepaliveRequests }}"
    - name: NGINX_TARANTOOL_UPSTREAM_SERVER_MAX_FAILS
      value: "{{ .Config.nginx.tarantoolUpstream.server.maxFails }}"
    - name: NGINX_TARANTOOL_UPSTREAM_SERVER_FAIL_TIMEOUT
      value: "{{ .Config.nginx.tarantoolUpstream.server.maxConns }}"
    - name: NGINX_TARANTOOL_UPSTREAM_SERVER_MAX_CONNS
      value: "{{ .Config.nginx.tarantoolUpstream.server.failTimeout }}"
    {{ if (isSet .ObjectMeta.Annotations (withAP "nginx-http-include")) -}}
    - name: NGINX_HTTP_INCLUDE
      value: "{{ index .ObjectMeta.Annotations (withAP `nginx-http-include`) }}"
    {{- end }}
    {{ if (isSet .ObjectMeta.Annotations (withAP "nginx-http-snippet")) -}}
    - name: NGINX_HTTP_SNIPPET
      value: "{{ index .ObjectMeta.Annotations (withAP `nginx-http-snippet`) }}"
    {{- end }}
    {{ if (isSet .ObjectMeta.Annotations (withAP "nginx-server-include")) -}}
    - name: NGINX_SERVER_INCLUDE
      value: "{{ index .ObjectMeta.Annotations (withAP `nginx-server-include`) }}"
    {{- end }}
    {{ if (isSet .ObjectMeta.Annotations (withAP "nginx-server-snippet")) -}}
    - name: NGINX_SERVER_SNIPPET
      value: "{{ index .ObjectMeta.Annotations (withAP `nginx-server-snippet`) }}"
    {{- end }}
    {{ if (isSet .ObjectMeta.Annotations (withAP "nginx-location-include")) -}}
    - name: NGINX_LOCATION_INCLUDE
      value: "{{ index .ObjectMeta.Annotations (withAP `nginx-location-include`) }}"
    {{- end }}
    {{ if (isSet .ObjectMeta.Annotations (withAP "nginx-location-snippet")) -}}
    - name: NGINX_LOCATION_SNIPPET
      value: "{{ index .ObjectMeta.Annotations (withAP `nginx-location-snippet`) }}"
    {{- end }}
    {{ if (isSet .ObjectMeta.Annotations (withAP "nginx-extra-modules")) -}}
    - name: NGINX_EXTRA_MODULES
      value: "{{ index .ObjectMeta.Annotations (withAP `nginx-extra-modules`) }}"
    {{- end }}
    {{ if and .Profile (index .Profile "nginx") -}}
    {{ if (index .Profile.nginx "servers") -}}
    - name: NGINX_SERVERS
      value: "{{ .Profile.nginx.servers | toJson | b64enc }}"
    {{- end }}
    {{- end }}
    - name: WALLARM_APIFW_ENABLE
      value: "{{ getAnnotation .ObjectMeta (withAP `api-firewall-enabled`) .Config.wallarm.apiFirewall.mode }}"
  ports:
    - name: status
      containerPort: {{ getAnnotation .ObjectMeta (withAP "nginx-status-port") .Config.nginx.statusPort }}
      protocol: TCP
    - name: metrics
      containerPort: {{ getAnnotation .ObjectMeta (withAP "nginx-wallarm-metrics-port") .Config.nginx.wallarmMetricsPort }}
      protocol: TCP
    {{ if not ((getAnnotation .ObjectMeta (withAP "sidecar-injection-iptables-enable") .Config.injectionStrategy.iptablesEnable) | toBool) -}}
    - name: proxy
      containerPort: {{ getAnnotation .ObjectMeta (withAP "nginx-listen-port") .Config.nginx.listenPort }}
      protocol: TCP
    {{- end }}
{{ if .Config.sidecar.containers.proxy.livenessProbeEnable }}
  livenessProbe:
    {{ toYaml .Config.sidecar.containers.proxy.livenessProbe | indent 4 }}
{{ end }}
{{ if .Config.sidecar.containers.proxy.readinessProbeEnable }}
  readinessProbe:
    {{ toYaml .Config.sidecar.containers.proxy.readinessProbe | indent 4 }}
{{ end }}
  volumeMounts:
    - mountPath: /opt/wallarm/etc/wallarm
      name: wallarm
    - mountPath: /opt/wallarm/var/lib/wallarm-acl
      name: wallarm-acl
    - mountPath: /opt/wallarm/var/lib/nginx/wallarm/
      name: wallarm-cache
    {{- if and .Profile (index .Profile "sidecar") -}}
    {{- with .Profile.sidecar.volumeMounts }}
    {{ . | toYaml | indent 4 }}
    {{- end }}
    {{- end -}}
    {{- if (isSet .ObjectMeta.Annotations (withAP "proxy-extra-volume-mounts")) }}
    {{ range $index, $value := fromJson (index .ObjectMeta.Annotations (withAP "proxy-extra-volume-mounts")) }}
    - name: "{{ $index }}"
      {{ toYaml $value | indent 6 }}
    {{ end }}
    {{- end }}
  securityContext:
    {{ toYaml .Config.sidecar.securityContext | indent 4 }}
  resources:
{{ template "proxyContainer.resources" . }}
{{ end }}

{{ define "helperContainer" }}
- name: sidecar-helper
  image: {{ template "image" . }}
  imagePullPolicy: {{ .Config.sidecar.image.pullPolicy }}
  command: ["/usr/local/run-helper.sh", "run", {{ template "wcli-args" . }}]
  env:
    {{ template "wallarmApiVariables" . }}
    {{ template "wallarmVersion" . }}
    {{ template "wallarmApiFwVariables" . }}
    - name: WALLARM_APIFW_ENABLE
      value: "{{ getAnnotation .ObjectMeta (withAP `api-firewall-enabled`) .Config.wallarm.apiFirewall.mode }}"
    - name: NGINX_STATUS_PORT
      value: "{{ getAnnotation .ObjectMeta (withAP `nginx-status-port`) .Config.nginx.statusPort }}"
  volumeMounts:
    - mountPath: /opt/wallarm/etc/wallarm
      name: wallarm
    - mountPath: /opt/wallarm/var/lib/wallarm-acl
      name: wallarm-acl
    - mountPath: /opt/wallarm/var/lib/wallarm-api
      name: wallarm-api
  securityContext:
    {{ toYaml .Config.sidecar.securityContext | indent 4 }}
  resources:
{{ template "helperContainer.resources" . }}
{{ end }}

{{ define "initHelperContainer" }}
- name: sidecar-init-helper
  image: {{ template "image" . }}
  imagePullPolicy: {{ .Config.sidecar.image.pullPolicy }}
  command: ["/usr/local/run-addnode.sh"]
  env:
    {{ template "wallarmApiVariables" . }}
    {{ template "wallarmVersion" . }}
    - name: WALLARM_FALLBACK
      value: "{{ getAnnotation .ObjectMeta (withAP `wallarm-fallback`) .Config.wallarm.fallback }}"
  volumeMounts:
    - mountPath: /opt/wallarm/etc/wallarm
      name: wallarm
    - mountPath: /opt/wallarm/var/lib/wallarm-acl
      name: wallarm-acl
    - mountPath: /opt/wallarm/var/lib/wallarm-api
      name: wallarm-api
  securityContext:
    {{ toYaml .Config.sidecar.securityContext | indent 4 }}
  resources:
{{ template "initHelperContainer.resources" . }}
{{ end }}

{{ define "initIptablesContainer" }}
- name: sidecar-init-iptables
  image: {{ template "image" . }}
  imagePullPolicy: {{ .Config.sidecar.image.pullPolicy }}
  env:
    - name: POD_IP
      valueFrom:
        fieldRef:
          fieldPath: status.podIP
    - name: APP_PORT
      value: "{{ template `applicationPort` . }}"
    - name: NGINX_PORT
      value: "{{ getAnnotation .ObjectMeta (withAP "nginx-listen-port") .Config.nginx.listenPort }}"
  command: ["iptables-legacy"]
  args: ["-t", "nat", "-A", "PREROUTING", "-p", "tcp", "-d", "$(POD_IP)", "--dport", "$(APP_PORT)", "-j", "REDIRECT", "--to-ports", "$(NGINX_PORT)"]
  securityContext:
    {{ toYaml .Config.sidecar.initContainers.iptables.securityContext | indent 4 }}
  resources:
{{ template "initIptablesContainer.resources" . }}
{{ end }}

{{- define "image" }}
  {{- if (isSet .ObjectMeta.Annotations (withAP "proxy-image")) }}
{{ index .ObjectMeta.Annotations (withAP "proxy-image") }}
  {{- else }}
    {{- if (index .Config.sidecar.image "fullname") }}
{{- print .Config.sidecar.image.fullname }}
    {{- else if (index .Config.sidecar.image "registry") }}
{{- printf "%s/%s:%s" .Config.sidecar.image.registry .Config.sidecar.image.image .Config.sidecar.image.tag }}
    {{- else }}
{{- printf "%s:%s" .Config.sidecar.image.image .Config.sidecar.image.tag }}
    {{- end }}
  {{- end }}
{{- end }}

{{- define "applicationPort" }}
  {{- if (isSet .ObjectMeta.Annotations (withAP "application-port")) }}
    {{- index .ObjectMeta.Annotations (withAP "application-port") }}
  {{- else }}
    {{- getAppPort .PodSpec .Config.nginx.applicationPort }}
  {{- end }}
{{- end }}

{{- define "wallarmApiVariables" }}
    - name: WALLARM_API_HOST
      value: "{{ .Config.wallarm.api.host }}"
    - name: WALLARM_API_PORT
      value: "{{ .Config.wallarm.api.port }}"
    - name: WALLARM_API_TOKEN
      value: "{{ .Secrets.Token }}"
    - name: WALLARM_API_USE_SSL
      value: "{{ .Config.wallarm.api.useSSL }}"
    - name: WALLARM_API_CA_VERIFY
      value: "{{ .Config.wallarm.api.caVerify }}"
    - name: WALLARM_LABELS
      value: "group={{ getAnnotation .ObjectMeta (withAP `wallarm-node-group`) .Config.wallarm.api.nodeGroup }}"
{{- end }}

{{- define "wallarmVersion" }}
    - name: WALLARM_COMPONENT_NAME
      value: "{{ .Config.component.name }}"
    - name: WALLARM_COMPONENT_VERSION
      value: "{{ .Config.component.version }}"
{{- end }}

{{- define "wallarmApiFwVariables" }}
    - name: APIFW_READ_BUFFER_SIZE
      value: "{{ .Config.wallarm.apiFirewall.readBufferSize | int64 }}"
    - name: APIFW_WRITE_BUFFER_SIZE
      value: "{{ .Config.wallarm.apiFirewall.writeBufferSize | int64 }}"
    - name: APIFW_MAX_REQUEST_BODY_SIZE
      value: "{{ .Config.wallarm.apiFirewall.maxRequestBodySize | int64 }}"
    - name: APIFW_DISABLE_KEEPALIVE
      value: "{{ .Config.wallarm.apiFirewall.disableKeepalive }}"
    - name: APIFW_MAX_CONNS_PER_IP
      value: "{{ .Config.wallarm.apiFirewall.maxConnectionsPerIp }}"
    - name: APIFW_MAX_REQUESTS_PER_CONN
      value: "{{ .Config.wallarm.apiFirewall.maxRequestsPerConnection }}"
{{- end }}

{{- define "helperContainer.resources" }}
  {{- if or (isSet .ObjectMeta.Annotations (withAP "helper-cpu")) (isSet .ObjectMeta.Annotations (withAP "helper-memory")) (isSet .ObjectMeta.Annotations (withAP "helper-cpu-limit")) (isSet .ObjectMeta.Annotations (withAP "helper-memory-limit")) }}
    {{- if or (isSet .ObjectMeta.Annotations (withAP "helper-cpu")) (isSet .ObjectMeta.Annotations (withAP "helper-memory")) }}
    requests:
      {{ if (isSet .ObjectMeta.Annotations (withAP "helper-cpu")) -}}
      cpu: "{{ index .ObjectMeta.Annotations (withAP `helper-cpu`) }}"
      {{ end }}
      {{ if (isSet .ObjectMeta.Annotations (withAP "helper-memory")) -}}
      memory: "{{ index .ObjectMeta.Annotations (withAP `helper-memory`) }}"
      {{ end }}
  {{- end }}
  {{- if or (isSet .ObjectMeta.Annotations (withAP "helper-cpu-limit")) (isSet .ObjectMeta.Annotations (withAP "helper-memory-limit")) }}
    limits:
      {{ if (isSet .ObjectMeta.Annotations (withAP "helper-cpu-limit")) -}}
      cpu: "{{ index .ObjectMeta.Annotations (withAP `helper-cpu-limit`) }}"
      {{ end }}
      {{ if (isSet .ObjectMeta.Annotations (withAP "helper-memory-limit")) -}}
      memory: "{{ index .ObjectMeta.Annotations (withAP `helper-memory-limit`) }}"
      {{ end }}
    {{- end }}
  {{- else }}
    {{- if (index .Config.sidecar.containers.helper "resources") }}
    {{ toYaml .Config.sidecar.containers.helper.resources | indent 4 }}
    {{- end }}
  {{- end }}
{{- end }}

{{- define "initIptablesContainer.resources" }}
  {{- if or (isSet .ObjectMeta.Annotations (withAP "init-iptables-cpu")) (isSet .ObjectMeta.Annotations (withAP "init-iptables-memory")) (isSet .ObjectMeta.Annotations (withAP "init-iptables-cpu-limit")) (isSet .ObjectMeta.Annotations (withAP "init-iptables-memory-limit")) }}
    {{- if or (isSet .ObjectMeta.Annotations (withAP "init-iptables-cpu")) (isSet .ObjectMeta.Annotations (withAP "init-iptables-memory")) }}
    requests:
      {{ if (isSet .ObjectMeta.Annotations (withAP "init-iptables-cpu")) -}}
      cpu: "{{ index .ObjectMeta.Annotations (withAP `init-iptables-cpu`) }}"
      {{ end }}
      {{ if (isSet .ObjectMeta.Annotations (withAP "init-iptables-memory")) -}}
      memory: "{{ index .ObjectMeta.Annotations (withAP `init-iptables-memory`) }}"
      {{ end }}
    {{- end }}
    {{- if or (isSet .ObjectMeta.Annotations (withAP "init-iptables-cpu-limit")) (isSet .ObjectMeta.Annotations (withAP "init-iptables-memory-limit")) }}
    limits:
      {{ if (isSet .ObjectMeta.Annotations (withAP "init-iptables-cpu-limit")) -}}
      cpu: "{{ index .ObjectMeta.Annotations (withAP `init-iptables-cpu-limit`) }}"
      {{ end }}
      {{ if (isSet .ObjectMeta.Annotations (withAP "init-iptables-memory-limit")) -}}
      memory: "{{ index .ObjectMeta.Annotations (withAP `init-iptables-memory-limit`) }}"
      {{ end }}
    {{- end }}
  {{- else }}
    {{- if (index .Config.sidecar.initContainers.iptables "resources") }}
    {{ toYaml .Config.sidecar.initContainers.iptables.resources | indent 4 }}
    {{- end }}
  {{- end }}
{{- end }}

{{- define "initHelperContainer.resources" }}
  {{- if or (isSet .ObjectMeta.Annotations (withAP "init-helper-cpu")) (isSet .ObjectMeta.Annotations (withAP "init-helper-memory")) (isSet .ObjectMeta.Annotations (withAP "init-helper-cpu-limit")) (isSet .ObjectMeta.Annotations (withAP "init-helper-memory-limit")) }}
    {{- if or (isSet .ObjectMeta.Annotations (withAP "init-helper-cpu")) (isSet .ObjectMeta.Annotations (withAP "init-helper-memory")) }}
    requests:
      {{ if (isSet .ObjectMeta.Annotations (withAP "init-helper-cpu")) -}}
      cpu: "{{ index .ObjectMeta.Annotations (withAP `init-helper-cpu`) }}"
      {{ end }}
      {{ if (isSet .ObjectMeta.Annotations (withAP "init-helper-memory")) -}}
      memory: "{{ index .ObjectMeta.Annotations (withAP `init-helper-memory`) }}"
      {{ end }}
    {{- end }}
    {{- if or (isSet .ObjectMeta.Annotations (withAP "init-helper-cpu-limit")) (isSet .ObjectMeta.Annotations (withAP "init-helper-memory-limit")) }}
    limits:
      {{ if (isSet .ObjectMeta.Annotations (withAP "init-helper-cpu-limit")) -}}
      cpu: "{{ index .ObjectMeta.Annotations (withAP `init-helper-cpu-limit`) }}"
      {{ end }}
      {{ if (isSet .ObjectMeta.Annotations (withAP "init-helper-memory-limit")) -}}
      memory: "{{ index .ObjectMeta.Annotations (withAP `init-helper-memory-limit`) }}"
      {{ end }}
    {{- end }}
  {{- else }}
    {{- if (index .Config.sidecar.initContainers.helper "resources") }}
    {{ toYaml .Config.sidecar.initContainers.helper.resources | indent 4 }}
    {{- end }}
  {{- end }}
{{- end }}

{{- define "proxyContainer.resources" }}
  {{- if or (isSet .ObjectMeta.Annotations (withAP "proxy-cpu")) (isSet .ObjectMeta.Annotations (withAP "proxy-memory")) (isSet .ObjectMeta.Annotations (withAP "proxy-cpu-limit")) (isSet .ObjectMeta.Annotations (withAP "proxy-memory-limit")) }}
    {{- if or (isSet .ObjectMeta.Annotations (withAP "proxy-cpu")) (isSet .ObjectMeta.Annotations (withAP "proxy-memory")) }}
    requests:
      {{ if (isSet .ObjectMeta.Annotations (withAP "proxy-cpu")) -}}
      cpu: "{{ index .ObjectMeta.Annotations (withAP `proxy-cpu`) }}"
      {{ end }}
      {{ if (isSet .ObjectMeta.Annotations (withAP "proxy-memory")) -}}
      memory: "{{ index .ObjectMeta.Annotations (withAP `proxy-memory`) }}"
      {{ end }}
    {{- end }}
    {{- if or (isSet .ObjectMeta.Annotations (withAP "proxy-cpu-limit")) (isSet .ObjectMeta.Annotations (withAP "proxy-memory-limit")) }}
    limits:
      {{ if (isSet .ObjectMeta.Annotations (withAP "proxy-cpu-limit")) -}}
      cpu: "{{ index .ObjectMeta.Annotations (withAP `proxy-cpu-limit`) }}"
      {{ end }}
      {{ if (isSet .ObjectMeta.Annotations (withAP "proxy-memory-limit")) -}}
      memory: "{{ index .ObjectMeta.Annotations (withAP `proxy-memory-limit`) }}"
      {{ end }}
    {{- end }}
  {{- else }}
    {{- if (index .Config.sidecar.containers.proxy "resources") }}
    {{ toYaml .Config.sidecar.containers.proxy.resources | indent 4 }}
    {{- end }}
  {{- end }}
{{- end }}

{{- define "volumes" }}
  - name: wallarm
    emptyDir: {}
  - name: wallarm-acl
    emptyDir: {}
  - name: wallarm-cache
    emptyDir: {}
  - name: wallarm-api
    emptyDir: {}
{{- if and .Profile (index .Profile "sidecar") -}}
  {{- with .Profile.sidecar.volumes }}
  {{ . | toYaml | indent 2 }}
  {{- end }}
{{- end -}}
{{- if (isSet .ObjectMeta.Annotations (withAP "proxy-extra-volumes")) -}}
  {{ range $index, $value := fromJson (index .ObjectMeta.Annotations (withAP "proxy-extra-volumes")) }}
  - name: "{{ $index }}"
    {{ toYaml $value | indent 4 }}
  {{ end }}
{{- end -}}
{{- end }}

{{/*
Wcli arguments building
*/}}
{{- define "wcli-args" -}}
"-log-level", "{{ .Config.cron.logLevel }}",{{ " " }}
{{- with .Config.cron.commands -}}
{{- range $name, $value := . -}}
"job:{{ $name }}", "-log-level", "{{ $value.logLevel }}",{{ " " }}
{{- end -}}
{{- end -}}
{{- end -}}
