@echo off
setlocal
cd /d "%~dp0"

fltmc >nul 2>&1
if errorlevel 1 (
    echo.
    echo [ERROR] Administrator privileges are required.
    echo Right-click this file and choose "Run as administrator".
    echo.
    pause
    exit /b 1
)

if not exist "%~dp0vs_buildtools.exe" (
    echo.
    echo [ERROR] vs_buildtools.exe was not found next to this script.
    echo.
    pause
    exit /b 1
)

echo.
echo ============================================================
echo  Installing Visual Studio Build Tools
echo  Workload: Desktop development with C++
echo  This may take 10-30 minutes and several GB of disk space.
echo ============================================================
echo.

"%~dp0vs_buildtools.exe" --passive --wait --norestart --nocache --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended

set "RC=%ERRORLEVEL%"
if "%RC%"=="3010" goto build
if not "%RC%"=="0" (
    echo.
    echo [ERROR] Installer exited with code %RC%.
    echo.
    pause
    exit /b %RC%
)

:build
echo.
echo ============================================================
echo  Build Tools installation finished. Building the agents...
echo ============================================================
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build.ps1"
if errorlevel 1 (
    echo.
    echo [ERROR] Build failed. See the messages above.
    echo.
    pause
    exit /b 1
)

echo.
echo Done. The binaries are in the "dist" folder.
echo.
pause
exit /b 0
