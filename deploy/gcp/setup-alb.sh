#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.sh"

# shellcheck source=config.sh
source "${CONFIG_FILE}"

: "${GCP_PROJECT:?}"
: "${GCP_REGION:?}"
: "${CLOUD_RUN_SERVICE:?}"
: "${DOMAIN:?}"
: "${GCS_BUCKET:?}"

WWW_DOMAIN="${WWW_DOMAIN:-www.${DOMAIN}}"

IP_NAME="hairitage-alb-ip"
NEG_NAME="hairitage-run-neg"
BACKEND_NAME="hairitage-run-backend"
URL_MAP_NAME="hairitage-url-map"
HTTP_REDIRECT_MAP="hairitage-http-redirect"
CERT_NAME="hairitage-managed-cert"
HTTPS_PROXY_NAME="hairitage-https-proxy"
HTTP_PROXY_NAME="hairitage-http-proxy"
HTTPS_RULE_NAME="hairitage-https-fr"
HTTP_RULE_NAME="hairitage-http-fr"
STATIC_BACKEND_BUCKET="hairitage-static-bucket"

gcloud config set project "${GCP_PROJECT}"

echo "==> Enabling Compute API"
gcloud services enable compute.googleapis.com

if ! gcloud compute addresses describe "${IP_NAME}" --global >/dev/null 2>&1; then
  echo "==> Reserving global static IP ${IP_NAME}"
  gcloud compute addresses create "${IP_NAME}" --global
fi

LB_IP="$(gcloud compute addresses describe "${IP_NAME}" --global --format='value(address)')"
echo "    Load balancer IP: ${LB_IP}"

if ! gcloud compute network-endpoint-groups describe "${NEG_NAME}" \
  --region="${GCP_REGION}" >/dev/null 2>&1; then
  echo "==> Creating serverless NEG ${NEG_NAME}"
  gcloud compute network-endpoint-groups create "${NEG_NAME}" \
    --region="${GCP_REGION}" \
    --network-endpoint-type=serverless \
    --cloud-run-service="${CLOUD_RUN_SERVICE}"
fi

if ! gcloud compute backend-services describe "${BACKEND_NAME}" --global >/dev/null 2>&1; then
  echo "==> Creating backend service ${BACKEND_NAME}"
  gcloud compute backend-services create "${BACKEND_NAME}" \
    --global \
    --load-balancing-scheme=EXTERNAL_MANAGED \
    --protocol=HTTP
fi

if ! gcloud compute backend-services describe "${BACKEND_NAME}" --global \
  --format='value(backends.group)' 2>/dev/null | grep -q "${NEG_NAME}"; then
  echo "==> Attaching Cloud Run NEG to backend"
  gcloud compute backend-services add-backend "${BACKEND_NAME}" \
    --global \
    --network-endpoint-group="${NEG_NAME}" \
    --network-endpoint-group-region="${GCP_REGION}"
fi

if ! gcloud compute url-maps describe "${URL_MAP_NAME}" --global >/dev/null 2>&1; then
  echo "==> Creating URL map ${URL_MAP_NAME}"
  gcloud compute url-maps create "${URL_MAP_NAME}" \
    --default-service="${BACKEND_NAME}"
fi

GCS_PUBLIC_BUCKET="${GCS_PUBLIC_BUCKET:-0}"
if [[ "${GCS_PUBLIC_BUCKET}" == "1" ]]; then
  if ! gcloud compute backend-buckets describe "${STATIC_BACKEND_BUCKET}" --global >/dev/null 2>&1; then
    echo "==> Creating backend bucket ${STATIC_BACKEND_BUCKET} for gs://${GCS_BUCKET}"
    gcloud compute backend-buckets create "${STATIC_BACKEND_BUCKET}" \
      --gcs-bucket-name="${GCS_BUCKET}" \
      --enable-cdn
  fi

  PROJECT_NUMBER="$(gcloud projects describe "${GCP_PROJECT}" --format='value(projectNumber)')"
  CLOUD_SERVICES_SA="${PROJECT_NUMBER}@cloudservices.gserviceaccount.com"
  echo "==> Granting load balancer read access to gs://${GCS_BUCKET}"
  gcloud storage buckets add-iam-policy-binding "gs://${GCS_BUCKET}" \
    --member="serviceAccount:${CLOUD_SERVICES_SA}" \
    --role="roles/storage.objectViewer" \
    --quiet >/dev/null 2>&1 || \
    echo "    (bucket IAM binding may already exist)"

  if ! gcloud compute url-maps describe "${URL_MAP_NAME}" --global \
    --format='yaml(pathMatchers)' 2>/dev/null | grep -q 'site-routes'; then
    echo "==> Routing /static/* to GCS backend bucket"
    gcloud compute url-maps add-path-matcher "${URL_MAP_NAME}" \
      --path-matcher-name=site-routes \
      --default-service="${BACKEND_NAME}" \
      --backend-bucket-path-rules="/static/*=${STATIC_BACKEND_BUCKET}" \
      --global
    gcloud compute url-maps add-host-rule "${URL_MAP_NAME}" \
      --hosts="${DOMAIN},${WWW_DOMAIN}" \
      --path-matcher-name=site-routes \
      --global
  fi
else
  echo "==> Static served by Cloud Run (/static/) with a GCS copy at gs://${GCS_BUCKET}/static/"
  echo "    (Private bucket + org policy: ALB cannot read GCS without public object access.)"
fi

if ! gcloud compute ssl-certificates describe "${CERT_NAME}" --global >/dev/null 2>&1; then
  echo "==> Creating managed SSL certificate for ${DOMAIN} and ${WWW_DOMAIN}"
  gcloud compute ssl-certificates create "${CERT_NAME}" \
    --domains="${DOMAIN},${WWW_DOMAIN}" \
    --global
fi

if ! gcloud compute target-https-proxies describe "${HTTPS_PROXY_NAME}" --global >/dev/null 2>&1; then
  echo "==> Creating HTTPS proxy"
  gcloud compute target-https-proxies create "${HTTPS_PROXY_NAME}" \
    --url-map="${URL_MAP_NAME}" \
    --ssl-certificates="${CERT_NAME}"
fi

if ! gcloud compute forwarding-rules describe "${HTTPS_RULE_NAME}" --global >/dev/null 2>&1; then
  echo "==> Creating HTTPS forwarding rule"
  gcloud compute forwarding-rules create "${HTTPS_RULE_NAME}" \
    --global \
    --target-https-proxy="${HTTPS_PROXY_NAME}" \
    --address="${IP_NAME}" \
    --ports=443
fi

if ! gcloud compute url-maps describe "${HTTP_REDIRECT_MAP}" --global >/dev/null 2>&1; then
  echo "==> Creating HTTP to HTTPS redirect"
  gcloud compute url-maps import "${HTTP_REDIRECT_MAP}" --global --quiet <<EOF
name: ${HTTP_REDIRECT_MAP}
defaultUrlRedirect:
  httpsRedirect: true
  redirectResponseCode: MOVED_PERMANENTLY_DEFAULT
EOF
fi

if ! gcloud compute target-http-proxies describe "${HTTP_PROXY_NAME}" --global >/dev/null 2>&1; then
  gcloud compute target-http-proxies create "${HTTP_PROXY_NAME}" \
    --url-map="${HTTP_REDIRECT_MAP}"
fi

if ! gcloud compute forwarding-rules describe "${HTTP_RULE_NAME}" --global >/dev/null 2>&1; then
  gcloud compute forwarding-rules create "${HTTP_RULE_NAME}" \
    --global \
    --target-http-proxy="${HTTP_PROXY_NAME}" \
    --address="${IP_NAME}" \
    --ports=80
fi

echo "==> Restricting Cloud Run ingress to load balancer only"
gcloud run services update "${CLOUD_RUN_SERVICE}" \
  --region="${GCP_REGION}" \
  --ingress=internal-and-cloud-load-balancing \
  --quiet

echo "==> Allowing load balancer traffic without allUsers (org-policy safe)"
gcloud run services update "${CLOUD_RUN_SERVICE}" \
  --region="${GCP_REGION}" \
  --no-invoker-iam-check \
  --quiet

CERT_STATUS="$(gcloud compute ssl-certificates describe "${CERT_NAME}" \
  --global --format='value(managed.status)' 2>/dev/null || echo "UNKNOWN")"

echo ""
echo "=========================================="
echo "Application Load Balancer ready"
echo "=========================================="
echo ""
echo "Add these DNS records at your .co.za registrar:"
echo ""
echo "  Type: A"
echo "  Name: @"
echo "  Value: ${LB_IP}"
echo ""
echo "  Type: A"
echo "  Name: www"
echo "  Value: ${LB_IP}"
echo ""
echo "SSL certificate status: ${CERT_STATUS}"
echo "(Becomes ACTIVE after DNS propagates, usually 15-60 minutes)"
echo ""
echo "Test after DNS + SSL are active:"
echo "  https://${DOMAIN}"
echo "  https://${WWW_DOMAIN}"
echo ""
echo "Note: This route avoids Cloud Run domain mapping (not supported in africa-south1)"
echo "      and avoids allUsers — ingress is LB-only and invoker IAM check is disabled."
