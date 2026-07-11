#========================================================================
# Cmb-Actions.ps1 — WPF combobox/selection handlers.
#========================================================================

# Loads the command text of a selected preset into the command editor.
# $cmb_trigger identifies which tab triggered it (room to grow as more
# Search->Description->Command tabs are added).
Function Handle-PS-cmb {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $True)]
        [String]
        $cmb_trigger
    )

    # 1. Resolve the chosen description
    $chosenDescription = $null
    switch ($cmb_trigger) {
        'cmb_LocalPS' {
            $chosenDescription = if ($global:cmb_LocalPS_Desc.SelectedItem) {
                $global:cmb_LocalPS_Desc.SelectedItem.ToString()
            } else {
                $global:cmb_LocalPS_Desc.Text
            }
        }
        default {
            $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "PS-cmb trigger not handled: $cmb_trigger", 'Red')
            return
        }
    }

    if ([String]::IsNullOrEmpty($chosenDescription)) { return }

    # 2. Map description -> command
    $chosenCommand = $global:GUIHandler.Get_PS_Command_By_Description($chosenDescription)
    if ([String]::IsNullOrEmpty($chosenCommand)) { return }

    # 3. Drop it into the right command editor
    switch ($cmb_trigger) {
        'cmb_LocalPS' { $global:cmb_LocalPS_Command.Text = $chosenCommand }
    }
}

# Loads a selected registry tweak into the path/description/entry grid and
# reads the current value of each entry.
Function Handle-cmb_Reg_Tweak {

    $name = $global:cmb_Reg_Tweak.SelectedItem
    if ([String]::IsNullOrEmpty($name)) { return }

    $tweak = $global:RegistryTweaksList | Where-Object { $_.name -eq $name } | Select-Object -First 1
    if ($null -eq $tweak) {
        $global:GUIHandler.Visual_Log($env:COMPUTERNAME, "Tweak not found: $name", 'Red')
        return
    }

    $global:Reg_SelectedTweak = $tweak
    $global:txt_Reg_Path.Text = $tweak.path
    $global:lbl_Reg_Desc.Text = $tweak.description

    # Populate the entry grid (Current read live; NewValue editable)
    $global:dgr_Reg_Entries.Items.Clear()
    foreach ($entry in $tweak.entries) {
        $current = $global:GUIHandler.Get_RegistryValue($tweak.path, $entry.name)
        $global:dgr_Reg_Entries.AddChild([pscustomobject]@{
            Key      = $entry.name
            Type     = $entry.type
            Current  = $current
            NewValue = $entry.value
        }) | Out-Null
    }

    # Warn if this tweak needs elevation we don't have
    if ($tweak.admin -and -not $global:GUIHandler.Test_IsAdmin()) {
        $global:lbl_Reg_AdminWarn.Text = "Needs Administrator — run the app elevated to apply."
    }
    else {
        $global:lbl_Reg_AdminWarn.Text = ""
    }
}
