# Install k3d on Windows using choco/scoop or download binary to C:\tools
Write-Host "Starting k3d installer script"

if (Get-Command k3d -ErrorAction SilentlyContinue) {
    Write-Host "k3d already installed"
    k3d version
    exit 0
}

if (Get-Command choco -ErrorAction SilentlyContinue) {
    Write-Host "Installing k3d via Chocolatey..."
    choco install k3d -y
    exit 0
}

if (Get-Command scoop -ErrorAction SilentlyContinue) {
    Write-Host "Installing k3d via Scoop..."
    scoop install k3d
    exit 0
}

Write-Host "No choco or scoop detected, downloading k3d binary to C:\\tools"
$tools = 'C:\\tools'
New-Item -ItemType Directory -Force -Path $tools | Out-Null
$url = 'https://github.com/k3d-io/k3d/releases/latest/download/k3d-windows-amd64.exe'
$out = Join-Path $tools 'k3d.exe'

try {
    Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing -ErrorAction Stop
    Write-Host "Downloaded k3d to $out"
} catch {
    Write-Error "Failed to download k3d: $_"
    exit 1
}

try {
    $envPath=[Environment]::GetEnvironmentVariable('Path',[EnvironmentVariableTarget]::Machine)
    if ($envPath -notlike "*$tools*") {
        [Environment]::SetEnvironmentVariable('Path', $envPath + ';' + $tools,[EnvironmentVariableTarget]::Machine)
        Write-Host "Added $tools to machine PATH (may require new shell to take effect)."
    } else {
        Write-Host "$tools already in PATH"
    }
} catch {
    Write-Warning "Could not update machine PATH automatically. You may need to add $tools to your PATH manually."
}

Write-Host "k3d installation step completed. Please open a new shell and run 'k3d version' to verify."