#!/usr/bin/env bash
set -euo pipefail

# Convenience runner: simulate a failure and open the generated RCA
./simulate_failure.sh "$@"

echo
echo "RCA summary (tail):"
tail -n 60 rca_report.md || true
