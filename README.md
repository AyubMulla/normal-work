# Staff SRE Assessment Platform (k3s + GitOps + LGTM + Temporal + AI RCA)

Production-leaning local platform implementation using `k3d/k3s` with full GitOps reconciliation through ArgoCD.

## Architecture Overview

- **Cluster**: k3d (k3s) local cluster
- **GitOps**: ArgoCD app-of-app (`platform-root`) reconciles all workloads from this repo
- **Observability (LGTM)**:
  - Grafana (Helm chart)
  - Loki (local manifest component)
  - Tempo (Helm chart)
  - Prometheus (local manifest component)
  - Promtail (Helm chart)
- **Workflow Orchestration**: Temporal server + Temporal UI + Postgres backend
- **Operational Workflow**: Temporal worker + periodic CronJob trigger (`OpsHeartbeatWorkflow`)
- **Sample API**: Flask app exporting logs, metrics, traces
- **AI SRE agent**: Queries Prometheus/Loki and writes structured RCA markdown

## Repo Layout

- `infra/` bootstrap, build, and helper scripts
- `gitops/apps/` ArgoCD `Application` manifests and shared cluster-level manifests
- `gitops/components/` local components (Prometheus, Loki, etc.)
- `gitops/temporal/` Temporal server, DB, UI, and operational workflow resources
- `sample-app/` API source + Kubernetes manifests
- `ai-agent/` failure simulation and RCA agent
- `ai-log/ai_interactions.md` AI interaction history used during development

## Bootstrap From Scratch

### 1) Create cluster (WSL)

```bash
./infra/bootstrap-wsl.sh
export KUBECONFIG=/home/$USER/.kube/config-lab
```

### 2) Build and push sample-app image

```bash
./infra/build-and-push.sh k3d-lab-registry:5000 sample-app latest
```

### 3) Bootstrap ArgoCD and GitOps root app

```bash
export GRAFANA_ADMIN_PASSWORD='replace-with-strong-password'
export TEMPORAL_DB_PASSWORD='replace-with-strong-password'
./infra/bootstrap-argocd.sh -r 'https://github.com/AyubMulla/normal-work'
```

If those environment variables are omitted, the script generates strong random values for the run.

### 4) Verify reconciliation

```bash
kubectl -n argocd get app -o wide
```

Expected final app set:
- `platform-root`
- `lgtm-grafana`
- `lgtm-loki`
- `lgtm-prometheus`
- `lgtm-promtail`
- `lgtm-tempo`
- `lgtm-temporal`
- `sample-app`

All should converge to `Synced` + `Healthy`.

## Access

Use port-forwards as needed:

```bash
kubectl -n lgtm port-forward svc/lgtm-grafana 3000:80
kubectl -n argocd port-forward svc/argocd-server 8083:443
kubectl -n temporal port-forward svc/temporal-web 8090:8088
kubectl -n sample-app port-forward svc/sample-app 8084:80
kubectl -n lgtm port-forward svc/prometheus-local 9091:9090
kubectl -n lgtm port-forward svc/loki-local 3101:3100
kubectl -n lgtm port-forward svc/lgtm-tempo 3201:3200
```

## What Is Production-Oriented Here

- Namespace isolation for major domains
- GitOps-only reconciliation after bootstrap
- Resource requests/limits on core workloads
- Liveness/readiness probes for app and platform components
- NetworkPolicy for sample app namespace
- Dedicated ServiceAccount + RBAC manifest for sample app
- SLI/SLO recording + alert rule (`PrometheusRule` manifests)
- Temporal operational workflow running on schedule

## Temporal Operational Workflow

Resources are in `gitops/temporal/temporal-workflow.yaml`:
- `temporal-ops-worker` Deployment
- `temporal-ops-heartbeat-trigger` CronJob
- `OpsHeartbeatWorkflow` workflow definition

Quick verification:

```bash
kubectl -n temporal get deploy temporal-ops-worker
kubectl -n temporal get cronjob temporal-ops-heartbeat-trigger
kubectl -n temporal get jobs --sort-by=.metadata.creationTimestamp | tail
```

## SLI/SLO + Alerting

Primary alert rule:
- `gitops/apps/alerts-prometheusrule.yaml`

Prometheus scrape:
- `gitops/components/prometheus/prometheus-deployment.yaml`

Sample metric query:

```promql
http_requests_total{job="sample-app"}
```

Error-rate SLI:

```promql
sum(rate(http_requests_total{job="sample-app",code!~"2.."}[5m]))
/
sum(rate(http_requests_total{job="sample-app"}[5m]))
```

## AI SRE Agent + Failure Simulation

Simulate failure and produce RCA:

```bash
cd ai-agent
./simulate_failure.sh sample-app
python3 agent.py
cat rca_report.md
```

Agent code:
- `ai-agent/agent.py`

## Security Notes

- Grafana and Temporal DB credentials are referenced by workloads but provisioned at bootstrap time, not stored as plaintext in Git.
- `infra/bootstrap-argocd.sh` creates required Kubernetes secrets from environment variables (or generated random values).
- For cloud production, replace bootstrap-created secrets with SealedSecrets/ExternalSecrets + KMS/Vault-backed rotation.

## Design Decisions and Trade-offs

- **k3d/k3s** chosen for fast local iteration while keeping Kubernetes behavior realistic.
- **GitOps app-of-app** used to model production reconciliation patterns.
- **Mixed local manifests + Helm apps** used for speed and deterministic control where needed.
- **Temporal worker container installs Python deps at runtime** to reduce image build complexity locally; production should use a prebuilt immutable worker image.

## Roadmap (Next Improvements)

1. Replace in-repo secrets with SealedSecrets or External Secrets Operator.
2. Add CI pipeline for image build/push + policy checks (`kubeconform`, `conftest`).
3. Add prebuilt Temporal worker image and workflow integration tests.
4. Add Mimir long-term metrics storage and dashboard-as-code provisioning.
5. Add runbook links and alert routing to PagerDuty/Slack.
