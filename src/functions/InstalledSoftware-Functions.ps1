#========================================================================
# Installed Software Functions - Software Management
#
# Functions for querying and managing installed software on Windows systems.
# Supports listing, searching, sorting, and uninstalling software.
#========================================================================

#========================================================================
# Get all installed software from Windows Registry
#========================================================================
function Get-InstalledSoftware {
    <#
    .SYNOPSIS
        Lists all installed software from Windows Registry.
    .DESCRIPTION
        Queries both HKLM and HKCU registry paths for installed software.
        Returns software with name, version, publisher, install date, and size.
    .OUTPUTS
        Array of PSCustomObject with properties: Name, Version, Publisher, InstallDate, Size
    #>
    $softwareList = @()
    
    # Registry paths for installed software
    $registryPaths = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    
    foreach ($path in $registryPaths) {
        if (Test-Path $path) {
            Get-ItemProperty $path -ErrorAction SilentlyContinue | ForEach-Object {
                $displayName = $_.DisplayName
                if (-not [String]::IsNullOrWhiteSpace($displayName)) {
                    # Parse install date from registry (Win32 format)
                    $installDate = $null
                    if ($_.InstallDate -and $_.InstallDate -match '^\d{8}$') {
                        try {
                            $year = $_.InstallDate.Substring(0, 4)
                            $month = $_.InstallDate.Substring(4, 2)
                            $day = $_.InstallDate.Substring(6, 2)
                            $installDate = Get-Date -Year $year -Month $month -Day $day -ErrorAction SilentlyContinue
                        }
                        catch {
                            # If date parsing fails, leave as null
                        }
                    }
                    
                    # Parse size (estimated from registry if available)
                    $size = $null
                    if ($_.EstimatedSize -and $_.EstimatedSize -match '^\d+$') {
                        # EstimatedSize is in KB
                        $sizeKB = [int]$_.EstimatedSize
                        if ($sizeKB -gt 1024) {
                            $size = "$([math]::Round($sizeKB / 1024, 1)) MB"
                        } else {
                            $size = "$sizeKB KB"
                        }
                    }
                    
                    $softwareList += [PSCustomObject]@{
                        Name = $displayName
                        Version = if ($_.DisplayVersion) { $_.DisplayVersion } else { "Unknown" }
                        Publisher = if ($_.Publisher) { $_.Publisher } else { "Unknown" }
                        InstallDate = if ($installDate) { $installDate.ToString("yyyy-MM-dd") } else { "Unknown" }
                        Size = if ($size) { $size } else { "Unknown" }
                        UninstallString = $_.UninstallString
                        QuietUninstallString = $_.QuietUninstallString
                    }
                }
            }
        }
    }
    
    return $softwareList
}

#========================================================================
# Find installed software by search term
#========================================================================
function Find-InstalledSoftware {
    <#
    .SYNOPSIS
        Filters installed software by search term.
    .PARAMETER SoftwareList
        Array of software objects to filter.
    .PARAMETER SearchTerm
        Search term to filter by (searches name, publisher, version).
    .OUTPUTS
        Filtered array of software objects.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [array]$SoftwareList,
        
        [Parameter(Mandatory=$false)]
        [string]$SearchTerm = ""
    )
    
    if ([String]::IsNullOrWhiteSpace($SearchTerm)) {
        return $SoftwareList
    }
    
    return $SoftwareList | Where-Object {
        $_.Name -like "*$SearchTerm*" -or
        $_.Publisher -like "*$SearchTerm*" -or
        $_.Version -like "*$SearchTerm*"
    }
}

#========================================================================
# Uninstall software
#========================================================================
function Uninstall-Software {
    <#
    .SYNOPSIS
        Uninstalls software using Windows uninstaller.
    .PARAMETER UninstallString
        Uninstall string from registry.
    .PARAMETER QuietUninstallString
        Quiet uninstall string from registry (preferred if available).
    .OUTPUTS
        Boolean indicating success or failure.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$UninstallString,
        
        [Parameter(Mandatory=$false)]
        [string]$QuietUninstallString = ""
    )
    
    try {
        # Prefer quiet uninstall if available
        $command = if (-not [String]::IsNullOrWhiteSpace($QuietUninstallString)) {
            $QuietUninstallString
        } else {
            $UninstallString
        }
        
        # Parse the command - handle both MsiExec.exe and direct uninstallers
        if ($command -match "MsiExec\.exe") {
            # MSI uninstall
            if ($command -match "/I\{[A-F0-9\-]+\}") {
                # Replace /I with /X for uninstall
                $command = $command -replace "/I\{([A-F0-9\-]+)\}", "/X`{$1`}"
            }
            if ($command -notmatch "/qn") {
                $command += " /qn"
            }
        }
        
        # Execute the uninstall command
        $processInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processInfo.FileName = "cmd.exe"
        $processInfo.Arguments = "/c $command"
        $processInfo.UseShellExecute = $false
        $processInfo.RedirectStandardOutput = $true
        $processInfo.RedirectStandardError = $true
        $processInfo.CreateNoWindow = $true
        
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $processInfo
        $process.Start() | Out-Null
        $process.WaitForExit()
        
        return ($process.ExitCode -eq 0)
    }
    catch {
        throw "Failed to uninstall software: $_"
    }
}
