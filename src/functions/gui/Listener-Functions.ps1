#========================================================================
# Listener-Functions.ps1 — wires WPF control events to handlers.
#
# Add_Click_listeners() is invoked (bare call at the bottom) when this
# file is dot-sourced by Import-Functions.ps1. By then Config.ps1 has
# already parsed the XAML, so all $global: controls exist.
#========================================================================

Function Add_Click_listeners {

    #--------------------------------------------------------------------
    # This machine (general info)
    #--------------------------------------------------------------------

    $global:btn_Elevate.add_Click({ Handle-btn_Elevate })

    # Disks grid: re-read the local fixed drives on demand.
    $global:btn_Disks_Refresh.add_Click({ [GUI_Handler]::Populate_Disks() })

    # Disks grid: double-click a row to open that drive in Explorer.
    $global:dgr_Disks.add_MouseDoubleClick({
        $row = $global:dgr_Disks.SelectedItem
        if ($row -and $row.Drive) {
            # Drive is the bare letter form ("C:"); append "\" for the root path.
            $global:GUIHandler.Open_Path("$($row.Drive)\")
        }
    })

    # Common paths: single left-click opens the folder in Explorer.
    $global:lst_QuickPaths.add_PreviewMouseLeftButtonUp({
        param($sender, $e)
        Handle-QuickPath-Click -OriginalSource $e.OriginalSource
    })

    # Common apps: now icon tiles (Buttons) built in Prepare_QuickLaunch, which
    # wires each tile's left-click (launch) / right-click (run as admin) itself.

    #--------------------------------------------------------------------
    # Local PS tab
    #--------------------------------------------------------------------

    # Run / clear buttons
    $global:btn_Run_LocalPS.add_Click({ Handle-btn_Run_LocalPS })
    $global:btn_Clear_LocalPS.add_Click({ Handle-btn_Clear_LocalPS })

    # Enter in the command editor runs it; Shift+Enter inserts a newline
    $global:cmb_LocalPS_Command.Add_KeyDown({
        if ($_.Key -eq 'Enter') {
            $shiftHeld = [System.Windows.Input.Keyboard]::IsKeyDown([System.Windows.Input.Key]::LeftShift) -or
                         [System.Windows.Input.Keyboard]::IsKeyDown([System.Windows.Input.Key]::RightShift)
            if (-not $shiftHeld) {
                $_.Handled = $true
                Handle-btn_Run_LocalPS
            }
        }
    })

    # Type-to-filter in the Search box -> filter the preset dropdown
    $global:cmb_LocalPS.add_KeyUp({
        param($sender, $e)
        $skipKeys = @('Up','Down','Enter','Escape','Tab','Left','Right','LeftShift','RightShift','LeftCtrl','RightCtrl')
        if ($e.Key.ToString() -in $skipKeys) { return }

        $typed = $sender.Text
        $global:cmb_LocalPS_Desc.Items.Clear()
        $global:PwsCommandsFullList | Where-Object { $_ -like "*$typed*" } | ForEach-Object {
            $global:cmb_LocalPS_Desc.Items.Add($_) | Out-Null
        }
        $sender.CaretIndex = $typed.Length
        $global:cmb_LocalPS_Desc.IsDropDownOpen = ($global:cmb_LocalPS_Desc.Items.Count -gt 0)
    })

    # Enter in Search -> take first match, load it, jump to command editor
    $global:cmb_LocalPS.Add_KeyDown({
        if ($_.Key -eq 'Enter') {
            if ($global:cmb_LocalPS_Desc.Items.Count -gt 0) {
                $global:cmb_LocalPS_Desc.SelectedIndex = 0
                Handle-PS-cmb -cmb_trigger 'cmb_LocalPS'
            }
            [System.Windows.Input.Keyboard]::Focus($global:cmb_LocalPS_Command) | Out-Null
        }
    })

    # Repopulate the dropdown when opened (respects current Search text).
    # DropDownOpened (not GotKeyboardFocus) avoids clearing SelectedItem after a pick.
    $global:cmb_LocalPS_Desc.add_DropDownOpened({
        param($sender, $e)
        $typed = $global:cmb_LocalPS.Text
        $sender.Items.Clear()
        if ([String]::IsNullOrEmpty($typed)) {
            $global:PwsCommandsFullList | ForEach-Object { $sender.Items.Add($_) | Out-Null }
        } else {
            $global:PwsCommandsFullList | Where-Object { $_ -like "*$typed*" } | ForEach-Object { $sender.Items.Add($_) | Out-Null }
        }
    })

    # Picking a preset loads its command and focuses the editor
    $global:cmb_LocalPS_Desc.Add_DropDownClosed({
        if ($global:cmb_LocalPS_Desc.SelectedItem) {
            Handle-PS-cmb -cmb_trigger 'cmb_LocalPS'
            [System.Windows.Input.Keyboard]::Focus($global:cmb_LocalPS_Command) | Out-Null
        }
    })

    #--------------------------------------------------------------------
    # File Cleanup tab
    #--------------------------------------------------------------------

    $global:btn_FC_Browse.add_Click({ Handle-btn_FC_Browse })
    $global:btn_FC_Preview.add_Click({ Handle-btn_FC_Preview })
    $global:btn_FC_Delete.add_Click({ Handle-btn_FC_Delete })

    #--------------------------------------------------------------------
    # Registry tab
    #--------------------------------------------------------------------

    $global:cmb_Reg_Tweak.add_SelectionChanged({ Handle-cmb_Reg_Tweak })
    $global:btn_Reg_GetValue.add_Click({ Handle-btn_Reg_GetValue })
    $global:btn_Reg_Apply.add_Click({ Handle-btn_Reg_Apply })

    #--------------------------------------------------------------------
    # COM Ports tab
    #--------------------------------------------------------------------

    $global:btn_COM_Start.add_Click({ Handle-btn_COM_Start })
    $global:btn_COM_Stop.add_Click({ Handle-btn_COM_Stop })
    $global:btn_COM_Refresh.add_Click({ Handle-btn_COM_Refresh })

    #--------------------------------------------------------------------
    # Diagnostics tab
    #--------------------------------------------------------------------

    $global:btn_Diag_Run.add_Click({ Handle-btn_Diag_Run })
    $global:btn_Diag_Stop.add_Click({ Handle-btn_Diag_Stop })
    $global:btn_Diag_Clear.add_Click({ Handle-btn_Diag_Clear })
    $global:btn_Diag_Save.add_Click({ Handle-btn_Diag_Save })

    #--------------------------------------------------------------------
    # WinGet Apps tab
    #--------------------------------------------------------------------

    $global:btn_WinGet_Search.add_Click({ Handle-btn_WinGet_Search })
    $global:btn_WinGet_GetInstalled.add_Click({ Handle-btn_WinGet_GetInstalled })
    $global:btn_WinGet_Clear.add_Click({ Handle-btn_WinGet_Clear })
    $global:btn_WinGet_Install.add_Click({ Handle-btn_WinGet_Install })
    $global:btn_WinGet_Update.add_Click({ Handle-btn_WinGet_Update })
    $global:btn_WinGet_Uninstall.add_Click({ Handle-btn_WinGet_Uninstall })

    # Enter in search box triggers search
    $global:txt_WinGet_Search.Add_KeyDown({
        if ($_.Key -eq 'Enter') {
            $_.Handled = $true
            Handle-btn_WinGet_Search
        }
    })

    #--------------------------------------------------------------------
    # Installed Software tab
    #--------------------------------------------------------------------

    $global:btn_Installed_Refresh.add_Click({ Handle-btn_Installed_Refresh })
    $global:btn_Installed_Clear.add_Click({ Handle-btn_Installed_Clear })
    $global:btn_Installed_Uninstall.add_Click({ Handle-btn_Installed_Uninstall })

    # Enter in search box triggers refresh with filter
    $global:txt_Installed_Search.Add_KeyDown({
        if ($_.Key -eq 'Enter') {
            $_.Handled = $true
            Handle-btn_Installed_Refresh
        }
    })

    # Sort/order dropdown changes trigger refresh
    $global:cmb_Installed_Sort.Add_SelectionChanged({
        Handle-btn_Installed_Refresh
    })
    $global:cmb_Installed_Order.Add_SelectionChanged({
        Handle-btn_Installed_Refresh
    })

    #--------------------------------------------------------------------
    # Windows Features tab
    #--------------------------------------------------------------------

    $global:btn_WinFeat_Refresh.add_Click({ Handle-btn_WinFeat_Refresh })
    $global:btn_WinFeat_Enable.add_Click({ Handle-btn_WinFeat_Enable })
    $global:btn_WinFeat_Disable.add_Click({ Handle-btn_WinFeat_Disable })

    #--------------------------------------------------------------------
    # System Fixes tab
    #--------------------------------------------------------------------

    $global:btn_SysFix_SFC.add_Click({ Handle-btn_SysFix_SFC })
    $global:btn_SysFix_DISM.add_Click({ Handle-btn_SysFix_DISM })
    $global:btn_SysFix_NetReset.add_Click({ Handle-btn_SysFix_NetReset })
    $global:btn_SysFix_WUReset.add_Click({ Handle-btn_SysFix_WUReset })
    $global:btn_SysFix_WUClear.add_Click({ Handle-btn_SysFix_WUClear })

    #--------------------------------------------------------------------
    # DNS Changer tab
    #--------------------------------------------------------------------

    $global:btn_DNS_Refresh.add_Click({ Handle-btn_DNS_Refresh })
    $global:btn_DNS_Apply.add_Click({ Handle-btn_DNS_Apply })
    $global:btn_DNS_Reset.add_Click({ Handle-btn_DNS_Reset })
    $global:btn_DNS_Flush.add_Click({ Handle-btn_DNS_Flush })

    $global:cmb_DNS_Adapter.Add_SelectionChanged({ Handle-cmb_DNS_Adapter_SelectionChanged })

    #--------------------------------------------------------------------
    # Performance Plans tab
    #--------------------------------------------------------------------

    $global:btn_Perf_Refresh.add_Click({ Handle-btn_Perf_Refresh })
    $global:btn_Perf_Apply.add_Click({ Handle-btn_Perf_Apply })
    $global:btn_Perf_Ultimate.add_Click({ Handle-btn_Perf_Ultimate })

    #--------------------------------------------------------------------
    # Windows Update tab
    #--------------------------------------------------------------------

    $global:btn_WU_Refresh.add_Click({ Handle-btn_WU_Refresh })
    $global:btn_WU_Manual.add_Click({ Handle-btn_WU_Manual })
    $global:btn_WU_Auto.add_Click({ Handle-btn_WU_Auto })
    $global:btn_WU_Disable.add_Click({ Handle-btn_WU_Disable })
    $global:btn_WU_Check.add_Click({ Handle-btn_WU_Check })
    $global:btn_WU_OpenSettings.add_Click({ Handle-btn_WU_OpenSettings })

    #--------------------------------------------------------------------
    # QR Code Generator tab
    #--------------------------------------------------------------------

    $global:btn_QRCode_Generate.add_Click({ Handle-btn_QRCode_Generate })
    $global:btn_QRCode_Save.add_Click({ Handle-btn_QRCode_Save })
    $global:btn_QRCode_Open.add_Click({ Handle-btn_QRCode_Open })

    # Enter in text box triggers generation
    $global:txt_QRCode_Text.Add_KeyDown({
        if ($_.Key -eq 'Enter') {
            $_.Handled = $true
            Handle-btn_QRCode_Generate
        }
    })
}

#========================================================================
# Register all listeners now (runs when this file is dot-sourced)
#========================================================================

Add_Click_listeners
