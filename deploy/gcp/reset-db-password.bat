@echo off
REM Windows port of reset-db-password.sh
REM Usage: deploy\gcp\reset-db-password.bat [password]
setlocal EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
for %%I in ("%SCRIPT_DIR%\..\..") do set "REPO_ROOT=%%~fI"
set "CONFIG_FILE=%SCRIPT_DIR%\config.bat"

if not exist "%CONFIG_FILE%" (
    echo Missing %CONFIG_FILE%. Copy deploy\gcp\config.example.bat to deploy\gcp\config.bat first.
    exit /b 1
)
call "%CONFIG_FILE%"

for %%V in (GCP_PROJECT GCP_REGION SQL_INSTANCE SQL_USER) do (
    if not defined %%V (
        echo ERROR: %%V is not set. Check %CONFIG_FILE%.
        exit /b 1
    )
)

set "PASSWORD=%~1"

if not defined PASSWORD (
    if exist "%REPO_ROOT%\.env.production" (
        for /f "usebackq tokens=1,* delims==" %%A in (`findstr /b "SQL_PASSWORD=" "%REPO_ROOT%\.env.production"`) do (
            set "PASSWORD=%%B"
        )
    )
)

if not defined PASSWORD (
    for /f "usebackq delims=" %%P in (`python3 -c "import secrets; print(secrets.token_urlsafe(24), end='')"`) do set "PASSWORD=%%P"
    echo Generated a new password.
)

echo ==^> Updating Secret Manager (db-password)
set "PWD_FILE=%TEMP%\dbpwd-%RANDOM%%RANDOM%.tmp"
<nul set /p "=%PASSWORD%" > "%PWD_FILE%"
call gcloud secrets versions add db-password ^
  --project="%GCP_PROJECT%" ^
  --data-file="%PWD_FILE%"
if errorlevel 1 (
    del /f /q "%PWD_FILE%" >nul 2>&1
    exit /b 1
)
del /f /q "%PWD_FILE%" >nul 2>&1

echo ==^> Updating Cloud SQL user %SQL_USER%
call gcloud sql users set-password "%SQL_USER%" ^
  --instance="%SQL_INSTANCE%" ^
  --project="%GCP_PROJECT%" ^
  --password="%PASSWORD%"
if errorlevel 1 exit /b 1

if defined CLOUD_RUN_SERVICE (
    echo ==^> Restarting Cloud Run service %CLOUD_RUN_SERVICE%
    call gcloud run services update "%CLOUD_RUN_SERVICE%" ^
      --region="%GCP_REGION%" ^
      --project="%GCP_PROJECT%" ^
      --update-secrets="SQL_PASSWORD=db-password:latest" ^
      --quiet
    if errorlevel 1 exit /b 1
)

echo.
echo Done. Secret Manager, Cloud SQL, and Cloud Run now use the same password.
if defined CLOUD_RUN_SERVICE (
    echo Test: gcloud run services proxy %CLOUD_RUN_SERVICE% --region=%GCP_REGION%
) else (
    echo Test: gcloud run services proxy hairitage-web --region=%GCP_REGION%
)

endlocal
exit /b 0
