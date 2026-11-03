# Windows PowerShell 5.1 syntax and regression check (does not connect to hardware).
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$total=0
$failures=0
Get-ChildItem -LiteralPath (Join-Path $root 'scripts') -Filter *.ps1 -File | ForEach-Object {
  $total++
  $tokens=$null
  $parseErrors=$null
  [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$tokens,[ref]$parseErrors)
  if($parseErrors.Count -gt 0) {
    $failures += $parseErrors.Count
    Write-Host "SYNTAX ERROR: $($_.Name)" -ForegroundColor Red
    $parseErrors | ForEach-Object { Write-Host ($_.ToString()) }
  } else { Write-Host "OK: $($_.Name)" }
}
$open=Get-Content -LiteralPath (Join-Path $root 'scripts\openocd.ps1') -Raw -Encoding UTF8
if($open -match '(?i)\$home\b') {
  Write-Host 'REGRESSION: reserved HOME variable was used.' -ForegroundColor Red
  $failures++
}
$gui=Get-Content -LiteralPath (Join-Path $root 'scripts\gui.ps1') -Raw -Encoding UTF8
if($gui -match '\$btnInstall\b|\$btnLogs\b') {
  Write-Host 'REGRESSION: obsolete GUI controls present.' -ForegroundColor Red
  $failures++
}
if($gui -notmatch 'ПРОВЕРИТЬ ПОДКЛЮЧЕНИЕ' -or $gui -notmatch 'ПРОШИТЬ С ПРОВЕРКОЙ'){
  Write-Host 'REGRESSION: main GUI buttons missing.' -ForegroundColor Red
  $failures++
}
$archive=Get-Content -LiteralPath (Join-Path $root 'scripts\install-openocd.ps1') -Raw -Encoding UTF8
if($archive -notmatch '6BFD3C97135AAFEF8AFFC9AF1ACF34FD0E2B9CA26044506F6ABD7F95B7630052'){
  Write-Host 'REGRESSION: pinned xPack SHA256 not found.' -ForegroundColor Red
  $failures++
}
# Offline IDCODE parser regression tests (no ST-Link required).
. (Join-Path $root 'scripts\openocd.ps1')
$f4=Parse-OpenOcdDeviceId "User : STM32_IDCODE=0x10016413"
$f1=Parse-OpenOcdDeviceId "STM32_IDCODE=0x20036410"
$untagged=Parse-OpenOcdDeviceId "Info : [stm32f4x.cpu] Cortex-M4 detected"
if(-not $f4 -or $f4.Target -ne 'STM32F405' -or $f4.DeviceId -ne 0x413){
  Write-Host 'REGRESSION: STM32F405 IDCODE parse failed.' -ForegroundColor Red
  $failures++
}
if(-not $f1 -or $f1.Target -ne 'STM32F103' -or $f1.DeviceId -ne 0x410){
  Write-Host 'REGRESSION: STM32F103 IDCODE parse failed.' -ForegroundColor Red
  $failures++
}
if($untagged){
  Write-Host 'REGRESSION: unsupported log recognized as MCU ID.' -ForegroundColor Red
  $failures++
}
$probeFile=Get-Content -LiteralPath (Join-Path $root 'scripts\openocd.ps1') -Raw -Encoding UTF8
if($probeFile -notmatch 'echo \[format \{STM32_IDCODE=' -or $probeFile -match 'mdw 0xE0042000 1'){
  Write-Host 'REGRESSION: probe does not use explicit read_memory echo.' -ForegroundColor Red
  $failures++
}
if($probeFile -notmatch 'RedirectStandardError' -or $probeFile -notmatch 'RedirectStandardOutput'){
  Write-Host 'REGRESSION: stderr/stdout redirection missing.' -ForegroundColor Red
  $failures++
}
if($failures -gt 0){
  Write-Host "FAIL: $failures issues in $total parsed PowerShell files." -ForegroundColor Red
  exit 1
}
Write-Host "PASS: $total PowerShell scripts parsed, invariants checked." -ForegroundColor Green
exit 0
