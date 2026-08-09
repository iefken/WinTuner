<#
.SYNOPSIS
    Dev-mode startup test for PC Management Tool.
    Walks the full Main.ps1 load chain step by step, reporting
    PASS / WARN / FAIL per stage — without showing the GUI (unless asked).

.NOTES
    Run from anywhere:  .\src\dev\Test-DevStartup.ps1
    Any new FAIL that wasn't there before your change is a regression.
#>

Clear-Host

$results   = [System.Collections.Generic.List[PSCustomObject]]::new()

function Write-Step { param([string]$msg)
    Write-Host ""
    Write-Host "  ---- $msg" -ForegroundColor DarkCyan
}

function Add-Result {
    param([string]$Step, [string]$Status, [string]$Detail = "")
    $script:results.Add([PSCustomObject]@{ Step = $Step; Status = $Status; Detail = $Detail })
    switch ($Status) {
        'PASS' { Write-Host "  [PASS] $Step"           -ForegroundColor Green  }
        'WARN' { Write-Host "  [WARN] $Step : $Detail" -ForegroundColor Yellow }
        'FAIL' { Write-Host "  [FAIL] $Step : $Detail" -ForegroundColor Red    }
    }
}

#========================================================================
# Step 0 - Resolve project root (this file lives in src\dev\)
#========================================================================

Write-Step "Step 0 - Environment"

$Global:ConfigFiles = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$Global:IniPath     = Join-Path $Global:ConfigFiles 'ini.json'
Add-Result "Project root: $Global:ConfigFiles" "PASS"

#========================================================================
# Step 1 - Load ini.json (active profile)
#========================================================================

Write-Step "Step 1 - ini.json"

try {
    if (-not (Test-Path $Global:IniPath)) { throw "File not found: $Global:IniPath" }

    $AllIni        = Get-Content $Global:IniPath -Raw | ConvertFrom-Json
    $ActiveProfile = $AllIni[0].ActiveProfile
    if ([String]::IsNullOrEmpty($ActiveProfile)) { $ActiveProfile = 'home' }

    $Global:IniFile = $AllIni | Where-Object { $_.Profile -eq $ActiveProfile }
    if ($null -eq $Global:IniFile) { throw "Active profile '$ActiveProfile' not found" }

    $Global:ConfigPath = Join-Path $Global:ConfigFiles $Global:IniFile.ConfigPath
    $Global:LogPath    = Join-Path $Global:ConfigFiles $Global:IniFile.LogPath
    $Global:AppVersion = $Global:IniFile.AppVersion

    Add-Result "ini.json loaded (profile: $ActiveProfile, v$Global:AppVersion)" "PASS"
}
catch {
    Add-Result "ini.json" "FAIL" $_.Exception.Message
    Write-Host "`n  Cannot continue without ini.json. Aborting." -ForegroundColor Red
    exit 1
}

#========================================================================
# Step 2 - Config.ps1 (assemblies, XAML parse, function import)
#========================================================================

Write-Step "Step 2 - Config.ps1"

try {
    if (-not (Test-Path $Global:ConfigPath)) { throw "File not found: $Global:ConfigPath" }
    . $Global:ConfigPath
    Add-Result "Config.ps1 loaded" "PASS"
}
catch {
    Add-Result "Config.ps1" "FAIL" $_.Exception.Message
    Write-Host "`n  Cannot continue without Config.ps1. Aborting." -ForegroundColor Red
    exit 1
}

#========================================================================
# Step 3 - Key .NET assemblies
#========================================================================

Write-Step "Step 3 - .NET assemblies"

@('PresentationFramework', 'System.Windows.Forms', 'System.Data') | ForEach-Object {
    try {
        Add-Type -AssemblyName $_ -ErrorAction Stop
        Add-Result "Assembly: $_" "PASS"
    }
    catch {
        Add-Result "Assembly: $_" "FAIL" $_.Exception.Message
    }
}

#========================================================================
# Step 4 - WPF form parsed
#========================================================================

Write-Step "Step 4 - WPF form"

if ($null -ne $Global:Form) {
    Add-Result "`$global:Form (XAML parsed)" "PASS"
}
else {
    Add-Result "`$global:Form is null — Load-XamlForm.ps1 may have failed" "FAIL"
}

#========================================================================
# Step 5 - Named control globals exposed
#========================================================================

Write-Step "Step 5 - Named controls"

@('richtxt_Log', 'cbx_GetFeedbackMessages', 'txt_YourUserName', 'txt_YourPcName',
  'cmb_LocalPS', 'cmb_LocalPS_Desc', 'cmb_LocalPS_Command', 'btn_Run_LocalPS', 'txt_cmdline_LocalPS') | ForEach-Object {
    $ctrl = Get-Variable -Name $_ -Scope Global -ValueOnly -ErrorAction SilentlyContinue
    if ($null -ne $ctrl) { Add-Result "Control: `$$_" "PASS" }
    else                 { Add-Result "Control: `$$_" "FAIL" "Not exposed by Load-XamlForm.ps1" }
}

#========================================================================
# Step 6 - Global handler instance
#========================================================================

Write-Step "Step 6 - GUI handler"

$instance = Get-Variable -Name 'GUIHandler' -Scope Global -ValueOnly -ErrorAction SilentlyContinue
if ($null -ne $instance) { Add-Result "`$global:GUIHandler (GUI_Handler)" "PASS" }
else                     { Add-Result "`$global:GUIHandler" "FAIL" "Variable is null or not set" }

#========================================================================
# Step 7 - Core methods present on GUI_Handler
#========================================================================

Write-Step "Step 7 - GUI_Handler methods"

@('Visual_Log', 'Get_Userdata', 'Launch_GUI', 'Format_RichTextBox', 'To_ConsoleColor',
  'Get_PS_Command_By_Description') | ForEach-Object {
    if ([GUI_Handler].GetMethods().Name -contains $_) { Add-Result "GUI_Handler.$_" "PASS" }
    else                                              { Add-Result "GUI_Handler.$_" "FAIL" "Method not found" }
}

# Every log colour must map to a real ConsoleColor - 'Orange' is a valid WPF
# brush but not a ConsoleColor, and Write-Host throws on it.
$consoleColors = [System.Enum]::GetNames([System.ConsoleColor])
$badColor = @('Orange', 'Red', 'Green', 'Cyan', 'Gray', 'Yellow', '', 'NotAColour') |
    Where-Object { $consoleColors -notcontains $global:GUIHandler.To_ConsoleColor($_) }
if (-not $badColor) { Add-Result "Log colours map to valid ConsoleColors" "PASS" }
else { Add-Result "Log colours map to valid ConsoleColors" "FAIL" "unmapped: $($badColor -join ', ')" }

# Visual_Log with the console echo on must not throw, whatever the colour.
try {
    $echoWasOn = $global:cbx_GetFeedbackMessages.IsChecked
    $global:cbx_GetFeedbackMessages.IsChecked = $true
    $global:GUIHandler.Visual_Log($env:COMPUTERNAME, 'startup test - colour probe', 'Orange')
    $global:GUIHandler.Visual_Log($env:COMPUTERNAME, 'startup test - colour probe', 'NotAColour')
    $global:cbx_GetFeedbackMessages.IsChecked = $echoWasOn
    Add-Result "Visual_Log survives non-console colours with echo on" "PASS"
}
catch {
    $global:cbx_GetFeedbackMessages.IsChecked = $false
    Add-Result "Visual_Log survives non-console colours with echo on" "FAIL" $_.Exception.Message
}

#========================================================================
# Step 8 - Local PS feature (functions, presets, lookup)
#========================================================================

Write-Step "Step 8 - Local PS feature"

@('Handle-btn_Run_LocalPS', 'Handle-btn_Clear_LocalPS', 'Handle-PS-cmb', 'Add_Click_listeners') | ForEach-Object {
    if (Get-Command $_ -ErrorAction SilentlyContinue) { Add-Result "Function: $_" "PASS" }
    else                                              { Add-Result "Function: $_" "FAIL" "Not loaded" }
}

# Presets loaded into the dropdown by Prepare_ComboBoxes
[GUI_Handler]::Prepare_ComboBoxes()
$presetCount = ($global:PwsCommandsFullList | Measure-Object).Count
if ($presetCount -gt 0) { Add-Result "pws_commands presets loaded ($presetCount)" "PASS" }
else                    { Add-Result "pws_commands presets" "FAIL" "PwsCommandsFullList empty" }

# Round-trip: description -> command lookup
$firstDesc = $global:PwsCommandsFullList | Select-Object -First 1
$cmd = $global:GUIHandler.Get_PS_Command_By_Description($firstDesc)
if (-not [String]::IsNullOrEmpty($cmd)) { Add-Result "Description->command lookup" "PASS" $firstDesc }
else                                    { Add-Result "Description->command lookup" "FAIL" "Empty for: $firstDesc" }

#========================================================================
# Step 9 - File Cleanup feature (controls, functions, utilities)
#========================================================================

Write-Step "Step 9 - File Cleanup feature"

@('cmb_FC_Path', 'txt_FC_Filter', 'chk_FC_Recurse', 'chk_FC_Recycle',
  'btn_FC_Preview', 'btn_FC_Delete', 'dgr_FC_Results') | ForEach-Object {
    $ctrl = Get-Variable -Name $_ -Scope Global -ValueOnly -ErrorAction SilentlyContinue
    if ($null -ne $ctrl) { Add-Result "Control: `$$_" "PASS" }
    else                 { Add-Result "Control: `$$_" "FAIL" "Not exposed by Load-XamlForm.ps1" }
}

@('Handle-btn_FC_Browse', 'Handle-btn_FC_Preview', 'Handle-btn_FC_Delete',
  'Get-FileLockProcess', 'Get-FileEncoding') | ForEach-Object {
    if (Get-Command $_ -ErrorAction SilentlyContinue) { Add-Result "Function: $_" "PASS" }
    else                                              { Add-Result "Function: $_" "FAIL" "Not loaded" }
}

# common_paths presets loaded into the folder dropdown
$pathCount = ($global:cmb_FC_Path.Items.Count)
if ($pathCount -gt 0) { Add-Result "common_paths presets loaded ($pathCount)" "PASS" }
else                  { Add-Result "common_paths presets" "FAIL" "cmb_FC_Path empty" }

# Recycle Bin API reachable (Microsoft.VisualBasic loaded)
if ([Microsoft.VisualBasic.FileIO.FileSystem] -as [type]) { Add-Result "Recycle Bin API available" "PASS" }
else                                                       { Add-Result "Recycle Bin API" "FAIL" "Microsoft.VisualBasic not loaded" }

#========================================================================
# Step 10 - Registry tweaks feature (controls, presets, read/write)
#========================================================================

Write-Step "Step 10 - Registry tweaks feature"

@('cmb_Reg_Tweak', 'txt_Reg_Path', 'dgr_Reg_Entries', 'btn_Reg_GetValue', 'btn_Reg_Apply') | ForEach-Object {
    $ctrl = Get-Variable -Name $_ -Scope Global -ValueOnly -ErrorAction SilentlyContinue
    if ($null -ne $ctrl) { Add-Result "Control: `$$_" "PASS" }
    else                 { Add-Result "Control: `$$_" "FAIL" "Not exposed by Load-XamlForm.ps1" }
}

@('Handle-cmb_Reg_Tweak', 'Handle-btn_Reg_GetValue', 'Handle-btn_Reg_Apply') | ForEach-Object {
    if (Get-Command $_ -ErrorAction SilentlyContinue) { Add-Result "Function: $_" "PASS" }
    else                                              { Add-Result "Function: $_" "FAIL" "Not loaded" }
}

@('Test_IsAdmin', 'Get_RegistryValue', 'Set_RegistryValue') | ForEach-Object {
    if ([GUI_Handler].GetMethods().Name -contains $_) { Add-Result "GUI_Handler.$_" "PASS" }
    else                                              { Add-Result "GUI_Handler.$_" "FAIL" "Method not found" }
}

$tweakCount = ($global:cmb_Reg_Tweak.Items.Count)
if ($tweakCount -gt 0) { Add-Result "registry_tweaks presets loaded ($tweakCount)" "PASS" }
else                   { Add-Result "registry_tweaks presets" "FAIL" "cmb_Reg_Tweak empty" }

# Live read/write round-trip on a throwaway HKCU key (no admin needed)
$testKey = 'HKEY_CURRENT_USER\Software\PcManagementTool\DevTest'
try {
    $wrote = $global:GUIHandler.Set_RegistryValue($testKey, 'Probe', 'DWord', '7')
    $read  = $global:GUIHandler.Get_RegistryValue($testKey, 'Probe')
    Remove-Item -LiteralPath "Registry::$testKey" -Recurse -Force -ErrorAction SilentlyContinue
    if ($wrote -and $read -eq '7') { Add-Result "Registry read/write round-trip" "PASS" "wrote 7, read $read" }
    else                           { Add-Result "Registry read/write round-trip" "FAIL" "wrote=$wrote read=$read" }
}
catch {
    Add-Result "Registry read/write round-trip" "FAIL" $_.Exception.Message
}

#========================================================================
# Step 11 - COM Ports feature (controls, functions, snapshot)
#========================================================================

Write-Step "Step 11 - COM Ports feature"

@('btn_COM_Start', 'btn_COM_Stop', 'btn_COM_Refresh', 'chk_COM_Beep', 'dgr_COM_Results', 'lbl_COM_Status') | ForEach-Object {
    $ctrl = Get-Variable -Name $_ -Scope Global -ValueOnly -ErrorAction SilentlyContinue
    if ($null -ne $ctrl) { Add-Result "Control: `$$_" "PASS" }
    else                 { Add-Result "Control: `$$_" "FAIL" "Not exposed by Load-XamlForm.ps1" }
}

@('Get-ComFromName', 'Get-ComPortSnapshot', 'Handle-btn_COM_Start', 'Handle-btn_COM_Stop',
  'Handle-btn_COM_Refresh', 'Handle-COM_Poll', 'Add-ComRow') | ForEach-Object {
    if (Get-Command $_ -ErrorAction SilentlyContinue) { Add-Result "Function: $_" "PASS" }
    else                                              { Add-Result "Function: $_" "FAIL" "Not loaded" }
}

# Snapshot must run and return an array (0 ports is valid on a laptop)
try {
    $snap = @(Get-ComPortSnapshot)
    Add-Result "Get-ComPortSnapshot ran ($($snap.Count) port(s))" "PASS"
}
catch {
    Add-Result "Get-ComPortSnapshot" "FAIL" $_.Exception.Message
}

# COM name parser sanity
if ((Get-ComFromName 'USB Serial Device (COM7)') -eq 'COM7') { Add-Result "Get-ComFromName parses COM7" "PASS" }
else                                                          { Add-Result "Get-ComFromName" "FAIL" "did not parse COM7" }

#========================================================================
# Step 12 - Diagnostics feature (controls, functions, job)
#========================================================================

Write-Step "Step 12 - Diagnostics feature"

@('txt_Diag_Target', 'txt_Diag_PingCount', 'chk_Diag_IPConfig', 'chk_Diag_NSLookup',
  'chk_Diag_Ping', 'chk_Diag_Tracert', 'btn_Diag_Run', 'btn_Diag_Stop',
  'btn_Diag_Clear', 'btn_Diag_Save', 'txt_Diag_Output') | ForEach-Object {
    $ctrl = Get-Variable -Name $_ -Scope Global -ValueOnly -ErrorAction SilentlyContinue
    if ($null -ne $ctrl) { Add-Result "Control: `$$_" "PASS" }
    else                 { Add-Result "Control: `$$_" "FAIL" "Not exposed by Load-XamlForm.ps1" }
}

@('Handle-btn_Diag_Run', 'Handle-Diag_Poll', 'Handle-btn_Diag_Stop',
  'Handle-btn_Diag_Clear', 'Handle-btn_Diag_Save') | ForEach-Object {
    if (Get-Command $_ -ErrorAction SilentlyContinue) { Add-Result "Function: $_" "PASS" }
    else                                              { Add-Result "Function: $_" "FAIL" "Not loaded" }
}

# Background-job round-trip: run a quick local 'ipconfig' job like the tab does
try {
    $job = Start-Job -ScriptBlock { ipconfig }
    $null = Wait-Job -Job $job -Timeout 20
    $out = (Receive-Job -Job $job) -join "`n"
    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    if ($out -match 'IPv4|Windows IP') { Add-Result "Diagnostics job round-trip" "PASS" "captured ipconfig output" }
    else                               { Add-Result "Diagnostics job round-trip" "FAIL" "no recognisable output" }
}
catch {
    Add-Result "Diagnostics job round-trip" "FAIL" $_.Exception.Message
}

#========================================================================
# Step 13 - WinGet feature (controls, functions, table parser, live CLI)
#
# The parser checks are the regression guard for the Name/Id column swap
# that made every install target a display name instead of a package ID.
# Nothing here installs, upgrades or removes anything.
#========================================================================

Write-Step "Step 13 - WinGet feature"

@('txt_WinGet_Search', 'cmb_WinGet_Category', 'btn_WinGet_Search', 'btn_WinGet_GetInstalled',
  'btn_WinGet_Clear', 'dgr_WinGet_Apps', 'btn_WinGet_Install', 'btn_WinGet_Update',
  'btn_WinGet_Uninstall', 'lbl_WinGet_Status') | ForEach-Object {
    $ctrl = Get-Variable -Name $_ -Scope Global -ValueOnly -ErrorAction SilentlyContinue
    if ($null -ne $ctrl) { Add-Result "Control: `$$_" "PASS" }
    else                 { Add-Result "Control: `$$_" "FAIL" "Not exposed by Load-XamlForm.ps1" }
}

@('Invoke-WinGet', 'ConvertFrom-WinGetTable', 'Get-WinGetExitMessage', 'Get-WinGetFailureText',
  'Get-WinGetApps', 'Search-WinGetApps', 'Install-WinGetApp', 'Install-WinGetApps',
  'Update-WinGetApps', 'Uninstall-WinGetApp', 'Test-WinGetAvailable') | ForEach-Object {
    if (Get-Command $_ -ErrorAction SilentlyContinue) { Add-Result "Function: $_" "PASS" }
    else                                              { Add-Result "Function: $_" "FAIL" "Not loaded" }
}

@('Handle-btn_WinGet_Search', 'Handle-btn_WinGet_GetInstalled', 'Handle-btn_WinGet_Clear',
  'Handle-btn_WinGet_Install', 'Handle-btn_WinGet_Update', 'Handle-btn_WinGet_Uninstall',
  'Start-WinGetJob', 'Handle-WinGet_Poll', 'Write-WinGetJobItem', 'Set-WinGetControlsEnabled') | ForEach-Object {
    if (Get-Command $_ -ErrorAction SilentlyContinue) { Add-Result "Function: $_" "PASS" }
    else                                              { Add-Result "Function: $_" "FAIL" "Not loaded" }
}

# applications.json prefill (drives the category filter)
if ($global:WinGetAppsList -and @($global:WinGetAppsList).Count -gt 1) {
    Add-Result "applications.json presets loaded ($(@($global:WinGetAppsList).Count))" "PASS"
}
else {
    Add-Result "applications.json presets" "FAIL" "list empty or collapsed to one element"
}

#--- Table parser: 5-column search output (Name Id Version Match Source) ---
try {
    $fmt    = '{0,-30}{1,-31}{2,-11}{3,-25}{4}'
    $sample = @(
        ($fmt -f 'Name', 'Id', 'Version', 'Match', 'Source'),
        ('-' * 100),
        ($fmt -f 'Notepad++',     'Notepad++.Notepad++',        '8.9.7', 'Tag: notepad', 'winget'),
        ($fmt -f 'NoteTab Light', 'FookesHolding.NoteTabLight', '7.2',   'Tag: notepad', 'winget')
    )
    $parsed = @(ConvertFrom-WinGetTable -Lines $sample)

    if ($parsed.Count -ne 2) {
        Add-Result "Parser: search table row count" "FAIL" "got $($parsed.Count), expected 2"
    }
    else {
        Add-Result "Parser: search table row count" "PASS"

        # The bug: Name and Id were read from swapped columns.
        if ($parsed[0].Name -eq 'Notepad++' -and $parsed[0].Id -eq 'Notepad++.Notepad++') {
            Add-Result "Parser: Name/Id not swapped" "PASS"
        }
        else {
            Add-Result "Parser: Name/Id not swapped" "FAIL" "Name='$($parsed[0].Name)' Id='$($parsed[0].Id)'"
        }

        # Names containing spaces used to be shredded by the token regex.
        if ($parsed[1].Name -eq 'NoteTab Light') { Add-Result "Parser: name with spaces" "PASS" }
        else { Add-Result "Parser: name with spaces" "FAIL" "got '$($parsed[1].Name)'" }

        # Source used to pick up the Match column and read 'Tag:'.
        if ($parsed[0].Source -eq 'winget') { Add-Result "Parser: Source column" "PASS" }
        else { Add-Result "Parser: Source column" "FAIL" "got '$($parsed[0].Source)'" }
    }
}
catch {
    Add-Result "Parser: search table" "FAIL" $_.Exception.Message
}

#--- Table parser: 4-column search output (winget drops Match on exact hits) ---
try {
    $fmt4   = '{0,-30}{1,-31}{2,-11}{3}'
    $sample = @(
        ($fmt4 -f 'Name', 'Id', 'Version', 'Source'),
        ('-' * 85),
        ($fmt4 -f 'Notepad++', 'Notepad++.Notepad++', '8.9.7', 'winget')
    )
    $parsed = @(ConvertFrom-WinGetTable -Lines $sample)
    if ($parsed.Count -eq 1 -and $parsed[0].Source -eq 'winget' -and $parsed[0].Id -eq 'Notepad++.Notepad++') {
        Add-Result "Parser: search table without Match column" "PASS"
    }
    else {
        Add-Result "Parser: search table without Match column" "FAIL" "Id='$($parsed[0].Id)' Source='$($parsed[0].Source)'"
    }
}
catch {
    Add-Result "Parser: search table without Match column" "FAIL" $_.Exception.Message
}

#--- Table parser: list output with empty trailing columns ---
try {
    $fmtL   = '{0,-28}{1,-62}{2,-14}{3,-12}{4}'
    $sample = @(
        ($fmtL -f 'Name', 'Id', 'Version', 'Available', 'Source'),
        ('-' * 130),
        ($fmtL -f 'App Installer', 'Microsoft.AppInstaller', '1.29.280.0', '', 'winget'),
        ($fmtL -f '3D Viewer',     'MSIX\Microsoft.Microsoft3DViewer_1.0.125.0_x64__8wekyb3d8bbwe', '1.0.125.0', '', '')
    )
    $parsed = @(ConvertFrom-WinGetTable -Lines $sample)
    # The old regex required a Source token and silently dropped source-less rows.
    if ($parsed.Count -eq 2) { Add-Result "Parser: list rows without a Source" "PASS" }
    else { Add-Result "Parser: list rows without a Source" "FAIL" "got $($parsed.Count), expected 2" }
}
catch {
    Add-Result "Parser: list rows without a Source" "FAIL" $_.Exception.Message
}

#--- Exit-code mapper ---
if ((Get-WinGetExitMessage -ExitCode -1978335230) -match 'Invalid command line') {
    Add-Result "Exit code 0x8A150002 mapped" "PASS"
}
else {
    Add-Result "Exit code 0x8A150002 mapped" "FAIL" "unexpected text"
}

#--- Live winget checks (read-only; nothing is installed or removed) ---
if (-not (Test-WinGetAvailable)) {
    Add-Result "winget CLI present" "WARN" "winget not on PATH - live checks skipped"
}
else {
    Add-Result "winget CLI present" "PASS"

    # Real search must come back with correctly separated Name/Id
    try {
        $hits = @(Search-WinGetApps -Query 'notepad')
        $npp  = $hits | Where-Object { $_.Id -eq 'Notepad++.Notepad++' } | Select-Object -First 1
        if ($npp -and $npp.Name -eq 'Notepad++') {
            Add-Result "Live search returns usable IDs ($($hits.Count) hits)" "PASS"
        }
        elseif ($hits.Count -gt 0) {
            Add-Result "Live search returns usable IDs" "WARN" "$($hits.Count) hits but Notepad++ not among them"
        }
        else {
            Add-Result "Live search returns usable IDs" "FAIL" "no results parsed"
        }
    }
    catch {
        Add-Result "Live search" "FAIL" $_.Exception.Message
    }

    # A search with no matches is an empty result, not an exception
    try {
        $none = @(Search-WinGetApps -Query 'zzqq-no-such-package-zzqq')
        if ($none.Count -eq 0) { Add-Result "Empty search result is not an error" "PASS" }
        else { Add-Result "Empty search result is not an error" "WARN" "got $($none.Count) hits" }
    }
    catch {
        Add-Result "Empty search result is not an error" "FAIL" $_.Exception.Message
    }

    # Installed list must parse (count varies per machine)
    try {
        $installed = @(Get-WinGetApps)
        if ($installed.Count -gt 0) { Add-Result "Live installed list parsed ($($installed.Count) packages)" "PASS" }
        else { Add-Result "Live installed list parsed" "WARN" "no rows parsed" }
    }
    catch {
        Add-Result "Live installed list" "FAIL" $_.Exception.Message
    }

    # Regression guard for the mutually exclusive --silent/--interactive pair:
    # winget must reject this on "package not found" (0x8A150014), never on
    # "invalid arguments" (0x8A150002). Nothing gets installed - the ID is fake.
    try {
        $probe = Install-WinGetApp -PackageId '__wintuner_probe_no_such_package__' -Silent
        if ($probe.ExitCode -eq -1978335230) {
            Add-Result "Install arguments accepted by winget" "FAIL" "winget rejected the argument list: $($probe.Message)"
        }
        elseif ($probe.Success) {
            Add-Result "Install arguments accepted by winget" "WARN" "probe package unexpectedly installed"
        }
        else {
            Add-Result "Install arguments accepted by winget" "PASS" "rejected on lookup, not on args"
        }
    }
    catch {
        Add-Result "Install arguments accepted by winget" "FAIL" $_.Exception.Message
    }
}

#========================================================================
# Step 14 - Hardware Info feature (controls, functions, live scan)
#========================================================================

Write-Step "Step 14 - Hardware Info feature"

@('btn_HW_Refresh', 'btn_HW_Copy', 'btn_HW_Save', 'dgr_HW_Gpu', 'dgr_HW_CpuMem',
  'dgr_HW_Details', 'lbl_HW_Status') | ForEach-Object {
    $ctrl = Get-Variable -Name $_ -Scope Global -ValueOnly -ErrorAction SilentlyContinue
    if ($null -ne $ctrl) { Add-Result "Control: `$$_" "PASS" }
    else                 { Add-Result "Control: `$$_" "FAIL" "Not exposed by Load-XamlForm.ps1" }
}

@('Get-GpuInfo', 'Get-GpuVramBytes', 'Get-CpuInfo', 'Get-MemoryInfo', 'Get-SystemHardware',
  'Get-HardwareSummary', 'Get-CpuMemoryNodes', 'New-HardwareNode', 'Expand-HardwareNodes',
  'Format-MemoryModuleText', 'Format-HardwareReport', 'ConvertTo-HumanSize', 'ConvertTo-VramBytes',
  'Handle-btn_HW_Refresh', 'Handle-btn_HW_Copy', 'Handle-btn_HW_Save', 'Handle-HW_CpuMem_Toggle') | ForEach-Object {
    if (Get-Command $_ -ErrorAction SilentlyContinue) { Add-Result "Function: $_" "PASS" }
    else                                              { Add-Result "Function: $_" "FAIL" "Not loaded" }
}

# Byte formatter sanity (guards the VRAM display path)
if ((ConvertTo-HumanSize -Bytes 12884901888) -eq '12.00 GB') { Add-Result "ConvertTo-HumanSize formats 12 GB" "PASS" }
else                                                          { Add-Result "ConvertTo-HumanSize" "FAIL" "12 GB not formatted as expected" }

# REG_BINARY blob -> byte count (older drivers store VRAM this way)
$blob = [byte[]](0x00, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00)   # 8 GB, little-endian
if ((ConvertTo-VramBytes -RawValue $blob) -eq 8589934592) { Add-Result "ConvertTo-VramBytes reads REG_BINARY" "PASS" }
else                                                       { Add-Result "ConvertTo-VramBytes" "FAIL" "binary blob not decoded" }

# Live scan - must return at least one adapter with a non-zero VRAM figure
try {
    $gpus = @(Get-GpuInfo)
    if ($gpus.Count -gt 0) {
        Add-Result "Get-GpuInfo ran ($($gpus.Count) adapter(s))" "PASS" ($gpus[0].Name)
        if ($gpus[0].VRAMBytes -gt 0) { Add-Result "VRAM detected: $($gpus[0].VRAM)" "PASS" }
        else                          { Add-Result "VRAM detection" "WARN" "0 bytes reported for $($gpus[0].Name)" }
    }
    else {
        Add-Result "Get-GpuInfo" "WARN" "no display adapters reported"
    }
}
catch {
    Add-Result "Get-GpuInfo" "FAIL" $_.Exception.Message
}

# Summary rows feed the details grid and the text report
try {
    $summary = @(Get-HardwareSummary)
    if ($summary.Count -gt 0) { Add-Result "Get-HardwareSummary ran ($($summary.Count) rows)" "PASS" }
    else                      { Add-Result "Get-HardwareSummary" "FAIL" "no rows returned" }

    # The System details grid asks for one section only - CPU/memory have
    # their own grid and must not appear twice.
    $systemRows = @(Get-HardwareSummary -Sections 'System')
    if ($systemRows.Count -gt 0 -and -not ($systemRows | Where-Object { $_.Category -in @('CPU', 'Memory') })) {
        Add-Result "Get-HardwareSummary -Sections System filters ($($systemRows.Count) rows)" "PASS"
    }
    else {
        Add-Result "Get-HardwareSummary -Sections System" "FAIL" "CPU/Memory rows leaked into the System section"
    }

    $report = Format-HardwareReport -Gpus @(Get-GpuInfo) -Summary $summary
    if ($report -match 'GRAPHICS' -and $report -match 'SYSTEM') { Add-Result "Format-HardwareReport builds report" "PASS" }
    else                                                        { Add-Result "Format-HardwareReport" "FAIL" "report missing sections" }
}
catch {
    Add-Result "Get-HardwareSummary / report" "FAIL" $_.Exception.Message
}

# Collapsible CPU / memory rows
try {
    $nodes = @(Get-CpuMemoryNodes)
    if ($nodes.Count -gt 0) { Add-Result "Get-CpuMemoryNodes ran ($($nodes.Count) rows)" "PASS" }
    else                    { Add-Result "Get-CpuMemoryNodes" "FAIL" "no rows returned" }

    # Collapsed by default: the flattened view must match the node count until
    # something is expanded.
    $collapsed = @(Expand-HardwareNodes -Nodes $nodes)
    if ($collapsed.Count -eq $nodes.Count) { Add-Result "Expand-HardwareNodes starts collapsed" "PASS" }
    else                                   { Add-Result "Expand-HardwareNodes" "FAIL" "$($collapsed.Count) rows for $($nodes.Count) nodes" }

    # Expanding a parent must add exactly its children.
    $parent = $nodes | Where-Object { $_.HasChildren } | Select-Object -First 1
    if ($null -ne $parent) {
        $parent.IsExpanded = $true
        $expanded = @(Expand-HardwareNodes -Nodes $nodes)
        $parent.IsExpanded = $false

        if ($expanded.Count -eq ($nodes.Count + @($parent.Children).Count)) {
            Add-Result "Expand-HardwareNodes reveals children ($($parent.Item))" "PASS"
        }
        else {
            Add-Result "Expand-HardwareNodes children" "FAIL" "expected $($nodes.Count + @($parent.Children).Count) rows, got $($expanded.Count)"
        }
    }
    else {
        Add-Result "Expand-HardwareNodes children" "WARN" "nothing aggregated on this machine"
    }
}
catch {
    Add-Result "Get-CpuMemoryNodes / Expand-HardwareNodes" "FAIL" $_.Exception.Message
}

#========================================================================
# Step 15 - Update check + installer switches
#
# The version comparison matters more than it looks: [version] parses
# '0.2.0' as 0.2 and '0.10.0' as 0.10 -> 0.1, so a naive compare would
# call 0.10.0 an OLDER release than 0.2.0 and never offer the update.
#========================================================================

Write-Step "Step 15 - Update check"

@('Compare-AppVersion', 'Get-RemoteAppVersion', 'Start-UpdateCheck', 'Handle-UpdateCheck_Poll') | ForEach-Object {
    if (Get-Command $_ -ErrorAction SilentlyContinue) { Add-Result "Function: $_" "PASS" }
    else                                              { Add-Result "Function: $_" "FAIL" "Not loaded" }
}

# ini.json should carry the check URL (code falls back, but config is the contract)
if (-not [String]::IsNullOrWhiteSpace($Global:IniFile.UpdateCheckUrl)) {
    Add-Result "ini.json UpdateCheckUrl present" "PASS" $Global:IniFile.UpdateCheckUrl
}
else {
    Add-Result "ini.json UpdateCheckUrl present" "WARN" "missing - falling back to the built-in default"
}

# Version comparison truth table
$versionCases = @(
    # Current x.y.z scheme
    @{ L = '0.3.0';    R = '0.3.0';  Expect = 0;     Why = 'equal' },
    @{ L = '0.3.0';    R = '0.3.1';  Expect = -1;    Why = 'patch bump is newer' },
    @{ L = '0.3.1';    R = '0.3.0';  Expect = 1;     Why = 'patch bump is newer' },
    @{ L = '0.3.9';    R = '0.4.0';  Expect = -1;    Why = 'feature bump beats patch' },
    @{ L = '0.9.9';    R = '1.0.0';  Expect = -1;    Why = 'major bump wins' },
    @{ L = '0.3.0';    R = '0.10.0'; Expect = -1;    Why = '0.10.0 is newer than 0.3.0' },
    @{ L = '0.10.0';   R = '0.3.0';  Expect = 1;     Why = '0.10.0 is newer than 0.3.0' },
    # Legacy x.xy releases must still compare sanely against x.y.z
    @{ L = '0.02';     R = '0.3.0';  Expect = -1;    Why = 'old 0.02 is older than 0.3.0' },
    @{ L = '0.3.0';    R = '0.02';   Expect = 1;     Why = 'old 0.02 is older than 0.3.0' },
    @{ L = '1.0';      R = '1';      Expect = 0;     Why = 'missing components count as zero' },
    @{ L = '1.0.0';    R = '1';      Expect = 0;     Why = 'missing components count as zero' },
    @{ L = 'v0.3.0';   R = '0.3.0';  Expect = 0;     Why = 'v prefix tolerated' },
    @{ L = '1.0-beta'; R = '1.0.0';  Expect = $null; Why = 'non-numeric is uncomparable' },
    @{ L = '';         R = '1.0.0';  Expect = $null; Why = 'empty is uncomparable' }
)
$versionFails = @()
foreach ($case in $versionCases) {
    $got = Compare-AppVersion -Local $case.L -Remote $case.R
    if ($got -ne $case.Expect) {
        $versionFails += "'$($case.L)' vs '$($case.R)' gave '$got', expected '$($case.Expect)' ($($case.Why))"
    }
}
if ($versionFails.Count -eq 0) {
    Add-Result "Compare-AppVersion truth table ($($versionCases.Count) cases)" "PASS"
}
else {
    Add-Result "Compare-AppVersion truth table" "FAIL" ($versionFails -join '; ')
}

# install.ps1 must expose -Local
try {
    $installCmd = Get-Command (Join-Path $Global:ConfigFiles 'install.ps1') -ErrorAction Stop
    if ($installCmd.Parameters.ContainsKey('Local')) { Add-Result "install.ps1 -Local switch" "PASS" }
    else { Add-Result "install.ps1 -Local switch" "FAIL" "parameter not declared" }
}
catch {
    Add-Result "install.ps1 -Local switch" "FAIL" $_.Exception.Message
}

# The configured URL must be the contents API, not raw: raw is served with
# max-age=300 and ignores cache-busting, so it reports the previous version
# for five minutes after a release.
$checkUrl = $Global:IniFile.UpdateCheckUrl
if ([String]::IsNullOrWhiteSpace($checkUrl)) { $checkUrl = $global:UpdateCheckDefaultUrl }
if ($checkUrl -match '^https://api\.github\.com/repos/.+/contents/') {
    Add-Result "Update URL uses the contents API (not cached raw)" "PASS"
}
else {
    Add-Result "Update URL uses the contents API (not cached raw)" "WARN" "points at $checkUrl"
}

# Live lookup of the published version (network - WARN, never FAIL)
try {
    $published = Get-RemoteAppVersion -Url $checkUrl -TimeoutSec 15
    Add-Result "Published version fetched (v$published)" "PASS"
}
catch {
    Add-Result "Published version fetch" "WARN" "offline or unreachable: $($_.Exception.Message)"
}

# Both response shapes must parse: the API's base64 wrapper and a plain raw
# file. An older install's ini.json can still point at raw.
try {
    $rawVersion = Get-RemoteAppVersion -TimeoutSec 15 `
        -Url 'https://raw.githubusercontent.com/iefken/WinTuner/main/ini.json'
    Add-Result "Raw URL shape still parses (v$rawVersion)" "PASS"
}
catch {
    Add-Result "Raw URL shape still parses" "WARN" "offline or unreachable: $($_.Exception.Message)"
}

# Background round-trip: start the job and pump the poller by hand
try {
    if (Start-UpdateCheck -TimeoutSec 15) {
        $deadline = (Get-Date).AddSeconds(45)
        while ($global:UpdateCheck_Job -and (Get-Date) -lt $deadline) {
            Handle-UpdateCheck_Poll
            Start-Sleep -Milliseconds 300
        }
        if ($null -eq $global:UpdateCheck_Job) {
            Add-Result "Update check job round-trip" "PASS" "job drained and cleaned up"
        }
        else {
            Add-Result "Update check job round-trip" "WARN" "job still running after 45s"
        }
    }
    else {
        Add-Result "Update check job round-trip" "WARN" "check did not start"
    }
}
catch {
    Add-Result "Update check job round-trip" "FAIL" $_.Exception.Message
}

#========================================================================
# Summary
#========================================================================

Write-Host ""
Write-Host "  ========================================" -ForegroundColor DarkCyan
Write-Host "  STARTUP TEST SUMMARY" -ForegroundColor Cyan
Write-Host "  ========================================" -ForegroundColor DarkCyan

$pass = ($results | Where-Object Status -eq 'PASS' | Measure-Object).Count
$warn = ($results | Where-Object Status -eq 'WARN' | Measure-Object).Count
$fail = ($results | Where-Object Status -eq 'FAIL' | Measure-Object).Count

Write-Host "  PASS: $pass  WARN: $warn  FAIL: $fail" -ForegroundColor $(if ($fail -gt 0) { 'Red' } elseif ($warn -gt 0) { 'Yellow' } else { 'Green' })

if ($fail -gt 0) {
    Write-Host ""
    Write-Host "  Failed steps:" -ForegroundColor Red
    $results | Where-Object Status -eq 'FAIL' | ForEach-Object {
        Write-Host "    - $($_.Step): $($_.Detail)" -ForegroundColor Red
    }
}
Write-Host "  ========================================" -ForegroundColor DarkCyan
Write-Host ""

#========================================================================
# Optional: launch the GUI if everything passed
#========================================================================

if ($fail -eq 0) {
    $launch = Read-Host "  All critical checks passed. Launch GUI? (y/n)"
    if ($launch -eq 'y') {
        try {
            [GUI_Handler]::Get_Userdata()
            [GUI_Handler]::Prepare_ComboBoxes()
            [GUI_Handler]::Prepare_DataGrids()
            [GUI_Handler]::Prepare_TextBoxes()
            $Global:Form.ShowDialog() | Out-Null
        }
        catch {
            Write-Host "  GUI launch failed: $_" -ForegroundColor Red
            Write-Host $_.ScriptStackTrace -ForegroundColor DarkYellow
        }
    }
}
