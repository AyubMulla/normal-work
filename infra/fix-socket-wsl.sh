#!/usr/bin/env bash
set -euo pipefail

echo "Fixing docker socket permissions and restarting daemon"
sudo groupadd -f docker
sudo usermod -aG docker $USER || true
echo "Killing any existing dockerd processes"
sudo pkill -f dockerd || true
sudo rm -f /var/run/docker.pid || true
echo "Starting dockerd in background (logs -> /tmp/dockerd.log)"
sudo nohup dockerd > /tmp/dockerd.log 2>&1 &
sleep 5
echo "Adjusting socket permissions"
sudo chown root:docker /var/run/docker.sock || true
sudo chmod 660 /var/run/docker.sock || true
echo "Tail dockerd log:"
sudo tail -n 200 /tmp/dockerd.log || true
echo "docker version (client/server):"
docker version || true
