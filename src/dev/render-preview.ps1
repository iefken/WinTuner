$ErrorActionPreference = 'Stop'
$Global:ConfigFiles = 'E:\Dev\Powershell\PcManagementTool'
$Global:IniPath     = Join-Path $Global:ConfigFiles 'ini.json'
$AllIni = Get-Content $Global:IniPath -Raw | ConvertFrom-Json
$ap = $AllIni[0].ActiveProfile; if (-not $ap) { $ap = 'home' }
$Global:IniFile    = $AllIni | Where-Object { $_.Profile -eq $ap }
$Global:ConfigPath = Join-Path $Global:ConfigFiles $Global:IniFile.ConfigPath
$Global:LogPath    = Join-Path $Global:ConfigFiles $Global:IniFile.LogPath
$Global:AppVersion = $Global:IniFile.AppVersion
. $Global:ConfigPath

try { $Global:GUIHandler.Get_Userdata() } catch {}
try { [GUI_Handler]::Populate_Disks() } catch {}
try { [GUI_Handler]::Prepare_ComboBoxes() } catch {}
try { [GUI_Handler]::Prepare_QuickLaunch() } catch { Write-Host "QuickLaunch: $_" }
try { $Global:tbc_Main.SelectedIndex = [int]$env:PREVIEW_TAB } catch {}
try { $Global:cmb_LocalPS_Command.Text = "gpresult /r`nGet-Process | Sort CPU -Desc | Select -First 5`n`$global:x = 42" } catch {}
try { $Global:cmb_FC_Path.Text = 'C:\Users\Public\Desktop\' } catch {}
try { $Global:txt_FC_Filter.Text = 'report' } catch {}

# --- representative sample data so the preview matches a running app ---
try { $Global:txt_AdminStatus.Text = 'Administrator (elevated)'; $Global:txt_AdminStatus.Foreground = [System.Windows.Media.Brushes]::LightGreen } catch {}
try { $Global:txt_YourUserName.Text = 'Ief' } catch {}
try { $Global:txt_YourPcName.Text   = 'DESKTOP-9MD8119' } catch {}
try { $Global:txt_YourIP.Text       = '192.168.56.1' } catch {}
try { $Global:txt_YourNetwork.Text  = 'TP-Link_533A 2' } catch {}
try {
    $Global:dgr_Disks.ItemsSource = @(
        [pscustomobject]@{ Drive='C:'; Label='(no label)'; UsedGB='369.8'; TotalGB='931.5'; FreeGB='561.7'; UsedPct='40%' }
        [pscustomobject]@{ Drive='E:'; Label='Local Disk'; UsedGB='128.6'; TotalGB='931.5'; FreeGB='802.9'; UsedPct='14%' }
        [pscustomobject]@{ Drive='F:'; Label='(no label)'; UsedGB='226';   TotalGB='238.3'; FreeGB='12.3';  UsedPct='95%' }
    )
} catch {}

$w = $Global:Form
$w.WindowStartupLocation = 'Manual'
$w.Left = -10000; $w.Top = -10000
$w.Show()
$w.UpdateLayout()
Start-Sleep -Milliseconds 500
[System.Windows.Forms.Application]::DoEvents()

$wd = [int]$w.ActualWidth; $ht = [int]$w.ActualHeight
$rtb = New-Object System.Windows.Media.Imaging.RenderTargetBitmap($wd, $ht, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
$rtb.Render($w)
$enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
$enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($rtb))
$fs = [IO.File]::Create((Join-Path $Global:ConfigFiles 'preview.png'))
$enc.Save($fs); $fs.Close()
$w.Close()
Write-Host "RENDERED $wd x $ht"
