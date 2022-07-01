{{- define "podDisruptionBudget.apiVersion" -}}
{{- if .Capabilities.APIVersions.Has "policy/v1/PodDisruptionBudget" -}}
{{- print "policy/v1" -}}
{{- else  -}}
{{- print "policy/v1beta1" -}}
{{- end -}}
{{- end -}}
