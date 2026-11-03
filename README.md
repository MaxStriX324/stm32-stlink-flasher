# STM32 ST-Link Flasher

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

**Сверяйте точную маркировку MCU и модель платы.** Скрипт не доказывает, что прошивка подходит конкретной плате, и поддерживает только BIN, рассчитанные на адрес **0x08000000** (без стороннего загрузчика и смещения). Не выполняет mass erase или снятие readout protection.

## Структура

    install.bat
    flash.bat
    settings.json
    scripts/common.ps1
    scripts/install.ps1
    scripts/flash.ps1
    firmware/STM32F103/
    firmware/STM32F405/
    installers/
    logs/                 (создаётся при запуске)

Файлы BIN и установщики не включаются в репозиторий; см. .gitignore.

[Справочник STM32CubeProgrammer CLI](https://dev.st.com/stm32cube-docs/prog/2.23.0/en/docs/markup/CubeProg_Command_Lines.html).
