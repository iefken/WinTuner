Add-Type -AssemblyName System.Drawing

# Create a simple 32x32 icon (standard size)
$bmp = New-Object System.Drawing.Bitmap 32, 32
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

# Clear with transparent background
$g.Clear([System.Drawing.Color]::Transparent)

# Draw blue circle
$brush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(0, 120, 212))
$g.FillEllipse($brush, 2, 2, 28, 28)

# Draw white rectangles (Windows logo - simplified)
$whiteBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
$g.FillRectangle($whiteBrush, 8, 8, 7, 7)
$g.FillRectangle($whiteBrush, 17, 8, 7, 7)
$g.FillRectangle($whiteBrush, 8, 17, 7, 7)
$g.FillRectangle($whiteBrush, 17, 17, 7, 7)

# Convert to icon using proper method
$iconHandle = $bmp.GetHicon()
$icon = [System.Drawing.Icon]::FromHandle($iconHandle)

# Save as ICO file using proper stream
$iconPath = Join-Path $PSScriptRoot "wintuner.ico"
$fileStream = [System.IO.FileStream]::new($iconPath, [System.IO.FileMode]::Create)
try {
    $icon.Save($fileStream)
} finally {
    $fileStream.Dispose()
}

# Cleanup
$bmp.Dispose()
$g.Dispose()

Write-Host "ICO file created successfully at: $iconPath"
Write-Host "File exists: $([System.IO.File]::Exists($iconPath))"
