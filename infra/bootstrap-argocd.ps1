param(
	[string]$RepoURL = '',
	[string]$Path = 'gitops/apps',
	[string]$DestNamespace = 'platform-system'
)

write-host "Applying ArgoCD manifests..."
kubectl create namespace argocd -o yaml --dry-run=client | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

write-host "Waiting for argocd-server..."
kubectl wait --for=condition=Available deployment/argocd-server -n argocd --timeout=180s

if (-not $RepoURL) {
	write-host "No RepoURL provided. Please re-run with -RepoURL 'https://github.com/your-org/your-repo' to auto-create the platform root Application."
	write-host "You can still port-forward and create the App via the ArgoCD UI or CLI."
	write-host "kubectl -n argocd port-forward svc/argocd-server 8080:443"
	exit 0
}

write-host "Creating platform-root Application in ArgoCD pointing to $RepoURL/$Path"
$appYaml = @"
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
	name: platform-root
	namespace: argocd
spec:
	project: default
	source:
		repoURL: '$RepoURL'
		targetRevision: HEAD
		path: $Path
	destination:
		server: 'https://kubernetes.default.svc'
		namespace: $DestNamespace
	syncPolicy:
		automated:
			prune: true
			selfHeal: true
		syncOptions:
			- CreateNamespace=true
"@

$appYaml | kubectl apply -f -

write-host "Platform root Application created. ArgoCD will reconcile the GitOps apps in $Path."
write-host "Access ArgoCD UI with: kubectl -n argocd port-forward svc/argocd-server 8080:443"
write-host "Retrieve admin password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 --decode"