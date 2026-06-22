#Requires -Version 5
#
# Build a versioned Windows release for QuickVPN.
#
# Produces a branded installer (build\quickvpn-v<version>-windows-x64-setup.exe)
# when Inno Setup (iscc.exe) is available, otherwise a .zip of the Release
# folder. The installer's icon and the app's icon are the QuickVPN logo.
#
# Run this ON Windows — Flutter cannot cross-compile desktop targets.
#
# Usage:  powershell -ExecutionPolicy Bypass -File scripts\make_win.ps1

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

# Version name from pubspec.yaml (strip the +build suffix).
$verLine = (Select-String -Path 'pubspec.yaml' -Pattern '^version:\s*(.+)$').Matches[0].Groups[1].Value
$Version = ($verLine -split '\+')[0].Trim()
Write-Host "==> QuickVPN version $Version"

Write-Host "==> flutter build windows --release"
& flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw "flutter build windows failed" }

$ReleaseDir = Get-ChildItem -Path 'build\windows' -Recurse -Directory -Filter 'Release' |
  Where-Object { Test-Path (Join-Path $_.FullName 'quickvpn.exe') } |
  Select-Object -First 1 -ExpandProperty FullName
if (-not $ReleaseDir) { throw "Release build (quickvpn.exe) not found under build\windows" }

$iscc = Get-Command iscc.exe -ErrorAction SilentlyContinue
if ($iscc) {
  Write-Host "==> Building installer with Inno Setup"
  & $iscc.Source "/DAppVersion=$Version" "/DReleaseDir=$ReleaseDir" "/DRepoRoot=$Root" `
    'windows\installer\quickvpn.iss'
  if ($LASTEXITCODE -ne 0) { throw "iscc failed" }
  Write-Host "==> Built: build\quickvpn-v$Version-windows-x64-setup.exe"
}
else {
  Write-Warning "Inno Setup (iscc.exe) not found - producing a .zip instead."
  Write-Warning "For a branded installer, install Inno Setup: https://jrsoftware.org/isdl.php"
  $zip = "build\quickvpn-v$Version-windows-x64.zip"
  if (Test-Path $zip) { Remove-Item $zip -Force }
  Compress-Archive -Path (Join-Path $ReleaseDir '*') -DestinationPath $zip
  Write-Host "==> Built: $zip"
}
