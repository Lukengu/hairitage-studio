@echo off
REM Windows port of sync-static.sh
setlocal EnableDelayedExpansion
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

for %%V in (GCP_PROJECT GCP_REGION GCS_BUCKET CLOUD_RUN_SERVICE SERVICE_ACCOUNT) do (
    if not defined %%V (
        echo ERROR: %%V is not set. Check %CONFIG_FILE%.
        exit /b 1
    )
)

set "ARTIFACT_REPO=cloud-run-source-deploy"
set "IMAGE=%GCP_REGION%-docker.pkg.dev/%GCP_PROJECT%/%ARTIFACT_REPO%/%CLOUD_RUN_SERVICE%:latest"
if not defined GCS_PUBLIC_BUCKET set "GCS_PUBLIC_BUCKET=0"

call gcloud config set project "%GCP_PROJECT%"
if errorlevel 1 exit /b 1

call "%SCRIPT_DIR%\ensure-build-sa.bat"
if errorlevel 1 exit /b 1

echo ==^> Uploading static files to gs://%GCS_BUCKET%/static/
call gcloud builds submit "%REPO_ROOT%\app" ^
  --config="%REPO_ROOT%\app\cloudbuild.yaml" ^
  --substitutions=_IMAGE="%IMAGE%" ^
  --service-account="%BUILD_SA_RESOURCE%"
if errorlevel 1 (
    set "EXITCODE=1"
    goto :done
)

echo.
echo Static sync complete.
echo   Bucket prefix: gs://%GCS_BUCKET%/static/
if defined DOMAIN (
    echo   Public URL: https://%DOMAIN%/static/ ^(via ALB backend bucket^)
) else (
    echo   Public URL: https://your-domain/static/ ^(via ALB backend bucket^)
)

:done
endlocal
exit /b %EXITCODE%
