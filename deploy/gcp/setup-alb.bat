@echo off
REM Windows port of setup-alb.sh
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

for %%V in (GCP_PROJECT GCP_REGION CLOUD_RUN_SERVICE DOMAIN GCS_BUCKET) do (
    if not defined %%V (
        echo ERROR: %%V is not set. Check %CONFIG_FILE%.
        exit /b 1
    )
)

if not defined WWW_DOMAIN set "WWW_DOMAIN=www.%DOMAIN%"

set "IP_NAME=hairitage-alb-ip"
set "NEG_NAME=hairitage-run-neg"
set "BACKEND_NAME=hairitage-run-backend"
set "URL_MAP_NAME=hairitage-url-map"
set "HTTP_REDIRECT_MAP=hairitage-http-redirect"
set "CERT_NAME=hairitage-managed-cert"
set "HTTPS_PROXY_NAME=hairitage-https-proxy"
set "HTTP_PROXY_NAME=hairitage-http-proxy"
set "HTTPS_RULE_NAME=hairitage-https-fr"
set "HTTP_RULE_NAME=hairitage-http-fr"
set "STATIC_BACKEND_BUCKET=hairitage-static-bucket"

call gcloud config set project "%GCP_PROJECT%"
if errorlevel 1 (set "EXITCODE=1" & goto :cleanup)

echo ==^> Enabling Compute API
call gcloud services enable compute.googleapis.com
if errorlevel 1 (set "EXITCODE=1" & goto :cleanup)

call gcloud compute addresses describe "%IP_NAME%" --global >nul 2>&1
if errorlevel 1 (
    echo ==^> Reserving global static IP %IP_NAME%
    call gcloud compute addresses create "%IP_NAME%" --global
    if errorlevel 1 (set "EXITCODE=1" & goto :cleanup)
)

set "LB_IP="
for /f "usebackq delims=" %%A in (`gcloud compute addresses describe "%IP_NAME%" --global --format="value(address)"`) do set "LB_IP=%%A"
echo     Load balancer IP: %LB_IP%

call gcloud compute network-endpoint-groups describe "%NEG_NAME%" --region="%GCP_REGION%" >nul 2>&1
if errorlevel 1 (
    echo ==^> Creating serverless NEG %NEG_NAME%
    call gcloud compute network-endpoint-groups create "%NEG_NAME%" ^
      --region="%GCP_REGION%" ^
      --network-endpoint-type=serverless ^
      --cloud-run-service="%CLOUD_RUN_SERVICE%"
    if errorlevel 1 (set "EXITCODE=1" & goto :cleanup)
)

call gcloud compute backend-services describe "%BACKEND_NAME%" --global >nul 2>&1
if errorlevel 1 (
    echo ==^> Creating backend service %BACKEND_NAME%
    call gcloud compute backend-services create "%BACKEND_NAME%" ^
      --global ^
      --load-balancing-scheme=EXTERNAL_MANAGED ^
      --protocol=HTTP
    if errorlevel 1 (set "EXITCODE=1" & goto :cleanup)
)

set "BACKEND_GROUPS="
for /f "usebackq delims=" %%A in (`gcloud compute backend-services describe "%BACKEND_NAME%" --global --format="value(backends.group)" 2^>nul`) do set "BACKEND_GROUPS=%%A"
echo !BACKEND_GROUPS! | findstr /c:"%NEG_NAME%" >nul
if errorlevel 1 (
    echo ==^> Attaching Cloud Run NEG to backend
    call gcloud compute backend-services add-backend "%BACKEND_NAME%" ^
      --global ^
      --network-endpoint-group="%NEG_NAME%" ^
      --network-endpoint-group-region="%GCP_REGION%"
    if errorlevel 1 (set "EXITCODE=1" & goto :cleanup)
)

call gcloud compute url-maps describe "%URL_MAP_NAME%" --global >nul 2>&1
if errorlevel 1 (
    echo ==^> Creating URL map %URL_MAP_NAME%
    call gcloud compute url-maps create "%URL_MAP_NAME%" ^
      --default-service="%BACKEND_NAME%"
    if errorlevel 1 (set "EXITCODE=1" & goto :cleanup)
)

if not defined GCS_PUBLIC_BUCKET set "GCS_PUBLIC_BUCKET=0"
if "%GCS_PUBLIC_BUCKET%"=="1" (
    call gcloud compute backend-buckets describe "%STATIC_BACKEND_BUCKET%" --global >nul 2>&1
    if errorlevel 1 (
        echo ==^> Creating backend bucket %STATIC_BACKEND_BUCKET% for gs://%GCS_BUCKET%
        call gcloud compute backend-buckets create "%STATIC_BACKEND_BUCKET%" ^
          --gcs-bucket-name="%GCS_BUCKET%" ^
          --enable-cdn
        if errorlevel 1 (set "EXITCODE=1" & goto :cleanup)
    )

    set "PROJECT_NUMBER="
    for /f "usebackq delims=" %%A in (`gcloud projects describe "%GCP_PROJECT%" --format="value(projectNumber)"`) do set "PROJECT_NUMBER=%%A"
    set "CLOUD_SERVICES_SA=!PROJECT_NUMBER!@cloudservices.gserviceaccount.com"
    echo ==^> Granting load balancer read access to gs://%GCS_BUCKET%
    call gcloud storage buckets add-iam-policy-binding "gs://%GCS_BUCKET%" ^
      --member="serviceAccount:!CLOUD_SERVICES_SA!" ^
      --role="roles/storage.objectViewer" ^
      --quiet >nul 2>&1
    if errorlevel 1 echo     ^(bucket IAM binding may already exist^)

    set "PATH_MATCHERS="
    for /f "usebackq delims=" %%A in (`gcloud compute url-maps describe "%URL_MAP_NAME%" --global --format="yaml(pathMatchers)" 2^>nul`) do set "PATH_MATCHERS=!PATH_MATCHERS! %%A"
    echo !PATH_MATCHERS! | findstr /c:"site-routes" >nul
    if errorlevel 1 (
        echo ==^> Routing /static/* to GCS backend bucket
        call gcloud compute url-maps add-path-matcher "%URL_MAP_NAME%" ^
          --path-matcher-name=site-routes ^
          --default-service="%BACKEND_NAME%" ^
          --backend-bucket-path-rules="/static/*=%STATIC_BACKEND_BUCKET%" ^
          --global
        if errorlevel 1 (set "EXITCODE=1" & goto :cleanup)
        call gcloud compute url-maps add-host-rule "%URL_MAP_NAME%" ^
          --hosts="%DOMAIN%,%WWW_DOMAIN%" ^
          --path-matcher-name=site-routes ^
          --global
        if errorlevel 1 (set "EXITCODE=1" & goto :cleanup)
    )
) else (
    echo ==^> Static served by Cloud Run ^(/static/^) with a GCS copy at gs://%GCS_BUCKET%/static/
    echo     ^(Private bucket + org policy: ALB cannot read GCS without public object access.^)
)

call gcloud compute ssl-certificates describe "%CERT_NAME%" --global >nul 2>&1
if errorlevel 1 (
    echo ==^> Creating managed SSL certificate for %DOMAIN% and %WWW_DOMAIN%
    call gcloud compute ssl-certificates create "%CERT_NAME%" ^
      --domains="%DOMAIN%,%WWW_DOMAIN%" ^
      --global
    if errorlevel 1 (set "EXITCODE=1" & goto :cleanup)
)

call gcloud compute target-https-proxies describe "%HTTPS_PROXY_NAME%" --global >nul 2>&1
if errorlevel 1 (
    echo ==^> Creating HTTPS proxy
    call gcloud compute target-https-proxies create "%HTTPS_PROXY_NAME%" ^
      --url-map="%URL_MAP_NAME%" ^
      --ssl-certificates="%CERT_NAME%"
    if errorlevel 1 (set "EXITCODE=1" & goto :cleanup)
)

call gcloud compute forwarding-rules describe "%HTTPS_RULE_NAME%" --global >nul 2>&1
if errorlevel 1 (
    echo ==^> Creating HTTPS forwarding rule
    call gcloud compute forwarding-rules create "%HTTPS_RULE_NAME%" ^
      --global ^
      --target-https-proxy="%HTTPS_PROXY_NAME%" ^
      --address="%IP_NAME%" ^
      --ports=443
    if errorlevel 1 (set "EXITCODE=1" & goto :cleanup)
)

call gcloud compute url-maps describe "%HTTP_REDIRECT_MAP%" --global >nul 2>&1
if errorlevel 1 (
    echo ==^> Creating HTTP to HTTPS redirect
    set "REDIRECT_YAML=%TEMP%\alb-redirect-%RANDOM%%RANDOM%.yaml"
    (
    echo name: %HTTP_REDIRECT_MAP%
    echo defaultUrlRedirect:
    echo   httpsRedirect: true
    echo   redirectResponseCode: MOVED_PERMANENTLY_DEFAULT
    ) > "!REDIRECT_YAML!"
    call gcloud compute url-maps import "%HTTP_REDIRECT_MAP%" --global --quiet --source="!REDIRECT_YAML!"
    set "IMPORT_RC=!errorlevel!"
    del /f /q "!REDIRECT_YAML!" >nul 2>&1
    if !IMPORT_RC! neq 0 (set "EXITCODE=1" & goto :cleanup)
)

call gcloud compute target-http-proxies describe "%HTTP_PROXY_NAME%" --global >nul 2>&1
if errorlevel 1 (
    call gcloud compute target-http-proxies create "%HTTP_PROXY_NAME%" ^
      --url-map="%HTTP_REDIRECT_MAP%"
    if errorlevel 1 (set "EXITCODE=1" & goto :cleanup)
)

call gcloud compute forwarding-rules describe "%HTTP_RULE_NAME%" --global >nul 2>&1
if errorlevel 1 (
    call gcloud compute forwarding-rules create "%HTTP_RULE_NAME%" ^
      --global ^
      --target-http-proxy="%HTTP_PROXY_NAME%" ^
      --address="%IP_NAME%" ^
      --ports=80
    if errorlevel 1 (set "EXITCODE=1" & goto :cleanup)
)

echo ==^> Restricting Cloud Run ingress to load balancer only
call gcloud run services update "%CLOUD_RUN_SERVICE%" ^
  --region="%GCP_REGION%" ^
  --ingress=internal-and-cloud-load-balancing ^
  --quiet
if errorlevel 1 (set "EXITCODE=1" & goto :cleanup)

echo ==^> Allowing load balancer traffic without allUsers (org-policy safe)
call gcloud run services update "%CLOUD_RUN_SERVICE%" ^
  --region="%GCP_REGION%" ^
  --no-invoker-iam-check ^
  --quiet
if errorlevel 1 (set "EXITCODE=1" & goto :cleanup)

set "CERT_STATUS=UNKNOWN"
for /f "usebackq delims=" %%A in (`gcloud compute ssl-certificates describe "%CERT_NAME%" --global --format="value(managed.status)" 2^>nul`) do set "CERT_STATUS=%%A"

echo.
echo ==========================================
echo Application Load Balancer ready
echo ==========================================
echo.
echo Add these DNS records at your .co.za registrar:
echo.
echo   Type: A
echo   Name: @
echo   Value: %LB_IP%
echo.
echo   Type: A
echo   Name: www
echo   Value: %LB_IP%
echo.
echo SSL certificate status: %CERT_STATUS%
echo (Becomes ACTIVE after DNS propagates, usually 15-60 minutes)
echo.
echo Test after DNS + SSL are active:
echo   https://%DOMAIN%
echo   https://%WWW_DOMAIN%
echo.
echo Note: This route avoids Cloud Run domain mapping (not supported in africa-south1)
echo       and avoids allUsers - ingress is LB-only and invoker IAM check is disabled.

:cleanup
endlocal
exit /b %EXITCODE%
