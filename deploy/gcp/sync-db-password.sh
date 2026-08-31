#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.sh"

# shellcheck source=config.sh
source "${CONFIG_FILE}"

: "${GCP_PROJECT:?}"
: "${SQL_INSTANCE:?}"
: "${SQL_USER:?}"

echo "==> Syncing Cloud SQL password for ${SQL_USER} from Secret Manager"
gcloud config set project "${GCP_PROJECT}" >/dev/null

DB_PASSWORD="$(gcloud secrets versions access latest --secret=db-password | tr -d '\n\r')"

gcloud sql users set-password "${SQL_USER}" \
  --instance="${SQL_INSTANCE}" \
  --password="${DB_PASSWORD}"

echo "==> Password synced for ${SQL_USER}@${SQL_INSTANCE}"

if [[ -n "${CLOUD_RUN_SERVICE:-}" && -n "${GCP_REGION:-}" ]]; then
  echo "==> Restarting Cloud Run service ${CLOUD_RUN_SERVICE} to pick up DB access"
  gcloud run services update "${CLOUD_RUN_SERVICE}" \
    --region="${GCP_REGION}" \
    --project="${GCP_PROJECT}" \
    --update-secrets="SQL_PASSWORD=db-password:latest" \
    --quiet
fi

echo "Done. Test with: gcloud run services proxy ${CLOUD_RUN_SERVICE:-hairitage-web} --region=${GCP_REGION:-africa-south1}"
