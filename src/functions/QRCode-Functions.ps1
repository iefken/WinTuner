#========================================================================
# QR Code Generator Functions
#========================================================================

function New-QRCode {
    <#
    .SYNOPSIS
        Generates a QR code from text or URL and saves it as an image file.
    
    .DESCRIPTION
        Uses the QRServer API to generate QR codes that can be scanned by any smartphone.
        The QR code is saved as a PNG file and can be displayed in the GUI.
    
    .PARAMETER Text
        The text or URL to encode in the QR code.
    
    .PARAMETER OutputPath
        The path where the QR code image will be saved.
    
    .PARAMETER Size
        The size of the QR code in pixels (default: 300).
    
    .EXAMPLE
        New-QRCode -Text "https://example.com" -OutputPath "C:\temp\qrcode.png"
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,
        
        [Parameter(Mandatory = $true)]
        [string]$OutputPath,
        
        [Parameter(Mandatory = $false)]
        [int]$Size = 300
    )
    
    try {
        # Encode the text for URL
        $EncodedText = [System.Web.HttpUtility]::UrlEncode($Text)
        
        # Build the API URL
        $ApiUrl = "https://api.qrserver.com/v1/create-qr-code/?size=${Size}x${Size}&data=${EncodedText}"
        
        # Download the QR code image
        Invoke-WebRequest -Uri $ApiUrl -OutFile $OutputPath -UseBasicParsing
        
        if (Test-Path $OutputPath) {
            return $true
        }
        else {
            return $false
        }
    }
    catch {
        Write-Error "Failed to generate QR code: $_"
        return $false
    }
}

function Show-QRCode {
    <#
    .SYNOPSIS
        Displays a QR code image in the default image viewer.
    
    .DESCRIPTION
        Opens the generated QR code image file with the default system image viewer.
    
    .PARAMETER Path
        The path to the QR code image file.
    
    .EXAMPLE
        Show-QRCode -Path "C:\temp\qrcode.png"
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    
    if (Test-Path $Path) {
        Start-Process $Path
    }
    else {
        Write-Error "QR code file not found: $Path"
    }
}

function Get-QRCodeTempPath {
    <#
    .SYNOPSIS
        Generates a temporary file path for QR code storage.
    
    .DESCRIPTION
        Creates a unique temporary file path in the system temp directory.
    
    .PARAMETER Prefix
        Optional prefix for the filename (default: "qrcode").
    
    .EXAMPLE
        $path = Get-QRCodeTempPath
    #>
    param(
        [Parameter(Mandatory = $false)]
        [string]$Prefix = "qrcode"
    )
    
    $tempDir = [System.IO.Path]::GetTempPath()
    $fileName = "$($Prefix)_$([Guid]::NewGuid().ToString('N')).png"
    return Join-Path $tempDir $fileName
}
