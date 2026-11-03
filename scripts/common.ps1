Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot

function Get-FlasherSettings {
  $path = Join-Path $ProjectRoot 'settings.json'
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'settings.json not found.' }
  Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Find-CubeCli {
  param([string]$ConfiguredPath = '')
  if (-not [string]::IsNullOrWhiteSpace($ConfiguredPath)) {
    $p = [Environment]::ExpandEnvironmentVariables($ConfiguredPath)
    if (Test-Path -LiteralPath $p -PathType Leaf) { return (Resolve-Path -LiteralPath $p).Path }
    throw "Configured cube_cli_path is missing: $p"
  }
  $cmd = Get-Command STM32_Programmer_CLI.exe -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  $bases = @($env:ProgramFiles, [Environment]::GetEnvironmentVariable('ProgramFiles(x86)'), $env:LOCALAPPDATA) | Where-Object { $_ }
  $relative = @(
    'STMicroelectronics\STM32Cube\STM32CubeProgrammer\bin\STM32_Programmer_CLI.exe',
    'STMicroelectronics\STM32CubeProgrammer\bin\STM32_Programmer_CLI.exe',
    'Programs\STMicroelectronics\STM32Cube\STM32CubeProgrammer\bin\STM32_Programmer_CLI.exe'
  )
  foreach ($base in $bases) {
    foreach ($rel in $relative) {
      $candidate = Join-Path $base $rel
      if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
  }
  return $null
}

function Get-ConnectionArgs {
  param($Settings)
  $freq = [int]$Settings.swd_frequency_khz
  if ($freq -lt 100 -or $freq -gt 24000) { throw 'swd_frequency_khz must be 100..24000.' }
  $result = @('-c','port=SWD',"freq=$freq")
  if ($Settings.connect_under_reset -eq $true) { $result += 'mode=UR' }
  if (-not [string]::IsNullOrWhiteSpace([string]$Settings.stlink_serial)) {
    $sn = [string]$Settings.stlink_serial
    if ($sn -notmatch '^[A-Za-z0-9_-]+$') { throw 'Invalid stlink_serial.' }
    $result += "sn=$sn"
  }
  return ,$result
}
