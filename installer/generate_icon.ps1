# generate_icon.ps1 — Render geogram-icon-dark.svg into a high-quality multi-size ICO.
#
# Usage: powershell -ExecutionPolicy Bypass -File installer\generate_icon.ps1
#
# Produces: windows\runner\resources\app_icon.ico
#
# Strategy:
#   1. Inline SVG into HTML, render to 512px PNG via msedge --headless=new
#   2. Fall back to assets\geogram_icon_transparent.png if Edge fails
#   3. Resize to 256, 64, 48, 32, 16 using System.Drawing (HighQualityBicubic)
#   4. Assemble multi-frame ICO binary

param(
    [string]$OutPath  = "windows\runner\resources\app_icon.ico",
    [int[]] $Sizes    = @(256, 64, 48, 32, 16)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Drawing

$tempDir = "build\icon_tmp"
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

# --- Step 1: Get a high-res source PNG -------------------------------------------

$sourcePng = Join-Path $PWD "$tempDir\source_512.png"
$rendered = $false

# Read SVG content and inline it into HTML (avoids file:// issues)
$svgPath = "assets\geogram-icon-dark.svg"

if (Test-Path $svgPath) {
    $svgContent = Get-Content $svgPath -Raw

    # Build HTML with inline SVG, sized to exactly 512x512
    $html = @"
<!DOCTYPE html><html><head><style>
*{margin:0;padding:0}
html,body{width:512px;height:512px;overflow:hidden;background:transparent}
svg{width:512px;height:512px}
</style></head><body>
$svgContent
</body></html>
"@

    $htmlPath = Join-Path $PWD "$tempDir\render.html"
    [System.IO.File]::WriteAllText($htmlPath, $html, [System.Text.Encoding]::UTF8)

    # Find Edge
    $edgePaths = @(
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
        "${env:LOCALAPPDATA}\Microsoft\Edge\Application\msedge.exe"
    )
    $edgeExe = $edgePaths | Where-Object { Test-Path $_ } | Select-Object -First 1

    if ($edgeExe) {
        Write-Host "Rendering SVG with Edge headless..."
        Write-Host "  Edge: $edgeExe"

        # Kill leftover Edge processes
        Get-Process msedge -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500

        $htmlUrl = "file:///" + ($htmlPath -replace '\\', '/')

        $args = @(
            "--headless=new"
            "--disable-gpu"
            "--screenshot=$sourcePng"
            "--window-size=512,512"
            "--force-device-scale-factor=1"
            "--no-first-run"
            "--no-default-browser-check"
            "--disable-extensions"
            "--user-data-dir=$tempDir\edge-profile"
            $htmlUrl
        )

        Write-Host "  URL: $htmlUrl"

        try {
            $proc = Start-Process -FilePath $edgeExe -ArgumentList $args -PassThru -NoNewWindow
            $exited = $proc.WaitForExit(15000)
            if (-not $exited) { $proc.Kill() }
            Start-Sleep -Seconds 1

            if (Test-Path $sourcePng) {
                $img = [System.Drawing.Image]::FromFile($sourcePng)
                $w = $img.Width; $h = $img.Height
                $img.Dispose()

                if ($w -ge 256 -and $h -ge 256) {
                    Write-Host "  SVG rendered: ${w}x${h}"
                    $rendered = $true
                } else {
                    Write-Host "  Screenshot too small: ${w}x${h}, falling back"
                }
            } else {
                Write-Host "  Screenshot file not created, falling back"
            }
        } catch {
            Write-Host "  Edge render failed: $_"
        }
    } else {
        Write-Host "Edge not found, falling back to PNG"
    }
}

if (-not $rendered) {
    $fallback = "assets\geogram_icon_transparent.png"
    if (Test-Path $fallback) {
        Write-Host "Using fallback: $fallback"
        Copy-Item $fallback $sourcePng -Force
    } else {
        Write-Error "No source image found. Place a 512x512 PNG at $fallback"
        exit 1
    }
}

# --- Step 2: Resize to each icon size -------------------------------------------

$sourceImg = [System.Drawing.Image]::FromFile($sourcePng)
Write-Host "Source: $($sourceImg.Width)x$($sourceImg.Height)"

$resizedPngs = @()

foreach ($size in $Sizes) {
    $outPng = Join-Path $PWD "$tempDir\icon_$size.png"

    $bmp = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceOver
    $g.Clear([System.Drawing.Color]::Transparent)
    $g.DrawImage($sourceImg, 0, 0, $size, $size)
    $g.Dispose()

    $bmp.Save($outPng, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()

    $resizedPngs += $outPng
    Write-Host "  Resized: ${size}x${size}"
}

$sourceImg.Dispose()

# --- Step 3: Assemble ICO -------------------------------------------------------

$pngData = @()
foreach ($p in $resizedPngs) {
    $pngData += , [System.IO.File]::ReadAllBytes($p)
}

$count = $Sizes.Count
$headerSize = 6 + ($count * 16)

$ms = New-Object System.IO.MemoryStream
$bw = New-Object System.IO.BinaryWriter($ms)

# ICONDIR
$bw.Write([UInt16]0)       # reserved
$bw.Write([UInt16]1)       # type = ICO
$bw.Write([UInt16]$count)  # image count

# ICONDIRENTRY for each size
$offset = $headerSize
for ($i = 0; $i -lt $count; $i++) {
    $sz = $Sizes[$i]
    $w = if ($sz -ge 256) { 0 } else { $sz }  # 0 means 256
    $bw.Write([byte]$w)          # width
    $bw.Write([byte]$w)          # height
    $bw.Write([byte]0)           # color count
    $bw.Write([byte]0)           # reserved
    $bw.Write([UInt16]1)         # color planes
    $bw.Write([UInt16]32)        # bits per pixel
    $bw.Write([UInt32]$pngData[$i].Length)  # image data size
    $bw.Write([UInt32]$offset)             # offset
    $offset += $pngData[$i].Length
}

# Image data
foreach ($d in $pngData) {
    $bw.Write($d)
}

$bw.Flush()

# Write output
$outDir = Split-Path $OutPath -Parent
if ($outDir -and -not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
}

$outFull = Join-Path $PWD $OutPath
[System.IO.File]::WriteAllBytes($outFull, $ms.ToArray())

$bw.Close()
$ms.Close()

$finalSize = (Get-Item $outFull).Length
Write-Host ""
Write-Host "Created $OutPath ($([math]::Round($finalSize / 1KB, 1)) KB) with sizes: $($Sizes -join ', ')"
