# Simple failure simulation for `sample-app`
# - deletes a single pod to simulate an outage
# - optional: inject latency by patching deployment to use a faulty image (not implemented)
param(
  [string]$Namespace = 'sample-app'
)

$pod = kubectl get pods -n $Namespace -l app=sample-app -o jsonpath='{.items[0].metadata.name}'
if ($pod) {
  Write-Host "Deleting pod $pod in namespace $Namespace to simulate failure"
  kubectl delete pod $pod -n $Namespace
} else {
  Write-Host "No pod found in namespace $Namespace with label app=sample-app"
}
