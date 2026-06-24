# AI SRE Agent

## Overview

This directory contains the **AI-powered SRE agent** for automated Root Cause Analysis (RCA) on the platform. The agent queries the observability stack (Prometheus, Loki, Tempo) to detect anomalies and generate structured RCA reports.

## Components

### `agent.py`
Main RCA agent that performs automated diagnostics:
- **Error rate spike detection** — Queries Prometheus for HTTP error rate anomalies
- **Pod restart analysis** — Detects unplanned pod restarts via `kube_pod_container_status_restarts_total`
- **CPU spike detection** — Identifies CPU saturation in the cluster
- **Log correlation** — Searches Loki for ERROR-level logs in sample-app
- **RCA report generation** — Produces a markdown report with findings and suggested next steps

**Output**: `rca_report.md` (structured findings with correlation insights)

### `simulate_failure.sh`
Failure injection script for testing the RCA agent.

**Options**:
```bash
./simulate_failure.sh kill-pod       # Kill a sample-app pod to trigger restarts
./simulate_failure.sh inject-latency # Inject network latency via tc
./simulate_failure.sh kill-all       # Kill all sample-app pods
```

After injecting a failure, run the agent:
```bash
python agent.py
```

The agent will detect the anomaly and generate an RCA report.

### `run_rca_after_failure.sh`
Helper script to:
1. Simulate a failure
2. Wait for metrics to stabilize
3. Run the RCA agent
4. Display the RCA report

**Usage**:
```bash
./run_rca_after_failure.sh kill-pod
```

## Usage

### Prerequisites

Environment variables (optional, defaults shown):
```bash
export PROM_URL="http://localhost:9090"      # Prometheus endpoint
export LOKI_URL="http://localhost:3100"      # Loki endpoint
export TEMPO_URL="http://localhost:3200"     # Tempo endpoint (for future correlation)
export OUTPUT_FILE="ai-agent/rca_report.md"  # RCA report output path
```

### Run the Agent

```bash
# Ensure port-forwards are active
./infra/port-forward.sh

# Run the agent
python ai-agent/agent.py

# View the report
cat ai-agent/rca_report.md
```

## Example Workflow

### Scenario: Pod Crash Loop

```bash
# Terminal 1: Start port-forwards
./infra/port-forward.sh

# Terminal 2: Inject failure
cd ai-agent
./simulate_failure.sh kill-pod
sleep 10

# Terminal 3: Run RCA
python agent.py

# View findings
cat rca_report.md
```

**Expected RCA output**:
```markdown
# RCA Report - sample-app (2026-06-24 16:45:00 UTC)

- Observed error rate (5m): 0.95
- Pod restarts (sum): 2
- CPU usage (rate 5m): None
- ...

## Correlation
- Error rate is above threshold (5%). Prioritize investigating logs and recent deploys.
- Pods have restarted recently. Inspect container kill reasons and OOM events.
```

## Extending the Agent

Add new detection capabilities:

```python
def detect_memory_pressure():
    """Detect OOM events or memory saturation"""
    q = 'sum(rate(container_memory_rss_bytes{namespace="sample-app"}[5m]))'
    try:
        resp = query_prometheus(q)
        # Parse and return findings
    except Exception:
        return None
```

Then update `build_rca()` to include the new metric in the correlation section.

## Day 2 Operations

In production, this agent would:
- Run on a schedule (e.g., every 5 minutes) to detect anomalies
- Integrate with Temporal for workflows (e.g., auto-remediation)
- Send RCA summaries to Slack/PagerDuty/email
- Store RCA history for post-mortems

### Potential Auto-Remediation

```python
if error_rate > 0.1 and cpu_usage > 0.8:
    # Scale up replicas
    scale_app_replicas(3)
    
    # Trigger workflow for manual review
    temporal_client.start_workflow(
        ReviewAndRollbackWorkflow,
        reason="High error rate with CPU saturation"
    )
```

## Architecture

```
sample-app (generates metrics/logs/traces)
       ↓
Prometheus (stores metrics), Loki (stores logs), Tempo (stores traces)
       ↓
agent.py (queries data + correlates)
       ↓
rca_report.md (human-readable findings)
```

## Troubleshooting

### Agent cannot connect to Prometheus/Loki

```bash
# Verify port-forwards are running
./infra/port-forward.sh status

# Or manually check connectivity
curl http://localhost:9090/api/v1/query?query=up
curl http://localhost:3100/loki/api/v1/query?query={job="promtail"}
```

### No metrics/logs available yet

Run sample-app traffic to generate data:
```bash
for i in {1..10}; do curl http://127.0.0.1:8084/work; done
```

Wait 30 seconds for Prometheus to scrape and Loki to ingest.

## References

- [Prometheus API Reference](https://prometheus.io/docs/prometheus/latest/querying/api/)
- [Loki API Reference](https://grafana.com/docs/loki/latest/api/)
- [RCA Best Practices](https://www.blameless.com/rca)

