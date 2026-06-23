#!/usr/bin/env bash
set -euo pipefail

usage() { echo "Usage: $0 -r <git-repo-url> [-p <path>]"; exit 1; }

REPO=''
PATH_IN_REPO='gitops/apps'

while getopts "r:p:" opt; do
  case ${opt} in
    r ) REPO=${OPTARG} ;;
    p ) PATH_IN_REPO=${OPTARG} ;;
    * ) usage ;;
  esac
done

if [ -z "$REPO" ]; then
  usage
fi

echo "Installing ArgoCD into cluster..."
kubectl create namespace argocd || true
# use --validate=false to avoid CRD annotation size validation failures on some environments
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml --validate=false

echo "Waiting for argocd-server deployment to be available (120s)..."
kubectl -n argocd wait --for=condition=Available deployment/argocd-server --timeout=180s || true

# Ensure destination namespace exists so ArgoCD can create resources into it
kubectl create namespace platform-system || true

echo "Creating platform-root Application pointing to $REPO/$PATH_IN_REPO"
cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: platform-root
  namespace: argocd
spec:
  project: default
  source:
    repoURL: '$REPO'
    targetRevision: HEAD
    path: $PATH_IN_REPO
  destination:
    server: 'https://kubernetes.default.svc'
    namespace: platform-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF

echo "ArgoCD bootstrap applied. Port-forward ArgoCD UI with: kubectl -n argocd port-forward svc/argocd-server 8080:443"
