@echo off
REM Windows port of update-turnstile-env.sh
REM Apply Cloudflare Turnstile env vars to Cloud Run without rebuilding the image.
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

if not defined TURNSTILE_SITE_KEY (
    echo TURNSTILE_SITE_KEY is not set in config.bat.
    echo Get it from Cloudflare Dashboard - Turnstile - your widget - Site Key
    exit /b 1
)

call gcloud config set project "%GCP_PROJECT%"
if errorlevel 1 exit /b 1

set "ACTIVE_REVISION="
for /f "usebackq delims=" %%A in (`gcloud run services describe "%CLOUD_RUN_SERVICE%" --project="%GCP_PROJECT%" --region="%GCP_REGION%" --format="value(status.traffic[0].revisionName)"`) do set "ACTIVE_REVISION=%%A"

set "WORKING_IMAGE="
for /f "usebackq delims=" %%A in (`gcloud run revisions describe "%ACTIVE_REVISION%" --project="%GCP_PROJECT%" --region="%GCP_REGION%" --format="value(spec.containers[0].image)"`) do set "WORKING_IMAGE=%%A"

set "HAS_TURNSTILE_SECRET="
call gcloud secrets describe turnstile-secret-key --project="%GCP_PROJECT%" >nul 2>&1
if not errorlevel 1 (
    for /f "usebackq delims=" %%L in (`gcloud secrets versions list turnstile-secret-key --project="%GCP_PROJECT%" --limit=1 --format="value(name)" 2^>nul`) do set "HAS_TURNSTILE_SECRET=1"
)

if defined HAS_TURNSTILE_SECRET (
    echo ==^> Updating %CLOUD_RUN_SERVICE% Turnstile site key + secret
    call gcloud run services update "%CLOUD_RUN_SERVICE%" ^
      --project="%GCP_PROJECT%" ^
      --region="%GCP_REGION%" ^
      --image="%WORKING_IMAGE%" ^
      --update-env-vars="TURNSTILE_SITE_KEY=%TURNSTILE_SITE_KEY%" ^
      --update-secrets="TURNSTILE_SECRET_KEY=turnstile-secret-key:latest" ^
      --quiet
) else (
    echo WARNING: Secret turnstile-secret-key not found.
    echo          Create it:
    echo            echo YOUR_SECRET_KEY^| gcloud secrets create turnstile-secret-key --data-file=- --project=%GCP_PROJECT%
    echo          Then re-run: deploy\gcp\update-turnstile-env.bat
    echo.
    echo ==^> Updating %CLOUD_RUN_SERVICE% Turnstile site key only
    call gcloud run services update "%CLOUD_RUN_SERVICE%" ^
      --project="%GCP_PROJECT%" ^
      --region="%GCP_REGION%" ^
      --image="%WORKING_IMAGE%" ^
      --update-env-vars="TURNSTILE_SITE_KEY=%TURNSTILE_SITE_KEY%" ^
      --quiet
)
if errorlevel 1 exit /b 1

echo.
echo Turnstile env applied to %CLOUD_RUN_SERVICE%.
echo   TURNSTILE_SITE_KEY=%TURNSTILE_SITE_KEY%
echo.
echo Redeploy the app image if the contact form template changed:
echo   deploy\gcp\deploy.bat

endlocal
exit /b 0
