#!/usr/bin/env bash
# Copy to config.sh and edit:
#   cp deploy/gcp/config.example.sh deploy/gcp/config.sh

export GCP_PROJECT="hairitage-studion-web"
export GCP_REGION="africa-south1"

export GCS_BUCKET="${GCP_PROJECT}-assets"
export SQL_INSTANCE="hairitage-db"
export SQL_DATABASE="hairitage"
export SQL_USER="hairst_usr"

export CLOUD_RUN_SERVICE="hairitage-web"
export SERVICE_ACCOUNT="hairitage-run"
export BUILD_SERVICE_ACCOUNT="hairitage-build"

export DOMAIN="hairitage-studio.co.za"
export ADMIN_EMAIL="info@hairitage-studio.co.za"

# SMTP. Password lives in Secret Manager secret email-smtp-password (never commit it):
#   printf '%s' 'YOUR_APP_PASSWORD' | gcloud secrets versions add email-smtp-password --data-file=-
# Apply env to Cloud Run without rebuilding: bash deploy/gcp/update-email-env.sh
export EMAIL_HOST="${EMAIL_HOST:-smtp.gmail.com}"
export EMAIL_HOST_USER="${EMAIL_HOST_USER:-info@hairitage-studio.co.za}"
export EMAIL_PORT="${EMAIL_PORT:-465}"
export EMAIL_USE_TLS="${EMAIL_USE_TLS:-False}"
export EMAIL_USE_SSL="${EMAIL_USE_SSL:-True}"
export DEFAULT_FROM_EMAIL="${DEFAULT_FROM_EMAIL:-info@hairitage-studio.co.za}"
export DEFAULT_NO_REPLY_EMAIL="${DEFAULT_NO_REPLY_EMAIL:-Hairitage Studio <noreply@hairitage-studio.co.za>}"

# Cloudflare Turnstile (human verification on contact/booking forms).
# 1. Create a widget at https://dash.cloudflare.com/?to=/:account/turnstile
#    Hostnames: hairitage-studio.co.za, www.hairitage-studio.co.za
# 2. Add site key to config.sh:
# export TURNSTILE_SITE_KEY="0x4AAAAAAA..."
# 3. Store secret key in Secret Manager:
#    printf '%s' 'YOUR_SECRET_KEY' | gcloud secrets create turnstile-secret-key --data-file=-
# 4. Apply without rebuild: bash deploy/gcp/update-turnstile-env.sh

# Optional Google Maps JavaScript API key for the contact page map.
# Without this, the contact page uses a free Google Maps embed iframe.
# export GOOGLE_MAPS_API_KEY="your-maps-api-key"

# 1 = public static/media URLs from GCS (needs allUsers IAM on bucket)
# 0 = private bucket; static served via ALB /static/* backend bucket
export GCS_PUBLIC_BUCKET="0"
export USE_ALB="1"
