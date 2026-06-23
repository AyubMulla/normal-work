#!/usr/bin/env bash
set -euo pipefail

# Idempotent k3d/k3s bootstrap skeleton for local development
# This script documents and automates cluster creation, registry setup, and kubeconfig placement.

REGISTRY_NAME="k3d-lab-registry"
CLUSTER_NAME="lab"

echo "Ensuring k3d cluster '${CLUSTER_NAME}' and registry '${REGISTRY_NAME}'..."

if ! command -v k3d >/dev/null 2>&1; then
  echo "k3d not found - please install k3d and docker first" >&2
  exit 1
fi

if ! k3d registry list | grep -q "${REGISTRY_NAME}"; then
  echo "Creating registry ${REGISTRY_NAME} on port 5000"
  k3d registry create ${REGISTRY_NAME} --port 5000
fi

if ! k3d cluster list | grep -q "${CLUSTER_NAME}"; then
  echo "Creating cluster ${CLUSTER_NAME} and connecting registry"
  k3d cluster create ${CLUSTER_NAME} --api-port 6550 -p "127.0.0.1:5000:5000@loadbalancer" --registry-use k3d-${REGISTRY_NAME}:5000
else
  echo "Cluster ${CLUSTER_NAME} already exists"
fi

KUBECONFIG_PATH="$HOME/.kube/config-${CLUSTER_NAME}"
echo "Writing kubeconfig to ${KUBECONFIG_PATH}"
k3d kubeconfig get ${CLUSTER_NAME} > "${KUBECONFIG_PATH}"
echo "Bootstrap complete. Export KUBECONFIG=${KUBECONFIG_PATH}"
