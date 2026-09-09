@echo off
REM Windows port of reset-admin-password.sh
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

for %%V in (GCP_PROJECT GCP_REGION SQL_INSTANCE SQL_DATABASE SQL_USER CLOUD_RUN_SERVICE SERVICE_ACCOUNT ADMIN_EMAIL) do (
    if not defined %%V (
        echo ERROR: %%V is not set. Check %CONFIG_FILE%.
        exit /b 1
    )
)

set "SA_EMAIL=%SERVICE_ACCOUNT%@%GCP_PROJECT%.iam.gserviceaccount.com"
set "CONNECTION_NAME=%GCP_PROJECT%:%GCP_REGION%:%SQL_INSTANCE%"
set "IMAGE=%GCP_REGION%-docker.pkg.dev/%GCP_PROJECT%/cloud-run-source-deploy/%CLOUD_RUN_SERVICE%:latest"
set "JOB_NAME=hairitage-reset-admin-password"

if not defined ADMIN_USERNAME set "ADMIN_USERNAME=admin"
set "SECRET_NAME=admin-password"
if not defined ROTATE set "ROTATE=0"

set "ENV_FILE=%TEMP%\reset-admin-env-%RANDOM%%RANDOM%.yaml"

if "%ROTATE%"=="1" (
    echo ==^> Rotating %SECRET_NAME% secret
    python3 -c "import secrets;print(secrets.token_urlsafe(16), end='')" | gcloud secrets versions add "%SECRET_NAME%" --project="%GCP_PROJECT%" --data-file=-
    if errorlevel 1 (
        set "EXITCODE=1"
        goto :cleanup
    )
)

call gcloud secrets describe "%SECRET_NAME%" --project="%GCP_PROJECT%" >nul 2>&1
if errorlevel 1 (
    echo ==^> Creating %SECRET_NAME% secret
    python3 -c "import secrets;print(secrets.token_urlsafe(16), end='')" | gcloud secrets create "%SECRET_NAME%" --project="%GCP_PROJECT%" --data-file=-
    if errorlevel 1 (
        set "EXITCODE=1"
        goto :cleanup
    )
)

set "ADMIN_PASSWORD="
for /f "usebackq delims=" %%P in (`gcloud secrets versions access latest --secret="%SECRET_NAME%" --project="%GCP_PROJECT%"`) do set "ADMIN_PASSWORD=%%P"
if not defined ADMIN_PASSWORD (
    echo ERROR: could not read %SECRET_NAME% from Secret Manager.
    set "EXITCODE=1"
    goto :cleanup
)

(
echo DEBUG: "0"
echo DATABASE: "postgres"
echo SQL_ENGINE: "django.db.backends.postgresql"
echo SQL_DATABASE: "%SQL_DATABASE%"
echo SQL_USER: "%SQL_USER%"
echo CLOUD_SQL_CONNECTION_NAME: "%CONNECTION_NAME%"
echo DJANGO_ALLOWED_HOSTS: "localhost"
echo DJANGO_SUPERUSER_USERNAME: "%ADMIN_USERNAME%"
echo DJANGO_SUPERUSER_EMAIL: "%ADMIN_EMAIL%"
echo DJANGO_SUPERUSER_PASSWORD: "%ADMIN_PASSWORD%"
) > "%ENV_FILE%"

call gcloud config set project "%GCP_PROJECT%" >nul

echo ==^> Deploying admin password reset job %JOB_NAME%
call gcloud run jobs deploy "%JOB_NAME%" ^
  --image="%IMAGE%" ^
  --region="%GCP_REGION%" ^
  --service-account="%SA_EMAIL%" ^
  --set-cloudsql-instances="%CONNECTION_NAME%" ^
  --env-vars-file="%ENV_FILE%" ^
  --set-secrets="SQL_PASSWORD=db-password:latest,SECRET_KEY=django-secret-key:latest" ^
  --command=python ^
  --args="manage.py,reset_admin_password,--create" ^
  --max-retries=0 ^
  --task-timeout=600 ^
  --quiet
if errorlevel 1 (
    set "EXITCODE=1"
    goto :cleanup
)

echo ==^> Resetting Django admin password for %ADMIN_USERNAME%
call gcloud run jobs execute "%JOB_NAME%" ^
  --region="%GCP_REGION%" ^
  --wait
if errorlevel 1 (
    set "EXITCODE=1"
    goto :cleanup
)

echo.
echo Admin login:
echo   URL:      https://%DOMAIN%/admin/
echo   Username: %ADMIN_USERNAME%
echo   Email:    %ADMIN_EMAIL%
echo   Password: stored in Secret Manager secret %SECRET_NAME%
echo.
echo Retrieve password:
echo   gcloud secrets versions access latest --secret=%SECRET_NAME% --project=%GCP_PROJECT%
echo.
echo Generate a new password:
echo   set ROTATE=1 ^&^& deploy\gcp\reset-admin-password.bat

:cleanup
if exist "%ENV_FILE%" del /f /q "%ENV_FILE%" >nul 2>&1
endlocal
exit /b %EXITCODE%
