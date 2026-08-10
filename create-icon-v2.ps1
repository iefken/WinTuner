#========================================================================
# create-icon-v2.ps1 - (re)generate wintuner.ico
#
# Writes a MULTI-SIZE icon (16 -> 256 px). The taskbar, Alt-Tab, the Start
# Menu and the title bar all ask for different pixel sizes; an icon holding
# only 32x32 gets stretched by Windows and looks smeared on any HiDPI
# display. Each frame is rendered at its own size rather than downscaled,
# so the small ones stay crisp.
#
# Frames are stored as PNG (supported inside .ico since Vista) which keeps
# the file small and the alpha channel clean.
#========================================================================

Add-Type -AssemblyName System.Drawing

$sizes    = @(16, 24, 32, 48, 64, 128, 256)
$iconPath = Join-Path $PSScriptRoot "wintuner.ico"

# Render one frame of the logo (blue disc + four white panes) as PNG bytes.
function New-IconFramePng {
    param([int]$Size)

    $bmp = New-Object System.Drawing.Bitmap $Size, $Size
    $g   = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.Clear([System.Drawing.Color]::Transparent)

        # All coordinates are fractions of the frame so every size matches.
        $inset = $Size * 0.0625          # 2/32
        $disc  = $Size * 0.875           # 28/32
        $pane  = $Size * 0.21875         # 7/32
        $near  = $Size * 0.25            # 8/32
        $far   = $Size * 0.53125         # 17/32

        $blue = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(0, 120, 212))
        try   { $g.FillEllipse($blue, $inset, $inset, $disc, $disc) }
        finally { $blue.Dispose() }

        $white = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
        try {
            foreach ($x in @($near, $far)) {
                foreach ($y in @($near, $far)) {
                    $g.FillRectangle($white, $x, $y, $pane, $pane)
                }
            }
        }
        finally { $white.Dispose() }

        $ms = New-Object System.IO.MemoryStream
        try {
            $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
            return $ms.ToArray()
        }
        finally { $ms.Dispose() }
    }
    finally {
        $g.Dispose()
        $bmp.Dispose()
    }
}

try {
    $frames = foreach ($size in $sizes) {
        # Cast back to byte[]: PowerShell unrolls the returned array into the
        # pipeline and would otherwise hand us an Object[], which BinaryWriter
        # silently mangles instead of writing.
        [PSCustomObject]@{ Size = $size; Bytes = [byte[]](New-IconFramePng -Size $size) }
    }

    $fs = [System.IO.FileStream]::new($iconPath, [System.IO.FileMode]::Create)
    $bw = New-Object System.IO.BinaryWriter($fs)
    try {
        # ICONDIR: reserved(0), type(1 = icon), image count
        $bw.Write([UInt16]0)
        $bw.Write([UInt16]1)
        $bw.Write([UInt16]$frames.Count)

        # Pixel data starts after the header + one 16-byte entry per frame.
        $offset = 6 + (16 * $frames.Count)

        foreach ($frame in $frames) {
            # 256 is encoded as 0 in the single-byte width/height fields.
            $dim = if ($frame.Size -ge 256) { 0 } else { $frame.Size }

            $bw.Write([Byte]$dim)                 # width
            $bw.Write([Byte]$dim)                 # height
            $bw.Write([Byte]0)                    # palette colours (0 = truecolour)
            $bw.Write([Byte]0)                    # reserved
            $bw.Write([UInt16]1)                  # colour planes
            $bw.Write([UInt16]32)                 # bits per pixel
            $bw.Write([UInt32]$frame.Bytes.Length)
            $bw.Write([UInt32]$offset)

            $offset += $frame.Bytes.Length
        }

        foreach ($frame in $frames) { $bw.Write($frame.Bytes) }
    }
    finally {
        $bw.Dispose()
        $fs.Dispose()
    }

    Write-Host "ICO written: $iconPath" -ForegroundColor Green
    Write-Host "Frames: $($sizes -join ', ') px  ($((Get-Item $iconPath).Length) bytes)"
}
catch {
    Write-Error "Failed to create the icon: $_"
}
