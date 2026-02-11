@echo off
setlocal enabledelayedexpansion
REM Geogram Desktop - Windows Build Script
REM Usage: build-windows.bat [--release] [--installer]
REM   --release    Build in release mode (default is debug)
REM   --installer  After building, compile Inno Setup installer (requires Inno Setup 6)

set BUILD_MODE=debug
set BUILD_INSTALLER=0

:parse_args
if "%~1"=="" goto args_done
if /i "%~1"=="--release" set BUILD_MODE=release
if /i "%~1"=="--installer" set BUILD_INSTALLER=1
shift
goto parse_args
:args_done

echo Building Geogram Desktop for Windows (%BUILD_MODE%)...
echo.

REM Add Flutter to PATH if not already there
set PATH=%PATH%;%USERPROFILE%\flutter\bin

REM Clean previous build
echo Cleaning previous build...
call flutter clean

REM Get dependencies
echo Getting dependencies...
call flutter pub get

REM Build Windows
echo Building Windows %BUILD_MODE%...
call flutter build windows --%BUILD_MODE%

if errorlevel 1 (
    echo.
    echo Build FAILED.
    pause
    exit /b 1
)

echo.
echo Build complete!
echo Executable: build\windows\x64\runner\Release\geogram.exe
echo.

if %BUILD_INSTALLER%==0 goto done

REM --- Installer build ---
set "ISCC=C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
if not exist "!ISCC!" (
    echo Inno Setup 6 not found at: !ISCC!
    echo.
    echo Download it from: https://jrsoftware.org/isdl.php
    echo After installing, re-run this script with --installer.
    pause
    exit /b 1
)

REM Extract version from pubspec.yaml
for /f "tokens=2 delims= " %%v in ('findstr /b "version:" pubspec.yaml') do (
    for /f "tokens=1 delims=+" %%a in ("%%v") do set APP_VERSION=%%a
)
echo Building installer for version !APP_VERSION!...

"!ISCC!" /DMyAppVersion=!APP_VERSION! installer\geogram.iss

if errorlevel 1 (
    echo.
    echo Installer build FAILED.
    pause
    exit /b 1
)

echo.
echo Installer created: build\installer\geogram-windows-x64-setup.exe

:done
echo.
pause
