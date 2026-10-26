#!/usr/bin/env bash
# Cross-builds SolHelper.exe (win-x64) on macOS/Linux and copies it to ../tools.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
out="$here/publish"
tools="$here/../tools"

dotnet publish "$here/SolHelper/SolHelper.csproj" -c Release -o "$out"
mkdir -p "$tools"
cp "$out/SolHelper.exe" "$tools/SolHelper.exe"
echo "SolHelper.exe -> $tools"
