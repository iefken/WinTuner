#========================================================================
# Windows Update Functions - Windows Update Control
#
# Functions for managing Windows Update settings and operations.
#========================================================================

#========================================================================
# Get Windows Update service status
#========================================================================
function Get-WindowsUpdateServiceStatus {
    <#
    .SYNOPSIS
        Returns the status of Windows Update related services.
    .OUTPUTS
        Array of PSCustomObject with service status.
    #>
    try {
        $services = @("wuauserv", "UsoSvc", "BITS")
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
        throw "Failed to get Windows Update service status: $_"
    }
}

#========================================================================
# Set Windows Update service startup type
#========================================================================
function Set-WindowsUpdateService {
    <#
    .SYNOPSIS
        Sets the startup type of Windows Update service.
    .PARAMETER StartupType
        The desired startup type (Automatic, Manual, Disabled).
    .OUTPUTS
        Boolean indicating success or failure.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet("Automatic", "Manual", "Disabled")]
        [string]$StartupType
    )
    
    try {
        Set-Service -Name "wuauserv" -StartupType $StartupType -ErrorAction Stop
        return $true
    }
    catch {
        throw "Failed to set Windows Update service: $_"
    }
}

#========================================================================
# Check for Windows updates
#========================================================================
function Invoke-WindowsUpdateCheck {
    <#
    .SYNOPSIS
        Initiates a Windows Update check.
    .OUTPUTS
        Boolean indicating success or failure.
   #>
    try {
        $process = Start-Process -FilePath "wuauclt.exe" -ArgumentList @("/detectnow") -Wait -PassThru -NoNewWindow
        return ($process.ExitCode -eq 0)
    }
    catch {
        throw "Failed to check for updates: $_"
    }
}

#========================================================================
# Get Windows Update settings
#========================================================================
function Get-WindowsUpdateSettings {
    <#
    .SYNOPSIS
        Returns current Windows Update settings from registry.
    .OUTPUTS
        PSCustomObject with Windows Update settings.
    #>
    try {
        $settings = [PSCustomObject]@{
            AutoUpdate = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update" -ErrorAction SilentlyContinue).AUOptions
            ScheduledInstallDay = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update" -ErrorAction SilentlyContinue).ScheduledInstallDay
            ScheduledInstallTime = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update" -ErrorAction SilentlyContinue).ScheduledInstallTime
            IncludeRecommendedUpdates = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update" -ErrorAction SilentlyContinue).IncludeRecommendedUpdates
        }
        return $settings
    }
    catch {
        throw "Failed to get Windows Update settings: $_"
    }
}

#========================================================================
# Set Windows Update to manual
#========================================================================
function Set-WindowsUpdateManual {
    <#
    .SYNOPSIS
        Sets Windows Update to manual (notify only).
    .OUTPUTS
        Boolean indicating success or failure.
    #>
    try {
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update" -Name "AUOptions" -Value 2 -ErrorAction Stop
        return $true
    }
    catch {
        throw "Failed to set Windows Update to manual: $_"
    }
}

#========================================================================
# Set Windows Update to automatic
#========================================================================
function Set-WindowsUpdateAutomatic {
    <#
    .SYNOPSIS
        Sets Windows Update to automatic (download and install).
    .OUTPUTS
        Boolean indicating success or failure.
    #>
    try {
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update" -Name "AUOptions" -Value 4 -ErrorAction Stop
        return $true
    }
    catch {
        throw "Failed to set Windows Update to automatic: $_"
    }
}

#========================================================================
# Disable Windows Update
#========================================================================
function Disable-WindowsUpdate {
    <#
    .SYNOPSIS
        Disables Windows Update by setting service to disabled and changing registry settings.
    .OUTPUTS
        Boolean indicating success or failure.
    #>
    try {
        # Stop service
        Stop-Service -Name "wuauserv" -Force -ErrorAction SilentlyContinue
        
        # Set service to disabled
        Set-Service -Name "wuauserv" -StartupType Disabled -ErrorAction Stop
        
        # Set registry to disable
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "NoAutoUpdate" -Value 1 -ErrorAction SilentlyContinue
        
        return $true
    }
    catch {
        throw "Failed to disable Windows Update: $_"
    }
}
