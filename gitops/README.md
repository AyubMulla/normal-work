# GitOps Configuration

## Overview

This directory contains all Kubernetes resources managed by ArgoCD using the **app-of-app pattern**. Every resource is declaratively defined here and reconciled automatically into the cluster.

## Structure

```
gitops/
├── apps/                    # ArgoCD Applications (child apps)
│   ├── app-of-app.yaml     # Root app (platform-root) — entry point
│   ├── lgtm-*.yaml         # Observability stack apps
│   ├── sample-app.yaml     # Sample workload app
│   └── temporal.yaml       # Workflow orchestration app
├── components/             # Kubernetes manifests (no Helm)
│   ├── grafana/            # Grafana ConfigMaps
│   ├── loki-local/         # Loki deployment
│   ├── prometheus/         # Prometheus deployment + recording rules
│   ├── prometheus/         # PrometheusRule (alerts & SLOs)
│   ├── sample-app/         # RBAC, NetworkPolicy, ServiceMonitor
│   └── tempo/              # Tempo deployment
├── lgtm/                   # Helm values overrides for LGTM
│   └── values.yaml         # Resource requests/limits for all services
└── temporal/               # Temporal manifests
    ├── temporal-deployment.yaml
    └── temporal-workflow.yaml
```

## App-of-App Pattern

### Root Application: `app-of-app.yaml`

Entrypoint for ArgoCD reconciliation.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: platform-root       # Visible in ArgoCD UI
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/AyubMulla/normal-work
    targetRevision: HEAD
    path: gitops/apps       # Points to this directory
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd       # Where platform-root lives
  syncPolicy:
    automated:
      prune: true          # Delete resources removed from git
      selfHeal: true       # Re-sync if manual changes detected
    syncOptions:
      - CreateNamespace=true
```

**What it does**:
1. Watches for changes in `gitops/apps/`
2. Auto-discovers child `Application` resources
3. Creates/updates them in argocd namespace
4. Each child app manages its own resources

### Child Applications

Each child app manages a component of the platform:

| App | Purpose | Namespace | Source |
|---|---|---|---|
| `lgtm-grafana` | Visualization | lgtm | Helm: `grafana/grafana` |
| `lgtm-loki` | Log aggregation | lgtm | Helm: `grafana/loki-stack` |
| `lgtm-prometheus` | Metrics storage | lgtm | Helm: `kube-prometheus-stack` |
| `lgtm-promtail` | Log collection | lgtm | Helm: `grafana/promtail` |
| `lgtm-tempo` | Trace storage | lgtm | Helm: `grafana/tempo` + custom values |
| `lgtm-temporal` | Workflow engine | temporal | Kustomize: `temporal/` |
| `sample-app` | Workload | sample-app | Kustomize: `sample-app/k8s/` |

**Sync behavior**:
- Automated sync with prune (removes resources deleted from git)
- Self-heal enabled (reconciles if manual changes detected)
- Respects custom sync strategies per app

## Key Files

### `apps/alerts-prometheusrule.yaml`

Defines SLI/SLO recording rules and alert rules.

**SLI** (Service Level Indicator):
```promql
job:http_error_rate:5m = 
  sum(rate(http_requests_total{job="sample-app",code!~"2.."}[5m])) 
  / 
  sum(rate(http_requests_total{job="sample-app"}[5m]))
```

**SLO** (Service Level Objective): < 5% error rate

**Alert**: Fires if `job:http_error_rate:5m > 0.05` for 2 minutes.

**Applies to**: `prometheus` namespace via PrometheusRule CRD

### `apps/sample-app.yaml`

ArgoCD Application for the sample Flask workload.

**Source**: Local manifests in `sample-app/k8s/`
- `deployment.yaml` (workload + service)
- `rbac.yaml` (ServiceAccount + Role + RoleBinding)
- `networkpolicy.yaml` (network security)
- `service-monitor.yaml` (Prometheus scrape config)

**Sync strategy**: Automated with self-heal

### `components/prometheus/prometheus-deployment.yaml`

Prometheus Deployment + Service + ConfigMap.

**Storage**: Local 15-day retention

**Scrape jobs**:
- `sample-app` (via ServiceMonitor)
- `prometheus` (self)
- `loki` (Loki metrics)
- `tempo` (Tempo metrics)
- `kubernetes-apiservers` (cluster metrics)
- `kubernetes-nodes` (node metrics)

**Recording rules**: Applied from PrometheusRule CRD

### `components/grafana/grafana-configmap.yaml`

Pre-provisioned Grafana datasources (no manual setup).

**Datasources**:
1. Prometheus (`prometheus-local:9090`)
2. Loki (`loki-local:3100`)
3. Tempo (`lgtm-tempo:3200`)

**Admin credentials**: Via K8s Secret (injected at deploy time)

### `components/sample-app/networkpolicy.yaml`

Deny-by-default network policy for sample-app namespace.

**Ingress**:
```yaml
ingress:
  - from:
      - namespaceSelector:
          matchLabels:
            kubernetes.io/metadata.name: lgtm  # Scraper access
    ports:
      - protocol: TCP
        port: 8080                             # HTTP service
```

**Egress**:
```yaml
egress:
  - to:
      - ipBlock:
          cidr: 10.43.0.10/32                  # kube-dns
    ports:
      - protocol: UDP
        port: 53                               # DNS
      - protocol: TCP
        port: 53
  - to:
      - namespaceSelector:
          matchLabels:
            kubernetes.io/metadata.name: lgtm  # Tempo
    ports:
      - protocol: TCP
        port: 4317                             # OTLP gRPC
      - protocol: TCP
        port: 4318                             # OTLP HTTP
```

### `components/sample-app/rbac.yaml`

RBAC for sample-app workload.

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: sample-app-sa
  namespace: sample-app

---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: sample-app-role
  namespace: sample-app
rules:
  - apiGroups: [""]
    resources: ["pods", "pods/log"]
    verbs: ["get", "list", "watch"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: sample-app-rolebinding
  namespace: sample-app
subjects:
  - kind: ServiceAccount
    name: sample-app-sa
roleRef:
  kind: Role
  name: sample-app-role
  apiGroup: rbac.authorization.k8s.io
```

### `lgtm/values.yaml`

Helm values for LGTM stack (Grafana, Loki, Tempo, Prometheus).

**Resource limits** (production-leaning):

```yaml
grafana:
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 1Gi

loki:
  persistence:
    enabled: true
    size: 50Gi
  resources:
    requests:
      cpu: 200m
      memory: 512Mi
    limits:
      cpu: 1
      memory: 2Gi

prometheus:
  prometheusSpec:
    retention: 15d
    resources:
      requests:
        cpu: 200m
        memory: 512Mi
      limits:
        cpu: 1
        memory: 2Gi

tempo:
  persistence:
    enabled: true
    size: 50Gi
```

## Deployment Workflow

### 1. Author manifests locally

```bash
# Edit gitops/components/sample-app/deployment.yaml
vim gitops/components/sample-app/deployment.yaml
```

### 2. Commit to git

```bash
git add gitops/
git commit -m "feat: scale sample-app to 3 replicas"
git push
```

### 3. ArgoCD detects change

ArgoCD polls git every 3 minutes (or via webhook):
- Sees new commit
- Compares desired state (git) vs actual state (cluster)
- Shows diff in ArgoCD UI

### 4. Sync (automatic or manual)

**Automatic** (enabled):
```bash
kubectl patch application -n argocd lgtm-tempo \
  --type merge -p '{"spec":{"syncPolicy":{"automated":{"prune":true}}}}'
```

**Manual**:
```bash
argocd app sync sample-app
# or
kubectl patch application -n argocd sample-app \
  --type json -p='[{"op":"replace","path":"/operation/initiatedBy/username","value":"admin"}]'
```

### 5. Verify deployment

```bash
# Check ArgoCD app status
kubectl get application -n argocd sample-app

# Check pod rollout
kubectl rollout status deploy/sample-app -n sample-app

# Check logs
kubectl logs -n sample-app -l app=sample-app
```

## Best Practices

### Namespacing

Always include namespace in manifests to avoid conflicts:

```yaml
metadata:
  name: my-resource
  namespace: sample-app    # REQUIRED
```

### Resource limits

Every Deployment must define requests/limits:

```yaml
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 512Mi
```

### Health checks

Include readiness/liveness probes:

```yaml
readinessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 10

livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 15
  periodSeconds: 20
```

### RBAC

Every workload gets a ServiceAccount with minimal permissions:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: app-sa
  namespace: sample-app

---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: app-role
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list"]    # Minimal permissions
```

### Network policies

Enforce deny-by-default:

```yaml
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from: [...specific sources...]
  egress:
    - to: [...specific destinations...]
```

### Helm values overrides

For Helm charts, override values in ArgoCD Application:

```yaml
source:
  helm:
    values: |
      replicaCount: 2
      resources:
        requests:
          cpu: 100m
```

## Troubleshooting

### App not syncing

```bash
# Check app status
kubectl get application -n argocd sample-app -o yaml | grep -A 20 status

# Check ArgoCDcontroller logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller | tail -50

# Manually trigger sync
argocd app sync sample-app
```

### Manifest validation error

Common issues:
- Missing `namespace` field
- Invalid YAML syntax
- Kubernetes API version not supported

```bash
# Validate locally before pushing
kubectl apply -f gitops/components/sample-app/deployment.yaml --dry-run=client

# Or check ArgoCD UI for error details
# https://127.0.0.1:8083/applications/argocd/sample-app
```

### Resource already exists error

If manual changes were made to the cluster:

```bash
# Option 1: Let ArgoCD prune (delete the resource)
argocd app sync sample-app --prune

# Option 2: Remove from cluster and re-sync
kubectl delete pod sample-app-xxx -n sample-app
argocd app sync sample-app
```

## Migration to Production-Grade GitOps

### Kustomize + Overlays

Separate dev/stage/prod configurations:

```
gitops/
├── base/
│   ├── sample-app/
│   │   ├── deployment.yaml
│   │   └── kustomization.yaml
├── overlays/
│   ├── dev/
│   │   └── kustomization.yaml
│   ├── stage/
│   └── prod/
```

### Sealed Secrets

Encrypt secrets before committing:

```bash
# Install sealed-secrets controller
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets

# Seal a secret
echo -n 'my-password' | kubectl create secret generic my-secret \
  --dry-run=client --from-file=password=/dev/stdin -o yaml | \
  kubeseal -f - > gitops/components/secrets/my-secret-sealed.yaml
```

### Flux CD

Alternative to ArgoCD (GitOps v2):

```bash
flux bootstrap github \
  --owner=AyubMulla \
  --repo=normal-work \
  --path=gitops/
```

### Policy as Code (OPA/Kyverno)

Enforce company policies before deploying:

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-resource-limits
spec:
  validationFailureAction: audit
  rules:
    - name: check-limits
      match:
        resources:
          kinds:
            - Deployment
      validate:
        message: "Must specify resource limits"
        pattern:
          spec:
            template:
              spec:
                containers:
                  - resources:
                      limits:
                        memory: "?*"
                        cpu: "?*"
```

## References

- [ArgoCD Application CRD](https://argo-cd.readthedocs.io/en/stable/operator-manual/application.yaml/)
- [ArgoCD App-of-Apps Pattern](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/#app-of-apps-pattern)
- [Helm in ArgoCD](https://argo-cd.readthedocs.io/en/stable/user-guide/helm/)
- [Kubernetes networking policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)

