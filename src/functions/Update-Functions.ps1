#========================================================================
# Update-Functions.ps1 - "is there a newer WinTuner?" check
#
# The only outbound call in the app. It reads the published ini.json from
# the GitHub repo and compares its AppVersion against the running one.
# It never downloads or installs anything - updating stays a deliberate
# act (run install.ps1).
#
# Runs in a background Start-Job drained by a DispatcherTimer, same
# pattern as the Diagnostics and WinGet tabs: a slow or unreachable
# network must never delay the window appearing.
#
# It reads the GitHub contents API, NOT raw.githubusercontent.com. Raw is
# served with Cache-Control: max-age=300 and GitHub normalises the query
# string away, so cache-busting does not work: for five minutes after a
# release the raw copy still reports the previous version. Measured, not
# assumed. The API answers immediately at the cost of a 60 requests/hour
# unauthenticated limit, which a once-per-launch check will never reach.
#========================================================================

# Used when ini.json carries no UpdateCheckUrl (older installs).
$global:UpdateCheckDefaultUrl = 'https://api.github.com/repos/iefken/WinTuner/contents/ini.json?ref=main'

#========================================================================
# Version comparison
#========================================================================
function Compare-AppVersion {
    <#
    .SYNOPSIS
        Compares two dotted version strings component by component.
    .DESCRIPTION
        Versions are x.y.z (major.feature.fix). Components are compared
        NUMERICALLY, so '0.10.0' is correctly newer than '0.3.0' - which
        [version] gets wrong, parsing '0.10.0' as 0.10 -> 0.1. Missing
        components count as 0, so '1', '1.0' and '1.0.0' are all equal,
        which also keeps the legacy x.xy releases (0.01, 0.02) ordering
        correctly against the newer x.y.z ones.
    .PARAMETER Local
        The running version.
    .PARAMETER Remote
        The published version.
    .OUTPUTS
        -1 local is older, 0 equal, 1 local is newer.
        $null when either side is not a plain dotted-numeric version.
    #>
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Local,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Remote
    )

    if ([String]::IsNullOrWhiteSpace($Local) -or [String]::IsNullOrWhiteSpace($Remote)) { return $null }

    $lParts = @($Local.Trim().TrimStart('v', 'V')  -split '\.')
    $rParts = @($Remote.Trim().TrimStart('v', 'V') -split '\.')

    # Anything non-numeric (pre-release tags, build suffixes) is out of scope.
    foreach ($p in ($lParts + $rParts)) {
        if ($p -notmatch '^\d+$') { return $null }
    }

    $max = [Math]::Max($lParts.Count, $rParts.Count)
    for ($i = 0; $i -lt $max; $i++) {
        $l = if ($i -lt $lParts.Count) { [int]$lParts[$i] } else { 0 }
        $r = if ($i -lt $rParts.Count) { [int]$rParts[$i] } else { 0 }
        if ($l -lt $r) { return -1 }
        if ($l -gt $r) { return 1 }
    }

    return 0
}

#========================================================================
# Remote version lookup
#========================================================================
function Get-RemoteAppVersion {
    <#
    .SYNOPSIS
        Reads AppVersion from the published ini.json.
    .DESCRIPTION
        Accepts either a GitHub contents-API URL (JSON wrapper with the
        file base64-encoded in .content) or a plain raw URL that returns
        the file itself. Both shapes are handled, so an ini.json left over
        from an older install that still points at raw keeps working.
    .PARAMETER Url
        Contents-API or raw URL of the published ini.json.
    .PARAMETER TimeoutSec
        How long to wait before giving up.
    .OUTPUTS
        The version string. Throws when the fetch or parse fails.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Url,

        [Parameter(Mandatory = $false)]
        [int]$TimeoutSec = 10
    )

    # PS 5.1 can still default to TLS 1.0; GitHub refuses anything below 1.2.
    try {
        [Net.ServicePointManager]::SecurityProtocol =
            [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    }
    catch {
        # Older .NET without Tls12 in the enum - let the request fail on its own.
    }

    # The API rejects requests without a User-Agent.
    $headers = @{
        'User-Agent' = 'WinTuner-UpdateCheck'
        'Accept'     = 'application/vnd.github+json'
    }

    $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec $TimeoutSec -Headers $headers
    if (-not $response -or [String]::IsNullOrWhiteSpace($response.Content)) {
        throw "Empty response from $Url"
    }

    $payload = $response.Content | ConvertFrom-Json

    # Contents API wraps the file; a raw URL returns it directly.
    $isApiWrapper = ($null -ne $payload) -and
                    ($payload.PSObject.Properties.Name -contains 'content') -and
                    ($payload.encoding -eq 'base64')

    if ($isApiWrapper) {
        $decoded = [System.Text.Encoding]::UTF8.GetString(
            [Convert]::FromBase64String(($payload.content -replace '\s', '')))
        # ini.json may carry a UTF-8 BOM; ConvertFrom-Json chokes on the
        # leading U+FEFF with a misleading "invalid JSON primitive".
        $decoded = $decoded.TrimStart([char]0xFEFF)
        $ini = $decoded | ConvertFrom-Json
    }
    else {
        $ini = $payload
    }

    # Same shape as the local file: element 0 selects the profile, the rest
    # are profiles. Take the first entry that actually declares a version.
    # NOTE: $ini is assigned before being piped - piping ConvertFrom-Json
    # output straight into Where-Object hands over an un-enumerated array.
    $version = ($ini | Where-Object { $_.AppVersion } | Select-Object -First 1).AppVersion
    if ([String]::IsNullOrWhiteSpace($version)) {
        throw "No AppVersion found in the published ini.json"
    }

    return $version.ToString().Trim()
}

#========================================================================
# Header button state
#========================================================================
function Set-UpdateCheckButtonEnabled {
    <#
    .SYNOPSIS
        Enables/disables the header "Check for updates" button.
    .DESCRIPTION
        Tolerates the button not existing - the check also runs at startup
        and must never fail over a missing control.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Enabled
    )

    try {
        if ($global:btn_CheckUpdates) { $global:btn_CheckUpdates.IsEnabled = $Enabled }
    }
    catch {
        # Cosmetic only - never let this break the check itself.
    }
}

#========================================================================
# Manual check (header button)
#========================================================================
function Handle-btn_CheckUpdates {
    <#
    .SYNOPSIS
        Runs the same check the app performs at startup, on demand.
    #>
    if ($global:UpdateCheck_Job -and $global:UpdateCheck_Job.State -eq 'Running') {
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Update check already running", 'Gray')
        return
    }

    # Immediate feedback; the verdict follows a moment later via the poller.
    $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Checking for updates...", 'Cyan')

    if (-not (Start-UpdateCheck)) {
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Could not start the update check", 'Red')
        Set-UpdateCheckButtonEnabled -Enabled $true
    }
}

#========================================================================
# Background check
#========================================================================
function Start-UpdateCheck {
    <#
    .SYNOPSIS
        Kicks off the update check in the background.
    .DESCRIPTION
        Safe to call unconditionally at startup: it never throws, and a
        failure to even start the job just means no check happened.
    .OUTPUTS
        $true if the check was started.
    #>
    param(
        [Parameter(Mandatory = $false)]
        [int]$TimeoutSec = 10
    )

    if ($global:UpdateCheck_Job -and $global:UpdateCheck_Job.State -eq 'Running') { return $false }

    if ($global:UpdateCheck_Job) {
        Remove-Job -Job $global:UpdateCheck_Job -Force -ErrorAction SilentlyContinue
        $global:UpdateCheck_Job = $null
    }

    # URL comes from the active ini.json profile; fall back to the repo default.
    $url = $null
    try { $url = $Global:IniFile.UpdateCheckUrl } catch { $url = $null }
    if ([String]::IsNullOrWhiteSpace($url)) { $url = $global:UpdateCheckDefaultUrl }

    $functionsPath = Join-Path $Global:ConfigFiles 'src\functions\Update-Functions.ps1'
    if (-not (Test-Path -LiteralPath $functionsPath)) { return $false }

    try {
        $global:UpdateCheck_Job = Start-Job -ScriptBlock {
            param($FunctionsPath, $Url, $TimeoutSec)

            . $FunctionsPath

            try {
                [PSCustomObject]@{
                    Ok      = $true
                    Version = (Get-RemoteAppVersion -Url $Url -TimeoutSec $TimeoutSec)
                    Error   = $null
                }
            }
            catch {
                # Offline, DNS down, proxy, rate limit - all the same to us.
                [PSCustomObject]@{ Ok = $false; Version = $null; Error = $_.Exception.Message }
            }
        } -ArgumentList $functionsPath, $url, $TimeoutSec
    }
    catch {
        return $false
    }

    # No double-clicking while a check is in flight.
    Set-UpdateCheckButtonEnabled -Enabled $false

    if (-not $global:UpdateCheck_Timer) {
        $global:UpdateCheck_Timer = New-Object System.Windows.Threading.DispatcherTimer
        $global:UpdateCheck_Timer.Interval = [TimeSpan]::FromMilliseconds(500)
        $global:UpdateCheck_Timer.add_Tick({ Handle-UpdateCheck_Poll })
    }
    $global:UpdateCheck_Timer.Start()

    return $true
}

#========================================================================
# Drain the check and report
#========================================================================
function Handle-UpdateCheck_Poll {
    <#
    .SYNOPSIS
        Reports the update-check outcome to the Activity log, once.
    #>
    if (-not $global:UpdateCheck_Job) {
        if ($global:UpdateCheck_Timer) { $global:UpdateCheck_Timer.Stop() }
        Set-UpdateCheckButtonEnabled -Enabled $true
        return
    }

    if ($global:UpdateCheck_Job.State -notin @('Completed', 'Failed', 'Stopped')) { return }

    $result = $null
    try {
        $result = @(Receive-Job -Job $global:UpdateCheck_Job -ErrorAction SilentlyContinue) |
                  Select-Object -First 1
    }
    catch {
        $result = $null
    }

    Remove-Job -Job $global:UpdateCheck_Job -Force -ErrorAction SilentlyContinue
    $global:UpdateCheck_Job = $null
    $global:UpdateCheck_Timer.Stop()

    # Re-enable before reporting, so an early return below cannot leave the
    # button stuck disabled.
    Set-UpdateCheckButtonEnabled -Enabled $true

    $localVersion = if ($Global:AppVersion) { [string]$Global:AppVersion } else { '' }

    # A failed check is background noise, not a problem the user must act on.
    if ($null -eq $result -or -not $result.Ok) {
        $reason = if ($result -and $result.Error) { $result.Error } else { 'no response' }
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Update check skipped ($reason)", 'Gray')
        return
    }

    $remoteVersion = [string]$result.Version
    $comparison = Compare-AppVersion -Local $localVersion -Remote $remoteVersion

    if ($null -eq $comparison) {
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME,
            "Update check: cannot compare v$localVersion with published v$remoteVersion", 'Gray')
        return
    }

    if ($comparison -lt 0) {
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME,
            "Update available: v$remoteVersion (running v$localVersion) - run install.ps1 to update", 'Orange')
    }
    elseif ($comparison -gt 0) {
        # Normal on the dev box: local is ahead of what has been pushed.
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME,
            "Running v$localVersion, ahead of published v$remoteVersion", 'Gray')
    }
    else {
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Up to date (v$localVersion)", 'Green')
    }
}
