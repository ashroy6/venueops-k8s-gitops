{{- define "venueops.namespace" -}}
{{- .Values.namespace.name -}}
{{- end -}}

{{- define "venueops.labels" -}}
app.kubernetes.io/managed-by: Helm
app.kubernetes.io/part-of: venueops
{{- end -}}
