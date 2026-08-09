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

    # Repo plumbing and local run artefacts have no business in the install.
    # NOTE: in a git worktree '.git' is a file, not a folder - match by name.
    $excluded = @('.git', '.gitignore', '.claude', '.github', 'logs')

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
        Write-Error "Failed to copy the working copy: $_"
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

    # Extract the archive
    Write-Host "Extracting files..." -ForegroundColor Cyan
    try {
        Expand-Archive -Path $tempZip -DestinationPath $env:TEMP -Force

        # Copy files to installation directory
        Copy-Item -Path "$extractedDir\*" -Destination $installDir -Recurse -Force
        Write-Host "Files extracted successfully" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to extract files: $_"
        exit 1
    }
    finally {
        # Cleanup
        Remove-Item $tempZip -ErrorAction SilentlyContinue
        Remove-Item $extractedDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Create a desktop shortcut (optional)
$desktopPath = [Environment]::GetFolderPath("Desktop")
$shortcutPath = "$desktopPath\WinTuner.lnk"
$wshShell = New-Object -ComObject WScript.Shell

try {
    $shortcut = $wshShell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = "powershell.exe"
    $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$installDir\Main.ps1`""
    $shortcut.WorkingDirectory = $installDir
    $shortcut.Description = "WinTuner - Windows PC Management Tool"
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
