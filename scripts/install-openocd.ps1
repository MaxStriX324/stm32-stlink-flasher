# Portable xPack OpenOCD download from pinned GitHub Release.
# SHA-256 is checked against the digest published by xPack.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
. (Join-Path $PSScriptRoot 'openocd.ps1')
$url='https://github.com/xpack-dev-tools/openocd-xpack/releases/download/v0.12.0-7/xpack-openocd-0.12.0-7-win32-x64.zip'
$expected='6BFD3C97135AAFEF8AFFC9AF1ACF34FD0E2B9CA26044506F6ABD7F95B7630052'
$tempFile=Join-Path $env:TEMP ('xpack-openocd-' + [guid]::NewGuid().ToString('N') + '.zip')
try {
  $existing=Find-OpenOcd
  if($existing){Write-Host "OpenOCD ready: $($existing.Exe)";exit 0}
  Write-Host "Downloading xPack OpenOCD: $url"
  [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
  Invoke-WebRequest -Uri $url -OutFile $tempFile -UseBasicParsing -MaximumRedirection 6 -TimeoutSec 120
  $actual=(Get-FileHash -LiteralPath $tempFile -Algorithm SHA256).Hash
  if($actual.ToUpperInvariant() -ne $expected){throw 'SHA-256 mismatch: archive not trusted.'}
  $destination=Join-Path $ProjectRoot 'tools\openocd'
  New-Item -ItemType Directory -Force -Path $destination | Out-Null
  Expand-Archive -LiteralPath $tempFile -DestinationPath $destination -Force
  $location=Find-OpenOcd
  if(-not $location){throw 'Downloaded archive is missing openocd.exe or target scripts.'}
  Write-Host "OpenOCD installed: $($location.Exe)" -ForegroundColor Green
  Write-Host 'If ST-Link is not detected, the official ST-Link USB driver may still be required.'
  exit 0
} catch {
  Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
  Write-Host 'Manual alternative: https://github.com/xpack-dev-tools/openocd-xpack/releases'
  Write-Host 'Extract Windows x64 ZIP under tools\openocd within this project.'
  exit 2
} finally {
  if(Test-Path -LiteralPath $tempFile){Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue}
}
