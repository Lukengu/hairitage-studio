#!/usr/bin/env bash
# Apply SMTP env vars (and optional secret) to Cloud Run without rebuilding the image.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.sh"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Missing ${CONFIG_FILE}. Copy deploy/gcp/config.example.sh to deploy/gcp/config.sh first."
  exit 1
fi

# shellcheck source=config.sh
source "$CONFIG_FILE"

: "${GCP_PROJECT:?}"
: "${GCP_REGION:?}"
: "${CLOUD_RUN_SERVICE:?}"

if [[ -z "${EMAIL_HOST:-}" ]]; then
  echo "EMAIL_HOST is not set in config.sh. Add SMTP settings and retry."
  exit 1
fi

gcloud config set project "${GCP_PROJECT}"

ACTIVE_REVISION="$(gcloud run services describe "${CLOUD_RUN_SERVICE}" \
  --project="${GCP_PROJECT}" \
  --region="${GCP_REGION}" \
  --format='value(status.traffic[0].revisionName)')"
WORKING_IMAGE="$(gcloud run revisions describe "${ACTIVE_REVISION}" \
  --project="${GCP_PROJECT}" \
  --region="${GCP_REGION}" \
  --format='value(spec.containers[0].image)')"

EMAIL_HOST_USER="${EMAIL_HOST_USER:-info@hairitage-studio.co.za}"
EMAIL_PORT="${EMAIL_PORT:-465}"
EMAIL_USE_TLS="${EMAIL_USE_TLS:-False}"
EMAIL_USE_SSL="${EMAIL_USE_SSL:-True}"
DEFAULT_FROM_EMAIL="${DEFAULT_FROM_EMAIL:-info@hairitage-studio.co.za}"
DEFAULT_NO_REPLY_EMAIL="${DEFAULT_NO_REPLY_EMAIL:-Hairitage Studio <noreply@hairitage-studio.co.za>}"

UPDATE_ARGS=(
  run services update "${CLOUD_RUN_SERVICE}"
  --project="${GCP_PROJECT}"
  --region="${GCP_REGION}"
  --image="${WORKING_IMAGE}"
  --update-env-vars="^:^EMAIL_HOST=${EMAIL_HOST}:EMAIL_HOST_USER=${EMAIL_HOST_USER}:EMAIL_PORT=${EMAIL_PORT}:EMAIL_USE_TLS=${EMAIL_USE_TLS}:EMAIL_USE_SSL=${EMAIL_USE_SSL}:DEFAULT_FROM_EMAIL=${DEFAULT_FROM_EMAIL}:DEFAULT_NO_REPLY_EMAIL=${DEFAULT_NO_REPLY_EMAIL}"
  --quiet
)

if gcloud secrets describe email-smtp-password --project="${GCP_PROJECT}" >/dev/null 2>&1 \
  && gcloud secrets versions list email-smtp-password --project="${GCP_PROJECT}" --limit=1 --format='value(name)' 2>/dev/null | grep -q .; then
  UPDATE_ARGS+=(--update-secrets="EMAIL_HOST_PASSWORD=email-smtp-password:latest")
  echo "==> Updating ${CLOUD_RUN_SERVICE} email env + EMAIL_HOST_PASSWORD secret"
else
  echo "WARNING: Secret email-smtp-password has no version yet."
  echo "         Create and set your SMTP password first:"
  echo "           bash deploy/gcp/setup-infra.sh   # creates placeholder secret if missing"
  echo "           printf '%s' 'APP_PASSWORD' | gcloud secrets versions add email-smtp-password --data-file=-"
  echo "         Then re-run: bash deploy/gcp/update-email-env.sh"
  echo ""
  echo "==> Updating ${CLOUD_RUN_SERVICE} email env only (no password secret)"
fi

echo "==> Pinning image ${WORKING_IMAGE}"
gcloud "${UPDATE_ARGS[@]}"

echo ""
echo "Email env applied to ${CLOUD_RUN_SERVICE} (no image rebuild)."
echo "  EMAIL_HOST=${EMAIL_HOST}"
echo "  EMAIL_PORT=${EMAIL_PORT}"
echo "  EMAIL_USE_SSL=${EMAIL_USE_SSL}"
echo "  DEFAULT_FROM_EMAIL=${DEFAULT_FROM_EMAIL}"
