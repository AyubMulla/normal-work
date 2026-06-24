#!/usr/bin/env bash
# ============================================================
# infra/port-forward.sh
# Start (or stop) all platform port-forwards in one shot.
#
# Usage:
#   ./infra/port-forward.sh          # start all
#   ./infra/port-forward.sh stop     # kill all managed PF processes
#   ./infra/port-forward.sh status   # print which ports are live
# ============================================================
set -euo pipefail

export KUBECONFIG="${KUBECONFIG:-/home/$USER/.kube/config-lab}"
PF_PIDFILE="/tmp/.lab-port-forwards.pids"

# ── port-forward definitions ─────────────────────────────────
#  FORMAT: "namespace|service|local-port|remote-port|friendly-name"
FORWARDS=(
  "lgtm|lgtm-grafana|3000|80|Grafana"
  "argocd|argocd-server|8083|443|ArgoCD"
  "temporal|temporal-web|8090|8088|Temporal UI"
  "sample-app|sample-app|8084|80|Sample App"
  "lgtm|prometheus-local|9091|9090|Prometheus"
  "lgtm|loki-local|3101|3100|Loki"
  "lgtm|lgtm-tempo|3201|3200|Tempo"
)

# ── helpers ───────────────────────────────────────────────────
log()  { echo "[pf] $*"; }
err()  { echo "[pf] ERROR: $*" >&2; }

wait_for_port() {
  local port=$1 retries=15
  while ! nc -z 127.0.0.1 "$port" 2>/dev/null; do
    ((retries--)) || return 1
    sleep 0.5
  done
}

# ── start ─────────────────────────────────────────────────────
start_all() {
  if [[ -f "$PF_PIDFILE" ]]; then
    log "Port-forwards already tracked (${PF_PIDFILE}). Run '$0 stop' first."
    exit 0
  fi

  log "Starting port-forwards..."
  local pids=()

  for entry in "${FORWARDS[@]}"; do
    IFS='|' read -r ns svc lport rport name <<< "$entry"
    kubectl -n "$ns" port-forward "svc/$svc" "${lport}:${rport}" \
      --address=127.0.0.1 >/tmp/pf-${lport}.log 2>&1 &
    local pid=$!
    pids+=("$pid")

    if wait_for_port "$lport"; then
      log "  ✓ ${name} → http://127.0.0.1:${lport}  (pid $pid)"
    else
      err "  ✗ ${name} (port ${lport}) did not come up in time — check /tmp/pf-${lport}.log"
    fi
  done

  printf '%s\n' "${pids[@]}" > "$PF_PIDFILE"
  echo ""
  log "All port-forwards started. PID file: ${PF_PIDFILE}"
  log "Run '$0 status' to check or '$0 stop' to tear down."
}

# ── stop ──────────────────────────────────────────────────────
stop_all() {
  if [[ ! -f "$PF_PIDFILE" ]]; then
    log "No PID file found. Nothing to stop."
    return
  fi
  log "Stopping port-forwards..."
  while IFS= read -r pid; do
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" && log "  killed pid $pid" || err "  failed to kill $pid"
    fi
  done < "$PF_PIDFILE"
  rm -f "$PF_PIDFILE"
  log "Done."
}

# ── status ────────────────────────────────────────────────────
status_all() {
  printf "\n%-18s %-5s %-6s %s\n" "Service" "Port" "Up?" "URL"
  printf '%.0s─' {1..60}; echo

  for entry in "${FORWARDS[@]}"; do
    IFS='|' read -r ns svc lport rport name <<< "$entry"
    if nc -z 127.0.0.1 "$lport" 2>/dev/null; then
      up="✓"
    else
      up="✗"
    fi
    printf "%-18s %-5s %-6s http://127.0.0.1:%s\n" "$name" "$lport" "$up" "$lport"
  done
  echo
}

# ── main ──────────────────────────────────────────────────────
case "${1:-start}" in
  start)  start_all  ;;
  stop)   stop_all   ;;
  status) status_all ;;
  *)
    echo "Usage: $0 [start|stop|status]"
    exit 1
    ;;
esac
