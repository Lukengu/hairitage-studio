#!/usr/bin/env bash
# Apply Cloudflare Turnstile env vars to Cloud Run without rebuilding the image.
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

if [[ -z "${TURNSTILE_SITE_KEY:-}" ]]; then
  echo "TURNSTILE_SITE_KEY is not set in config.sh."
  echo "Get it from Cloudflare Dashboard → Turnstile → your widget → Site Key"
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

UPDATE_ARGS=(
  run services update "${CLOUD_RUN_SERVICE}"
  --project="${GCP_PROJECT}"
  --region="${GCP_REGION}"
  --image="${WORKING_IMAGE}"
  --update-env-vars="TURNSTILE_SITE_KEY=${TURNSTILE_SITE_KEY}"
  --quiet
)

if gcloud secrets describe turnstile-secret-key --project="${GCP_PROJECT}" >/dev/null 2>&1 \
  && gcloud secrets versions list turnstile-secret-key --project="${GCP_PROJECT}" --limit=1 --format='value(name)' 2>/dev/null | grep -q .; then
  UPDATE_ARGS+=(--update-secrets="TURNSTILE_SECRET_KEY=turnstile-secret-key:latest")
  echo "==> Updating ${CLOUD_RUN_SERVICE} Turnstile site key + secret"
else
  echo "WARNING: Secret turnstile-secret-key not found."
  echo "         Create it:"
  echo "           printf '%s' 'YOUR_SECRET_KEY' | gcloud secrets create turnstile-secret-key --data-file=- --project=${GCP_PROJECT}"
  echo "         Then re-run: bash deploy/gcp/update-turnstile-env.sh"
  echo ""
  echo "==> Updating ${CLOUD_RUN_SERVICE} Turnstile site key only"
fi

gcloud "${UPDATE_ARGS[@]}"

echo ""
echo "Turnstile env applied to ${CLOUD_RUN_SERVICE}."
echo "  TURNSTILE_SITE_KEY=${TURNSTILE_SITE_KEY}"
echo ""
echo "Redeploy the app image if the contact form template changed:"
echo "  bash deploy/gcp/deploy.sh"
