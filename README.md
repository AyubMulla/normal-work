# Production-Grade Local Platform (staff-sre)

This repository contains a production‑grade local platform scaffold (k3s/k3d, ArgoCD GitOps, LGTM observability, Temporal, sample app, and an AI SRE agent).

Purpose
- Prove out a production-like platform locally before touching cloud.
- Provide GitOps-managed workloads via ArgoCD.

Quick start (developer flow — WSL recommended)
1. Ensure WSL2 Ubuntu, Docker, and k3d are installed and working.
2. Create k3d cluster (example):
   - `k3d cluster create lab --api-port 6550 -p "127.0.0.1:5000:5000@loadbalancer"`
3. Export kubeconfig in WSL: `export KUBECONFIG=/home/$USER/.kube/config-lab`
4. Build sample app image and push to local registry (see `infra/build-and-push.sh`).
5. Bootstrap ArgoCD with `infra/bootstrap-argocd.sh -r <git-repo>` and let ArgoCD sync `gitops/`.

What I will commit in this branch
- `infra/bootstrap-k3s.sh` — idempotent cluster bootstrap skeleton
- `infra/bootstrap-argocd.sh` — ArgoCD bootstrap (existing; I'll iterate)
- `gitops/` — Application-of-Applications to manage LGTM & Temporal (existing)

Next steps (short term)
- Harden manifests with RBAC, resource requests/limits, NetworkPolicies, and Secrets management (sealed-secrets or external secret store).
- Replace Helm charts with pinned chart versions and reproducible values files.

Branch: `staff-sre/initial-bootstraps`
Engineering Assessment — Production-grade k3s GitOps platform (local)

Overview

This repository is a scaffold for a production-grade platform running on a local k3s cluster (via k3d). It demonstrates a full GitOps-driven stack managed by ArgoCD and a LGTM observability stack (Loki, Grafana, Tempo, Prometheus/Mimir), Temporal, a sample API that emits metrics/logs/traces, and an AI SRE agent that queries observability to produce an RCA.

Goal

Build a platform you'd be comfortable running in production, only difference: k3s (k3d) instead of EKS.

What's included
- k3d-based k3s bootstrap scripts
- ArgoCD bootstrap + GitOps repo layout (app-of-app)
- LGTM observability values and manifests (Helm values placeholders)
- Prometheus/Mimir integration with an example SLI/SLO and alert rule
- Temporal deployment + sample workflow
- Sample Flask API emitting structured logs, Prometheus metrics, and OpenTelemetry traces
- AI SRE agent (Python) that queries Loki/Prometheus/Tempo and produces structured RCA markdown

Prerequisites
- Docker Desktop (or Docker) on Windows
- PowerShell 7+ (for provided scripts) or WSL/Linux
- kubectl
- k3d (scripts can install if missing)
- argocd CLI (optional but helpful)

Quick bootstrap (high level)

1. Clone repo
2. If you prefer WSL (recommended for Linux-like environment), run the WSL scripts from inside your WSL2 distro:

```bash
# inside WSL2 shell
./infra/bootstrap-wsl.sh
./infra/build-and-push.sh k3d-lab-registry:5000 sample-app latest
./infra/bootstrap-argocd.sh -r 'https://github.com/your-org/your-repo'
```

Or on Windows PowerShell (non-WSL):

```powershell
infra\bootstrap-k3d.ps1 -ClusterName lab -RegistryName lab-registry
infra\build-and-push.ps1 -Registry k3d-lab-registry:5000 -Image sample-app -Tag latest
infra\bootstrap-argocd.ps1 -RepoURL 'https://github.com/your-org/your-repo'
```

3. Wait for workloads to reconcile (LGTM, Temporal, sample-app)

Full bootstrap commands (example):

```powershell
# 1. Create k3d cluster (requires k3d installed)
infra\bootstrap-k3d.ps1 -ClusterName lab -RegistryName lab-registry

# 2. Build and push sample app image to local registry (Docker required)
infra\build-and-push.ps1 -Registry k3d-lab-registry:5000 -Image sample-app -Tag latest

# 3. Install ArgoCD and create platform root app (point RepoURL to your git remote URL)
infra\bootstrap-argocd.ps1 -RepoURL 'https://github.com/your-org/your-repo'

# 4. Port-forward ArgoCD UI locally to login and observe sync

```

## Troubleshooting & Reconciliation

**Loki Configuration Issue (schema_config)**

If Loki pod fails with error `Please define loki.storage.bucketNames.chunks`:
- **Root Cause**: Loki 2.8.2+ requires explicit `schema_config` in the storage config, even when using boltdb-shipper
- **Solution**: Ensure `gitops/components/loki-local/loki-deployment.yaml` ConfigMap includes:
  ```yaml
  schema_config:
    configs:
      - from: 2020-10-24
        store: boltdb
        object_store: filesystem
        schema: v11
        index:
          prefix: index_
          period: 168h
  ```
- **Applied**: Switched `lgtm-loki` Application from Helm chart source to local manifests at `gitops/components/loki-local`

**Temporal Database Backend Issue**

If Temporal pod fails with `CASSANDRA_SEEDS env must be set if DB is cassandra`:
- **Root Cause**: Temporal auto-setup image defaults to Docker Compose behavior (cassandra + elasticsearch), which won't auto-initialize in Kubernetes
- **Solution**: Use in-cluster PostgreSQL backend instead:
  - Deploy `temporal-postgres` Deployment (postgres:15-alpine with emptyDir storage for development)
  - Set Temporal env: `DB=postgresql`, `POSTGRES_SEEDS=temporal-postgres`, `DB_PORT=5432`
  - Ensure all env values are quoted strings (e.g., `value: "5432"`, not `value: 5432`) to avoid ArgoCD unmarshalling errors
- **Applied**: Updated `gitops/temporal/temporal-deployment.yaml` with in-cluster Postgres and corrected env vars (commit: 4d37e43)

**ArgoCD Deployment Env Value Type Mismatches**

If ArgoCD Application shows error `cannot unmarshal number into Go struct field EnvVar.spec.template.spec.containers.env.value of type string`:
- **Root Cause**: Kubernetes env values must always be strings in YAML, even for ports/numbers; ArgoCD fails when numeric literals (`5432`) are used instead of quoted strings (`"5432"`)
- **Solution**: Quote all env values explicitly in Deployment manifests (e.g., `value: '5432'` or `value: "5432"`)
- **ArgoCD Sync Option**: Add `syncOptions: ["Replace=true"]` to Application spec to allow clean Deployment recreation instead of failed patch-based updates

**K3d Cluster Connectivity Loss**

If kubectl commands fail with `connection refused on 127.0.0.1:XXXXX`:
- **Root Cause**: K3d cluster nodes may stop unexpectedly (check with `k3d cluster ls`)
- **Solution**: Restart cluster with `k3d cluster start lab` and verify connectivity with `kubectl cluster-info`

Design decisions & tradeoffs
- Use k3d for deterministic local k3s clusters and reproducible testing.
- GitOps via ArgoCD — all workloads managed from `gitops/` (nothing applied manually after bootstrap).
- Observe strict namespace separation, resource requests/limits, liveness/readiness, and network policies across manifests.
- Use Helm for production-grade charts (values under `lgtm/`), but include concrete manifests for sample app and Temporal for clarity.
- Secrets: recommend SealedSecrets or external Vault in production — placeholder notes provided.

Files of interest
- infra/bootstrap-k3d.ps1 — create k3d cluster and load local registry
- infra/bootstrap-argocd.ps1 — install ArgoCD and bootstrap initial app-of-app
- gitops/ — ArgoCD-managed applications and values
- sample-app/ — Flask sample app, k8s manifests, Dockerfile
- ai-agent/ — Python AI SRE agent and usage

Next steps / Roadmap
- Complete Helm value tuning for Prometheus/Mimir and Tempo
- Add SealedSecrets + Vault integration for secret rotation
- Add real SLO dashboards and SLO operator integration
- Add CI to build images and push to local registry

AI Interaction Log
- A complete AI interaction log (transcripts used during development) will be added to `ai-log/` as `ai_interactions.md`.
 
Simulated failure and RCA

```powershell
# delete a sample-app pod to simulate outage
infra\simulate-failure.ps1 -Namespace sample-app

# run the AI SRE agent locally (ensure Prometheus and Loki endpoints are reachable from where you run the agent)
python -m pip install -r ai-agent/requirements.txt
python ai-agent/agent.py
```

License
- MIT (please add if needed)

Contact
- If you want me to fully implement Helm values and run the bootstrap locally on my machine, tell me to proceed and I'll continue.
