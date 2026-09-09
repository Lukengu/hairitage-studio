@echo off
REM Copy to config.bat and edit:
REM   copy deploy\gcp\config.example.bat deploy\gcp\config.bat

set "GCP_PROJECT=hairitage-studion-web"
set "GCP_REGION=africa-south1"

set "GCS_BUCKET=%GCP_PROJECT%-assets"
set "SQL_INSTANCE=hairitage-db"
set "SQL_DATABASE=hairitage"
set "SQL_USER=hairst_usr"

set "CLOUD_RUN_SERVICE=hairitage-web"
set "SERVICE_ACCOUNT=hairitage-run"
set "BUILD_SERVICE_ACCOUNT=hairitage-build"

set "DOMAIN=hairitage-studio.co.za"
set "ADMIN_EMAIL=info@hairitage-studio.co.za"

REM SMTP. Password lives in Secret Manager secret email-smtp-password (never commit it):
REM   echo YOUR_APP_PASSWORD| gcloud secrets versions add email-smtp-password --data-file=-
REM Apply env to Cloud Run without rebuilding: deploy\gcp\update-email-env.bat
if not defined EMAIL_HOST set "EMAIL_HOST=smtp.gmail.com"
if not defined EMAIL_HOST_USER set "EMAIL_HOST_USER=info@hairitage-studio.co.za"
if not defined EMAIL_PORT set "EMAIL_PORT=465"
if not defined EMAIL_USE_TLS set "EMAIL_USE_TLS=False"
if not defined EMAIL_USE_SSL set "EMAIL_USE_SSL=True"
if not defined DEFAULT_FROM_EMAIL set "DEFAULT_FROM_EMAIL=info@hairitage-studio.co.za"
if not defined DEFAULT_NO_REPLY_EMAIL set "DEFAULT_NO_REPLY_EMAIL=Hairitage Studio <noreply@hairitage-studio.co.za>"

REM Cloudflare Turnstile (human verification on contact/booking forms).
REM 1. Create a widget at https://dash.cloudflare.com/?to=/:account/turnstile
REM    Hostnames: hairitage-studio.co.za, www.hairitage-studio.co.za
REM 2. Add site key to config.bat:
REM set "TURNSTILE_SITE_KEY=0x4AAAAAAA..."
REM 3. Store secret key in Secret Manager:
REM    echo YOUR_SECRET_KEY| gcloud secrets create turnstile-secret-key --data-file=-
REM 4. Apply without rebuild: deploy\gcp\update-turnstile-env.bat

REM Optional Google Maps JavaScript API key for the contact page map.
REM Without this, the contact page uses a free Google Maps embed iframe.
REM set "GOOGLE_MAPS_API_KEY=your-maps-api-key"

REM 1 = public static/media URLs from GCS (needs allUsers IAM on bucket)
REM 0 = private bucket; static served via ALB /static/* backend bucket
set "GCS_PUBLIC_BUCKET=0"
set "USE_ALB=1"
