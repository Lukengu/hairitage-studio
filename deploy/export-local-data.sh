#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

FIXTURE_DIR="${REPO_ROOT}/app/fixtures"
FIXTURE_FILE="${FIXTURE_DIR}/site_content.json"

if ! docker compose ps --status running web >/dev/null 2>&1; then
  echo "Start the local stack first: docker compose up -d"
  exit 1
fi

mkdir -p "${FIXTURE_DIR}"

echo "==> Exporting site content from local database"
docker compose exec -T web python manage.py dumpdata \
  configuration \
  work \
  blog \
  product \
  legal \
  --natural-foreign \
  --natural-primary \
  --indent 2 \
  --output "fixtures/site_content.json"

echo ""
echo "Exported: ${FIXTURE_FILE}"
echo "Media files (sync separately): ${REPO_ROOT}/app/media/"
echo ""
echo "Next:"
echo "  git add app/fixtures/site_content.json"
echo "  bash deploy/gcp/import-data.sh"
