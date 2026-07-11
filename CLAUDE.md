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

Bootstrap + shared infra + first features are in place and pass `Test-DevStartup.ps1` (87/87):

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

Remaining phases (repo comparer, storage rewrite) follow the proven donor layout — build into this shape
unless we explicitly decide to diverge.

Notes:
- `Get-FileEncoding` is a **ground-up rewrite** (BOM byte inspection), not a port — the donor's version was
  a no-op that always returned "UTF8".
- `registry_tweaks.json` schema is a **redesign** of the donor's flat `key/val/key1..key4` CSV into clean
  per-tweak `entries[]` (`name`/`type`/`value`).

## PowerShell 5.1 gotchas (carry-over — these bit us)

- **`@(... | ConvertFrom-Json)` collapses a JSON array to ONE element.** When the JSON root is an array,
  `ConvertFrom-Json` emits it un-enumerated down the pipeline, so `@()` wraps the whole thing as a single
  `Object[]`. Assign first, then wrap: `$x = Get-Content … | ConvertFrom-Json; $arr = @($x)`. (Piping into
  `ForEach-Object` enumerates fine — that's why the `pws_commands` load worked but the registry load didn't.)

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
     └─ Import-Functions.ps1         # dynamic loader
         ├─ loads every *.ps1 in src/functions/ (root) except the loaders themselves
         └─ recursively loads src/functions/**/*.ps1, skipping ignored folders
            (backup, old, standalone, …)
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

## Conventions reminder

- **File encoding: save every `.ps1` as UTF-8 *with BOM*.** Windows PowerShell 5.1 reads UTF-8-without-BOM
  as Windows-1252, so any non-ASCII byte (em-dash, curly quote, accented char) corrupts the parse with
  misleading "string is missing the terminator" errors. The BOM makes 5.1 read UTF-8 correctly. (Editors/
  tools often write without a BOM — re-encode after creating a file.)
- PowerShell for all scripting (this is a PS project end to end).
- Wrap fallible calls in try/catch; surface failures via `Visual_Log`, don't swallow them.
- Validate user-supplied paths/input before acting on the filesystem or registry.
