# AI Interaction Log

This file captures the development interactions used to accelerate implementation, debugging, and hardening.

## Session Timeline (Summary)

### Session 1 — Platform bootstrap and GitOps wiring
- Used AI to scaffold and verify:
  - `infra/bootstrap-wsl.sh`
  - `infra/bootstrap-k3s.sh`
  - `infra/bootstrap-argocd.sh`
  - `gitops/apps/app-of-app.yaml`
- Outcome: ArgoCD root app (`platform-root`) reconciles the `gitops/apps` path.

### Session 2 — Observability stack stabilization
- Investigated Grafana datasource failures and Loki startup errors.
- Root causes identified and fixed:
  - Loki schema/storage mismatch and missing valid writable paths
  - Invalid Loki schema period for `boltdb-shipper`
- Resulting commits (examples):
  - `dea901a` fix loki crashloop by correcting storage schema and data mounts
  - `e458279` fix loki schema index period for boltdb-shipper

### Session 3 — Sample app reliability and telemetry visibility
- Investigated sample-app crash and Prometheus target failures.
- Root causes identified and fixed:
  - app typo in OTLP endpoint variable
  - network policy namespace selector mismatch
  - ingress port mismatch for scrape path
- Resulting commits (examples):
  - `39a2480` fix sample-app startup runtime typo handling
  - `a67a6ea` fix sample-app networkpolicy ingress port
  - `dd0705e` fix networkpolicy namespace selector labels

### Session 4 — GitOps app cleanup for reproducibility
- Removed duplicate/legacy Argo app manifests and standardized final app set.
- Pinned chart versions for deterministic team bootstrap.
- Resulting commits (examples):
  - `68816d8` finalize Argo apps and simplify deployment
  - `6a6fa2e` remove redundant namespace and duplicate Argo app manifests

### Session 5 — Production-readiness gap closure pass
- Added Temporal operational workflow resources:
  - worker deployment
  - periodic workflow trigger cronjob
- Hardened sample-app deployment:
  - removed runtime sed patch hack
  - wired ServiceAccount
  - tightened container security settings
- Improved secret handling posture by moving inline credentials to `Secret` objects in manifests.
- Updated README to reflect real architecture and reproducible bootstrap flow.

## Representative AI-Assisted Tasks

- Root cause analysis from logs/events (`kubectl logs`, `describe`, service endpoints, target health APIs)
- Manifest refactoring and conflict cleanup across Argo applications
- Troubleshooting port-forward collisions and validating endpoint readiness
- Converting tactical runtime fixes into declarative GitOps manifests
- Documenting setup and operational verification steps for handoff

## Notes

- This log is intentionally concise and engineering-focused.
- Command traces and concrete outcomes are reflected in commit history and repository diffs.
