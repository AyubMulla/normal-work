# RCA Report - sample-app (2026-06-23 08:01:53 UTC)

- Observed error rate (5m): None
- Pod restarts (sum): None
- CPU usage (rate 5m): None

No error logs found in Loki query or Loki unavailable.

## Correlation

## Suggested next steps
- `kubectl -n sample-app get pods -o wide` — check pod status and restarts
- Inspect logs in Loki for the top error patterns and timestamps
- Correlate slow requests using Tempo (open the trace UI)
- Scale up replicas or increase resource requests if CPU saturated