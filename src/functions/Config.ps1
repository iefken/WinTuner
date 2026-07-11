#========================================================================
# Config.ps1 — load assemblies, set globals, parse XAML, import functions
#
# Local-only: no AD module, no credential export, no RemoteSigned/RSAT
# prompts. This file is dot-sourced by Main.ps1 (and Test-DevStartup.ps1).
#========================================================================

#========================================================================
# 0. Startup message buffer
#
# The Activity log (richtxt_Log) doesn't exist until the XAML is parsed
# below, but warnings can occur before then. Buffer them here; the GUI
# handler flushes the buffer into the Activity log once the window is up.
#========================================================================

if (-not $Global:StartupLog) {
    $Global:StartupLog = New-Object System.Collections.Generic.List[object]
}

function Add-StartupLog {
    param(
        [Parameter(Mandatory)][string] $Message,
        [string] $Color = 'Yellow'
    )
    $Global:StartupLog.Add([pscustomobject]@{ Message = $Message; Color = $Color })
}

#========================================================================
# 1. Required .NET assemblies (WPF + WinForms dialogs)
#========================================================================

Add-Type -AssemblyName 'System.Windows.Forms'
Add-Type -AssemblyName 'PresentationFramework'
Add-Type -AssemblyName 'System.Data'
Add-Type -AssemblyName 'Microsoft.VisualBasic'   # Recycle Bin deletes (File Cleanup tab)
Add-Type -AssemblyName 'System.Drawing'          # app-icon extraction (Common apps tiles)

#========================================================================
# 2. Ensure the log directory exists
#========================================================================

if (-not [String]::IsNullOrEmpty($Global:LogPath) -and -not (Test-Path $Global:LogPath)) {
    try {
        New-Item -ItemType Directory -Path $Global:LogPath -Force | Out-Null
    }
    catch {
        Add-StartupLog "Could not create LogPath ($Global:LogPath): $_" 'Yellow'
    }
}

#========================================================================
# 3. Parse the WPF XAML form  ->  $global:Form + named control globals
#========================================================================

. "$Global:ConfigFiles\src\functions\startup\Load-XamlForm.ps1"

#========================================================================
# 4. Dynamically import all functions & handler classes
#========================================================================

. "$Global:ConfigFiles\src\functions\Import-Functions.ps1"
