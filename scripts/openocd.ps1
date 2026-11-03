Set-StrictMode -Version Latest

function Find-OpenOcd {
  $candidates=New-Object System.Collections.Generic.List[string]
  $settings=Get-FlasherSettings
  if($settings.PSObject.Properties.Name -contains 'openocd_path'){
    $custom=[string]$settings.openocd_path
    if($custom){$candidates.Add([Environment]::ExpandEnvironmentVariables($custom))}
  }
  $cmd=Get-Command openocd.exe -ErrorAction SilentlyContinue
  if($cmd){$candidates.Add($cmd.Source)}
  $home=if($env:PLATFORMIO_CORE_DIR){$env:PLATFORMIO_CORE_DIR}else{Join-Path $env:USERPROFILE '.platformio'}
  foreach($name in @('tool-openocd','tool-openocd-stm32')){
    $candidates.Add((Join-Path $home ("packages\" + $name + "\bin\openocd.exe")))
  }
  $portable=Join-Path $ProjectRoot 'tools\openocd'
  if(Test-Path -LiteralPath $portable){
    Get-ChildItem -LiteralPath $portable -Recurse -File -Filter openocd.exe -ErrorAction SilentlyContinue |
      ForEach-Object {$candidates.Add($_.FullName)}
  }
  foreach($exe in $candidates){
    if(-not (Test-Path -LiteralPath $exe -PathType Leaf)){continue}
    $resolved=(Resolve-Path -LiteralPath $exe).Path
    $root=Split-Path -Parent (Split-Path -Parent $resolved)
    foreach($scripts in @((Join-Path $root 'scripts'),(Join-Path $root 'openocd\scripts'),(Join-Path $root 'share\openocd\scripts'))){
      if((Test-Path -LiteralPath (Join-Path $scripts 'interface\stlink.cfg')) -and
        (Test-Path -LiteralPath (Join-Path $scripts 'target\stm32f1x.cfg')) -and
        (Test-Path -LiteralPath (Join-Path $scripts 'target\stm32f4x.cfg'))){
        return [pscustomobject]@{Exe=$resolved;Scripts=$scripts}
      }
    }
  }
  return $null
}

function Invoke-OpenOcd {
  param($Location,[string[]]$Arguments)
  $old=$ErrorActionPreference
  $ErrorActionPreference='Continue'
  try {
    $out=(& $Location.Exe @Arguments 2>&1 | Out-String)
    $rc=$LASTEXITCODE
  } finally {$ErrorActionPreference=$old}
  return [pscustomobject]@{Output=$out;ExitCode=$rc}
}

function OpenOcd-Args {
  param($Location,[string]$Target,$Settings,[string]$Command)
  $freq=[int]$Settings.swd_frequency_khz
  if($freq -lt 100 -or $freq -gt 24000){throw 'Invalid SWD frequency.'}
  if(-not [string]::IsNullOrWhiteSpace([string]$Settings.stlink_serial)){
    throw 'OpenOCD ST-Link serial selection is not configured. Use STM32CubeProgrammer.'
  }
  if($Settings.connect_under_reset -eq $true){
    throw 'OpenOCD under-reset is not configured. Disable connect_under_reset or use STM32CubeProgrammer.'
  }
  $config=if($Target -eq 'STM32F103'){'stm32f1x.cfg'}else{'stm32f4x.cfg'}
  return ,@('-s',$Location.Scripts,'-f','interface/stlink.cfg','-c',"adapter speed $freq",'-f',"target/$config",'-c',$Command)
}

function Get-OpenOcdDevice {
  param($Location,$Settings)
  $last=''
  foreach($trial in @('STM32F103','STM32F405')){
    $args=OpenOcd-Args $Location $trial $Settings 'init; halt; mdw 0xE0042000 1; shutdown'
    $result=Invoke-OpenOcd $Location $args
    $last=$result.Output
    if($result.ExitCode -ne 0){continue}
    $m=[regex]::Match($result.Output,'(?im)0xE0042000:\s*(?:0x)?([0-9a-f]{8})\b')
    if(-not $m.Success){continue}
    $raw=[Convert]::ToUInt32($m.Groups[1].Value,16)
    $id=[int]($raw -band 0xFFF)
    $family=if($id -in @(0x410,0x412,0x414,0x430)){'STM32F103'}elseif($id -eq 0x413){'STM32F405'}else{$null}
    if($family){return [pscustomobject]@{Target=$family;DeviceId=$id;RawId=$raw;Output=$result.Output}}
    throw ('Unsupported Device ID 0x{0:X3}. Nothing written.' -f $id)
  }
  throw ('OpenOCD could not read the MCU Device ID. Nothing written. Last output: ' + $last)
}

function Invoke-OpenOcdFlash {
  param($Location,$Settings,[string]$Target,[string]$Firmware)
  if($Firmware -match '[{}]'){throw 'BIN path contains curly braces, unsupported by OpenOCD script mode.'}
  $normalized=$Firmware.Replace('\','/')
  $suffix=if($Settings.auto_reset_after_verify -eq $true){'verify reset exit'}else{'verify exit'}
  $command='program {' + $normalized + '} ' + $suffix + ' 0x08000000'
  $args=OpenOcd-Args $Location $Target $Settings $command
  $result=Invoke-OpenOcd $Location $args
  if($result.ExitCode -ne 0){throw ('OpenOCD failed: ' + $result.Output)}
  if($result.Output -notmatch '(?i)verified'){
    throw ('OpenOCD did not explicitly report verification success: ' + $result.Output)
  }
  return $result
}
