# Build the `sample-app` Docker image and push to k3d local registry
param(
  [string]$Registry = 'k3d-lab-registry:5000',
  [string]$Image = 'sample-app',
  [string]$Tag = 'latest'
)

$full = "$Registry/$Image:$Tag"
Write-Host "Building image $full"
docker build -t $full sample-app
Write-Host "Pushing image $full"
docker push $full
Write-Host "Image pushed. You may need to update imagePullSecrets if using private registry."
