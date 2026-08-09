#========================================================================
# WinGet Functions - Application Manager
#
# Functions for managing Windows applications via WinGet package manager.
# Supports listing, searching, installing, updating, and uninstalling apps.
#
# NOTE on parsing: winget has no machine-readable output for search/list,
# so we parse its fixed-width table. The layout is:
#
#   Name        Id        Version   [Match|Available]   Source
#   ---------------------------------------------------------
#
# Column boundaries are derived from the header row (the line directly
# above the dashed separator), never from a regex over the data rows -
# names contain spaces ("NoteTab Light") and trailing columns are often
# empty, both of which break token-based matching.
#========================================================================

#========================================================================
# Known winget exit codes
#========================================================================
# winget returns HRESULT-style codes. Only codes verified against the
# shipped CLI are mapped here; anything else is reported as hex plus
# winget's own output text, which is more reliable than guessing.
$script:WinGetExitCodes = @{
    0            = 'Success'
    -1978335230  = 'Invalid command line arguments'             # 0x8A150002
    -1978335212  = 'No package found matching input criteria'   # 0x8A150014
    -1978335189  = 'Already up to date'                         # 0x8A15002B
}

# Exit codes meaning "the package is present and current" - clicking Install
# on something already installed is a no-op, not a failure.
$script:WinGetUpToDateCodes = @(-1978335189)

function Get-WinGetExitMessage {
    <#
    .SYNOPSIS
        Translates a winget exit code into a human-readable message.
    .PARAMETER ExitCode
        The exit code returned by the winget process.
    .OUTPUTS
        String description of the exit code.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [int]$ExitCode
    )

    if ($script:WinGetExitCodes.ContainsKey($ExitCode)) {
        return $script:WinGetExitCodes[$ExitCode]
    }

    # Unknown code - hex form is what the winget docs/issues use.
    return ('winget exit code 0x{0:X8}' -f $ExitCode)
}

#========================================================================
# Low-level winget runner
#========================================================================
function Invoke-WinGet {
    <#
    .SYNOPSIS
        Runs winget and captures its output and exit code.
    .DESCRIPTION
        Central entry point for every winget call. Captures stdout+stderr
        so failures can be reported with winget's own message instead of a
        bare exit code, and never opens a console window.
    .PARAMETER Arguments
        The argument list to pass to winget.
    .OUTPUTS
        PSCustomObject with ExitCode (int), Lines (string[]) and Output (string).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    # winget writes UTF-8; PS 5.1 decodes native output using the console
    # code page, which mangles non-ASCII package names. Switch it for the
    # duration of the call - throws when the host has no console, hence the try.
    $previousEncoding = $null
    try {
        $previousEncoding = [Console]::OutputEncoding
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    }
    catch {
        $previousEncoding = $null
    }

    try {
        # No 2>&1 on purpose: winget writes its error text to stdout, and
        # redirecting a native command's stderr in PS 5.1 wraps every line in a
        # NativeCommandError that throws when $ErrorActionPreference is 'Stop'.
        $global:LASTEXITCODE = 0
        $raw = & winget @Arguments
        $exitCode = $global:LASTEXITCODE

        # Normalise to lines and drop winget's spinner/progress artefacts.
        $lines = @()
        foreach ($item in @($raw)) {
            $text = [string]$item
            foreach ($part in ($text -split "`r?`n")) {
                $clean = ($part -replace "`r", '').TrimEnd()
                if ([string]::IsNullOrWhiteSpace($clean)) { continue }

                $trimmed = $clean.Trim()
                # Keep the table's dashed separator - the parser needs it.
                if ($trimmed -notmatch '^-{5,}$') {
                    # Progress frames consist only of spinner/bar characters.
                    if ($trimmed -match '^[\-\\|/█░▒▓■·]+$') { continue }
                }

                $lines += $clean
            }
        }

        return [PSCustomObject]@{
            ExitCode = $exitCode
            Lines    = $lines
            Output   = ($lines -join [Environment]::NewLine)
        }
    }
    catch {
        throw "Failed to run winget $($Arguments -join ' '): $_"
    }
    finally {
        if ($null -ne $previousEncoding) {
            try { [Console]::OutputEncoding = $previousEncoding } catch { }
        }
    }
}

#========================================================================
# Fixed-width table parser
#========================================================================
function ConvertFrom-WinGetTable {
    <#
    .SYNOPSIS
        Parses a winget fixed-width result table into objects.
    .DESCRIPTION
        Locates the dashed separator line, takes the line above it as the
        header, derives each column's start offset from the header, then
        slices every following line on those offsets. Columns are looked up
        by header name (Name/Id/Version/Source/Match/Available) and fall
        back to fixed positions if the header is localised.
    .PARAMETER Lines
        Raw output lines from a winget search/list call.
    .OUTPUTS
        Array of PSCustomObject with Name, Id, Version, Source, Extra.
    #>
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$Lines
    )

    $rows = @()
    if (-not $Lines -or $Lines.Count -eq 0) { return $rows }

    # --- locate the header (line directly above the dashed separator) ---
    $sepIndex = -1
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i].Trim() -match '^-{5,}$') { $sepIndex = $i; break }
    }
    if ($sepIndex -lt 1) { return $rows }

    $header = $Lines[$sepIndex - 1]
    if ([string]::IsNullOrWhiteSpace($header)) { return $rows }

    # --- derive column start offsets from the header ---
    # Header cells are separated by two or more spaces.
    $headerCells = @($header -split '\s{2,}' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($headerCells.Count -lt 2) { return $rows }

    $colStarts = @()
    $searchFrom = 0
    foreach ($cell in $headerCells) {
        $idx = $header.IndexOf($cell, $searchFrom)
        if ($idx -lt 0) { $idx = $searchFrom }
        $colStarts += $idx
        $searchFrom = $idx + $cell.Length
    }

    # --- map known header names to column indexes (fallback: position) ---
    $map = @{}
    for ($c = 0; $c -lt $headerCells.Count; $c++) {
        $map[$headerCells[$c].Trim().ToLowerInvariant()] = $c
    }

    function Get-ColIndex {
        param([hashtable]$Map, [string[]]$Names, [int]$Fallback, [int]$ColumnCount)
        foreach ($n in $Names) {
            if ($Map.ContainsKey($n)) { return $Map[$n] }
        }
        if ($Fallback -lt $ColumnCount) { return $Fallback }
        return -1
    }

    $colCount = $colStarts.Count
    $iName    = Get-ColIndex -Map $map -Names @('name')                    -Fallback 0 -ColumnCount $colCount
    $iId      = Get-ColIndex -Map $map -Names @('id')                      -Fallback 1 -ColumnCount $colCount
    $iVersion = Get-ColIndex -Map $map -Names @('version')                 -Fallback 2 -ColumnCount $colCount
    $iExtra   = Get-ColIndex -Map $map -Names @('match', 'available')      -Fallback 3 -ColumnCount $colCount
    $iSource  = Get-ColIndex -Map $map -Names @('source')                  -Fallback ($colCount - 1) -ColumnCount $colCount

    # If the header had no recognisable 'Source' and only 4 columns exist,
    # the 4th is Source, not Match/Available (winget drops Match on exact hits).
    if ($iSource -eq $iExtra) { $iExtra = -1 }

    # --- slice each data line on the header offsets ---
    for ($i = $sepIndex + 1; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i]
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line.Trim() -match '^-{5,}$') { continue }

        $cells = @()
        for ($c = 0; $c -lt $colCount; $c++) {
            $start = $colStarts[$c]
            if ($start -ge $line.Length) {
                $cells += ''
                continue
            }
            if ($c -lt ($colCount - 1)) {
                $end = [Math]::Min($colStarts[$c + 1], $line.Length)
            }
            else {
                $end = $line.Length
            }
            if ($end -le $start) { $cells += ''; continue }
            $cells += $line.Substring($start, $end - $start).Trim()
        }

        $id = if ($iId -ge 0) { $cells[$iId] } else { '' }
        # A row without an Id is a footer/notice line, not a package.
        if ([string]::IsNullOrWhiteSpace($id)) { continue }

        $rows += [PSCustomObject]@{
            Name    = if ($iName    -ge 0) { $cells[$iName] }    else { '' }
            Id      = $id
            Version = if ($iVersion -ge 0) { $cells[$iVersion] } else { '' }
            Extra   = if ($iExtra   -ge 0) { $cells[$iExtra] }   else { '' }
            Source  = if ($iSource  -ge 0) { $cells[$iSource] }  else { '' }
        }
    }

    return $rows
}

#========================================================================
# Get WinGet installed packages
#========================================================================
function Get-WinGetApps {
    <#
    .SYNOPSIS
        Lists all packages winget knows about on this machine.
    .DESCRIPTION
        Returns installed packages with their Name, Id, Version, the
        available upgrade version (if any) and the source.
    .OUTPUTS
        Array of PSCustomObject: Name, Id, Version, Available, Source
    #>
    try {
        $result = Invoke-WinGet -Arguments @('list', '--accept-source-agreements', '--disable-interactivity')

        $rows = ConvertFrom-WinGetTable -Lines $result.Lines

        # A non-zero exit with rows parsed is not fatal (e.g. partial source failure).
        if ($result.ExitCode -ne 0 -and $rows.Count -eq 0) {
            throw (Get-WinGetExitMessage -ExitCode $result.ExitCode)
        }

        return @($rows | ForEach-Object {
            [PSCustomObject]@{
                Name      = $_.Name
                Id        = $_.Id
                Version   = $_.Version
                Available = $_.Extra
                Source    = $_.Source
            }
        })
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
        Searches configured winget sources for available packages.
    .PARAMETER Query
        Search term for the package.
    .OUTPUTS
        Array of PSCustomObject: Name, Id, Version, Match, Source
        (empty array when nothing matches - that is not an error)
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Query
    )

    try {
        $result = Invoke-WinGet -Arguments @('search', '--query', $Query, '--accept-source-agreements', '--disable-interactivity')

        # 0x8A150014 - "No package found matching input criteria". Empty result, not a failure.
        if ($result.ExitCode -eq -1978335212) { return @() }

        $rows = ConvertFrom-WinGetTable -Lines $result.Lines

        if ($result.ExitCode -ne 0 -and $rows.Count -eq 0) {
            throw (Get-WinGetExitMessage -ExitCode $result.ExitCode)
        }

        return @($rows | ForEach-Object {
            [PSCustomObject]@{
                Name    = $_.Name
                Id      = $_.Id
                Version = $_.Version
                Match   = $_.Extra
                Source  = $_.Source
            }
        })
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
        Installs a single WinGet package by package ID.
    .PARAMETER PackageId
        The exact WinGet package ID to install (e.g. "Notepad++.Notepad++").
    .PARAMETER Silent
        Request a silent install (no installer UI).
    .OUTPUTS
        PSCustomObject: Success (bool), ExitCode (int), Message (string)
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$PackageId,

        [Parameter(Mandatory = $false)]
        [switch]$Silent
    )

    try {
        # --id + --exact avoids ambiguous matches; a bare query can hit several
        # packages and winget then refuses with "multiple packages found".
        $wingetArgs = @(
            'install',
            '--id', $PackageId,
            '--exact',
            '--accept-package-agreements',
            '--accept-source-agreements',
            '--disable-interactivity'
        )

        # --silent and --interactive are mutually exclusive execution behaviours;
        # passing both makes winget bail out with 0x8A150002 before doing anything.
        if ($Silent) { $wingetArgs += '--silent' }

        $result = Invoke-WinGet -Arguments $wingetArgs

        # winget reports "already installed / no newer version" with a non-zero
        # code. The requested end state holds, so don't call that a failure.
        $upToDate = ($script:WinGetUpToDateCodes -contains $result.ExitCode)

        return [PSCustomObject]@{
            Success  = ($result.ExitCode -eq 0 -or $upToDate)
            ExitCode = $result.ExitCode
            Message  = if ($result.ExitCode -eq 0) {
                'Installed successfully'
            }
            elseif ($upToDate) {
                'Already installed and up to date'
            }
            else {
                Get-WinGetFailureText -Result $result
            }
        }
    }
    catch {
        throw "Failed to install WinGet app '$PackageId': $_"
    }
}

#========================================================================
# Build a readable failure message from a winget result
#========================================================================
function Get-WinGetFailureText {
    <#
    .SYNOPSIS
        Combines winget's own error text with the mapped exit code.
    .PARAMETER Result
        The object returned by Invoke-WinGet.
    .OUTPUTS
        String suitable for the activity log.
    #>
    param(
        [Parameter(Mandatory = $true)]
        $Result
    )

    $codeText = Get-WinGetExitMessage -ExitCode $Result.ExitCode

    # winget prints the reason near the end; take the last meaningful line
    # but skip its usage/help dump, which is long and unhelpful in a log.
    $meaningful = @($Result.Lines | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_) -and
        $_ -notmatch '^\s*(usage:|The following|  -|Windows Package Manager|Copyright|More help)' -and
        $_ -notmatch 'All rights reserved'
    })

    if ($meaningful.Count -gt 0) {
        $last = $meaningful[$meaningful.Count - 1].Trim()
        # Don't repeat ourselves when winget's text already says the same thing
        # (differing only by trailing punctuation).
        if ($last.TrimEnd('.', '!') -ne $codeText.TrimEnd('.', '!')) {
            return "$codeText - $last"
        }
        return $last
    }

    return $codeText
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
        Request silent installs (no installer UI).
    .OUTPUTS
        Array of PSCustomObject: PackageId, Success, ExitCode, Message
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$PackageIds,

        [Parameter(Mandatory = $false)]
        [switch]$Silent
    )

    $results = @()

    foreach ($pkgId in $PackageIds) {
        if ([string]::IsNullOrWhiteSpace($pkgId)) { continue }

        try {
            $outcome = Install-WinGetApp -PackageId $pkgId -Silent:$Silent
            $results += [PSCustomObject]@{
                PackageId = $pkgId
                Success   = $outcome.Success
                ExitCode  = $outcome.ExitCode
                Message   = $outcome.Message
            }
        }
        catch {
            $results += [PSCustomObject]@{
                PackageId = $pkgId
                Success   = $false
                ExitCode  = $null
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
        Upgrades all installed WinGet packages.
    .PARAMETER All
        Also upgrade packages whose installed version winget cannot determine
        (adds --include-unknown).
    .OUTPUTS
        PSCustomObject: Success (bool), ExitCode (int), Message (string)
    #>
    param(
        [Parameter(Mandatory = $false)]
        [switch]$All
    )

    try {
        $wingetArgs = @(
            'upgrade',
            '--all',
            '--silent',
            '--accept-package-agreements',
            '--accept-source-agreements',
            '--disable-interactivity'
        )
        if ($All) { $wingetArgs += '--include-unknown' }

        $result = Invoke-WinGet -Arguments $wingetArgs

        # "Already up to date" means nothing needed doing - not a failure.
        $ok = ($result.ExitCode -eq 0 -or ($script:WinGetUpToDateCodes -contains $result.ExitCode))

        return [PSCustomObject]@{
            Success  = $ok
            ExitCode = $result.ExitCode
            Message  = if ($ok) {
                if ($result.ExitCode -eq 0) { 'Update complete' } else { 'Everything is already up to date' }
            }
            else {
                Get-WinGetFailureText -Result $result
            }
        }
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
        Uninstalls a WinGet package by package ID.
    .PARAMETER PackageId
        The exact WinGet package ID to uninstall.
    .OUTPUTS
        PSCustomObject: Success (bool), ExitCode (int), Message (string)
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$PackageId
    )

    try {
        $result = Invoke-WinGet -Arguments @(
            'uninstall',
            '--id', $PackageId,
            '--exact',
            '--silent',
            '--accept-source-agreements',
            '--disable-interactivity'
        )

        return [PSCustomObject]@{
            Success  = ($result.ExitCode -eq 0)
            ExitCode = $result.ExitCode
            Message  = if ($result.ExitCode -eq 0) { 'Uninstalled successfully' } else { Get-WinGetFailureText -Result $result }
        }
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
