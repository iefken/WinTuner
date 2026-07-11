#========================================================================
# Performance Plans Functions - Windows Power Plans
#
# Functions for managing Windows power plans (performance profiles).
#========================================================================

#========================================================================
# Get available power plans
#========================================================================
function Get-PowerPlans {
    <#
    .SYNOPSIS
        Returns all available power plans on the system.
    .OUTPUTS
        Array of PSCustomObject with power plan information.
    #>
    try {
        $plans = powercfg -list
        $result = @()
        
        foreach ($line in $plans) {
            if ($line -match "Power Scheme GUID: ([0-9a-f-]+)\s+\(([^)]+)\)\s+(.+)") {
                $guid = $matches[1]
                $name = $matches[2]
                $description = $matches[3].Trim()
                
                # Check if this is the active plan
                $activePlan = powercfg -getactivescheme
                if ($activePlan -match $guid) {
                    $isActive = $true
                } else {
                    $isActive = $false
                }
                
                $result += [PSCustomObject]@{
                    Guid = $guid
                    Name = $name
                    Description = $description
                    IsActive = $isActive
                }
            }
        }
        
        return $result
    }
    catch {
        throw "Failed to get power plans: $_"
    }
}

#========================================================================
# Get common power plans for quick access
#========================================================================
function Get-CommonPowerPlans {
    <#
    .SYNOPSIS
        Returns a curated list of common power plan GUIDs.
    .OUTPUTS
        Array of PSCustomObject with common power plan information.
    #>
    return @(
        [PSCustomObject]@{
            Name = "High Performance"
            Guid = "8c5e7fda-e8bf-45a6-a7cc-4b3c8f3291c6"
            Description = "Maximizes system performance"
        },
        [PSCustomObject]@{
            Name = "Balanced"
            Guid = "381b4222-f694-41f0-9685-ff5bb260df2e"
            Description = "Balances performance and power consumption"
        },
        [PSCustomObject]@{
            Name = "Power Saver"
            Guid = "a1841308-3541-4fab-bc81-f71556f20b4a"
            Description = "Saves power by reducing performance"
        },
        [PSCustomObject]@{
            Name = "Ultimate Performance"
            Guid = "e9a42b02-d5df-448d-aa00-03f14749eb61"
            Description = "Maximum performance (hidden by default)"
        }
    )
}

#========================================================================
# Set active power plan
#========================================================================
function Set-PowerPlan {
    <#
    .SYNOPSIS
        Sets the active power plan.
    .PARAMETER Guid
        The GUID of the power plan to activate.
    .OUTPUTS
        Boolean indicating success or failure.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Guid
    )
    
    try {
        $process = Start-Process -FilePath "powercfg.exe" -ArgumentList @("-setactive", $Guid) -Wait -PassThru -NoNewWindow
        return ($process.ExitCode -eq 0)
    }
    catch {
        throw "Failed to set power plan: $_"
    }
}

#========================================================================
# Get active power plan
#========================================================================
function Get-ActivePowerPlan {
    <#
    .SYNOPSIS
        Returns the currently active power plan.
    .OUTPUTS
        PSCustomObject with active power plan information.
    #>
    try {
        $active = powercfg -getactivescheme
        if ($active -match "Power Scheme GUID: ([0-9a-f-]+)\s+\(([^)]+)\)") {
            return [PSCustomObject]@{
                Guid = $matches[1]
                Name = $matches[2]
            }
        }
        return $null
    }
    catch {
        throw "Failed to get active power plan: $_"
    }
}

#========================================================================
# Enable Ultimate Performance plan (if available)
#========================================================================
function Enable-UltimatePerformancePlan {
    <#
    .SYNOPSIS
        Enables the hidden Ultimate Performance power plan.
    .OUTPUTS
        Boolean indicating success or failure.
    #>
    try {
        $process = Start-Process -FilePath "powercfg.exe" -ArgumentList @("-duplicatescheme", "e9a42b02-d5df-448d-aa00-03f14749eb61") -Wait -PassThru -NoNewWindow
        return ($process.ExitCode -eq 0)
    }
    catch {
        throw "Failed to enable Ultimate Performance plan: $_"
    }
}
