#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

for file in .env.local .env.db.local; do
  if [[ ! -f "${file}" ]]; then
    echo "Missing ${file}. Add it in the repo root before starting locally."
    exit 1
  fi
done

echo "==> Starting local stack (Postgres + Django + Nginx on http://localhost:1337)"
docker compose up -d --build

echo ""
echo "Local URLs:"
echo "  Site:    http://localhost:1337"
echo "  Adminer: http://localhost:7580"
echo ""
echo "Create an admin user:"
echo "  docker compose exec web python manage.py createsuperuser"
