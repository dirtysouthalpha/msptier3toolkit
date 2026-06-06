<#
.SYNOPSIS
    Generate Sentinel Recon PNG icons for PWA manifest.
.DESCRIPTION
    Creates icon-192.png and icon-512.png using System.Drawing.
    Draws the crosshair/reticle logo in Sentinel Cyan on dark navy.
#>
param(
    [string]$OutputDir = "$PSScriptRoot\..\assets"
)

Add-Type -AssemblyName System.Drawing

$sizes = @(192, 512)
$cyan = [System.Drawing.Color]::FromArgb(0, 240, 255)
$bg = [System.Drawing.Color]::FromArgb(5, 6, 8)

foreach ($size in $sizes) {
    $bmp = New-Object System.Drawing.Bitmap($size, $size)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear($bg)

    $center = $size / 2
    $radius = [int]($size * 0.40)
    $lineWidth = [int][Math]::Max(2, $size * 0.025)
    $pen = New-Object System.Drawing.Pen($cyan, $lineWidth)

    # Outer circle
    $g.DrawEllipse($pen, $center - $radius, $center - $radius, $radius * 2, $radius * 2)

    # Inner circle (subtle)
    $innerPen = New-Object System.Drawing.Pen($cyan, [int]($lineWidth * 0.6))
    $innerR = [int]($radius * 0.15)
    # Skip inner, just keep it clean

    # Crosshair lines
    $g.DrawLine($pen, 0, $center, $size, $center)
    $g.DrawLine($pen, $center, 0, $center, $size)

    # Center dot
    $dotSize = [int]($size * 0.06)
    $dotBrush = New-Object System.Drawing.SolidBrush($cyan)
    $g.FillEllipse($dotBrush, $center - $dotSize/2, $center - $dotSize/2, $dotSize, $dotSize)

    # Scanning arc (top right quadrant arc)
    $arcPen = New-Object System.Drawing.Pen($cyan, [int]($lineWidth * 1.5))
    $arcPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $arcPen.EndCap = [System.Drawing.Drawing2D.LineCap]::ArrowAnchor
    $g.DrawArc($arcPen, $center - $radius, $center - $radius, $radius * 2, $radius * 2, -45, 90)

    $outPath = Join-Path $OutputDir "icon-$size.png"
    $bmp.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
    Write-Host "Created: $outPath ($size x $size)"

    $g.Dispose()
    $bmp.Dispose()
    $pen.Dispose()
    $dotBrush.Dispose()
    $arcPen.Dispose()
    $innerPen.Dispose()
}

Write-Host "Icon generation complete." -ForegroundColor Green
