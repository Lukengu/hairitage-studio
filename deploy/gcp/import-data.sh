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
: "${SQL_DATABASE:?}"
: "${SQL_USER:?}"
: "${CLOUD_RUN_SERVICE:?}"
: "${SERVICE_ACCOUNT:?}"
: "${GCS_BUCKET:?}"

FLUSH="${FLUSH:-1}"
SYNC_MEDIA="${SYNC_MEDIA:-1}"
DEPLOY="${DEPLOY:-0}"

if [[ ! -f "${REPO_ROOT}/app/common/management/commands/import_site_data.py" ]]; then
  echo "Missing import_site_data management command in app/common/management/commands/"
  exit 1
fi

SA_EMAIL="${SERVICE_ACCOUNT}@${GCP_PROJECT}.iam.gserviceaccount.com"
CONNECTION_NAME="${GCP_PROJECT}:${GCP_REGION}:${SQL_INSTANCE}"
IMAGE="${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT}/cloud-run-source-deploy/${CLOUD_RUN_SERVICE}:latest"
JOB_NAME="hairitage-import-data"

if [[ ! -f "${REPO_ROOT}/app/fixtures/site_content.json" ]]; then
  echo "Missing app/fixtures/site_content.json"
  echo "Run: bash deploy/export-local-data.sh"
  exit 1
fi

ENV_FILE="$(mktemp "${TMPDIR:-/tmp}/import-data-env.XXXXXX.yaml")"
trap 'rm -f "${ENV_FILE}"' EXIT

IMPORT_ARGS="manage.py,import_site_data"
if [[ "${FLUSH}" == "1" ]]; then
  IMPORT_ARGS="manage.py,import_site_data,--flush"
fi

cat > "${ENV_FILE}" <<EOF
DEBUG: "0"
DATABASE: "postgres"
SQL_ENGINE: "django.db.backends.postgresql"
SQL_DATABASE: "${SQL_DATABASE}"
SQL_USER: "${SQL_USER}"
CLOUD_SQL_CONNECTION_NAME: "${CONNECTION_NAME}"
GS_BUCKET_NAME: "${GCS_BUCKET}"
GCS_PUBLIC_BUCKET: "${GCS_PUBLIC_BUCKET:-0}"
DJANGO_ALLOWED_HOSTS: "localhost"
EOF

gcloud config set project "${GCP_PROJECT}" >/dev/null

if [[ "${DEPLOY}" == "1" ]]; then
  echo "==> Building and deploying latest app image (includes fixture + import command)"
  bash "${SCRIPT_DIR}/deploy.sh"
fi

echo ""
echo "Note: import_site_data must exist in the Cloud Run image."
echo "If the job fails with 'Unknown command: import_site_data', run:"
echo "  DEPLOY=1 bash deploy/gcp/import-data.sh"
echo "  # or: bash deploy/gcp/deploy.sh && bash deploy/gcp/import-data.sh"
echo ""

echo "==> Deploying import job ${JOB_NAME}"
gcloud run jobs deploy "${JOB_NAME}" \
  --image="${IMAGE}" \
  --region="${GCP_REGION}" \
  --service-account="${SA_EMAIL}" \
  --set-cloudsql-instances="${CONNECTION_NAME}" \
  --env-vars-file="${ENV_FILE}" \
  --set-secrets="SQL_PASSWORD=db-password:latest,SECRET_KEY=django-secret-key:latest" \
  --command=python \
  --args="${IMPORT_ARGS}" \
  --max-retries=0 \
  --task-timeout=900 \
  --quiet

echo "==> Importing site content fixture"
gcloud run jobs execute "${JOB_NAME}" \
  --region="${GCP_REGION}" \
  --wait

if [[ "${SYNC_MEDIA}" == "1" && -d "${REPO_ROOT}/app/media" ]]; then
  echo "==> Syncing local media to gs://${GCS_BUCKET}/media/"
  gcloud storage rsync -r "${REPO_ROOT}/app/media" "gs://${GCS_BUCKET}/media"
else
  echo "==> Skipping media sync (SYNC_MEDIA=${SYNC_MEDIA})"
fi

echo ""
echo "Import complete. Review: https://${DOMAIN}/"
