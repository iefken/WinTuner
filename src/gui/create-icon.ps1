Add-Type -AssemblyName System.Drawing

# Create a 64x64 bitmap
$bmp = New-Object System.Drawing.Bitmap 64, 64
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

# Clear with transparent background
$g.Clear([System.Drawing.Color]::Transparent)

# Draw blue circle
$brush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(0, 120, 212))
$g.FillEllipse($brush, 2, 2, 60, 60)

# Draw white rectangles (Windows logo)
$whiteBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
$g.FillRectangle($whiteBrush, 18, 18, 14, 14)
$g.FillRectangle($whiteBrush, 36, 18, 14, 14)
$g.FillRectangle($whiteBrush, 18, 36, 14, 14)
$g.FillRectangle($whiteBrush, 36, 36, 14, 14)

# Draw tuning indicator lines
$pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::White), 2
$g.DrawLine($pen, 34, 10, 34, 14)
$g.DrawLine($pen, 34, 54, 34, 58)
$g.DrawLine($pen, 10, 34, 14, 34)
$g.DrawLine($pen, 54, 34, 58, 34)

# Convert to icon
$icon = [System.Drawing.Icon]::FromHandle($bmp.GetHicon())

# Save as ICO file
$iconPath = Join-Path $PSScriptRoot "wintuner.ico"
$fileStream = [System.IO.File]::Open($iconPath, [System.IO.FileMode]::Create)
$icon.Save($fileStream)
$fileStream.Close()

# Cleanup
$bmp.Dispose()
$g.Dispose()

Write-Host "ICO file created successfully at: $iconPath"
