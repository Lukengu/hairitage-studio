#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.sh"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Missing ${CONFIG_FILE}. Copy deploy/gcp/config.example.sh to deploy/gcp/config.sh first."
  exit 1
fi

# shellcheck source=config.sh
source "$CONFIG_FILE"

: "${GCP_PROJECT:?}"
: "${GCP_REGION:?}"
: "${GCS_BUCKET:?}"
: "${SQL_INSTANCE:?}"
: "${SQL_DATABASE:?}"
: "${SQL_USER:?}"
: "${CLOUD_RUN_SERVICE:?}"
: "${SERVICE_ACCOUNT:?}"
: "${DOMAIN:?}"

SA_EMAIL="${SERVICE_ACCOUNT}@${GCP_PROJECT}.iam.gserviceaccount.com"
CONNECTION_NAME="${GCP_PROJECT}:${GCP_REGION}:${SQL_INSTANCE}"
ARTIFACT_REPO="cloud-run-source-deploy"
IMAGE="${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT}/${ARTIFACT_REPO}/${CLOUD_RUN_SERVICE}:latest"

COLLECT_STATIC="${COLLECT_STATIC:-1}"
GCS_PUBLIC_BUCKET="${GCS_PUBLIC_BUCKET:-0}"
USE_ALB="${USE_ALB:-1}"

ENV_FILE="$(mktemp "${TMPDIR:-/tmp}/cloudrun-env-XXXXXX").yaml"
trap 'rm -f "${ENV_FILE}"' EXIT

cat > "${ENV_FILE}" <<EOF
DEBUG: "0"
DATABASE: "postgres"
SQL_ENGINE: "django.db.backends.postgresql"
SQL_DATABASE: "${SQL_DATABASE}"
SQL_USER: "${SQL_USER}"
CLOUD_SQL_CONNECTION_NAME: "${CONNECTION_NAME}"
GS_BUCKET_NAME: "${GCS_BUCKET}"
GCS_PUBLIC_BUCKET: "${GCS_PUBLIC_BUCKET}"
DJANGO_ALLOWED_HOSTS: "${DOMAIN},www.${DOMAIN},.run.app"
COLLECT_STATIC: "${COLLECT_STATIC}"
EOF

if [[ -n "${CSRF_TRUSTED_ORIGINS_EXTRA:-}" ]]; then
  echo "CSRF_TRUSTED_ORIGINS_EXTRA: \"${CSRF_TRUSTED_ORIGINS_EXTRA}\"" >> "${ENV_FILE}"
fi

if [[ -n "${EMAIL_HOST:-}" ]]; then
  cat >> "${ENV_FILE}" <<EOF
EMAIL_HOST: "${EMAIL_HOST}"
EMAIL_HOST_USER: "${EMAIL_HOST_USER:-info@hairitage-studio.co.za}"
EMAIL_PORT: "${EMAIL_PORT:-465}"
EMAIL_USE_TLS: "${EMAIL_USE_TLS:-False}"
EMAIL_USE_SSL: "${EMAIL_USE_SSL:-True}"
DEFAULT_FROM_EMAIL: "${DEFAULT_FROM_EMAIL:-info@hairitage-studio.co.za}"
DEFAULT_NO_REPLY_EMAIL: "${DEFAULT_NO_REPLY_EMAIL:-Hairitage Studio <noreply@hairitage-studio.co.za>}"
EOF
fi

if [[ -n "${TURNSTILE_SITE_KEY:-}" ]]; then
  echo "TURNSTILE_SITE_KEY: \"${TURNSTILE_SITE_KEY}\"" >> "${ENV_FILE}"
fi

if [[ -n "${GOOGLE_MAPS_API_KEY:-}" ]]; then
  echo "GOOGLE_MAPS_API_KEY: \"${GOOGLE_MAPS_API_KEY}\"" >> "${ENV_FILE}"
fi

SECRETS="SQL_PASSWORD=db-password:latest,SECRET_KEY=django-secret-key:latest"
if gcloud secrets describe email-smtp-password --project="${GCP_PROJECT}" >/dev/null 2>&1 \
  && gcloud secrets versions list email-smtp-password --project="${GCP_PROJECT}" --limit=1 --format='value(name)' 2>/dev/null | grep -q .; then
  SECRETS="${SECRETS},EMAIL_HOST_PASSWORD=email-smtp-password:latest"
else
  echo "WARNING: Secret email-smtp-password not found or has no version; EMAIL_HOST_PASSWORD will be unset."
  echo "         Create it: bash deploy/gcp/setup-infra.sh"
  echo "         Then set password: printf '%s' 'APP_PASSWORD' | gcloud secrets versions add email-smtp-password --data-file=-"
  echo "         Or apply without rebuild: bash deploy/gcp/update-email-env.sh"
fi

if gcloud secrets describe turnstile-secret-key --project="${GCP_PROJECT}" >/dev/null 2>&1 \
  && gcloud secrets versions list turnstile-secret-key --project="${GCP_PROJECT}" --limit=1 --format='value(name)' 2>/dev/null | grep -q .; then
  SECRETS="${SECRETS},TURNSTILE_SECRET_KEY=turnstile-secret-key:latest"
fi

gcloud config set project "${GCP_PROJECT}"

# shellcheck source=ensure-build-sa.sh
source "${SCRIPT_DIR}/ensure-build-sa.sh"
ensure_build_service_account

echo "==> Building image ${IMAGE} (service account: ${BUILD_SA_EMAIL})"
gcloud builds submit "${REPO_ROOT}/app" \
  --config="${REPO_ROOT}/app/cloudbuild.yaml" \
  --substitutions=_IMAGE="${IMAGE}" \
  --service-account="${BUILD_SA_RESOURCE}"

echo "==> Deploying ${CLOUD_RUN_SERVICE} to ${GCP_REGION}"
gcloud run deploy "${CLOUD_RUN_SERVICE}" \
  --project="${GCP_PROJECT}" \
  --image="${IMAGE}" \
  --region="${GCP_REGION}" \
  --platform=managed \
  --service-account="${SA_EMAIL}" \
  --add-cloudsql-instances="${CONNECTION_NAME}" \
  --env-vars-file="${ENV_FILE}" \
  --set-secrets="${SECRETS}" \
  --memory=1Gi \
  --cpu=1 \
  --cpu-boost \
  --min-instances=0 \
  --max-instances=3 \
  --no-allow-unauthenticated

if [[ "${USE_ALB:-0}" == "1" ]]; then
  echo "==> ALB mode: restrict ingress and skip invoker IAM check"
  gcloud run services update "${CLOUD_RUN_SERVICE}" \
    --project="${GCP_PROJECT}" \
    --region="${GCP_REGION}" \
    --ingress=internal-and-cloud-load-balancing \
    --no-invoker-iam-check \
    --quiet
else
  echo "==> Allowing public web access"
  if ! gcloud run services add-iam-policy-binding "${CLOUD_RUN_SERVICE}" \
    --project="${GCP_PROJECT}" \
    --region="${GCP_REGION}" \
    --member="allUsers" \
    --role="roles/run.invoker" \
    --quiet >/dev/null 2>&1; then
    echo ""
    echo "WARNING: Could not grant public access (org policy may block allUsers)."
    echo "         Use the ALB route instead: bash deploy/gcp/setup-alb.sh"
    echo ""
  fi
fi

SERVICE_URL="$(gcloud run services describe "${CLOUD_RUN_SERVICE}" \
  --project="${GCP_PROJECT}" \
  --region="${GCP_REGION}" \
  --format='value(status.url)')"

echo ""
echo "Deployment complete."
echo "  Service URL: ${SERVICE_URL}"
echo ""
echo "Tips:"
echo "  Static files are served from Cloud Run at /static/ and copied to gs://${GCS_BUCKET}/static/."
echo "  Custom domain via ALB: bash deploy/gcp/setup-alb.sh (required in ${GCP_REGION})"
echo "  Add CSRF origin if testing the *.run.app URL:"
echo "    CSRF_TRUSTED_ORIGINS_EXTRA=${SERVICE_URL} COLLECT_STATIC=1 bash deploy/gcp/deploy.sh"
if [[ -n "${EMAIL_HOST:-}" ]] && ! gcloud secrets describe email-smtp-password --project="${GCP_PROJECT}" >/dev/null 2>&1; then
  echo "  Email: set SMTP token in Secret Manager secret email-smtp-password, then:"
  echo "    bash deploy/gcp/update-email-env.sh"
fi
