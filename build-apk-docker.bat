@echo off
chcp 65001 >nul
setlocal
echo ============================================
echo  M-Music APK build (Docker)
echo  First run downloads ~3GB Flutter image
echo ============================================
echo.
set "HERE=%~dp0"
if "%HERE:~-1%"=="\" set "HERE=%HERE:~0,-1%"
echo Project dir: %HERE%
echo.
docker run --rm -v "%HERE%:/proj" -w /proj ghcr.io/cirruslabs/flutter:3.32.0 bash /proj/build.sh
if errorlevel 1 goto fail
goto done
:fail
echo.
echo [BUILD FAILED] Common fixes:
echo   1. Docker Desktop not running - start it and wait for green "Engine running"
echo   2. Image tag missing - change flutter:3.32.0 to flutter:stable in this file
echo   3. Mount denied - Docker Desktop Settings, Resources, File sharing, allow this drive
echo   4. Send the last lines of output to Claude
:done
pause
