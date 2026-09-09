@echo off
REM Windows port of migrate.sh
setlocal EnableDelayedExpansion
set "EXITCODE=0"

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
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

set "SA_EMAIL=%SERVICE_ACCOUNT%@%GCP_PROJECT%.iam.gserviceaccount.com"
set "CONNECTION_NAME=%GCP_PROJECT%:%GCP_REGION%:%SQL_INSTANCE%"
set "IMAGE=%GCP_REGION%-docker.pkg.dev/%GCP_PROJECT%/cloud-run-source-deploy/%CLOUD_RUN_SERVICE%:latest"
set "JOB_NAME=hairitage-migrate"

set "ENV_FILE=%TEMP%\migrate-env-%RANDOM%%RANDOM%.yaml"

(
echo DEBUG: "0"
echo DATABASE: "postgres"
echo SQL_ENGINE: "django.db.backends.postgresql"
echo SQL_DATABASE: "%SQL_DATABASE%"
echo SQL_USER: "%SQL_USER%"
echo CLOUD_SQL_CONNECTION_NAME: "%CONNECTION_NAME%"
echo GS_BUCKET_NAME: "%GCS_BUCKET%"
echo GCS_PUBLIC_BUCKET: "0"
echo DJANGO_ALLOWED_HOSTS: "localhost"
) > "%ENV_FILE%"

call gcloud config set project "%GCP_PROJECT%" >nul

echo ==^> Deploying migration job %JOB_NAME%
call gcloud run jobs deploy "%JOB_NAME%" ^
  --image="%IMAGE%" ^
  --region="%GCP_REGION%" ^
  --service-account="%SA_EMAIL%" ^
  --set-cloudsql-instances="%CONNECTION_NAME%" ^
  --env-vars-file="%ENV_FILE%" ^
  --set-secrets="SQL_PASSWORD=db-password:latest,SECRET_KEY=django-secret-key:latest" ^
  --command=python ^
  --args="manage.py,migrate,--noinput" ^
  --max-retries=0 ^
  --task-timeout=600 ^
  --quiet
if errorlevel 1 (
    set "EXITCODE=1"
    goto :cleanup
)

echo ==^> Running migrations
call gcloud run jobs execute "%JOB_NAME%" ^
  --region="%GCP_REGION%" ^
  --wait
if errorlevel 1 (
    set "EXITCODE=1"
    goto :cleanup
)

echo ==^> Verifying migrations (second pass if first run hit contenttypes conflict)
call gcloud run jobs execute "%JOB_NAME%" ^
  --region="%GCP_REGION%" ^
  --wait

echo ==^> Migrations complete

:cleanup
if exist "%ENV_FILE%" del /f /q "%ENV_FILE%" >nul 2>&1
endlocal
exit /b %EXITCODE%
