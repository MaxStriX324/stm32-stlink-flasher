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
if($failures -gt 0){
  Write-Host "FAIL: $failures issues in $total parsed PowerShell files." -ForegroundColor Red
  exit 1
}
Write-Host "PASS: $total PowerShell scripts parsed, invariants checked." -ForegroundColor Green
exit 0
