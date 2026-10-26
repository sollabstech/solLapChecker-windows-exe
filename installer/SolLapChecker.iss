; SolLapChecker installer (Inno Setup 6.3 or later)
;
; Build with:  .\installer\build.ps1      (builds the app first, then runs ISCC)
; or directly: ISCC.exe /DAppVersion=1.0.0 installer\SolLapChecker.iss
;
; Everything the installer ships comes from the Flutter release folder, which
; the CMake install step fills with the app, its plugins, and the contents of
; ..\tools (smartctl.exe, SolHelper.exe, optionally PawnIO_setup.exe).

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

#define AppName       "SolLapChecker"
#define AppPublisher  "Sollabs Tech"
#define AppUrl        "https://www.sollabstech.com"
#define AppExe        "SolLapChecker.exe"
#define BuildDir      "..\build\windows\x64\runner\Release"
#define ToolsDir      BuildDir + "\tools"

; ---- Fail the build early, with a clear message, if something is missing ----
#if !FileExists(AddBackslash(SourcePath) + BuildDir + "\" + AppExe)
  #error "SolLapChecker.exe not found in the Flutter release folder. Run: flutter build windows --release"
#endif
#if !FileExists(AddBackslash(SourcePath) + ToolsDir + "\smartctl.exe")
  #error "tools\smartctl.exe is missing. See tools\README.md, then rebuild so it is copied next to the app."
#endif
#if !FileExists(AddBackslash(SourcePath) + ToolsDir + "\SolHelper.exe")
  #error "tools\SolHelper.exe is missing. Run helper\build.ps1, then rebuild."
#endif
#if !FileExists(AddBackslash(SourcePath) + "redist\vcruntime140.dll")
  #error "installer\redist is missing the Visual C++ runtime DLLs. Run installer\build.ps1, which copies them."
#endif
#if !FileExists(AddBackslash(SourcePath) + "licenses\smartmontools-COPYING.txt")
  #error "installer\licenses\smartmontools-COPYING.txt is missing. smartmontools is GPL: its license text must ship with smartctl.exe."
#endif

[Setup]
; Stable identity: lets a newer installer upgrade an existing install in place.
AppId={{431863D4-F7F9-4534-B9C3-464A029098FF}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppUrl}
AppSupportURL={#AppUrl}
AppUpdatesURL={#AppUrl}
VersionInfoVersion={#AppVersion}
VersionInfoCompany={#AppPublisher}
VersionInfoProductName={#AppName}
VersionInfoDescription={#AppName} Setup

DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
UninstallDisplayName={#AppName}
UninstallDisplayIcon={app}\{#AppExe}

; The app itself requires administrator (SMART data and sensor access), and
; installing under Program Files needs it too.
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0

OutputDir=output
OutputBaseFilename=SolLapChecker_Setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
SetupLogging=yes
CloseApplications=yes
RestartApplications=no

; Unsigned installers trigger Windows SmartScreen. To sign, configure a SignTool
; in the Inno IDE (or pass /S to ISCC) and uncomment:
; SignTool=signtool
; SignedUninstaller=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[InstallDelete]
; On upgrade, drop the previous Flutter assets so no stale files linger.
Type: filesandordirs; Name: "{app}\data"

[Files]
; The Flutter app, its plugin DLLs, and tools\ (smartctl.exe, SolHelper.exe, ...).
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; Visual C++ runtime, deployed next to the exe so a clean Windows needs no separate redistributable.
Source: "redist\*.dll"; DestDir: "{app}"; Flags: ignoreversion
; Licence texts (smartmontools is GPL; others require attribution).
Source: "licenses\*"; DestDir: "{app}\licenses"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
; The exe carries the SolLapChecker logo icon (windows\runner\resources\app_icon.ico).
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"; Comment: "Laptop health check"
Name: "{autoprograms}\Uninstall {#AppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Comment: "Laptop health check"; Tasks: desktopicon

[Run]
; PawnIO is the sensor driver LibreHardwareMonitor needs for CPU temperatures. It is
; offered, with its own installer window, only if its setup was placed in tools\.
#if FileExists(AddBackslash(SourcePath) + ToolsDir + "\PawnIO_setup.exe")
Filename: "{app}\tools\PawnIO_setup.exe"; Description: "Install the PawnIO sensor driver (needed for CPU temperatures)"; Flags: postinstall skipifsilent runascurrentuser
#endif
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent shellexec

[UninstallDelete]
; Only the program folder is removed. Reports in Documents\SolLapChecker\Reports are the
; user's data and are deliberately left in place.
Type: filesandordirs; Name: "{app}"
