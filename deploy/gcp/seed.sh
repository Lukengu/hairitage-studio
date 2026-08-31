#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.sh"

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

SA_EMAIL="${SERVICE_ACCOUNT}@${GCP_PROJECT}.iam.gserviceaccount.com"
CONNECTION_NAME="${GCP_PROJECT}:${GCP_REGION}:${SQL_INSTANCE}"
IMAGE="${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT}/cloud-run-source-deploy/${CLOUD_RUN_SERVICE}:latest"
JOB_NAME="hairitage-seed"
SEED_ARGS="manage.py,seed_site"
if [[ "${FORCE:-0}" == "1" ]]; then
  SEED_ARGS="manage.py,seed_site,--force"
fi

ENV_FILE="$(mktemp "${TMPDIR:-/tmp}/seed-env.XXXXXX.yaml")"
trap 'rm -f "${ENV_FILE}"' EXIT

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

echo "==> Deploying seed job ${JOB_NAME}"
gcloud run jobs deploy "${JOB_NAME}" \
  --image="${IMAGE}" \
  --region="${GCP_REGION}" \
  --service-account="${SA_EMAIL}" \
  --set-cloudsql-instances="${CONNECTION_NAME}" \
  --env-vars-file="${ENV_FILE}" \
  --set-secrets="SQL_PASSWORD=db-password:latest,SECRET_KEY=django-secret-key:latest" \
  --command=python \
  --args="${SEED_ARGS}" \
  --max-retries=0 \
  --task-timeout=600 \
  --quiet

echo "==> Loading starter site content"
gcloud run jobs execute "${JOB_NAME}" \
  --region="${GCP_REGION}" \
  --wait

echo ""
echo "Seed complete. Review the site at https://${DOMAIN}/"
