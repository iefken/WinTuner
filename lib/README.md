# lib/ — bundled third-party assemblies

These DLLs ship with WinTuner and are loaded by `src/functions/Config.ps1` at startup.
They are committed on purpose: the app must work with no network access, so nothing here
may be fetched at install time or at run time.

## ZXing.Net 0.16.11

| | |
|---|---|
| Purpose | Local barcode/QR generation (Tools → QR Code) |
| Project | https://github.com/micjahn/ZXing.Net |
| Package | https://www.nuget.org/packages/ZXing.Net/0.16.11 |
| Licence | Apache-2.0 — full text in `ZXing.Net-LICENSE.txt` |
| Target | `lib/net45` (PowerShell 5.1 runs on .NET Framework 4.x) |

| File | Size | SHA-256 |
|------|------|---------|
| `zxing.dll` | 531,456 | `39C1DFEA722C9F9DE18F2E0959F4D7490610436632E5F9B76E0EFA1265B5B6A3` |
| `zxing.presentation.dll` | 19,968 | `B339D2F41421DD83CEDE4D46BC409240E4332F654E5727CDB3F9B05E6E95F7EA` |

`zxing.net.0.16.11.nupkg` SHA-256: `7D39234D668E558B3D374D18116ED57021D7C0DF482801F1E1DB4F1DB9314EC3`

`zxing.presentation.dll` is what lets `ZXing.Presentation.BarcodeWriter` hand back a WPF
`WriteableBitmap` directly. Without it the only renderer is the `System.Drawing` one, which
would mean a `Bitmap` → PNG → `BitmapImage` round-trip through a temp file on every keystroke.

### Replacing these files

1. Download the `.nupkg` from nuget.org and take `lib/net45/zxing.dll` and
   `lib/net45/zxing.presentation.dll` out of it.
2. `Unblock-File` both — files that arrive from the internet carry a mark-of-the-web
   alternate data stream, and `Add-Type -Path` refuses to load a blocked assembly.
   (`Import-BarcodeAssemblies` unblocks defensively too, since a repo ZIP downloaded by
   `install.ps1` marks every file it extracts.)
3. Update the table above — the hashes are the only record of what was actually shipped.
