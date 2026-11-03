param([string]$InstallerPath = '')
. (Join-Path $PSScriptRoot 'common.ps1')
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$official = 'https://www.st.com/en/development-tools/stm32cubeprog.html'
$driver = 'https://www.st.com/en/development-tools/stsw-link009.html'

try {
  $s = Get-FlasherSettings
  $cli = Find-CubeCli ([string]$s.cube_cli_path)
  if (-not $cli) {
    Write-Host 'STM32CubeProgrammer is not installed.'
    if (-not $InstallerPath) {
      foreach ($folder in @((Join-Path $ProjectRoot 'installers'), (Join-Path $env:USERPROFILE 'Downloads'))) {
        if (Test-Path -LiteralPath $folder) {
          $candidate = Get-ChildItem -LiteralPath $folder -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^SetupSTM32CubeProgrammer.*\.exe$' } |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
          if ($candidate) { $InstallerPath = $candidate.FullName; break }
        }
      }
    }
    if (-not $InstallerPath) {
      Write-Host "Get the official installer: $official"
      Start-Process $official
      Write-Host 'Download and extract the STM32CubeProgrammer Windows ZIP, then run install.bat again.'
      Write-Host 'You can put SetupSTM32CubeProgrammer-*.exe in installers or pass its path to install.bat.'
      exit 2
    }
    $InstallerPath = [Environment]::ExpandEnvironmentVariables($InstallerPath.Trim('"'))
    if (-not (Test-Path -LiteralPath $InstallerPath -PathType Leaf)) { throw "Installer not found: $InstallerPath" }
    if ([IO.Path]::GetFileName($InstallerPath) -notmatch '^SetupSTM32CubeProgrammer.*\.exe$') {
      throw 'Expected the official extracted SetupSTM32CubeProgrammer-*.exe file.'
    }
    $proc = Start-Process -FilePath $InstallerPath -Verb RunAs -Wait -PassThru
    if ($proc.ExitCode -ne 0) { throw "Installer failed with code $($proc.ExitCode)" }
    $cli = Find-CubeCli ([string]$s.cube_cli_path)
    if (-not $cli) { throw 'CLI not found after installation. Set cube_cli_path in settings.json.' }
  }
  Write-Host "STM32CubeProgrammer CLI: $cli" -ForegroundColor Green
  $driverScript = Join-Path (Split-Path -Parent (Split-Path -Parent $cli)) 'Driver\stsw-link009_v3\stlink_winusb_install.bat'
  if (Test-Path -LiteralPath $driverScript -PathType Leaf) {
    $answer = Read-Host 'Run bundled official ST-Link driver installer? Y/N'
    if ($answer -match '^[Yy]$') {
      $proc = Start-Process -FilePath 'cmd.exe' -ArgumentList ('/c "' + $driverScript + '"') -Verb RunAs -Wait -PassThru
      if ($proc.ExitCode -ne 0) { Write-Warning "ST-Link driver installer exited: $($proc.ExitCode)" }
    }
  } else {
    Write-Host "If ST-Link is not detected, install STSW-LINK009: $driver"
    $answer = Read-Host 'Open the official driver page? Y/N'
    if ($answer -match '^[Yy]$') { Start-Process $driver }
  }
  Write-Host 'Setup finished. VS Code/PlatformIO are not required on this PC.' -ForegroundColor Green
  exit 0
} catch {
  Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
  exit 1
}
