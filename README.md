# STM32 ST-Link Flasher

**Без STM32CubeProgrammer:** программа сначала ищет OpenOCD из PlatformIO по пути `%USERPROFILE%\\.platformio\\packages\\tool-openocd\\bin\\openocd.exe`. Если установленного OpenOCD нет и нет STM32CubeProgrammer, `install.bat` скачивает портативный ZIP xPack OpenOCD с GitHub, сверяет SHA-256 и распаковывает его в `tools/openocd`. Регистрация на сайте ST не требуется. При необходимости укажите `openocd_path` в `settings.json`. ST-Link USB-драйвер на Windows должен быть установлен отдельно, если его ещё нет.

**Графический режим (Windows):** запустите **`GUI.bat`**. **Выбирать процессор не нужно**: нажмите «Проверить ST-Link», и программа определит семейство через Device ID (F103/F405). Укажите `firmware.bin` непосредственно из `.pio/build/<env>/`, затем нажмите «Прошить и проверить». Результат и журнал отображаются в окне, полные логи сохраняются в `logs/`. Работает через Windows PowerShell 5.1/WinForms, без Python и дополнительных GUI-библиотек. Для консольной работы оставлен `flash.bat`.


Прошивка **STM32F103** и **STM32F405** через **ST-Link** на Windows 10/11 без необходимости устанавливать VS Code или PlatformIO на ПК с программатором.

Программа проверяет подключённый MCU по Device ID, записывает BIN во внутреннюю Flash, выполняет проверку записи (verify), сохраняет журнал и при необходимости перезапускает MCU.

**Внимание:** до прошивки отключите высоковольтную часть, силовые ключи, двигатель и исполнительные механизмы. Проверка Flash не гарантирует безопасность или работоспособность прошивки. Пока не тестировалось на физическом оборудовании.

## Установка

1. Скачайте ZIP репозитория («Code → Download ZIP») и распакуйте.
2. Запустите **install.bat**.
3. Если STM32CubeProgrammer отсутствует, откроется официальная страница https://www.st.com/en/development-tools/stm32cubeprog.html. Скачайте Windows-версию и распакуйте архив ST.
4. Скопируйте официальный файл SetupSTM32CubeProgrammer-*.exe в папку installers и повторно запустите install.bat, либо передайте полный путь к установщику первым аргументом BAT.
5. При проблемах с определением ST-Link установите драйвер STSW-LINK009: https://www.st.com/en/development-tools/stsw-link009.html

Установка STM32CubeProgrammer и драйвера осуществляется официальными установщиками ST; установщик не обходит лицензионные условия ST. Для работы программы нужен встроенный Windows PowerShell, но **Python, PlatformIO и VS Code на компьютере прошивки не нужны**.

## Где взять файл прошивки

В VS Code откройте PlatformIO и нажмите **Build** (галочка на панели), либо запустите команду сборки:

    pio run -e ИМЯ_ОКРУЖЕНИЯ

Затем найдите файл:

    ПАПКА_ПРОЕКТА/.pio/build/ИМЯ_ОКРУЖЕНИЯ/firmware.bin

ИМЯ_ОКРУЖЕНИЯ — имя секции env в platformio.ini. Именно **firmware.bin** нужно копировать в прошивальщик (не firmware.elf и не firmware.map).

## Подключение ST-Link

Провода: SWDIO, SWCLK, GND, подходящее питание платы; желательно также NRST. При настройке connect_under_reset=true NRST обязателен. Следите, чтобы два источника питания не конфликтовали.

## Как прошить

1. Скопируйте firmware.bin для нужной платы в **firmware/STM32F103/firmware.bin** или **firmware/STM32F405/firmware.bin**.
2. Запустите **flash.bat**.
3. Выберите 1 для STM32F103 или 2 для STM32F405.
4. Проверьте размер, SHA256 и определённый Device ID; введите **FLASH** для подтверждения.
5. Скрипт выполнит запись по адресу 0x08000000 с проверкой (verify), сохранит лог в logs и, если включено в настройках, перезапустит MCU.

Когда файл лежит в другом месте, скрипт попросит путь к нему. Запуск из PowerShell со своими параметрами:

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\flash.ps1 -Target STM32F405 -FirmwarePath "C:\MyProject\.pio\build\my_env\firmware.bin"

В settings.json настраиваются cube_cli_path, swd_frequency_khz, connect_under_reset, auto_reset_after_verify и stlink_serial.

## Поддерживаемые идентификаторы

- STM32F103: 0x410, 0x412, 0x414, 0x430. Некоторые идентификаторы могут совпадать с F101/F102.
- STM32F405: 0x413. Идентификатор может совпадать с F407/F415/F417.

**В .bin нет поля с моделью процессора.** Программа распознаёт подключённое устройство через ST-Link, но не может доказать, что выбранный BIN соответствует аппаратной ревизии. Обязательно сверяйте плату и конфигурацию сборки.

**Сверяйте точную маркировку MCU и модель платы.** Скрипт не доказывает, что прошивка подходит конкретной плате, и поддерживает только BIN, рассчитанные на адрес **0x08000000** (без стороннего загрузчика и смещения). Не выполняет mass erase или снятие readout protection.

## Структура

    GUI.bat               <- графический режим
    install.bat
    flash.bat
    settings.json
    scripts/common.ps1
    scripts/probe.ps1
    scripts/openocd.ps1
    scripts/install-openocd.ps1
    scripts/gui.ps1
    scripts/install.ps1
    scripts/flash.ps1
    firmware/STM32F103/
    firmware/STM32F405/
    installers/
    logs/                 (создаётся при запуске)

Файлы BIN и установщики не включаются в репозиторий; см. .gitignore.

[Справочник STM32CubeProgrammer CLI](https://dev.st.com/stm32cube-docs/prog/2.23.0/en/docs/markup/CubeProg_Command_Lines.html).

## Прошивка без STM32CubeProgrammer

Если программатор уже работает через VS Code/PlatformIO, ничего дополнительно скачивать не нужно. Нажмите `GUI.bat`: утилита должна найти OpenOCD в установленном PlatformIO и использовать его для проверки ST-Link, записи и verify. Для отдельного ПК `install.bat` автоматически скачает портативный xPack OpenOCD с GitHub (при наличии доступа) и проверит SHA-256 опубликованного архива. Альтернатива: скачайте ZIP для Windows x64 вручную: https://github.com/xpack-dev-tools/openocd-xpack/releases и распакуйте под `tools/openocd`.

OpenOCD запускается с `interface/stlink.cfg` и `target/stm32f1x.cfg`/ `stm32f4x.cfg` согласно обнаруженному Device ID. Запись BIN происходит по адресу `0x08000000`, затем выполняется verify. Проверка OpenOCD-бэкенда на физическом ST-Link пока не проводилась.
