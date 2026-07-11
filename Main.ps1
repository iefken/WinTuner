#========================================================================
# Title: WinTuner (Windows system tuning utility)
# Author: Ief
# Ported (local-only) from DHL_DEVICE_MANAGER
#========================================================================

#========================================================================
# GUI app — no terminal. Hide the console window straight away so the
# user only ever sees the WPF window. Flip $Global:ShowConsole to $true
# when you need the console for troubleshooting.
#
# Because the console is hidden, fatal startup errors (which happen
# BEFORE the Activity log exists) are surfaced via a MessageBox instead
# of Write-Host + Read-Host — otherwise they'd vanish into the void.
#========================================================================

Add-Type -AssemblyName System.Windows.Forms   # MessageBox fallback + WPF dialogs

$Global:ShowConsole = $false

if (-not $Global:ShowConsole) {
    try {
        $hideSig = @'
[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")]   public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
'@
        $null = Add-Type -MemberDefinition $hideSig -Name 'ConsoleWin' -Namespace 'Win32' -PassThru
        $hWnd = [Win32.ConsoleWin]::GetConsoleWindow()
        if ($hWnd -ne [IntPtr]::Zero) { [Win32.ConsoleWin]::ShowWindow($hWnd, 0) | Out-Null }  # 0 = SW_HIDE
    }
    catch {
        # Non-fatal: if hiding fails (e.g. no console host), just carry on.
    }
}
else {
    Clear-Host
}

# Fatal-error popup for anything that goes wrong before the GUI is up.
function Show-FatalError {
    param([string]$Message)
    [System.Windows.Forms.MessageBox]::Show(
        $Message, 'WinTuner', 'OK', 'Error') | Out-Null
}

#========================================================================
# Resolve paths & load the active profile from ini.json
#
# NOTE: unlike the donor project (which hardcodes absolute network-share
# paths per hub), this is a single-machine local tool — so the project
# root is simply wherever Main.ps1 lives. That keeps the tool portable:
# clone/copy it anywhere and it just runs.
#========================================================================

$Global:ConfigFiles = $PSScriptRoot
$Global:IniPath     = Join-Path $Global:ConfigFiles 'ini.json'

if (-not (Test-Path $Global:IniPath)) {
    Show-FatalError "ini.json not found at:`n$Global:IniPath"
    return
}

try {
    $AllIni        = Get-Content $Global:IniPath -Raw | ConvertFrom-Json
    $ActiveProfile = $AllIni[0].ActiveProfile
    if ([String]::IsNullOrEmpty($ActiveProfile)) { $ActiveProfile = 'home' }

    $Global:IniFile = $AllIni | Where-Object { $_.Profile -eq $ActiveProfile }
    if ($null -eq $Global:IniFile) {
        throw "Active profile '$ActiveProfile' not found in ini.json"
    }
}
catch {
    Show-FatalError "Failed to read ini.json:`n$_"
    return
}

#========================================================================
# Derive global paths
#========================================================================

$Global:ConfigPath = Join-Path $Global:ConfigFiles $Global:IniFile.ConfigPath
$Global:LogPath    = Join-Path $Global:ConfigFiles $Global:IniFile.LogPath
$Global:AppVersion = $Global:IniFile.AppVersion

if ($debug) {
    Write-Host "ConfigFiles: $Global:ConfigFiles"
    Write-Host "ConfigPath:  $Global:ConfigPath"
    Write-Host "LogPath:     $Global:LogPath"
}

#========================================================================
# Load the configuration chain (assemblies, XAML, functions, classes)
#========================================================================

if (-not (Test-Path $Global:ConfigPath)) {
    Show-FatalError "Config.ps1 not found at:`n$Global:ConfigPath"
    return
}

# Loading the config chain parses the XAML; a failure here means there is
# no Activity log to fall back on, so surface it via the MessageBox.
try {
    . $Global:ConfigPath
}
catch {
    Show-FatalError "Failed to load the application:`n$_"
    return
}

#========================================================================
# Launch the GUI ( src/functions/classes/GUI-Handler.ps1 )
#========================================================================

try {
    $Global:GUIHandler = [GUI_Handler]::new()
    $Global:GUIHandler.Launch_GUI()
}
catch {
    Show-FatalError "Critical error launching the GUI:`n$_"
}
