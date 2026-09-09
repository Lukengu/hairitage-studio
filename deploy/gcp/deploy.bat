@echo off
REM ============================================================
REM Windows port of deploy.sh
REM Requires: gcloud CLI on PATH, and deploy\gcp\config.bat
REM (bash "source config.sh" -> batch "call config.bat", so your
REM  config file must now use `set VAR=value` lines instead of
REM  shell VAR=value lines. See config.example.bat.)
REM ============================================================

setlocal enabledelayedexpansion
set "EXITCODE=0"

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
for %%I in ("%SCRIPT_DIR%\..\..") do set "REPO_ROOT=%%~fI"

set "CONFIG_FILE=%SCRIPT_DIR%\config.bat"

if not exist "%CONFIG_FILE%" (
    echo Missing %CONFIG_FILE%. Copy deploy\gcp\config.example.bat to deploy\gcp\config.bat first.
    exit /b 1
)

call "%CONFIG_FILE%"

REM ---- required vars check (bash ": ${VAR:?}") ----
for %%V in (GCP_PROJECT GCP_REGION GCS_BUCKET SQL_INSTANCE SQL_DATABASE SQL_USER CLOUD_RUN_SERVICE SERVICE_ACCOUNT DOMAIN) do (
    if not defined %%V (
        echo ERROR: %%V is not set. Check %CONFIG_FILE%.
        exit /b 1
    )
)

set "SA_EMAIL=%SERVICE_ACCOUNT%@%GCP_PROJECT%.iam.gserviceaccount.com"
set "CONNECTION_NAME=%GCP_PROJECT%:%GCP_REGION%:%SQL_INSTANCE%"
set "ARTIFACT_REPO=cloud-run-source-deploy"
set "IMAGE=%GCP_REGION%-docker.pkg.dev/%GCP_PROJECT%/%ARTIFACT_REPO%/%CLOUD_RUN_SERVICE%:latest"

if not defined COLLECT_STATIC set "COLLECT_STATIC=1"
if not defined GCS_PUBLIC_BUCKET set "GCS_PUBLIC_BUCKET=0"
if not defined USE_ALB set "USE_ALB=1"

REM ---- temp env file (stand-in for bash mktemp) ----
set "ENV_FILE=%TEMP%\cloudrun-env-%RANDOM%%RANDOM%.yaml"

(
echo DEBUG: "0"
echo DATABASE: "postgres"
echo SQL_ENGINE: "django.db.backends.postgresql"
echo SQL_DATABASE: "%SQL_DATABASE%"
echo SQL_USER: "%SQL_USER%"
echo CLOUD_SQL_CONNECTION_NAME: "%CONNECTION_NAME%"
echo GS_BUCKET_NAME: "%GCS_BUCKET%"
echo GCS_PUBLIC_BUCKET: "%GCS_PUBLIC_BUCKET%"
echo DJANGO_ALLOWED_HOSTS: "%DOMAIN%,www.%DOMAIN%,.run.app"
echo COLLECT_STATIC: "%COLLECT_STATIC%"
) > "%ENV_FILE%"

if defined CSRF_TRUSTED_ORIGINS_EXTRA (
    echo CSRF_TRUSTED_ORIGINS_EXTRA: "%CSRF_TRUSTED_ORIGINS_EXTRA%">> "%ENV_FILE%"
)

if defined EMAIL_HOST (
    if not defined EMAIL_HOST_USER set "EMAIL_HOST_USER=info@hairitage-studio.co.za"
    if not defined EMAIL_PORT set "EMAIL_PORT=465"
    if not defined EMAIL_USE_TLS set "EMAIL_USE_TLS=False"
    if not defined EMAIL_USE_SSL set "EMAIL_USE_SSL=True"
    if not defined DEFAULT_FROM_EMAIL set "DEFAULT_FROM_EMAIL=info@hairitage-studio.co.za"
    if not defined DEFAULT_NO_REPLY_EMAIL set "DEFAULT_NO_REPLY_EMAIL=Hairitage Studio <noreply@hairitage-studio.co.za>"
    (
    echo EMAIL_HOST: "%EMAIL_HOST%"
    echo EMAIL_HOST_USER: "%EMAIL_HOST_USER%"
    echo EMAIL_PORT: "%EMAIL_PORT%"
    echo EMAIL_USE_TLS: "%EMAIL_USE_TLS%"
    echo EMAIL_USE_SSL: "%EMAIL_USE_SSL%"
    echo DEFAULT_FROM_EMAIL: "%DEFAULT_FROM_EMAIL%"
    echo DEFAULT_NO_REPLY_EMAIL: "%DEFAULT_NO_REPLY_EMAIL%"
    ) >> "%ENV_FILE%"
)

if defined TURNSTILE_SITE_KEY (
    echo TURNSTILE_SITE_KEY: "%TURNSTILE_SITE_KEY%">> "%ENV_FILE%"
)

if defined GOOGLE_MAPS_API_KEY (
    echo GOOGLE_MAPS_API_KEY: "%GOOGLE_MAPS_API_KEY%">> "%ENV_FILE%"
)

set "SECRETS=SQL_PASSWORD=db-password:latest,SECRET_KEY=django-secret-key:latest"

set "HAS_EMAIL_SECRET="
call gcloud secrets describe email-smtp-password --project="%GCP_PROJECT%" >nul 2>&1
if not errorlevel 1 (
    for /f "usebackq delims=" %%L in (`gcloud secrets versions list email-smtp-password --project="%GCP_PROJECT%" --limit=1 --format="value(name)" 2^>nul`) do set "HAS_EMAIL_SECRET=1"
)
if defined HAS_EMAIL_SECRET (
    set "SECRETS=%SECRETS%,EMAIL_HOST_PASSWORD=email-smtp-password:latest"
) else (
    echo WARNING: Secret email-smtp-password not found or has no version; EMAIL_HOST_PASSWORD will be unset.
    echo          Create it: deploy\gcp\setup-infra.bat
    echo          Then set password: echo APP_PASSWORD^| gcloud secrets versions add email-smtp-password --data-file=-
    echo          Or apply without rebuild: deploy\gcp\update-email-env.bat
)

set "HAS_TURNSTILE_SECRET="
call gcloud secrets describe turnstile-secret-key --project="%GCP_PROJECT%" >nul 2>&1
if not errorlevel 1 (
    for /f "usebackq delims=" %%L in (`gcloud secrets versions list turnstile-secret-key --project="%GCP_PROJECT%" --limit=1 --format="value(name)" 2^>nul`) do set "HAS_TURNSTILE_SECRET=1"
)
if defined HAS_TURNSTILE_SECRET (
    set "SECRETS=%SECRETS%,TURNSTILE_SECRET_KEY=turnstile-secret-key:latest"
)

call gcloud config set project "%GCP_PROJECT%"

REM ---- ensure-build-sa.bat must `set BUILD_SA_EMAIL=...` / `set BUILD_SA_RESOURCE=...` ----
call "%SCRIPT_DIR%\ensure-build-sa.bat"
if errorlevel 1 (
    set "EXITCODE=1"
    goto :cleanup
)

echo ==^> Building image %IMAGE% (service account: %BUILD_SA_EMAIL%)
call gcloud builds submit "%REPO_ROOT%\app" ^
  --config="%REPO_ROOT%\app\cloudbuild.yaml" ^
  --substitutions=_IMAGE="%IMAGE%" ^
  --service-account="%BUILD_SA_RESOURCE%"
if errorlevel 1 (
    set "EXITCODE=1"
    goto :cleanup
)

echo ==^> Deploying %CLOUD_RUN_SERVICE% to %GCP_REGION%
call gcloud run deploy "%CLOUD_RUN_SERVICE%" ^
  --project="%GCP_PROJECT%" ^
  --image="%IMAGE%" ^
  --region="%GCP_REGION%" ^
  --platform=managed ^
  --service-account="%SA_EMAIL%" ^
  --add-cloudsql-instances="%CONNECTION_NAME%" ^
  --env-vars-file="%ENV_FILE%" ^
  --set-secrets="%SECRETS%" ^
  --memory=1Gi ^
  --cpu=1 ^
  --cpu-boost ^
  --min-instances=0 ^
  --max-instances=3 ^
  --no-allow-unauthenticated
if errorlevel 1 (
    set "EXITCODE=1"
    goto :cleanup
)

if "%USE_ALB%"=="1" (
    echo ==^> ALB mode: restrict ingress and skip invoker IAM check
    call gcloud run services update "%CLOUD_RUN_SERVICE%" ^
      --project="%GCP_PROJECT%" ^
      --region="%GCP_REGION%" ^
      --ingress=internal-and-cloud-load-balancing ^
      --no-invoker-iam-check ^
      --quiet
    if errorlevel 1 (
        set "EXITCODE=1"
        goto :cleanup
    )
) else (
    echo ==^> Allowing public web access
    call gcloud run services add-iam-policy-binding "%CLOUD_RUN_SERVICE%" ^
      --project="%GCP_PROJECT%" ^
      --region="%GCP_REGION%" ^
      --member="allUsers" ^
      --role="roles/run.invoker" ^
      --quiet >nul 2>&1
    if errorlevel 1 (
        echo.
        echo WARNING: Could not grant public access ^(org policy may block allUsers^).
        echo          Use the ALB route instead: deploy\gcp\setup-alb.bat
        echo.
    )
)

set "SERVICE_URL="
for /f "usebackq delims=" %%U in (`gcloud run services describe "%CLOUD_RUN_SERVICE%" --project="%GCP_PROJECT%" --region="%GCP_REGION%" --format="value(status.url)"`) do set "SERVICE_URL=%%U"

echo.
echo Deployment complete.
echo   Service URL: %SERVICE_URL%
echo.
echo Tips:
echo   Static files are served from Cloud Run at /static/ and copied to gs://%GCS_BUCKET%/static/.
echo   Custom domain via ALB: deploy\gcp\setup-alb.bat (required in %GCP_REGION%)
echo   Add CSRF origin if testing the *.run.app URL:
echo     set CSRF_TRUSTED_ORIGINS_EXTRA=%SERVICE_URL%^&^& set COLLECT_STATIC=1 ^&^& deploy\gcp\deploy.bat

if defined EMAIL_HOST (
    call gcloud secrets describe email-smtp-password --project="%GCP_PROJECT%" >nul 2>&1
    if errorlevel 1 (
        echo   Email: set SMTP token in Secret Manager secret email-smtp-password, then:
        echo     deploy\gcp\update-email-env.bat
    )
)

:cleanup
if exist "%ENV_FILE%" del /f /q "%ENV_FILE%" >nul 2>&1
endlocal
exit /b %EXITCODE%
