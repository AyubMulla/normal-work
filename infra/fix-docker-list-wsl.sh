#!/usr/bin/env bash
set -e
ARCH=$(dpkg --print-architecture)
DIST=$(lsb_release -cs)
sudo bash -c "cat > /etc/apt/sources.list.d/docker.list <<'EOF'
deb [arch=${ARCH} signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu ${DIST} stable
EOF"
echo "Wrote /etc/apt/sources.list.d/docker.list:"
sudo cat /etc/apt/sources.list.d/docker.list
