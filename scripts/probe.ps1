param([Parameter(Mandatory=$true)][ValidateSet('STM32F103','STM32F405')][string]$Target)
. (Join-Path $PSScriptRoot 'common.ps1')
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
try {
  $settings=Get-FlasherSettings
  $cli=Find-CubeCli ([string]$settings.cube_cli_path)
  if(-not $cli){throw 'STM32CubeProgrammer CLI not found. Run install.bat.'}
  $connection=Get-ConnectionArgs $settings
  Write-Host "Connecting: ST-Link / $Target"
  $info=& $cli @connection 2>&1 | Out-String
  $rc=$LASTEXITCODE
  Write-Host $info
  if($rc -ne 0 -or $info -match '(?im)^\s*(?:Error|Exception)\s*:'){
    throw "Connection failed (code $rc). Check SWD cable, target voltage and ST-Link."
  }
  $match=[regex]::Match($info,'(?im)^\s*(?:Device\s+ID|Chip\s+ID)\s*:\s*0x([0-9a-f]+)')
  if(-not $match.Success){throw 'Failed to read MCU Device ID; nothing was written.'}
  $id=[Convert]::ToInt32($match.Groups[1].Value,16)
  $allowed=if($Target -eq 'STM32F103'){@(0x410,0x412,0x414,0x430)}else{@(0x413)}
  if($id -notin $allowed){
    throw ('Wrong MCU: Device ID 0x{0:X3}, selected {1}. Nothing was written.' -f $id,$Target)
  }
  Write-Host ('SUCCESS: connected to {0}; Device ID 0x{1:X3}' -f $Target,$id)
  Write-Warning 'Device ID is shared by other variants; check the part marking / board type.'
  exit 0
} catch { Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red; exit 1 }
