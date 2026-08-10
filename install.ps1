<#
.SYNOPSIS
    Installs WinTuner to %USERPROFILE%\WinTuner and creates the shortcuts.

.DESCRIPTION
    By default the current published code is downloaded from GitHub 'main'.
    Use -Local to install straight from this working copy instead, which is
    what you want when testing a change before pushing it.

.PARAMETER Local
    Install from the folder this script lives in rather than downloading.
    '.git', '.claude' and 'logs' are not copied.

.EXAMPLE
    .\install.ps1
    Downloads and installs the published version from GitHub main.

.EXAMPLE
    .\install.ps1 -Local
    Installs the working copy as-is, without touching the network.
#>
[CmdletBinding()]
param(
    [switch]$Local
)

$ErrorActionPreference = "Stop"

$mode = if ($Local) { 'local working copy' } else { 'GitHub main' }
Write-Host "=== WinTuner Installation ($mode) ===" -ForegroundColor Cyan
Write-Host ""

# Check if running as Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Warning "WinTuner should be run as Administrator for full functionality."
    Write-Host "Continuing installation anyway..." -ForegroundColor Yellow
    Write-Host ""
}

# Determine installation directory
$installDir = "$env:USERPROFILE\WinTuner"
Write-Host "Installing to: $installDir" -ForegroundColor Cyan

# Create installation directory if it doesn't exist
if (-not (Test-Path $installDir)) {
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
    Write-Host "Created installation directory" -ForegroundColor Green
}

#------------------------------------------------------------------------
# Shared install rules
#
# $excluded  - names never copied out of the source (repo plumbing and
#              local run artefacts). In a git worktree '.git' is a FILE,
#              not a folder, so match on name rather than type.
# $protected - top-level names in the install that pruning must never
#              touch. 'logs' holds the user's saved diagnostics and
#              hardware reports; it does not exist in the source, so
#              without this it would be deleted on every install.
#------------------------------------------------------------------------
$excluded  = @('.git', '.gitignore', '.claude', '.github', 'logs')
$protected = @('logs')

if ($Local) {
    #--------------------------------------------------------------------
    # Install from this working copy - no network, no git state involved.
    # Whatever is on disk right now is what gets installed, including
    # uncommitted edits. That is the point of the switch.
    #--------------------------------------------------------------------
    $sourceDir = $PSScriptRoot
    if ([String]::IsNullOrWhiteSpace($sourceDir)) {
        Write-Error "Cannot resolve the script folder - run install.ps1 from a file, not a pasted snippet."
        exit 1
    }

    Write-Host "Source: $sourceDir" -ForegroundColor Cyan

    # Copying a folder onto itself would silently shred it.
    $srcFull = [System.IO.Path]::GetFullPath($sourceDir).TrimEnd('\')
    $dstFull = [System.IO.Path]::GetFullPath($installDir).TrimEnd('\')
    if ($srcFull -eq $dstFull) {
        Write-Error "Source and install directory are the same ($dstFull). Nothing to do."
        exit 1
    }

    if (-not (Test-Path (Join-Path $sourceDir 'Main.ps1'))) {
        Write-Error "No Main.ps1 in $sourceDir - this does not look like the WinTuner repo."
        exit 1
    }
}
else {
    #--------------------------------------------------------------------
    # Install the published version from GitHub main.
    #--------------------------------------------------------------------
    Write-Host "Downloading WinTuner..." -ForegroundColor Cyan
    $tempZip = "$env:TEMP\WinTuner.zip"
    $repoUrl = "https://github.com/iefken/WinTuner/archive/refs/heads/main.zip"
    $extractedDir = "$env:TEMP\WinTuner-main"

    try {
        # PS 5.1 can default to TLS 1.0, which GitHub refuses.
        [Net.ServicePointManager]::SecurityProtocol =
            [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

        Invoke-WebRequest -Uri $repoUrl -OutFile $tempZip -UseBasicParsing
        Write-Host "Download complete" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to download WinTuner: $_"
        Write-Host "Please check your internet connection and the repository URL."
        exit 1
    }

    # Extract the archive. The copy + prune below needs the extracted tree,
    # so the temp cleanup happens after that, not here.
    Write-Host "Extracting files..." -ForegroundColor Cyan
    try {
        Expand-Archive -Path $tempZip -DestinationPath $env:TEMP -Force
        Write-Host "Extracted" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to extract files: $_"
        Remove-Item $tempZip -ErrorAction SilentlyContinue
        exit 1
    }

    $sourceDir  = $extractedDir
    $cleanupZip = $tempZip
}

#------------------------------------------------------------------------
# Copy source -> install
#------------------------------------------------------------------------
Write-Host "Copying files..." -ForegroundColor Cyan
try {
    $copied = 0
    Get-ChildItem -LiteralPath $sourceDir -Force |
        Where-Object { $excluded -notcontains $_.Name } |
        ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination $installDir -Recurse -Force
            $copied++
        }
    Write-Host "Copied $copied top-level item(s)" -ForegroundColor Green
}
catch {
    Write-Error "Failed to copy files: $_"
    exit 1
}

#------------------------------------------------------------------------
# Prune files that no longer exist in the source
#
# Copy-Item overwrites but never deletes, so a file renamed or removed in
# the repo used to linger in the install forever - and a stale .ps1 still
# gets dot-sourced by Import-Functions, so orphans are not harmless.
#------------------------------------------------------------------------
Write-Host "Removing files no longer in the source..." -ForegroundColor Cyan
try {
    # Sanity check: only ever prune something that looks like a WinTuner install.
    if (-not (Test-Path (Join-Path $installDir 'Main.ps1'))) {
        throw "No Main.ps1 in $installDir after copying - refusing to prune."
    }

    # Every relative path the install is supposed to contain.
    $expected = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($top in (Get-ChildItem -LiteralPath $sourceDir -Force | Where-Object { $excluded -notcontains $_.Name })) {
        $null = $expected.Add($top.Name)
        if ($top.PSIsContainer) {
            foreach ($child in (Get-ChildItem -LiteralPath $top.FullName -Recurse -Force)) {
                $null = $expected.Add($child.FullName.Substring($sourceDir.Length).TrimStart('\'))
            }
        }
    }

    # Walk the install deepest-first so children go before their parents.
    $removed = 0
    $candidates = Get-ChildItem -LiteralPath $installDir -Recurse -Force |
                  Sort-Object { $_.FullName.Length } -Descending

    foreach ($item in $candidates) {
        # A parent may already have taken this one with it.
        if (-not (Test-Path -LiteralPath $item.FullName)) { continue }

        $rel     = $item.FullName.Substring($installDir.Length).TrimStart('\')
        $topName = ($rel -split '\\')[0]

        if ($protected -contains $topName) { continue }
        if ($expected.Contains($rel))      { continue }

        Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop
        Write-Host "  removed $rel" -ForegroundColor DarkYellow
        $removed++
    }

    if ($removed -gt 0) { Write-Host "Removed $removed orphaned item(s)" -ForegroundColor Green }
    else                { Write-Host "Nothing to remove" -ForegroundColor Green }
}
catch {
    # A failed prune leaves a working (if untidy) install - do not abort.
    Write-Warning "Could not finish pruning: $_"
}

# Temp artefacts from the download path
if ($cleanupZip)   { Remove-Item $cleanupZip -ErrorAction SilentlyContinue }
if (-not $Local -and $sourceDir) { Remove-Item $sourceDir -Recurse -Force -ErrorAction SilentlyContinue }

# Create a desktop shortcut (optional)
$desktopPath = [Environment]::GetFolderPath("Desktop")
$shortcutPath = "$desktopPath\WinTuner.lnk"
$wshShell = New-Object -ComObject WScript.Shell

# The shortcut targets powershell.exe, so without an explicit icon Windows
# shows the PowerShell logo on the desktop and in the Start Menu. Point it
# at the app's own .ico (index 0) instead.
$shortcutIcon = Join-Path $installDir 'wintuner.ico'
if (-not (Test-Path $shortcutIcon)) {
    Write-Warning "Icon not found at $shortcutIcon - shortcuts will use the PowerShell icon"
    $shortcutIcon = $null
}

try {
    $shortcut = $wshShell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = "powershell.exe"
    $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$installDir\Main.ps1`""
    $shortcut.WorkingDirectory = $installDir
    $shortcut.Description = "WinTuner - Windows PC Management Tool"
    if ($shortcutIcon) { $shortcut.IconLocation = "$shortcutIcon,0" }
    $shortcut.Save()
    Write-Host "Desktop shortcut created" -ForegroundColor Green
}
catch {
    Write-Warning "Could not create desktop shortcut: $_"
}

# Create a Start Menu shortcut (optional)
$startMenuPath = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs"
$startMenuShortcutPath = "$startMenuPath\WinTuner.lnk"

try {
    $shortcut = $wshShell.CreateShortcut($startMenuShortcutPath)
    $shortcut.TargetPath = "powershell.exe"
    $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$installDir\Main.ps1`""
    $shortcut.WorkingDirectory = $installDir
    $shortcut.Description = "WinTuner - Windows PC Management Tool"
    if ($shortcutIcon) { $shortcut.IconLocation = "$shortcutIcon,0" }
    $shortcut.Save()
    Write-Host "Start Menu shortcut created" -ForegroundColor Green
}
catch {
    Write-Warning "Could not create Start Menu shortcut: $_"
}

Write-Host ""
Write-Host "=== Installation Complete ===" -ForegroundColor Green

# Report what actually landed, so a stale install is obvious at a glance.
try {
    $installedIni = Get-Content (Join-Path $installDir 'ini.json') -Raw | ConvertFrom-Json
    $installedVer = ($installedIni | Where-Object { $_.Profile } | Select-Object -First 1).AppVersion
    Write-Host "Installed version: v$installedVer  ($mode)" -ForegroundColor Green
}
catch {
    Write-Warning "Could not read the installed version: $_"
}

Write-Host ""
Write-Host "To run WinTuner:" -ForegroundColor Cyan
Write-Host "  1. Double-click the desktop shortcut"
Write-Host "  2. Or run: powershell -ExecutionPolicy Bypass -File `"$installDir\Main.ps1`""
Write-Host ""
Write-Host "For full functionality, right-click and select 'Run as Administrator'" -ForegroundColor Yellow
Write-Host ""
