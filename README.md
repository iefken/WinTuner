# WinTuner

A comprehensive PowerShell + WPF GUI utility for local PC management and maintenance tasks. Streamline file cleanup, registry tweaks, Windows updates, application installation, network diagnostics, and system optimization—all through an intuitive interface.

![Windows](https://img.shields.io/badge/OS-Windows-blue?style=for-the-badge)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue?style=for-the-badge)
![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)

---

## Features

### 🖥️ Local PowerShell REPL
- **42 preset commands** organized by category (Info, Network, Hardware, Files, System, Actions)
- Search, select, and execute common administrative commands
- Commands run in-process with `$global:` variable persistence
- Categories include:
  - **User Info**: Active users, mapped drives, Group Policy
  - **Network**: Traceroute, DNS lookup, IP config, Wi-Fi signal, ARP cache
  - **Hardware**: PnP devices, printers, BIOS, USB devices
  - **Files**: File search, startup items, disk space
  - **System**: Last reboot, OS version, process management
  - **Actions**: Force GP update, software uninstall, network reset, DNS flush

### 🧹 File Cleanup
- Scan and clean directories with configurable filters
- Preview files in a grid before deletion
- Recursive search with name pattern matching
- Safe deletion to Recycle Bin by default
- Identifies processes holding locked files

### ⚙️ Registry Tweaks
- **18 pre-configured registry optimizations** with descriptions
- View current values before applying changes
- Admin privilege detection and warnings
- Tweaks include:
  - **Privacy**: Disable telemetry, location tracking, advertising ID, Cortana
  - **Performance**: Disable Delivery Optimization, Game DVR
  - **UI**: Show file extensions, hidden files, disable taskbar search/widgets
  - **Network**: NCSI active probing, passive poll period
  - **System**: NumLock at logon, fast user switching, default terminal

### 🔌 COM Port Monitor
- Real-time monitoring of serial/COM device connections
- Automatic detection of device connect/disconnect events
- Logs device state changes (PRESENT/ADDED/REMOVED)
- 2-second polling interval via DispatcherTimer

### 🌐 Network Diagnostics
- Run network checks (ipconfig, nslookup, ping, tracert)
- Background job execution for responsive UI
- Real-time output streaming to console
- Save diagnostic results to timestamped log files

### 📦 Application Management
- **25+ curated applications** ready for installation via WinGet
- Categories: Browsers, Development, Multimedia, Utilities, Games, Communication
- One-click installation with progress feedback
- Popular apps: Chrome, Firefox, VS Code, Python, VLC, Steam, Discord

### 🛠️ System Fixes & Optimization
- Windows Update management and troubleshooting
- Performance plan configuration
- Windows Features enable/disable
- DNS configuration and flushing
- Common system issue resolutions

---

## Quick Start

> **WinTuner must be run as Administrator** for system-wide changes (registry tweaks, Windows updates, etc.).

### Windows Installation

Open PowerShell or Terminal as Administrator, then run:

```powershell
irm https://raw.githubusercontent.com/iefken/WinTuner/main/install.ps1 | iex
```

Or download and run manually:

```powershell
# Clone the repository
git clone https://github.com/iefken/WinTuner.git
cd WinTuner

# Run the application
.\Main.ps1
```

### Linux Installation (via PowerShell)

```powershell
# Install PowerShell core if not already installed
# Ubuntu/Debian:
wget https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb
sudo dpkg -i packages-microsoft-prod.deb
sudo apt-get update
sudo apt-get install -y powershell

# Run WinTuner (limited functionality on Linux)
pwsh -c "irm https://raw.githubusercontent.com/iefken/WinTuner/main/install.ps1 | iex"
```

> **Note**: Linux support is limited—Windows-specific features (registry, COM ports, Windows Updates) are unavailable.

### How to open an admin terminal

- **Start menu**: Right-click Start → *Windows PowerShell (Admin)* or *Terminal (Admin)*
- **Search**: Press `Windows key`, type `PowerShell` or `Terminal`, then `Ctrl + Shift + Enter`

---

## Requirements

- **OS**: Windows 10/11 (recommended), Windows 8.1 (limited support)
- **PowerShell**: 5.1 or later (PowerShell Core 6+ for Linux)
- **.NET Framework**: 4.5+ (included with Windows)
- **Admin Rights**: Required for registry tweaks, Windows updates, and system changes
- **WinGet**: Required for application installation (included in Windows 11, available for Windows 10)

---

## Usage

### Launching the Application

```powershell
.\Main.ps1
```

The GUI will launch with the following tabs:

1. **Home** - Activity log and general information
2. **Local PS** - PowerShell command REPL with presets
3. **File Cleanup** - Directory scanning and file deletion
4. **Registry** - Registry tweaks and optimizations
5. **COM Ports** - Serial device monitoring
6. **Diagnostics** - Network diagnostic tools
7. **Applications** - WinGet application installation
8. **System Fixes** - Windows update and system repair tools

### Common Workflows

#### Clean up temporary files
1. Navigate to **File Cleanup** tab
2. Select a directory (e.g., `C:\Windows\Temp`)
3. Optionally add a name filter
4. Click **Preview** to see files
5. Review and click **Delete** to clean

#### Apply registry tweaks
1. Navigate to **Registry** tab
2. Select a tweak from the dropdown
3. Review current values
4. Edit new values if needed
5. Click **Apply** (admin required for HKLM/HKU)

#### Install applications
1. Navigate to **Applications** tab
2. Browse or search for applications
3. Select desired apps
4. Click **Install** to run WinGet

#### Run network diagnostics
1. Navigate to **Diagnostics** tab
2. Enter target host/IP (optional)
3. Select diagnostics to run
4. Click **Run** to execute
5. View real-time output in console
6. Click **Save** to export results

---

## Configuration

Edit `ini.json` to customize:

```json
{
  "ActiveProfile": "Default",
  "ConfigFiles": {
    "ConfigPath": "./src/gui/form_prefills",
    "LogPath": "./logs"
  },
  "AppVersion": "1.0.0"
}
```

### Prefill Data Locations

- **PowerShell commands**: `src/gui/form_prefills/pws_commands.json`
- **Registry tweaks**: `src/gui/form_prefills/registry_tweaks.json`
- **Applications**: `src/gui/form_prefills/applications.json`
- **Common paths**: `src/gui/form_prefills/common_paths.csv`

---

## Development

### Project Structure

```
WinTuner/
├── Main.ps1                    # Application entry point
├── ini.json                    # Configuration file
├── src/
│   ├── functions/              # Core functionality
│   │   ├── classes/            # Handler classes
│   │   ├── gui/                # GUI event handlers
│   │   ├── startup/            # Bootstrap scripts
│   │   ├── Config.ps1          # Configuration loader
│   │   ├── Import-Functions.ps1 # Dynamic function loader
│   │   ├── File-Functions.ps1  # File operations
│   │   ├── COM-Functions.ps1   # COM port monitoring
│   │   ├── DNS-Functions.ps1   # DNS utilities
│   │   ├── WinGet-Functions.ps1 # App installation
│   │   ├── WindowsUpdate-Functions.ps1
│   │   └── ...
│   └── gui/
│       ├── FormUIv3.xaml       # WPF form definition
│       └── form_prefills/      # JSON/CSV data files
├── logs/                       # Application logs
└── CLAUDE.md                   # Development guidelines
```

### Adding New Features

1. **Add function file** to `src/functions/` (auto-loaded by `Import-Functions.ps1`)
2. **Create handler class** in `src/functions/classes/` if needed
3. **Add GUI controls** to `src/gui/FormUIv3.xaml`
4. **Wire event handlers** in `src/functions/gui/`
5. **Add prefill data** to `src/gui/form_prefills/` if applicable

### File Encoding

**Critical**: Save all `.ps1` files as **UTF-8 with BOM**. Windows PowerShell 5.1 reads UTF-8 without BOM as Windows-1252, causing parse errors with non-ASCII characters.

### Testing

Run the dev startup test:

```powershell
.\src\dev\Test-DevStartup.ps1
```

This validates the full load chain without launching the GUI.

---

## Version History

### v1.0.0 (Current)
- **Initial release**
- Local PowerShell REPL with 42 preset commands
- File Cleanup with preview and safe deletion
- Registry Tweaks with 18 optimizations
- COM Port monitoring with real-time detection
- Network Diagnostics with background job execution
- Application Management via WinGet (25+ apps)
- System Fixes and Windows Update management
- WPF GUI with tabbed interface
- Comprehensive logging and error handling

---

## Troubleshooting

### "String is missing the terminator" error
- **Cause**: File saved as UTF-8 without BOM
- **Fix**: Re-save the file as UTF-8 with BOM in your editor

### Registry Apply button disabled
- **Cause**: Not running as Administrator
- **Fix**: Right-click `Main.ps1` → "Run as Administrator"

### WinGet commands not working
- **Cause**: WinGet not installed or outdated
- **Fix**: Run `winget --upgrade` or install from Microsoft Store

### COM Ports tab not detecting devices
- **Cause**: No serial devices connected or insufficient permissions
- **Fix**: Connect a COM device and run as Administrator

---

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Follow the coding conventions in `CLAUDE.md`
4. Test with `Test-DevStartup.ps1`
5. Submit a pull request

---

## License

This project is licensed under the MIT License.

---

## Acknowledgments

Inspired by [ChrisTitusTech/winutil](https://github.com/ChrisTitusTech/winutil) - a comprehensive Windows utility tool.
