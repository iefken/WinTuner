# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project is

A personal PowerShell + WPF GUI utility called **WinTuner** for performing **local PC** management/maintenance tasks
(file cleanup, registry tweaks, printer handling, storage info, a local-PS REPL, repo/version comparison,
etc.). It is being built by porting the **local-only** parts of the larger
`DHL_DEVICE_MANAGER` project — deliberately leaving behind anything that does remote work.

### Scope boundary (hard rule)

**Local-machine only.** Do **not** port or write:

- API calls / network service integrations
- Remote installs, remote PowerShell (`Invoke-Command -ComputerName`, WinRM), remote file pushes
- Active Directory / domain lookups, multi-hub network-share logic, credential export for remote use

If a candidate feature from the source project reaches across the network, it is out of scope — flag it and
ask before adapting. When in doubt, prefer the local equivalent (e.g. operate on `$env:COMPUTERNAME` /
`localhost`, not a remote `-ComputerName`).

## Current state

Bootstrap + shared infra + first features are in place and pass `Test-DevStartup.ps1` (158/158):

- **Phase 0/1 (done):** `Main.ps1` → `src/functions/Config.ps1` → `Load-XamlForm.ps1` + `Import-Functions.ps1`;
  `GUI_Handler` class (`Visual_Log`, `Get_Userdata`, path helpers); `Helper-Functions.ps1`; minimal WPF shell
  with a Home tab + activity-log RichTextBox.
- **Phase 2 (done):** **Local PS** tab — an in-process PowerShell runner driven by
  `src/gui/form_prefills/pws_commands.json` (42 local presets). Search → Preset → Command → Run, output to a
  console TextBox. Files: `gui/Btn-Actions.ps1`, `gui/Cmb-Actions.ps1`, `gui/Listener-Functions.ps1`.

  Commands execute in the app's own runspace via `Invoke-Expression`; only `$global:` assignments survive
  between runs (the UI promises exactly that, nothing more).
- **Phase 3 (done):** **File Cleanup** tab — pick/enter a folder (presets from `common_paths.csv`), optional
  name filter (bare text → `*contains*`, explicit `*`/`?` kept as-is) + recurse, **Preview** into a grid,
  then **Delete** with a confirm dialog. Defaults to **Recycle Bin** (`Microsoft.VisualBasic.FileIO`).
  Delete operates only on the previewed set (`$global:FC_PreviewItems`); on a locked-file failure it names
  the holding process via `Get-FileLockProcess`. Utilities live in `src/functions/File-Functions.ps1`
  (`Get-FileLockProcess`, `Get-FileEncoding` — both callable from the Local PS REPL too).

- **Phase 4 (done):** **Registry** tab — preset tweaks from `registry_tweaks.json` (8 entries; **autologon
  intentionally dropped** as a passwordless-login risk). Pick a tweak → path + per-value grid (name / type /
  current / editable new value); **Read current** and **Apply** (confirm dialog). Registry I/O lives on
  `GUI_Handler` (`Get_RegistryValue`, `Set_RegistryValue`, `Test_IsAdmin`); paths are stored in clean
  `HKEY_...` form and `Registry::`-prefixed at use. HKLM/HKU writes need an elevated app — the UI warns when
  not admin and `Apply` refuses rather than throwing.

- **Phase 5 (done):** **COM Ports** tab — watches serial/COM devices connect/disconnect. Uses a
  `System.Windows.Threading.DispatcherTimer` (2s) that snapshots `Win32_PnPEntity` (`PNPClass='Ports'`) and
  diffs against the last poll, logging PRESENT/ADDED/REMOVED. **NOT** `Register-WmiEvent -Action` — those
  callbacks never fire while the main thread is blocked in `Form.ShowDialog()`. Helpers in
  `src/functions/COM-Functions.ps1` (`Get-ComFromName`, `Get-ComPortSnapshot`); poll/start/stop in
  `gui/Btn-Actions.ps1`. (ZPL/label-printer was dropped from scope by request.)

- **Phase 6 (done):** **Diagnostics** tab — local network checks (ipconfig /all, nslookup, ping, tracert)
  against an optional target. The slow CLI tools run in a background `Start-Job`; a `DispatcherTimer` (500ms)
  drains job output into a console box on the UI thread, so the window stays responsive. Run/Stop/Clear/Save
  (Save → timestamped file under `logs\diagnostics\`). All in `gui/Btn-Actions.ps1`. (Rewritten, not ported:
  the donor was a parallel `Workflow` dumping per-host files.)

- **WinGet Apps tab (fixed):** search / list / install / update / uninstall via the `winget` CLI.
  All winget calls go through `Invoke-WinGet` in `src/functions/WinGet-Functions.ps1` (captures output +
  exit code, no console window). Install/Update/Uninstall run in a background `Start-Job` +
  `DispatcherTimer` (same pattern as Diagnostics) and disable the tab's buttons while in flight; Search and
  Get Installed stay synchronous. Covered by Step 13 of `Test-DevStartup.ps1`.

- **Hardware Info (done):** **System Info → Hardware Info** tab — read-only local inventory in three grids:
  display adapters (VRAM, vendor, driver + date, current mode), **CPU & memory**, and system/motherboard/BIOS
  details. Buttons: Scan Hardware / Copy to Clipboard / Save Report (timestamped file under `logs\hardware\`).
  Scanning is **manual** — nothing runs at startup. Logic lives in `src/functions/Hardware-Functions.ps1`
  (`Get-GpuInfo`, `Get-CpuInfo`, `Get-MemoryInfo`, `Get-SystemHardware`, `Get-HardwareSummary`,
  `Get-CpuMemoryNodes`, `Format-HardwareReport`), all callable from the Local PS REPL too. Covered by
  Step 14 of `Test-DevStartup.ps1`.

  The CPU & memory grid **aggregates identical items**: matching memory sticks collapse into one
  `2 x 32.00 GB` row and a multi-socket box collapses into `2 x <model>`; a caret (▸/▾) expands the row to
  list them per slot/socket. `Get-CpuMemoryNodes` builds parent nodes (`New-HardwareNode`), and
  `Expand-HardwareNodes` flattens them into the rows currently visible — PSCustomObject raises no change
  notifications, so toggling re-assigns `ItemsSource` rather than mutating in place. The caret buttons live
  in a `DataGridTemplateColumn` and have no `x:Name`, so their Click is caught on the grid itself via
  `AddHandler(ButtonBase.ClickEvent, ...)` and the row comes from `$e.OriginalSource.DataContext`.
  `Get-HardwareSummary -Sections` keeps the two lower grids from listing the same facts twice while the
  text report still gets everything.

  The three tables are separated by `GridSplitter`s (`RowSplitter` style) so their heights are draggable.
  The GPU row stays `Auto` — it starts exactly as tall as the adapters it holds, and a drag replaces that
  with an explicit height anyway; the two lower rows are star-sized with `MinHeight`, so growing one shrinks
  its neighbour instead of pushing the footer off the tab.

- **QR / barcode generator (done, rewritten):** **Tools → QR / Barcode** (`tab_QRCode`) — type in the box and the code redraws
  on every keystroke; there is no Generate button. Encoding is **100% local and in-process** via
  **ZXing.Net** (Apache-2.0), committed under `lib/` — see `lib/README.md` for version, hashes and how to
  replace it. The original implementation GET'd `api.qrserver.com`, which meant the payload left the machine,
  a render needed internet, and the UI thread blocked on HTTP; all three are gone.

  Logic lives in `src/functions/Barcode-Functions.ps1` (`Get-BarcodeFormats`, `Get-BarcodeFormat`,
  `Import-BarcodeAssemblies`, `New-BarcodeBitmap`, `Test-BarcodeText`, `Save-BarcodeBitmap`, plus
  `New-QRCode` / `Show-QRCode` / `Get-QRCodeTempPath` kept for file-based and REPL callers). It is written
  **format-first, not QR-first**: 14 symbologies already encode (QR, Aztec, Data Matrix, PDF417, Code
  128/39/93, Codabar, EAN-8/13, UPC-A/E, ITF, MSI). Covered by Step 16 of `Test-DevStartup.ps1`, which
  encodes every advertised format and re-renders with the default proxy pointed at a closed port.

  - The **Format** dropdown (`cmb_QRCode_Format`) is filled by `Prepare_ComboBoxes` from
    `Get-BarcodeFormats` — never hardcoded in XAML, so a decode-only symbology cannot be offered.
    It holds **display strings**, like every other ComboBox here, and `Get-BarcodeFormat` maps the string
    back to its format object. Binding the objects with `DisplayMemberPath` renders
    `@{Key=EAN_13; Display=…}` in the closed box under this app's ComboBox `ControlTemplate`.
    `Get-QRCodeSelectedFormat` still falls back to QR when the control is absent.
  - ZXing's `BarcodeFormat` enum contains **decode-only** members (`MAXICODE`, `RSS_14`, `RSS_EXPANDED`,
    `IMB`, `PHARMA_CODE`, `All_1D`, `UPC_EAN_EXTENSION`). Offering one in the UI earns a runtime
    "No encoder available for format X", so `$script:BarcodeFormats` lists only what actually writes.
  - `zxing.presentation.dll` is what makes `ZXing.Presentation.BarcodeWriter` return a WPF `WriteableBitmap`.
    Without it the only renderer is the `System.Drawing` one — a `Bitmap` → PNG → `BitmapImage` round-trip
    through a temp file on every keystroke. **Nothing is written to disk while typing**; Save encodes
    straight to the chosen path and Open writes one temp file on demand.
  - 1D codes render as a strip (`Size` × `0.45`), not a square; 2D codes stay square.
  - **The preview draws at true pixel size (`Stretch="None"` in a `ScrollViewer`), so the Size picker
    visibly does something.** `img_QRCode` used to be pinned to `Width`/`Height` 300 with
    `Stretch="Uniform"`: 200 and 500 looked identical on screen even though the saved PNG differed, which
    reads as a broken picker. Scale-to-fit (`StretchDirection="DownOnly"`) was tried and is worse — in a
    short window every size collapses to the panel height and they all match again. A code larger than the
    panel now scrolls, and the status line always states the real size (`Up to date - 500 x 500 px`).
    The display row is the star row; it was `Auto` while the hint below held the star row, which left a
    dead gap under the hint and let a large code overflow its own panel.
  - **The human-readable caption under 1D codes is drawn by us, not by ZXing.** `PureBarcode = $false` is
    honoured only by ZXing's `System.Drawing` renderer — `WriteableBitmapRenderer` exposes `Font*`
    properties and ignores them, and adopting the GDI renderer would cost a `Bitmap` → PNG → `BitmapImage`
    round-trip per keystroke. So `New-BarcodeBitmap` asks for a pure symbol and `Add-BarcodeCaption`
    composites the payload underneath with `DrawingVisual` + `FormattedText` → `RenderTargetBitmap`,
    entirely in WPF.
    - **The bars give up the caption's height; the strip does not grow** — the footprint stays
      `Size` × `Size * 0.45` whether captioned or not.
    - Caption band is 24% of the strip (clamped 10–40px), Consolas so digit columns line up. A payload
      wider than the symbol is scaled down to fit rather than clipped.
    - Below ~24px of remaining bar height the caption is **dropped rather than shrinking the bars** into
      something a scanner can't read — that's the `Size 60` case.
    - `-NoCaption` suppresses it and gives the space back to the bars. 2D formats never get one.
    - **`src/dev/render-preview.ps1` cannot be trusted for this tab.** Its screenshot of the QR tab shows
      the bars without the caption, even though `img_QRCode.Source` is provably the composited 500×225
      bitmap (save it with `Save-BarcodeBitmap` and the digits are there) and the Image control lays out at
      300×135, the captioned aspect. The harness renders an off-screen window (`Left/Top = -10000`) into a
      `RenderTargetBitmap`, and that path mis-composites this image. Verify barcode changes by saving
      `$global:img_QRCode.Source` to a PNG, not by screenshotting the window.
  - **`install.ps1` delivers this app as a downloaded ZIP, so every extracted file carries a mark-of-the-web
    stream and `Add-Type` refuses to load a blocked assembly.** `Import-BarcodeAssemblies` runs
    `Unblock-File` over `lib\*.dll` before loading them. Config.ps1 calls it at startup so a missing or
    blocked DLL shows up in the Activity log at launch instead of as a dead tab later — and it *logs*
    rather than throws, because one broken tab must not stop the app.

- **Bootable USB (stub):** **Tools → Bootable USB** (`tab_BootUSB`) is a placeholder only — no handlers, no
  logic. Intended scope: list removable drives, install/update **Ventoy** on the selected stick, manage the
  ISOs on it. Two things to settle before building it: every write must confirm against a named target drive
  (this formats a disk), and fetching the Ventoy release itself is an outbound call — the only other one in
  the app is the update check, so decide deliberately rather than drifting past the local-only boundary.

Remaining phases (repo comparer, storage rewrite) follow the proven donor layout — build into this shape
unless we explicitly decide to diverge.

Notes:
- **`Win32_VideoController.AdapterRAM` is a UInt32 — it wraps at 4 GB.** A 12 GB card reports ~4095 MB, which
  is why `Get-GpuVramBytes` reads `HardwareInformation.qwMemorySize` from the display driver's own key under
  `HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\NNNN` (matched on
  `DriverDesc`), falling back to the older `HardwareInformation.MemorySize` (DWORD *or* little-endian
  REG_BINARY, hence `ConvertTo-VramBytes`) and only then to `AdapterRAM`.
- `Get-FileEncoding` is a **ground-up rewrite** (BOM byte inspection), not a port — the donor's version was
  a no-op that always returned "UTF8".
- `registry_tweaks.json` schema is a **redesign** of the donor's flat `key/val/key1..key4` CSV into clean
  per-tweak `entries[]` (`name`/`type`/`value`).

## winget CLI gotchas (these bit us — every install failed)

- **Column order is `Name  Id  Version  [Match|Available]  Source`.** Reading Name/Id the other way round
  makes the app pass a *display name* to `winget install`, which then reports "No package found". Always
  install with `--id <id> --exact`.
- **Never parse winget's table with a token regex.** Names contain spaces (`NoteTab Light`) and trailing
  columns are frequently empty (`winget list` rows with no Source), so a `(\S+)\s+(\S+)…` pattern both
  mangles and silently drops rows. `ConvertFrom-WinGetTable` derives column offsets from the header line
  above the dashed separator and slices on those. The `Match` column disappears on exact hits, so the
  column count varies — key off the header, not a fixed position.
- **`--silent` and `--interactive` are mutually exclusive.** Passing both aborts with `0x8A150002`
  ("More than one execution behavior argument provided") before winget does any work.
- **Non-zero doesn't always mean failure.** `0x8A15002B` is "no newer version available" — a no-op, not an
  error. Codes to know: `0x8A150002` invalid args, `0x8A150014` no package found, `0x8A15002B` up to date.
- **winget writes its error text to stdout, not stderr.** So capture stdout and skip `2>&1` — redirecting a
  native command's stderr in PS 5.1 wraps each line in a `NativeCommandError` that throws under
  `$ErrorActionPreference = 'Stop'`.
- Pass `--disable-interactivity` from the GUI so winget can never sit waiting on a prompt nobody can see.

## PowerShell 5.1 gotchas (carry-over — these bit us)

- **`@(... | ConvertFrom-Json)` collapses a JSON array to ONE element.** When the JSON root is an array,
  `ConvertFrom-Json` emits it un-enumerated down the pipeline, so `@()` wraps the whole thing as a single
  `Object[]`. Assign first, then wrap: `$x = Get-Content … | ConvertFrom-Json; $arr = @($x)`. (Piping into
  `ForEach-Object` enumerates fine — that's why the `pws_commands` load worked but the registry load didn't.)

- **Same trap in reverse: `return ,$rows` from a function.** The comma keeps the array un-enumerated, so the
  caller's `@(...)` wraps the whole thing as ONE element — `Expand-HardwareNodes` silently returned 1 row for
  10. Return the array plainly and let callers wrap with `@()`.

- **Class methods can't see session/automatic variables.** Inside a `class` method, an unqualified
  `$PSVersionTable` / `$ErrorActionPreference` / any session variable is a **parse-time** failure —
  `Variable is not assigned in the method` — so the whole app dies at load, not at call time. Reach them
  through the global scope: `$global:PSVersionTable.PSVersion`. (`$env:...` and `$this` are fine.)

- **Scriptblocks created inside a class method don't capture that method's locals.** A WPF event handler
  wired up in a class method (`$btn.add_Click({ $myWindow.Close() })`) sees `$null`, and fails silently at
  click time — there is no load-time warning. Get what you need from the event args instead
  (`[System.Windows.Window]::GetWindow($s)`) or park it in a `$global:`.

- **`Window.Icon` is a WPF `ImageSource`, not a `System.Drawing.Icon`.** `ExtractAssociatedIcon` output
  won't cast — decode the `.ico` with `BitmapDecoder.Create(..., OnLoad)` (so the file isn't left locked),
  take the largest frame and `Freeze()` it. See `src/functions/startup/Load-XamlForm.ps1`.

- **`Window.Icon` alone does NOT fix the taskbar button.** Windows identifies the button by
  AppUserModelID, which defaults to the host process — so a WPF window hosted by `powershell.exe` gets
  PowerShell's icon in the taskbar and Alt-Tab no matter what the window icon says. `Main.ps1` calls
  `SetCurrentProcessExplicitAppUserModelID('Ief.WinTuner')` **before the first window exists**; after that
  the taskbar uses our own icon and groups only WinTuner windows. The desktop / Start Menu shortcuts are a
  third, separate thing — they target `powershell.exe`, so `install.ps1` sets `IconLocation` on both.

- **Ship a multi-size `.ico`.** `create-icon-v2.ps1` regenerates `wintuner.ico` with 16/24/32/48/64/128/256
  frames (each rendered at its own size, stored as PNG). A single 32×32 frame was smeared everywhere except
  the title bar. Note the PS 5.1 trap in that script: a function returning `[byte[]]` gets unrolled into an
  `Object[]`, which `BinaryWriter.Write()` mangles into a 1-byte write — cast back with `[byte[]](...)`.

### Search → Preset → Command tab pattern

The Local PS tab is the template for any future command-list tab. Three controls share a name stem
(`cmb_LocalPS` search TextBox, `cmb_LocalPS_Desc` ComboBox, `cmb_LocalPS_Command` editor). Flow:
`KeyUp` on search filters `$global:PwsCommandsFullList` into the dropdown → `DropDownOpened` repopulates →
`DropDownClosed` calls `Handle-PS-cmb` → `GUIHandler.Get_PS_Command_By_Description()` maps the display
string (`"[category]: description"`) back to the raw command. Enter in the editor runs; Shift+Enter = newline.

## Source project (reference only — do not edit)

`E:\Dev\DHL\DHL_DEVICE_MANAGER` is the donor codebase. Its active code lives under `Conf/`, and its own
`CLAUDE.md` documents the full architecture. When porting a feature:

1. Read the original in `DHL_DEVICE_MANAGER\Conf\src\...` to understand intent.
2. Strip remote/AD/API concerns (see scope boundary).
3. Reproduce it here following the conventions below.

Treat the source as **read-only**. Never modify files under `E:\Dev\DHL\DHL_DEVICE_MANAGER`.

## Target architecture (ported conventions)

### Bootstrap / loading chain

Note: the source nests everything under a `Conf/` wrapper (multi-hub network-share artifact). **Drop that
wrapper here** — `Main.ps1`, `ini.json`, and `src/` live at the repo root.

```
Main.ps1
 └─ reads ini.json (active profile → ConfigFiles/ConfigPath/LogPath/AppVersion)
 └─ dot-sources Config.ps1
     ├─ Add-Type for required .NET assemblies (System.Windows.Forms, PresentationFramework, …)
     ├─ Load-XamlForm.ps1            # parses the WPF XAML
     ├─ Import-Functions.ps1         # dynamic loader
     │   ├─ loads every *.ps1 in src/functions/ (root) except the loaders themselves
     │   └─ recursively loads src/functions/**/*.ps1, skipping ignored folders
     │      (backup, old, standalone, …)
     └─ Import-BarcodeAssemblies     # bundled lib/*.dll (ZXing.Net) - logs, never throws
 └─ instantiates $global:GUIHandler and calls .Launch_GUI()
```

`Import-Functions.ps1` is **exclusion-based**: it loads everything under `src/functions/` except a hardcoded
folder/file ignore-list. Adding a new function file usually means just dropping it in the right folder — but
if you add a folder that should *not* auto-load, add it to the ignore-list.

### Class-based handlers

Domain logic lives in handler classes under `src/functions/classes/`, each instantiated as a global at the
end of its file (e.g. `$global:PCHandler = [PC_Handler]::new()`). Method naming convention is `Verb_Noun`
(e.g. `Get_IPAddress`, `Remove_FilesInPath`). Prefer adding class methods over loose functions for new code.

Only port the locally-relevant handlers (e.g. PC/Storage/Printer/Network-for-localhost). **Drop** AD-Handler,
UAR-Handler, Installer-Handler (remote installs), and any async remote/file-sender machinery.

### GUI layer (WPF)

- XAML form under `src/gui/`.
- Event handlers split into `src/functions/gui/` (button actions, combobox actions, listener wiring).
- WPF control references are globals (e.g. `$cmb_LocalPS`). GUI-coupled code generally can't live inside a
  class cleanly — keep it in the `gui/` event files.
- User feedback goes through a single `Visual_Log(...)` method on the GUI handler — route all status output
  through it rather than `Write-Host`.

### GUI prefill data

Paired `.csv` / `.json` data files (loaded at startup) drive the dropdowns/REPL command lists
(`pws_commands`, `common_paths`, `registry_tweaks`, …). Port only the local-relevant data sets.

## WPF event gotchas (carry-over knowledge — these bit us before)

- `ComboBox` has no `add_Click` — use `add_PreviewMouseLeftButtonDown` to detect user clicks.
- For "type-to-filter then click-to-select" ComboBoxes: repopulate items in `add_DropDownOpened`
  (not `GotKeyboardFocus`, which re-fires after selection and clears `SelectedItem`).
- `Dispatcher.BeginInvoke` breaks PowerShell closure variable capture (`$var` goes out of scope before the
  UI thread runs). Use `Dispatcher.Invoke` (synchronous) when streaming output via `DataAdded` callbacks.
- In WPF event scriptblocks without `param($sender, $e)`, `$sender` is `$null` — reference controls by their
  explicit global variable name.
- Check a method exists without an instance: `[ClassName].GetMethods().Name -contains 'MethodName'`.
- **WPF brush names are a superset of `ConsoleColor`.** `Visual_Log` colours are brush names, so `'Orange'`
  paints the RichTextBox fine but `Write-Host -ForegroundColor Orange` throws — which used to kill the
  calling event handler whenever "Echo to console" was ticked. `GUI_Handler.To_ConsoleColor()` maps brush
  names onto real console colours (unknown → `Gray`). Likewise an unrecognised brush name makes
  `ApplyPropertyValue` throw "Token is not valid" — both paths are now caught. Logging must never be able
  to take down the caller.
- **`Register-WmiEvent`/`Register-ObjectEvent -Action` callbacks don't fire while the main thread is blocked
  in `Form.ShowDialog()`.** For any "watch for changes" feature, poll with a
  `System.Windows.Threading.DispatcherTimer` instead — its `Tick` runs on the UI thread during the modal
  loop, so grid/control updates are safe with no cross-thread marshalling (see the COM Ports tab).

## Running

Once `Main.ps1` exists, launch from the project root:

```powershell
.\Main.ps1
```

A dev startup test (validates the full load chain without showing the GUI) is worth porting from the source
(`DHL_DEVICE_MANAGER\Conf\src\dev\Test-DevStartup.ps1`) — it reports PASS/WARN/FAIL per load step.

### Installing vs. running from the repo

**The Start Menu / desktop shortcut does NOT run this repo.** It runs `%USERPROFILE%\WinTuner\Main.ps1`, a
separate copy that `install.ps1` unpacks. Pushing to `main` does not update it — re-run the installer, or
you will spend an afternoon wondering why your fix "did nothing".

```powershell
.\install.ps1           # download + install the published version from GitHub main
.\install.ps1 -Local    # install THIS working copy (uncommitted edits included)
```

`-Local` skips the network entirely and copies from `$PSScriptRoot`, excluding `.git`, `.gitignore`,
`.claude`, `.github` and `logs`. It refuses to run if source and destination resolve to the same folder.
Use it to test a change in the installed app before pushing. Both modes print the installed `AppVersion`
at the end, so a stale install is obvious.

**Both modes prune.** After copying, anything in the install directory that no longer exists in the source
is deleted, and each removal is printed. `Copy-Item` overwrites but never deletes, so before this a file
renamed or removed in the repo lingered forever — and a stale `.ps1` under `src/functions/` still gets
dot-sourced by `Import-Functions`, so orphans were not harmless.

- **`logs` is protected** and never pruned. It holds saved diagnostics and hardware reports, and it does
  not exist in the source, so without the exception every install would wipe it.
- The same exclusion list (`.git`, `.gitignore`, `.claude`, `.github`, `logs`) drives both the copy and the
  prune, so the two can't disagree about what belongs in an install.
- Pruning walks deepest-first so children are removed before their parents, and refuses to run at all if
  `Main.ps1` is missing after the copy — a guard against ever pointing it at the wrong folder.
- A failed prune warns but does not abort: an untidy install still works.

### Update check

`src/functions/Update-Functions.ps1` reads `AppVersion` from the published `ini.json`
(`IniFile.UpdateCheckUrl`) and compares it with the running version, reporting into the Activity log. It
only ever *reports* — updating stays a deliberate `install.ps1` run.

It runs in two places, both through the same `Start-UpdateCheck` / `Handle-UpdateCheck_Poll` pair:

- **At startup**, from `Launch_GUI` just before `ShowDialog`.
- **On demand**, via the **Check for updates** button in the header next to the version
  (`btn_CheckUpdates` → `Handle-btn_CheckUpdates`, wired in `Add_Click_listeners`). The button is disabled
  while a check is in flight and a second click is refused rather than queued.

- **Use the GitHub contents API, not `raw.githubusercontent.com`.** *Both* endpoints are cached, but by
  very different amounts — headers measured, not assumed:

  | Endpoint | `Cache-Control` | Stale window |
  |----------|-----------------|--------------|
  | `raw.githubusercontent.com` | `max-age=300` | 5 minutes |
  | `api.github.com/…/contents` | `max-age=60` | 1 minute |

  GitHub normalises the query string away on raw, so cache-busting does not work there either. **Neither is
  instant** — check within a minute of a release and you may still be told the previous version is current;
  a second check a moment later is right. Raw's five-minute window is the one that actually misleads: it
  tells someone who just updated that they are "ahead of published". The API costs a 60 requests/hour
  unauthenticated limit, unreachable for a once-per-launch check, and needs a `User-Agent` header or it 403s.
- `Get-RemoteAppVersion` parses **both** shapes — the API's base64 `.content` wrapper and a plain raw file —
  so an `ini.json` left over from an older install that still points at raw keeps working. Strip the UTF-8
  BOM from the decoded text first, or `ConvertFrom-Json` fails with a misleading "invalid JSON primitive".

- It is the **only outbound call in the app**, and it is about WinTuner itself, not PC management — the
  local-only scope boundary above still stands for every feature.
- Runs in a `Start-Job` + `DispatcherTimer`, so an unreachable network cannot delay the window. A failed
  check logs a grey "skipped" line and nothing else.
- **Bump `AppVersion` in `ini.json` on every release**, or the check can never fire.
- `Compare-AppVersion` compares components **numerically**, on purpose. `[version]` parses `'0.10.0'` as
  `0.10` → `0.1`, so it would rank `0.10.0` *older* than `0.3.0` and silently never offer the update.
  Missing components count as zero, which is also what keeps the legacy `x.xy` releases (`0.01`, `0.02`)
  ordering correctly against `x.y.z`. Non-numeric versions (`1.0-beta`) return `$null` = "can't compare".

### Versioning — `x.y.z`

| Part | Bump when | Who decides |
|------|-----------|-------------|
| `x` | Major release | **Ief only** — never bump this unless told to |
| `y` | A feature is added | Bump it as part of the feature commit |
| `z` | Bug fix or small improvement | Bump it as part of the fix commit |

`AppVersion` in `ini.json` is the single source of truth — the version display, the About window and the
update check all read it. Releases before `0.3.0` used a flat `x.xy` form (`0.01`, `0.02`);
`Compare-AppVersion` orders the two schemes against each other correctly, so installs still on `0.02`
detect `0.3.0` as an update.

## Conventions reminder

- **File encoding: save every `.ps1` as UTF-8 *with BOM*.** Windows PowerShell 5.1 reads UTF-8-without-BOM
  as Windows-1252, so any non-ASCII byte (em-dash, curly quote, accented char) corrupts the parse with
  misleading "string is missing the terminator" errors. The BOM makes 5.1 read UTF-8 correctly. (Editors/
  tools often write without a BOM — re-encode after creating a file.)
- PowerShell for all scripting (this is a PS project end to end).
- Wrap fallible calls in try/catch; surface failures via `Visual_Log`, don't swallow them.
- Validate user-supplied paths/input before acting on the filesystem or registry.
