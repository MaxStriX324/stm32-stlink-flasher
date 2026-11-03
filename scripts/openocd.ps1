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
  $platformioHome=if($env:PLATFORMIO_CORE_DIR){$env:PLATFORMIO_CORE_DIR}else{Join-Path $env:USERPROFILE '.platformio'}
  foreach($name in @('tool-openocd','tool-openocd-stm32')){
    $candidates.Add((Join-Path $platformioHome ("packages\" + $name + "\bin\openocd.exe")))
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
  param($Location,[string[]]$Arguments,[int]$TimeoutSeconds=30)
  # OpenOCD writes information to stderr even when it succeeds.
  # In Windows PowerShell 5.1, '2>&1' turns those lines into NativeCommandError records.
  # Capture stdout and stderr separately to avoid corrupted / missing device-ID output.
  $stdout=[IO.Path]::GetTempFileName()
  $stderr=[IO.Path]::GetTempFileName()
  $process=$null
  try {
    # Start-Process in Windows PowerShell 5.1 joins ArgumentList values without quoting.
    # Quote every argument so paths with spaces and entire Tcl -c commands stay intact.
    $nativeArguments=($Arguments | ForEach-Object {
      if($_.Contains('"')){throw 'Unexpected double quote in OpenOCD argument.'}
      '"' + $_ + '"'
    }) -join ' '
    $process=Start-Process -FilePath $Location.Exe -ArgumentList $nativeArguments -WindowStyle Hidden `
      -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru -ErrorAction Stop
    $completed=$process.WaitForExit($TimeoutSeconds * 1000)
    if(-not $completed){
      try{$process.Kill()}catch{}
      throw ('OpenOCD timed out after ' + $TimeoutSeconds + ' seconds. Check ST-Link connection.')
    }
    $exitCode=$process.ExitCode
    $outText=[IO.File]::ReadAllText($stdout)
    $errText=[IO.File]::ReadAllText($stderr)
    $combined=$outText + [Environment]::NewLine + $errText
    return [pscustomobject]@{Output=$combined;ExitCode=$exitCode}
  } finally {
    if($process){$process.Dispose()}
    foreach($item in @($stdout,$stderr)){
      if(Test-Path -LiteralPath $item){Remove-Item -LiteralPath $item -Force -ErrorAction SilentlyContinue}
    }
  }
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
  return ,@('-s',$Location.Scripts,'-f','interface/stlink.cfg','-f',"target/$config",'-c',"adapter speed $freq",'-c',$Command)
}

function Parse-OpenOcdDeviceId {
  param([string]$Output)
  $m=[regex]::Match($Output,'(?im)^\s*(?:(?:User|Info)\s*:\s*)?STM32_IDCODE=0x([0-9a-f]{8})\s*$')
  if(-not $m.Success){return $null}
  $raw=[Convert]::ToUInt32($m.Groups[1].Value,16)
  $id=[int]($raw -band 0xFFF)
  $family=if($id -in @(0x410,0x412,0x414,0x430)){'STM32F103'}elseif($id -eq 0x413){'STM32F405'}else{$null}
  return [pscustomobject]@{Target=$family;DeviceId=$id;RawId=$raw}
}
function Get-OpenOcdDevice {
  param($Location,$Settings)
  $last=''
  foreach($trial in @('STM32F405','STM32F103')){
    $command='init; halt; if {[catch {read_memory 0xE0042000 32 1} data]} {echo STM32_READ_FAILED; resume; shutdown error}; echo [format {STM32_IDCODE=0x%08X} [lindex $data 0]]; resume; shutdown'
    $probeArguments=OpenOcd-Args $Location $trial $Settings $command
    $result=Invoke-OpenOcd $Location $probeArguments 30
    $last=$result.Output
    if($result.ExitCode -ne 0){continue}
    $device=Parse-OpenOcdDeviceId $result.Output
    if(-not $device){continue}
    if(-not $device.Target){throw ('Unsupported Device ID 0x{0:X3}. Nothing written.' -f $device.DeviceId)}
    if($trial -ne $device.Target){continue}
    return [pscustomobject]@{Target=$device.Target;DeviceId=$device.DeviceId;RawId=$device.RawId;Output=$result.Output}
  }
  throw ('OpenOCD did not report an MCU ID. No write attempted. Last output: ' + $last)
}

function Invoke-OpenOcdFlash {
  param($Location,$Settings,[string]$Target,[string]$Firmware)
  if($Firmware -match '[{}]'){throw 'BIN path contains curly braces, unsupported by OpenOCD script mode.'}
  $normalized=$Firmware.Replace('\','/')
  $suffix=if($Settings.auto_reset_after_verify -eq $true){'verify reset exit'}else{'verify exit'}
  $command='program {' + $normalized + '} ' + $suffix + ' 0x08000000'
  $flashArguments=OpenOcd-Args $Location $Target $Settings $command
  $result=Invoke-OpenOcd $Location $flashArguments 180
  if($result.ExitCode -ne 0){throw ('OpenOCD failed: ' + $result.Output)}
  if($result.Output -notmatch '(?i)\*\*\s*Verified OK\s*\*\*'){
    throw ('OpenOCD did not explicitly report verification success: ' + $result.Output)
  }
  return $result
}
