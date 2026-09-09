@echo off
REM Windows port of map-domain.sh
setlocal EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

echo Cloud Run domain mapping is NOT supported in africa-south1.
echo Using Application Load Balancer instead...
echo.

call "%SCRIPT_DIR%\setup-alb.bat"
set "EXITCODE=%errorlevel%"
endlocal
exit /b %EXITCODE%
