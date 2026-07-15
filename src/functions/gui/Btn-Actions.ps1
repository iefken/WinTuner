#========================================================================
# Btn-Actions.ps1 — WPF button-click handlers.
#
# These run on the GUI thread (synchronous). Reference controls via their
# $global: variable names (exposed by Load-XamlForm.ps1).
#========================================================================

#========================================================================
# This machine (general info)
#========================================================================

# Relaunches the app elevated via a UAC prompt, then closes this instance.
# Only shown/used when the current session is NOT already an administrator.
Function Handle-btn_Elevate {

    $mainScript = Join-Path $Global:ConfigFiles 'Main.ps1'
    if (-not (Test-Path -LiteralPath $mainScript)) {
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Cannot relaunch — Main.ps1 not found at $mainScript", 'Red')
        return
    }

    try {
        # -Verb RunAs triggers the UAC prompt. If the user cancels it,
        # Start-Process throws and we keep the current (non-elevated) window.
        Start-Process -FilePath 'powershell.exe' `
            -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$mainScript`"") `
            -Verb RunAs -ErrorAction Stop

        # Elevated copy is starting — close this one so we don't run two windows.
        $global:Form.Close()
    }
    catch {
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Elevation cancelled or failed: $($_.Exception.Message)", 'Orange')
    }
}

# Walks the visual tree up from a click's OriginalSource to the ListBoxItem,
# then returns the data object bound to it. Hit-testing the clicked container
# (rather than reading SelectedItem) makes "single-click to open" reliable and
# lets right-click act on the row under the cursor without changing selection.
Function Get-ClickedListItem {
    param($ListBox, $OriginalSource)

    $dep = $OriginalSource
    while ($null -ne $dep -and -not ($dep -is [System.Windows.Controls.ListBoxItem])) {
        if ($dep -isnot [System.Windows.DependencyObject]) { return $null }
        $dep = [System.Windows.Media.VisualTreeHelper]::GetParent($dep)
    }
    if ($null -eq $dep) { return $null }   # clicked empty space, not a row
    return $ListBox.ItemContainerGenerator.ItemFromContainer($dep)
}

# Common paths: single-click a row -> open that folder in Explorer.
Function Handle-QuickPath-Click {
    param($OriginalSource)

    $item = Get-ClickedListItem -ListBox $global:lst_QuickPaths -OriginalSource $OriginalSource
    if ($null -eq $item) { return }
    $global:GUIHandler.Open_Path($item.path)
}

# Common apps: launch the clicked app. $AsAdmin (right-click) triggers UAC.
Function Handle-QuickApp-Click {
    param($OriginalSource, [bool]$AsAdmin = $false)

    $item = Get-ClickedListItem -ListBox $global:lst_QuickApps -OriginalSource $OriginalSource
    if ($null -eq $item) { return }
    $global:GUIHandler.Launch_App($item.file, $item.args, $AsAdmin)
}

# Runs the Local PS command box against this machine, in-process.
# NOTE: expressions execute in this function's scope — assign to $global:
# if you want a value to survive into the next command.
Function Handle-btn_Run_LocalPS {

    $expression = $global:cmb_LocalPS_Command.Text

    if ([String]::IsNullOrWhiteSpace($expression)) {
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Nothing to run — enter a command first", 'Red')
        return
    }

    # Echo the command into the output console
    $global:txt_cmdline_LocalPS.AppendText("PS> $expression`r`n")

    try {
        $result = Invoke-Expression $expression -ErrorAction Stop | Out-String

        if (-not [String]::IsNullOrWhiteSpace($result)) {
            $global:txt_cmdline_LocalPS.AppendText($result.TrimEnd() + "`r`n")
        }
        $global:txt_cmdline_LocalPS.AppendText("`r`n")
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Local PS command ran OK", 'Green')
    }
    catch {
        $global:txt_cmdline_LocalPS.AppendText("ERROR: $($_.Exception.Message)`r`n`r`n")
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Local PS error: $($_.Exception.Message)", 'Red')
    }
    finally {
        $global:txt_cmdline_LocalPS.ScrollToEnd()
    }
}

# Clears the Local PS output console.
Function Handle-btn_Clear_LocalPS {
    $global:txt_cmdline_LocalPS.Clear()
}

#========================================================================
# File Cleanup tab
#========================================================================

# Opens a folder picker and drops the chosen path into the folder box.
Function Handle-btn_FC_Browse {
    $start = $global:cmb_FC_Path.Text
    $folder = $global:GUIHandler.Get_Folder($start)
    if (-not [String]::IsNullOrEmpty($folder)) {
        $global:cmb_FC_Path.Text = $folder
    }
}

# Lists the files that match the folder + name filter into the results grid.
# Nothing is deleted here — Delete acts only on what this produces.
Function Handle-btn_FC_Preview {

    $global:dgr_FC_Results.Items.Clear()
    $global:FC_PreviewItems = @()
    $global:lbl_FC_Count.Text = ""

    $folder = $global:cmb_FC_Path.Text
    if ([String]::IsNullOrWhiteSpace($folder)) {
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Pick or type a folder first", 'Red')
        return
    }
    if (-not (Test-Path -LiteralPath $folder -PathType Container)) {
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Folder not found: $folder", 'Red')
        $global:lbl_FC_Count.Text = "Folder not found."
        return
    }

    # Build a name pattern: blank = everything; bare text = *contains*; keep explicit wildcards as-is
    $filter = $global:txt_FC_Filter.Text
    if ([String]::IsNullOrWhiteSpace($filter)) {
        $pattern = '*'
    }
    elseif ($filter -match '[\*\?]') {
        $pattern = $filter
    }
    else {
        $pattern = "*$filter*"
    }

    $recurse = [bool]$global:chk_FC_Recurse.IsChecked

    # Human-readable description of exactly what's being matched, reused in messages.
    $ruleDesc = if ($pattern -eq '*') { 'all files' } else { "name like '$pattern'" }
    $scope    = if ($recurse) { 'incl. subfolders' } else { 'this folder only' }

    try {
        $files = Get-ChildItem -LiteralPath $folder -File -Recurse:$recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like $pattern }
    }
    catch {
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Preview failed: $($_.Exception.Message)", 'Red')
        return
    }

    $files = @($files)
    if ($files.Count -eq 0) {
        $global:lbl_FC_Count.Text = "No matches ($ruleDesc, $scope)."
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "No files match ($ruleDesc, $scope) in $folder", 'Cyan')
        return
    }

    $counter = 0
    $totalBytes = 0
    foreach ($file in $files) {
        $counter++
        $totalBytes += $file.Length
        $global:dgr_FC_Results.AddChild([pscustomobject]@{
            nr       = $counter
            Name     = $file.Name
            SizeKB   = [math]::Round($file.Length / 1KB, 1)
            Modified = $file.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
            FullName = $file.FullName
        }) | Out-Null
    }

    # Keep the exact paths so Delete operates on precisely this set
    $global:FC_PreviewItems = @($files | ForEach-Object { $_.FullName })

    $totalMB = [math]::Round($totalBytes / 1MB, 1)
    $global:lbl_FC_Count.Text = "$($files.Count) file(s), $totalMB MB"
    $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Previewed $($files.Count) file(s) in $folder", 'Green')
}

# Deletes exactly the files currently listed (from the last Preview).
# Defaults to Recycle Bin; reports the locking process if a delete fails.
Function Handle-btn_FC_Delete {

    $items = @($global:FC_PreviewItems)
    if ($items.Count -eq 0) {
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Nothing to delete — run Preview first", 'Red')
        return
    }

    $toRecycle = [bool]$global:chk_FC_Recycle.IsChecked
    $where = if ($toRecycle) { "the Recycle Bin" } else { "PERMANENTLY deleted" }

    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "Send $($items.Count) file(s) to $where?",
        'Confirm delete', 'OKCancel', 'Warning')
    if ($confirm -ne 'OK') {
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Delete cancelled", 'Cyan')
        return
    }

    $deleted = 0
    $failed  = 0
    foreach ($path in $items) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        try {
            if ($toRecycle) {
                [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
                    $path,
                    [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
                    [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin)
            }
            else {
                Remove-Item -LiteralPath $path -Force -ErrorAction Stop
            }
            $deleted++
        }
        catch {
            $failed++
            $msg = "Could not delete $([System.IO.Path]::GetFileName($path)): $($_.Exception.Message)"

            # If it's locked, name the culprit process(es)
            try {
                $lockers = Get-FileLockProcess -FilePath $path -ErrorAction SilentlyContinue
                if ($lockers -and @($lockers).Count -gt 0) {
                    $names = ($lockers | ForEach-Object { "$($_.ProcessName) (PID $($_.Id))" }) -join ', '
                    $msg += " — locked by: $names"
                }
            }
            catch { }

            $global:GUIHandler.Visual_Log($env:COMPUTERNAME, $msg, 'Red')
        }
    }

    $color = if ($failed -gt 0) { 'Yellow' } else { 'Green' }
    $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Deleted $deleted file(s), $failed failed", $color)

    # Refresh the list to reflect what's gone
    Handle-btn_FC_Preview
}

#========================================================================
# Registry tab
#========================================================================

# Re-reads the current value of each entry in the grid.
Function Handle-btn_Reg_GetValue {
    if ($null -eq $global:Reg_SelectedTweak) {
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Pick a tweak first", 'Red')
        return
    }
    foreach ($row in @($global:dgr_Reg_Entries.Items)) {
        $row.Current = $global:GUIHandler.Get_RegistryValue($global:Reg_SelectedTweak.path, $row.Key)
    }
    $global:dgr_Reg_Entries.Items.Refresh()
    $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Read current values for '$($global:Reg_SelectedTweak.name)'", 'Cyan')
}

# Writes the 'New value' of each grid entry to the registry (with confirm).
Function Handle-btn_Reg_Apply {

    $tweak = $global:Reg_SelectedTweak
    if ($null -eq $tweak) {
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Pick a tweak first", 'Red')
        return
    }

    if ($tweak.admin -and -not $global:GUIHandler.Test_IsAdmin()) {
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "'$($tweak.name)' needs Administrator — restart the app elevated", 'Red')
        return
    }

    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "Apply '$($tweak.name)' to:`n$($tweak.path) ?",
        'Confirm registry change', 'OKCancel', 'Warning')
    if ($confirm -ne 'OK') {
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Registry change cancelled", 'Cyan')
        return
    }

    $ok = 0
    $fail = 0
    foreach ($row in @($global:dgr_Reg_Entries.Items)) {
        if ($global:GUIHandler.Set_RegistryValue($tweak.path, $row.Key, $row.Type, [String]$row.NewValue)) {
            $ok++
        }
        else {
            $fail++
        }
    }

    $color = if ($fail -gt 0) { 'Yellow' } else { 'Green' }
    $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Applied '$($tweak.name)': $ok ok, $fail failed", $color)

    # Reflect the new state
    Handle-btn_Reg_GetValue
}

#========================================================================
# COM Ports tab
#
# Uses a DispatcherTimer (UI thread) to poll + diff — Register-WmiEvent
# -Action callbacks do NOT fire while the main thread is blocked in
# Form.ShowDialog(), so event-driven monitoring would never trigger.
#========================================================================

# Appends one row to the COM grid; beeps if enabled. UI-thread only.
Function Add-ComRow {
    param([string]$Type, $Port)

    $global:dgr_COM_Results.AddChild([pscustomobject]@{
        Time         = (Get-Date).ToString('HH:mm:ss')
        Event        = $Type
        COM          = $Port.COM
        Name         = $Port.Name
        Manufacturer = $Port.Manufacturer
        PNPDeviceID  = $Port.PNPDeviceID
    }) | Out-Null

    $count = $global:dgr_COM_Results.Items.Count
    if ($count -gt 0) {
        $global:dgr_COM_Results.ScrollIntoView($global:dgr_COM_Results.Items[$count - 1])
    }

    if ($global:chk_COM_Beep.IsChecked -and $Type -ne 'PRESENT') {
        try {
            $freq = if ($Type -eq 'ADDED') { 1200 } else { 800 }
            [console]::Beep($freq, 120)
        }
        catch { }  # no console / beep unavailable — ignore
    }
}

# One poll tick: snapshot current ports, diff against last seen, log changes.
Function Handle-COM_Poll {
    $current = @{}
    foreach ($p in (Get-ComPortSnapshot)) { $current[$p.PNPDeviceID] = $p }

    # Added = present now, not before
    foreach ($key in $current.Keys) {
        if (-not $global:COM_LastKeys.ContainsKey($key)) {
            Add-ComRow 'ADDED' $current[$key]
            $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "COM connected: $($current[$key].COM) $($current[$key].Name)", 'Green')
        }
    }
    # Removed = present before, not now
    foreach ($key in $global:COM_LastKeys.Keys) {
        if (-not $current.ContainsKey($key)) {
            Add-ComRow 'REMOVED' $global:COM_LastKeys[$key]
            $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "COM disconnected: $($global:COM_LastKeys[$key].COM) $($global:COM_LastKeys[$key].Name)", 'Yellow')
        }
    }

    $global:COM_LastKeys = $current
}

# Lists the current ports as a baseline and starts the poll timer.
Function Handle-btn_COM_Start {
    if ($global:COM_Running) {
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "COM monitoring already running", 'Cyan')
        return
    }

    # Baseline snapshot (marked PRESENT)
    $global:dgr_COM_Results.Items.Clear()
    $global:COM_LastKeys = @{}
    $snap = Get-ComPortSnapshot
    foreach ($p in $snap) {
        $global:COM_LastKeys[$p.PNPDeviceID] = $p
        Add-ComRow 'PRESENT' $p
    }

    if (-not $global:COM_Timer) {
        $global:COM_Timer = New-Object System.Windows.Threading.DispatcherTimer
        $global:COM_Timer.Interval = [TimeSpan]::FromSeconds(2)
        $global:COM_Timer.add_Tick({ Handle-COM_Poll })
    }
    $global:COM_Timer.Start()
    $global:COM_Running = $true

    $global:lbl_COM_Status.Text = "Monitoring (every 2s) - $($snap.Count) present"
    $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "COM monitoring started ($($snap.Count) present)", 'Green')
}

# Stops the poll timer.
Function Handle-btn_COM_Stop {
    if ($global:COM_Timer) { $global:COM_Timer.Stop() }
    $global:COM_Running = $false
    $global:lbl_COM_Status.Text = "Stopped."
    $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "COM monitoring stopped", 'Cyan')
}

# One-shot listing of current ports (also resets the diff baseline).
Function Handle-btn_COM_Refresh {
    $global:dgr_COM_Results.Items.Clear()
    $global:COM_LastKeys = @{}
    $snap = Get-ComPortSnapshot
    foreach ($p in $snap) {
        $global:COM_LastKeys[$p.PNPDeviceID] = $p
        Add-ComRow 'PRESENT' $p
    }
    $global:lbl_COM_Status.Text = "$($snap.Count) port(s) listed."
    $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Listed $($snap.Count) COM port(s)", 'Cyan')
}

#========================================================================
# Diagnostics tab
#
# The CLI tools (ping/tracert) are slow, so they run in a background
# Start-Job. A DispatcherTimer drains the job's output into the console
# box on the UI thread, keeping the window responsive.
#========================================================================

# Builds + starts the diagnostics job from the checked options.
Function Handle-btn_Diag_Run {

    if ($global:Diag_Job -and $global:Diag_Job.State -eq 'Running') {
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Diagnostics already running — Stop first", 'Cyan')
        return
    }

    $target   = $global:txt_Diag_Target.Text.Trim()
    $doIp      = [bool]$global:chk_Diag_IPConfig.IsChecked
    $doNs      = [bool]$global:chk_Diag_NSLookup.IsChecked
    $doPing    = [bool]$global:chk_Diag_Ping.IsChecked
    $doTracert = [bool]$global:chk_Diag_Tracert.IsChecked

    if (-not ($doIp -or $doNs -or $doPing -or $doTracert)) {
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Pick at least one check", 'Red')
        return
    }
    if (($doNs -or $doPing -or $doTracert) -and [String]::IsNullOrWhiteSpace($target)) {
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Enter a target host/IP for ping/tracert/nslookup", 'Red')
        return
    }

    # Validate ping count
    $pingCount = 4
    if (-not [int]::TryParse($global:txt_Diag_PingCount.Text, [ref]$pingCount) -or $pingCount -lt 1) {
        $pingCount = 4
        $global:txt_Diag_PingCount.Text = '4'
    }

    # Clean up any finished prior job
    if ($global:Diag_Job) {
        Remove-Job -Job $global:Diag_Job -Force -ErrorAction SilentlyContinue
        $global:Diag_Job = $null
    }

    $global:txt_Diag_Output.AppendText("===== Run @ $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') =====`r`n")

    $global:Diag_Job = Start-Job -ScriptBlock {
        param($target, $pingCount, $doIp, $doNs, $doPing, $doTracert)
        if ($doIp)      { "=== ipconfig /all ==="; ipconfig /all; "" }
        if ($doNs)      { "=== nslookup $target ==="; nslookup $target; "" }
        if ($doPing)    { "=== ping $target -n $pingCount ==="; ping $target -n $pingCount; "" }
        if ($doTracert) { "=== tracert $target ==="; tracert $target; "" }
    } -ArgumentList $target, $pingCount, $doIp, $doNs, $doPing, $doTracert

    # Start the output pump
    if (-not $global:Diag_Timer) {
        $global:Diag_Timer = New-Object System.Windows.Threading.DispatcherTimer
        $global:Diag_Timer.Interval = [TimeSpan]::FromMilliseconds(500)
        $global:Diag_Timer.add_Tick({ Handle-Diag_Poll })
    }
    $global:Diag_Timer.Start()
    $global:lbl_Diag_Status.Text = "Running..."
    $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Diagnostics started", 'Green')
}

# Drains new job output into the console; finalises when the job ends.
Function Handle-Diag_Poll {
    if (-not $global:Diag_Job) { $global:Diag_Timer.Stop(); return }

    $new = Receive-Job -Job $global:Diag_Job -ErrorAction SilentlyContinue
    if ($new) {
        $global:txt_Diag_Output.AppendText(($new -join "`r`n") + "`r`n")
        $global:txt_Diag_Output.ScrollToEnd()
    }

    if ($global:Diag_Job.State -in @('Completed', 'Failed', 'Stopped')) {
        # Final drain to catch anything buffered after the state flip
        $tail = Receive-Job -Job $global:Diag_Job -ErrorAction SilentlyContinue
        if ($tail) {
            $global:txt_Diag_Output.AppendText(($tail -join "`r`n") + "`r`n")
        }
        $global:txt_Diag_Output.AppendText("`r`n")
        $global:txt_Diag_Output.ScrollToEnd()

        $state = $global:Diag_Job.State
        Remove-Job -Job $global:Diag_Job -Force -ErrorAction SilentlyContinue
        $global:Diag_Job = $null
        $global:Diag_Timer.Stop()
        $global:lbl_Diag_Status.Text = "Done ($state)."
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Diagnostics finished ($state)", 'Green')
    }
}

# Stops a running diagnostics job.
Function Handle-btn_Diag_Stop {
    if ($global:Diag_Timer) { $global:Diag_Timer.Stop() }
    if ($global:Diag_Job) {
        Stop-Job -Job $global:Diag_Job -ErrorAction SilentlyContinue
        Remove-Job -Job $global:Diag_Job -Force -ErrorAction SilentlyContinue
        $global:Diag_Job = $null
    }
    $global:lbl_Diag_Status.Text = "Stopped."
    $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Diagnostics stopped", 'Cyan')
}

# Clears the output console.
Function Handle-btn_Diag_Clear {
    $global:txt_Diag_Output.Clear()
}

# Saves the console output to a timestamped log file under LogPath\diagnostics.
Function Handle-btn_Diag_Save {
    $text = $global:txt_Diag_Output.Text
    if ([String]::IsNullOrWhiteSpace($text)) {
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Nothing to save", 'Red')
        return
    }
    try {
        $dir = Join-Path $Global:LogPath 'diagnostics'
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $file = Join-Path $dir ("diag_{0}.txt" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
        Set-Content -Path $file -Value $text -Encoding UTF8
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Saved diagnostics to $file", 'Green')
    }
    catch {
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Save failed: $($_.Exception.Message)", 'Red')
    }
}

#========================================================================
# WinGet Application Manager
#========================================================================

# Searches WinGet for packages matching the search term.
Function Handle-btn_WinGet_Search {
    $searchTerm = $global:txt_WinGet_Search.Text
    $category = $global:cmb_WinGet_Category.Text

    if ([String]::IsNullOrWhiteSpace($searchTerm)) {
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Enter a search term", 'Orange')
        return
    }

    try {
        $global:lbl_WinGet_Status.Text = "Searching..."

        # Filter local apps by category first (if not "All")
        $localApps = $global:WinGetAppsList
        if (-not [String]::IsNullOrWhiteSpace($category) -and $category -ne "All") {
            $localApps = $localApps | Where-Object { $_.category -eq $category }
        }

        # Search WinGet for the term
        $wingetResults = Search-WinGetApps -Query $searchTerm

        # Match WinGet results with local apps to get category info
        $displayApps = @()
        foreach ($wingetApp in $wingetResults) {
            # Find matching local app by ID or name
            $localMatch = $localApps | Where-Object {
                $_.winget -eq $wingetApp.Id -or $_.name -eq $wingetApp.Name
            } | Select-Object -First 1

            if ($localMatch) {
                # Include if it matches the category filter
                if ($category -eq "All" -or $localMatch.category -eq $category) {
                    $displayApps += [PSCustomObject]@{
                        Selected = $false
                        Name = $wingetApp.Name
                        Id = $wingetApp.Id
                        Version = $wingetApp.Version
                        Category = $localMatch.category
                        Source = $wingetApp.Source
                    }
                }
            } else {
                # Include non-curated apps only if category is "All"
                if ($category -eq "All") {
                    $displayApps += [PSCustomObject]@{
                        Selected = $false
                        Name = $wingetApp.Name
                        Id = $wingetApp.Id
                        Version = $wingetApp.Version
                        Category = "Other"
                        Source = $wingetApp.Source
                    }
                }
            }
        }

        $global:dgr_WinGet_Apps.ItemsSource = @($displayApps)
        $global:lbl_WinGet_Status.Text = "Found $($displayApps.Count) packages"
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Found $($displayApps.Count) packages for '$searchTerm'", 'Green')
    }
    catch {
        $global:lbl_WinGet_Status.Text = "Search failed"
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "WinGet search failed: $_", 'Red')
    }
}

# Lists all installed WinGet packages.
Function Handle-btn_WinGet_GetInstalled {
    try {
        $global:lbl_WinGet_Status.Text = "Getting installed apps..."
        $apps = Get-WinGetApps

        # Convert to display format with checkbox
        $displayApps = $apps | ForEach-Object {
            [PSCustomObject]@{
                Selected = $false
                Name = $_.Name
                Id = $_.Id
                Version = $_.Version
                Category = "Installed"
                Source = $_.Source
            }
        }

        $global:dgr_WinGet_Apps.ItemsSource = @($displayApps)
        $global:lbl_WinGet_Status.Text = "$($displayApps.Count) installed"
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Found $($displayApps.Count) installed packages", 'Green')
    }
    catch {
        $global:lbl_WinGet_Status.Text = "Failed"
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Failed to get installed apps: $_", 'Red')
    }
}

# Clears the app list.
Function Handle-btn_WinGet_Clear {
    $global:dgr_WinGet_Apps.ItemsSource = @()
    $global:txt_WinGet_Search.Text = ""
    $global:lbl_WinGet_Status.Text = "Ready"
}

# Installs selected packages.
Function Handle-btn_WinGet_Install {
    $selectedApps = $global:dgr_WinGet_Apps.ItemsSource | Where-Object { $_.Selected -eq $true }

    if ($selectedApps.Count -eq 0) {
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "No packages selected", 'Orange')
        return
    }

    $packageIds = $selectedApps | ForEach-Object { $_.Id }
    $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Installing $($packageIds.Count) packages...", 'Cyan')

    try {
        $results = Install-WinGetApps -PackageIds $packageIds -Silent

        foreach ($result in $results) {
            if ($result.Success) {
                $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Installed: $($result.PackageId)", 'Green')
            } else {
                $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Failed: $($result.PackageId) - $($result.Message)", 'Red')
            }
        }

        $global:lbl_WinGet_Status.Text = "Installation complete"
        # Refresh the list
        Handle-btn_WinGet_GetInstalled
    }
    catch {
        $global:lbl_WinGet_Status.Text = "Installation failed"
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Installation failed: $_", 'Red')
    }
}

# Updates all installed packages.
Function Handle-btn_WinGet_Update {
    $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Updating all packages...", 'Cyan')

    try {
        $success = Update-WinGetApps -All
        if ($success) {
            $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Update complete", 'Green')
            $global:lbl_WinGet_Status.Text = "Update complete"
            Handle-btn_WinGet_GetInstalled
        } else {
            $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Update failed", 'Red')
            $global:lbl_WinGet_Status.Text = "Update failed"
        }
    }
    catch {
        $global:lbl_WinGet_Status.Text = "Update failed"
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Update failed: $_", 'Red')
    }
}

# Uninstalls selected packages.
Function Handle-btn_WinGet_Uninstall {
    $selectedApps = $global:dgr_WinGet_Apps.ItemsSource | Where-Object { $_.Selected -eq $true }

    if ($selectedApps.Count -eq 0) {
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "No packages selected", 'Orange')
        return
    }

    $packageIds = $selectedApps | ForEach-Object { $_.Id }
    $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Uninstalling $($packageIds.Count) packages...", 'Cyan')

    foreach ($pkgId in $packageIds) {
        try {
            $success = Uninstall-WinGetApp -PackageId $pkgId
            if ($success) {
                $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Uninstalled: $pkgId", 'Green')
            } else {
                $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Failed to uninstall: $pkgId", 'Red')
            }
        }
        catch {
            $errorMsg = $_.Exception.Message
            $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Error uninstalling ${pkgId}: $errorMsg", 'Red')
        }
    }

    $global:lbl_WinGet_Status.Text = "Uninstall complete"
    Handle-btn_WinGet_GetInstalled
}

#========================================================================
# Windows Features
#========================================================================

# Refreshes the list of Windows features.
Function Handle-btn_WinFeat_Refresh {
    try {
        $global:lbl_WinFeat_Status.Text = "Loading features..."
        $category = $global:cmb_WinFeat_Category.Text

        # Get common features
        $commonFeatures = Get-CommonWindowsFeatures

        # Filter by category if selected
        if (-not [String]::IsNullOrWhiteSpace($category) -and $category -ne "All") {
            $commonFeatures = $commonFeatures | Where-Object { $_.Category -eq $category }
        }

        # Check actual state for each feature
        $displayFeatures = @()
        foreach ($feature in $commonFeatures) {
            $isEnabled = Test-WindowsFeatureEnabled -FeatureName $feature.Name
            $displayFeatures += [PSCustomObject]@{
                Selected = $false
                Name = $feature.Name
                DisplayName = $feature.DisplayName
                State = if ($isEnabled) { "Enabled" } else { "Disabled" }
                Category = $feature.Category
            }
        }

        $global:dgr_WinFeat_Features.ItemsSource = @($displayFeatures)
        $global:lbl_WinFeat_Status.Text = "$($displayFeatures.Count) features loaded"
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Loaded $($displayFeatures.Count) Windows features", 'Green')
    }
    catch {
        $global:lbl_WinFeat_Status.Text = "Failed to load"
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Failed to load Windows features: $_", 'Red')
    }
}

# Enables selected Windows features.
Function Handle-btn_WinFeat_Enable {
    $selectedFeatures = $global:dgr_WinFeat_Features.ItemsSource | Where-Object { $_.Selected -eq $true }

    if ($selectedFeatures.Count -eq 0) {
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "No features selected", 'Orange')
        return
    }

    $noRestart = $global:chk_WinFeat_NoRestart.IsChecked
    $featureNames = $selectedFeatures | ForEach-Object { $_.Name }
    $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Enabling $($featureNames.Count) features...", 'Cyan')

    foreach ($featName in $featureNames) {
        try {
            $success = Enable-WindowsFeature -FeatureName $featName -NoRestart:$noRestart
            if ($success) {
                $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Enabled: $featName", 'Green')
            } else {
                $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Failed to enable: $featName (may require restart)", 'Orange')
            }
        }
        catch {
            $errorMsg = $_.Exception.Message
            $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Error enabling ${featName}: $errorMsg", 'Red')
        }
    }

    $global:lbl_WinFeat_Status.Text = "Enable complete"
    Handle-btn_WinFeat_Refresh
}

# Disables selected Windows features.
Function Handle-btn_WinFeat_Disable {
    $selectedFeatures = $global:dgr_WinFeat_Features.ItemsSource | Where-Object { $_.Selected -eq $true }

    if ($selectedFeatures.Count -eq 0) {
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "No features selected", 'Orange')
        return
    }

    $noRestart = $global:chk_WinFeat_NoRestart.IsChecked
    $featureNames = $selectedFeatures | ForEach-Object { $_.Name }
    $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Disabling $($featureNames.Count) features...", 'Cyan')

    foreach ($featName in $featureNames) {
        try {
            $success = Disable-WindowsFeature -FeatureName $featName -NoRestart:$noRestart
            if ($success) {
                $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Disabled: $featName", 'Green')
            } else {
                $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Failed to disable: $featName (may require restart)", 'Orange')
            }
        }
        catch {
            $errorMsg = $_.Exception.Message
            $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Error disabling ${featName}: $errorMsg", 'Red')
        }
    }

    $global:lbl_WinFeat_Status.Text = "Disable complete"
    Handle-btn_WinFeat_Refresh
}

#========================================================================
# Installed Software tab
#========================================================================

# Refreshes the list of installed software.
Function Handle-btn_Installed_Refresh {
    try {
        $global:lbl_Installed_Status.Text = "Loading software..."
        
        # Get all installed software
        $software = Get-InstalledSoftware
        
        # Apply current filters
        $searchTerm = $global:txt_Installed_Search.Text
        $sortBy = if ($global:cmb_Installed_Sort.SelectedItem) { $global:cmb_Installed_Sort.SelectedItem.Tag } else { "Name" }
        $order = if ($global:cmb_Installed_Order.SelectedItem) { $global:cmb_Installed_Order.SelectedItem.Tag } else { "Asc" }
        
        # Filter by search term
        if (-not [String]::IsNullOrWhiteSpace($searchTerm)) {
            $software = Find-InstalledSoftware -SoftwareList $software -SearchTerm $searchTerm
        }
        
        # Sort the results
        $software = $software | Sort-Object -Property $sortBy -Descending:($order -eq "Desc")
        
        # Convert to display format with checkbox
        $displaySoftware = $software | ForEach-Object {
            [PSCustomObject]@{
                Selected = $false
                Name = $_.Name
                Version = $_.Version
                Publisher = $_.Publisher
                Size = $_.Size
                InstallDate = $_.InstallDate
                UninstallString = $_.UninstallString
                QuietUninstallString = $_.QuietUninstallString
            }
        }
        
        $global:dgr_Installed_Software.ItemsSource = @($displaySoftware)
        $global:lbl_Installed_Status.Text = "$($displaySoftware.Count) programs"
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Loaded $($displaySoftware.Count) installed programs", 'Green')
    }
    catch {
        $global:lbl_Installed_Status.Text = "Failed to load"
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Failed to load installed software: $_", 'Red')
    }
}

# Clears the search and software list.
Function Handle-btn_Installed_Clear {
    $global:dgr_Installed_Software.ItemsSource = @()
    $global:txt_Installed_Search.Text = ""
    $global:lbl_Installed_Status.Text = "Ready"
}

# Uninstalls selected software.
Function Handle-btn_Installed_Uninstall {
    $selectedSoftware = $global:dgr_Installed_Software.ItemsSource | Where-Object { $_.Selected -eq $true }
    
    if ($selectedSoftware.Count -eq 0) {
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "No programs selected", 'Orange')
        return
    }
    
    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "Uninstall $($selectedSoftware.Count) selected program(s)?",
        'Confirm uninstall', 'OKCancel', 'Warning')
    if ($confirm -ne 'OK') {
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Uninstall cancelled", 'Cyan')
        return
    }
    
    $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Uninstalling $($selectedSoftware.Count) program(s)...", 'Cyan')
    
    $successCount = 0
    $failCount = 0
    
    foreach ($software in $selectedSoftware) {
        try {
            $uninstallString = $software.UninstallString
            $quietUninstallString = $software.QuietUninstallString
            
            if ([String]::IsNullOrWhiteSpace($uninstallString) -and [String]::IsNullOrWhiteSpace($quietUninstallString)) {
                $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "No uninstall string for: $($software.Name)", 'Red')
                $failCount++
                continue
            }
            
            $success = Uninstall-Software -UninstallString $uninstallString -QuietUninstallString $quietUninstallString
            if ($success) {
                $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Uninstalled: $($software.Name)", 'Green')
                $successCount++
            } else {
                $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Failed to uninstall: $($software.Name)", 'Red')
                $failCount++
            }
        }
        catch {
            $errorMsg = $_.Exception.Message
            $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Error uninstalling $($software.Name): $errorMsg", 'Red')
            $failCount++
        }
    }
    
    $color = if ($failCount -gt 0) { 'Yellow' } else { 'Green' }
    $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Uninstall complete: $successCount succeeded, $failCount failed", $color)
    $global:lbl_Installed_Status.Text = "Uninstall complete"
    
    # Refresh the list
    Handle-btn_Installed_Refresh
}

#========================================================================
# System Fixes
#========================================================================

# Runs System File Checker scan.
Function Handle-btn_SysFix_SFC {
    $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Starting SFC scan...", 'Cyan')
    
    try {
        $success = Invoke-SFCScan
        if ($success) {
            $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "SFC scan completed successfully. Check the console for details.", 'Green')
        } else {
            $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "SFC scan completed with errors. Check the console for details.", 'Orange')
        }
    }
    catch {
        $errorMsg = $_.Exception.Message
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "SFC scan failed: $errorMsg", 'Red')
    }
}

# Runs DISM repair.
Function Handle-btn_SysFix_DISM {
    $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Starting DISM repair...", 'Cyan')
    
    try {
        $success = Invoke-DISMRepair -RestoreHealth
        if ($success) {
            $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "DISM repair completed successfully. Check the console for details.", 'Green')
        } else {
            $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "DISM repair completed with errors. Check the console for details.", 'Orange')
        }
    }
    catch {
        $errorMsg = $_.Exception.Message
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "DISM repair failed: $errorMsg", 'Red')
    }
}

# Resets network settings.
Function Handle-btn_SysFix_NetReset {
    $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Resetting network settings...", 'Cyan')
    
    try {
        $success = Reset-NetworkSettings
        if ($success) {
            $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Network reset completed. You may need to reconnect to your network.", 'Green')
        } else {
            $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Network reset completed with errors.", 'Orange')
        }
    }
    catch {
        $errorMsg = $_.Exception.Message
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Network reset failed: $errorMsg", 'Red')
    }
}

# Resets Windows Update components.
Function Handle-btn_SysFix_WUReset {
    $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Resetting Windows Update components...", 'Cyan')
    
    try {
        $success = Reset-WindowsUpdate
        if ($success) {
            $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Windows Update reset completed successfully.", 'Green')
        } else {
            $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Windows Update reset completed with errors.", 'Orange')
        }
    }
    catch {
        $errorMsg = $_.Exception.Message
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Windows Update reset failed: $errorMsg", 'Red')
    }
}

# Clears Windows Update cache.
Function Handle-btn_SysFix_WUClear {
    $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Clearing Windows Update cache...", 'Cyan')
    
    try {
        $success = Clear-WindowsUpdateCache
        if ($success) {
            $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Windows Update cache cleared successfully.", 'Green')
        } else {
            $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Windows Update cache clear completed with errors.", 'Orange')
        }
    }
    catch {
        $errorMsg = $_.Exception.Message
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Windows Update cache clear failed: $errorMsg", 'Red')
    }
}

#========================================================================
# DNS Changer
#========================================================================

# Refreshes network adapter list.
Function Handle-btn_DNS_Refresh {
    try {
        $global:lbl_DNS_Status.Text = "Loading adapters..."
        
        $adapters = Get-NetworkAdapters
        $global:DNSAdaptersList = @($adapters)
        
        $global:cmb_DNS_Adapter.Items.Clear()
        foreach ($adapter in $adapters) {
            $global:cmb_DNS_Adapter.Items.Add($adapter.Name) | Out-Null
        }
        
        if ($adapters.Count -gt 0) {
            $global:cmb_DNS_Adapter.SelectedIndex = 0
            Handle-cmb_DNS_Adapter_SelectionChanged
            $global:lbl_DNS_Status.Text = "$($adapters.Count) adapters loaded"
        } else {
            $global:lbl_DNS_Status.Text = "No active adapters found"
        }
        
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Loaded $($adapters.Count) network adapters", 'Green')
    }
    catch {
        $global:lbl_DNS_Status.Text = "Failed to load"
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Failed to load adapters: $_", 'Red')
    }
}

# Handles adapter selection change.
Function Handle-cmb_DNS_Adapter_SelectionChanged {
    $selectedAdapter = $global:cmb_DNS_Adapter.SelectedItem
    if ([String]::IsNullOrWhiteSpace($selectedAdapter)) {
        return
    }
    
    try {
        $adapter = $global:DNSAdaptersList | Where-Object { $_.Name -eq $selectedAdapter } | Select-Object -First 1
        if ($adapter) {
            $dnsSettings = Get-AdapterDNS -InterfaceAlias $adapter.InterfaceAlias
            $global:lbl_DNS_Primary.Text = $dnsSettings.Primary
            $global:lbl_DNS_Secondary.Text = $dnsSettings.Secondary
            $global:lbl_DNS_Method.Text = $dnsSettings.Method
        }
    }
    catch {
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Failed to get DNS settings: $_", 'Red')
    }
}

# Applies selected DNS provider.
Function Handle-btn_DNS_Apply {
    $selectedAdapter = $global:cmb_DNS_Adapter.SelectedItem
    $selectedProvider = $global:cmb_DNS_Provider.SelectedItem
    
    if ([String]::IsNullOrWhiteSpace($selectedAdapter)) {
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "No adapter selected", 'Orange')
        return
    }
    
    if ([String]::IsNullOrWhiteSpace($selectedProvider)) {
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "No DNS provider selected", 'Orange')
        return
    }
    
    try {
        $adapter = $global:DNSAdaptersList | Where-Object { $_.Name -eq $selectedAdapter } | Select-Object -First 1
        $provider = $global:DNSProvidersList | Where-Object { $_.Name -eq $selectedProvider } | Select-Object -First 1
        
        if ($adapter -and $provider) {
            $global:lbl_DNS_Status.Text = "Applying DNS..."
            $success = Set-AdapterDNS -InterfaceAlias $adapter.InterfaceAlias -PrimaryDNS $provider.Primary -SecondaryDNS $provider.Secondary
            
            if ($success) {
                $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "DNS set to $($provider.Name) for $($adapter.Name)", 'Green')
                Handle-cmb_DNS_Adapter_SelectionChanged
                $global:lbl_DNS_Status.Text = "DNS applied successfully"
            } else {
                $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Failed to apply DNS", 'Red')
                $global:lbl_DNS_Status.Text = "Failed to apply DNS"
            }
        }
    }
    catch {
        $errorMsg = $_.Exception.Message
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Failed to apply DNS: $errorMsg", 'Red')
        $global:lbl_DNS_Status.Text = "Failed to apply DNS"
    }
}

# Resets DNS to DHCP.
Function Handle-btn_DNS_Reset {
    $selectedAdapter = $global:cmb_DNS_Adapter.SelectedItem
    
    if ([String]::IsNullOrWhiteSpace($selectedAdapter)) {
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "No adapter selected", 'Orange')
        return
    }
    
    try {
        $adapter = $global:DNSAdaptersList | Where-Object { $_.Name -eq $selectedAdapter } | Select-Object -First 1
        
        if ($adapter) {
            $global:lbl_DNS_Status.Text = "Resetting DNS..."
            $success = Reset-AdapterDNS -InterfaceAlias $adapter.InterfaceAlias
            
            if ($success) {
                $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "DNS reset to DHCP for $($adapter.Name)", 'Green')
                Handle-cmb_DNS_Adapter_SelectionChanged
                $global:lbl_DNS_Status.Text = "DNS reset successfully"
            } else {
                $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Failed to reset DNS", 'Red')
                $global:lbl_DNS_Status.Text = "Failed to reset DNS"
            }
        }
    }
    catch {
        $errorMsg = $_.Exception.Message
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Failed to reset DNS: $errorMsg", 'Red')
        $global:lbl_DNS_Status.Text = "Failed to reset DNS"
    }
}

# Flushes DNS cache.
Function Handle-btn_DNS_Flush {
    try {
        $global:lbl_DNS_Status.Text = "Flushing DNS cache..."
        $success = Clear-DNSCache
        
        if ($success) {
            $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "DNS cache flushed successfully", 'Green')
            $global:lbl_DNS_Status.Text = "DNS cache flushed"
        } else {
            $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Failed to flush DNS cache", 'Red')
            $global:lbl_DNS_Status.Text = "Failed to flush DNS cache"
        }
    }
    catch {
        $errorMsg = $_.Exception.Message
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Failed to flush DNS cache: $errorMsg", 'Red')
        $global:lbl_DNS_Status.Text = "Failed to flush DNS cache"
    }
}

#========================================================================
# Performance Plans
#========================================================================

# Refreshes power plans list.
Function Handle-btn_Perf_Refresh {
    try {
        $global:lbl_Perf_Status.Text = "Loading plans..."
        
        # Update current plan display
        $activePlan = Get-ActivePowerPlan
        if ($activePlan) {
            $global:lbl_Perf_Current.Text = $activePlan.Name
        } else {
            $global:lbl_Perf_Current.Text = "Unknown"
        }
        
        # Load available plans
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
        
        $global:lbl_Perf_Status.Text = "$($plans.Count) plans loaded"
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Loaded $($plans.Count) power plans", 'Green')
    }
    catch {
        $global:lbl_Perf_Status.Text = "Failed to load"
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Failed to load power plans: $_", 'Red')
    }
}

# Applies selected power plan.
Function Handle-btn_Perf_Apply {
    $selectedPlan = $global:cmb_Perf_Plan.SelectedItem
    
    if ([String]::IsNullOrWhiteSpace($selectedPlan)) {
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "No power plan selected", 'Orange')
        return
    }
    
    try {
        # Extract plan name from selection (remove " (Active)" suffix if present)
        $planName = $selectedPlan -replace " \(Active\)$", ""
        $plan = $global:PowerPlansList | Where-Object { $_.Name -eq $planName } | Select-Object -First 1
        
        if ($plan) {
            $global:lbl_Perf_Status.Text = "Applying plan..."
            $success = Set-PowerPlan -Guid $plan.Guid
            
            if ($success) {
                $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Power plan set to $($plan.Name)", 'Green')
                Handle-btn_Perf_Refresh
                $global:lbl_Perf_Status.Text = "Plan applied successfully"
            } else {
                $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Failed to apply power plan", 'Red')
                $global:lbl_Perf_Status.Text = "Failed to apply plan"
            }
        }
    }
    catch {
        $errorMsg = $_.Exception.Message
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Failed to apply power plan: $errorMsg", 'Red')
        $global:lbl_Perf_Status.Text = "Failed to apply plan"
    }
}

# Enables Ultimate Performance plan.
Function Handle-btn_Perf_Ultimate {
    try {
        $global:lbl_Perf_Status.Text = "Enabling Ultimate Performance..."
        $success = Enable-UltimatePerformancePlan
        
        if ($success) {
            $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Ultimate Performance plan enabled", 'Green')
            Handle-btn_Perf_Refresh
            $global:lbl_Perf_Status.Text = "Ultimate Performance enabled"
        } else {
            $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Failed to enable Ultimate Performance", 'Red')
            $global:lbl_Perf_Status.Text = "Failed to enable"
        }
    }
    catch {
        $errorMsg = $_.Exception.Message
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Failed to enable Ultimate Performance: $errorMsg", 'Red')
        $global:lbl_Perf_Status.Text = "Failed to enable"
    }
}

#========================================================================
# Windows Update
#========================================================================

# Refreshes Windows Update service status.
Function Handle-btn_WU_Refresh {
    try {
        $global:lbl_WU_ActionStatus.Text = "Loading status..."
        
        $services = Get-WindowsUpdateServiceStatus
        $wuService = $services | Where-Object { $_.Name -eq "wuauserv" } | Select-Object -First 1
        
        if ($wuService) {
            $global:lbl_WU_Status.Text = $wuService.Status
            $global:lbl_WU_Startup.Text = $wuService.StartType
        } else {
            $global:lbl_WU_Status.Text = "Unknown"
            $global:lbl_WU_Startup.Text = "Unknown"
        }
        
        $global:lbl_WU_ActionStatus.Text = "Status updated"
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Windows Update service: $($wuService.Status) ($($wuService.StartType))", 'Green')
    }
    catch {
        $global:lbl_WU_ActionStatus.Text = "Failed to load"
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Failed to get Windows Update status: $_", 'Red')
    }
}

# Sets Windows Update to manual mode.
Function Handle-btn_WU_Manual {
    try {
        $global:lbl_WU_ActionStatus.Text = "Setting to manual..."
        $success = Set-WindowsUpdateManual
        
        if ($success) {
            $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Windows Update set to manual (notify only)", 'Green')
            Handle-btn_WU_Refresh
            $global:lbl_WU_ActionStatus.Text = "Manual mode enabled"
        } else {
            $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Failed to set manual mode", 'Red')
            $global:lbl_WU_ActionStatus.Text = "Failed to set manual"
        }
    }
    catch {
        $errorMsg = $_.Exception.Message
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Failed to set manual mode: $errorMsg", 'Red')
        $global:lbl_WU_ActionStatus.Text = "Failed to set manual"
    }
}

# Sets Windows Update to automatic mode.
Function Handle-btn_WU_Auto {
    try {
        $global:lbl_WU_ActionStatus.Text = "Setting to automatic..."
        $success = Set-WindowsUpdateAutomatic
        
        if ($success) {
            $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Windows Update set to automatic", 'Green')
            Handle-btn_WU_Refresh
            $global:lbl_WU_ActionStatus.Text = "Automatic mode enabled"
        } else {
            $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Failed to set automatic mode", 'Red')
            $global:lbl_WU_ActionStatus.Text = "Failed to set automatic"
        }
    }
    catch {
        $errorMsg = $_.Exception.Message
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Failed to set automatic mode: $errorMsg", 'Red')
        $global:lbl_WU_ActionStatus.Text = "Failed to set automatic"
    }
}

# Disables Windows Update.
Function Handle-btn_WU_Disable {
    try {
        $global:lbl_WU_ActionStatus.Text = "Disabling Windows Update..."
        $success = Disable-WindowsUpdate
        
        if ($success) {
            $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Windows Update disabled", 'Green')
            Handle-btn_WU_Refresh
            $global:lbl_WU_ActionStatus.Text = "Windows Update disabled"
        } else {
            $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Failed to disable Windows Update", 'Red')
            $global:lbl_WU_ActionStatus.Text = "Failed to disable"
        }
    }
    catch {
        $errorMsg = $_.Exception.Message
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Failed to disable Windows Update: $errorMsg", 'Red')
        $global:lbl_WU_ActionStatus.Text = "Failed to disable"
    }
}

# Checks for Windows updates.
Function Handle-btn_WU_Check {
    try {
        $global:lbl_WU_ActionStatus.Text = "Checking for updates..."
        $success = Invoke-WindowsUpdateCheck
        
        if ($success) {
            $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Windows Update check initiated", 'Green')
            $global:lbl_WU_ActionStatus.Text = "Check initiated"
        } else {
            $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Failed to check for updates", 'Red')
            $global:lbl_WU_ActionStatus.Text = "Check failed"
        }
    }
    catch {
        $errorMsg = $_.Exception.Message
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Failed to check for updates: $errorMsg", 'Red')
        $global:lbl_WU_ActionStatus.Text = "Check failed"
    }
}

# Opens Windows Update settings.
Function Handle-btn_WU_OpenSettings {
    try {
        Start-Process "ms-settings:windowsupdate"
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Opened Windows Update settings", 'Green')
    }
    catch {
        $errorMsg = $_.Exception.Message
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Failed to open settings: $errorMsg", 'Red')
    }
}

#========================================================================
# QR Code Generator tab
#========================================================================

# Generates a QR code from the entered text/URL.
Function Handle-btn_QRCode_Generate {
    try {
        $text = $global:txt_QRCode_Text.Text.Trim()
        
        if ([String]::IsNullOrWhiteSpace($text)) {
            $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Please enter text or URL to generate QR code", 'Red')
            $global:lbl_QRCode_Status.Text = "Enter text first"
            return
        }

        # Get selected size from ComboBox
        $sizeItem = $global:cmb_QRCode_Size.SelectedItem
        $size = if ($sizeItem) { [int]$sizeItem.Tag } else { 300 }

        $global:lbl_QRCode_Status.Text = "Generating..."
        
        # Generate QR code to temp file
        $tempPath = Get-QRCodeTempPath
        $success = New-QRCode -Text $text -OutputPath $tempPath -Size $size
        
        if ($success -and (Test-Path $tempPath)) {
            # Load the image into the WPF Image control
            $bitmap = [System.Windows.Media.Imaging.BitmapImage]::new()
            $bitmap.BeginInit()
            $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
            $bitmap.UriSource = [System.Uri]::new($tempPath)
            $bitmap.EndInit()
            $bitmap.Freeze()
            
            $global:img_QRCode.Source = $bitmap
            $global:QRCodeCurrentPath = $tempPath
            
            $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "QR code generated successfully", 'Green')
            $global:lbl_QRCode_Status.Text = "Generated successfully"
        } else {
            $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Failed to generate QR code", 'Red')
            $global:lbl_QRCode_Status.Text = "Generation failed"
        }
    }
    catch {
        $errorMsg = $_.Exception.Message
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "QR code generation error: $errorMsg", 'Red')
        $global:lbl_QRCode_Status.Text = "Error occurred"
    }
}

# Saves the current QR code image to a user-selected location.
Function Handle-btn_QRCode_Save {
    try {
        if ([String]::IsNullOrEmpty($global:QRCodeCurrentPath) -or -not (Test-Path $global:QRCodeCurrentPath)) {
            $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "No QR code to save - generate one first", 'Red')
            $global:lbl_QRCode_Status.Text = "Generate QR code first"
            return
        }

        $dialog = New-Object System.Windows.Forms.SaveFileDialog -Property @{
            Title            = 'Save QR Code'
            Filter           = 'PNG Image (*.png)|*.png|All Files (*.*)|*.*'
            DefaultExt       = 'png'
            InitialDirectory = $global:GUIHandler.InitialFolderPath
        }

        if ($dialog.ShowDialog() -eq 'OK') {
            Copy-Item -Path $global:QRCodeCurrentPath -Destination $dialog.FileName -Force
            $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "QR code saved to $($dialog.FileName)", 'Green')
            $global:lbl_QRCode_Status.Text = "Saved successfully"
        }
    }
    catch {
        $errorMsg = $_.Exception.Message
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Failed to save QR code: $errorMsg", 'Red')
        $global:lbl_QRCode_Status.Text = "Save failed"
    }
}

# Opens the current QR code image in the default image viewer.
Function Handle-btn_QRCode_Open {
    try {
        if ([String]::IsNullOrEmpty($global:QRCodeCurrentPath) -or -not (Test-Path $global:QRCodeCurrentPath)) {
            $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "No QR code to open - generate one first", 'Red')
            $global:lbl_QRCode_Status.Text = "Generate QR code first"
            return
        }

        Start-Process $global:QRCodeCurrentPath
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Opened QR code in default viewer", 'Green')
        $global:lbl_QRCode_Status.Text = "Opened in viewer"
    }
    catch {
        $errorMsg = $_.Exception.Message
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Failed to open QR code: $errorMsg", 'Red')
        $global:lbl_QRCode_Status.Text = "Open failed"
    }
}
