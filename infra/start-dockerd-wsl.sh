#!/usr/bin/env bash
set -e
sudo nohup dockerd > /tmp/dockerd.log 2>&1 &
sleep 5
sudo tail -n 200 /tmp/dockerd.log || true
