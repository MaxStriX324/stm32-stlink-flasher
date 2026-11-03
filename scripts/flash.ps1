param(
  [ValidateSet('STM32F103','STM32F405')][string]$Target,
  [string]$FirmwarePath,
  [switch]$Yes
)
. (Join-Path $PSScriptRoot 'common.ps1')
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

function Fail([string]$msg) { throw $msg }

try {
  $settings = Get-FlasherSettings
  $cli = Find-CubeCli ([string]$settings.cube_cli_path)
  if (-not $cli) { Fail 'STM32CubeProgrammer CLI not found. Run install.bat.' }
  if (-not $Target) {
    Write-Host '[1] STM32F103'
    Write-Host '[2] STM32F405'
    switch (Read-Host 'Choose MCU (1/2)') {
      '1' { $Target='STM32F103' }
      '2' { $Target='STM32F405' }
      default { Fail 'Invalid MCU selection.' }
    }
  }
  if (-not $FirmwarePath) {
    $default = Join-Path $ProjectRoot "firmware\$Target\firmware.bin"
    if (Test-Path -LiteralPath $default -PathType Leaf) { $FirmwarePath=$default }
    else { $FirmwarePath=Read-Host 'Path to firmware.bin from .pio\build\ENV\' }
  }
  $FirmwarePath = $FirmwarePath.Trim().Trim('"')
  if (-not (Test-Path -LiteralPath $FirmwarePath -PathType Leaf)) { Fail "File missing: $FirmwarePath" }
  $bin = (Resolve-Path -LiteralPath $FirmwarePath).Path
  if ([IO.Path]::GetExtension($bin).ToLowerInvariant() -ne '.bin') { Fail 'Expected firmware.bin (.bin).' }
  $fw = Get-Item -LiteralPath $bin
  if ($fw.Length -lt 8) { Fail 'Firmware file is too small.' }
  $data = [IO.File]::ReadAllBytes($bin)
  $stack = [BitConverter]::ToUInt32($data,0)
  $reset = [BitConverter]::ToUInt32($data,4)
  if (($stack -band 0xFF000000) -ne 0x20000000 -and ($stack -band 0xFF000000) -ne 0x10000000) {
    Fail ('Bad initial SP 0x{0:X8}; is this a valid Cortex-M firmware?' -f $stack)
  }
  if (($reset -band 1) -ne 1 -or ($reset -band 0xFF000000) -ne 0x08000000) {
    Fail ('Bad reset vector 0x{0:X8}. Only Flash images for 0x08000000 are supported.' -f $reset)
  }
  $hash = (Get-FileHash -LiteralPath $bin -Algorithm SHA256).Hash
  $logDir = Join-Path $ProjectRoot 'logs'
  New-Item -ItemType Directory -Force -Path $logDir | Out-Null
  $log = Join-Path $logDir ((Get-Date -Format yyyyMMdd_HHmmss_fff)+"_$Target.log")
  $conn = Get-ConnectionArgs $settings
  Add-Content -LiteralPath $log -Encoding UTF8 -Value ("Target=$Target; File=$bin; SHA256=$hash")

  function Invoke-Cube([string[]]$Arguments) {
    Add-Content -LiteralPath $log -Encoding UTF8 -Value ('> "'+$cli+'" '+($Arguments -join ' '))
    $output = & $cli @Arguments 2>&1 | Out-String
    $rc = $LASTEXITCODE
    Add-Content -LiteralPath $log -Encoding UTF8 -Value $output
    Write-Host $output
    if ($rc -ne 0 -or $output -match '(?im)^\s*(?:Error|Exception)\s*:') {
      Fail "STM32CubeProgrammer failed (code $rc). See $log"
    }
    return $output
  }

  Write-Host "MCU=$Target; BIN=$bin; Bytes=$($fw.Length)"
  Write-Host "SHA256: $hash"
  $info = Invoke-Cube $conn
  $m = [regex]::Match($info,'(?im)^\s*(?:Device\s+ID|Chip\s+ID)\s*:\s*0x([0-9a-f]+)')
  if (-not $m.Success) { Fail 'Could not read MCU Device ID; nothing was written.' }
  $id = [Convert]::ToInt32($m.Groups[1].Value,16)
  $allowed = if ($Target -eq 'STM32F103') { @(0x410,0x412,0x414,0x430) } else { @(0x413) }
  if ($id -notin $allowed) { Fail ('Device ID 0x{0:X3} is not allowed for {1}; no write.' -f $id,$Target) }
  Write-Host ('Detected Device ID: 0x{0:X3}' -f $id)
  $sz = [regex]::Match($info,'(?im)^\s*Flash\s+size\s*:\s*(\d+)\s*(KBytes|KB|MBytes|MB|Bytes)')
  if ($sz.Success) {
    $capacity = [long]::Parse($sz.Groups[1].Value)
    if ($sz.Groups[2].Value -match '^(KBytes|KB)$') { $capacity *= 1024 }
    if ($sz.Groups[2].Value -match '^(MBytes|MB)$') { $capacity *= 1048576 }
    if ($fw.Length -gt $capacity) { Fail "Image exceeds detected Flash size ($capacity bytes)." }
  } else { Write-Warning 'CLI did not report Flash size; verify the exact MCU manually.' }
  Write-Warning 'Device ID does not uniquely identify the MCU/PCB variant. Check the firmware carefully.'
  Write-Warning 'Disconnect high voltage, gate drivers, motors and other actuators.'
  if (-not $Yes) {
    if ((Read-Host 'Type FLASH to program the device') -cne 'FLASH') { Fail 'Cancelled; nothing written.' }
  }
  $null = Invoke-Cube (@($conn) + @('-w',$bin,'0x08000000','-v'))
  Write-Host 'SUCCESS: firmware written and verified.' -ForegroundColor Green
  if ($settings.auto_reset_after_verify -eq $true) {
    try { $null = Invoke-Cube (@($conn) + @('-rst')) }
    catch { Write-Warning "Verified successfully, but reset failed: $_" }
  }
  Write-Host "Log saved: $log"
  exit 0
} catch {
  Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
  exit 1
}
