# Install kubectl to C:\tools and add to user PATH
$tools = 'C:\tools'
New-Item -ItemType Directory -Force -Path $tools | Out-Null

try {
    $version = (Invoke-RestMethod -Uri 'https://dl.k8s.io/release/stable.txt').Trim()
    $url = "https://dl.k8s.io/release/$version/bin/windows/amd64/kubectl.exe"
    $out = Join-Path $tools 'kubectl.exe'
    Write-Host "Downloading kubectl $version to $out"
    Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing -ErrorAction Stop
    Write-Host "Downloaded kubectl to $out"
    try { Unblock-File -Path $out -ErrorAction SilentlyContinue } catch {}
} catch {
    Write-Error "Failed to download kubectl: $_"
    exit 1
}

try {
    & $out version --client
} catch {
    Write-Warning "Could not run kubectl from $out; it may require PATH update or admin rights."
}

try {
    $userPath=[Environment]::GetEnvironmentVariable('Path','User')
    if ($userPath -notlike "*$tools*") {
        [Environment]::SetEnvironmentVariable('Path', $userPath + ';' + $tools,'User')
        Write-Host "Added $tools to user PATH. Open a new shell to use kubectl from PATH."
    } else {
        Write-Host "$tools already in user PATH"
    }
} catch {
    Write-Warning "Failed to update user PATH."
}
