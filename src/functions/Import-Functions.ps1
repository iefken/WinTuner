#========================================================================
# Import-Functions.ps1 — dynamic, exclusion-based function loader
#
# Loads every *.ps1 under src/functions/ EXCEPT:
#   - the loader files themselves (FilesToIgnore)
#   - the folders in FoldersToIgnore (e.g. startup, which Config.ps1
#     dot-sources explicitly, and standalone/old archives)
#
# To add a new function file: drop it into src/functions/ (root) or any
# non-ignored subfolder and it loads automatically. To keep a NEW folder
# from auto-loading, add its name to $FoldersToIgnore below.
#========================================================================

$LocalPath = "$Global:ConfigFiles\src\functions"

$FilesToIgnore = @(
    'Config.ps1',
    'Import-Functions.ps1'
)

$FoldersToIgnore = @(
    'backup',
    'old',
    'startup',     # Load-XamlForm.ps1 is dot-sourced directly by Config.ps1
    'standalone'   # archived / run-on-demand scripts; never auto-load
)

#------------------------------------------------------------------------
# 1. Root-level files
#------------------------------------------------------------------------

$LocalPathFiles = Get-ChildItem -Path $LocalPath -File -Filter '*.ps1'
foreach ($File in $LocalPathFiles) {
    if (-not ($FilesToIgnore -contains $File.Name)) {
        if ($debug) { Write-Host "Loading $($File.Name)" }
        . $File.FullName
    }
}

#------------------------------------------------------------------------
# 2. Sub-folders (recursive), skipping the ignore-list
#------------------------------------------------------------------------

$LocalPathDirectories = Get-ChildItem -Path $LocalPath -Directory
foreach ($Directory in $LocalPathDirectories) {
    if ($FoldersToIgnore -contains $Directory.Name) { continue }

    $Files = Get-ChildItem -Path $Directory.FullName -Filter '*.ps1' -File -Recurse
    foreach ($File in $Files) {
        if (-not ($FilesToIgnore -contains $File.Name)) {
            if ($debug) { Write-Host "Loading $($File.Name)" }
            . $File.FullName
        }
    }
}
