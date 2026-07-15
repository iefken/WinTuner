#========================================================================
# GUI_Handler — owns GUI lifecycle, startup prep, and user feedback.
#
# Local-only rewrite of the donor class: no AD credential gate, no
# remote/device prep. The Prepare_* methods are intentionally lean stubs
# that each feature phase grows as its controls/prefills land.
#
# Instantiated as $global:GUIHandler at the bottom of this file.
#========================================================================

class GUI_Handler {

    [String] $InitialFolderPath = $global:ConfigFiles

    #--------------------------------------------------------------------
    # Lifecycle
    #--------------------------------------------------------------------

    # [INIT] Builds startup state and shows the window.
    [void] Launch_GUI() {
        # The Activity log control now exists — drain any buffered startup
        # messages into it so early warnings are visible to the user.
        $this.Flush_StartupLog()

        [GUI_Handler]::Get_Userdata()
        [GUI_Handler]::Populate_Disks()
        [GUI_Handler]::Prepare_ComboBoxes()
        [GUI_Handler]::Prepare_DataGrids()
        [GUI_Handler]::Prepare_TextBoxes()
        [GUI_Handler]::Prepare_QuickLaunch()

        try {
            $global:Form.ShowDialog() | Out-Null
        }
        catch {
            # The window itself failed to show — no Activity log to fall back
            # on, so use a MessageBox (console is hidden in normal runs).
            [System.Windows.Forms.MessageBox]::Show(
                "Critical error launching the GUI:`n$_",
                'WinTuner', 'OK', 'Error') | Out-Null
        }
    }

    # [INIT] Moves buffered startup messages into the Activity log.
    [void] Flush_StartupLog() {
        if ($null -eq $global:StartupLog -or $global:StartupLog.Count -eq 0) { return }
        foreach ($entry in $global:StartupLog) {
            $this.Visual_Log($env:COMPUTERNAME, $entry.Message, $entry.Color)
        }
        $global:StartupLog.Clear()
    }

    # [INIT] Populates the "this machine" info fields.
    static [void] Get_Userdata() {
        try {
            $global:txt_YourUserName.Text = $env:USERNAME
            $global:txt_YourPcName.Text   = $env:COMPUTERNAME

            # First active, non-loopback IPv4 address (robust across NIC naming)
            $ip = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                Where-Object { $_.IPAddress -ne '127.0.0.1' -and $_.AddressState -eq 'Preferred' } |
                Select-Object -First 1 -ExpandProperty IPAddress
            $global:txt_YourIP.Text = if ($ip) { $ip } else { 'N/A' }

            $net = (Get-NetConnectionProfile -ErrorAction SilentlyContinue | Select-Object -First 1).Name
            $global:txt_YourNetwork.Text = if ($net) { $net } else { 'N/A' }

            # Admin / elevation status — show an Elevate button only when NOT admin.
            $isAdmin = $global:GUIHandler.Test_IsAdmin()
            if ($isAdmin) {
                $global:txt_AdminStatus.Text       = 'Administrator (elevated)'
                $global:txt_AdminStatus.Foreground = [System.Windows.Media.Brushes]::Green
                $global:btn_Elevate.Visibility     = [System.Windows.Visibility]::Collapsed
            }
            else {
                $global:txt_AdminStatus.Text       = 'Standard user (not elevated)'
                $global:txt_AdminStatus.Foreground = [System.Windows.Media.Brushes]::DarkOrange
                $global:btn_Elevate.Visibility     = [System.Windows.Visibility]::Visible
            }
        }
        catch {
            $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Get_Userdata error: $_", 'Orange')
        }
    }

    #--------------------------------------------------------------------
    # Local disks
    #--------------------------------------------------------------------

    # Returns one row object per local FIXED drive (DriveType 3), with
    # used / total / free space in GB and percent used. Local-only by design.
    [Object[]] Get_Disks() {
        $rows = @()
        try {
            $disks = Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType = 3' -ErrorAction Stop |
                Sort-Object DeviceID

            foreach ($d in $disks) {
                # Size can be $null/0 for an unformatted or unreadable volume — guard the math.
                $totalBytes = [double]($d.Size)
                $freeBytes  = [double]($d.FreeSpace)
                $usedBytes  = $totalBytes - $freeBytes

                $totalGB = [Math]::Round($totalBytes / 1GB, 1)
                $freeGB  = [Math]::Round($freeBytes  / 1GB, 1)
                $usedGB  = [Math]::Round($usedBytes  / 1GB, 1)
                $usedPct = if ($totalBytes -gt 0) { [Math]::Round(($usedBytes / $totalBytes) * 100, 0) } else { 0 }

                $rows += [PSCustomObject]@{
                    Drive   = $d.DeviceID
                    Label   = if ([String]::IsNullOrWhiteSpace($d.VolumeName)) { '(no label)' } else { $d.VolumeName }
                    UsedGB  = $usedGB
                    TotalGB = $totalGB
                    FreeGB  = $freeGB
                    UsedPct = "$usedPct%"
                }
            }
        }
        catch {
            $this.Visual_Log($env:COMPUTERNAME, "Get_Disks error: $($_.Exception.Message)", 'Red')
        }
        return $rows
    }

    # [INIT] Fills the Home-tab disks grid. Safe to call again (Refresh button).
    static [void] Populate_Disks() {
        try {
            $global:dgr_Disks.ItemsSource = @($global:GUIHandler.Get_Disks())
        }
        catch {
            $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Populate_Disks error: $($_.Exception.Message)", 'Red')
        }
    }

    #--------------------------------------------------------------------
    # Startup prep — grow these as feature tabs are ported.
    #--------------------------------------------------------------------

    static [void] Prepare_ComboBoxes() {

        # --- Local PS presets (pws_commands.json) ---
        try {
            $pwsPath = "$Global:ConfigFiles\src\gui\form_prefills\pws_commands.json"
            $pwsCommands = Get-Content -Path $pwsPath -Raw | ConvertFrom-Json

            # Build the display list once; reused by the search/filter listeners.
            $global:PwsCommandsFullList = @($pwsCommands | ForEach-Object {
                if ($_.category) { "[$($_.category)]: $($_.description)" } else { $_.description }
            })

            $global:cmb_LocalPS_Desc.Items.Clear()
            foreach ($display in $global:PwsCommandsFullList) {
                $global:cmb_LocalPS_Desc.Items.Add($display) | Out-Null
            }
        }
        catch {
            $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Prepare_ComboBoxes: failed to load pws_commands.json: $_", 'Red')
        }

        # --- File Cleanup folder presets (common_paths.csv) ---
        try {
            $pathsCsv = "$Global:ConfigFiles\src\gui\form_prefills\common_paths.csv"
            $commonPaths = Import-Csv -Path $pathsCsv

            $global:cmb_FC_Path.Items.Clear()
            foreach ($entry in $commonPaths) {
                # xUSERIDx is a placeholder for the current user's name
                $resolved = $entry.path -replace 'xUSERIDx', $env:USERNAME
                $global:cmb_FC_Path.Items.Add($resolved) | Out-Null
            }
        }
        catch {
            $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Prepare_ComboBoxes: failed to load common_paths.csv: $_", 'Red')
        }

        # --- Registry tweak presets (registry_tweaks.json) ---
        try {
            $regPath = "$Global:ConfigFiles\src\gui\form_prefills\registry_tweaks.json"
            # NOTE: assign first, THEN @() — `@(... | ConvertFrom-Json)` in PS 5.1
            # wraps the whole JSON array as one Object[] element (count = 1).
            $regTweaks = Get-Content -Path $regPath -Raw | ConvertFrom-Json
            $global:RegistryTweaksList = @($regTweaks)

            $global:cmb_Reg_Tweak.Items.Clear()
            foreach ($tweak in $global:RegistryTweaksList) {
                $global:cmb_Reg_Tweak.Items.Add($tweak.name) | Out-Null
            }
        }
        catch {
            $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Prepare_ComboBoxes: failed to load registry_tweaks.json: $_", 'Red')
        }

        # --- WinGet category filter ---
        try {
            $appsPath = "$Global:ConfigFiles\src\gui\form_prefills\applications.json"
            $appsData = Get-Content -Path $appsPath -Raw | ConvertFrom-Json
            $global:WinGetAppsList = @($appsData)

            # Extract unique categories
            $categories = $global:WinGetAppsList | Select-Object -ExpandProperty category -Unique | Sort-Object
            $categories = @("All") + $categories

            $global:cmb_WinGet_Category.Items.Clear()
            foreach ($cat in $categories) {
                $global:cmb_WinGet_Category.Items.Add($cat) | Out-Null
            }
            $global:cmb_WinGet_Category.SelectedIndex = 0
        }
        catch {
            $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Prepare_ComboBoxes: failed to load applications.json: $_", 'Red')
        }

        # --- Windows Features category filter ---
        try {
            $commonFeatures = Get-CommonWindowsFeatures
            $categories = $commonFeatures | Select-Object -ExpandProperty Category -Unique | Sort-Object
            $categories = @("All") + $categories

            $global:cmb_WinFeat_Category.Items.Clear()
            foreach ($cat in $categories) {
                $global:cmb_WinFeat_Category.Items.Add($cat) | Out-Null
            }
            $global:cmb_WinFeat_Category.SelectedIndex = 0
        }
        catch {
            $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Prepare_ComboBoxes: failed to load Windows features categories: $_", 'Red')
        }

        # --- DNS provider filter ---
        try {
            $dnsProviders = Get-DNSProviders
            $global:DNSProvidersList = @($dnsProviders)

            $global:cmb_DNS_Provider.Items.Clear()
            foreach ($provider in $dnsProviders) {
                $global:cmb_DNS_Provider.Items.Add($provider.Name) | Out-Null
            }
            if ($dnsProviders.Count -gt 0) {
                $global:cmb_DNS_Provider.SelectedIndex = 0
            }
        }
        catch {
            $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Prepare_ComboBoxes: failed to load DNS providers: $_", 'Red')
        }

        # --- Load network adapters for DNS ---
        try {
            $adapters = Get-NetworkAdapters
            $global:DNSAdaptersList = @($adapters)

            $global:cmb_DNS_Adapter.Items.Clear()
            foreach ($adapter in $adapters) {
                $global:cmb_DNS_Adapter.Items.Add($adapter.Name) | Out-Null
            }

            if ($adapters.Count -gt 0) {
                $global:cmb_DNS_Adapter.SelectedIndex = 0

                # Load DNS settings for first adapter
                $firstAdapter = $adapters[0]
                $dnsSettings = Get-AdapterDNS -InterfaceAlias $firstAdapter.InterfaceAlias
                $global:lbl_DNS_Primary.Text = $dnsSettings.Primary
                $global:lbl_DNS_Secondary.Text = $dnsSettings.Secondary
                $global:lbl_DNS_Method.Text = $dnsSettings.Method
            } else {
                $global:lbl_DNS_Primary.Text = "No adapters"
                $global:lbl_DNS_Secondary.Text = "No adapters"
                $global:lbl_DNS_Method.Text = "N/A"
            }
        }
        catch {
            $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Prepare_ComboBoxes: failed to load network adapters: $_", 'Red')
        }

        # --- Load initial power plan ---
        try {
            $activePlan = Get-ActivePowerPlan
            if ($activePlan) {
                $global:lbl_Perf_Current.Text = $activePlan.Name
            } else {
                $global:lbl_Perf_Current.Text = "Unknown"
            }

            # Populate power plans ComboBox
            $plans = Get-PowerPlans
            $global:PowerPlansList = @($plans)

            $global:cmb_Perf_Plan.Items.Clear()
            foreach ($plan in $plans) {
                $display = if ($plan.IsActive) { "$($plan.Name) (Active)" } else { $plan.Name }
                $global:cmb_Perf_Plan.Items.Add($display) | Out-Null
            }

            # Select current plan
            if ($activePlan) {
                for ($i = 0; $i -lt $plans.Count; $i++) {
                    if ($plans[$i].Guid -eq $activePlan.Guid) {
                        $global:cmb_Perf_Plan.SelectedIndex = $i
                        break
                    }
                }
            }
        }
        catch {
            $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Prepare_ComboBoxes: failed to load active power plan: $_", 'Red')
        }

        # --- Load initial Windows Update status ---
        try {
            $services = Get-WindowsUpdateServiceStatus
            $wuService = $services | Where-Object { $_.Name -eq "wuauserv" } | Select-Object -First 1
            if ($wuService) {
                $global:lbl_WU_Status.Text = $wuService.Status
                $global:lbl_WU_Startup.Text = $wuService.StartType
            } else {
                $global:lbl_WU_Status.Text = "Unknown"
                $global:lbl_WU_Startup.Text = "Unknown"
            }
        }
        catch {
            $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Prepare_ComboBoxes: failed to load Windows Update status: $_", 'Red')
        }
    }

    static [void] Prepare_DataGrids() {
        # Populated per-feature.
    }

    static [void] Prepare_TextBoxes() {
        # Populated per-feature.
    }

    # [INIT] Fills the "Common paths" / "Common apps" quick-launch lists.
    # Both are data-driven from form_prefills CSVs; items are kept as objects
    # (not just display strings) so click handlers get the real path/command.
    static [void] Prepare_QuickLaunch() {

        # --- Common paths (quick_paths.csv) ---
        try {
            $pathsCsv = "$Global:ConfigFiles\src\gui\form_prefills\quick_paths.csv"
            $quickPaths = Import-Csv -Path $pathsCsv

            $global:lst_QuickPaths.Items.Clear()
            foreach ($entry in $quickPaths) {
                # xUSERIDx is a placeholder for the current user's name
                $resolvedPath  = $entry.path  -replace 'xUSERIDx', $env:USERNAME
                $resolvedLabel = $entry.label -replace 'xUSERIDx', $env:USERNAME
                $global:lst_QuickPaths.Items.Add(
                    [PSCustomObject]@{ label = $resolvedLabel; path = $resolvedPath }
                ) | Out-Null
            }
        }
        catch {
            $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Prepare_QuickLaunch: failed to load quick_paths.csv: $_", 'Red')
        }

        # --- Common apps (quick_apps.csv) -> icon tiles ---
        # Each app becomes a Button tile (real icon over a wrapped label) in the
        # pnl_QuickApps WrapPanel. Left-click launches; right-click runs as admin.
        try {
            $appsCsv = "$Global:ConfigFiles\src\gui\form_prefills\quick_apps.csv"
            $quickApps = Import-Csv -Path $appsCsv

            $tileStyle = $global:Form.FindResource('AppTile')
            $global:pnl_QuickApps.Children.Clear()

            foreach ($entry in $quickApps) {
                $btn = New-Object System.Windows.Controls.Button
                $btn.Style   = $tileStyle
                $btn.Tag     = [PSCustomObject]@{ file = $entry.file; args = $entry.args }
                $btn.ToolTip = "$($entry.label)`nLeft-click: launch  -  Right-click: run as administrator"

                $stack = New-Object System.Windows.Controls.StackPanel
                $stack.HorizontalAlignment = 'Center'

                # Real icon for the target (exe or .msc snap-in). Best-effort:
                # a tile with no resolvable icon still shows its label.
                $iconSource = [GUI_Handler]::Get_AppIcon($entry.file)
                if ($null -ne $iconSource) {
                    $img = New-Object System.Windows.Controls.Image
                    $img.Width  = 14
                    $img.Height = 14
                    $img.Margin = '0,0,0,4'
                    $img.HorizontalAlignment = 'Center'
                    $img.Source = $iconSource
                    $stack.Children.Add($img) | Out-Null
                }

                $tb = New-Object System.Windows.Controls.TextBlock
                $tb.Text          = $entry.label
                $tb.TextWrapping   = 'Wrap'
                $tb.TextAlignment  = 'Center'
                $tb.FontSize       = 10
                $stack.Children.Add($tb) | Out-Null

                $btn.Content = $stack
                # WPF gotcha: declare param($s,$e) so $s is the clicked button
                # (without param, $sender is $null). Tag carries file/args.
                $btn.add_Click({ param($s, $e)
                    $app = $s.Tag
                    $global:GUIHandler.Launch_App($app.file, $app.args, $false)
                })
                $btn.add_MouseRightButtonUp({ param($s, $e)
                    $app = $s.Tag
                    $global:GUIHandler.Launch_App($app.file, $app.args, $true)
                })

                $global:pnl_QuickApps.Children.Add($btn) | Out-Null
            }
        }
        catch {
            $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Prepare_QuickLaunch: failed to load quick_apps.csv: $_", 'Red')
        }
    }

    # Resolves an app's real icon as a WPF ImageSource (frozen so it's safe to
    # reuse). Returns $null if the target can't be located or has no icon.
    # Accepts bare commands on PATH (regedit, powershell, taskmgr) and System32
    # files such as .msc snap-ins (whose icon is MMC's, as Explorer shows it).
    static [object] Get_AppIcon([string] $File) {
        try {
            $full = $null

            $cmd = Get-Command $File -ErrorAction SilentlyContinue
            if ($cmd -and $cmd.Source) {
                $full = $cmd.Source
            }
            else {
                foreach ($dir in @("$env:SystemRoot\System32", $env:SystemRoot)) {
                    $candidate = Join-Path $dir $File
                    if (Test-Path -LiteralPath $candidate) { $full = $candidate; break }
                }
            }

            if ([String]::IsNullOrEmpty($full)) { return $null }

            $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($full)
            if ($null -eq $icon) { return $null }

            $source = [System.Windows.Interop.Imaging]::CreateBitmapSourceFromHIcon(
                $icon.Handle,
                [System.Windows.Int32Rect]::Empty,
                [System.Windows.Media.Imaging.BitmapSizeOptions]::FromEmptyOptions())
            $icon.Dispose()
            $source.Freeze()
            return $source
        }
        catch {
            return $null
        }
    }

    #--------------------------------------------------------------------
    # Quick-launch actions (local)
    #--------------------------------------------------------------------

    # Opens a folder in Explorer. Validates existence first so a stale preset
    # surfaces a clear log line instead of a blank Explorer window.
    [void] Open_Path([String] $Path) {
        if ([String]::IsNullOrWhiteSpace($Path)) { return }
        try {
            if (-not (Test-Path -LiteralPath $Path)) {
                $this.Visual_Log($env:COMPUTERNAME, "Path not found: $Path", 'Orange')
                return
            }
            Start-Process -FilePath 'explorer.exe' -ArgumentList "`"$Path`"" -ErrorAction Stop
            $this.Visual_Log($env:COMPUTERNAME, "Opened $Path", 'Green')
        }
        catch {
            $this.Visual_Log($env:COMPUTERNAME, "Could not open '$Path': $($_.Exception.Message)", 'Red')
        }
    }

    # Launches a local app/console. .msc snap-ins are routed through mmc.exe so
    # the same code path works whether or not we elevate ($AsAdmin -> UAC prompt).
    [void] Launch_App([String] $File, [String] $Arguments, [bool] $AsAdmin) {
        if ([String]::IsNullOrWhiteSpace($File)) { return }
        try {
            $targetFile = $File
            $targetArgs = $Arguments

            # mmc snap-ins (.msc) can't be elevated directly via -Verb RunAs;
            # launch mmc.exe with the snap-in as its argument instead.
            if ($File -match '\.msc$') {
                $targetFile = 'mmc.exe'
                $targetArgs = if ([String]::IsNullOrWhiteSpace($Arguments)) { $File } else { "$File $Arguments" }
            }

            $splat = @{ FilePath = $targetFile; ErrorAction = 'Stop' }
            if (-not [String]::IsNullOrWhiteSpace($targetArgs)) { $splat['ArgumentList'] = $targetArgs }
            if ($AsAdmin) { $splat['Verb'] = 'RunAs' }

            Start-Process @splat
            $mode = if ($AsAdmin) { ' (as administrator)' } else { '' }
            $this.Visual_Log($env:COMPUTERNAME, "Launched $File$mode", 'Green')
        }
        catch {
            # A cancelled UAC prompt also lands here — report it plainly.
            $this.Visual_Log($env:COMPUTERNAME, "Could not launch '$File': $($_.Exception.Message)", 'Orange')
        }
    }

    #--------------------------------------------------------------------
    # Path helpers (local)
    #--------------------------------------------------------------------

    # Normalises slashes and guarantees a trailing backslash.
    [String] Get_CleanPath([String] $Path) {
        $clean = $Path
        while ($clean.Contains('/')) { $clean = $clean.Replace('/', '\') }
        while ($clean.Contains('\\') -and -not $clean.Contains('*\\')) { $clean = $clean.Replace('\\', '\') }

        if ($clean.Length -gt 0) {
            $lastChar = $clean.Substring($clean.Length - 1)
            if ($clean.Contains('\') -and $lastChar -ne '\') { $clean += '\' }
        }
        return $clean
    }

    # Folder picker dialog; returns selected path or $null.
    [String] Get_Folder([String] $InitialPath) {
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.SelectedPath = if ([String]::IsNullOrEmpty($InitialPath)) { $this.InitialFolderPath } else { $InitialPath }

        $folder = $null
        if ($dialog.ShowDialog() -eq 'OK') { $folder = $dialog.SelectedPath }
        return $folder
    }

    # File picker dialog; resolves .lnk targets. Returns selected path or $null.
    [String] Get_FilePath([String] $InitialPath) {
        if ([String]::IsNullOrEmpty($InitialPath)) { $InitialPath = $this.InitialFolderPath }

        $dialog = New-Object System.Windows.Forms.OpenFileDialog -Property @{
            Title            = 'Select file...'
            InitialDirectory = $InitialPath
            CheckFileExists  = $true
        }

        $filePath = $null
        try {
            if ($dialog.ShowDialog() -eq 'OK') {
                $filePath = $dialog.FileName
                if ((Test-Path $filePath) -and (Get-Item $filePath).Extension -eq '.lnk') {
                    $filePath = Resolve-Shortcut -Path $filePath
                }
            }
        }
        catch {
            Write-Error "Get_FilePath error: $_"
        }
        return $filePath
    }

    #--------------------------------------------------------------------
    # PowerShell preset lookup
    #--------------------------------------------------------------------

    # Maps a preset display string ("[cat]: desc") back to its command text.
    [String] Get_PS_Command_By_Description([String] $Description) {
        try {
            $pwsPath = "$Global:ConfigFiles\src\gui\form_prefills\pws_commands.json"
            $commands = Get-Content -Path $pwsPath -Raw | ConvertFrom-Json

            $match = $commands | Where-Object {
                $display = if ($_.category) { "[$($_.category)]: $($_.description)" } else { $_.description }
                $display -eq $Description
            }

            $count = ($match | Measure-Object).Count
            if ($count -ne 1) {
                $this.Visual_Log($env:COMPUTERNAME, "Found $count presets matching '$Description' (expected 1) — check for duplicates in pws_commands.json", 'Red')
                return [String]::Empty
            }
            return $match.command
        }
        catch {
            $this.Visual_Log($env:COMPUTERNAME, "Get_PS_Command_By_Description error: $_", 'Red')
            return [String]::Empty
        }
    }

    #--------------------------------------------------------------------
    # Registry helpers (local hives)
    #--------------------------------------------------------------------

    # True if the app is running elevated (needed to write HKLM / HKU\.DEFAULT).
    [bool] Test_IsAdmin() {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        return ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
    }

    # Reads a single value. $Path is the clean "HKEY_..." form (no Registry:: prefix).
    # Returns the value as a string, or '(not set)' if missing.
    [String] Get_RegistryValue([String] $Path, [String] $Name) {
        try {
            $full = "Registry::$Path"
            if (-not (Test-Path -LiteralPath $full)) { return '(no key)' }
            $item = Get-ItemProperty -LiteralPath $full -Name $Name -ErrorAction SilentlyContinue
            if ($null -eq $item) { return '(not set)' }
            return [String]$item.$Name
        }
        catch {
            return "(error: $($_.Exception.Message))"
        }
    }

    # Writes a single value, creating the key path if needed.
    # $Type is a RegistryValueKind name (String, DWord, QWord, ...).
    [bool] Set_RegistryValue([String] $Path, [String] $Name, [String] $Type, [String] $Value) {
        try {
            $full = "Registry::$Path"
            if (-not (Test-Path -LiteralPath $full)) {
                New-Item -Path $full -Force -ErrorAction Stop | Out-Null
            }

            # Cast numeric kinds; everything else stays a string
            $typed = switch ($Type) {
                'DWord' { [int]$Value }
                'QWord' { [long]$Value }
                default { $Value }
            }

            Set-ItemProperty -LiteralPath $full -Name $Name -Value $typed -Type $Type -ErrorAction Stop
            return $true
        }
        catch {
            $this.Visual_Log($env:COMPUTERNAME, "Registry write failed ($Name): $($_.Exception.Message)", 'Red')
            return $false
        }
    }

    #--------------------------------------------------------------------
    # User feedback — the single output channel for the whole app.
    #--------------------------------------------------------------------

    [void] Visual_Log([String] $ComputerName, [String] $Message, [String] $Color = $null) {
        if ([String]::IsNullOrEmpty($Color)) { $Color = 'Cyan' }

        $line = "$ComputerName : $Message!"
        $this.Format_RichTextBox($global:richtxt_Log, $line, $Color, $true)

        if ($global:cbx_GetFeedbackMessages -and $global:cbx_GetFeedbackMessages.IsChecked -eq $true) {
            $dateNow = Get-Date -Format 'HH:mm:ss'
            Write-Host "$dateNow | $line" -ForegroundColor $Color
        }
    }

    # Appends coloured, timestamped text to a WPF RichTextBox.
    [void] Format_RichTextBox($RichTextBoxControl, $Text, $ForeGroundColor, $NewLine) {
        if ($null -eq $RichTextBoxControl) { return }

        $systemTime = Get-Date -Format HH:mm:ss
        $range = New-Object System.Windows.Documents.TextRange($RichTextBoxControl.Document.ContentEnd, $RichTextBoxControl.Document.ContentEnd)
        $range.Text = if ($NewLine) { "`n[$systemTime] - $Text" } else { "[$systemTime] - $Text" }

        if ([String]::IsNullOrEmpty($ForeGroundColor)) { $ForeGroundColor = 'Black' }
        $range.ApplyPropertyValue([System.Windows.Documents.TextElement]::ForegroundProperty, $ForeGroundColor)

        $RichTextBoxControl.ScrollToEnd()
    }
}

#========================================================================
# Instantiate the global handler
#========================================================================

$global:GUIHandler = [GUI_Handler]::new()
