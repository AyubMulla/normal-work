# Staff SRE Assessment Platform (k3s + GitOps + LGTM + Temporal + AI RCA)

Production-leaning local platform implementation using k3d/k3s with full GitOps reconciliation through ArgoCD.

## Objective Alignment (Assessment Checklist)

This repository is structured to map directly to the assessment requirements.

| Requirement | Status | Evidence |
|---|---|---|
| k3s cluster | ✅ | `infra/bootstrap-wsl.sh`, `infra/bootstrap-k3s.sh`, `infra/bootstrap-k3d.ps1` |
| ArgoCD manages workloads from GitOps repo | ✅ | `gitops/apps/app-of-app.yaml` (`platform-root`) + all app manifests under `gitops/apps/` |
| LGTM stack (Grafana, Loki, Tempo, Prometheus) | ✅ | `gitops/apps/lgtm-*.yaml`, components under `gitops/components/` |
| SLI/SLO + real alert rule | ✅ | `gitops/components/prometheus/prometheus-deployment.yaml` (`job:http_error_rate:5m`, `SampleAppHighErrorRate`) |
| Temporal with operational workflow | ✅ | `gitops/temporal/temporal-workflow.yaml` (`temporal-ops-worker`, cron trigger, `OpsHeartbeatWorkflow`) |
| Sample API emits metrics/logs/traces | ✅ | `sample-app/` manifests + OTLP/log/metrics wiring |
| AI SRE agent performs RCA from observability data | ✅ | `ai-agent/agent.py`, `ai-agent/simulate_failure.sh`, `ai-agent/rca_report.md` |
| Complete AI interaction log | ✅ | `ai-log/ai_interactions.md` |
| Clear README, design decisions, roadmap | ✅ | This document |
| Meaningful git history | ✅ | multiple incremental commits on `staff-sre/initial-bootstraps` |

---

## Architecture Overview

- Cluster: k3d (k3s)
- GitOps: ArgoCD app-of-app pattern (`platform-root`)
- Observability:
  - Grafana
  - Loki
  - Tempo
  - Prometheus
  - Promtail
- Workflow Orchestration: Temporal server + Temporal UI + Postgres
- Operational Workflow: `OpsHeartbeatWorkflow` running on cron
- Sample Application: Flask API exporting logs, metrics, traces
- AI Day-2 Operations: AI agent that queries Prometheus/Loki and writes structured RCA

---

## Repository Layout

- `infra/` cluster/bootstrap/build helper scripts
- `gitops/apps/` ArgoCD Applications (app-of-app children)
- `gitops/components/` local components (Prometheus, Loki, sample app RBAC/policies)
- `gitops/temporal/` Temporal server/DB/UI/workflow resources
- `sample-app/` API code and Kubernetes resources
- `ai-agent/` failure simulation + RCA agent
- `ai-log/ai_interactions.md` full AI collaboration log

---

## Bootstrap From Scratch

### 1) Create local cluster (WSL)

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

If env vars are omitted, bootstrap generates strong random values for that run.

### 4) Verify ArgoCD convergence

```bash
kubectl -n argocd get app -o wide
```

Expected apps:
- `platform-root`
- `lgtm-grafana`
- `lgtm-loki`
- `lgtm-prometheus`
- `lgtm-promtail`
- `lgtm-tempo`
- `lgtm-temporal`
- `sample-app`

All should be `Synced` + `Healthy`.

---

## Service Port Reference

| Service | Local URL | Port mapping | Namespace | Service |
|---|---|---|---|---|
| Grafana | http://127.0.0.1:3000 | 3000 -> 80 | `lgtm` | `lgtm-grafana` |
| ArgoCD | https://127.0.0.1:8083 | 8083 -> 443 | `argocd` | `argocd-server` |
| Temporal UI | http://127.0.0.1:8090 | 8090 -> 8088 | `temporal` | `temporal-web` |
| Sample app | http://127.0.0.1:8084 | 8084 -> 80 | `sample-app` | `sample-app` |
| Prometheus | http://127.0.0.1:9091 | 9091 -> 9090 | `lgtm` | `prometheus-local` |
| Loki | http://127.0.0.1:3101 | 3101 -> 3100 | `lgtm` | `loki-local` |
| Tempo | http://127.0.0.1:3201 | 3201 -> 3200 | `lgtm` | `lgtm-tempo` |

---

## Start/Stop All Port-Forwards

Use the helper script:

```bash
export KUBECONFIG=/home/$USER/.kube/config-lab
chmod +x infra/port-forward.sh

./infra/port-forward.sh          # start all
./infra/port-forward.sh status   # check status
./infra/port-forward.sh stop     # stop all managed PF processes
```

PowerShell quick check:

```powershell
3000,8083,8090,8084,9091,3101,3201 | ForEach-Object {
  $ok = (Test-NetConnection 127.0.0.1 -Port $_ -WarningAction SilentlyContinue).TcpTestSucceeded
  "$_`: $ok"
}
```

---

## Temporal Operational Workflow

Source: `gitops/temporal/temporal-workflow.yaml`

Workflow: `OpsHeartbeatWorkflow`

Execution flow:
1. CronJob `temporal-ops-heartbeat-trigger` fires every 10 min.
2. `starter.py` connects to Temporal (`temporal:7233`, namespace `default`) and starts workflow ID `ops-heartbeat-<uuid>`.
3. Worker deployment `temporal-ops-worker` polls `ops-task-queue`.
4. Workflow sleeps 2 seconds, returns:

```json
{ "workflow": "OpsHeartbeatWorkflow", "source": "cron", "status": "ok" }
```

Because execution is short, it appears in Temporal UI under `Closed`.

### CLI verification

```bash
kubectl -n temporal get deploy temporal-ops-worker
kubectl -n temporal get cronjob temporal-ops-heartbeat-trigger
kubectl -n temporal exec deploy/temporal -- env TEMPORAL_CLI_ADDRESS=temporal:7233 tctl --ns default workflow listall
```

### UI verification

1. Open `http://127.0.0.1:8090`
2. Namespace = `default`
3. Use `Closed` filter to view `OpsHeartbeatWorkflow` runs
4. Open a run -> inspect Summary / Input & Results / Event History

---

## SLI/SLO + Alerting

Primary recording + alert rules are loaded in Prometheus runtime config:
- `job:http_error_rate:5m` (recording rule)
- `SampleAppHighErrorRate` (alert if > 5% error rate for 2 minutes)

Rule definitions:
- `gitops/components/prometheus/prometheus-deployment.yaml`
- `gitops/apps/alerts-prometheusrule.yaml` (manifest-level representation)

### PromQL (error-rate SLI)

```promql
sum(rate(http_requests_total{job="sample-app",code!~"2.."}[5m]))
/
sum(rate(http_requests_total{job="sample-app"}[5m]))
```

### Verify via Prometheus API

```bash
curl -s http://127.0.0.1:9091/api/v1/rules
curl -s http://127.0.0.1:9091/api/v1/status/config
```

---

## Sample App + LGTM Verification

### Sample app

```bash
curl http://127.0.0.1:8084/health
curl http://127.0.0.1:8084/metrics
```

Generate traffic:

```bash
for i in $(seq 1 50); do curl -s http://127.0.0.1:8084/ > /dev/null; done
for i in $(seq 1 10); do curl -s http://127.0.0.1:8084/error > /dev/null; done
```

### Grafana (UI)

- Open `http://127.0.0.1:3000`
- Data sources: Prometheus, Loki, Tempo should pass health checks
- Explore queries:
  - Prometheus: `rate(http_requests_total{job="sample-app"}[5m])`
  - Loki: `{namespace="sample-app"}`
  - Tempo TraceQL: `{.service.name = "sample-app"}`

### Prometheus (UI)

- Open `http://127.0.0.1:9091`
- Alerts tab should list `SampleAppHighErrorRate`
- Graph query `job:http_error_rate:5m`

---

## AI SRE Agent + Simulated Failure

Simulate failure and run RCA:

```bash
cd ai-agent
./simulate_failure.sh sample-app
python3 agent.py
cat rca_report.md
```

Agent behavior:
- Queries Prometheus for error rate / restarts / CPU
- Queries Loki for error logs
- Writes structured RCA markdown with findings and next actions

Files:
- `ai-agent/agent.py`
- `ai-agent/simulate_failure.sh`
- `ai-agent/rca_report.md`

---

## Production-Grade Controls Present

- Namespace isolation: `argocd`, `lgtm`, `temporal`, `sample-app`
- GitOps-only reconciliation after bootstrap
- RBAC + dedicated ServiceAccount for sample app
- Resource requests/limits for core workloads
- Liveness/readiness probes for platform and app components
- NetworkPolicy for sample-app and additional namespace policy
- Secret references via `secretKeyRef`; no plaintext creds committed in runtime manifests

---

## AI Usage Log (Required Deliverable)

Complete AI interaction history is included in:
- `ai-log/ai_interactions.md`

This log captures prompts, AI actions, validations, outcomes, and commit traceability.

---

## Design Decisions and Trade-offs

- k3d/k3s for rapid local iteration with realistic Kubernetes behavior
- Argo app-of-app for production-like reconciliation model
- Mixed manifests + Helm charts for speed and deterministic control
- Temporal worker currently installs dependencies at runtime (acceptable for local proving; immutable image planned)
- Prometheus native `rule_files` used so SLO rules load at runtime without requiring Prometheus Operator

---

## EKS Migration Roadmap (Next Phase)

When moving from local k3s to AWS EKS, implement in this order:

1. Foundation and identity
   - Provision EKS with Terraform (multi-AZ managed node groups)
   - Enable IAM Roles for Service Accounts (IRSA)
   - Move cluster auth and bootstrap to GitHub OIDC + short-lived credentials

2. Networking and ingress
   - Replace local networking with VPC CNI best practices
   - Add AWS Load Balancer Controller + external DNS
   - Use private subnets for worker nodes and restrict public exposure

3. Secrets and encryption
   - Replace bootstrap secrets with External Secrets Operator + AWS Secrets Manager
   - Enable envelope encryption for Kubernetes secrets using KMS
   - Introduce rotation policy for Grafana/DB credentials

4. Persistence and data backends
   - Move Temporal/Postgres to managed RDS (Multi-AZ)
   - Move Loki/Tempo object storage to S3 with lifecycle policies
   - Add Mimir for long-term metrics retention at scale

5. Observability hardening
   - Introduce remote_write / long-term retention strategy
   - Add SLO dashboards-as-code and service-level alert routing
   - Integrate Alertmanager routing with PagerDuty/Slack

6. Security and policy enforcement
   - Enforce Pod Security Standards
   - Add policy-as-code (Kyverno or OPA Gatekeeper)
   - Add image scanning + signed image verification (Cosign)

7. Delivery pipeline and quality gates
   - CI pipeline: build/test/scan/sign/publish
   - Pre-merge checks: kubeconform, conftest, lint, unit tests
   - Progressive delivery (Argo Rollouts / canary) for app changes

8. Reliability and DR
   - Backup/restore for ArgoCD, Temporal metadata, and observability data
   - Multi-environment promotion (dev -> stage -> prod) with separate overlays
   - Run regular game days (pod kills, latency injection, dependency outage drills)

---

## Submission Notes

- Branch used: `staff-sre/initial-bootstraps`
- Commit history is incremental and meaningful
- Repository is intended to be cloned and bootstrapped from scratch using this README
