#========================================================================
# Helper-Functions.ps1 — shared, GUI-agnostic utility functions.
#
# Local-only subset ported from DHL_DEVICE_MANAGER. Remote/session and
# DHL-specific helpers (Verify-Session, Fix-ManualLTSCUpdate,
# Verify-ValidPcTag, …) were intentionally left behind.
#
# User-facing feedback should go through $global:GUIHandler.Visual_Log()
# (defined on the GUI_Handler class), not Write-Host.
#========================================================================

# Appends an action record to a CSV audit log.
Function Set-Logfile {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True)]
        [string]
        # Which action/script the user invoked
        $Config,

        [Parameter(Mandatory = $True)]
        [string]
        # Full path of the CSV log to append to
        $Path,

        [Parameter(Mandatory = $False)]
        [string]
        $ComputerName = $env:COMPUTERNAME
    )

    try {
        [pscustomobject]@{
            Date         = Get-Date -Format G
            ComputerName = $ComputerName
            User         = $env:USERNAME
            Config       = $Config
        } | Export-Csv -NoTypeInformation -Path $Path -Append -ErrorAction Stop
        return $true
    }
    catch {
        Write-Error "Set-Logfile failed: $_"
        return $false
    }
}

# Consistent error reporting for catch blocks. Routes to the Activity log
# (via Visual_Log) when the GUI is up; falls back to the console otherwise
# (e.g. when called from the Local PS REPL or a standalone script run).
Function Handle-Catchblock {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True)]
        [System.Management.Automation.ErrorRecord]
        $ErrorRecord,

        [Parameter(Mandatory = $False)]
        [string]
        $Action = "operation",

        [Parameter(Mandatory = $False)]
        [string]
        $ComputerName = $env:COMPUTERNAME
    )

    $invocation = $ErrorRecord.InvocationInfo
    $message = "Error during $Action : $($ErrorRecord.Exception.Message)"
    $detail  = "  (line $($invocation.ScriptLineNumber): $($invocation.Line.Trim()))"

    if ($global:GUIHandler -and $global:richtxt_Log) {
        $global:GUIHandler.Visual_Log($ComputerName, $message, 'Red')
        $global:GUIHandler.Visual_Log($ComputerName, $detail, 'Orange')
    }
    else {
        Write-Host "[$ComputerName] $message" -ForegroundColor Red
        Write-Host $detail -ForegroundColor DarkYellow
        Write-Host "Script: $($invocation.ScriptName)" -ForegroundColor DarkYellow
    }

    return $false
}

# Resolves a .lnk shortcut to its target path.
Function Resolve-Shortcut {
    param (
        [Parameter(Mandatory = $True, ValueFromPipeline = $True, Position = 0)]
        [Alias("PSPath")]
        [string]$Path
    )

    try {
        $shell    = New-Object -COM WScript.Shell
        $shortcut = $shell.CreateShortcut($Path)
        return $shortcut.TargetPath
    }
    catch {
        Write-Error "Resolve-Shortcut failed for '$Path': $_"
        return $null
    }
    finally {
        $shell = $null
    }
}

# Hides the PowerShell console window (call after the GUI is up).
Function Hide-Console {
    Add-Type -Name Window -Namespace Console -MemberDefinition '
    [DllImport("Kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, Int32 nCmdShow);
    '
    $ConsolePtr = [Console.Window]::GetConsoleWindow()
    [Console.Window]::ShowWindow($ConsolePtr, 0) | Out-Null  # 0 = hide
}
