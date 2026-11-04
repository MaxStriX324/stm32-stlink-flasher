param([switch]$NoLaunch)
# One-click installer for the current Windows user; no admin rights required.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object System.Text.UTF8Encoding($false)
try {
  if(-not [Environment]::Is64BitOperatingSystem){
    throw 'Requires 64-bit Windows 10 or 11.'
  }
  $sourceRoot=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
  $installRoot=Join-Path $env:LOCALAPPDATA 'Programs\STM32-STLink-Flasher'
  New-Item -ItemType Directory -Path $installRoot -Force | Out-Null

  $distributionFiles=@(
    'install.bat','update.bat','GUI.bat','LaunchGUI.vbs','flash.bat','README.md','settings.json',
    'scripts\common.ps1','scripts\openocd.ps1','scripts\install.ps1','scripts\update.ps1',
    'scripts\install-openocd.ps1','scripts\probe.ps1','scripts\flash.ps1',
    'scripts\gui.ps1','firmware\STM32F103\.gitkeep',
    'firmware\STM32F405\.gitkeep','installers\.gitkeep'
  )
  if($sourceRoot.TrimEnd('\') -ine $installRoot.TrimEnd('\')){
    Write-Host ('Installing files into ' + $installRoot)
    foreach($item in $distributionFiles){
      $source=Join-Path $sourceRoot $item
      $dest=Join-Path $installRoot $item
      if(-not (Test-Path -LiteralPath $source -PathType Leaf)){throw "Package is missing $item"}
      $folder=Split-Path -Parent $dest
      New-Item -ItemType Directory -Path $folder -Force | Out-Null
      if($item -eq 'settings.json' -and (Test-Path -LiteralPath $dest -PathType Leaf)){
        Write-Host 'Preserving existing settings.json'
        continue
      }
      Copy-Item -LiteralPath $source -Destination $dest -Force
    }
  } else {
    Write-Host 'Installation already at destination. Checking dependencies.'
  }

  # Search for PlatformIO's OpenOCD first, then use existing CubeProgrammer.
  . (Join-Path $installRoot 'scripts\common.ps1')
  . (Join-Path $installRoot 'scripts\openocd.ps1')
  $settings=Get-FlasherSettings
  $openocd=Find-OpenOcd
  $backend=$null
  if($openocd){
    $backend='OpenOCD'
    Write-Host ('OpenOCD found: ' + $openocd.Exe) -ForegroundColor Green
  } else {
    $cube=Find-CubeCli ([string]$settings.cube_cli_path)
    if($cube){
      $backend='STM32CubeProgrammer'
      Write-Host ('STM32CubeProgrammer found: ' + $cube) -ForegroundColor Green
    } else {
      Write-Host 'Downloading portable OpenOCD with SHA256 verification...'
      & (Join-Path $installRoot 'scripts\install-openocd.ps1')
      if($LASTEXITCODE -ne 0){throw ('OpenOCD installation exited with code ' + $LASTEXITCODE)}
      $openocd=Find-OpenOcd
      if(-not $openocd){throw 'OpenOCD still not found after extracting it.'}
      $backend='OpenOCD'
    }
  }

  # Desktop shortcut; preserve the user's location even with OneDrive redirects.
  $launchScript=Join-Path $installRoot 'LaunchGUI.vbs'
  $wscript=Join-Path $env:WINDIR 'System32\wscript.exe'
  $desktop=[Environment]::GetFolderPath([System.Environment+SpecialFolder]::DesktopDirectory)
  if($desktop -and (Test-Path -LiteralPath $desktop)){
    try {
      $shell=New-Object -ComObject WScript.Shell
      $shortcut=$shell.CreateShortcut((Join-Path $desktop 'STM32 ST-Link Flasher.lnk'))
      $shortcut.TargetPath=$wscript
      $shortcut.Arguments='"' + $launchScript + '"'
      $shortcut.WorkingDirectory=$installRoot
      $shortcut.Description='Program and verify STM32F103 / STM32F405 using ST-Link'
      $shortcut.IconLocation=(Join-Path $env:WINDIR 'System32\shell32.dll') + ',13'
      $shortcut.Save()
      Write-Host 'Desktop shortcut created.' -ForegroundColor Green
    } catch {
      Write-Warning ('Cannot create desktop shortcut: ' + $_.Exception.Message)
    }
  }
  Write-Host ('Installed: ' + $installRoot) -ForegroundColor Green
  Write-Host ('Programming backend: ' + $backend) -ForegroundColor Green
  if(-not $NoLaunch){
    Start-Process -FilePath $wscript -ArgumentList ('"' + $launchScript + '"') -WorkingDirectory $installRoot
  }
  exit 0
} catch {
  Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red
  Write-Host 'Alternative OpenOCD download: https://github.com/xpack-dev-tools/openocd-xpack/releases'
  exit 1
}
