#!/usr/bin/env bash
set -euo pipefail

# Install Docker Engine inside WSL Ubuntu.
# NOTE: In many setups it's preferable to use Docker Desktop WSL integration.
# This script attempts a standalone install and starts dockerd in background.

echo "Updating apt..."
sudo apt-get update -y

echo "Installing prerequisites..."
sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release

echo "Adding Docker GPG key and repo..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo \"deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable\" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
ARCH=$(dpkg --print-architecture)
DIST=$(lsb_release -cs)
sudo bash -c "cat > /etc/apt/sources.list.d/docker.list <<'EOF'
deb [arch=${ARCH} signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu ${DIST} stable
EOF"

sudo apt-get update -y

echo "Installing docker packages..."
sudo apt-get install -y docker-ce docker-ce-cli containerd.io

# Add current user to docker group
sudo groupadd -f docker
sudo usermod -aG docker $USER || true

# Try starting dockerd in background
echo "Attempting to start dockerd in background (logs -> /tmp/dockerd.log)"
if command -v dockerd >/dev/null 2>&1; then
  sudo nohup dockerd > /tmp/dockerd.log 2>&1 &
  sleep 3
  echo "Checking docker version and info..."
  if docker version >/dev/null 2>&1; then
    docker version
    docker info || true
    echo "Docker daemon appears running inside WSL."
    echo "Note: You may need to open a new shell to use docker as a non-root user."
  else
    echo "docker CLI not yet able to contact daemon. Check /tmp/dockerd.log for details."
    tail -n 50 /tmp/dockerd.log || true
  fi
else
  echo "dockerd not installed or not found in PATH"
fi

echo "If dockerd failed to run, consider enabling Docker Desktop WSL integration instead (recommended)."
