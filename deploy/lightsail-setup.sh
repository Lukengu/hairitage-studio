#!/usr/bin/env bash
set -euo pipefail

if ! command -v docker >/dev/null 2>&1; then
  echo "==> Installing Docker..."
  curl -fsSL https://get.docker.com | sh
  usermod -aG docker "${SUDO_USER:-ubuntu}" || true
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "Docker Compose plugin is required. Re-run after Docker install or log out and back in."
  exit 1
fi

echo "==> Docker is ready."
docker --version
docker compose version

echo ""
echo "Next steps:"
echo "  1. Clone the repo into this instance"
echo "  2. Edit .env.production and .env.db.production with strong secrets"
echo "  3. docker compose -f docker-compose.prod.yml up -d --build"
echo "  4. Point DNS A record to this instance's static IP"
echo "  5. bash deploy/init-ssl.sh"
