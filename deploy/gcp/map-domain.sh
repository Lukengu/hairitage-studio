#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Cloud Run domain mapping is NOT supported in africa-south1."
echo "Using Application Load Balancer instead..."
echo ""

exec bash "${SCRIPT_DIR}/setup-alb.sh"
