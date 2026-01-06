# Bundle Visual C++ Runtime DLLs for Geogram Windows distribution
# Run this script on Windows after building with: powershell -ExecutionPolicy Bypass -File bundle_vcrt_dlls.ps1

$ErrorActionPreference = "Stop"

# Target directory (Flutter Windows release build)
$targetDir = "..\build\windows\x64\runner\Release"

if (-not (Test-Path $targetDir)) {
    Write-Host "Error: Build directory not found at $targetDir" -ForegroundColor Red
    Write-Host "Please run 'flutter build windows' first." -ForegroundColor Yellow
    exit 1
}

# Required DLLs
$dlls = @(
    "msvcp140.dll",
    "msvcp140_1.dll",
    "vcruntime140.dll",
    "vcruntime140_1.dll"
)

# Possible source locations
$sourcePaths = @(
    "$env:SystemRoot\System32",
    "$env:VCToolsRedistDir\x64\Microsoft.VC143.CRT",
    "$env:VCToolsRedistDir\x64\Microsoft.VC142.CRT",
    "${env:ProgramFiles}\Microsoft Visual Studio\2022\Community\VC\Redist\MSVC\*\x64\Microsoft.VC143.CRT",
    "${env:ProgramFiles}\Microsoft Visual Studio\2022\BuildTools\VC\Redist\MSVC\*\x64\Microsoft.VC143.CRT",
    "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\BuildTools\VC\Redist\MSVC\*\x64\Microsoft.VC143.CRT"
)

Write-Host "Bundling Visual C++ Runtime DLLs..." -ForegroundColor Cyan

$copied = 0
foreach ($dll in $dlls) {
    $found = $false

    foreach ($sourcePath in $sourcePaths) {
        $resolvedPaths = Resolve-Path $sourcePath -ErrorAction SilentlyContinue
        foreach ($resolved in $resolvedPaths) {
            $sourceFile = Join-Path $resolved $dll
            if (Test-Path $sourceFile) {
                $destFile = Join-Path $targetDir $dll
                Copy-Item $sourceFile $destFile -Force
                Write-Host "  Copied: $dll" -ForegroundColor Green
                $found = $true
                $copied++
                break
            }
        }
        if ($found) { break }
    }

    if (-not $found) {
        Write-Host "  Warning: $dll not found" -ForegroundColor Yellow
    }
}

if ($copied -eq $dlls.Count) {
    Write-Host "`nSuccess! All $copied DLLs bundled to: $targetDir" -ForegroundColor Green
} elseif ($copied -gt 0) {
    Write-Host "`nPartially complete: $copied of $($dlls.Count) DLLs copied." -ForegroundColor Yellow
    Write-Host "Install Visual C++ Redistributable for missing DLLs:" -ForegroundColor Yellow
    Write-Host "  https://aka.ms/vs/17/release/vc_redist.x64.exe" -ForegroundColor Cyan
} else {
    Write-Host "`nNo DLLs found. Please install Visual C++ Redistributable:" -ForegroundColor Red
    Write-Host "  https://aka.ms/vs/17/release/vc_redist.x64.exe" -ForegroundColor Cyan
}
