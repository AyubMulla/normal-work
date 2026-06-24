# AI Interaction Log

This file captures the complete development interaction flow with AI assistance, including prompts, AI-generated actions, validation steps, and outcomes.

## Session 1 — Bootstrap and GitOps foundation

### Prompt
- "Set up local k3s/k3d platform with ArgoCD app-of-app so everything is managed from GitOps manifests."

### AI Actions
- Generated bootstrap scripts for local cluster and ArgoCD installation.
- Created root Argo application pointing to `gitops/apps`.
- Added basic namespace and app scaffolding for platform services.

### Validation
- Verified ArgoCD server availability.
- Verified root app creation and reconciliation behavior.

### Outcome
- GitOps control plane established with app-of-app pattern and deterministic bootstrap path.

## Session 2 — Loki and observability stack recovery

### Prompt
- "Grafana datasources and Loki are not stable. Make this permanent and production-leaning."

### AI Actions
- Investigated Loki pod logs and restart behavior.
- Identified storage/path and schema issues in Loki config.
- Patched manifest to use valid writable path and valid `boltdb-shipper` schema period.

### Validation
- Checked Loki rollout status and readiness endpoints.
- Confirmed Grafana datasource queries succeeded.

### Outcome
- Loki moved from crashloop to healthy steady state.
- Representative commits:
  - `dea901a` fix loki crashloop by correcting storage schema and data mounts
  - `e458279` fix loki schema index period for boltdb-shipper

## Session 3 — Sample app runtime fixes and telemetry wiring

### Prompt
- "Sample app keeps failing and metrics/logs/traces are not reliable."

### AI Actions
- Inspected app errors and identified typo in OTLP variable handling.
- Corrected network policy namespace selectors and ingress port mismatch.
- Ensured Prometheus scrape integration aligned with emitted metrics labels.

### Validation
- Verified pod health and rollout state.
- Verified sample-app health endpoint and scrape path.

### Outcome
- Sample app stabilized and telemetry became visible in observability stack.
- Representative commits:
  - `39a2480` fix sample-app startup runtime typo handling
  - `a67a6ea` fix sample-app networkpolicy ingress port
  - `dd0705e` fix networkpolicy namespace selector labels

## Session 4 — ArgoCD cleanup and final app topology

### Prompt
- "Remove unnecessary Argo apps and keep only final manifests for handoff."

### AI Actions
- Removed duplicate/legacy app manifests.
- Consolidated final application set for deterministic reconciliation.
- Pinned chart versions for reproducibility.

### Validation
- Reconciled apps with hard refresh.
- Verified app list converged to expected set and health state.

### Outcome
- Final app topology reduced to production-relevant components only.
- Representative commits:
  - `68816d8` finalize Argo apps and simplify deployment
  - `6a6fa2e` remove redundant namespace and duplicate Argo app manifests

## Session 5 — Temporal operational workflow and day-2 behavior

### Prompt
- "Add a real operational workflow in Temporal and keep it healthy."

### AI Actions
- Added workflow scripts config map.
- Added Temporal worker deployment.
- Added cron-based workflow trigger job.
- Fixed namespace binding and script issues to keep worker functional.

### Validation
- Verified worker deployment, cronjob, and jobs execution.
- Checked Temporal app sync/health and worker logs.

### Outcome
- Operational workflow (`OpsHeartbeatWorkflow`) runs on schedule in cluster.

## Session 6 — Credentials, persistence drift, and access stabilization

### Prompt
- "Grafana credentials are not working."

### AI Actions
- Compared expected credentials with runtime auth behavior.
- Identified persisted Grafana DB state drift from manifest intent.
- Reset runtime admin password and aligned with desired credential.

### Validation
- Verified new credentials return success.
- Verified old credentials fail.

### Outcome
- Access restored and documented for handoff.

## Session 7 — Submission hardening and assessment closeout

### Prompt
- "Check against assessment criteria and close remaining gaps."

### AI Actions
- Audited deliverables against objective/success criteria.
- Removed plaintext committed secrets from GitOps manifests.
- Updated bootstrap to provision required secrets from environment variables or generated random values.
- Corrected Temporal workflow script indentation bug.
- Expanded docs and this AI log for assessment review clarity.

### Validation
- Performed manifest and repo consistency checks.
- Verified branch cleanliness/sync with remote.

### Outcome
- Repository is in final handoff-ready state for local production-grade assessment demonstration.

## AI-Assisted Tooling Pattern Used

- Rapid hypothesis generation from logs and health signals.
- Declarative manifest patch generation with minimal blast radius.
- Iterative reconcile/verify loops (`rollout`, `get`, `logs`, endpoint probes).
- Documentation updates tied to operational state changes.

## Deliverable Traceability

- Architecture and bootstrap flow: `README.md`
- GitOps app definitions: `gitops/apps/`
- Temporal operational workflow: `gitops/temporal/temporal-workflow.yaml`
- AI RCA agent and simulation: `ai-agent/agent.py`, `ai-agent/simulate_failure.sh`
- This interaction history: `ai-log/ai_interactions.md`
