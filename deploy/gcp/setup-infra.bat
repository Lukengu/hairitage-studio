@echo off
REM Windows port of setup-infra.sh
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

for %%V in (GCP_PROJECT GCP_REGION GCS_BUCKET SQL_INSTANCE SQL_DATABASE SQL_USER CLOUD_RUN_SERVICE SERVICE_ACCOUNT) do (
    if not defined %%V (
        echo ERROR: %%V is not set. Check %CONFIG_FILE%.
        exit /b 1
    )
)

set "SA_EMAIL=%SERVICE_ACCOUNT%@%GCP_PROJECT%.iam.gserviceaccount.com"
set "CONNECTION_NAME=%GCP_PROJECT%:%GCP_REGION%:%SQL_INSTANCE%"

echo ==^> Setting project %GCP_PROJECT%
call gcloud config set project "%GCP_PROJECT%"
if errorlevel 1 exit /b 1

echo ==^> Enabling required APIs
call gcloud services enable ^
  run.googleapis.com ^
  sqladmin.googleapis.com ^
  storage.googleapis.com ^
  artifactregistry.googleapis.com ^
  secretmanager.googleapis.com ^
  cloudbuild.googleapis.com
if errorlevel 1 exit /b 1

set "PROJECT_NUMBER="
for /f "usebackq delims=" %%A in (`gcloud projects describe "%GCP_PROJECT%" --format="value(projectNumber)"`) do set "PROJECT_NUMBER=%%A"
set "CLOUDBUILD_SA=serviceAccount:%PROJECT_NUMBER%@cloudbuild.gserviceaccount.com"
set "COMPUTE_SA=serviceAccount:%PROJECT_NUMBER%-compute@developer.gserviceaccount.com"

echo ==^> Granting Cloud Build permissions
call :grant_member_role "%CLOUDBUILD_SA%" roles/storage.admin
if errorlevel 1 exit /b 1
call :grant_member_role "%CLOUDBUILD_SA%" roles/artifactregistry.writer
if errorlevel 1 exit /b 1
call :grant_member_role "%CLOUDBUILD_SA%" roles/logging.logWriter
if errorlevel 1 exit /b 1
call :grant_member_role "%CLOUDBUILD_SA%" roles/cloudbuild.builds.builder
if errorlevel 1 exit /b 1
call :grant_member_role "%COMPUTE_SA%" roles/storage.objectAdmin
if errorlevel 1 exit /b 1
call :grant_member_role "%COMPUTE_SA%" roles/artifactregistry.writer
if errorlevel 1 exit /b 1
call :grant_member_role "%COMPUTE_SA%" roles/logging.logWriter
if errorlevel 1 exit /b 1

call "%SCRIPT_DIR%\ensure-build-sa.bat"
if errorlevel 1 exit /b 1

call gcloud secrets describe django-secret-key >nul 2>&1
if errorlevel 1 (
    echo ==^> Creating django-secret-key secret
    python3 -c "import secrets;print(secrets.token_urlsafe(50), end='')" | gcloud secrets create django-secret-key --data-file=-
    if errorlevel 1 exit /b 1
) else (
    echo ==^> Secret django-secret-key already exists
)

call gcloud secrets describe db-password >nul 2>&1
if errorlevel 1 (
    echo ==^> Creating db-password secret
    python3 -c "import secrets;print(secrets.token_urlsafe(24), end='')" | gcloud secrets create db-password --data-file=-
    if errorlevel 1 exit /b 1
) else (
    echo ==^> Secret db-password already exists
)

call gcloud secrets describe email-smtp-password >nul 2>&1
if errorlevel 1 (
    echo ==^> Creating email-smtp-password secret placeholder
    call gcloud secrets create email-smtp-password --replication-policy=automatic
    if errorlevel 1 exit /b 1
    set "PLACEHOLDER_FILE=%TEMP%\email-placeholder-%RANDOM%%RANDOM%.tmp"
    <nul set /p "=unset" > "!PLACEHOLDER_FILE!"
    call gcloud secrets versions add email-smtp-password --data-file="!PLACEHOLDER_FILE!"
    del /f /q "!PLACEHOLDER_FILE!" >nul 2>&1
    echo     Set your Gmail app password:
    echo       echo APP_PASSWORD^| gcloud secrets versions add email-smtp-password --data-file=-
) else (
    echo ==^> Secret email-smtp-password already exists
)

call gcloud storage buckets describe "gs://%GCS_BUCKET%" >nul 2>&1
if errorlevel 1 (
    echo ==^> Creating GCS bucket gs://%GCS_BUCKET%
    call gcloud storage buckets create "gs://%GCS_BUCKET%" --location="%GCP_REGION%"
    if errorlevel 1 exit /b 1
    call gcloud storage buckets update "gs://%GCS_BUCKET%" --uniform-bucket-level-access
    if errorlevel 1 exit /b 1
) else (
    echo ==^> Bucket gs://%GCS_BUCKET% already exists
)

if not defined GCS_PUBLIC_BUCKET set "GCS_PUBLIC_BUCKET=1"
if "%GCS_PUBLIC_BUCKET%"=="1" (
    echo ==^> Granting public read on gs://%GCS_BUCKET%
    call gcloud storage buckets add-iam-policy-binding "gs://%GCS_BUCKET%" ^
      --member=allUsers ^
      --role=roles/storage.objectViewer >nul 2>&1
    if errorlevel 1 (
        echo.
        echo WARNING: Could not grant public read ^(org policy often blocks allUsers^).
        echo          Set GCS_PUBLIC_BUCKET=0 in deploy\gcp\config.bat and redeploy.
        echo          Static files will be served from Cloud Run; media stays on private GCS.
        echo.
    ) else (
        echo ==^> Public bucket access enabled
    )
) else (
    echo ==^> Skipping public bucket access ^(GCS_PUBLIC_BUCKET=0^)
    set "PROJECT_NUMBER="
    for /f "usebackq delims=" %%A in (`gcloud projects describe "%GCP_PROJECT%" --format="value(projectNumber)"`) do set "PROJECT_NUMBER=%%A"
    set "CLOUD_SERVICES_SA=!PROJECT_NUMBER!@cloudservices.gserviceaccount.com"
    echo ==^> Granting load balancer read access to gs://%GCS_BUCKET%
    call gcloud storage buckets add-iam-policy-binding "gs://%GCS_BUCKET%" ^
      --member="serviceAccount:!CLOUD_SERVICES_SA!" ^
      --role="roles/storage.objectViewer" ^
      --quiet >nul 2>&1
    if errorlevel 1 echo     ^(bucket IAM binding may already exist^)
)

call gcloud sql instances describe "%SQL_INSTANCE%" >nul 2>&1
if errorlevel 1 (
    set "DB_PASSWORD="
    for /f "usebackq delims=" %%A in (`gcloud secrets versions access latest --secret=db-password`) do set "DB_PASSWORD=%%A"
    echo ==^> Creating Cloud SQL instance %SQL_INSTANCE%
    call gcloud sql instances create "%SQL_INSTANCE%" ^
      --database-version=POSTGRES_15 ^
      --tier=db-f1-micro ^
      --region="%GCP_REGION%" ^
      --storage-size=10GB ^
      --storage-type=SSD ^
      --backup-start-time=03:00 ^
      --root-password="!DB_PASSWORD!"
    if errorlevel 1 exit /b 1
) else (
    echo ==^> Cloud SQL instance %SQL_INSTANCE% already exists
)

call gcloud sql databases describe "%SQL_DATABASE%" --instance="%SQL_INSTANCE%" >nul 2>&1
if errorlevel 1 (
    echo ==^> Creating database %SQL_DATABASE%
    call gcloud sql databases create "%SQL_DATABASE%" --instance="%SQL_INSTANCE%"
    if errorlevel 1 exit /b 1
)

set "DB_PASSWORD="
for /f "usebackq delims=" %%A in (`gcloud secrets versions access latest --secret=db-password`) do set "DB_PASSWORD=%%A"

set "SQL_USER_EXISTS="
for /f "usebackq delims=" %%A in (`gcloud sql users list --instance="%SQL_INSTANCE%" --format="value(name)"`) do (
    if /i "%%A"=="%SQL_USER%" set "SQL_USER_EXISTS=1"
)

if defined SQL_USER_EXISTS (
    echo ==^> Syncing password for database user %SQL_USER%
    call gcloud sql users set-password "%SQL_USER%" ^
      --instance="%SQL_INSTANCE%" ^
      --password="%DB_PASSWORD%"
    if errorlevel 1 exit /b 1
) else (
    echo ==^> Creating database user %SQL_USER%
    call gcloud sql users create "%SQL_USER%" ^
      --instance="%SQL_INSTANCE%" ^
      --password="%DB_PASSWORD%"
    if errorlevel 1 exit /b 1
)

call gcloud iam service-accounts describe "%SA_EMAIL%" >nul 2>&1
if errorlevel 1 (
    echo ==^> Creating service account %SA_EMAIL%
    call gcloud iam service-accounts create "%SERVICE_ACCOUNT%" ^
      --display-name="Hairitage Cloud Run"
    if errorlevel 1 exit /b 1
)

echo ==^> Waiting for service account to become available...
for /l %%I in (1,1,30) do (
    call gcloud iam service-accounts describe "%SA_EMAIL%" >nul 2>&1
    if not errorlevel 1 goto :sa_available
    timeout /t 2 /nobreak >nul
)
:sa_available

call :grant_member_role "serviceAccount:%SA_EMAIL%" roles/cloudsql.client
if errorlevel 1 exit /b 1
call :grant_member_role "serviceAccount:%SA_EMAIL%" roles/storage.objectAdmin
if errorlevel 1 exit /b 1
call :grant_member_role "serviceAccount:%SA_EMAIL%" roles/secretmanager.secretAccessor
if errorlevel 1 exit /b 1

echo.
echo Infrastructure ready.
echo   Cloud SQL connection: %CONNECTION_NAME%
echo   GCS bucket: gs://%GCS_BUCKET%
echo.
echo Email (optional):
echo   1. Set Gmail app password: echo APP_PASSWORD^| gcloud secrets versions add email-smtp-password --data-file=-
echo   2. Apply to Cloud Run (no rebuild): deploy\gcp\update-email-env.bat
echo.
echo Next: deploy\gcp\deploy.bat

endlocal
exit /b 0

REM ---- subroutine: grant an IAM role to a member, with retries ----
:grant_member_role
setlocal
set "GMR_MEMBER=%~1"
set "GMR_ROLE=%~2"
echo ==^> Granting %GMR_ROLE% to %GMR_MEMBER%
set "GMR_OK="
for /l %%I in (1,1,10) do (
    if not defined GMR_OK (
        call gcloud projects add-iam-policy-binding "%GCP_PROJECT%" ^
          --member="%GMR_MEMBER%" ^
          --role="%GMR_ROLE%" ^
          --quiet >nul 2>&1
        if not errorlevel 1 (
            set "GMR_OK=1"
        ) else (
            timeout /t 3 /nobreak >nul
        )
    )
)
if not defined GMR_OK (
    echo ERROR: Failed to grant %GMR_ROLE% to %GMR_MEMBER%
    endlocal
    exit /b 1
)
endlocal
exit /b 0
