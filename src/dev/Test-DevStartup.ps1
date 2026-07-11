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

@('Visual_Log', 'Get_Userdata', 'Launch_GUI', 'Format_RichTextBox', 'Get_PS_Command_By_Description') | ForEach-Object {
    if ([GUI_Handler].GetMethods().Name -contains $_) { Add-Result "GUI_Handler.$_" "PASS" }
    else                                              { Add-Result "GUI_Handler.$_" "FAIL" "Method not found" }
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
