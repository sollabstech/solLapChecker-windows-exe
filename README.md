# SolLapChecker (Windows desktop)

Laptop diagnostic and health-check tool by Sollabs Tech. Flutter + GetX UI,
C# helper (`SolHelper.exe`) and bundled `smartctl.exe` for hardware tasks.
Runs fully offline and requires Administrator (set in `windows/runner/runner.exe.manifest`).

## Build (on Windows)

```powershell
flutter pub get
flutter run -d windows          # dev
flutter build windows --release # -> build\windows\x64\runner\Release\SolLapChecker.exe
```

## Layout

- `lib/app` - theme and the module registry (sidebar entries, test order)
- `lib/controllers` - app-wide state (selected screen, test statuses, guided wizard)
- `lib/core` - models, services (PowerShell/WMI) and utilities
- `lib/modules/<name>` - one folder per screen
- `lib/widgets` - shared UI (title bar, sidebar, glass card, progress ring...)
- `windows/` - runner (admin manifest, icon, version info)
- `lib/core/report` - report model, scoring, builder, PDF generator and the on-disk repository
- `lib/core/input` - Raw Input over `dart:ffi` (hidden message-only window, device classification, packet parser)
- `helper/SolHelper` (Phase 3) and `tools/smartctl.exe` (Phase 2)

## Build phases

1. Project setup, UI shell, sidebar, dashboard / system info  **(done)**
2. Battery + SSD health  **(done; needs `tools/smartctl.exe`, see `tools/README.md`)**
3. SolHelper.exe: CPU/GPU stress + temperatures  **(done; build with `helper/build.ps1`, needs the PawnIO driver, see `helper/README.md`)**
4. Keyboard + touchpad (Raw Input)  **(done; see `lib/core/input`)**
5. Webcam, speaker, mic, display  **(done)**
6. PDF report + history  **(done; reports are saved to `Documents\SolLapChecker\Reports`)**
7. Inno Setup installer  **(done; build with `installer\build.ps1`, see `installer/README.md`)**
