#========================================================================
# WinGet Functions - Application Manager
#
# Functions for managing Windows applications via WinGet package manager.
# Supports listing, searching, installing, updating, and uninstalling apps.
#========================================================================

#========================================================================
# Get WinGet installed packages
#========================================================================
function Get-WinGetApps {
    <#
    .SYNOPSIS
        Lists all WinGet-installed packages on the system.
    .DESCRIPTION
        Returns a list of installed packages with their ID, name, and version.
    .OUTPUTS
        Array of PSCustomObject with properties: Id, Name, Version, Source
    #>
    try {
        $result = winget list --accept-source-agreements
        if ($LASTEXITCODE -ne 0) {
            throw "WinGet command failed with exit code $LASTEXITCODE"
        }

        # Parse the output (skip header lines)
        $apps = @()
        $lines = $result -split "`n"
        
        foreach ($line in $lines) {
            if ($line -match '^\s*(\S+)\s+([^\s]+(?:\s+[^\s]+)?)\s+([\d\.]+)\s+(\S+)') {
                $apps += [PSCustomObject]@{
                    Id      = $matches[1].Trim()
                    Name    = $matches[2].Trim()
                    Version = $matches[3].Trim()
                    Source  = $matches[4].Trim()
                }
            }
        }
        return $apps
    }
    catch {
        throw "Failed to get WinGet apps: $_"
    }
}

#========================================================================
# Search WinGet for available packages
#========================================================================
function Search-WinGetApps {
    <#
    .SYNOPSIS
        Searches WinGet repository for available packages.
    .PARAMETER Query
        Search term for the package.
    .OUTPUTS
        Array of PSCustomObject with properties: Id, Name, Version, Source
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Query
    )
    
    try {
        $result = winget search $Query --accept-source-agreements
        if ($LASTEXITCODE -ne 0) {
            throw "WinGet search failed with exit code $LASTEXITCODE"
        }

        # Parse the output (skip header lines)
        $apps = @()
        $lines = $result -split "`n"
        
        foreach ($line in $lines) {
            if ($line -match '^\s*(\S+)\s+([^\s]+(?:\s+[^\s]+)?)\s+([\d\.]+)\s+(\S+)') {
                $apps += [PSCustomObject]@{
                    Id      = $matches[1].Trim()
                    Name    = $matches[2].Trim()
                    Version = $matches[3].Trim()
                    Source  = $matches[4].Trim()
                }
            }
        }
        return $apps
    }
    catch {
        throw "Failed to search WinGet apps: $_"
    }
}

#========================================================================
# Install a WinGet package
#========================================================================
function Install-WinGetApp {
    <#
    .SYNOPSIS
        Installs a single WinGet package.
    .PARAMETER PackageId
        The WinGet package ID to install.
    .PARAMETER Silent
        Install silently without UI prompts.
    .OUTPUTS
        Boolean indicating success or failure.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$PackageId,
        
        [Parameter(Mandatory=$false)]
        [switch]$Silent
    )
    
    try {
        $wingetArgs = @("install", $PackageId, "--accept-package-agreements", "--accept-source-agreements")
        if ($Silent) {
            $wingetArgs += "--silent", "--interactive"
        }
        
        $process = Start-Process -FilePath "winget" -ArgumentList $wingetArgs -Wait -PassThru -NoNewWindow
        return ($process.ExitCode -eq 0)
    }
    catch {
        throw "Failed to install WinGet app '$PackageId': $_"
    }
}

#========================================================================
# Install multiple WinGet packages
#========================================================================
function Install-WinGetApps {
    <#
    .SYNOPSIS
        Installs multiple WinGet packages.
    .PARAMETER PackageIds
        Array of WinGet package IDs to install.
    .PARAMETER Silent
        Install silently without UI prompts.
    .OUTPUTS
        Array of PSCustomObject with results for each package.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$PackageIds,
        
        [Parameter(Mandatory=$false)]
        [switch]$Silent
    )
    
    $results = @()
    
    foreach ($pkgId in $PackageIds) {
        try {
            $success = Install-WinGetApp -PackageId $pkgId -Silent:$Silent
            $results += [PSCustomObject]@{
                PackageId = $pkgId
                Success   = $success
                Message   = if ($success) { "Installed successfully" } else { "Installation failed" }
            }
        }
        catch {
            $results += [PSCustomObject]@{
                PackageId = $pkgId
                Success   = $false
                Message   = "Error: $_"
            }
        }
    }
    
    return $results
}

#========================================================================
# Update all WinGet packages
#========================================================================
function Update-WinGetApps {
    <#
    .SYNOPSIS
        Updates all installed WinGet packages.
    .PARAMETER All
        Update all packages (including those not set to auto-update).
    .OUTPUTS
        Array of PSCustomObject with update results.
    #>
    param(
        [Parameter(Mandatory=$false)]
        [switch]$All
    )
    
    try {
        $wingetArgs = @("upgrade", "--all", "--accept-package-agreements", "--accept-source-agreements")
        if (-not $All) {
            $wingetArgs += "--include-unknown"
        }
        
        $process = Start-Process -FilePath "winget" -ArgumentList $wingetArgs -Wait -PassThru -NoNewWindow
        return ($process.ExitCode -eq 0)
    }
    catch {
        throw "Failed to update WinGet apps: $_"
    }
}

#========================================================================
# Uninstall a WinGet package
#========================================================================
function Uninstall-WinGetApp {
    <#
    .SYNOPSIS
        Uninstalls a WinGet package.
    .PARAMETER PackageId
        The WinGet package ID to uninstall.
    .OUTPUTS
        Boolean indicating success or failure.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$PackageId
    )
    
    try {
        $process = Start-Process -FilePath "winget" -ArgumentList @("uninstall", $PackageId, "--accept-source-agreements") -Wait -PassThru -NoNewWindow
        return ($process.ExitCode -eq 0)
    }
    catch {
        throw "Failed to uninstall WinGet app '$PackageId': $_"
    }
}

#========================================================================
# Check if WinGet is available
#========================================================================
function Test-WinGetAvailable {
    <#
    .SYNOPSIS
        Checks if WinGet is available on the system.
    .OUTPUTS
        Boolean indicating WinGet availability.
    #>
    try {
        $null = Get-Command winget -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}
