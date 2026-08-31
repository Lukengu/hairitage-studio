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
: "${ADMIN_EMAIL:?}"

SA_EMAIL="${SERVICE_ACCOUNT}@${GCP_PROJECT}.iam.gserviceaccount.com"
CONNECTION_NAME="${GCP_PROJECT}:${GCP_REGION}:${SQL_INSTANCE}"
IMAGE="${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT}/cloud-run-source-deploy/${CLOUD_RUN_SERVICE}:latest"
JOB_NAME="hairitage-createsuperuser"

ADMIN_USERNAME="${ADMIN_USERNAME:-admin}"
SECRET_NAME="admin-password"

if ! gcloud secrets describe "${SECRET_NAME}" --project="${GCP_PROJECT}" >/dev/null 2>&1; then
  echo "==> Creating ${SECRET_NAME} secret"
  python3 - <<'PY' | gcloud secrets create "${SECRET_NAME}" --project="${GCP_PROJECT}" --data-file=-
import secrets
print(secrets.token_urlsafe(16), end='')
PY
fi

ADMIN_PASSWORD="$(gcloud secrets versions access latest --secret="${SECRET_NAME}" --project="${GCP_PROJECT}")"

ENV_FILE="$(mktemp "${TMPDIR:-/tmp}/createsuperuser-env.XXXXXX.yaml")"
trap 'rm -f "${ENV_FILE}"' EXIT

cat > "${ENV_FILE}" <<EOF
DEBUG: "0"
DATABASE: "postgres"
SQL_ENGINE: "django.db.backends.postgresql"
SQL_DATABASE: "${SQL_DATABASE}"
SQL_USER: "${SQL_USER}"
CLOUD_SQL_CONNECTION_NAME: "${CONNECTION_NAME}"
DJANGO_ALLOWED_HOSTS: "localhost"
DJANGO_SUPERUSER_USERNAME: "${ADMIN_USERNAME}"
DJANGO_SUPERUSER_EMAIL: "${ADMIN_EMAIL}"
DJANGO_SUPERUSER_PASSWORD: "${ADMIN_PASSWORD}"
EOF

gcloud config set project "${GCP_PROJECT}" >/dev/null

echo "==> Deploying admin user job ${JOB_NAME}"
gcloud run jobs deploy "${JOB_NAME}" \
  --image="${IMAGE}" \
  --region="${GCP_REGION}" \
  --service-account="${SA_EMAIL}" \
  --set-cloudsql-instances="${CONNECTION_NAME}" \
  --env-vars-file="${ENV_FILE}" \
  --set-secrets="SQL_PASSWORD=db-password:latest,SECRET_KEY=django-secret-key:latest" \
  --command=python \
  --args=manage.py,createsuperuser,--noinput \
  --max-retries=0 \
  --task-timeout=600 \
  --quiet

echo "==> Creating Django admin user (skips if ${ADMIN_USERNAME} already exists)"
gcloud run jobs execute "${JOB_NAME}" \
  --region="${GCP_REGION}" \
  --wait || true

echo ""
echo "Admin login:"
echo "  URL:      https://${DOMAIN}/admin/"
echo "  Username: ${ADMIN_USERNAME}"
echo "  Email:    ${ADMIN_EMAIL}"
echo "  Password: stored in Secret Manager secret ${SECRET_NAME}"
echo ""
echo "Retrieve password:"
echo "  gcloud secrets versions access latest --secret=${SECRET_NAME} --project=${GCP_PROJECT}"
