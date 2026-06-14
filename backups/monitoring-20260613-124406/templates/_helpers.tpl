{{- define "monitoring.namespace" -}}
{{- .Values.namespace.name -}}
{{- end -}}

{{- define "monitoring.labels" -}}
app.kubernetes.io/managed-by: Helm
app.kubernetes.io/part-of: kl-monitoring
{{- end -}}
