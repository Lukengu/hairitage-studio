@echo off
REM Windows port of update-email-env.sh
REM Apply SMTP env vars (and optional secret) to Cloud Run without rebuilding the image.
setlocal EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "CONFIG_FILE=%SCRIPT_DIR%\config.bat"

if not exist "%CONFIG_FILE%" (
    echo Missing %CONFIG_FILE%. Copy deploy\gcp\config.example.bat to deploy\gcp\config.bat first.
    exit /b 1
)
call "%CONFIG_FILE%"

for %%V in (GCP_PROJECT GCP_REGION CLOUD_RUN_SERVICE) do (
    if not defined %%V (
        echo ERROR: %%V is not set. Check %CONFIG_FILE%.
        exit /b 1
    )
)

if not defined EMAIL_HOST (
    echo EMAIL_HOST is not set in config.bat. Add SMTP settings and retry.
    exit /b 1
)

call gcloud config set project "%GCP_PROJECT%"
if errorlevel 1 exit /b 1

set "ACTIVE_REVISION="
for /f "usebackq delims=" %%A in (`gcloud run services describe "%CLOUD_RUN_SERVICE%" --project="%GCP_PROJECT%" --region="%GCP_REGION%" --format="value(status.traffic[0].revisionName)"`) do set "ACTIVE_REVISION=%%A"

set "WORKING_IMAGE="
for /f "usebackq delims=" %%A in (`gcloud run revisions describe "%ACTIVE_REVISION%" --project="%GCP_PROJECT%" --region="%GCP_REGION%" --format="value(spec.containers[0].image)"`) do set "WORKING_IMAGE=%%A"

if not defined EMAIL_HOST_USER set "EMAIL_HOST_USER=info@hairitage-studio.co.za"
if not defined EMAIL_PORT set "EMAIL_PORT=465"
if not defined EMAIL_USE_TLS set "EMAIL_USE_TLS=False"
if not defined EMAIL_USE_SSL set "EMAIL_USE_SSL=True"
if not defined DEFAULT_FROM_EMAIL set "DEFAULT_FROM_EMAIL=info@hairitage-studio.co.za"
if not defined DEFAULT_NO_REPLY_EMAIL set "DEFAULT_NO_REPLY_EMAIL=Hairitage Studio <noreply@hairitage-studio.co.za>"

set "ENV_VARS=^^:^^EMAIL_HOST=%EMAIL_HOST%:EMAIL_HOST_USER=%EMAIL_HOST_USER%:EMAIL_PORT=%EMAIL_PORT%:EMAIL_USE_TLS=%EMAIL_USE_TLS%:EMAIL_USE_SSL=%EMAIL_USE_SSL%:DEFAULT_FROM_EMAIL=%DEFAULT_FROM_EMAIL%:DEFAULT_NO_REPLY_EMAIL=%DEFAULT_NO_REPLY_EMAIL%"

set "HAS_EMAIL_SECRET="
call gcloud secrets describe email-smtp-password --project="%GCP_PROJECT%" >nul 2>&1
if not errorlevel 1 (
    for /f "usebackq delims=" %%L in (`gcloud secrets versions list email-smtp-password --project="%GCP_PROJECT%" --limit=1 --format="value(name)" 2^>nul`) do set "HAS_EMAIL_SECRET=1"
)

echo ==^> Pinning image %WORKING_IMAGE%
if defined HAS_EMAIL_SECRET (
    echo ==^> Updating %CLOUD_RUN_SERVICE% email env + EMAIL_HOST_PASSWORD secret
    call gcloud run services update "%CLOUD_RUN_SERVICE%" ^
      --project="%GCP_PROJECT%" ^
      --region="%GCP_REGION%" ^
      --image="%WORKING_IMAGE%" ^
      --update-env-vars="%ENV_VARS%" ^
      --update-secrets="EMAIL_HOST_PASSWORD=email-smtp-password:latest" ^
      --quiet
) else (
    echo WARNING: Secret email-smtp-password has no version yet.
    echo          Create and set your SMTP password first:
    echo            deploy\gcp\setup-infra.bat   ^& REM creates placeholder secret if missing
    echo            echo APP_PASSWORD^| gcloud secrets versions add email-smtp-password --data-file=-
    echo          Then re-run: deploy\gcp\update-email-env.bat
    echo.
    echo ==^> Updating %CLOUD_RUN_SERVICE% email env only ^(no password secret^)
    call gcloud run services update "%CLOUD_RUN_SERVICE%" ^
      --project="%GCP_PROJECT%" ^
      --region="%GCP_REGION%" ^
      --image="%WORKING_IMAGE%" ^
      --update-env-vars="%ENV_VARS%" ^
      --quiet
)
if errorlevel 1 exit /b 1

echo.
echo Email env applied to %CLOUD_RUN_SERVICE% (no image rebuild).
echo   EMAIL_HOST=%EMAIL_HOST%
echo   EMAIL_PORT=%EMAIL_PORT%
echo   EMAIL_USE_SSL=%EMAIL_USE_SSL%
echo   DEFAULT_FROM_EMAIL=%DEFAULT_FROM_EMAIL%

endlocal
exit /b 0
