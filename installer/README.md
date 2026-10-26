# SolLapChecker installer

Produces `installer\output\SolLapChecker_Setup.exe` with Inno Setup.

## Build

On a Windows PC with Flutter (Windows desktop enabled), Visual Studio C++ tools, the
.NET 8 SDK and [Inno Setup 6.3+](https://jrsoftware.org/isinfo.php):

```powershell
.\installer\build.ps1
```

It reads the version from `pubspec.yaml`, builds `SolHelper.exe`, builds the Flutter
release, stages the Visual C++ runtime DLLs in `installer\redist`, and runs `ISCC`.
Use `-SkipFlutter` / `-SkipHelper` to reuse earlier builds.

**Before the first build** put these in place (the script stops with a clear message if not):

| File | Where | Notes |
|---|---|---|
| `smartctl.exe` | `tools\` | see `tools\README.md` |
| `smartmontools-COPYING.txt` | `installer\licenses\` | a GPL v2 text is included; replace it with the `COPYING` file from the smartmontools download you use |
| `PawnIO_setup.exe` *(optional)* | `tools\` | the CPU-temperature sensor driver; if present the installer offers to run it |

## What gets installed

- `C:\Program Files\SolLapChecker\` : `SolLapChecker.exe`, the Flutter runtime and plugin
  DLLs, `data\`, the Visual C++ runtime DLLs, `tools\smartctl.exe`, `tools\SolHelper.exe`
  and `licenses\`.
- A **Start Menu** shortcut, and an optional **Desktop** shortcut (a checkbox, on by default).
  Both use the SolLapChecker logo icon, which is built into the exe from
  `windows\runner\resources\app_icon.ico` (generated from `assets\logo.png`).
- The app asks for administrator rights each time it starts (SMART and sensor access).
  The installer also needs administrator rights.

## Uninstall and upgrades

- A newer installer upgrades in place (the `AppId` stays the same) and clears the old `data\` folder first.
- Uninstalling removes the program folder only. **Reports in
  `Documents\SolLapChecker\Reports` are kept.**

## Things to know

- **SmartScreen:** an unsigned installer shows "Windows protected your PC". Sign it with a
  code-signing certificate (see the `SignTool` note in the `.iss`) to avoid the warning.
- **PawnIO:** without it, CPU/GPU stress tests refuse to run on most laptops (no temperature
  sensor). If `PawnIO_setup.exe` is bundled, its own installer window opens at the end of setup.
- **Licences:** `licenses\THIRD_PARTY_NOTICES.txt` lists what is bundled. smartmontools is
  GPL: keep its licence text with `smartctl.exe` and offer its source (https://www.smartmontools.org/).
- **Testing:** install on a clean Windows 10/11 VM (no Visual Studio, no .NET) to confirm the
  app and `SolHelper.exe` start without extra downloads.
