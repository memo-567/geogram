@echo off
setlocal enabledelayedexpansion
title Geogram Desktop Launcher

REM Geogram Desktop Launch Script for Windows
REM Double-click from File Explorer or run from command line

REM ============================================================
REM Navigate to script directory FIRST
REM ============================================================
cd /d "%~dp0"

REM ============================================================
REM Configuration
REM ============================================================
set "FLUTTER_VERSION=3.38.5"
set "FLUTTER_HOME=%USERPROFILE%\flutter"
set "FLUTTER_BIN=%FLUTTER_HOME%\bin\flutter.bat"
set "ONNX_VERSION=1.21.0"

REM ============================================================
REM Check for Flutter
REM ============================================================
if exist call "%FLUTTER_BIN%" (
    echo [OK] Flutter found at %FLUTTER_HOME%
    goto :flutter_found
)

REM Check if flutter is in PATH already
where flutter.bat >nul 2>&1
if !errorlevel!==0 (
    for /f "tokens=*" %%i in ('where flutter.bat') do set "FLUTTER_BIN=%%i"
    echo [OK] Flutter found in PATH: !FLUTTER_BIN!
    goto :flutter_found
)

echo.
echo [ERROR] Flutter not found at %FLUTTER_HOME% or in PATH
echo.
echo Please install Flutter %FLUTTER_VERSION% for Windows:
echo   1. Download from https://docs.flutter.dev/get-started/install/windows/desktop
echo   2. Extract to %FLUTTER_HOME%
echo   3. Or run: git clone -b %FLUTTER_VERSION% https://github.com/flutter/flutter.git "%FLUTTER_HOME%"
echo.
pause
exit /b 1

:flutter_found

REM ============================================================
REM Check Developer Mode (required for symlink support)
REM ============================================================
set "DEVMODE=0"
for /f "tokens=3" %%a in ('reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" /v AllowDevelopmentWithoutDevLicense 2^>nul') do (
    if "%%a"=="0x1" set "DEVMODE=1"
)
if "!DEVMODE!"=="0" (
    echo.
    echo [WARNING] Windows Developer Mode is not enabled.
    echo Flutter plugins require symlink support which needs Developer Mode.
    echo.
    echo To enable: Settings ^> Update and Security ^> For developers ^> Developer Mode
    echo.
    pause
    exit /b 1
)
echo [OK] Developer Mode enabled

REM ============================================================
REM Check for Visual Studio (required for Windows desktop builds)
REM ============================================================
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" (
    echo.
    echo [ERROR] Visual Studio not found.
    echo Windows desktop builds require Visual Studio with the
    echo "Desktop development with C++" workload installed.
    echo.
    echo Download from: https://visualstudio.microsoft.com/downloads/
    echo.
    pause
    exit /b 1
)

set "VS_PATH="
for /f "tokens=*" %%i in ('"%VSWHERE%" -latest -products * -property installationPath 2^>nul') do set "VS_PATH=%%i"
if not defined VS_PATH (
    echo.
    echo [ERROR] Visual Studio installation not detected.
    echo.
    pause
    exit /b 1
)
echo [OK] Visual Studio found
echo [..] Preparing build environment...

REM Kill any existing geogram processes
%SystemRoot%\System32\taskkill.exe /f /im geogram.exe >nul 2>&1

REM Enable Windows desktop support
call "%FLUTTER_BIN%" config --enable-windows-desktop >nul 2>&1
echo [OK] Windows desktop enabled

REM ============================================================
REM Handle flags: --clean, --release
REM ============================================================
set "DO_CLEAN=0"
set "BUILD_MODE=debug"
set "FLUTTER_ARGS="
for %%a in (%*) do (
    if "%%a"=="--clean" (
        set "DO_CLEAN=1"
    ) else if "%%a"=="--release" (
        set "BUILD_MODE=release"
    ) else (
        set "FLUTTER_ARGS=!FLUTTER_ARGS! %%a"
    )
)

if "!DO_CLEAN!"=="1" (
    echo [..] Cleaning previous build...
    call "%FLUTTER_BIN%" clean
)

REM ============================================================
REM Get dependencies
REM ============================================================
echo [..] Getting dependencies...
call "%FLUTTER_BIN%" pub get
if !errorlevel! neq 0 (
    echo.
    echo [ERROR] Failed to get dependencies.
    echo.
    pause
    exit /b 1
)
echo [OK] Dependencies ready

REM ============================================================
REM Pre-download ONNX Runtime if not already cached
REM ============================================================
set "ONNX_DIR=build\windows\x64\plugins\flutter_onnxruntime\onnxruntime"
set "ONNX_EXTRACT_DIR=%ONNX_DIR%\onnxruntime-win-x64-%ONNX_VERSION%"
set "ONNX_CACHE=windows\onnx-cache"

if exist "%ONNX_EXTRACT_DIR%\lib\onnxruntime.dll" (
    echo [OK] ONNX Runtime v%ONNX_VERSION% already available
    goto :build_app
)

if exist "%ONNX_CACHE%\onnxruntime-win-x64-%ONNX_VERSION%" (
    echo [..] Restoring ONNX Runtime from local cache...
    if not exist "%ONNX_DIR%" mkdir "%ONNX_DIR%"
    xcopy /e /i /q /y "%ONNX_CACHE%\onnxruntime-win-x64-%ONNX_VERSION%" "%ONNX_EXTRACT_DIR%" >nul
    echo [OK] ONNX Runtime restored from cache
    goto :build_app
)

echo [..] Downloading ONNX Runtime v%ONNX_VERSION%...
if not exist "%ONNX_DIR%" mkdir "%ONNX_DIR%"
set "ONNX_URL=https://github.com/microsoft/onnxruntime/releases/download/v%ONNX_VERSION%/onnxruntime-win-x64-%ONNX_VERSION%.zip"
set "ONNX_ZIP=%ONNX_DIR%\onnxruntime.zip"

curl -L "%ONNX_URL%" -o "%ONNX_ZIP%" 2>nul
if !errorlevel! neq 0 (
    echo [WARNING] Failed to download ONNX Runtime. Continuing anyway...
    goto :build_app
)

echo [..] Extracting ONNX Runtime...
tar -xf "%ONNX_ZIP%" -C "%ONNX_DIR%" 2>nul
if !errorlevel! neq 0 (
    powershell -Command "Expand-Archive -Path '%ONNX_ZIP%' -DestinationPath '%ONNX_DIR%' -Force" 2>nul
)

if exist "%ONNX_EXTRACT_DIR%\lib\onnxruntime.dll" (
    echo [OK] ONNX Runtime v%ONNX_VERSION% ready
    if not exist "%ONNX_CACHE%" mkdir "%ONNX_CACHE%"
    xcopy /e /i /q /y "%ONNX_EXTRACT_DIR%" "%ONNX_CACHE%\onnxruntime-win-x64-%ONNX_VERSION%" >nul
) else (
    echo [WARNING] ONNX Runtime extraction may have failed. Continuing...
)
del "%ONNX_ZIP%" 2>nul

:build_app
REM ============================================================
REM Build the app
REM ============================================================
echo.

if "!BUILD_MODE!"=="release" goto :build_release
set "BUILD_DIR=build\windows\x64\runner\Debug"
echo [..] Building Geogram Desktop - debug mode
echo     First build takes several minutes, please wait...
echo.
call "%FLUTTER_BIN%" build windows --debug --no-pub !FLUTTER_ARGS!
goto :build_done

:build_release
set "BUILD_DIR=build\windows\x64\runner\Release"
echo [..] Building Geogram Desktop - release mode
echo     First build takes several minutes, please wait...
echo.
call "%FLUTTER_BIN%" build windows --release --no-pub !FLUTTER_ARGS!

:build_done
if !errorlevel! neq 0 (
    echo.
    echo [ERROR] Build failed!
    echo.
    pause
    exit /b 1
)

REM ============================================================
REM Launch the exe directly
REM ============================================================
set "EXE_PATH=!BUILD_DIR!\geogram.exe"

if not exist "!EXE_PATH!" (
    echo [ERROR] Built executable not found at !EXE_PATH!
    echo.
    pause
    exit /b 1
)

echo.
echo [OK] Build successful
echo [>>] Launching Geogram Desktop...
echo.

start "" "!EXE_PATH!"

%SystemRoot%\System32\timeout.exe /t 2 /nobreak >nul
echo [OK] Geogram Desktop is running. This window will close shortly.
%SystemRoot%\System32\timeout.exe /t 3 /nobreak >nul
endlocal
