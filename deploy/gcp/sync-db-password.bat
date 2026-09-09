@echo off
REM Windows port of sync-db-password.sh
setlocal EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "CONFIG_FILE=%SCRIPT_DIR%\config.bat"

if not exist "%CONFIG_FILE%" (
    echo Missing %CONFIG_FILE%. Copy deploy\gcp\config.example.bat to deploy\gcp\config.bat first.
    exit /b 1
)
call "%CONFIG_FILE%"

for %%V in (GCP_PROJECT SQL_INSTANCE SQL_USER) do (
    if not defined %%V (
        echo ERROR: %%V is not set. Check %CONFIG_FILE%.
        exit /b 1
    )
)

echo ==^> Syncing Cloud SQL password for %SQL_USER% from Secret Manager
call gcloud config set project "%GCP_PROJECT%" >nul
if errorlevel 1 exit /b 1

set "DB_PASSWORD="
for /f "usebackq delims=" %%A in (`gcloud secrets versions access latest --secret=db-password`) do set "DB_PASSWORD=%%A"
if not defined DB_PASSWORD (
    echo ERROR: could not read db-password from Secret Manager.
    exit /b 1
)

call gcloud sql users set-password "%SQL_USER%" ^
  --instance="%SQL_INSTANCE%" ^
  --password="%DB_PASSWORD%"
if errorlevel 1 exit /b 1

echo ==^> Password synced for %SQL_USER%@%SQL_INSTANCE%

if defined CLOUD_RUN_SERVICE if defined GCP_REGION (
    echo ==^> Restarting Cloud Run service %CLOUD_RUN_SERVICE% to pick up DB access
    call gcloud run services update "%CLOUD_RUN_SERVICE%" ^
      --region="%GCP_REGION%" ^
      --project="%GCP_PROJECT%" ^
      --update-secrets="SQL_PASSWORD=db-password:latest" ^
      --quiet
    if errorlevel 1 exit /b 1
)

if not defined CLOUD_RUN_SERVICE set "CLOUD_RUN_SERVICE=hairitage-web"
if not defined GCP_REGION set "GCP_REGION=africa-south1"
echo Done. Test with: gcloud run services proxy %CLOUD_RUN_SERVICE% --region=%GCP_REGION%

endlocal
exit /b 0
