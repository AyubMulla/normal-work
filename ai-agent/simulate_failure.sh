#!/usr/bin/env bash
set -euo pipefail

# Simulate a failure by deleting one sample-app pod, wait, then run RCA agent
KUBECONFIG=${KUBECONFIG:-/home/ayub/.kube/config-lab}
NAMESPACE=${1:-sample-app}

echo "Finding sample-app pod to delete in namespace $NAMESPACE"
POD=$(kubectl --kubeconfig="$KUBECONFIG" -n "$NAMESPACE" get pods -l app=sample-app -o jsonpath='{.items[0].metadata.name}')
if [ -z "$POD" ]; then
  echo "No sample-app pod found" >&2
  exit 1
fi

echo "Deleting pod $POD"
kubectl --kubeconfig="$KUBECONFIG" -n "$NAMESPACE" delete pod "$POD"

echo "Waiting 15s for system to record metrics/logs"
sleep 15

echo "Running AI SRE agent to produce RCA..."
python3 agent.py || true

echo "Done. RCA output at ai-agent/rca_report.md"
