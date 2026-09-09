@echo off
REM Windows port of import-data.sh
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

for %%V in (GCP_PROJECT GCP_REGION SQL_INSTANCE SQL_DATABASE SQL_USER CLOUD_RUN_SERVICE SERVICE_ACCOUNT GCS_BUCKET) do (
    if not defined %%V (
        echo ERROR: %%V is not set. Check %CONFIG_FILE%.
        exit /b 1
    )
)

if not defined FLUSH set "FLUSH=1"
if not defined SYNC_MEDIA set "SYNC_MEDIA=1"
if not defined DEPLOY set "DEPLOY=0"

if not exist "%REPO_ROOT%\app\common\management\commands\import_site_data.py" (
    echo Missing import_site_data management command in app\common\management\commands\
    exit /b 1
)

set "SA_EMAIL=%SERVICE_ACCOUNT%@%GCP_PROJECT%.iam.gserviceaccount.com"
set "CONNECTION_NAME=%GCP_PROJECT%:%GCP_REGION%:%SQL_INSTANCE%"
set "IMAGE=%GCP_REGION%-docker.pkg.dev/%GCP_PROJECT%/cloud-run-source-deploy/%CLOUD_RUN_SERVICE%:latest"
set "JOB_NAME=hairitage-import-data"

if not exist "%REPO_ROOT%\app\fixtures\site_content.json" (
    echo Missing app\fixtures\site_content.json
    echo Run: deploy\export-local-data.bat
    exit /b 1
)

set "ENV_FILE=%TEMP%\import-data-env-%RANDOM%%RANDOM%.yaml"

set "IMPORT_ARGS=manage.py,import_site_data"
if "%FLUSH%"=="1" set "IMPORT_ARGS=manage.py,import_site_data,--flush"

if not defined GCS_PUBLIC_BUCKET set "GCS_PUBLIC_BUCKET=0"

(
echo DEBUG: "0"
echo DATABASE: "postgres"
echo SQL_ENGINE: "django.db.backends.postgresql"
echo SQL_DATABASE: "%SQL_DATABASE%"
echo SQL_USER: "%SQL_USER%"
echo CLOUD_SQL_CONNECTION_NAME: "%CONNECTION_NAME%"
echo GS_BUCKET_NAME: "%GCS_BUCKET%"
echo GCS_PUBLIC_BUCKET: "%GCS_PUBLIC_BUCKET%"
echo DJANGO_ALLOWED_HOSTS: "localhost"
) > "%ENV_FILE%"

call gcloud config set project "%GCP_PROJECT%" >nul

if "%DEPLOY%"=="1" (
    echo ==^> Building and deploying latest app image ^(includes fixture + import command^)
    call "%SCRIPT_DIR%\deploy.bat"
    if errorlevel 1 (
        set "EXITCODE=1"
        goto :cleanup
    )
)

echo.
echo Note: import_site_data must exist in the Cloud Run image.
echo If the job fails with 'Unknown command: import_site_data', run:
echo   set DEPLOY=1 ^&^& deploy\gcp\import-data.bat
echo   # or: deploy\gcp\deploy.bat ^&^& deploy\gcp\import-data.bat
echo.

echo ==^> Deploying import job %JOB_NAME%
call gcloud run jobs deploy "%JOB_NAME%" ^
  --image="%IMAGE%" ^
  --region="%GCP_REGION%" ^
  --service-account="%SA_EMAIL%" ^
  --set-cloudsql-instances="%CONNECTION_NAME%" ^
  --env-vars-file="%ENV_FILE%" ^
  --set-secrets="SQL_PASSWORD=db-password:latest,SECRET_KEY=django-secret-key:latest" ^
  --command=python ^
  --args="%IMPORT_ARGS%" ^
  --max-retries=0 ^
  --task-timeout=900 ^
  --quiet
if errorlevel 1 (
    set "EXITCODE=1"
    goto :cleanup
)

echo ==^> Importing site content fixture
call gcloud run jobs execute "%JOB_NAME%" ^
  --region="%GCP_REGION%" ^
  --wait
if errorlevel 1 (
    set "EXITCODE=1"
    goto :cleanup
)

if "%SYNC_MEDIA%"=="1" if exist "%REPO_ROOT%\app\media" (
    echo ==^> Syncing local media to gs://%GCS_BUCKET%/media/
    call gcloud storage rsync -r "%REPO_ROOT%\app\media" "gs://%GCS_BUCKET%/media"
    if errorlevel 1 (
        set "EXITCODE=1"
        goto :cleanup
    )
) else (
    echo ==^> Skipping media sync ^(SYNC_MEDIA=%SYNC_MEDIA%^)
)

echo.
echo Import complete. Review: https://%DOMAIN%/

:cleanup
if exist "%ENV_FILE%" del /f /q "%ENV_FILE%" >nul 2>&1
endlocal
exit /b %EXITCODE%
