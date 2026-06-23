#!/usr/bin/env bash
set -euo pipefail

# Build and push helper that is resilient to WSL path quirks and docker socket
# usage: ./build-and-push.sh [registry_host:port] [image] [tag]

REGISTRY_ARG=${1:-}
IMAGE=${2:-sample-app}
TAG=${3:-latest}

# Determine repository root (one level up from infra/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Detect registry from k3d if not explicitly provided
if [ -z "$REGISTRY_ARG" ]; then
	if command -v k3d >/dev/null 2>&1; then
		REG=$(k3d registry list 2>/dev/null | awk '/k3d-lab-registry/ {print $4; exit}') || true
		if [ -n "$REG" ]; then
			REGISTRY_ARG=$REG
		fi
	fi
fi

# Fallback default
: "${REGISTRY_ARG:=localhost:5000}"

FULL="$REGISTRY_ARG/$IMAGE:$TAG"

echo "Repo root: $REPO_ROOT"
echo "Building image: $FULL"

DOCKER_CMD=docker
if ! $DOCKER_CMD info >/dev/null 2>&1; then
	echo "docker CLI cannot reach daemon as current user; trying sudo docker..."
	if sudo -n true 2>/dev/null; then
		DOCKER_CMD="sudo docker"
	else
		echo "Note: you may need to run this script with sudo or fix /var/run/docker.sock permissions. Trying sudo interactively..."
		DOCKER_CMD="sudo docker"
	fi
fi

# Build using the sample-app directory in the repo root so parentheses in C:\ paths don't leak into WSL quoting
$DOCKER_CMD build -t "$FULL" -f "$REPO_ROOT/sample-app/Dockerfile" "$REPO_ROOT/sample-app"

echo "Pushing $FULL"
$DOCKER_CMD push "$FULL"

echo "Image pushed: $FULL"
