# tools/

`smartctl.exe` (from [smartmontools](https://www.smartmontools.org/)) must be placed here
for the Storage test to read SMART data. It is **not** committed to this repo.

1. Download the Windows installer from <https://www.smartmontools.org/wiki/Download>
   (e.g. `smartmontools-7.x-1.win32-setup.exe`) and verify its checksum/signature
   against the values published there.
2. Extract it with 7-Zip (right-click -> 7-Zip -> Extract) - do not run the installer.
3. Copy `smartctl.exe` from the extracted `bin` folder into this folder (use the 64-bit
   build if the archive has both).
4. Keep `COPYING` from the archive next to it: smartmontools is GPL v2, and the
   installer must ship its license text.

The CMake install step copies this folder next to `SolLapChecker.exe`
(`<app>\tools\smartctl.exe`) on every `flutter run` / `flutter build windows`.

## SolHelper.exe

`SolHelper.exe` (CPU/GPU stress tests) is built from `helper/SolHelper`; run
`helper\build.ps1` (or `helper/build.sh`) and it is copied here.

## PawnIO_setup.exe (optional, for CPU temperatures)

`SolHelper.exe` reads CPU sensors through the PawnIO driver. If you place PawnIO's own
installer here as `PawnIO_setup.exe`, the SolLapChecker installer bundles it and offers to
run it at the end of setup. Download it only from the project's official site and check its
signature. Without it the CPU/GPU stress tests refuse to run on most laptops.

## Licences

`smartctl.exe` is GPL: `installer\licenses\smartmontools-COPYING.txt` must ship with it
(see `installer\README.md`).
