#========================================================================
# DNS Functions - DNS Changer
#
# Functions for changing DNS settings on network adapters.
#========================================================================

#========================================================================
# Get common DNS providers
#========================================================================
function Get-DNSProviders {
    <#
    .SYNOPSIS
        Returns a list of common DNS providers.
    .OUTPUTS
        Array of PSCustomObject with DNS provider information.
    #>
    return @(
        [PSCustomObject]@{
            Name = "Google DNS"
            Primary = "8.8.8.8"
            Secondary = "8.8.4.4"
            Description = "Google Public DNS"
        },
        [PSCustomObject]@{
            Name = "Cloudflare DNS"
            Primary = "1.1.1.1"
            Secondary = "1.0.0.1"
            Description = "Cloudflare DNS (1.1.1.1)"
        },
        [PSCustomObject]@{
            Name = "OpenDNS"
            Primary = "208.67.222.222"
            Secondary = "208.67.220.220"
            Description = "OpenDNS Family Shield"
        },
        [PSCustomObject]@{
            Name = "Quad9 DNS"
            Primary = "9.9.9.9"
            Secondary = "149.112.112.112"
            Description = "Quad9 Security DNS"
        },
        [PSCustomObject]@{
            Name = "DNS.WATCH"
            Primary = "84.200.69.80"
            Secondary = "84.200.70.40"
            Description = "DNS.WATCH Germany"
        },
        [PSCustomObject]@{
            Name = "AdGuard DNS"
            Primary = "94.140.14.14"
            Secondary = "94.140.15.15"
            Description = "AdGuard DNS (blocking ads)"
        },
        [PSCustomObject]@{
            Name = "Comodo DNS"
            Primary = "8.26.56.26"
            Secondary = "8.20.247.20"
            Description = "Comodo Secure DNS"
        }
    )
}

#========================================================================
# Get network adapters
#========================================================================
function Get-NetworkAdapters {
    <#
    .SYNOPSIS
        Returns active network adapters that can have DNS configured.
    .OUTPUTS
        Array of PSCustomObject with adapter information.
    #>
    try {
        $adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" -and $_.MediaType -in @("Ethernet", "802.11") }
        $result = @()
        
        foreach ($adapter in $adapters) {
            $result += [PSCustomObject]@{
                Name = $adapter.Name
                InterfaceAlias = $adapter.InterfaceAlias
                Description = $adapter.InterfaceDescription
                Status = $adapter.Status
            }
        }
        
        return $result
    }
    catch {
        throw "Failed to get network adapters: $_"
    }
}

#========================================================================
# Get current DNS settings for an adapter
#========================================================================
function Get-AdapterDNS {
    <#
    .SYNOPSIS
        Gets the current DNS settings for a specific adapter.
    .PARAMETER InterfaceAlias
        The interface alias of the adapter.
    .OUTPUTS
        PSCustomObject with current DNS settings.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$InterfaceAlias
    )
    
    try {
        $dnsSettings = Get-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue
        
        if ($dnsSettings) {
            $primary = ($dnsSettings | Where-Object { $_.ServerAddressIndex -eq 0 }).ServerAddresses[0]
            $secondary = ($dnsSettings | Where-Object { $_.ServerAddressIndex -eq 1 }).ServerAddresses[0]
            
            return [PSCustomObject]@{
                Primary = $primary
                Secondary = $secondary
                Method = if ($primary -eq "127.0.0.1") { "DHCP" } else { "Static" }
            }
        }
        
        return [PSCustomObject]@{
            Primary = "DHCP"
            Secondary = "DHCP"
            Method = "DHCP"
        }
    }
    catch {
        throw "Failed to get DNS settings: $_"
    }
}

#========================================================================
# Set DNS for an adapter
#========================================================================
function Set-AdapterDNS {
    <#
    .SYNOPSIS
        Sets DNS servers for a specific adapter.
    .PARAMETER InterfaceAlias
        The interface alias of the adapter.
    .PARAMETER PrimaryDNS
        Primary DNS server IP.
    .PARAMETER SecondaryDNS
        Secondary DNS server IP (optional).
    .OUTPUTS
        Boolean indicating success or failure.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$InterfaceAlias,
        
        [Parameter(Mandatory=$true)]
        [string]$PrimaryDNS,
        
        [Parameter(Mandatory=$false)]
        [string]$SecondaryDNS = ""
    )
    
    try {
        if ([String]::IsNullOrWhiteSpace($SecondaryDNS)) {
            Set-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -ServerAddresses $PrimaryDNS -ErrorAction Stop
        } else {
            Set-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -ServerAddresses @($PrimaryDNS, $SecondaryDNS) -ErrorAction Stop
        }
        
        return $true
    }
    catch {
        throw "Failed to set DNS: $_"
    }
}

#========================================================================
# Reset DNS to DHCP
#========================================================================
function Reset-AdapterDNS {
    <#
    .SYNOPSIS
        Resets DNS settings to DHCP for a specific adapter.
    .PARAMETER InterfaceAlias
        The interface alias of the adapter.
    .OUTPUTS
        Boolean indicating success or failure.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$InterfaceAlias
    )
    
    try {
        Set-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -ResetServerAddresses -ErrorAction Stop
        return $true
    }
    catch {
        throw "Failed to reset DNS: $_"
    }
}

#========================================================================
# Flush DNS cache
#========================================================================
function Clear-DNSCache {
    <#
    .SYNOPSIS
        Clears the local DNS cache.
    .OUTPUTS
        Boolean indicating success or failure.
    #>
    try {
        Clear-DnsClientCache -ErrorAction Stop
        return $true
    }
    catch {
        throw "Failed to clear DNS cache: $_"
    }
}
