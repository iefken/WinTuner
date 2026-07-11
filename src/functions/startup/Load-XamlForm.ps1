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

# Expose each named control as a global variable (e.g. $global:richtxt_Log)
$XAML.SelectNodes("//*[@Name]") | ForEach-Object {
    Set-Variable -Name $_.Name -Value $Global:Form.FindName($_.Name) -Scope Global -ErrorAction Stop
}
