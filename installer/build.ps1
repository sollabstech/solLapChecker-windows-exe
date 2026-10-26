<#
.SYNOPSIS
  Builds SolLapChecker_Setup.exe from scratch: Flutter release build, SolHelper.exe,
  the Visual C++ runtime DLLs, then the Inno Setup compiler.

.PARAMETER SkipFlutter   Reuse the existing build\windows release folder.
.PARAMETER SkipHelper    Reuse the existing tools\SolHelper.exe.

.NOTES
  Needs on the build PC: Flutter (Windows desktop enabled), Visual Studio C++ tools,
  .NET 8 SDK, Inno Setup 6.3+, and tools\smartctl.exe (see tools\README.md).

.EXAMPLE
  .\installer\build.ps1
#>
param(
  [switch]$SkipFlutter,
  [switch]$SkipHelper
)

$ErrorActionPreference = 'Stop'

$here  = $PSScriptRoot
$root  = Split-Path -Parent $here
$tools = Join-Path $root 'tools'
$redist = Join-Path $here 'redist'

function Step($text) { Write-Host "`n==> $text" -ForegroundColor Cyan }

# --- version from pubspec.yaml (1.0.0+1 -> 1.0.0) ---------------------------------
$pubspec = Get-Content (Join-Path $root 'pubspec.yaml') -Raw
if ($pubspec -notmatch '(?m)^version:\s*(\d+\.\d+\.\d+)') { throw 'Could not read the version from pubspec.yaml' }
$version = $Matches[1]
Write-Host "SolLapChecker $version"

# --- required inputs that are not built here ----------------------------------------
Step 'Checking inputs'
if (-not (Test-Path (Join-Path $tools 'smartctl.exe'))) {
  throw "tools\smartctl.exe is missing. See tools\README.md for how to add it."
}
if (-not (Test-Path (Join-Path $here 'licenses\smartmontools-COPYING.txt'))) {
  throw "installer\licenses\smartmontools-COPYING.txt is missing (smartmontools is GPL; ship its COPYING file)."
}

# --- SolHelper.exe ---------------------------------------------------------------------
if (-not $SkipHelper) {
  Step 'Building SolHelper.exe'
  & (Join-Path $root 'helper\build.ps1')
  if ($LASTEXITCODE -ne 0) { throw 'helper build failed' }
}
if (-not (Test-Path (Join-Path $tools 'SolHelper.exe'))) { throw 'tools\SolHelper.exe is missing.' }

# --- Flutter release build ---------------------------------------------------------------
if (-not $SkipFlutter) {
  Step 'Building the Flutter app (release)'
  Push-Location $root
  try {
    flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed' }
    flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw 'flutter build failed' }
  } finally { Pop-Location }
}
$release = Join-Path $root 'build\windows\x64\runner\Release'
if (-not (Test-Path (Join-Path $release 'SolLapChecker.exe'))) { throw "No release build found at $release" }
# The CMake install step copies ..\tools next to the exe; confirm it did.
foreach ($f in 'smartctl.exe', 'SolHelper.exe') {
  if (-not (Test-Path (Join-Path $release "tools\$f"))) {
    throw "tools\$f was not copied into the release folder. Rebuild without -SkipFlutter."
  }
}

# --- Visual C++ runtime (app-local deployment) ------------------------------------------
Step 'Staging the Visual C++ runtime DLLs'
New-Item -ItemType Directory -Force -Path $redist | Out-Null
$system32 = Join-Path $env:SystemRoot 'System32'
foreach ($dll in 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll') {
  $src = Join-Path $system32 $dll
  if (-not (Test-Path $src)) { throw "$dll not found in System32. Install the Visual C++ 2015-2022 x64 redistributable on this PC." }
  Copy-Item $src $redist -Force
}
# Some plugins need these too; copy them when present.
foreach ($dll in 'msvcp140_1.dll', 'msvcp140_2.dll') {
  $src = Join-Path $system32 $dll
  if (Test-Path $src) { Copy-Item $src $redist -Force }
}

# --- Inno Setup ---------------------------------------------------------------------------
Step 'Compiling the installer'
$iscc = @(
  (Get-Command ISCC.exe -ErrorAction SilentlyContinue).Source,
  "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
  "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
  "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $iscc) { throw 'Inno Setup 6 (ISCC.exe) was not found. Install it from https://jrsoftware.org/isinfo.php' }

& $iscc "/DAppVersion=$version" (Join-Path $here 'SolLapChecker.iss')
if ($LASTEXITCODE -ne 0) { throw "ISCC failed ($LASTEXITCODE)" }

$setup = Join-Path $here 'output\SolLapChecker_Setup.exe'
$size = [math]::Round((Get-Item $setup).Length / 1MB, 1)
$hash = (Get-FileHash $setup -Algorithm SHA256).Hash
Write-Host "`nDone: $setup ($size MB)" -ForegroundColor Green
Write-Host "SHA-256: $hash"
