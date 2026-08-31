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
: "${SQL_INSTANCE:?}"
: "${SQL_DATABASE:?}"
: "${SQL_USER:?}"
: "${CLOUD_RUN_SERVICE:?}"
: "${SERVICE_ACCOUNT:?}"

SA_EMAIL="${SERVICE_ACCOUNT}@${GCP_PROJECT}.iam.gserviceaccount.com"
CONNECTION_NAME="${GCP_PROJECT}:${GCP_REGION}:${SQL_INSTANCE}"

grant_member_role() {
  local member="$1"
  local role="$2"
  echo "==> Granting ${role} to ${member}"
  for _ in $(seq 1 10); do
    if gcloud projects add-iam-policy-binding "${GCP_PROJECT}" \
      --member="${member}" \
      --role="${role}" \
      --quiet >/dev/null 2>&1; then
      return 0
    fi
    sleep 3
  done
  echo "ERROR: Failed to grant ${role} to ${member}"
  return 1
}

echo "==> Setting project ${GCP_PROJECT}"
gcloud config set project "${GCP_PROJECT}"

echo "==> Enabling required APIs"
gcloud services enable \
  run.googleapis.com \
  sqladmin.googleapis.com \
  storage.googleapis.com \
  artifactregistry.googleapis.com \
  secretmanager.googleapis.com \
  cloudbuild.googleapis.com

PROJECT_NUMBER="$(gcloud projects describe "${GCP_PROJECT}" --format='value(projectNumber)')"
CLOUDBUILD_SA="serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com"
COMPUTE_SA="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

echo "==> Granting Cloud Build permissions"
grant_member_role "${CLOUDBUILD_SA}" roles/storage.admin
grant_member_role "${CLOUDBUILD_SA}" roles/artifactregistry.writer
grant_member_role "${CLOUDBUILD_SA}" roles/logging.logWriter
grant_member_role "${CLOUDBUILD_SA}" roles/cloudbuild.builds.builder
grant_member_role "${COMPUTE_SA}" roles/storage.objectAdmin
grant_member_role "${COMPUTE_SA}" roles/artifactregistry.writer
grant_member_role "${COMPUTE_SA}" roles/logging.logWriter

# shellcheck source=ensure-build-sa.sh
source "${SCRIPT_DIR}/ensure-build-sa.sh"
ensure_build_service_account

if ! gcloud secrets describe django-secret-key >/dev/null 2>&1; then
  echo "==> Creating django-secret-key secret"
  python3 - <<'PY' | gcloud secrets create django-secret-key --data-file=-
import secrets
print(secrets.token_urlsafe(50), end='')
PY
else
  echo "==> Secret django-secret-key already exists"
fi

if ! gcloud secrets describe db-password >/dev/null 2>&1; then
  echo "==> Creating db-password secret"
  python3 - <<'PY' | gcloud secrets create db-password --data-file=-
import secrets
print(secrets.token_urlsafe(24), end='')
PY
else
  echo "==> Secret db-password already exists"
fi

if ! gcloud secrets describe email-smtp-password >/dev/null 2>&1; then
  echo "==> Creating email-smtp-password secret placeholder"
  gcloud secrets create email-smtp-password --replication-policy=automatic
  echo -n 'unset' | gcloud secrets versions add email-smtp-password --data-file=-
  echo "    Set your Gmail app password:"
  echo "      printf '%s' 'APP_PASSWORD' | gcloud secrets versions add email-smtp-password --data-file=-"
else
  echo "==> Secret email-smtp-password already exists"
fi

if ! gcloud storage buckets describe "gs://${GCS_BUCKET}" >/dev/null 2>&1; then
  echo "==> Creating GCS bucket gs://${GCS_BUCKET}"
  gcloud storage buckets create "gs://${GCS_BUCKET}" --location="${GCP_REGION}"
  gcloud storage buckets update "gs://${GCS_BUCKET}" --uniform-bucket-level-access
else
  echo "==> Bucket gs://${GCS_BUCKET} already exists"
fi

GCS_PUBLIC_BUCKET="${GCS_PUBLIC_BUCKET:-1}"
if [[ "${GCS_PUBLIC_BUCKET}" == "1" ]]; then
  echo "==> Granting public read on gs://${GCS_BUCKET}"
  if gcloud storage buckets add-iam-policy-binding "gs://${GCS_BUCKET}" \
    --member=allUsers \
    --role=roles/storage.objectViewer >/dev/null 2>&1; then
    echo "==> Public bucket access enabled"
  else
    echo ""
    echo "WARNING: Could not grant public read (org policy often blocks allUsers)."
    echo "         Set GCS_PUBLIC_BUCKET=0 in deploy/gcp/config.sh and redeploy."
    echo "         Static files will be served from Cloud Run; media stays on private GCS."
    echo ""
  fi
else
  echo "==> Skipping public bucket access (GCS_PUBLIC_BUCKET=0)"
  PROJECT_NUMBER="$(gcloud projects describe "${GCP_PROJECT}" --format='value(projectNumber)')"
  CLOUD_SERVICES_SA="${PROJECT_NUMBER}@cloudservices.gserviceaccount.com"
  echo "==> Granting load balancer read access to gs://${GCS_BUCKET}"
  gcloud storage buckets add-iam-policy-binding "gs://${GCS_BUCKET}" \
    --member="serviceAccount:${CLOUD_SERVICES_SA}" \
    --role="roles/storage.objectViewer" \
    --quiet >/dev/null 2>&1 || \
    echo "    (bucket IAM binding may already exist)"
fi

if ! gcloud sql instances describe "${SQL_INSTANCE}" >/dev/null 2>&1; then
  DB_PASSWORD="$(gcloud secrets versions access latest --secret=db-password)"
  echo "==> Creating Cloud SQL instance ${SQL_INSTANCE}"
  gcloud sql instances create "${SQL_INSTANCE}" \
    --database-version=POSTGRES_15 \
    --tier=db-f1-micro \
    --region="${GCP_REGION}" \
    --storage-size=10GB \
    --storage-type=SSD \
    --backup-start-time=03:00 \
    --root-password="${DB_PASSWORD}"
else
  echo "==> Cloud SQL instance ${SQL_INSTANCE} already exists"
fi

if ! gcloud sql databases describe "${SQL_DATABASE}" --instance="${SQL_INSTANCE}" >/dev/null 2>&1; then
  echo "==> Creating database ${SQL_DATABASE}"
  gcloud sql databases create "${SQL_DATABASE}" --instance="${SQL_INSTANCE}"
fi

DB_PASSWORD="$(gcloud secrets versions access latest --secret=db-password)"
if ! gcloud sql users list --instance="${SQL_INSTANCE}" --format='value(name)' | grep -qx "${SQL_USER}"; then
  echo "==> Creating database user ${SQL_USER}"
  gcloud sql users create "${SQL_USER}" \
    --instance="${SQL_INSTANCE}" \
    --password="${DB_PASSWORD}"
else
  echo "==> Syncing password for database user ${SQL_USER}"
  gcloud sql users set-password "${SQL_USER}" \
    --instance="${SQL_INSTANCE}" \
    --password="${DB_PASSWORD}"
fi

if ! gcloud iam service-accounts describe "${SA_EMAIL}" >/dev/null 2>&1; then
  echo "==> Creating service account ${SA_EMAIL}"
  gcloud iam service-accounts create "${SERVICE_ACCOUNT}" \
    --display-name="Hairitage Cloud Run"
fi

echo "==> Waiting for service account to become available..."
for _ in $(seq 1 30); do
  if gcloud iam service-accounts describe "${SA_EMAIL}" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

grant_member_role "serviceAccount:${SA_EMAIL}" roles/cloudsql.client
grant_member_role "serviceAccount:${SA_EMAIL}" roles/storage.objectAdmin
grant_member_role "serviceAccount:${SA_EMAIL}" roles/secretmanager.secretAccessor

echo ""
echo "Infrastructure ready."
echo "  Cloud SQL connection: ${CONNECTION_NAME}"
echo "  GCS bucket: gs://${GCS_BUCKET}"
echo ""
echo "Email (optional):"
echo "  1. Set Gmail app password: printf '%s' 'APP_PASSWORD' | gcloud secrets versions add email-smtp-password --data-file=-"
echo "  2. Apply to Cloud Run (no rebuild): bash deploy/gcp/update-email-env.sh"
echo ""
echo "Next: bash deploy/gcp/deploy.sh"
