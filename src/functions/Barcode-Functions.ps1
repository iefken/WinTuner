#========================================================================
# Barcode / QR Code generation  (100% local - no network, ever)
#
# Backed by ZXing.Net (Apache-2.0), bundled under lib/. See lib/README.md.
# The previous implementation GET'd api.qrserver.com, which meant the text
# being encoded left the machine and a render could not happen offline.
# Nothing in this file touches the network.
#
# Everything is written format-first rather than QR-first, so adding another
# symbology to the UI later is a row in $script:BarcodeFormats, not a rewrite.
#========================================================================

# Formats ZXing can actually WRITE. Its BarcodeFormat enum also contains
# decode-only entries (MAXICODE, RSS_14, RSS_EXPANDED, IMB, PHARMA_CODE,
# All_1D, UPC_EAN_EXTENSION) - asking those to encode throws
# "No encoder available for format X", so they are deliberately absent.
#
#   Key         - stable id used in code/config
#   Display     - what a UI shows
#   ZXing       - BarcodeFormat enum member
#   Dimensions  - '2D' (square) or '1D' (wide and short)
#   Hint        - input rules, shown when encoding fails
$script:BarcodeFormats = @(
    [pscustomobject]@{ Key = 'QR_CODE';     Display = 'QR Code';     ZXing = 'QR_CODE';     Dimensions = '2D'; Hint = 'Any text or URL.' }
    [pscustomobject]@{ Key = 'AZTEC';       Display = 'Aztec';       ZXing = 'AZTEC';       Dimensions = '2D'; Hint = 'Any text.' }
    [pscustomobject]@{ Key = 'DATA_MATRIX'; Display = 'Data Matrix'; ZXing = 'DATA_MATRIX'; Dimensions = '2D'; Hint = 'Any text.' }
    [pscustomobject]@{ Key = 'PDF_417';     Display = 'PDF417';      ZXing = 'PDF_417';     Dimensions = '2D'; Hint = 'Any text.' }
    [pscustomobject]@{ Key = 'CODE_128';    Display = 'Code 128';    ZXing = 'CODE_128';    Dimensions = '1D'; Hint = 'ASCII characters.' }
    [pscustomobject]@{ Key = 'CODE_39';     Display = 'Code 39';     ZXing = 'CODE_39';     Dimensions = '1D'; Hint = 'Digits, A-Z (upper case) and - . $ / + % space.' }
    [pscustomobject]@{ Key = 'CODE_93';     Display = 'Code 93';     ZXing = 'CODE_93';     Dimensions = '1D'; Hint = 'Digits, A-Z (upper case) and - . $ / + % space.' }
    [pscustomobject]@{ Key = 'CODABAR';     Display = 'Codabar';     ZXing = 'CODABAR';     Dimensions = '1D'; Hint = 'Digits, wrapped in a start/stop letter A-D (e.g. A12345A).' }
    [pscustomobject]@{ Key = 'EAN_13';      Display = 'EAN-13';      ZXing = 'EAN_13';      Dimensions = '1D'; Hint = 'Exactly 13 digits (or 12 - the check digit is added).' }
    [pscustomobject]@{ Key = 'EAN_8';       Display = 'EAN-8';       ZXing = 'EAN_8';       Dimensions = '1D'; Hint = 'Exactly 8 digits (or 7 - the check digit is added).' }
    [pscustomobject]@{ Key = 'UPC_A';       Display = 'UPC-A';       ZXing = 'UPC_A';       Dimensions = '1D'; Hint = 'Exactly 12 digits (or 11 - the check digit is added).' }
    [pscustomobject]@{ Key = 'UPC_E';       Display = 'UPC-E';       ZXing = 'UPC_E';       Dimensions = '1D'; Hint = 'Exactly 8 digits (or 7 - the check digit is added).' }
    [pscustomobject]@{ Key = 'ITF';         Display = 'ITF';         ZXing = 'ITF';         Dimensions = '1D'; Hint = 'Digits only, and an even number of them.' }
    [pscustomobject]@{ Key = 'MSI';         Display = 'MSI';         ZXing = 'MSI';         Dimensions = '1D'; Hint = 'Digits only.' }
)

function Get-BarcodeFormats {
    <#
    .SYNOPSIS
        Lists the barcode formats this app can generate.

    .DESCRIPTION
        Returns one object per supported format (Key, Display, ZXing,
        Dimensions, Hint). Bind it straight to a ComboBox to let the user pick
        a symbology, or use it to validate a format name from config.

    .EXAMPLE
        Get-BarcodeFormats | Format-Table Display, Dimensions, Hint
    #>
    return $script:BarcodeFormats
}

function Get-BarcodeFormat {
    <#
    .SYNOPSIS
        Looks a format up by key or display name (case-insensitive).

    .PARAMETER Name
        'QR_CODE', 'QR Code', 'ean-13', ... Returns $null when unknown.

    .EXAMPLE
        Get-BarcodeFormat -Name 'EAN-13'
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $needle = $Name.Trim()
    foreach ($f in $script:BarcodeFormats) {
        if ($f.Key -eq $needle -or $f.Display -eq $needle) { return $f }
    }
    # Second pass tolerates the punctuation people actually type ('ean13').
    $loose = ($needle -replace '[^A-Za-z0-9]', '')
    foreach ($f in $script:BarcodeFormats) {
        if (($f.Key -replace '[^A-Za-z0-9]', '') -eq $loose) { return $f }
        if (($f.Display -replace '[^A-Za-z0-9]', '') -eq $loose) { return $f }
    }
    return $null
}

function Import-BarcodeAssemblies {
    <#
    .SYNOPSIS
        Loads the bundled ZXing.Net assemblies. Safe to call repeatedly.

    .DESCRIPTION
        Loads lib\zxing.dll and lib\zxing.presentation.dll from the app folder.
        Returns $true when the writer type is available, $false otherwise -
        callers surface that instead of throwing, so a missing DLL disables one
        tab rather than killing startup.

        Files extracted from a downloaded ZIP (which is exactly how install.ps1
        delivers this app) carry a mark-of-the-web stream, and Add-Type refuses
        to load a blocked assembly - hence the Unblock-File pass.
    #>

    if ('ZXing.Presentation.BarcodeWriter' -as [type]) { return $true }

    try {
        $libDir = Join-Path $global:ConfigFiles 'lib'
        $dlls   = @('zxing.dll', 'zxing.presentation.dll')

        foreach ($name in $dlls) {
            $path = Join-Path $libDir $name
            if (-not (Test-Path -LiteralPath $path)) {
                throw "Missing $path - reinstall WinTuner or restore the lib folder."
            }
            try { Unblock-File -LiteralPath $path -ErrorAction SilentlyContinue } catch { }
        }

        # WriteableBitmap lives in these two; loading them explicitly keeps the
        # order deterministic when Config.ps1 is dot-sourced from a bare host.
        Add-Type -AssemblyName 'PresentationCore'
        Add-Type -AssemblyName 'WindowsBase'

        foreach ($name in $dlls) {
            Add-Type -Path (Join-Path $libDir $name)
        }

        return [bool]('ZXing.Presentation.BarcodeWriter' -as [type])
    }
    catch {
        Add-StartupLog "Barcode generation unavailable: $($_.Exception.Message)" 'Red'
        return $false
    }
}

function New-BarcodeBitmap {
    <#
    .SYNOPSIS
        Encodes text into a barcode and returns a frozen WPF BitmapSource.

    .DESCRIPTION
        Generated entirely in-process by ZXing.Net - no network call, no temp
        file, no external tool. The result is frozen, so it can be handed to an
        Image control from any thread.

        Throws on invalid input (e.g. letters in an EAN-13); the caller decides
        how loudly to complain. Use Test-BarcodeText for a non-throwing check.

    .PARAMETER Text
        The payload to encode.

    .PARAMETER Format
        Format key or display name - see Get-BarcodeFormats. Default 'QR_CODE'.

    .PARAMETER Size
        Longest edge in pixels. 2D formats render Size x Size; 1D formats render
        Size wide by a proportional height, because a square Code 128 is mostly
        wasted white space.

    .EXAMPLE
        $bmp = New-BarcodeBitmap -Text 'https://example.com' -Size 300

    .EXAMPLE
        $bmp = New-BarcodeBitmap -Text '5901234123457' -Format 'EAN-13' -Size 400
    #>
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Text,

        [Parameter(Mandatory = $false)]
        [string]$Format = 'QR_CODE',

        [Parameter(Mandatory = $false)]
        [ValidateRange(50, 2000)]
        [int]$Size = 300
    )

    if ([String]::IsNullOrWhiteSpace($Text)) {
        throw "Nothing to encode - enter some text first."
    }

    if (-not (Import-BarcodeAssemblies)) {
        throw "The barcode library (lib\zxing.dll) could not be loaded."
    }

    $fmt = Get-BarcodeFormat -Name $Format
    if (-not $fmt) {
        throw "Unknown barcode format '$Format'. Known: $(($script:BarcodeFormats.Display) -join ', ')."
    }

    # A 1D symbol is a strip, not a square - give it a sane aspect ratio.
    $width  = $Size
    $height = if ($fmt.Dimensions -eq '2D') { $Size } else { [int][Math]::Round($Size * 0.45) }

    $writer = New-Object ZXing.Presentation.BarcodeWriter
    $writer.Format = [ZXing.BarcodeFormat]::($fmt.ZXing)
    $writer.Options.Width  = $width
    $writer.Options.Height = $height
    $writer.Options.Margin = 1
    # Print the payload under 1D codes, the way a real label does. QR and
    # friends stay clean - the text would only steal module space.
    $writer.Options.PureBarcode = ($fmt.Dimensions -eq '2D')

    try {
        $bitmap = $writer.Write($Text)
    }
    catch {
        # ZXing wraps the real complaint one level down.
        $inner = $_.Exception.InnerException
        $why   = if ($inner) { $inner.Message } else { $_.Exception.Message }
        throw "$($fmt.Display): $why  ($($fmt.Hint))"
    }

    if ($bitmap.CanFreeze) { $bitmap.Freeze() }
    return $bitmap
}

function Test-BarcodeText {
    <#
    .SYNOPSIS
        Non-throwing check that Text can be encoded as Format.

    .DESCRIPTION
        Returns an object with IsValid and Message. Handy for live validation
        while typing, where an exception per keystroke would be silly.

    .EXAMPLE
        Test-BarcodeText -Text '123' -Format 'EAN-13'
    #>
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Text,

        [Parameter(Mandatory = $false)]
        [string]$Format = 'QR_CODE'
    )

    try {
        $null = New-BarcodeBitmap -Text $Text -Format $Format -Size 100
        return [pscustomobject]@{ IsValid = $true; Message = 'OK' }
    }
    catch {
        return [pscustomobject]@{ IsValid = $false; Message = $_.Exception.Message }
    }
}

function Save-BarcodeBitmap {
    <#
    .SYNOPSIS
        Writes a BitmapSource to disk as a PNG.

    .PARAMETER Bitmap
        A BitmapSource, e.g. from New-BarcodeBitmap.

    .PARAMETER Path
        Destination .png path. The folder must exist.

    .EXAMPLE
        New-BarcodeBitmap -Text 'hello' | Save-BarcodeBitmap -Path 'C:\temp\hello.png'
    #>
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [System.Windows.Media.Imaging.BitmapSource]$Bitmap,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    process {
        $encoder = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
        $encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($Bitmap))

        # FileStream in a finally, so a failed encode can't leave the file open.
        $stream = [System.IO.File]::Create($Path)
        try   { $encoder.Save($stream) }
        finally { $stream.Close() }

        return (Test-Path -LiteralPath $Path)
    }
}

function New-QRCode {
    <#
    .SYNOPSIS
        Generates a QR code (or any supported barcode) straight to a PNG file.

    .DESCRIPTION
        Kept for callers that want a file rather than a bitmap - the Local PS
        REPL, scripts, and anything written against the old API. Fully local;
        the old version of this function called out to api.qrserver.com.

    .PARAMETER Text
        The text or URL to encode.

    .PARAMETER OutputPath
        Where the PNG is written.

    .PARAMETER Size
        Longest edge in pixels (default 300).

    .PARAMETER Format
        Format key or display name (default 'QR_CODE'). See Get-BarcodeFormats.

    .EXAMPLE
        New-QRCode -Text "https://example.com" -OutputPath "C:\temp\qrcode.png"

    .EXAMPLE
        New-QRCode -Text "5901234123457" -Format "EAN-13" -OutputPath "C:\temp\ean.png"
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [Parameter(Mandatory = $false)]
        [int]$Size = 300,

        [Parameter(Mandatory = $false)]
        [string]$Format = 'QR_CODE'
    )

    try {
        $bitmap = New-BarcodeBitmap -Text $Text -Format $Format -Size $Size
        return [bool](Save-BarcodeBitmap -Bitmap $bitmap -Path $OutputPath)
    }
    catch {
        Write-Error "Failed to generate barcode: $_"
        return $false
    }
}

function Show-QRCode {
    <#
    .SYNOPSIS
        Displays a generated code image in the default image viewer.

    .PARAMETER Path
        The path to the image file.

    .EXAMPLE
        Show-QRCode -Path "C:\temp\qrcode.png"
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (Test-Path -LiteralPath $Path) {
        Start-Process $Path
    }
    else {
        Write-Error "Image file not found: $Path"
    }
}

function Get-QRCodeTempPath {
    <#
    .SYNOPSIS
        Builds a temporary file path for a generated code image.

    .PARAMETER Prefix
        Optional filename prefix (default "qrcode").

    .EXAMPLE
        $path = Get-QRCodeTempPath
    #>
    param(
        [Parameter(Mandatory = $false)]
        [string]$Prefix = "qrcode"
    )

    $tempDir  = [System.IO.Path]::GetTempPath()
    $fileName = "$($Prefix)_$([Guid]::NewGuid().ToString('N')).png"
    return Join-Path $tempDir $fileName
}
