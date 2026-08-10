#========================================================================
# Load-XamlForm.ps1 — parse the WPF XAML into $global:Form and expose
# every x:Name'd control as a global variable of the same name.
#
# Dot-sourced directly by Config.ps1 (this 'startup' folder is excluded
# from the dynamic loader).
#========================================================================

Add-Type -AssemblyName PresentationFramework

$xamlPath = "$Global:ConfigFiles\$($Global:IniFile.GUIPath)"

if (-not (Test-Path $xamlPath)) {
    Write-Host "XAML form not found at: $xamlPath" -ForegroundColor Red
    throw "Missing XAML form: $xamlPath"
}

$inputXML = Get-Content $xamlPath -Raw

# Strip designer-only attributes that XamlReader can't handle
$inputXML = $inputXML -replace 'mc:Ignorable="d"', '' -replace 'x:N', 'N' -replace '^<Win.*', '<Window'

[xml]$XAML = $inputXML

$reader = New-Object System.Xml.XmlNodeReader $XAML
try {
    $Global:Form = [Windows.Markup.XamlReader]::Load($reader)
}
catch {
    Write-Host "Unable to parse XAML. Ensure there are NO SelectionChanged/TextChanged attributes in the markup." -ForegroundColor Red
    Write-Host $_ -ForegroundColor Red
    throw
}

# Set the window icon programmatically
$iconPath = Join-Path $Global:ConfigFiles "wintuner.ico"
if (Test-Path $iconPath) {
    try {
        # WPF's Window.Icon is an ImageSource — a System.Drawing.Icon won't cast.
        # OnLoad caching + Freeze so the file isn't kept locked and the source is
        # safe to reuse from any thread.
        #
        # wintuner.ico is multi-frame (16 → 256 px). BitmapImage would pick one
        # frame for us with no say in which, so decode explicitly and hand WPF
        # the LARGEST frame: Windows derives both the title-bar icon and the
        # bigger taskbar/Alt-Tab icon from this one source, and downscaling a
        # large frame looks far better than blowing up a small one.
        $iconUri = New-Object System.Uri (Resolve-Path -LiteralPath $iconPath).Path
        $decoder = [System.Windows.Media.Imaging.BitmapDecoder]::Create(
            $iconUri,
            [System.Windows.Media.Imaging.BitmapCreateOptions]::None,
            [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad)

        $iconImage = $decoder.Frames | Sort-Object PixelWidth -Descending | Select-Object -First 1
        if ($null -eq $iconImage) { throw "No image frames found in $iconPath" }

        if (-not $iconImage.IsFrozen) { $iconImage.Freeze() }

        $Global:Form.Icon = $iconImage
    }
    catch {
        Write-Host "Failed to load icon from: $iconPath - $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# Expose each named control as a global variable (e.g. $global:richtxt_Log)
$XAML.SelectNodes("//*[@Name]") | ForEach-Object {
    Set-Variable -Name $_.Name -Value $Global:Form.FindName($_.Name) -Scope Global -ErrorAction Stop
}
