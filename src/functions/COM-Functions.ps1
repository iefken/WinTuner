#========================================================================
# COM-Functions.ps1 — serial/COM port helpers (pure, no GUI).
#
# Auto-loaded by Import-Functions.ps1, so also callable from the Local PS
# tab (e.g. Get-ComPortSnapshot).
#========================================================================

# Extracts a COM port name (e.g. COM3) from a device's display name.
function Get-ComFromName {
    param([string]$Name)
    if ($Name -match '\((COM\d+)\)') { return $Matches[1] }
    if ($Name -match '\bCOM\d+\b')    { return $Matches[0] }
    return ''
}

# Returns the COM/serial ports currently present, one object per device.
# PNPDeviceID is the stable key used to diff add/remove between polls.
function Get-ComPortSnapshot {
    $result = @()
    try {
        $ports = Get-CimInstance Win32_PnPEntity -Filter "PNPClass='Ports'" -ErrorAction Stop
    }
    catch {
        Write-Warning "Get-ComPortSnapshot: WMI query failed: $_"
        return $result
    }

    foreach ($p in $ports) {
        $result += [pscustomobject]@{
            COM          = Get-ComFromName ([string]$p.Name)
            Name         = [string]$p.Name
            Manufacturer = [string]$p.Manufacturer
            PNPDeviceID  = [string]$p.PNPDeviceID
        }
    }
    return $result
}
