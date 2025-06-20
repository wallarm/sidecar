{{/*
Expand the name of the chart.
*/}}
{{- define "wallarm-sidecar.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "wallarm-sidecar.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "wallarm-sidecar.labels" -}}
{{ include "wallarm-sidecar.selectorLabels" . }}
app.kubernetes.io/app: {{ template "wallarm-sidecar.name" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service | quote }}
{{- if .Values.extraLabels }}
{{- .Values.extraLabels | toYaml }}
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "wallarm-sidecar.selectorLabels" -}}
app.kubernetes.io/name: {{ include "wallarm-sidecar.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Basic annotations
*/}}
{{- define "wallarm-sidecar.annotations" -}}
{{- if .Values.extraAnnotations }}
{{- .Values.extraAnnotations | toYaml }}
{{- end }}
{{- end }}

{{/*
Create the name of the service account for postanalytics
*/}}
{{- define "wallarm-sidecar.postanalytics.serviceAccountName" -}}
{{- if .Values.postanalytics.serviceAccount.create -}}
{{- include "wallarm-sidecar.fullname" . }}-postanalytics
{{- else -}}
{{- .Values.postanalytics.serviceAccount.name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
Create the name of the service account for controller
*/}}
{{- define "wallarm-sidecar.controller.serviceAccountName" -}}
{{- if .Values.controller.serviceAccount.create -}}
{{- include "wallarm-sidecar.fullname" . }}-controller
{{- else -}}
{{- .Values.controller.serviceAccount.name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
Gives name of image to use
*/}}
{{- define "wallarm-sidecar.image" -}}
{{- if .fullname -}}
{{- .fullname -}}
{{- else -}}
{{- if .registry -}}
{{- printf "%s/%s:%s" .registry .image .tag -}}
{{- else -}}
{{- printf "%s:%s" .image .tag -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "wallarm-sidecar.credentials" -}}
- name: WALLARM_API_HOST
  valueFrom:
    secretKeyRef:
      key: WALLARM_API_HOST
      name: {{ template "wallarm-sidecar.fullname" . }}-credentials
- name: WALLARM_API_PORT
  valueFrom:
    secretKeyRef:
      key: WALLARM_API_PORT
      name: {{ template "wallarm-sidecar.fullname" . }}-credentials
- name: WALLARM_API_USE_SSL
  valueFrom:
    secretKeyRef:
      key: WALLARM_API_USE_SSL
      name: {{ template "wallarm-sidecar.fullname" . }}-credentials
- name: WALLARM_API_CA_VERIFY
  valueFrom:
    secretKeyRef:
      key: WALLARM_API_CA_VERIFY
      name: {{ template "wallarm-sidecar.fullname" . }}-credentials
- name: WALLARM_LABELS
  valueFrom:
    secretKeyRef:
      key: WALLARM_LABELS
      name: {{ template "wallarm-sidecar.fullname" . }}-credentials
- name: WALLARM_API_TOKEN
  valueFrom:
    secretKeyRef:
      {{- $existingSecret := index .Values.config.wallarm.api "existingSecret" | default dict }}
      {{- if $existingSecret.enabled }}
      key: {{ $existingSecret.secretKey }}
      name: {{ $existingSecret.secretName }}
      {{- else }}
      key: WALLARM_API_TOKEN
      name: {{ template "wallarm-sidecar.fullname" . }}-credentials
      {{- end }}
{{- end -}}

{{/*
The name of Wallarm component
*/}}
{{- define "wallarm-sidecar.componentName" -}}
wallarm-sidecar-proxy
{{- end -}}

{{- define "wallarm-sidecar.version" -}}
- name: WALLARM_COMPONENT_NAME
  value: {{ template "wallarm-sidecar.componentName" . }}
- name: WALLARM_COMPONENT_VERSION
  value: {{ .Chart.Version | quote }}
{{- end -}}

{{- define "wallarm-sidecar.wstoreHost" -}}
{{- if .Values.postanalytics.external.enabled }}
{{- required "Hostname of external wstore instance is required" .Values.postanalytics.external.host }}
{{- else }}
{{- template "wallarm-sidecar.fullname" . }}-postanalytics.{{ .Release.Namespace }}.svc
{{- end }}
{{- end -}}

{{- define "wallarm-sidecar.wstorePort" -}}
{{- if .Values.postanalytics.external.enabled }}
{{- required "Port of external wstore instance is required" .Values.postanalytics.external.port }}
{{- else }}
{{- .Values.postanalytics.service.port }}
{{- end }}
{{- end -}}

{{/*
Wcli arguments building
*/}}
{{- define "wallarm-sidecar.wcli-args" -}}
"-log-level", "{{ .Values.config.wcli.logLevel }}",{{ " " }}
{{- with .Values.config.wcli.commands -}}
{{- range $name, $value := . -}}
"job:{{ $name }}", "-log-level", "{{ $value.logLevel }}",{{ " " }}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "wallarm-sidecar.wstoreTlsVariables" -}}
- name: WALLARM_WSTORE__SERVICE__TLS__ENABLED
  value: "{{ .Values.postanalytics.wstore.tls.enabled }}"
- name: WALLARM_WSTORE__SERVICE__TLS__CERT_FILE
  value: "{{ .Values.postanalytics.wstore.tls.certFile }}"
- name: WALLARM_WSTORE__SERVICE__TLS__KEY_FILE
  value: "{{ .Values.postanalytics.wstore.tls.keyFile }}"
- name: WALLARM_WSTORE__SERVICE__TLS__CA_CERT_FILE
  value: "{{ .Values.postanalytics.wstore.tls.caCertFile }}"
- name: WALLARM_WSTORE__SERVICE__TLS__MUTUAL_TLS__ENABLED
  value: "{{ .Values.postanalytics.wstore.tls.mutualTLS.enabled }}"
- name: WALLARM_WSTORE__SERVICE__TLS__MUTUAL_TLS__CLIENT_CA_CERT_FILE
  value: "{{ .Values.postanalytics.wstore.tls.mutualTLS.clientCACertFile }}"
{{- end -}}
