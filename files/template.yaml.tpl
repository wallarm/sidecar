initContainers:
{{ if ((getAnnotation .ObjectMeta "sidecar-injection-iptables-enable" .Config.injectionStrategy.iptablesEnable) | toBool) -}}
  {{ template "initIptablesContainer" . }}
{{- end }}
{{ if eq (getAnnotation .ObjectMeta "sidecar-injection-schema" .Config.injectionStrategy.scheme) "split" -}}
  {{ template "initHelperContainer" . }}
{{- end }}

containers:
{{ if eq (getAnnotation .ObjectMeta "sidecar-injection-schema" .Config.injectionStrategy.scheme) "split" -}}
  {{ template "helperContainer" . }}
{{- end }}
  {{ template "proxyContainer" . }}

volumes:
  - name: wallarm
    emptyDir: {}
  - name: wallarm-acl
    emptyDir: {}
  - name: wallarm-cache
    emptyDir: {}
{{ if (isSet .ObjectMeta.Annotations "proxy-extra-volumes") -}}
  {{ range $index, $value := fromJson (index .ObjectMeta.Annotations (withAP "proxy-extra-volumes")) }}
  - name: "{{ $index }}"
    {{ toYaml $value | indent 4 }}
  {{ end }}
{{- end }}


{{ define "proxyContainer" }}
- name: sidecar-proxy
  image: {{ template "image" . }}
  imagePullPolicy: {{ .Config.sidecar.image.pullPolicy }}
  {{ if eq (getAnnotation .ObjectMeta "sidecar-injection-scheme" .Config.injectionStrategy.scheme) "split" -}}
  command: ["/usr/local/run-nginx.sh"]
  {{- else }}
  command: ["/usr/local/run-node.sh"]
  {{- end }}
  env:
    {{ if ne (getAnnotation .ObjectMeta "sidecar-injection-schema" .Config.injectionStrategy.scheme) "split" -}}
    {{ template "wallarmApiVariables" . }}
    {{ template "wallarmCronVariables" . }}
      #TODO Determine proper way to identify sidecar version
    - name: WALLARM_INGRESS_CONTROLLER_VERSION
      value: "{{ .Config.version }}"
    {{- end  }}
    {{ if (isSet .ObjectMeta.Annotations "wallarm-application") -}}
    - name: WALLARM_APPLICATION
      value: "{{ index .ObjectMeta.Annotations (withAP `wallarm-application`) }}"
    {{- end  }}
    - name: WALLARM_MODE
      value: "{{ getAnnotation .ObjectMeta `wallarm-mode` .Config.wallarm.mode }}"
    - name: WALLARM_MODE_ALLOW_OVERRIDE
      value: "{{ getAnnotation .ObjectMeta `wallarm-mode-allow-override` .Config.wallarm.modeAllowOverride }}"
    - name: WALLARM_PARSE_RESPONSE
      value: "{{ getAnnotation .ObjectMeta `wallarm-parse-response` .Config.wallarm.parseResponse }}"
    - name: WALLARM_PARSE_WEBSOCKET
      value: "{{ getAnnotation .ObjectMeta `wallarm-parse-websocket` .Config.wallarm.parseWebsocket }}"
    - name: WALLARM_UNPACK_RESPONSE
      value: "{{ getAnnotation .ObjectMeta `wallarm-unpack-response` .Config.wallarm.unpackResponse }}"
    - name: WALLARM_TARANTOOL_HOST
      value: "{{ .Config.tarantool.host }}"
    - name: WALLARM_UPSTREAM_CONNECT_ATTEMPTS
      value: "{{ getAnnotation .ObjectMeta `wallarm-upstream-connect-attempts` .Config.wallarm.upstream.connectAttempts }}"
    - name: WALLARM_UPSTREAM_RECONNECT_INTERVAL
      value: "{{ getAnnotation .ObjectMeta `wallarm-upstream-reconnect-interval` .Config.wallarm.upstream.reconnectInterval }}"
    - name: NGINX_LISTEN_PORT
      value: "{{ getAnnotation .ObjectMeta `nginx-listen-port` .Config.nginx.listenPort }}"
    - name: NGINX_PROXY_PASS_PORT
      value: "{{ template `applicationPort` . }}"
    - name: NGINX_STATUS_PORT
      value: "{{ getAnnotation .ObjectMeta `nginx-status-port` .Config.nginx.statusPort }}"
    - name: NGINX_STATUS_PATH
      value: "{{ getAnnotation .ObjectMeta `nginx-status-path` .Config.nginx.statusPath }}"
    - name: NGINX_HEALTH_PATH
      value: "{{ getAnnotation .ObjectMeta `nginx-health-path` .Config.nginx.healthPath }}"
    - name: NGINX_WALLARM_STATUS_PATH
      value: "{{ getAnnotation .ObjectMeta `nginx-wallarm-status-path` .Config.nginx.wallarmStatusPath }}"
    - name: NGINX_WALLARM_METRICS_PORT
      value: "{{ getAnnotation .ObjectMeta `nginx-wallarm-metrics-port` .Config.nginx.wallarmMetricsPort }}"
    - name: NGINX_WALLARM_METRICS_PATH
      value: "{{ getAnnotation .ObjectMeta `nginx-wallarm-metrics-path` .Config.nginx.wallarmMetricsPath }}"
    {{ if (isSet .ObjectMeta.Annotations "nginx-http-include") -}}
    - name: NGINX_HTTP_INCLUDE
      value: "{{ index .ObjectMeta.Annotations (withAP `nginx-http-include`) }}"
    {{- end }}
    {{ if (isSet .ObjectMeta.Annotations "nginx-server-include") -}}
    - name: NGINX_SERVER_INCLUDE
      value: "{{ index .ObjectMeta.Annotations (withAP `nginx-server-include`) }}"
    {{- end }}
    {{ if (isSet .ObjectMeta.Annotations "nginx-location-include") -}}
    - name: NGINX_LOCATION_INCLUDE
      value: "{{ index .ObjectMeta.Annotations (withAP `nginx-location-include`) }}"
    {{- end }}
    {{ if (isSet .ObjectMeta.Annotations "nginx-extra-modules") -}}
    - name: NGINX_EXTRA_MODULES
      value: "{{ index .ObjectMeta.Annotations (withAP `nginx-extra-modules`) }}"
    {{- end }}
  ports:
    - name: status
      containerPort: {{ getAnnotation .ObjectMeta "nginx-status-port" .Config.nginx.statusPort }}
      protocol: TCP
    - name: metrics
      containerPort: {{ getAnnotation .ObjectMeta "nginx-wallarm-metrics-port" .Config.nginx.wallarmMetricsPort }}
      protocol: TCP
    {{ if not ((getAnnotation .ObjectMeta "sidecar-injection-iptables-enable" .Config.injectionStrategy.iptablesEnable) | toBool) -}}
    - name: proxy
      containerPort: {{ getAnnotation .ObjectMeta "nginx-listen-port" .Config.nginx.listenPort }}
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
    - mountPath: /etc/wallarm
      name: wallarm
    - mountPath: /var/lib/wallarm-acl
      name: wallarm-acl
    - mountPath: /var/lib/nginx/wallarm/
      name: wallarm-cache
    {{- if (isSet .ObjectMeta.Annotations "proxy-extra-volume-mounts") }}
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
  command: ["supervisord", "-c", "/etc/supervisor/supervisord.helper.conf"]
  env:
    {{ template "wallarmApiVariables" . }}
    {{ template "wallarmCronVariables" . }}
    - name: WALLARM_SYNCNODE_OWNER
      value: www-data
    - name: WALLARM_SYNCNODE_GROUP
      value: www-data
      #TODO Determine proper way to identify sidecar version
    - name: WALLARM_INGRESS_CONTROLLER_VERSION
      value: "{{ .Config.version }}"
  volumeMounts:
    - mountPath: /etc/wallarm
      name: wallarm
    - mountPath: /var/lib/wallarm-acl
      name: wallarm-acl
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
    - name: WALLARM_SYNCNODE_OWNER
      value: www-data
    - name: WALLARM_SYNCNODE_GROUP
      value: www-data
      #TODO Determine proper way to identify sidecar version
    - name: WALLARM_INGRESS_CONTROLLER_VERSION
      value: "{{ .Config.version }}"
  volumeMounts:
    - mountPath: /etc/wallarm
      name: wallarm
    - mountPath: /var/lib/wallarm-acl
      name: wallarm-acl
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
      value: "{{ getAnnotation .ObjectMeta "nginx-listen-port" .Config.nginx.listenPort }}"
  command: ["iptables"]
  args: ["-t", "nat", "-A", "PREROUTING", "-p", "tcp", "-d", "$(POD_IP)", "--dport", "$(APP_PORT)", "-j", "REDIRECT", "--to-ports", "$(NGINX_PORT)"]
  securityContext:
    {{ toYaml .Config.sidecar.initContainers.iptables.securityContext | indent 4 }}
  resources:
{{ template "initIptablesContainer.resources" . }}
{{ end }}

{{- define "image" }}
  {{- if (isSet .ObjectMeta.Annotations "proxy-image") }}
{{ index .ObjectMeta.Annotations (withAP "proxy-image") }}
  {{- else }}
    {{- if (index .Config.sidecar.image "registry") }}
{{- printf "%s/%s:%s" .Config.sidecar.image.registry .Config.sidecar.image.image .Config.sidecar.image.tag }}
    {{- else }}
{{- printf "%s:%s" .Config.sidecar.image.image .Config.sidecar.image.tag }}
    {{- end }}
  {{- end }}
{{- end }}

{{- define "applicationPort" }}
  {{- if (isSet .ObjectMeta.Annotations "application-port") }}
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
      value: "{{ .Config.wallarm.api.token }}"
    - name: WALLARM_API_USE_SSL
      value: "{{ .Config.wallarm.api.useSSL }}"
    - name: WALLARM_API_CA_VERIFY
      value: "{{ .Config.wallarm.api.caVerify }}"
{{- end }}

{{- define "wallarmCronVariables" }}
    - name: WALLARM_CRON_EXPORT_ENV_SCHEDULE
      value: "{{ .Config.wallarm.cron.exportEnvironment.schedule }}"
    - name: WALLARM_CRON_EXPORT_ENV_TIMEOUT
      value: "{{ .Config.wallarm.cron.exportEnvironment.timeout }}"
    - name: WALLARM_CRON_EXPORT_ENV_COMMAND
      value: "{{ .Config.wallarm.cron.exportEnvironment.command }}"
    - name: WALLARM_CRON_EXPORT_METRICS_SCHEDULE
      value: "{{ .Config.wallarm.cron.exportMetrics.schedule }}"
    - name: WALLARM_CRON_EXPORT_METRICS_TIMEOUT
      value: "{{ .Config.wallarm.cron.exportMetrics.timeout }}"
    - name: WALLARM_CRON_EXPORT_METRICS_COMMAND
      value: "{{ .Config.wallarm.cron.exportMetrics.command }}"
    - name: WALLARM_CRON_SYNC_IP_LISTS_SCHEDULE
      value: "{{ .Config.wallarm.cron.syncIpLists.schedule }}"
    - name: WALLARM_CRON_SYNC_IP_LISTS_TIMEOUT
      value: "{{ .Config.wallarm.cron.syncIpLists.timeout }}"
    - name: WALLARM_CRON_SYNC_IP_LISTS_COMMAND
      value: "{{ .Config.wallarm.cron.syncIpLists.command }}"
    - name: WALLARM_CRON_SYNC_IP_LISTS_SOURCE_SCHEDULE
      value: "{{ .Config.wallarm.cron.syncIpListsSource.schedule }}"
    - name: WALLARM_CRON_SYNC_IP_LISTS_SOURCE_TIMEOUT
      value: "{{ .Config.wallarm.cron.syncIpListsSource.timeout }}"
    - name: WALLARM_CRON_SYNC_IP_LISTS_SOURCE_COMMAND
      value: "{{ .Config.wallarm.cron.syncIpListsSource.command }}"
{{- end }}

{{- define "helperContainer.resources" }}
  {{- if or (isSet .ObjectMeta.Annotations "helper-cpu") (isSet .ObjectMeta.Annotations "helper-memory") (isSet .ObjectMeta.Annotations "helper-cpu-limit") (isSet .ObjectMeta.Annotations "helper-memory-limit") }}
    {{- if or (isSet .ObjectMeta.Annotations "helper-cpu") (isSet .ObjectMeta.Annotations "helper-memory") }}
    requests:
      {{ if (isSet .ObjectMeta.Annotations "helper-cpu") -}}
      cpu: "{{ index .ObjectMeta.Annotations (withAP `helper-cpu`) }}"
      {{ end }}
      {{ if (isSet .ObjectMeta.Annotations "helper-memory") -}}
      memory: "{{ index .ObjectMeta.Annotations (withAP `helper-memory`) }}"
      {{ end }}
  {{- end }}
  {{- if or (isSet .ObjectMeta.Annotations "helper-cpu-limit") (isSet .ObjectMeta.Annotations "helper-memory-limit") }}
    limits:
      {{ if (isSet .ObjectMeta.Annotations "helper-cpu-limit") -}}
      cpu: "{{ index .ObjectMeta.Annotations (withAP `helper-cpu-limit`) }}"
      {{ end }}
      {{ if (isSet .ObjectMeta.Annotations "helper-memory-limit") -}}
      memory: "{{ index .ObjectMeta.Annotations (withAP `helper-memory-limit`) }}"
      {{ end }}
    {{- end }}
  {{- else }}
    {{- if (index .Config.sidecar.containers.helper (withAP "resources")) }}
    {{ toYaml .Config.sidecar.containers.helper.resources | indent 4 }}
    {{- end }}
  {{- end }}
{{- end }}

{{- define "initIptablesContainer.resources" }}
  {{- if or (isSet .ObjectMeta.Annotations "init-iptables-cpu") (isSet .ObjectMeta.Annotations "init-iptables-memory") (isSet .ObjectMeta.Annotations "init-iptables-cpu-limit") (isSet .ObjectMeta.Annotations "init-iptables-memory-limit") }}
    {{- if or (isSet .ObjectMeta.Annotations "init-iptables-cpu") (isSet .ObjectMeta.Annotations "init-iptables-memory") }}
    requests:
      {{ if (isSet .ObjectMeta.Annotations "init-iptables-cpu") -}}
      cpu: "{{ index .ObjectMeta.Annotations (withAP `init-iptables-cpu`) }}"
      {{ end }}
      {{ if (isSet .ObjectMeta.Annotations "init-iptables-memory") -}}
      memory: "{{ index .ObjectMeta.Annotations (withAP `init-iptables-memory`) }}"
      {{ end }}
    {{- end }}
    {{- if or (isSet .ObjectMeta.Annotations "init-iptables-cpu-limit") (isSet .ObjectMeta.Annotations "init-iptables-memory-limit") }}
    limits:
      {{ if (isSet .ObjectMeta.Annotations "init-iptables-cpu-limit") -}}
      cpu: "{{ index .ObjectMeta.Annotations (withAP `init-iptables-cpu-limit`) }}"
      {{ end }}
      {{ if (isSet .ObjectMeta.Annotations "init-iptables-memory-limit") -}}
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
  {{- if or (isSet .ObjectMeta.Annotations "init-helper-cpu") (isSet .ObjectMeta.Annotations "init-helper-memory") (isSet .ObjectMeta.Annotations "init-helper-cpu-limit") (isSet .ObjectMeta.Annotations "init-helper-memory-limit") }}
    {{- if or (isSet .ObjectMeta.Annotations "init-helper-cpu") (isSet .ObjectMeta.Annotations "init-helper-memory") }}
    requests:
      {{ if (isSet .ObjectMeta.Annotations "init-helper-cpu") -}}
      cpu: "{{ index .ObjectMeta.Annotations (withAP `init-helper-cpu`) }}"
      {{ end }}
      {{ if (isSet .ObjectMeta.Annotations "init-helper-memory") -}}
      memory: "{{ index .ObjectMeta.Annotations (withAP `init-helper-memory`) }}"
      {{ end }}
    {{- end }}
    {{- if or (isSet .ObjectMeta.Annotations "init-helper-cpu-limit") (isSet .ObjectMeta.Annotations "init-helper-memory-limit") }}
    limits:
      {{ if (isSet .ObjectMeta.Annotations "init-helper-cpu-limit") -}}
      cpu: "{{ index .ObjectMeta.Annotations (withAP `init-helper-cpu-limit`) }}"
      {{ end }}
      {{ if (isSet .ObjectMeta.Annotations "init-helper-memory-limit") -}}
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
  {{- if or (isSet .ObjectMeta.Annotations "proxy-cpu") (isSet .ObjectMeta.Annotations "proxy-memory") (isSet .ObjectMeta.Annotations "proxy-cpu-limit") (isSet .ObjectMeta.Annotations "proxy-memory-limit") }}
    {{- if or (isSet .ObjectMeta.Annotations "proxy-cpu") (isSet .ObjectMeta.Annotations "proxy-memory") }}
    requests:
      {{ if (isSet .ObjectMeta.Annotations "proxy-cpu") -}}
      cpu: "{{ index .ObjectMeta.Annotations (withAP `proxy-cpu`) }}"
      {{ end }}
      {{ if (isSet .ObjectMeta.Annotations "proxy-memory") -}}
      memory: "{{ index .ObjectMeta.Annotations (withAP `proxy-memory`) }}"
      {{ end }}
    {{- end }}
    {{- if or (isSet .ObjectMeta.Annotations "proxy-cpu-limit") (isSet .ObjectMeta.Annotations "proxy-memory-limit") }}
    limits:
      {{ if (isSet .ObjectMeta.Annotations "proxy-cpu-limit") -}}
      cpu: "{{ index .ObjectMeta.Annotations (withAP `proxy-cpu-limit`) }}"
      {{ end }}
      {{ if (isSet .ObjectMeta.Annotations "proxy-memory-limit") -}}
      memory: "{{ index .ObjectMeta.Annotations (withAP `proxy-memory-limit`) }}"
      {{ end }}
    {{- end }}
  {{- else }}
    {{- if (index .Config.sidecar.containers.proxy "resources") }}
    {{ toYaml .Config.sidecar.containers.proxy.resources | indent 4 }}
    {{- end }}
  {{- end }}
{{- end }}