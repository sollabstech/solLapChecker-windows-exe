<#
.SYNOPSIS
  Builds SolHelper.exe (self-contained, single file) and copies it to ..\tools.

.EXAMPLE
  .\helper\build.ps1
#>
$ErrorActionPreference = 'Stop'

$root    = Split-Path -Parent $PSScriptRoot
$project = Join-Path $PSScriptRoot 'SolHelper\SolHelper.csproj'
$out     = Join-Path $PSScriptRoot 'publish'
$tools   = Join-Path $root 'tools'

dotnet publish $project -c Release -o $out
if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed ($LASTEXITCODE)" }

New-Item -ItemType Directory -Force -Path $tools | Out-Null
Copy-Item (Join-Path $out 'SolHelper.exe') (Join-Path $tools 'SolHelper.exe') -Force
Write-Host "SolHelper.exe -> $tools"
