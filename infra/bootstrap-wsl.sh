#!/usr/bin/env bash
set -euo pipefail

# Bootstrap k3d/k3s in WSL2-friendly environment.
# Assumes Docker daemon is available in WSL (Docker Desktop WSL integration recommended)

echo "Checking docker..."
if ! command -v docker >/dev/null 2>&1; then
  echo "Docker CLI not found in WSL. Please enable Docker Desktop WSL integration or install docker inside WSL and start the daemon."
  exit 1
fi

echo "Installing prerequisites..."
sudo apt-get update -y
sudo apt-get install -y curl ca-certificates gnupg lsb-release

if ! command -v kubectl >/dev/null 2>&1; then
  echo "Installing kubectl..."
  KUBE_VER=$(curl -s https://dl.k8s.io/release/stable.txt)
  curl -L --fail -o kubectl "https://dl.k8s.io/release/${KUBE_VER}/bin/linux/amd64/kubectl"
  sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
  rm kubectl
fi

if ! command -v k3d >/dev/null 2>&1; then
  echo "Installing k3d..."
  curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | TAG=v5.9.0 bash
fi

REG_NAME="lab-registry"
CLUSTER_NAME="lab"

echo "Ensure local registry exists: $REG_NAME"
if ! k3d registry list | grep -q "$REG_NAME"; then
  k3d registry create $REG_NAME --port 5000
fi

echo "Creating k3d cluster $CLUSTER_NAME..."
k3d cluster create $CLUSTER_NAME --servers 1 --agents 1 --registry-use k3d-$REG_NAME:5000 --wait

echo "Cluster created. Setting kubectl context to k3d-$CLUSTER_NAME"
k3d kubeconfig get $CLUSTER_NAME > ~/.kube/config-$CLUSTER_NAME
kubectl config use-context k3d-$CLUSTER_NAME

echo "Bootstrap complete. You can now run infra/bootstrap-argocd.sh -r <git-repo-url> to install ArgoCD and bootstrap GitOps apps."
