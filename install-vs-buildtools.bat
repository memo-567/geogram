@echo off
REM Install Visual Studio 2022 Build Tools with C++ workload
REM Must be run as administrator for system-wide install

echo Installing Visual Studio 2022 Build Tools with C++ Desktop workload...
echo This may take 10-20 minutes depending on your connection.
echo.

winget install Microsoft.VisualStudio.2022.BuildTools --silent --accept-package-agreements --accept-source-agreements --override "--add Microsoft.VisualStudio.Workload.VCTools --includeRecommended --quiet --wait"

if %errorlevel% neq 0 (
    echo.
    echo [WARNING] winget install returned error code %errorlevel%
    echo.
    echo If winget failed, you can install manually:
    echo   1. Go to https://visualstudio.microsoft.com/downloads/
    echo   2. Scroll down to "Build Tools for Visual Studio 2022"
    echo   3. Download and run the installer
    echo   4. Select "Desktop development with C++" workload
    echo   5. Click Install
    echo.
    pause
    exit /b 1
)

echo.
echo [OK] Visual Studio Build Tools installed successfully!
pause
