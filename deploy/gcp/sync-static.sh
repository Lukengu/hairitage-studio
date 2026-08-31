#!/usr/bin/env bash
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
: "${GCS_BUCKET:?}"
: "${CLOUD_RUN_SERVICE:?}"
: "${SERVICE_ACCOUNT:?}"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ARTIFACT_REPO="cloud-run-source-deploy"
IMAGE="${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT}/${ARTIFACT_REPO}/${CLOUD_RUN_SERVICE}:latest"
GCS_PUBLIC_BUCKET="${GCS_PUBLIC_BUCKET:-0}"

gcloud config set project "${GCP_PROJECT}"

# shellcheck source=ensure-build-sa.sh
source "${SCRIPT_DIR}/ensure-build-sa.sh"
ensure_build_service_account

echo "==> Uploading static files to gs://${GCS_BUCKET}/static/"
gcloud builds submit "${REPO_ROOT}/app" \
  --config="${REPO_ROOT}/app/cloudbuild.yaml" \
  --substitutions=_IMAGE="${IMAGE}" \
  --service-account="${BUILD_SA_RESOURCE}"

echo ""
echo "Static sync complete."
echo "  Bucket prefix: gs://${GCS_BUCKET}/static/"
echo "  Public URL: https://${DOMAIN:-your-domain}/static/ (via ALB backend bucket)"
