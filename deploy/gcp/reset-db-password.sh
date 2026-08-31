#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=config.sh
source "${CONFIG_FILE}"

: "${GCP_PROJECT:?}"
: "${GCP_REGION:?}"
: "${SQL_INSTANCE:?}"
: "${SQL_USER:?}"

PASSWORD="${1:-}"

if [[ -z "${PASSWORD}" && -f "${REPO_ROOT}/.env.production" ]]; then
  PASSWORD="$(grep '^SQL_PASSWORD=' "${REPO_ROOT}/.env.production" | cut -d= -f2- | tr -d '\r')"
fi

if [[ -z "${PASSWORD}" ]]; then
  PASSWORD="$(python3 -c "import secrets; print(secrets.token_urlsafe(24), end='')")"
  echo "Generated a new password."
fi

echo "==> Updating Secret Manager (db-password)"
printf '%s' "${PASSWORD}" | gcloud secrets versions add db-password \
  --project="${GCP_PROJECT}" \
  --data-file=-

echo "==> Updating Cloud SQL user ${SQL_USER}"
gcloud sql users set-password "${SQL_USER}" \
  --instance="${SQL_INSTANCE}" \
  --project="${GCP_PROJECT}" \
  --password="${PASSWORD}"

if [[ -n "${CLOUD_RUN_SERVICE:-}" ]]; then
  echo "==> Restarting Cloud Run service ${CLOUD_RUN_SERVICE}"
  gcloud run services update "${CLOUD_RUN_SERVICE}" \
    --region="${GCP_REGION}" \
    --project="${GCP_PROJECT}" \
    --update-secrets="SQL_PASSWORD=db-password:latest" \
    --quiet
fi

echo ""
echo "Done. Secret Manager, Cloud SQL, and Cloud Run now use the same password."
echo "Test: gcloud run services proxy ${CLOUD_RUN_SERVICE:-hairitage-web} --region=${GCP_REGION}"
