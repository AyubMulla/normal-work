# Download Docker Desktop installer to C:\tools and launch it
$tools = 'C:\tools'
New-Item -ItemType Directory -Force -Path $tools | Out-Null

$url = 'https://desktop.docker.com/win/stable/amd64/Docker%20Desktop%20Installer.exe'
$out = Join-Path $tools 'DockerDesktopInstaller.exe'

Write-Host "Downloading Docker Desktop installer to $out"
try {
    Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing -ErrorAction Stop
    Write-Host "Downloaded installer to $out"
} catch {
    Write-Error "Failed to download Docker Desktop installer: $_"
    exit 1
}

Write-Host "Launching Docker Desktop installer. This may prompt for UAC and require interactive approval."
try {
    # Launch installer without elevation (user requested non-admin install). This may fail if elevation is actually required.
    Start-Process -FilePath $out -ArgumentList 'install','--quiet' -Wait -PassThru | Out-Null
    Write-Host "Installer launched (non-elevated). Complete installation interactively if prompted. After install, start Docker Desktop and re-run infra\bootstrap-k3d.ps1."
} catch {
    Write-Error "Failed to launch installer: $_"
    exit 1
}
