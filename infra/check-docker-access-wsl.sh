#!/usr/bin/env bash
set -euo pipefail

echo "Checking docker access via newgrp docker (temporary group change)"
newgrp docker <<'EOD'
docker version --format "Client: {{.Client.Version}}\nServer: {{.Server.Version}}" || true
EOD

echo "Also showing docker info (as root) for reference:"
sudo docker info || true
