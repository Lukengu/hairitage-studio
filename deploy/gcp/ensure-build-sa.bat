@echo off
REM Shared setup for the Cloud Build service account.
REM Call from setup-infra.bat and deploy.bat via:
REM   call ensure-build-service-account.bat
REM Requires GCP_PROJECT and GCP_REGION to already be set in the environment.

setlocal EnableDelayedExpansion
goto :ensure_build_service_account

:ensure_build_service_account
if "%GCP_PROJECT%"=="" (
  echo ERROR: GCP_PROJECT is not set >&2
  exit /b 1
)
if "%GCP_REGION%"=="" (
  echo ERROR: GCP_REGION is not set >&2
  exit /b 1
)

if "%BUILD_SERVICE_ACCOUNT%"=="" (set "BUILD_SA_NAME=hairitage-build") else (set "BUILD_SA_NAME=%BUILD_SERVICE_ACCOUNT%")
if "%ARTIFACT_REPO%"=="" (set "ARTIFACT_REPO_NAME=cloud-run-source-deploy") else (set "ARTIFACT_REPO_NAME=%ARTIFACT_REPO%")

set "BUILD_SA_EMAIL=%BUILD_SA_NAME%@%GCP_PROJECT%.iam.gserviceaccount.com"

for /f "usebackq delims=" %%P in (`gcloud projects describe "%GCP_PROJECT%" --format="value(projectNumber)"`) do (
  set "PROJECT_NUMBER=%%P"
)
set "CLOUDBUILD_SA=serviceAccount:!PROJECT_NUMBER!@cloudbuild.gserviceaccount.com"

gcloud iam service-accounts describe "%BUILD_SA_EMAIL%" >nul 2>&1
if errorlevel 1 (
  echo ==^> Creating build service account %BUILD_SA_EMAIL%
  gcloud iam service-accounts create "%BUILD_SA_NAME%" ^
    --display-name="Hairitage Cloud Build"
)

for /l %%I in (1,1,30) do (
  gcloud iam service-accounts describe "%BUILD_SA_EMAIL%" >nul 2>&1
  if not errorlevel 1 goto :sa_ready
  timeout /t 2 /nobreak >nul
)
:sa_ready

for %%R in (roles/storage.admin roles/artifactregistry.writer roles/logging.logWriter roles/cloudbuild.builds.builder) do (
  set "ROLE_BOUND="
  for /l %%I in (1,1,5) do (
    if not defined ROLE_BOUND (
      gcloud projects add-iam-policy-binding "%GCP_PROJECT%" ^
        --member="serviceAccount:%BUILD_SA_EMAIL%" ^
        --role="%%R" ^
        --quiet >nul 2>&1
      if not errorlevel 1 (
        set "ROLE_BOUND=1"
      ) else (
        timeout /t 2 /nobreak >nul
      )
    )
  )
)

gcloud artifacts repositories describe "%ARTIFACT_REPO_NAME%" --location="%GCP_REGION%" >nul 2>&1
if errorlevel 1 (
  gcloud artifacts repositories create "%ARTIFACT_REPO_NAME%" ^
    --repository-format=docker ^
    --location="%GCP_REGION%"
)

for /l %%I in (1,1,5) do (
  gcloud artifacts repositories add-iam-policy-binding "%ARTIFACT_REPO_NAME%" ^
    --location="%GCP_REGION%" ^
    --member="serviceAccount:%BUILD_SA_EMAIL%" ^
    --role="roles/artifactregistry.writer" ^
    --quiet >nul 2>&1
  if not errorlevel 1 goto :repo_binding_done
  timeout /t 2 /nobreak >nul
)
:repo_binding_done

gcloud iam service-accounts add-iam-policy-binding "%BUILD_SA_EMAIL%" ^
  --member="!CLOUDBUILD_SA!" ^
  --role="roles/iam.serviceAccountUser" ^
  --quiet >nul 2>&1

endlocal & (
  set "BUILD_SA_EMAIL=%BUILD_SA_EMAIL%"
  set "BUILD_SA_RESOURCE=projects/%GCP_PROJECT%/serviceAccounts/%BUILD_SA_EMAIL%"
)

exit /b 0
