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


---

## Service Port Reference

| Service | Local URL | Port mapping | Namespace | k8s Service |
|---|---|---|---|---|
| **Grafana** | http://127.0.0.1:3000 | 3000 → 80 | `lgtm` | `lgtm-grafana` |
| **ArgoCD** | https://127.0.0.1:8083 | 8083 → 443 | `argocd` | `argocd-server` |
| **Temporal UI** | http://127.0.0.1:8090 | 8090 → 8088 | `temporal` | `temporal-web` |
| **Sample App** | http://127.0.0.1:8084 | 8084 → 80 | `sample-app` | `sample-app` |
| **Prometheus** | http://127.0.0.1:9091 | 9091 → 9090 | `lgtm` | `prometheus-local` |
| **Loki** | http://127.0.0.1:3101 | 3101 → 3100 | `lgtm` | `loki-local` |
| **Tempo** | http://127.0.0.1:3201 | 3201 → 3200 | `lgtm` | `lgtm-tempo` |

---

## Start All Port-Forwards

### Option A — One-command script (recommended)

```bash
export KUBECONFIG=/home/$USER/.kube/config-lab
chmod +x infra/port-forward.sh

./infra/port-forward.sh          # start all services in background
./infra/port-forward.sh status   # check which ports are live
./infra/port-forward.sh stop     # tear everything down
```

The script starts all seven port-forwards in the background, waits for each port to respond, prints a live/dead status table, and stores PIDs in `/tmp/.lab-port-forwards.pids`.

### Option B — All background from one shell

```bash
export KUBECONFIG=/home/$USER/.kube/config-lab
kubectl -n lgtm      port-forward svc/lgtm-grafana     3000:80   &
kubectl -n argocd    port-forward svc/argocd-server    8083:443  &
kubectl -n temporal  port-forward svc/temporal-web     8090:8088 &
kubectl -n sample-app port-forward svc/sample-app      8084:80   &
kubectl -n lgtm      port-forward svc/prometheus-local 9091:9090 &
kubectl -n lgtm      port-forward svc/loki-local       3101:3100 &
kubectl -n lgtm      port-forward svc/lgtm-tempo       3201:3200 &
```

### Option C — One terminal per service

```bash
# Run each in its own terminal tab
kubectl -n lgtm      port-forward svc/lgtm-grafana     3000:80
kubectl -n argocd    port-forward svc/argocd-server    8083:443
kubectl -n temporal  port-forward svc/temporal-web     8090:8088
kubectl -n sample-app port-forward svc/sample-app      8084:80
kubectl -n lgtm      port-forward svc/prometheus-local 9091:9090
kubectl -n lgtm      port-forward svc/loki-local       3101:3100
kubectl -n lgtm      port-forward svc/lgtm-tempo       3201:3200
```

### Verify all ports are up

**From WSL / bash:**
```bash
for p in 3000 8083 8090 8084 9091 3101 3201; do
  nc -z 127.0.0.1 $p && echo "$p: UP" || echo "$p: DOWN"
done
```

**From PowerShell (Windows):**
```powershell
3000,8083,8090,8084,9091,3101,3201 | ForEach-Object {
    $ok = (Test-NetConnection 127.0.0.1 -Port $_ -WarningAction SilentlyContinue).TcpTestSucceeded
    "$_`: $ok"
}
```

---

## Service Testing Guide

### 1 — Sample App

**URL**: http://127.0.0.1:8084

#### CLI

```bash
# Health check
curl http://127.0.0.1:8084/health
# → {"status":"ok"}

# Generate normal traffic (produces metrics, logs, traces)
for i in $(seq 1 50); do curl -s http://127.0.0.1:8084/ > /dev/null; done

# Generate error traffic (to test SLO alerting)
for i in $(seq 1 20); do curl -s http://127.0.0.1:8084/error > /dev/null; done

# View raw Prometheus metrics exposed by the app
curl http://127.0.0.1:8084/metrics | grep http_requests
```

#### UI

Open http://127.0.0.1:8084 — returns a JSON response.
Check http://127.0.0.1:8084/health for `{"status":"ok"}`.

---

### 2 — ArgoCD

**URL**: https://127.0.0.1:8083 *(accept the self-signed cert warning)*

**Get admin password:**
```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

#### CLI

```bash
export KUBECONFIG=/home/$USER/.kube/config-lab

# All apps with sync/health status
kubectl -n argocd get app -o wide

# Force hard-refresh a specific app (pull latest from Git immediately)
kubectl -n argocd annotate app lgtm-temporal argocd.argoproj.io/refresh=hard --overwrite

# Force sync
kubectl -n argocd app sync lgtm-prometheus

# Watch all apps converge
watch kubectl -n argocd get app -o wide
```

#### UI

1. Open https://127.0.0.1:8083 → login as `admin`
2. All 8 app tiles should be green (**Synced + Healthy**)
3. Click any app → **App Details**: commit SHA, sync status, resource tree
4. Click any pod resource → inline logs and events
5. Click **Sync** on any app to trigger an immediate reconcile from Git

---

### 3 — Prometheus

**URL**: http://127.0.0.1:9091

#### CLI

```bash
# Health check
curl http://127.0.0.1:9091/-/healthy
# → Prometheus Server is Healthy.

# List all loaded alert rule names
curl -s http://127.0.0.1:9091/api/v1/rules | jq '.data.groups[].rules[].name'

# Query error-rate SLI (recording rule output)
curl -s 'http://127.0.0.1:9091/api/v1/query?query=job:http_error_rate:5m' | jq '.data.result'

# Query raw request rate
curl -s 'http://127.0.0.1:9091/api/v1/query?query=rate(http_requests_total{job="sample-app"}[5m])' | jq .

# Confirm rule_files is wired in config
curl -s http://127.0.0.1:9091/api/v1/status/config | grep rule_files

# Check scrape targets
curl -s http://127.0.0.1:9091/api/v1/targets \
  | jq '.data.activeTargets[] | {job:.labels.job, health:.health}'
```

#### UI

1. Open http://127.0.0.1:9091

**Check alert rules are loaded:**
- Top nav → **Alerts** → confirm `SampleAppHighErrorRate` listed (`inactive` under normal load)

**Verify recording rule:**
- Top nav → **Graph** → query `job:http_error_rate:5m` → **Execute** → graph appears

**Verify config:**
- Top nav → **Status → Configuration** → search for `rule_files` → shows `/etc/prometheus/sample-app-rules.yml`

**Verify scrape targets:**
- Top nav → **Status → Targets** → confirm `sample-app` is **UP**

**Trigger the alert (FIRING state):**
```bash
# Sustain >5% errors for 2+ minutes to breach SLO threshold
for i in $(seq 1 300); do curl -s http://127.0.0.1:8084/error > /dev/null; sleep 0.4; done
```
Refresh the Alerts page after ~2 minutes — `SampleAppHighErrorRate` changes to **FIRING**.

---

### 4 — Grafana

**URL**: http://127.0.0.1:3000 | Login: `admin`

**Get admin password:**
```bash
kubectl -n lgtm get secret grafana-admin-credentials \
  -o jsonpath='{.data.admin-password}' | base64 -d; echo
```

#### CLI (datasource health via API)

```bash
GRAFANA_PASSWORD=$(kubectl -n lgtm get secret grafana-admin-credentials \
  -o jsonpath='{.data.admin-password}' | base64 -d)

# List configured datasources
curl -s -u "admin:${GRAFANA_PASSWORD}" \
  http://127.0.0.1:3000/api/datasources | jq '.[].name'

# Check datasource health
curl -s -u "admin:${GRAFANA_PASSWORD}" \
  http://127.0.0.1:3000/api/datasources/uid/prometheus/health | jq .
```

#### UI — Test Prometheus Datasource

1. Left sidebar → **Connections → Data sources** → click **Prometheus**
2. Scroll to bottom → **Save & test** → expect green `"Data source is working"`
3. Left sidebar → **Explore** → datasource = **Prometheus** → **Code** mode
4. Run these PromQL queries:

   | Purpose | Query |
   |---|---|
   | Request rate | `rate(http_requests_total{job="sample-app"}[5m])` |
   | Error rate SLI | `sum(rate(http_requests_total{job="sample-app",code!~"2.."}[5m])) / sum(rate(http_requests_total{job="sample-app"}[5m]))` |
   | p99 latency | `histogram_quantile(0.99, rate(http_request_duration_seconds_bucket{job="sample-app"}[5m]))` |
   | Recording rule | `job:http_error_rate:5m` |

5. Click **Run query** → time-series graph appears

Generate traffic if no data yet:
```bash
for i in $(seq 1 50); do curl -s http://127.0.0.1:8084/ > /dev/null; done
```

#### UI — Test Loki Datasource (Logs)

1. Left sidebar → **Explore** → datasource = **Loki** → **Code** mode
2. Run these LogQL queries:

   | Purpose | Query |
   |---|---|
   | All sample-app logs | `{namespace="sample-app"}` |
   | Error lines only | `{namespace="sample-app"} \|= "ERROR"` |
   | Temporal worker logs | `{namespace="temporal"}` |
   | Log volume rate | `sum(rate({namespace="sample-app"}[1m]))` |

3. Log lines stream into the panel — expand any entry to see JSON fields (level, trace_id, etc.)
4. Generate live error logs: `curl http://127.0.0.1:8084/error` — appears in Loki within seconds

#### UI — Test Tempo Datasource (Traces)

1. Left sidebar → **Explore** → datasource = **Tempo**
2. **Search** tab → set **Service Name** = `sample-app` → **Run query**
3. Trace list appears — click any row → span waterfall view
4. **TraceQL** tab: `{.service.name = "sample-app"}` for all recent traces

Generate a trace first:
```bash
curl http://127.0.0.1:8084/
```

#### UI — Log → Trace Correlation

1. In Loki Explore, expand a log line containing `trace_id=...`
2. A **Tempo** jump button appears beside the trace ID field
3. Click it → opens the correlated trace waterfall directly

---

### 5 — Loki

**URL**: http://127.0.0.1:3101 *(API only — use Grafana Explore for UI)*

#### CLI

```bash
# Readiness check
curl http://127.0.0.1:3101/ready
# → ready

# List available log labels
curl -s http://127.0.0.1:3101/loki/api/v1/labels | jq .

# Query last 10 log lines from sample-app (last 1 hour)
curl -s -G http://127.0.0.1:3101/loki/api/v1/query_range \
  --data-urlencode 'query={namespace="sample-app"}' \
  --data-urlencode 'limit=10' \
  --data-urlencode "start=$(date -d '1 hour ago' +%s)000000000" \
  --data-urlencode "end=$(date +%s)000000000" \
  | jq '.data.result[].values[][1]'

# Query error lines only
curl -s -G http://127.0.0.1:3101/loki/api/v1/query_range \
  --data-urlencode 'query={namespace="sample-app"} |= "ERROR"' \
  --data-urlencode 'limit=5' \
  --data-urlencode "start=$(date -d '1 hour ago' +%s)000000000" \
  --data-urlencode "end=$(date +%s)000000000" \
  | jq '.data.result[].values[][1]'
```

---

### 6 — Tempo

**URL**: http://127.0.0.1:3201 *(API only — use Grafana Explore for UI)*

#### CLI

```bash
# Readiness check
curl http://127.0.0.1:3201/ready
# → ready

# Search recent traces for sample-app
curl -s 'http://127.0.0.1:3201/api/search?tags=service.name%3Dsample-app&limit=5' \
  | jq '.traces[] | {traceID, rootServiceName, durationMs}'

# Fetch a specific trace by ID
curl -s http://127.0.0.1:3201/api/traces/<trace-id> \
  | jq '.batches[].scopeSpans[].spans[].name'
```

---

### 7 — Temporal

**URL**: http://127.0.0.1:8090

#### CLI

```bash
export KUBECONFIG=/home/$USER/.kube/config-lab

# Check all Temporal pods are Running
kubectl -n temporal get pods

# Check worker deployment is Ready
kubectl -n temporal get deploy temporal-ops-worker

# Check CronJob schedule (fires every 10 min)
kubectl -n temporal get cronjob temporal-ops-heartbeat-trigger

# Trigger a workflow run immediately (skip waiting for cron)
kubectl -n temporal delete job manual-heartbeat-test --ignore-not-found=true
kubectl -n temporal create job --from=cronjob/temporal-ops-heartbeat-trigger manual-heartbeat-test
kubectl -n temporal wait --for=condition=complete job/manual-heartbeat-test --timeout=60s
kubectl -n temporal logs job/manual-heartbeat-test
# → Started workflow: ops-heartbeat-<uuid>

# List all workflow executions
kubectl -n temporal exec deploy/temporal -- \
  env TEMPORAL_CLI_ADDRESS=temporal:7233 tctl --ns default workflow listall

# Watch live worker logs
kubectl -n temporal logs deploy/temporal-ops-worker -f --tail=30
```

#### UI — View Completed Workflows

1. Open http://127.0.0.1:8090
2. Confirm namespace dropdown = **`default`** (not `temporal-system`)
3. Click the **Closed** filter — workflows finish in ~2 seconds so they are always closed
4. Rows show Workflow Type = `OpsHeartbeatWorkflow`
5. Click any row:
   - **Summary** tab: workflow ID, run ID, task queue, start/close times
   - **Input & Results** tab: input `"cron"` → result `{"workflow":"OpsHeartbeatWorkflow","source":"cron","status":"ok"}`
   - **Event History** tab: `WorkflowExecutionStarted → TimerStarted → TimerFired → WorkflowExecutionCompleted`

#### UI — Start a New Workflow from the Browser

1. Click **Start Workflow** (top-right button)
2. Fill the form:

   | Field | Value |
   |---|---|
   | Workflow ID | `manual-ui-test-001` *(or any unique string)* |
   | Workflow Type | `OpsHeartbeatWorkflow` |
   | Task Queue | `ops-task-queue` |
   | Input (JSON) | `"ui"` |

3. Click **Start**
4. Switch to the **Closed** filter within ~3 seconds
5. Find `manual-ui-test-001` → click it → **Input & Results** shows `{"source":"ui","status":"ok"}`

---

## Temporal Operational Workflow — How It Works

Source: `gitops/temporal/temporal-workflow.yaml`

**Components:**

| Resource | Kind | Purpose |
|---|---|---|
| `temporal-workflow-scripts` | ConfigMap | Embeds `workflows.py`, `worker.py`, `starter.py` |
| `temporal-ops-worker` | Deployment | Python worker — polls `ops-task-queue` continuously |
| `temporal-ops-heartbeat-trigger` | CronJob | Fires every 10 min, calls `starter.py` |

**Execution flow:**

1. CronJob fires → `starter.py` connects to `temporal:7233` namespace `default`
2. Starts `OpsHeartbeatWorkflow` with ID `ops-heartbeat-<uuid>` on task queue `ops-task-queue`
3. Worker picks up the task → sleeps 2 seconds (simulating an async platform health check)
4. Returns `{"workflow":"OpsHeartbeatWorkflow","source":"cron","status":"ok"}`
5. Execution closes with status **Completed**

**Workflow code** (`workflows.py`):
```python
@workflow.defn
class OpsHeartbeatWorkflow:
    @workflow.run
    async def run(self, source: str = "cron") -> dict:
        await workflow.sleep(timedelta(seconds=2))
        return {"workflow": "OpsHeartbeatWorkflow", "source": source, "status": "ok"}
```

> Workflows always land in **Closed** state within ~2 seconds. Use the **Closed** filter in the UI to find them.

---

## SLI/SLO + Alerting

| Item | Value |
|---|---|
| Alert rule file | `gitops/apps/alerts-prometheusrule.yaml` |
| Recording rule | embedded in `gitops/components/prometheus/prometheus-deployment.yaml` |
| Alert name | `SampleAppHighErrorRate` |
| SLO threshold | < 5% error rate (95% success) |
| Alert window | 2 minutes sustained |

**Error-rate SLI:**
```promql
sum(rate(http_requests_total{job="sample-app",code!~"2.."}[5m]))
/
sum(rate(http_requests_total{job="sample-app"}[5m]))
```

**Pre-aggregated recording rule:**
```promql
job:http_error_rate:5m
```

---

## AI SRE Agent + Failure Simulation

```bash
cd ai-agent
./simulate_failure.sh sample-app   # inject failure
python3 agent.py                    # query Prometheus + Loki, write RCA
cat rca_report.md                   # structured root-cause analysis
```

AI interaction history: `ai-log/ai_interactions.md`

---

## What Is Production-Oriented Here

- Namespace isolation for major domains (`lgtm`, `temporal`, `sample-app`, `argocd`)
- GitOps-only reconciliation after bootstrap — all changes go through Git → ArgoCD
- Resource requests/limits on all core workloads
- Liveness/readiness probes for app and platform components
- NetworkPolicy for sample-app namespace
- Dedicated ServiceAccount + RBAC for sample app
- SLI/SLO recording + alert rule
- Temporal operational workflow on cron schedule
- Credentials provisioned at bootstrap-time, never plaintext in Git

---

## Security Notes

- Grafana and Temporal DB credentials are provisioned at bootstrap time, not stored as plaintext in Git
- `infra/bootstrap-argocd.sh` creates Kubernetes secrets from env vars or generates random values
- For cloud production: replace with SealedSecrets / External Secrets Operator + KMS/Vault rotation

---

## Design Decisions and Trade-offs

- **k3d/k3s** — fast local iteration, realistic Kubernetes behaviour
- **GitOps app-of-app** — all changes go through Git; models production reconciliation
- **Mixed local manifests + Helm apps** — speed and deterministic control where needed
- **Temporal worker installs Python deps at runtime** — reduces local build complexity; production should use a prebuilt immutable worker image
- **Prometheus native `rule_files`** — no Prometheus Operator required; rules load from ConfigMap

---

## Roadmap

1. Replace bootstrap secrets with SealedSecrets or External Secrets Operator
2. Add CI pipeline: image build/push + policy checks (`kubeconform`, `conftest`)
3. Prebuilt Temporal worker image + workflow integration tests
4. Mimir for long-term metrics storage + dashboard-as-code provisioning
5. Runbook links and alert routing to PagerDuty / Slack
