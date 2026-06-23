"""
Simple AI SRE agent prototype:
- Queries Prometheus and Loki to find anomalies for `sample-app`
- Produces a structured RCA markdown file

This is a minimal, extensible prototype for the assessment.
"""
import requests
import time
import os
import traceback

PROM_URL = os.getenv('PROM_URL', 'http://localhost:9090')
LOKI_URL = os.getenv('LOKI_URL', 'http://localhost:3100')
TEMPO_URL = os.getenv('TEMPO_URL', 'http://localhost:3200')
OUTPUT = os.getenv('OUTPUT_FILE', 'ai-agent/rca_report.md')


def query_prometheus(query):
    r = requests.get(f"{PROM_URL}/api/v1/query", params={'query': query}, timeout=10)
    r.raise_for_status()
    return r.json()


def query_loki(query):
    r = requests.get(f"{LOKI_URL}/loki/api/v1/query", params={'query': query}, timeout=10)
    r.raise_for_status()
    return r.json()


def detect_error_rate_spike():
    q = 'sum(rate(http_requests_total{job="sample-app",code!~"2.."}[5m])) / sum(rate(http_requests_total{job="sample-app"}[5m]))'
    try:
        resp = query_prometheus(q)
        val = float(resp['data']['result'][0]['value'][1]) if resp['data']['result'] else 0.0
        return val
    except Exception:
        return None


def detect_pod_restarts():
    # look for recent restarts in the sample-app namespace
    q = 'sum(kube_pod_container_status_restarts_total{namespace="sample-app"})'
    try:
        resp = query_prometheus(q)
        val = int(float(resp['data']['result'][0]['value'][1])) if resp['data']['result'] else 0
        return val
    except Exception:
        return None


def detect_cpu_spike():
    # generic CPU usage spike over 5m for sample-app containers (may vary by metrics setup)
    q = 'sum(rate(container_cpu_usage_seconds_total{namespace="sample-app"}[5m]))'
    try:
        resp = query_prometheus(q)
        val = float(resp['data']['result'][0]['value'][1]) if resp['data']['result'] else 0.0
        return val
    except Exception:
        return None


def search_recent_errors():
    q = '{app="sample-app"} |= "ERROR"'
    try:
        resp = query_loki(q)
        return resp.get('data', {})
    except Exception:
        return None


def build_rca(error_rate, restarts, cpu_usage, logs):
    now = time.strftime('%Y-%m-%d %H:%M:%S', time.gmtime())
    lines = [f"# RCA Report - sample-app ({now} UTC)", ""]
    lines.append(f"- Observed error rate (5m): {error_rate}")
    lines.append(f"- Pod restarts (sum): {restarts}")
    lines.append(f"- CPU usage (rate 5m): {cpu_usage}")
    lines.append("")

    if logs and logs.get('result'):
        lines.append('## Sample logs (first results)')
        for r in logs['result'][:10]:
            # human-friendly formatting of Loki result entries
            lines.append(f"- {r}")
    else:
        lines.append('No error logs found in Loki query or Loki unavailable.')

    lines.append('\n## Correlation')
    if error_rate and error_rate > 0.05:
        lines.append('- Error rate is above threshold (5%). Prioritize investigating logs and recent deploys.')
    if restarts and restarts > 0:
        lines.append('- Pods have restarted recently. Inspect container kill reasons and OOM events.')
    if cpu_usage and cpu_usage > 0.5:
        lines.append('- Elevated CPU usage detected; may explain increased latency and errors.')

    lines.append('\n## Suggested next steps')
    lines.append('- `kubectl -n sample-app get pods -o wide` — check pod status and restarts')
    lines.append('- Inspect logs in Loki for the top error patterns and timestamps')
    lines.append('- Correlate slow requests using Tempo (open the trace UI)')
    lines.append('- Scale up replicas or increase resource requests if CPU saturated')

    with open(OUTPUT, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines))
    return OUTPUT


if __name__ == '__main__':
    print('Running AI SRE agent checks...')
    try:
        er = detect_error_rate_spike()
        restarts = detect_pod_restarts()
        cpu = detect_cpu_spike()
        lg = search_recent_errors()
        out = build_rca(er, restarts, cpu, lg)
        print('RCA written to', out)
    except Exception as e:
        print('Agent failed:', e)
        traceback.print_exc()
