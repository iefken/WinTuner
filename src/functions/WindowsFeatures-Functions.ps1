#========================================================================
# Windows Features Functions - Enable/Disable Windows Optional Features
#
# Functions for managing Windows optional features (WSL, Sandbox, Hyper-V, etc.)
#========================================================================

#========================================================================
# Get list of available Windows optional features
#========================================================================
function Get-WindowsFeatures {
    <#
    .SYNOPSIS
        Lists all available Windows optional features.
    .OUTPUTS
        Array of PSCustomObject with properties: Name, DisplayName, State
    #>
    try {
        $features = Get-WindowsOptionalFeature -Online
        $result = @()
        
        foreach ($feature in $features) {
            $result += [PSCustomObject]@{
                Name = $feature.FeatureName
                DisplayName = if ($feature.DisplayName) { $feature.DisplayName } else { $feature.FeatureName }
                State = $feature.State
            }
        }
        
        return $result
    }
    catch {
        throw "Failed to get Windows features: $_"
    }
}

#========================================================================
# Enable a Windows optional feature
#========================================================================
function Enable-WindowsFeature {
    <#
    .SYNOPSIS
        Enables a Windows optional feature.
    .PARAMETER FeatureName
        The name of the feature to enable.
    .PARAMETER NoRestart
        Suppress restart prompt if needed.
    .OUTPUTS
        Boolean indicating success or failure.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$FeatureName,
        
        [Parameter(Mandatory=$false)]
        [switch]$NoRestart
    )
    
    try {
        $featureArgs = @("-Online", "-Enable", "-FeatureName", $FeatureName)
        if ($NoRestart) {
            $featureArgs += "-NoRestart"
        }
        
        $result = Enable-WindowsOptionalFeature @featureArgs
        return ($result.RestartNeeded -eq $false -or $NoRestart)
    }
    catch {
        throw "Failed to enable feature '$FeatureName': $_"
    }
}

#========================================================================
# Disable a Windows optional feature
#========================================================================
function Disable-WindowsFeature {
    <#
    .SYNOPSIS
        Disables a Windows optional feature.
    .PARAMETER FeatureName
        The name of the feature to disable.
    .PARAMETER NoRestart
        Suppress restart prompt if needed.
    .OUTPUTS
        Boolean indicating success or failure.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$FeatureName,
        
        [Parameter(Mandatory=$false)]
        [switch]$NoRestart
    )
    
    try {
        $featureArgs = @("-Online", "-Disable", "-FeatureName", $FeatureName)
        if ($NoRestart) {
            $featureArgs += "-NoRestart"
        }
        
        $result = Disable-WindowsOptionalFeature @featureArgs
        return ($result.RestartNeeded -eq $false -or $NoRestart)
    }
    catch {
        throw "Failed to disable feature '$FeatureName': $_"
    }
}

#========================================================================
# Get common Windows features for quick access
#========================================================================
function Get-CommonWindowsFeatures {
    <#
    .SYNOPSIS
        Returns a curated list of commonly used Windows features.
    .OUTPUTS
        Array of PSCustomObject with properties: Name, DisplayName, Description, Category
    #>
    return @(
        [PSCustomObject]@{
            Name = "Microsoft-Windows-Subsystem-Linux"
            DisplayName = "Windows Subsystem for Linux (WSL)"
            Description = "Run Linux environments directly on Windows"
            Category = "Development"
        },
        [PSCustomObject]@{
            Name = "VirtualMachinePlatform"
            DisplayName = "Virtual Machine Platform"
            Description = "Required for WSL 2"
            Category = "Development"
        },
        [PSCustomObject]@{
            Name = "Containers"
            DisplayName = "Containers"
            Description = "Windows containers support"
            Category = "Development"
        },
        [PSCustomObject]@{
            Name = "Microsoft-Hyper-V"
            DisplayName = "Hyper-V"
            Description = "Virtualization platform"
            Category = "Virtualization"
        },
        [PSCustomObject]@{
            Name = "Microsoft-Windows-Client-EmbeddedExp-Package-Server"
            DisplayName = "Windows Sandbox"
            Description = "Secure desktop environment for running untrusted applications"
            Category = "Security"
        },
        [PSCustomObject]@{
            Name = "TelnetClient"
            DisplayName = "Telnet Client"
            Description = "Telnet client for network troubleshooting"
            Category = "Networking"
        },
        [PSCustomObject]@{
            Name = "TFTP"
            DisplayName = "TFTP Client"
            Description = "Trivial File Transfer Protocol client"
            Category = "Networking"
        },
        [PSCustomObject]@{
            Name = "NetFx3"
            DisplayName = ".NET Framework 3.5"
            Description = "Legacy .NET Framework support"
            Category = "Legacy"
        },
        [PSCustomObject]@{
            Name = "IIS-WebServer"
            DisplayName = "IIS Web Server"
            Description = "Internet Information Services web server"
            Category = "Server"
        },
        [PSCustomObject]@{
            Name = "IIS-WebServerRole"
            DisplayName = "IIS Web Server Role"
            Description = "Full IIS web server role"
            Category = "Server"
        },
        [PSCustomObject]@{
            Name = "Microsoft-Windows-IIS-WebServer"
            DisplayName = "IIS Web Server (Full)"
            Description = "Complete IIS web server installation"
            Category = "Server"
        },
        [PSCustomObject]@{
            Name = "Windows-Defender-Default-Definitions"
            DisplayName = "Windows Defender Default Definitions"
            Description = "Default malware definitions"
            Category = "Security"
        },
        [PSCustomObject]@{
            Name = "SearchEngine-Client-Package"
            DisplayName = "Windows Search"
            Description = "Windows Search service"
            Category = "System"
        },
        [PSCustomObject]@{
            Name = "WorkFolders-Client"
            DisplayName = "Work Folders Client"
            Description = "Sync work files across devices"
            Category = "Productivity"
        },
        [PSCustomObject]@{
            Name = "Printing-XPSServices-Features"
            DisplayName = "XPS Services"
            Description = "XPS document viewer and services"
            Category = "System"
        }
    )
}

#========================================================================
# Check if a feature is enabled
#========================================================================
function Test-WindowsFeatureEnabled {
    <#
    .SYNOPSIS
        Checks if a Windows optional feature is enabled.
    .PARAMETER FeatureName
        The name of the feature to check.
    .OUTPUTS
        Boolean indicating if the feature is enabled.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$FeatureName
    )
    
    try {
        $feature = Get-WindowsOptionalFeature -Online -FeatureName $FeatureName -ErrorAction SilentlyContinue
        if ($feature) {
            return ($feature.State -eq "Enabled")
        }
        return $false
    }
    catch {
        return $false
    }
}
