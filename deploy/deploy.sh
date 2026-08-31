#!/usr/bin/env bash
set -euo pipefail

COMPOSE="docker compose -f docker-compose.prod.yml"

echo "==> Pulling latest code..."
git pull --ff-only

echo "==> Building and starting services..."
$COMPOSE up -d --build

echo "==> Deployment complete."
$COMPOSE ps
