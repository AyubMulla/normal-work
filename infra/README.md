# Infrastructure & Bootstrap Scripts

## Overview

This directory contains all bootstrapping and infrastructure helper scripts for setting up the platform locally (k3d/k3s) or on cloud (EKS migration).

## Quick Start

### Linux (k3s native or k3d)

```bash
./bootstrap-k3s.sh
# or for Docker-based k3s:
./bootstrap-k3d.ps1  # PowerShell
./bootstrap-k3d.ps1  # or use k3d-linux variant
```

### macOS / Windows WSL

```bash
./bootstrap-wsl.sh
./bootstrap-k3d.ps1
```

### Windows PowerShell (native)

```powershell
.\bootstrap-k3d.ps1
.\bootstrap-argocd.ps1
```

## Cluster Setup Scripts

### `bootstrap-k3s.sh`
Native k3s cluster setup (Linux).

**What it does**:
- Installs k3s server with embedded storage (SQLite)
- Configures kubeconfig at `~/.kube/config-lab`
- Sets up kubectl completion
- Verifies core services (coredns, local-storage)

**Usage**:
```bash
./bootstrap-k3s.sh
export KUBECONFIG=~/.kube/config-lab
kubectl get nodes
```

### `bootstrap-k3d.ps1`
k3d cluster setup (Docker in container, works on all platforms).

**What it does**:
- Creates k3d cluster named `k3d-lab`
- Exposes local Docker registry (localhost:5000) for image push/pull
- Configures kubeconfig at `~/.kube/config-lab`
- Pre-creates common namespaces (lgtm, sample-app, temporal, argocd)

**Usage** (PowerShell):
```powershell
.\bootstrap-k3d.ps1
$env:KUBECONFIG="$HOME\.kube\config-lab"
kubectl get nodes
```

### `bootstrap-wsl.sh`
WSL-specific setup (Docker daemon, kubectl, k3d).

**What it does**:
- Checks/installs Docker in WSL
- Installs kubectl
- Installs k3d
- Sets up kubeconfig
- Creates k3d cluster

**Usage** (WSL bash):
```bash
./bootstrap-wsl.sh
export KUBECONFIG=~/.kube/config-lab
kubectl get nodes
```

## GitOps Setup

### `bootstrap-argocd.sh`
Deploys ArgoCD and the GitOps root app.

**What it does**:
- Installs ArgoCD via Helm (namespace: argocd)
- Creates platform-root App pointing to `gitops/apps`
- Sets Grafana/Temporal admin passwords (via env or auto-generated)
- Waits for ArgoCD API to be ready
- Triggers initial reconciliation

**Usage**:
```bash
export KUBECONFIG=~/.kube/config-lab
export GRAFANA_ADMIN_PASSWORD="secure-password-here"
export TEMPORAL_DB_PASSWORD="secure-db-password"

./bootstrap-argocd.sh -r 'https://github.com/AyubMulla/normal-work' \
                      -b 'staff-sre/initial-bootstraps'
```

**Parameters**:
- `-r, --repo` — Git repository URL (required)
- `-b, --branch` — Git branch (default: HEAD)

**Output**:
- ArgoCD API available at `https://127.0.0.1:8083`
- ArgoCD password: `admin` / value from `$ARGOCD_ADMIN_PASSWORD` env var (auto-generated if not set)
- Platform root app syncing automatically

### `bootstrap-argocd.ps1`
PowerShell variant of `bootstrap-argocd.sh`.

**Usage**:
```powershell
$env:KUBECONFIG="$HOME\.kube\config-lab"
$env:GRAFANA_ADMIN_PASSWORD="secure-password"
$env:TEMPORAL_DB_PASSWORD="secure-db-password"

.\bootstrap-argocd.ps1 -Repo 'https://github.com/AyubMulla/normal-work' `
                       -Branch 'staff-sre/initial-bootstraps'
```

## Docker & Image Management

### `build-and-push.sh`
Build sample-app image and push to registry.

**Usage**:
```bash
./build-and-push.sh <registry-url> <image-name> <tag>

# Example:
./build-and-push.sh k3d-lab-registry:5000 sample-app latest
```

**What it does**:
- Builds `Dockerfile` from `sample-app/`
- Tags and pushes to local registry
- Updates `sample-app/k8s/deployment.yaml` image field
- (Optional) Commits changes to git

### `build-and-push.ps1`
PowerShell variant.

**Usage**:
```powershell
.\build-and-push.ps1 -Registry "k3d-lab-registry:5000" `
                      -ImageName "sample-app" `
                      -Tag "latest"
```

## Utilities

### `port-forward.sh`
Manage kubectl port-forward tunnels to local services.

**Usage**:
```bash
./port-forward.sh                 # Start all port-forwards
./port-forward.sh status          # Show active PF sessions
./port-forward.sh stop            # Stop all managed PF
./port-forward.sh clean           # Cleanup orphan processes
```

**Managed services**:
- Grafana (3000)
- ArgoCD (8083)
- Sample app (8084)
- Temporal UI (8090)
- Prometheus (9091)
- Loki (3101)
- Tempo (3201)

### `check-docker-access-wsl.sh`
Verify Docker daemon is accessible from WSL.

**Troubleshooting**:
```bash
./check-docker-access-wsl.sh
# If fails, run:
./start-dockerd-wsl.sh
```

### `restart-dockerd-wsl.sh`
Restart Docker daemon in WSL.

**Usage**:
```bash
./restart-dockerd-wsl.sh
```

### `fix-docker-list-wsl.sh` / `fix-socket-wsl.sh`
Fix Docker socket issues in WSL.

**Common error**:
```
error during connect: Post "http://%2Fvar%2Frun%2Fdocker.sock/v1.24/...": 
dial unix /var/run/docker.sock: permission denied
```

**Fix**:
```bash
./fix-socket-wsl.sh
```

## Installation Scripts

### `install-kubectl.ps1`
Install kubectl on Windows.

```powershell
.\install-kubectl.ps1
kubectl version --client
```

### `install-k3d.ps1`
Install k3d on Windows.

```powershell
.\install-k3d.ps1
k3d version
```

### `install-docker.ps1`
Install Docker Desktop on Windows.

```powershell
.\install-docker.ps1
docker version
```

### `install-docker-wsl.sh`
Install Docker in WSL.

```bash
./install-docker-wsl.sh
docker version
```

## Complete Bootstrap Workflow

### From Scratch (Linux)

```bash
# 1. Setup cluster
git clone https://github.com/AyubMulla/normal-work.git
cd normal-work/lab

export KUBECONFIG=~/.kube/config-lab
./infra/bootstrap-k3s.sh

# 2. Setup GitOps
export GRAFANA_ADMIN_PASSWORD="MySecurePassword123!"
./infra/bootstrap-argocd.sh \
  -r 'https://github.com/AyubMulla/normal-work' \
  -b 'staff-sre/initial-bootstraps'

# 3. Build and push sample-app
./infra/build-and-push.sh k3d-lab-registry:5000 sample-app latest

# 4. Wait for apps to sync (watch in another terminal)
kubectl -n argocd get app -w

# 5. Port-forward to services
./infra/port-forward.sh

# 6. Open Grafana
open http://127.0.0.1:3000
```

### From Scratch (Windows WSL)

```bash
# 1. Setup cluster
cd normal-work/lab
export KUBECONFIG=~/.kube/config-lab
./infra/bootstrap-wsl.sh

# 2. Setup GitOps
export GRAFANA_ADMIN_PASSWORD="MySecurePassword123!"
./infra/bootstrap-argocd.sh \
  -r 'https://github.com/AyubMulla/normal-work' \
  -b 'staff-sre/initial-bootstraps'

# 3-6. Same as Linux...
```

### From Scratch (Windows PowerShell)

```powershell
# 1. Setup cluster
cd normal-work/lab
$env:KUBECONFIG="$HOME\.kube\config-lab"
.\infra\bootstrap-k3d.ps1

# 2. Setup GitOps
$env:GRAFANA_ADMIN_PASSWORD="MySecurePassword123!"
.\infra\bootstrap-argocd.ps1 -Repo 'https://github.com/AyubMulla/normal-work'

# 3-6. Similar to above...
```

## Troubleshooting

### Cluster not starting

Check logs:
```bash
kubectl logs -n kube-system -l k8s-app=coredns
kubectl logs -n kube-system -l app=local-path-provisioner
```

### ArgoCD controller not ready

```bash
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller
kubectl get pod -n argocd
```

### Port-forward failures

```bash
# Check if ports are already in use
ss -ltn | grep ':3000\|:8083\|:8084'

# Kill existing processes
pkill -f "kubectl.*port-forward"

# Retry
./infra/port-forward.sh
```

### Docker issues in WSL

```bash
# Check Docker status
ps aux | grep dockerd

# Restart Docker
./infra/restart-dockerd-wsl.sh

# Verify connectivity
docker ps
```

## References

- [k3s Documentation](https://docs.k3s.io/)
- [k3d Documentation](https://k3d.io/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [kubectl cheatsheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)

