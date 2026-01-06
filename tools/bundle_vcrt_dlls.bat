@echo off
REM Bundle Visual C++ Runtime DLLs for Geogram Windows distribution
REM Run this script from the tools directory after building with 'flutter build windows'

setlocal enabledelayedexpansion

set "TARGET_DIR=..\build\windows\x64\runner\Release"

if not exist "%TARGET_DIR%" (
    echo Error: Build directory not found at %TARGET_DIR%
    echo Please run 'flutter build windows' first.
    pause
    exit /b 1
)

echo Bundling Visual C++ Runtime DLLs...

set COPIED=0
for %%d in (msvcp140.dll msvcp140_1.dll vcruntime140.dll vcruntime140_1.dll) do (
    if exist "%SystemRoot%\System32\%%d" (
        copy /y "%SystemRoot%\System32\%%d" "%TARGET_DIR%\" >nul 2>&1
        if !errorlevel! equ 0 (
            echo   Copied: %%d
            set /a COPIED+=1
        )
    ) else (
        echo   Warning: %%d not found in System32
    )
)

echo.
if %COPIED% geq 4 (
    echo Success! All DLLs bundled to: %TARGET_DIR%
) else if %COPIED% gtr 0 (
    echo Partially complete: %COPIED% of 4 DLLs copied.
    echo Install Visual C++ Redistributable for missing DLLs:
    echo   https://aka.ms/vs/17/release/vc_redist.x64.exe
) else (
    echo No DLLs found. Please install Visual C++ Redistributable:
    echo   https://aka.ms/vs/17/release/vc_redist.x64.exe
)

pause
