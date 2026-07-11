#========================================================================
# System Fixes Functions - Common Windows system repair tools
#
# Functions for running system repair operations like network reset,
# Windows Update reset, SFC, and DISM.
#========================================================================

#========================================================================
# Run System File Checker (SFC)
#========================================================================
function Invoke-SFCScan {
    <#
    .SYNOPSIS
        Runs the System File Checker to repair Windows system files.
    .PARAMETER ScanOnly
        Only scan without repairing.
    .OUTPUTS
        Boolean indicating success or failure.
    #>
    param(
        [Parameter(Mandatory=$false)]
        [switch]$ScanOnly
    )
    
    try {
        $sfcArgs = @("/scannow")
        if ($ScanOnly) {
            $sfcArgs = @("/verifyonly")
        }
        
        $process = Start-Process -FilePath "sfc.exe" -ArgumentList $sfcArgs -Wait -PassThru -NoNewWindow -Verb RunAs
        return ($process.ExitCode -eq 0)
    }
    catch {
        throw "Failed to run SFC scan: $_"
    }
}

#========================================================================
# Run DISM repair
#========================================================================
function Invoke-DISMRepair {
    <#
    .SYNOPSIS
        Runs DISM to repair the Windows image.
    .PARAMETER RestoreHealth
        Use /RestoreHealth to repair the image.
    .OUTPUTS
        Boolean indicating success or failure.
    #>
    param(
        [Parameter(Mandatory=$false)]
        [switch]$RestoreHealth
    )
    
    try {
        $dismArgs = @("/Online", "/Cleanup-Image", "/ScanHealth")
        if ($RestoreHealth) {
            $dismArgs = @("/Online", "/Cleanup-Image", "/RestoreHealth")
        }
        
        $process = Start-Process -FilePath "dism.exe" -ArgumentList $dismArgs -Wait -PassThru -NoNewWindow -Verb RunAs
        return ($process.ExitCode -eq 0)
    }
    catch {
        throw "Failed to run DISM repair: $_"
    }
}

#========================================================================
# Reset network settings
#========================================================================
function Reset-NetworkSettings {
    <#
    .SYNOPSIS
        Resets network settings to default (flushes DNS, resets IP, etc.).
    .OUTPUTS
        Boolean indicating success or failure.
    #>
    try {
        # Release IP
        Start-Process -FilePath "ipconfig.exe" -ArgumentList @("/release") -Wait -NoNewWindow -ErrorAction SilentlyContinue
        
        # Flush DNS
        Start-Process -FilePath "ipconfig.exe" -ArgumentList @("/flushdns") -Wait -NoNewWindow -ErrorAction SilentlyContinue
        
        # Renew IP
        Start-Process -FilePath "ipconfig.exe" -ArgumentList @("/renew") -Wait -NoNewWindow -ErrorAction SilentlyContinue
        
        # Reset Winsock
        Start-Process -FilePath "netsh.exe" -ArgumentList @("winsock", "reset") -Wait -NoNewWindow -ErrorAction SilentlyContinue
        
        # Reset network adapter
        Start-Process -FilePath "netsh.exe" -ArgumentList @("int", "ip", "reset") -Wait -NoNewWindow -ErrorAction SilentlyContinue
        
        return $true
    }
    catch {
        throw "Failed to reset network settings: $_"
    }
}

#========================================================================
# Reset Windows Update components
#========================================================================
function Reset-WindowsUpdate {
    <#
    .SYNOPSIS
        Resets Windows Update components to default state.
    .OUTPUTS
        Boolean indicating success or failure.
    #>
    try {
        # Stop Windows Update services
        $services = @("wuauserv", "cryptSvc", "bits", "msiserver")
        foreach ($svc in $services) {
            Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
        }
        
        # Rename Windows Update directories
        $paths = @(
            "$env:systemroot\SoftwareDistribution",
            "$env:systemroot\System32\catroot2"
        )
        
        foreach ($path in $paths) {
            if (Test-Path $path) {
                $newPath = "$path.old"
                if (Test-Path $newPath) {
                    Remove-Item -Path $newPath -Recurse -Force -ErrorAction SilentlyContinue
                }
                Rename-Item -Path $path -NewName "$path.old" -ErrorAction SilentlyContinue
            }
        }
        
        # Restart Windows Update services
        foreach ($svc in $services) {
            Start-Service -Name $svc -ErrorAction SilentlyContinue
        }
        
        return $true
    }
    catch {
        throw "Failed to reset Windows Update: $_"
    }
}

#========================================================================
# Clear Windows Update cache
#========================================================================
function Clear-WindowsUpdateCache {
    <#
    .SYNOPSIS
        Clears the Windows Update cache (SoftwareDistribution folder).
    .OUTPUTS
        Boolean indicating success or failure.
    #>
    try {
        # Stop Windows Update service
        Stop-Service -Name "wuauserv" -Force -ErrorAction SilentlyContinue
        
        # Clear SoftwareDistribution folder
        $softDistPath = "$env:systemroot\SoftwareDistribution"
        if (Test-Path $softDistPath) {
            Remove-Item -Path "$softDistPath\*" -Recurse -Force -ErrorAction SilentlyContinue
        }
        
        # Start Windows Update service
        Start-Service -Name "wuauserv" -ErrorAction SilentlyContinue
        
        return $true
    }
    catch {
        throw "Failed to clear Windows Update cache: $_"
    }
}

#========================================================================
# Check Windows Update service status
#========================================================================
function Get-WindowsUpdateStatus {
    <#
    .SYNOPSIS
        Gets the status of Windows Update services.
    .OUTPUTS
        Array of PSCustomObject with service status.
    #>
    try {
        $services = @("wuauserv", "cryptSvc", "bits", "msiserver")
        $result = @()
        
        foreach ($svc in $services) {
            $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
            if ($service) {
                $result += [PSCustomObject]@{
                    Name = $service.Name
                    DisplayName = $service.DisplayName
                    Status = $service.Status
                    StartType = $service.StartType
                }
            }
        }
        
        return $result
    }
    catch {
        throw "Failed to get Windows Update status: $_"
    }
}
