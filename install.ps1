# WinTuner Installation Script
# This script downloads and sets up WinTuner on your system

$ErrorActionPreference = "Stop"

Write-Host "=== WinTuner Installation ===" -ForegroundColor Cyan
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

# Download the repository
Write-Host "Downloading WinTuner..." -ForegroundColor Cyan
$tempZip = "$env:TEMP\WinTuner.zip"
$repoUrl = "https://github.com/iefken/WinTuner/archive/refs/heads/main.zip"

try {
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
    $extractedDir = "$env:TEMP\WinTuner-main"
    
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
    Remove-Item $extractedDir -Recurse -ErrorAction SilentlyContinue
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
Write-Host ""
Write-Host "To run WinTuner:" -ForegroundColor Cyan
Write-Host "  1. Double-click the desktop shortcut"
Write-Host "  2. Or run: powershell -ExecutionPolicy Bypass -File `"$installDir\Main.ps1`""
Write-Host ""
Write-Host "For full functionality, right-click and select 'Run as Administrator'" -ForegroundColor Yellow
Write-Host ""
