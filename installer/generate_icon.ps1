# generate_icon.ps1 — Convert geogram_icon_transparent.png into a high-quality multi-size ICO.
#
# Usage: powershell -ExecutionPolicy Bypass -File installer\generate_icon.ps1
#
# Produces: windows\runner\resources\app_icon.ico
# Source:   assets\geogram_icon_transparent.png (512x512, 32-bit ARGB)

param(
    [string]$SourcePng = "assets\geogram_icon_transparent.png",
    [string]$OutPath   = "windows\runner\resources\app_icon.ico",
    [int[]] $Sizes     = @(256, 64, 48, 32, 16)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Drawing

if (-not (Test-Path $SourcePng)) {
    Write-Error "Source image not found: $SourcePng"
    exit 1
}

# --- Step 1: Resize to each icon size -------------------------------------------

$sourceImg = [System.Drawing.Image]::FromFile((Resolve-Path $SourcePng).Path)
Write-Host "Source: $SourcePng ($($sourceImg.Width)x$($sourceImg.Height))"

$pngFrames = @()

foreach ($size in $Sizes) {
    $bmp = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $g.Clear([System.Drawing.Color]::Transparent)
    $g.DrawImage($sourceImg, 0, 0, $size, $size)
    $g.Dispose()

    # Save to memory stream as PNG
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $pngFrames += , $ms.ToArray()
    $ms.Close()
    $bmp.Dispose()

    Write-Host "  Resized: ${size}x${size} ($($pngFrames[-1].Length) bytes)"
}

$sourceImg.Dispose()

# --- Step 2: Assemble ICO -------------------------------------------------------

$count = $Sizes.Count
$headerSize = 6 + ($count * 16)

$ico = New-Object System.IO.MemoryStream
$bw = New-Object System.IO.BinaryWriter($ico)

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
    $bw.Write([UInt32]$pngFrames[$i].Length)  # image data size
    $bw.Write([UInt32]$offset)               # offset
    $offset += $pngFrames[$i].Length
}

# Image data
foreach ($d in $pngFrames) {
    $bw.Write($d)
}

$bw.Flush()

# Write output
$outFull = Join-Path $PWD $OutPath
$outDir = Split-Path $outFull -Parent
if (-not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
}
[System.IO.File]::WriteAllBytes($outFull, $ico.ToArray())

$bw.Close()
$ico.Close()

$finalSize = (Get-Item $outFull).Length
Write-Host ""
Write-Host "Created $OutPath ($([math]::Round($finalSize / 1KB, 1)) KB) with sizes: $($Sizes -join ', ')"
