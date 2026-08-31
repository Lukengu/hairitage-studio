#!/usr/bin/env bash
# Shared setup for the Cloud Build service account.
# Source from setup-infra.sh and deploy.sh.

ensure_build_service_account() {
  : "${GCP_PROJECT:?}"
  : "${GCP_REGION:?}"

  local build_sa_name="${BUILD_SERVICE_ACCOUNT:-hairitage-build}"
  local artifact_repo="${ARTIFACT_REPO:-cloud-run-source-deploy}"
  local build_sa_email="${build_sa_name}@${GCP_PROJECT}.iam.gserviceaccount.com"
  local project_number
  project_number="$(gcloud projects describe "${GCP_PROJECT}" --format='value(projectNumber)')"
  local cloudbuild_sa="serviceAccount:${project_number}@cloudbuild.gserviceaccount.com"

  if ! gcloud iam service-accounts describe "${build_sa_email}" >/dev/null 2>&1; then
    echo "==> Creating build service account ${build_sa_email}"
    gcloud iam service-accounts create "${build_sa_name}" \
      --display-name="Hairitage Cloud Build"
  fi

  for _ in $(seq 1 30); do
    if gcloud iam service-accounts describe "${build_sa_email}" >/dev/null 2>&1; then
      break
    fi
    sleep 2
  done

  local role
  for role in \
    roles/storage.admin \
    roles/artifactregistry.writer \
    roles/logging.logWriter \
    roles/cloudbuild.builds.builder; do
    for _ in $(seq 1 5); do
      if gcloud projects add-iam-policy-binding "${GCP_PROJECT}" \
        --member="serviceAccount:${build_sa_email}" \
        --role="${role}" \
        --quiet >/dev/null 2>&1; then
        break
      fi
      sleep 2
    done
  done

  if ! gcloud artifacts repositories describe "${artifact_repo}" \
    --location="${GCP_REGION}" >/dev/null 2>&1; then
    gcloud artifacts repositories create "${artifact_repo}" \
      --repository-format=docker \
      --location="${GCP_REGION}"
  fi

  for _ in $(seq 1 5); do
    if gcloud artifacts repositories add-iam-policy-binding "${artifact_repo}" \
      --location="${GCP_REGION}" \
      --member="serviceAccount:${build_sa_email}" \
      --role="roles/artifactregistry.writer" \
      --quiet >/dev/null 2>&1; then
      break
    fi
    sleep 2
  done

  gcloud iam service-accounts add-iam-policy-binding "${build_sa_email}" \
    --member="${cloudbuild_sa}" \
    --role="roles/iam.serviceAccountUser" \
    --quiet >/dev/null 2>&1 || true

  BUILD_SA_EMAIL="${build_sa_email}"
  BUILD_SA_RESOURCE="projects/${GCP_PROJECT}/serviceAccounts/${build_sa_email}"
  export BUILD_SA_EMAIL
  export BUILD_SA_RESOURCE
}
