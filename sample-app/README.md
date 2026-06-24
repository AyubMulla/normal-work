# Sample Application

## Overview

Production-grade Flask API that serves as the primary workload for demonstrating the observability stack. The app generates:

- **Metrics** (Prometheus format)
- **Structured Logs** (JSON to stdout, scraped by Promtail)
- **Traces** (OpenTelemetry OTLP/gRPC to Tempo)

## Application

### `app.py`

Flask HTTP server with the following endpoints:

| Endpoint | Method | Purpose | Response |
|---|---|---|---|
| `/health` | GET | Liveness/readiness probe | `{"status": "ok"}` |
| `/metrics` | GET | Prometheus scrape endpoint | Prometheus text format metrics |
| `/work` | GET | Simulates work (generates traces) | `{"status": "done", "delay": <float>s}` |
| `/` | GET | Index/info page | Basic HTML |

#### Metrics

**Custom metrics**:
- `http_requests_total` (counter) — Request count by `code`, `method`, `path`
- `request_duration_seconds` (histogram) — Request latency by `endpoint`
- `active_requests` (gauge) — Currently processing requests

**Labels**:
```
http_requests_total{job="sample-app", code="200", method="GET", path="/work"}
request_duration_seconds_bucket{endpoint="/work", le="0.5"}
```

#### Logs

**JSON structured logs** (Python logging module):
```json
{
  "asctime": "2026-06-24 16:37:48,318",
  "levelname": "INFO",
  "name": "root",
  "message": "request_processed",
  "path": "/work",
  "duration": 0.2,
  "status": 200
}
```

**Log levels**:
- `INFO` — Request lifecycle (start, complete)
- `WARNING` — Slow requests (>1s)
- `ERROR` — Uncaught exceptions, failed upstreams

#### Traces

**Distributed tracing** via OpenTelemetry SDK:
- Exporter: `OTLPSpanExporter` (gRPC)
- Endpoint: `http://lgtm-tempo.lgtm.svc.cluster.local:4317` (in-cluster)
- Spans created for:
  - HTTP request (root span)
  - Database operations (if any)
  - External API calls (simulated)

**Trace attributes**:
```
Span: "GET /work"
├─ http.method: "GET"
├─ http.url: "http://localhost:8080/work"
├─ http.status_code: 200
├─ http.response_content_type: "application/json"
└─ duration_ms: 523
```

### `requirements.txt`

Python dependencies:
```
flask==3.0.0
prometheus-client==0.19.0
opentelemetry-api==1.21.0
opentelemetry-sdk==1.21.0
opentelemetry-exporter-otlp==1.21.0
```

### `Dockerfile`

Multi-stage Docker build for minimal image.

**Base**: `python:3.11-slim` (~120 MB)

**Build stages**:
1. Install dependencies from `requirements.txt`
2. Copy application code
3. Set `PYTHONUNBUFFERED=1` for immediate log output
4. Expose port 8080
5. Run app with `python app.py`

**Image size**: ~250 MB (base + pip packages)

**Build & push**:
```bash
./infra/build-and-push.sh k3d-lab-registry:5000 sample-app latest
```

## Kubernetes Deployment

### `k8s/deployment.yaml`

Workload configuration:

**Replicas**: 2 (for HA testing)

**Resource limits**:
```yaml
requests:
  cpu: 100m
  memory: 128Mi
limits:
  cpu: 500m
  memory: 512Mi
```

**Health checks**:
- `readinessProbe` — GET /health, initialDelay 5s, period 10s
- `livenessProbe` — GET /health, initialDelay 15s, period 20s

**Environment**:
- `OTEL_EXPORTER_OTLP_ENDPOINT` — `http://lgtm-tempo.lgtm.svc.cluster.local:4317`

**Service Account**: Bound to `sample-app-sa` with RBAC permissions (get/list pods)

### `k8s/service.yaml` (in deployment.yaml)

ClusterIP service for in-cluster communication.

**Port mapping**: 80 (service) → 8080 (container)

**Annotations** (for Prometheus scraping):
```yaml
prometheus.io/scrape: "true"
prometheus.io/port: "80"
prometheus.io/path: "/metrics"
```

### `k8s/rbac.yaml`

ServiceAccount + Role + RoleBinding:

**Permissions**:
- `get/list/watch pods` — For debugging/introspection
- `get pods/log` — For reading pod logs

**Used by**: Sample-app pods (for potential self-diagnostics)

### `k8s/networkpolicy.yaml`

Deny-by-default network security policy:

**Ingress**:
- Allow from lgtm namespace (Tempo, Prometheus scrapers)
- Allow from same namespace (pod-to-pod)
- Port: 8080 (HTTP)

**Egress**:
- Allow DNS (UDP/TCP 53) to kube-dns (10.43.0.10)
- Allow to lgtm namespace (ports 4317/4318 for Tempo)
- Deny all else

**Purpose**: Enforce least privilege for observability integration

### `k8s/service-monitor.yaml`

Prometheus Operator ServiceMonitor for metric scraping.

**Scrape config**:
```yaml
interval: 30s
scrapeTimeout: 10s
scheme: http
metrics_path: /metrics
```

**Job label**: `job: sample-app` (visible in Prometheus queries)

## Local Testing

### Port-forward to sample-app

```bash
./infra/port-forward.sh

# OR manually:
kubectl port-forward -n sample-app svc/sample-app 8084:80
```

### Generate traffic

```bash
# Single request
curl http://127.0.0.1:8084/work

# Multiple requests
for i in {1..10}; do curl -s http://127.0.0.1:8084/work >/dev/null; done

# With output
curl http://127.0.0.1:8084/work | jq .
```

### Check metrics

```bash
curl http://127.0.0.1:8084/metrics | grep http_requests_total
```

**Output**:
```
# HELP http_requests_total All HTTP requests
# TYPE http_requests_total counter
http_requests_total{code="200",job="sample-app",method="GET",path="/health"} 42.0
http_requests_total{code="200",job="sample-app",method="GET",path="/metrics"} 21.0
http_requests_total{code="200",job="sample-app",method="GET",path="/work"} 10.0
```

### Check logs in Loki

```bash
./infra/port-forward.sh

# Query Loki directly
curl 'http://127.0.0.1:3101/loki/api/v1/query' \
  --data-urlencode 'query={app="sample-app"}'

# Or via Grafana (http://127.0.0.1:3000 → Explore → Loki)
```

**Sample log line**:
```json
{
  "asctime": "2026-06-24 16:37:48,318",
  "levelname": "INFO",
  "name": "root",
  "message": "request_processed",
  "path": "/work",
  "duration": 0.2,
  "status": 200
}
```

### Check traces in Tempo

```bash
./infra/port-forward.sh

# Query Tempo search API
curl 'http://127.0.0.1:3201/api/search?tags=service.name%3Dsample-app&limit=5'

# Or via Grafana Explore (http://127.0.0.1:3000 → Explore → Tempo)
```

**Sample trace**:
```json
{
  "traces": [
    {
      "traceID": "49d17fd14c8aafa5bceb4bd95b6ba664",
      "rootServiceName": "sample-app",
      "rootTraceName": "GET /work",
      "startTimeUnixNano": "1782318296318563968",
      "durationMs": 501
    }
  ]
}
```

## Production Ready Checklist

- ✅ Resource requests/limits defined
- ✅ Health checks (readiness + liveness)
- ✅ RBAC with least privilege
- ✅ Network policies (deny-by-default)
- ✅ Structured logging (JSON format)
- ✅ Prometheus metrics exported
- ✅ Distributed traces via OTLP
- ✅ Security context (no privilege escalation)
- ✅ 2 replicas for HA
- ✅ Service account binding

## Extending the Application

### Add a new endpoint

```python
@app.route("/api/expensive", methods=["GET"])
@app.before_request
def expensive_operation():
    """Simulate a CPU-intensive operation"""
    with tracer.start_as_current_span("expensive_computation"):
        result = sum(i**i for i in range(100))
    request_duration_seconds.observe(time.time() - start_time)
    return {"result": result}
```

### Add custom metrics

```python
from prometheus_client import Gauge

cache_hits = Gauge("cache_hits_total", "Total cache hits")
cache_misses = Gauge("cache_misses_total", "Total cache misses")

@app.route("/cached-value")
def get_cached_value():
    if value_in_cache():
        cache_hits.inc()
    else:
        cache_misses.inc()
    return {"value": ...}
```

### Add database tracing

```python
from opentelemetry.exporter import trace_api_telemetry

@app.route("/users/<user_id>")
def get_user(user_id):
    with tracer.start_as_current_span(f"db.query.users") as span:
        span.set_attribute("db.user_id", user_id)
        user = db.query(f"SELECT * FROM users WHERE id = {user_id}")
    return {"user": user}
```

## Troubleshooting

### App not starting

```bash
kubectl logs -n sample-app -l app=sample-app
# Check for OTLP export errors or dependency issues
```

### Metrics not appearing in Prometheus

```bash
# Check if pod is ready
kubectl get pod -n sample-app

# Verify service is discoverable
kubectl get svc -n sample-app

# Check Prometheus scrape configuration
kubectl get servicemonitor -n sample-app
```

### Traces not appearing in Tempo

```bash
# Check OTLP endpoint connectivity
kubectl exec -n sample-app pod/<pod-name> -- \
  python -c "import socket; socket.create_connection(('lgtm-tempo.lgtm.svc.cluster.local', 4317))"

# Check logs for export errors
kubectl logs -n sample-app -l app=sample-app | grep OTLP
```

## References

- [Flask Documentation](https://flask.palletsprojects.com/)
- [prometheus_client Python](https://github.com/prometheus/client_python)
- [OpenTelemetry Python](https://opentelemetry.io/docs/instrumentation/python/)
- [12-factor app manifesto](https://12factor.net/)

