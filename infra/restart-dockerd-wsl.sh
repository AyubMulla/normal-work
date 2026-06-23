#!/usr/bin/env bash
set -e
# Kill existing dockerd processes if any
pids=$(pgrep -f dockerd || true)
if [ -n "$pids" ]; then
  echo "Found dockerd pids: $pids"
  sudo kill -9 $pids || true
  sleep 1
fi

# start dockerd
sudo nohup dockerd > /tmp/dockerd.log 2>&1 &
sleep 5
sudo tail -n 200 /tmp/dockerd.log || true

echo "Now checking docker info (may require a few seconds)"
docker info || true
