$ErrorActionPreference = "Stop"

$Root = "C:\KL"
$Chart = Join-Path $Root "helm\monitoring"
$Templates = Join-Path $Chart "templates"
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$Backup = Join-Path $Root "backups\monitoring-$Timestamp"

if (-not (Test-Path $Chart)) {
    throw "Monitoring chart not found: $Chart"
}

New-Item -ItemType Directory -Force -Path (Split-Path $Backup) | Out-Null
Copy-Item -Recurse -Force $Chart $Backup

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )
    $Parent = Split-Path $Path
    if (-not (Test-Path $Parent)) {
        New-Item -ItemType Directory -Force -Path $Parent | Out-Null
    }
    [System.IO.File]::WriteAllText(
        $Path,
        $Content,
        [System.Text.UTF8Encoding]::new($false)
    )
}

$OldCombinedFiles = @(
    "30-prometheus.yaml",
    "41-grafana.yaml",
    "50-node-exporter.yaml",
    "60-kube-state-metrics.yaml",
    "70-pdb.yaml"
)

foreach ($File in $OldCombinedFiles) {
    $Path = Join-Path $Templates $File
    if (Test-Path $Path) {
        Remove-Item -Force $Path
    }
}

Write-Utf8NoBom (Join-Path $Chart "values.yaml") @'
namespace:
  create: true
  name: monitoring

prometheus:
  enabled: true
  replicas: 1
  image: prom/prometheus:v2.55.1
  imagePullPolicy: IfNotPresent
  serviceAccountName: prometheus
  revisionHistoryLimit: 3
  terminationGracePeriodSeconds: 60

  strategy:
    type: Recreate

  nodeSelector:
    node-role.kubernetes.io/worker: worker

  retention: 6h

  service:
    type: NodePort
    port: 9090
    nodePort: 30090

  pdb:
    enabled: false
    maxUnavailable: 1
    unhealthyPodEvictionPolicy: AlwaysAllow

  securityContext:
    runAsNonRoot: true
    runAsUser: 65534
    runAsGroup: 65534
    fsGroup: 65534
    fsGroupChangePolicy: OnRootMismatch
    seccompProfile:
      type: RuntimeDefault

  containerSecurityContext:
    allowPrivilegeEscalation: false
    readOnlyRootFilesystem: true
    capabilities:
      drop:
        - ALL

  probes:
    startup:
      httpGet:
        path: /-/ready
        port: http
      periodSeconds: 5
      timeoutSeconds: 3
      failureThreshold: 30

    readiness:
      httpGet:
        path: /-/ready
        port: http
      periodSeconds: 10
      timeoutSeconds: 3
      failureThreshold: 3

    liveness:
      httpGet:
        path: /-/healthy
        port: http
      initialDelaySeconds: 30
      periodSeconds: 20
      timeoutSeconds: 3
      failureThreshold: 3

  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 768Mi

grafana:
  enabled: true
  replicas: 1
  image: grafana/grafana:11.3.1
  imagePullPolicy: IfNotPresent
  serviceAccountName: grafana
  revisionHistoryLimit: 3
  terminationGracePeriodSeconds: 30

  strategy:
    type: Recreate

  nodeSelector:
    node-role.kubernetes.io/worker: worker

  adminUser: admin
  adminPassword: admin

  service:
    type: NodePort
    port: 3000
    nodePort: 30300

  pdb:
    enabled: false
    maxUnavailable: 1
    unhealthyPodEvictionPolicy: AlwaysAllow

  securityContext:
    runAsNonRoot: true
    runAsUser: 472
    runAsGroup: 472
    fsGroup: 472
    fsGroupChangePolicy: OnRootMismatch
    seccompProfile:
      type: RuntimeDefault

  containerSecurityContext:
    allowPrivilegeEscalation: false
    readOnlyRootFilesystem: true
    capabilities:
      drop:
        - ALL

  probes:
    readiness:
      httpGet:
        path: /api/health
        port: http
      initialDelaySeconds: 10
      periodSeconds: 10
      timeoutSeconds: 3
      failureThreshold: 6

    liveness:
      httpGet:
        path: /api/health
        port: http
      initialDelaySeconds: 30
      periodSeconds: 20
      timeoutSeconds: 5
      failureThreshold: 3

  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 768Mi

nodeExporter:
  enabled: true
  image: prom/node-exporter:v1.8.2
  imagePullPolicy: IfNotPresent
  serviceAccountName: node-exporter
  port: 9100

  containerSecurityContext:
    allowPrivilegeEscalation: false
    readOnlyRootFilesystem: true
    capabilities:
      drop:
        - ALL

  probes:
    readiness:
      tcpSocket:
        port: metrics
      initialDelaySeconds: 5
      periodSeconds: 10
      timeoutSeconds: 3
      failureThreshold: 3

    liveness:
      tcpSocket:
        port: metrics
      initialDelaySeconds: 20
      periodSeconds: 20
      timeoutSeconds: 3
      failureThreshold: 3

  resources:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 200m
      memory: 128Mi

kubeStateMetrics:
  enabled: true
  image: registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.15.0
  imagePullPolicy: IfNotPresent
  serviceAccountName: kube-state-metrics
  replicas: 2
  revisionHistoryLimit: 3
  terminationGracePeriodSeconds: 30

  rollingUpdate:
    maxSurge: 1
    maxUnavailable: 0

  port: 8080
  telemetryPort: 8081

  nodeSelector:
    node-role.kubernetes.io/worker: worker

  pdb:
    enabled: true
    maxUnavailable: 1
    unhealthyPodEvictionPolicy: AlwaysAllow

  topologySpread:
    enabled: true
    maxSkew: 1
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: DoNotSchedule

  securityContext:
    runAsNonRoot: true
    runAsUser: 65534
    runAsGroup: 65534
    seccompProfile:
      type: RuntimeDefault

  containerSecurityContext:
    allowPrivilegeEscalation: false
    readOnlyRootFilesystem: true
    capabilities:
      drop:
        - ALL

  probes:
    startup:
      httpGet:
        path: /healthz
        port: http-metrics
      periodSeconds: 5
      timeoutSeconds: 3
      failureThreshold: 30

    readiness:
      httpGet:
        path: /readyz
        port: telemetry
      periodSeconds: 10
      timeoutSeconds: 3
      failureThreshold: 3

    liveness:
      httpGet:
        path: /livez
        port: http-metrics
      initialDelaySeconds: 20
      periodSeconds: 20
      timeoutSeconds: 3
      failureThreshold: 3

  resources:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 200m
      memory: 128Mi
'@

Write-Utf8NoBom (Join-Path $Templates "01-serviceaccounts.yaml") @'
{{- if .Values.prometheus.enabled }}
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ .Values.prometheus.serviceAccountName }}
  namespace: {{ include "monitoring.namespace" . }}
  labels:
    app: prometheus
automountServiceAccountToken: true
{{- end }}

{{- if .Values.grafana.enabled }}
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ .Values.grafana.serviceAccountName }}
  namespace: {{ include "monitoring.namespace" . }}
  labels:
    app: grafana
automountServiceAccountToken: false
{{- end }}

{{- if .Values.nodeExporter.enabled }}
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ .Values.nodeExporter.serviceAccountName }}
  namespace: {{ include "monitoring.namespace" . }}
  labels:
    app: node-exporter
automountServiceAccountToken: false
{{- end }}

{{- if .Values.kubeStateMetrics.enabled }}
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ .Values.kubeStateMetrics.serviceAccountName }}
  namespace: {{ include "monitoring.namespace" . }}
  labels:
    app: kube-state-metrics
automountServiceAccountToken: true
{{- end }}
'@

Write-Utf8NoBom (Join-Path $Templates "10-prometheus-rbac.yaml") @'
{{- if .Values.prometheus.enabled }}
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: prometheus-read
  labels:
    app: prometheus
rules:
  - apiGroups:
      - ""
    resources:
      - nodes
      - nodes/proxy
      - services
      - endpoints
      - pods
    verbs:
      - get
      - list
      - watch

  - apiGroups:
      - networking.k8s.io
    resources:
      - ingresses
    verbs:
      - get
      - list
      - watch

  - nonResourceURLs:
      - /metrics
    verbs:
      - get

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: prometheus-read-binding
  labels:
    app: prometheus
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: prometheus-read
subjects:
  - kind: ServiceAccount
    name: {{ .Values.prometheus.serviceAccountName }}
    namespace: {{ include "monitoring.namespace" . }}
{{- end }}
'@

Write-Utf8NoBom (Join-Path $Templates "20-prometheus-config.yaml") @'
{{- if .Values.prometheus.enabled }}
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-config
  namespace: {{ include "monitoring.namespace" . }}
  labels:
    app: prometheus
data:
  prometheus.yml: |
    global:
      scrape_interval: 15s
      evaluation_interval: 15s

    rule_files:
      - /etc/prometheus/rules/alert-rules.yml

    scrape_configs:
      - job_name: "prometheus"
        static_configs:
          - targets:
              - "localhost:9090"

      - job_name: "node-exporter"
        kubernetes_sd_configs:
          - role: pod
        relabel_configs:
          - source_labels:
              - __meta_kubernetes_namespace
            action: keep
            regex: monitoring

          - source_labels:
              - __meta_kubernetes_pod_label_app
            action: keep
            regex: node-exporter

          - source_labels:
              - __meta_kubernetes_pod_ip
            action: replace
            target_label: __address__
            replacement: "$1:9100"

          - source_labels:
              - __meta_kubernetes_pod_node_name
            action: replace
            target_label: node

          - source_labels:
              - __meta_kubernetes_pod_name
            action: replace
            target_label: pod

      - job_name: "kube-state-metrics"
        static_configs:
          - targets:
              - "kube-state-metrics.monitoring.svc.cluster.local:8080"

      - job_name: "kubernetes-pods"
        kubernetes_sd_configs:
          - role: pod
        relabel_configs:
          - source_labels:
              - __meta_kubernetes_pod_annotation_prometheus_io_scrape
            action: keep
            regex: "true"

          - source_labels:
              - __meta_kubernetes_pod_annotation_prometheus_io_path
            action: replace
            target_label: __metrics_path__
            regex: "(.+)"

          - source_labels:
              - __address__
              - __meta_kubernetes_pod_annotation_prometheus_io_port
            action: replace
            regex: '([^:]+)(?::\d+)?;(\d+)'
            replacement: '$1:$2'
            target_label: __address__

          - action: labelmap
            regex: __meta_kubernetes_pod_label_(.+)

          - source_labels:
              - __meta_kubernetes_namespace
            action: replace
            target_label: kubernetes_namespace

          - source_labels:
              - __meta_kubernetes_pod_name
            action: replace
            target_label: kubernetes_pod_name
{{- end }}
'@

Write-Utf8NoBom (Join-Path $Templates "21-prometheus-alert-rules.yaml") @'
{{- if .Values.prometheus.enabled }}
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-alert-rules
  namespace: {{ include "monitoring.namespace" . }}
  labels:
    app: prometheus
data:
  alert-rules.yml: |
    groups:
      - name: kubernetes-basic-health
        rules:
          - alert: KubernetesPodRestartingTooMuch
            expr: increase(kube_pod_container_status_restarts_total[10m]) > 3
            for: 2m
            labels:
              severity: warning
              category: kubernetes
            annotations:
              summary: "Pod is restarting too much"
              description: "Pod {{ "{{" }} $labels.namespace {{ "}}" }}/{{ "{{" }} $labels.pod {{ "}}" }} container {{ "{{" }} $labels.container {{ "}}" }} restarted more than 3 times in 10 minutes."

          - alert: KubernetesDeploymentReplicasUnavailable
            expr: kube_deployment_status_replicas_available < kube_deployment_spec_replicas
            for: 5m
            labels:
              severity: warning
              category: kubernetes
            annotations:
              summary: "Deployment has unavailable replicas"
              description: "Deployment {{ "{{" }} $labels.namespace {{ "}}" }}/{{ "{{" }} $labels.deployment {{ "}}" }} does not have all desired replicas available."

          - alert: KubernetesNodeNotReady
            expr: kube_node_status_condition{condition="Ready",status="true"} == 0
            for: 3m
            labels:
              severity: critical
              category: node
            annotations:
              summary: "Kubernetes node is not ready"
              description: "Node {{ "{{" }} $labels.node {{ "}}" }} has been NotReady for more than 3 minutes."

          - alert: PrometheusTargetDown
            expr: up == 0
            for: 2m
            labels:
              severity: warning
              category: monitoring
            annotations:
              summary: "Prometheus target is down"
              description: "Prometheus target {{ "{{" }} $labels.job {{ "}}" }} / {{ "{{" }} $labels.instance {{ "}}" }} has been down for more than 2 minutes."
{{- end }}
'@

Write-Utf8NoBom (Join-Path $Templates "30-prometheus-deployment.yaml") @'
{{- if .Values.prometheus.enabled }}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prometheus
  namespace: {{ include "monitoring.namespace" . }}
  labels:
    app: prometheus
spec:
  replicas: {{ .Values.prometheus.replicas }}
  revisionHistoryLimit: {{ .Values.prometheus.revisionHistoryLimit }}

  strategy:
    type: {{ .Values.prometheus.strategy.type }}

  selector:
    matchLabels:
      app: prometheus

  template:
    metadata:
      labels:
        app: prometheus

    spec:
      serviceAccountName: {{ .Values.prometheus.serviceAccountName }}
      automountServiceAccountToken: true
      terminationGracePeriodSeconds: {{ .Values.prometheus.terminationGracePeriodSeconds }}

      securityContext:
        {{- toYaml .Values.prometheus.securityContext | nindent 8 }}

      nodeSelector:
        {{- toYaml .Values.prometheus.nodeSelector | nindent 8 }}

      containers:
        - name: prometheus
          image: {{ .Values.prometheus.image | quote }}
          imagePullPolicy: {{ .Values.prometheus.imagePullPolicy }}

          securityContext:
            {{- toYaml .Values.prometheus.containerSecurityContext | nindent 12 }}

          args:
            - "--config.file=/etc/prometheus/config/prometheus.yml"
            - "--storage.tsdb.path=/prometheus"
            - "--storage.tsdb.retention.time={{ .Values.prometheus.retention }}"
            - "--web.enable-lifecycle"

          ports:
            - containerPort: 9090
              name: http
              protocol: TCP

          startupProbe:
            {{- toYaml .Values.prometheus.probes.startup | nindent 12 }}

          readinessProbe:
            {{- toYaml .Values.prometheus.probes.readiness | nindent 12 }}

          livenessProbe:
            {{- toYaml .Values.prometheus.probes.liveness | nindent 12 }}

          volumeMounts:
            - name: config
              mountPath: /etc/prometheus/config
              readOnly: true

            - name: rules
              mountPath: /etc/prometheus/rules
              readOnly: true

            - name: data
              mountPath: /prometheus

            - name: tmp
              mountPath: /tmp

          resources:
            {{- toYaml .Values.prometheus.resources | nindent 12 }}

      volumes:
        - name: config
          configMap:
            name: prometheus-config

        - name: rules
          configMap:
            name: prometheus-alert-rules

        - name: data
          emptyDir: {}

        - name: tmp
          emptyDir: {}
{{- end }}
'@

Write-Utf8NoBom (Join-Path $Templates "31-prometheus-service.yaml") @'
{{- if .Values.prometheus.enabled }}
apiVersion: v1
kind: Service
metadata:
  name: prometheus
  namespace: {{ include "monitoring.namespace" . }}
  labels:
    app: prometheus
spec:
  type: {{ .Values.prometheus.service.type }}
  selector:
    app: prometheus
  ports:
    - name: http
      protocol: TCP
      port: {{ .Values.prometheus.service.port }}
      targetPort: http
      {{- if eq .Values.prometheus.service.type "NodePort" }}
      nodePort: {{ .Values.prometheus.service.nodePort }}
      {{- end }}
{{- end }}
'@

Write-Utf8NoBom (Join-Path $Templates "32-prometheus-pdb.yaml") @'
{{- if and .Values.prometheus.enabled .Values.prometheus.pdb.enabled }}
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: prometheus-pdb
  namespace: {{ include "monitoring.namespace" . }}
  labels:
    app: prometheus
spec:
  maxUnavailable: {{ .Values.prometheus.pdb.maxUnavailable }}
  unhealthyPodEvictionPolicy: {{ .Values.prometheus.pdb.unhealthyPodEvictionPolicy }}
  selector:
    matchLabels:
      app: prometheus
{{- end }}
'@

Write-Utf8NoBom (Join-Path $Templates "40-grafana-configmaps.yaml") @'
{{- if .Values.grafana.enabled }}
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-datasource
  namespace: {{ include "monitoring.namespace" . }}
  labels:
    app: grafana
data:
  prometheus.yaml: |-
    apiVersion: 1
    datasources:
      - name: Prometheus
        uid: prometheus
        type: prometheus
        access: proxy
        url: http://prometheus:9090
        isDefault: true
        editable: false

---
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboard-provider
  namespace: {{ include "monitoring.namespace" . }}
  labels:
    app: grafana
data:
  dashboards.yaml: |-
    apiVersion: 1
    providers:
      - name: "KL Kubernetes Dashboards"
        orgId: 1
        folder: "KL Platform"
        type: file
        disableDeletion: true
        editable: false
        allowUiUpdates: false
        options:
          path: /var/lib/grafana/dashboards

---
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboards
  namespace: {{ include "monitoring.namespace" . }}
  labels:
    app: grafana
data:
  kl-node-overview.json: |-
{{ .Files.Get "files/grafana/dashboards/kl-node-overview.json" | indent 4 }}
{{- end }}
'@

Write-Utf8NoBom (Join-Path $Templates "41-grafana-secret.yaml") @'
{{- if .Values.grafana.enabled }}
apiVersion: v1
kind: Secret
metadata:
  name: grafana-admin-credentials
  namespace: {{ include "monitoring.namespace" . }}
  labels:
    app: grafana
type: Opaque
stringData:
  admin-user: {{ .Values.grafana.adminUser | quote }}
  admin-password: {{ .Values.grafana.adminPassword | quote }}
{{- end }}
'@

Write-Utf8NoBom (Join-Path $Templates "42-grafana-deployment.yaml") @'
{{- if .Values.grafana.enabled }}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: grafana
  namespace: {{ include "monitoring.namespace" . }}
  labels:
    app: grafana
spec:
  replicas: {{ .Values.grafana.replicas }}
  revisionHistoryLimit: {{ .Values.grafana.revisionHistoryLimit }}

  strategy:
    type: {{ .Values.grafana.strategy.type }}

  selector:
    matchLabels:
      app: grafana

  template:
    metadata:
      labels:
        app: grafana

    spec:
      serviceAccountName: {{ .Values.grafana.serviceAccountName }}
      automountServiceAccountToken: false
      terminationGracePeriodSeconds: {{ .Values.grafana.terminationGracePeriodSeconds }}

      securityContext:
        {{- toYaml .Values.grafana.securityContext | nindent 8 }}

      nodeSelector:
        {{- toYaml .Values.grafana.nodeSelector | nindent 8 }}

      containers:
        - name: grafana
          image: {{ .Values.grafana.image | quote }}
          imagePullPolicy: {{ .Values.grafana.imagePullPolicy }}

          securityContext:
            {{- toYaml .Values.grafana.containerSecurityContext | nindent 12 }}

          ports:
            - containerPort: 3000
              name: http
              protocol: TCP

          env:
            - name: GF_SECURITY_ADMIN_USER
              valueFrom:
                secretKeyRef:
                  name: grafana-admin-credentials
                  key: admin-user

            - name: GF_SECURITY_ADMIN_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: grafana-admin-credentials
                  key: admin-password

            - name: GF_USERS_ALLOW_SIGN_UP
              value: "false"

            - name: GF_LOG_MODE
              value: "console"

            - name: GF_PATHS_DATA
              value: /var/lib/grafana

            - name: GF_PATHS_LOGS
              value: /var/log/grafana

            - name: GF_PATHS_PLUGINS
              value: /var/lib/grafana/plugins

            - name: GF_PATHS_PROVISIONING
              value: /etc/grafana/provisioning

          readinessProbe:
            {{- toYaml .Values.grafana.probes.readiness | nindent 12 }}

          livenessProbe:
            {{- toYaml .Values.grafana.probes.liveness | nindent 12 }}

          volumeMounts:
            - name: grafana-data
              mountPath: /var/lib/grafana

            - name: grafana-logs
              mountPath: /var/log/grafana

            - name: grafana-tmp
              mountPath: /tmp

            - name: grafana-datasource
              mountPath: /etc/grafana/provisioning/datasources
              readOnly: true

            - name: grafana-dashboard-provider
              mountPath: /etc/grafana/provisioning/dashboards
              readOnly: true

            - name: grafana-dashboards
              mountPath: /var/lib/grafana/dashboards
              readOnly: true

          resources:
            {{- toYaml .Values.grafana.resources | nindent 12 }}

      volumes:
        - name: grafana-data
          emptyDir: {}

        - name: grafana-logs
          emptyDir: {}

        - name: grafana-tmp
          emptyDir: {}

        - name: grafana-datasource
          configMap:
            name: grafana-datasource

        - name: grafana-dashboard-provider
          configMap:
            name: grafana-dashboard-provider

        - name: grafana-dashboards
          configMap:
            name: grafana-dashboards
{{- end }}
'@

Write-Utf8NoBom (Join-Path $Templates "43-grafana-service.yaml") @'
{{- if .Values.grafana.enabled }}
apiVersion: v1
kind: Service
metadata:
  name: grafana
  namespace: {{ include "monitoring.namespace" . }}
  labels:
    app: grafana
spec:
  type: {{ .Values.grafana.service.type }}
  selector:
    app: grafana
  ports:
    - name: http
      protocol: TCP
      port: {{ .Values.grafana.service.port }}
      targetPort: http
      {{- if eq .Values.grafana.service.type "NodePort" }}
      nodePort: {{ .Values.grafana.service.nodePort }}
      {{- end }}
{{- end }}
'@

Write-Utf8NoBom (Join-Path $Templates "44-grafana-pdb.yaml") @'
{{- if and .Values.grafana.enabled .Values.grafana.pdb.enabled }}
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: grafana-pdb
  namespace: {{ include "monitoring.namespace" . }}
  labels:
    app: grafana
spec:
  maxUnavailable: {{ .Values.grafana.pdb.maxUnavailable }}
  unhealthyPodEvictionPolicy: {{ .Values.grafana.pdb.unhealthyPodEvictionPolicy }}
  selector:
    matchLabels:
      app: grafana
{{- end }}
'@

Write-Utf8NoBom (Join-Path $Templates "50-node-exporter-daemonset.yaml") @'
{{- if .Values.nodeExporter.enabled }}
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-exporter
  namespace: {{ include "monitoring.namespace" . }}
  labels:
    app: node-exporter
spec:
  selector:
    matchLabels:
      app: node-exporter

  template:
    metadata:
      labels:
        app: node-exporter
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: {{ .Values.nodeExporter.port | quote }}
        prometheus.io/path: /metrics

    spec:
      serviceAccountName: {{ .Values.nodeExporter.serviceAccountName }}
      automountServiceAccountToken: false
      hostNetwork: true
      hostPID: true
      dnsPolicy: ClusterFirstWithHostNet

      tolerations:
        - operator: Exists

      containers:
        - name: node-exporter
          image: {{ .Values.nodeExporter.image | quote }}
          imagePullPolicy: {{ .Values.nodeExporter.imagePullPolicy }}

          securityContext:
            {{- toYaml .Values.nodeExporter.containerSecurityContext | nindent 12 }}

          args:
            - "--path.rootfs=/host"
            - "--web.listen-address=0.0.0.0:{{ .Values.nodeExporter.port }}"

          ports:
            - name: metrics
              containerPort: {{ .Values.nodeExporter.port }}
              protocol: TCP

          readinessProbe:
            {{- toYaml .Values.nodeExporter.probes.readiness | nindent 12 }}

          livenessProbe:
            {{- toYaml .Values.nodeExporter.probes.liveness | nindent 12 }}

          volumeMounts:
            - name: rootfs
              mountPath: /host
              readOnly: true

          resources:
            {{- toYaml .Values.nodeExporter.resources | nindent 12 }}

      volumes:
        - name: rootfs
          hostPath:
            path: /
            type: Directory
{{- end }}
'@

Write-Utf8NoBom (Join-Path $Templates "51-node-exporter-service.yaml") @'
{{- if .Values.nodeExporter.enabled }}
apiVersion: v1
kind: Service
metadata:
  name: node-exporter
  namespace: {{ include "monitoring.namespace" . }}
  labels:
    app: node-exporter
spec:
  type: ClusterIP
  clusterIP: None
  selector:
    app: node-exporter
  ports:
    - name: metrics
      protocol: TCP
      port: {{ .Values.nodeExporter.port }}
      targetPort: metrics
{{- end }}
'@

Write-Utf8NoBom (Join-Path $Templates "60-kube-state-metrics-rbac.yaml") @'
{{- if .Values.kubeStateMetrics.enabled }}
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: kube-state-metrics
  labels:
    app: kube-state-metrics
rules:
  - apiGroups:
      - ""
    resources:
      - configmaps
      - secrets
      - nodes
      - pods
      - services
      - serviceaccounts
      - resourcequotas
      - replicationcontrollers
      - limitranges
      - persistentvolumeclaims
      - persistentvolumes
      - namespaces
      - endpoints
    verbs:
      - list
      - watch

  - apiGroups:
      - apps
    resources:
      - statefulsets
      - daemonsets
      - deployments
      - replicasets
    verbs:
      - list
      - watch

  - apiGroups:
      - batch
    resources:
      - cronjobs
      - jobs
    verbs:
      - list
      - watch

  - apiGroups:
      - autoscaling
    resources:
      - horizontalpodautoscalers
    verbs:
      - list
      - watch

  - apiGroups:
      - policy
    resources:
      - poddisruptionbudgets
    verbs:
      - list
      - watch

  - apiGroups:
      - networking.k8s.io
    resources:
      - ingresses
      - networkpolicies
    verbs:
      - list
      - watch

  - apiGroups:
      - storage.k8s.io
    resources:
      - storageclasses
      - volumeattachments
    verbs:
      - list
      - watch

  - apiGroups:
      - certificates.k8s.io
    resources:
      - certificatesigningrequests
    verbs:
      - list
      - watch

  - apiGroups:
      - admissionregistration.k8s.io
    resources:
      - mutatingwebhookconfigurations
      - validatingwebhookconfigurations
    verbs:
      - list
      - watch

  - apiGroups:
      - coordination.k8s.io
    resources:
      - leases
    verbs:
      - list
      - watch

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: kube-state-metrics
  labels:
    app: kube-state-metrics
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: kube-state-metrics
subjects:
  - kind: ServiceAccount
    name: {{ .Values.kubeStateMetrics.serviceAccountName }}
    namespace: {{ include "monitoring.namespace" . }}
{{- end }}
'@

Write-Utf8NoBom (Join-Path $Templates "61-kube-state-metrics-deployment.yaml") @'
{{- if .Values.kubeStateMetrics.enabled }}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kube-state-metrics
  namespace: {{ include "monitoring.namespace" . }}
  labels:
    app: kube-state-metrics
spec:
  replicas: {{ .Values.kubeStateMetrics.replicas }}
  revisionHistoryLimit: {{ .Values.kubeStateMetrics.revisionHistoryLimit }}

  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: {{ .Values.kubeStateMetrics.rollingUpdate.maxSurge }}
      maxUnavailable: {{ .Values.kubeStateMetrics.rollingUpdate.maxUnavailable }}

  selector:
    matchLabels:
      app: kube-state-metrics

  template:
    metadata:
      labels:
        app: kube-state-metrics

    spec:
      serviceAccountName: {{ .Values.kubeStateMetrics.serviceAccountName }}
      automountServiceAccountToken: true
      terminationGracePeriodSeconds: {{ .Values.kubeStateMetrics.terminationGracePeriodSeconds }}

      securityContext:
        {{- toYaml .Values.kubeStateMetrics.securityContext | nindent 8 }}

      nodeSelector:
        {{- toYaml .Values.kubeStateMetrics.nodeSelector | nindent 8 }}

      {{- if .Values.kubeStateMetrics.topologySpread.enabled }}
      topologySpreadConstraints:
        - maxSkew: {{ .Values.kubeStateMetrics.topologySpread.maxSkew }}
          topologyKey: {{ .Values.kubeStateMetrics.topologySpread.topologyKey | quote }}
          whenUnsatisfiable: {{ .Values.kubeStateMetrics.topologySpread.whenUnsatisfiable }}
          labelSelector:
            matchLabels:
              app: kube-state-metrics
      {{- end }}

      containers:
        - name: kube-state-metrics
          image: {{ .Values.kubeStateMetrics.image | quote }}
          imagePullPolicy: {{ .Values.kubeStateMetrics.imagePullPolicy }}

          securityContext:
            {{- toYaml .Values.kubeStateMetrics.containerSecurityContext | nindent 12 }}

          ports:
            - name: http-metrics
              containerPort: {{ .Values.kubeStateMetrics.port }}
              protocol: TCP

            - name: telemetry
              containerPort: {{ .Values.kubeStateMetrics.telemetryPort }}
              protocol: TCP

          startupProbe:
            {{- toYaml .Values.kubeStateMetrics.probes.startup | nindent 12 }}

          readinessProbe:
            {{- toYaml .Values.kubeStateMetrics.probes.readiness | nindent 12 }}

          livenessProbe:
            {{- toYaml .Values.kubeStateMetrics.probes.liveness | nindent 12 }}

          resources:
            {{- toYaml .Values.kubeStateMetrics.resources | nindent 12 }}
{{- end }}
'@

Write-Utf8NoBom (Join-Path $Templates "62-kube-state-metrics-service.yaml") @'
{{- if .Values.kubeStateMetrics.enabled }}
apiVersion: v1
kind: Service
metadata:
  name: kube-state-metrics
  namespace: {{ include "monitoring.namespace" . }}
  labels:
    app: kube-state-metrics
spec:
  type: ClusterIP
  selector:
    app: kube-state-metrics
  ports:
    - name: http-metrics
      protocol: TCP
      port: {{ .Values.kubeStateMetrics.port }}
      targetPort: http-metrics

    - name: telemetry
      protocol: TCP
      port: {{ .Values.kubeStateMetrics.telemetryPort }}
      targetPort: telemetry
{{- end }}
'@

Write-Utf8NoBom (Join-Path $Templates "63-kube-state-metrics-pdb.yaml") @'
{{- if and .Values.kubeStateMetrics.enabled .Values.kubeStateMetrics.pdb.enabled }}
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: kube-state-metrics-pdb
  namespace: {{ include "monitoring.namespace" . }}
  labels:
    app: kube-state-metrics
spec:
  maxUnavailable: {{ .Values.kubeStateMetrics.pdb.maxUnavailable }}
  unhealthyPodEvictionPolicy: {{ .Values.kubeStateMetrics.pdb.unhealthyPodEvictionPolicy }}
  selector:
    matchLabels:
      app: kube-state-metrics
{{- end }}
'@

Write-Host "`nBackup created: $Backup" -ForegroundColor Cyan
Write-Host "`nFinal monitoring templates:" -ForegroundColor Cyan
Get-ChildItem $Templates -File | Sort-Object Name | Select-Object Name, Length

Push-Location $Root
try {
    Write-Host "`nRunning Helm lint..." -ForegroundColor Cyan
    helm lint .\helm\monitoring
    if ($LASTEXITCODE -ne 0) {
        throw "helm lint failed"
    }

    $Rendered = Join-Path $Root "monitoring-rendered-hardening.yaml"

    Write-Host "`nRendering Helm chart..." -ForegroundColor Cyan
    helm template monitoring .\helm\monitoring |
        Set-Content -Encoding utf8 $Rendered
    if ($LASTEXITCODE -ne 0) {
        throw "helm template failed"
    }

    Write-Host "`nRunning Kubernetes server-side dry-run..." -ForegroundColor Cyan
    vagrant ssh kl-cp-1 -c "kubectl apply --dry-run=server -f /vagrant/monitoring-rendered-hardening.yaml"
    if ($LASTEXITCODE -ne 0) {
        throw "kubectl server-side dry-run failed"
    }

    Remove-Item $Rendered -Force

    Write-Host "`nValidation passed. No Git commit was made." -ForegroundColor Green
    Write-Host "`nReview changes with:" -ForegroundColor Yellow
    Write-Host "git status --short"
    Write-Host "git diff -- helm/monitoring"
}
finally {
    Pop-Location
}
