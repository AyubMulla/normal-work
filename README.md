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

### What `OpsHeartbeatWorkflow` Does

`OpsHeartbeatWorkflow` is a lightweight platform health-check workflow defined in `gitops/temporal/temporal-workflow.yaml`.

**Execution flow:**
1. A CronJob (`temporal-ops-heartbeat-trigger`) fires every **10 minutes** and runs `starter.py`
2. `starter.py` connects to Temporal (`temporal:7233`, namespace `default`) and starts a new workflow execution with a unique ID (`ops-heartbeat-<uuid>`)
3. The workflow worker (`temporal-ops-worker` Deployment) picks up the task from `ops-task-queue`, sleeps **2 seconds** (simulating an async ops check), then returns:
   ```json
   { "workflow": "OpsHeartbeatWorkflow", "source": "cron", "status": "ok" }
   ```
4. The execution closes with status **Completed** and appears in the Temporal UI under **Closed** workflows

The 2-second runtime means it is always in the **Closed** state by the time you open the UI. See below for how to verify it and how to trigger a new one manually.

---

### Verify via CLI

```bash
export KUBECONFIG=/home/$USER/.kube/config-lab

# Check worker and cronjob are healthy
kubectl -n temporal get deploy temporal-ops-worker
kubectl -n temporal get cronjob temporal-ops-heartbeat-trigger

# Trigger a manual job immediately (does not wait for cron schedule)
kubectl -n temporal delete job manual-heartbeat-test --ignore-not-found=true
kubectl -n temporal create job --from=cronjob/temporal-ops-heartbeat-trigger manual-heartbeat-test
kubectl -n temporal wait --for=condition=complete job/manual-heartbeat-test --timeout=60s
kubectl -n temporal logs job/manual-heartbeat-test

# List all completed executions
kubectl -n temporal exec deploy/temporal -- \
  env TEMPORAL_CLI_ADDRESS=temporal:7233 tctl --ns default workflow listall
```

Expected log output:
```
Started workflow: ops-heartbeat-<uuid>
```

Expected `tctl listall` row:
```
OpsHeartbeatWorkflow | ops-heartbeat-<uuid> | <run-id> | ops-task-queue | <start> | <end>
```

---

### Trigger a New Workflow from the Temporal UI

> **Prerequisite**: port-forward must be running — `kubectl -n temporal port-forward svc/temporal-web 8090:8088`

1. Open **http://127.0.0.1:8090** in your browser
2. Confirm the namespace selector at the top shows **`default`** (not `temporal-system`)
3. Click **"Start Workflow"** (button in the top-right)
4. Fill in the form:

   | Field | Value |
   |---|---|
   | **Workflow ID** | `manual-ui-test-001` (any unique string) |
   | **Workflow Type** | `OpsHeartbeatWorkflow` |
   | **Task Queue** | `ops-task-queue` |
   | **Input** (JSON) | `"ui"` |

5. Click **Start** — the workflow executes in ~2 seconds
6. To see the result: click the **"Closed"** filter button (top of workflow list) and find `manual-ui-test-001`
7. Click the row → **"Input & Results"** tab shows the return value `{ "workflow": "OpsHeartbeatWorkflow", "source": "ui", "status": "ok" }`

> **Tip**: if you want the workflow to be visible in the **Open** state for a few seconds, change the Input JSON to any value — the 2-second sleep is the only pause before completion.

---

## Platform Verification Guide

### Port-Forward Checklist

Start all port-forwards before testing (each in its own terminal or as background jobs):

```bash
export KUBECONFIG=/home/$USER/.kube/config-lab

kubectl -n lgtm     port-forward svc/lgtm-grafana    3000:80   &
kubectl -n argocd   port-forward svc/argocd-server   8083:443  &
kubectl -n temporal port-forward svc/temporal-web    8090:8088 &
kubectl -n sample-app port-forward svc/sample-app   8084:80   &
kubectl -n lgtm     port-forward svc/prometheus-local 9091:9090 &
kubectl -n lgtm     port-forward svc/loki-local      3101:3100 &
kubectl -n lgtm     port-forward svc/lgtm-tempo      3201:3200 &
```

Quick connectivity check (PowerShell on Windows):
```powershell
3000,8083,8090,8084,9091,3101,3201 | ForEach-Object {
    $ok = (Test-NetConnection 127.0.0.1 -Port $_ -WarningAction SilentlyContinue).TcpTestSucceeded
    "$_`: $ok"
}
```

---

### Grafana — UI Walkthrough

**URL**: http://127.0.0.1:3000  
**Credentials**: `admin` / *(password set at bootstrap or in the `grafana-admin-credentials` secret)*

Retrieve password:
```bash
kubectl -n lgtm get secret grafana-admin-credentials \
  -o jsonpath='{.data.admin-password}' | base64 -d; echo
```

#### Test Prometheus Data Source

1. Left sidebar → **Connections → Data sources** → click **Prometheus**
2. Scroll down → click **"Save & test"** → expect `"Data source is working"`
3. Left sidebar → **Explore** (compass icon)
4. Data source dropdown → select **Prometheus**
5. Switch to **Code** mode and run these queries:

   | Purpose | PromQL |
   |---|---|
   | Request rate | `rate(http_requests_total{job="sample-app"}[5m])` |
   | Error rate SLI | `sum(rate(http_requests_total{job="sample-app",code!~"2.."}[5m])) / sum(rate(http_requests_total{job="sample-app"}[5m]))` |
   | Latency p99 | `histogram_quantile(0.99, rate(http_request_duration_seconds_bucket{job="sample-app"}[5m]))` |

6. Click **Run query** — you should see time-series data. If no data yet, generate traffic first:
   ```bash
   # Generate sample traffic (from WSL)
   for i in $(seq 1 50); do curl -s http://127.0.0.1:8084/ > /dev/null; done
   for i in $(seq 1 10); do curl -s http://127.0.0.1:8084/error > /dev/null; done
   ```

#### Test Loki Data Source (Logs)

1. Left sidebar → **Explore**
2. Data source dropdown → select **Loki**
3. Switch to **Code** mode and run:

   | Purpose | LogQL |
   |---|---|
   | All sample-app logs | `{namespace="sample-app"}` |
   | Error logs only | `{namespace="sample-app"} \|= "ERROR"` |
   | Temporal worker logs | `{namespace="temporal"}` |
   | Log rate graph | `sum(rate({namespace="sample-app"}[1m]))` |

4. Click **Run query** → log lines should appear in the panel  
5. Expand any line to see structured fields (level, trace_id, etc.)

> **Tip**: Generate errors with `curl http://127.0.0.1:8084/error` to see error-level log entries appear live.

#### Test Tempo Data Source (Traces)

1. Left sidebar → **Explore**
2. Data source dropdown → select **Tempo**
3. Query type: **Search** tab
4. Set **Service Name** = `sample-app` and click **Run query**
5. Traces from recent requests should appear with their duration and span count
6. Click any trace row → waterfall view shows individual spans

   Alternatively, use **TraceQL** mode:
   ```
   {.service.name = "sample-app"}
   ```

> **Tip**: Generate traces first — `curl http://127.0.0.1:8084/` sends a request that propagates a trace through the Flask app to Tempo via OTLP.

#### Correlate Logs → Traces (Derived Fields)

If Loki is configured with a `traceID` derived field pointing to Tempo:
1. In the Loki Explore view, expand any log line that contains `trace_id=...`
2. A **"Tempo"** link button appears next to the trace ID field
3. Click it to jump directly to the correlated trace in Tempo

---

### Prometheus — Direct UI

**URL**: http://127.0.0.1:9091

#### Check Alert Rules Are Loaded

1. Top nav → **Alerts**
2. Confirm `SampleAppHighErrorRate` is listed (state: `inactive` when error rate is normal)
3. To trigger a **FIRING** state:
   ```bash
   # Send 100% errors for >2 minutes to breach the 5% SLO threshold
   for i in $(seq 1 200); do curl -s http://127.0.0.1:8084/error > /dev/null; sleep 0.5; done
   ```
4. Refresh the Alerts page after ~2 minutes — `SampleAppHighErrorRate` should show **FIRING**

#### Verify Recording Rule

1. Top nav → **Graph**
2. Query: `job:http_error_rate:5m`
3. Click **Execute** → confirms the recording rule is computing and storing the pre-aggregated error rate

#### Verify Config

Top nav → **Status → Configuration** — confirm `rule_files` section lists `/etc/prometheus/sample-app-rules.yml`.

---

### Temporal UI — Full Walkthrough

**URL**: http://127.0.0.1:8090

1. **Namespace**: confirm the dropdown shows **`default`**
2. **View past executions**: click the **Closed** filter → all completed `OpsHeartbeatWorkflow` executions appear
3. **Inspect an execution**:
   - Click any row → **Summary** tab shows workflow ID, run ID, task queue, timing
   - **Input & Results** tab shows `{ "workflow": "OpsHeartbeatWorkflow", "source": "cron", "status": "ok" }`
   - **Event History** tab shows the full event log: `WorkflowExecutionStarted → TimerStarted → TimerFired → WorkflowExecutionCompleted`
4. **Start a new workflow from UI**: see [Trigger a New Workflow from the Temporal UI](#trigger-a-new-workflow-from-the-temporal-ui) above

---

### ArgoCD — GitOps Health Check

**URL**: https://127.0.0.1:8083 (accept self-signed cert)  
**Credentials**: `admin` / retrieve with:
```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

All 8 apps should show **Synced** + **Healthy** at the latest commit. Any **OutOfSync** app can be force-refreshed:
```bash
kubectl -n argocd annotate app <app-name> argocd.argoproj.io/refresh=hard --overwrite
```

---

## SLI/SLO + Alerting

Primary alert rule: `gitops/apps/alerts-prometheusrule.yaml`  
Prometheus config: `gitops/components/prometheus/prometheus-deployment.yaml`

**Error-rate SLI** (5-minute window):
```promql
sum(rate(http_requests_total{job="sample-app",code!~"2.."}[5m]))
/
sum(rate(http_requests_total{job="sample-app"}[5m]))
```

**Pre-aggregated recording rule** (fast dashboard queries):
```promql
job:http_error_rate:5m
```

**Alert threshold**: fires when error rate > 5% sustained for 2 minutes (`SampleAppHighErrorRate`).

---

## AI SRE Agent + Failure Simulation

Simulate failure and produce RCA:

```bash
cd ai-agent
./simulate_failure.sh sample-app
python3 agent.py
cat rca_report.md
```

Agent code: `ai-agent/agent.py`

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
