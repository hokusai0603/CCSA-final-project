{{/* Base name for every resource: the release name, trimmed to the DNS label limit. */}}
{{- define "drawguess.fullname" -}}
{{- .Release.Name | trunc 50 | trimSuffix "-" -}}
{{- end -}}

{{/* Common labels. Call with (dict "ctx" $ "component" "redis"). */}}
{{- define "drawguess.labels" -}}
app.kubernetes.io/name: drawguess
app.kubernetes.io/instance: {{ .ctx.Release.Name }}
app.kubernetes.io/component: {{ .component }}
app.kubernetes.io/part-of: drawguess
app.kubernetes.io/managed-by: {{ .ctx.Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .ctx.Chart.Name .ctx.Chart.Version }}
{{- end -}}

{{/* Selector labels: must never change for an existing StatefulSet/Deployment. */}}
{{- define "drawguess.selectorLabels" -}}
app.kubernetes.io/instance: {{ .ctx.Release.Name }}
app.kubernetes.io/component: {{ .component }}
{{- end -}}

{{- define "drawguess.redis.fullname" -}}{{ include "drawguess.fullname" . }}-redis{{- end -}}
{{- define "drawguess.postgres.fullname" -}}{{ include "drawguess.fullname" . }}-postgres{{- end -}}

{{/* Name of the Secret holding the PostgreSQL password (key "password"). */}}
{{- define "drawguess.postgres.secretName" -}}
{{- if .Values.postgres.auth.existingSecret -}}
{{- .Values.postgres.auth.existingSecret -}}
{{- else -}}
{{- include "drawguess.postgres.fullname" . -}}
{{- end -}}
{{- end -}}

{{/* storageClassName line for a PVC template, omitted for the cluster default. */}}
{{- define "drawguess.storageClass" -}}
{{- if .Values.global.storageClass }}
storageClassName: {{ .Values.global.storageClass | quote }}
{{- end }}
{{- end -}}

{{/* Restricted pod-security settings for a container. */}}
{{- define "drawguess.containerSecurityContext" -}}
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
capabilities:
  drop: [ALL]
{{- end -}}
