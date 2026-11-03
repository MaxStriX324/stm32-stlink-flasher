# Windows PowerShell 5.1 + WinForms (requires no external GUI packages).
# All firmware safety checks are repeated by the flash.ps1 child process.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
. (Join-Path $PSScriptRoot 'common.ps1')
. (Join-Path $PSScriptRoot 'openocd.ps1')

$script:busy=$false
$script:worker=$null
$script:mode=''
$script:outFile=''
$script:errFile=''
$script:outOffset=0
$script:errOffset=0
$script:detectedTarget=$null
$script:detectedId=$null

function C([string]$hex) { return [System.Drawing.ColorTranslator]::FromHtml($hex) }
function Label($parent,[string]$caption,[int]$x,[int]$y,[int]$w,[int]$h,[int]$size=10,[bool]$bold=$false) {
  $obj=New-Object System.Windows.Forms.Label
  $obj.Text=$caption
  $obj.Location=[System.Drawing.Point]::new($x,$y)
  $obj.Size=[System.Drawing.Size]::new($w,$h)
  $fontStyle=if($bold){[System.Drawing.FontStyle]::Bold}else{[System.Drawing.FontStyle]::Regular}
  $obj.Font=[System.Drawing.Font]::new('Segoe UI',[float]$size,$fontStyle)
  $obj.ForeColor=C '#18323C'
  $parent.Controls.Add($obj)
  return $obj
}
function Button($parent,[string]$caption,[int]$x,[int]$y,[int]$w,[int]$h,[bool]$primary=$false) {
  $obj=New-Object System.Windows.Forms.Button
  $obj.Text=$caption
  $obj.Location=[System.Drawing.Point]::new($x,$y)
  $obj.Size=[System.Drawing.Size]::new($w,$h)
  $obj.FlatStyle=[System.Windows.Forms.FlatStyle]::Flat
  $obj.FlatAppearance.BorderSize=1
  $obj.FlatAppearance.BorderColor=C '#D3E0E3'
  $obj.Cursor=[System.Windows.Forms.Cursors]::Hand
  $obj.BackColor=if($primary){C '#25816D'}else{C '#FFFFFF'}
  $obj.ForeColor=if($primary){C '#FFFFFF'}else{C '#21414A'}
  $parent.Controls.Add($obj)
  return $obj
}
function Panel([int]$x,[int]$y,[int]$w,[int]$h) {
  $obj=New-Object System.Windows.Forms.Panel
  $obj.Location=[System.Drawing.Point]::new($x,$y)
  $obj.Size=[System.Drawing.Size]::new($w,$h)
  $obj.BackColor=C '#FFFFFF'
  $obj.BorderStyle=[System.Windows.Forms.BorderStyle]::FixedSingle
  $form.Controls.Add($obj)
  return $obj
}
function Quoted([string]$value) { return '"' + $value.Replace('"','\"') + '"' }

$form=New-Object System.Windows.Forms.Form
$form.Text='STM32 ST-Link Flasher'
$form.StartPosition=[System.Windows.Forms.FormStartPosition]::CenterScreen
$form.FormBorderStyle=[System.Windows.Forms.FormBorderStyle]::FixedDialog
$form.MaximizeBox=$false
$form.ClientSize=[System.Drawing.Size]::new(880,738)
$form.BackColor=C '#F2F6F6'
$form.Font=[System.Drawing.Font]::new('Segoe UI',10)

$header=New-Object System.Windows.Forms.Panel
$header.Location=[System.Drawing.Point]::new(0,0)
$header.Size=[System.Drawing.Size]::new(880,93)
$header.BackColor=C '#1C4851'
$form.Controls.Add($header)
$t=Label $header 'STM32  /  ST-LINK FLASHER' 26 18 830 34 20 $true
$t.ForeColor=C '#FFFFFF'
$t=Label $header 'Запись и проверка Flash • STM32F103 / STM32F405 • SWD' 27 58 830 22 10
$t.ForeColor=C '#D8EFEC'

$pDevice=Panel 24 112 832 104
[void](Label $pDevice '1. Микроконтроллер и соединение' 18 11 480 25 11 $true)
[void](Label $pDevice 'Серия MCU' 18 43 110 26 10)
$lblAuto=Label $pDevice 'Автоматически через ST-Link' 138 45 229 26 9 $true
$lblDevice=Label $pDevice 'MCU: не проверен' 380 47 245 23 9
$note=Label $pDevice 'Автоопределение через ST-Link' 611 45 218 28 9

$pFile=Panel 24 232 832 168
[void](Label $pFile '2. Файл прошивки' 18 12 500 25 11 $true)
$txtFile=New-Object System.Windows.Forms.TextBox
$txtFile.Location=[System.Drawing.Point]::new(18,45)
$txtFile.Size=[System.Drawing.Size]::new(661,28)
$txtFile.ReadOnly=$true
$txtFile.BackColor=C '#F9FCFC'
$pFile.Controls.Add($txtFile)
$btnBrowse=Button $pFile 'Выбрать BIN' 692 40 119 37
$lblFile=Label $pFile 'Файл не выбран' 18 87 796 25 9
$hint=Label $pFile 'Файл находится в .pio\build\ИМЯ_ОКРУЖЕНИЯ\firmware.bin после Build в PlatformIO.' 18 124 794 24 9
$hint.ForeColor=C '#67818A'

$btnProbe=Button $form '1. ПРОВЕРИТЬ ПОДКЛЮЧЕНИЕ' 24 417 355 52
$btnFlash=Button $form '2. ПРОШИТЬ С ПРОВЕРКОЙ' 392 417 464 52 $true

$progress=New-Object System.Windows.Forms.ProgressBar
$progress.Location=[System.Drawing.Point]::new(24,485)
$progress.Size=[System.Drawing.Size]::new(832,17)
$progress.Style=[System.Windows.Forms.ProgressBarStyle]::Continuous
$form.Controls.Add($progress)
$lblStatus=Label $form 'Готово. Подключите ST-Link и выберите BIN.' 24 512 832 28 9
[void](Label $form 'Журнал операций' 24 549 600 26 11 $true)
$txtLog=New-Object System.Windows.Forms.RichTextBox
$txtLog.Location=[System.Drawing.Point]::new(24,582)
$txtLog.Size=[System.Drawing.Size]::new(832,119)
$txtLog.ReadOnly=$true
$txtLog.WordWrap=$false
$txtLog.ScrollBars=[System.Windows.Forms.RichTextBoxScrollBars]::Vertical
$txtLog.Font=[System.Drawing.Font]::new('Consolas',9)
$txtLog.BackColor=C '#19282F'
$txtLog.ForeColor=C '#E2F0F1'
$form.Controls.Add($txtLog)
[void](Label $form 'Внимание: перед прошивкой отключите силовую часть, двигатель и исполнительные устройства.' 24 710 832 22 9)

function Log-Line([string]$message) {
  $txtLog.AppendText("[$(Get-Date -Format HH:mm:ss)] $message" + [Environment]::NewLine)
  $txtLog.SelectionStart=$txtLog.TextLength
  $txtLog.ScrollToCaret()
}
function Status([string]$message,[bool]$bad=$false) {
  $lblStatus.Text=$message
  $lblStatus.ForeColor=if($bad){C '#AC3939'}else{C '#255D59'}
}
function Refresh-Buttons {
  $btnProbe.Enabled=-not $script:busy
  $btnBrowse.Enabled=-not $script:busy
  $btnFlash.Enabled=(-not $script:busy) -and ($null -ne $script:detectedTarget) -and (-not [string]::IsNullOrWhiteSpace($txtFile.Text)) -and (Test-Path -LiteralPath $txtFile.Text -PathType Leaf)
}
function Refresh-Firmware {
  $candidate=if($script:detectedTarget){Join-Path $ProjectRoot ('firmware\' + $script:detectedTarget + '\firmware.bin')}else{''}
  if($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
    $txtFile.Text=$candidate
    $info=Get-Item -LiteralPath $candidate
    $lblFile.Text=$info.Name + '  |  ' + ('{0:N0}' -f $info.Length) + ' байт'
  } else {
    $txtFile.Text=''
    $lblFile.Text='Файл не выбран. Укажите BIN из PlatformIO.'
  }
  Refresh-Buttons
}
function Read-Worker-Logs {
  foreach($kind in @('out','err')) {
    $path=if($kind -eq 'out'){$script:outFile}else{$script:errFile}
    if(-not (Test-Path -LiteralPath $path -PathType Leaf)){continue}
    try {
      $value=Get-Content -LiteralPath $path -Raw -Encoding UTF8 -ErrorAction Stop
      if($null -eq $value){continue}
      if($kind -eq 'out'){
        if($value.Length -gt $script:outOffset){
          $txtLog.AppendText($value.Substring($script:outOffset))
          $script:outOffset=$value.Length
        }
      } else {
        if($value.Length -gt $script:errOffset){
          $txtLog.AppendText($value.Substring($script:errOffset))
          $script:errOffset=$value.Length
        }
      }
      $txtLog.SelectionStart=$txtLog.TextLength
      $txtLog.ScrollToCaret()
    } catch {
      # Retry on the next tick if the writer holds the file.
    }
  }
}
function Start-Worker([ValidateSet('probe','flash')][string]$operation) {
  if($script:busy){return}
  $path=if($operation -eq 'probe'){Join-Path $PSScriptRoot 'probe.ps1'}else{Join-Path $PSScriptRoot 'flash.ps1'}
  $target=if($operation -eq 'probe'){'Auto'}else{$script:detectedTarget}
  if(-not $target){throw 'ST-Link has not been checked. Press Check ST-Link first.'}
  $stamp=Get-Date -Format 'yyyyMMdd_HHmmss_fff'
  $folder=Join-Path $ProjectRoot 'logs'
  New-Item -ItemType Directory -Path $folder -Force | Out-Null
  $prefix=Join-Path $folder ('gui_' + $stamp + '_' + $operation)
  $script:outFile=$prefix + '.out.log'
  $script:errFile=$prefix + '.err.log'
  $script:outOffset=0
  $script:errOffset=0
  $script:mode=$operation
  $workerArguments='-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ' + (Quoted $path) + ' -Target ' + $target
  if($operation -eq 'flash') { $workerArguments += ' -FirmwarePath ' + (Quoted $txtFile.Text) + ' -Yes' }
  $ps=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
  try {
    $script:worker=Start-Process -FilePath $ps -ArgumentList $workerArguments -WorkingDirectory $ProjectRoot -WindowStyle Hidden -RedirectStandardOutput $script:outFile -RedirectStandardError $script:errFile -PassThru -ErrorAction Stop
    $script:busy=$true
    $progress.Style=[System.Windows.Forms.ProgressBarStyle]::Marquee
    $progress.MarqueeAnimationSpeed=25
    Refresh-Buttons
    if($operation -eq 'probe'){ Status "Проверка ST-Link и MCU: $target ..." }
    else { Status "Запись и проверка: $target. Не отключайте ST-Link!" }
    Log-Line ('Запущено: ' + $operation + ' / ' + $target)
    $timer.Start()
  } catch {
    $script:worker=$null
    Status ('Ошибка запуска: ' + $_.Exception.Message) $true
    Log-Line ('Ошибка запуска: ' + $_.Exception.Message)
    Refresh-Buttons
  }
}
$timer=New-Object System.Windows.Forms.Timer
$timer.Interval=350
$timer.Add_Tick({
  if(-not $script:busy){return}
  Read-Worker-Logs
  try {
    $script:worker.Refresh()
    if(-not $script:worker.HasExited){return}
    $timer.Stop()
    Read-Worker-Logs
    $code=$script:worker.ExitCode
    $script:worker.Dispose()
    $script:worker=$null
    $script:busy=$false
    $progress.MarqueeAnimationSpeed=0
    $progress.Style=[System.Windows.Forms.ProgressBarStyle]::Continuous
    $progress.Value=if($code -eq 0){100}else{0}
    if($code -eq 0 -and $script:mode -eq 'probe'){
      $resultText=Get-Content -LiteralPath $script:outFile -Raw -Encoding UTF8
      $detected=[regex]::Match($resultText,'DETECTED_TARGET=(STM32F103|STM32F405);DEVICE_ID=(0x[0-9A-Fa-f]+)')
      if(-not $detected.Success){throw 'MCU identification was missing from probe output.'}
      $script:detectedTarget=$detected.Groups[1].Value
      $script:detectedId=$detected.Groups[2].Value
      $lblDevice.Text=$script:detectedTarget + ' / ' + $script:detectedId
      $lblDevice.ForeColor=C '#25816D'
      Status 'MCU распознан через ST-Link. Проверьте совместимость BIN с платой.'
      Log-Line ('Обнаружено: ' + $script:detectedTarget + ' / ' + $script:detectedId)
      if([string]::IsNullOrWhiteSpace($txtFile.Text)){Refresh-Firmware}
    } elseif($code -eq 0 -and $script:mode -eq 'flash'){
      Status 'УСПЕХ: прошивка записана и проверена.'
      Log-Line 'Прошивка и проверка: успешно.'
      [void][System.Windows.Forms.MessageBox]::Show('Запись и проверка Flash завершились успешно.','Успех','OK','Information')
    } else {
      if($script:mode -eq 'probe'){
        $script:detectedTarget=$null
        $script:detectedId=$null
        $lblDevice.Text='ST-Link / MCU: ошибка'
        $lblDevice.ForeColor=C '#AD4343'
      }
      Status 'Ошибка. Посмотрите подробности в журнале ниже.' $true
      Log-Line ('Неуспешная операция. Код: ' + $code)
      [void][System.Windows.Forms.MessageBox]::Show('Ошибка операции. Проверьте журнал, SWD и питание MCU.','Ошибка','OK','Error')
    }
    Refresh-Buttons
  } catch { Log-Line ('Ошибка обработки статуса: ' + $_.Exception.Message) }
})
$btnBrowse.Add_Click({
  $dialog=New-Object System.Windows.Forms.OpenFileDialog
  $dialog.Filter='BIN прошивки (*.bin)|*.bin|Все файлы (*.*)|*.*'
  $dialog.Title='Выберите firmware.bin из PlatformIO'
  $dialog.CheckFileExists=$true
  $dialog.Multiselect=$false
  try {
    if($dialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK){
      $txtFile.Text=$dialog.FileName
      $item=Get-Item -LiteralPath $txtFile.Text
      $lblFile.Text=$item.Name + '  |  ' + ('{0:N0}' -f $item.Length) + ' байт'
      Log-Line ('Файл: ' + $item.FullName)
      Refresh-Buttons
    }
  } finally { $dialog.Dispose() }
})
$btnProbe.Add_Click({ Start-Worker 'probe' })
$btnFlash.Add_Click({
  if($script:busy){return}
  if(-not $script:detectedTarget){
    [void][System.Windows.Forms.MessageBox]::Show('Сначала нажмите «Проверить ST-Link».','MCU не определён','OK','Warning')
    return
  }
  if(-not $txtFile.Text -or -not (Test-Path -LiteralPath $txtFile.Text -PathType Leaf)){
    [void][System.Windows.Forms.MessageBox]::Show('Сначала выберите файл прошивки.','Нет файла','OK','Warning')
    return
  }
  if([IO.Path]::GetExtension($txtFile.Text).ToLowerInvariant() -ne '.bin'){
    [void][System.Windows.Forms.MessageBox]::Show('Нужен файл с расширением .bin.','Неверный файл','OK','Warning')
    return
  }
  try {
    $s=Get-FlasherSettings
    if(-not (Find-OpenOcd) -and -not (Find-CubeCli ([string]$s.cube_cli_path))){
      [void][System.Windows.Forms.MessageBox]::Show('Не найден OpenOCD или STM32CubeProgrammer. Нажмите «Установить OpenOCD».','Нет инструмента','OK','Warning')
      return
    }
    $fw=Get-Item -LiteralPath $txtFile.Text
    $hash=(Get-FileHash -LiteralPath $fw.FullName -Algorithm SHA256).Hash
    $message="Обнаруженный MCU: $($script:detectedTarget), Device ID: $($script:detectedId)" + [Environment]::NewLine +
      "Файл: $($fw.FullName)" + [Environment]::NewLine +
      "Размер: $($fw.Length) байт" + [Environment]::NewLine +
      "SHA-256: $hash" + [Environment]::NewLine + [Environment]::NewLine +
      'В BIN нет информации о модели MCU. Убедитесь, что прошивка собрана для этой платы.' + [Environment]::NewLine +
      'Отключите высокое напряжение и исполнительные устройства!' + [Environment]::NewLine +
      'Записать по адресу 0x08000000 и проверить Flash?'
    $answer=[System.Windows.Forms.MessageBox]::Show($message,'Подтверждение записи','YesNo','Warning','Button2')
    if($answer -ne [System.Windows.Forms.DialogResult]::Yes){Log-Line 'Запись отменена.';return}
    Start-Worker 'flash'
  } catch {
    [void][System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'Ошибка подготовки','OK','Error')
  }
})
$form.Add_FormClosing({
  param($sender,$eventArgs)
  if($script:busy){
    $eventArgs.Cancel=$true
    [void][System.Windows.Forms.MessageBox]::Show('Операция ещё выполняется. Дождитесь окончания и не отключайте ST-Link.','Операция активна','OK','Warning')
  }
})
Refresh-Firmware
Log-Line 'Проверьте подключение ST-Link, выберите BIN и нажмите «Прошить с проверкой».'
try { [void]$form.ShowDialog() } finally {
  $timer.Stop()
  $timer.Dispose()
  $form.Dispose()
}
