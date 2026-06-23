# Bootstrap a local k3s cluster using k3d (Windows PowerShell)
# Installs k3d if missing and creates a cluster named 'lab'






# create a local registry for images
# Bootstrap a local k3s cluster using k3d (Windows PowerShell)
# Installs k3d if missing and creates a cluster named 'lab'

# Prereqs: Docker Desktop running
param(
    # optional cluster name
    [string]$ClusterName = 'lab',
    # optional registry name (k3d registry will be created as k3d-<name>)
    [string]$RegistryName = 'lab-registry',
    # number of agent nodes
    [int]$NodeCount = 1
)

write-host "Checking k3d..."
$k3dExe = 'k3d'
if (Test-Path 'C:\\tools\\k3d.exe') {
    Write-Host "Using k3d from C:\\tools\\k3d.exe"
    $k3dExe = 'C:\\tools\\k3d.exe'
} elseif (-not (Get-Command k3d -ErrorAction SilentlyContinue)) {
    Write-Host "k3d not found. Please install k3d: https://k3d.io/ and re-run this script."
    exit 1
}
# detect kubectl binary if present in C:\tools for use later in this script
$kubectlExe = 'kubectl'
if (Test-Path 'C:\\tools\\kubectl.exe') {
    Write-Host "Using kubectl from C:\\tools\\kubectl.exe"
    $kubectlExe = 'C:\\tools\\kubectl.exe'
}

# create a local registry for images (k3d registry names are prefixed with k3d- when used by clusters)
write-host "Creating local registry (if missing)..."
$existing = & $k3dExe registry list | Select-String $RegistryName -Quiet
if (-not $existing) {
    & $k3dExe registry create $RegistryName --port 5000
}

# create cluster
write-host "Creating cluster $ClusterName..."
& $k3dExe cluster create $ClusterName --servers 1 --agents $NodeCount --registry-use k3d-$RegistryName:5000 --wait

write-host "Cluster created. Setting kubectl context..."
& $k3dExe kubeconfig get $ClusterName | Out-File -Encoding ascii "$env:USERPROFILE\.kube\config-$ClusterName"
try {
    & $kubectlExe config use-context k3d-$ClusterName
} catch {
    Write-Warning "kubectl not available in PATH or at C:\\tools; kubeconfig written to $env:USERPROFILE\\.kube\\config-$ClusterName. Import it into your kubectl context manually."
}

write-host "Cluster ready. You can now run infra\bootstrap-argocd.ps1 -RepoURL '<your-repo-url>' to install ArgoCD and bootstrap GitOps."