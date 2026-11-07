@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion

set "REPORT=%~dp0pc_report.txt"
set "APPS=%TEMP%\apps_list.txt"
set "TMP1=%TEMP%\pc_info_1.tmp"

> "%REPORT%" echo Диагностика компьютера
>>"%REPORT%" echo ============================================================
>>"%REPORT%" echo Дата формирования: %DATE% %TIME%
>>"%REPORT%" echo ============================================================
>>"%REPORT%" echo.

echo Диагностика компьютера
echo ============================================================
echo Дата: %DATE% %TIME%
echo.

REM --- Операционная система ---
call :log ""
call :log "Операционная система"
set "OS_CAPTION="
set "OS_VERSION="
wmic os get Caption,Version /format:list 2>nul | findstr /r /v "^$" > "%TMP1%"
for /f "tokens=1,* delims==" %%a in ('type "%TMP1%"') do (
    if /i "%%a"=="Caption" set "OS_CAPTION=%%b"
    if /i "%%a"=="Version" set "OS_VERSION=%%b"
)
if defined OS_CAPTION (
    call :log "  Система: !OS_CAPTION!"
    call :log "  Версия:  !OS_VERSION!"
) else (
    call :log "  Не удалось получить сведения об ОС."
)
del "%TMP1%" 2>nul

REM --- Процессор ---
call :log ""
call :log "Процессор"
set "CPU="
for /f "skip=1 tokens=* delims=" %%a in ('wmic cpu get Name 2^>nul ^| findstr /r /v "^$"') do (
    if not defined CPU set "CPU=%%a"
)
if defined CPU (
    call :log "  Название: !CPU!"
) else (
    call :log "  Не удалось получить сведения о процессоре."
)

REM --- Оперативная память ---
call :log ""
call :log "Оперативная память"
set "TOTAL_GB="
set "FREE_GB="
for /f "usebackq delims=" %%a in (`powershell -NoProfile -Command ^
  "$o=Get-CimInstance Win32_OperatingSystem; '{0} {1}' -f [math]::Round($o.TotalVisibleMemorySize/1MB), [math]::Round($o.FreePhysicalMemory/1MB)"`) do (
    for /f "tokens=1,2" %%x in ("%%a") do (
        set "TOTAL_GB=%%x"
        set "FREE_GB=%%y"
    )
)
if defined TOTAL_GB (
    call :log "  Всего памяти:    !TOTAL_GB! ГБ"
    call :log "  Свободно памяти: !FREE_GB! ГБ"
) else (
    call :log "  Не удалось получить сведения об оперативной памяти."
)

REM --- Диск C ---
call :log ""
call :log "Диск C:"
set "SIZE_GB="
set "FREE_DISK_GB="

REM Создаем временный файл со скриптом PowerShell (чтобы избежать проблем с кавычками)
set "PS_SCRIPT=%TEMP%\get_disk.ps1"
echo $d = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" > "%PS_SCRIPT%"
echo if ($d) { >> "%PS_SCRIPT%"
echo     $free = [math]::Round($d.FreeSpace / 1GB) >> "%PS_SCRIPT%"
echo     $total = [math]::Round($d.Size / 1GB) >> "%PS_SCRIPT%"
echo     Write-Output "$total $free" >> "%PS_SCRIPT%"
echo } >> "%PS_SCRIPT%"

REM Запускаем скрипт и читаем результат
for /f "tokens=1,2" %%a in ('powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%"') do (
    set "SIZE_GB=%%a"
    set "FREE_DISK_GB=%%b"
)

del "%PS_SCRIPT%" 2>nul

if defined SIZE_GB (
    call :log "  Всего места:    !SIZE_GB! ГБ"
    call :log "  Свободно места: !FREE_DISK_GB! ГБ"
) else (
    call :log "  Не удалось получить сведения о диске C:."
)

call :log ""
call :log "Идёт поиск установленных программ, это может занять несколько минут..."
> "%APPS%" type nul
set "REG_OUT=%TEMP%\reg_out.tmp"

call :collect_apps "HKLM\Software\Microsoft\Windows\CurrentVersion\Uninstall"
call :collect_apps "HKLM\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"

REM сортировка и удаление дублей
sort "%APPS%" /o "%APPS%.sorted"
for /f "usebackq delims=" %%a in ("%APPS%.sorted") do (
    if not defined _prev set "_prev=%%a"
    if /i not "%%a"=="!_prev!" echo %%a>>"%APPS%.uniq"
    set "_prev=%%a"
)
move /y "%APPS%.uniq" "%APPS%" >nul
del "%APPS%.sorted" 2>nul
set "_prev="

call :log ""
call :log "============================================================"
call :log "1. ПРОВЕРКА БАЗОВОГО ОФИСНОГО ПО"
call :log "============================================================"

set /a BASE_OK=0
set /a BASE_NEED=0
set /a BASE_TOTAL=0

REM Категория: офисный пакет
call :check_category "Офисный пакет" "Office LibreOffice OpenOffice МойОфис" ^
    "Не обнаружен офисный пакет. Для работы с документами рекомендуется установить Microsoft Office, LibreOffice или МойОфис."

REM Категория: браузер
call :check_category "Браузер" "Chrome Firefox Edge Яндекс Yandex" ^
    "Не обнаружен браузер. Для работы с веб-ресурсами рекомендуется установить Google Chrome или Mozilla Firefox."

REM Категория: PDF
call :check_category "Программа для чтения PDF" "Acrobat Foxit SumatraPDF PDF" ^
    "Не обнаружена программа для чтения PDF. Для работы с вложениями рекомендуется установить Adobe Acrobat Reader или SumatraPDF."

REM Категория: архиватор
call :check_category "Архиватор" "7-Zip WinRAR WinZip" ^
    "Не обнаружен архиватор. Для работы с вложениями в почте рекомендуется установить 7-Zip или WinRAR."

REM Категория: антивирус
call :check_category "Антивирус" "Defender Kaspersky ESET Dr.Web" ^
    "Не обнаружен антивирус. Для защиты рабочего места рекомендуется установить корпоративный антивирус или использовать Windows Defender."

call :log ""
call :log "============================================================"
call :log "2. ПРОВЕРКА ИЗЛИШНЕГО ПО (к проверке, а не к удалению!)"
call :log "============================================================"
call :log "Внимание: это рекомендация к проверке, а не указание к удалению."
call :log "Часть программ может быть установлена по согласованию с руководством."
call :log ""

call :find_group "Игровое ПО и игровые платформы" "Steam Epic Games GOG Origin Ubisoft Connect Battle.net Riot game gaming"
call :find_group "Торрент-клиенты и файлообменники" "torrent uTorrent BitTorrent qBittorrent Vuze"
call :find_group "Мессенджеры личного общения (проверить необходимость)" "Discord Telegram WhatsApp Viber Skype"
call :find_group "Развлечения и оформление (проверить необходимость)" "Wallpaper Engine OBS Soundpad"

call :log ""
call :log "============================================================"
call :log "ИТОГ"
call :log "============================================================"
call :log "Проверено категорий базового ПО: !BASE_TOTAL!"
call :log "  в порядке:            !BASE_OK!"
call :log "  требуют внимания:     !BASE_NEED!"
call :log "Отчёт сохранён: %REPORT%"

REM чистка временных файлов
del "%APPS%" 2>nul
del "%REG_OUT%" 2>nul
del "%TMP1%" 2>nul

echo.
echo Готово. Отчёт: %REPORT%
pause
exit /b 0

REM ============================================================
REM :log — Шаг 2. Единая точка вывода на экран и в файл
REM   %~1 — аргумент без кавычек
REM   пустой аргумент печатает пустую строку через echo(
REM ============================================================
:log
setlocal EnableDelayedExpansion
set "MSG=%~1"
echo(!MSG!
>>"%REPORT%" echo(!MSG!
endlocal
exit /b 0

REM ============================================================
REM :collect_apps <ветка реестра>
REM   Сохраняет ТОЛЬКО названия программ (3-я часть строки)
REM ============================================================
:collect_apps
set "BRANCH=%~1"
reg query "%BRANCH%" /s /v DisplayName 2>nul | findstr /i "DisplayName" > "%REG_OUT%"
for /f "tokens=2,*" %%a in ('type "%REG_OUT%"') do (
    set "APP=%%b"
    REM убираем кавычки и префикс REG_SZ если он попал
    set "APP=!APP:REG_SZ=!"
    if not "!APP!"=="" echo !APP!>>"%APPS%"
)
exit /b 0

REM ============================================================
REM :check_category <имя> <признаки через пробел> <текст рекомендации>
REM   Ищет хотя бы один признак в %APPS% без учёта регистра
REM ============================================================
:check_category
setlocal EnableDelayedExpansion
set "CAT=%~1"
set "KEYS=%~2"
set "HINT=%~3"
set "FOUND="
for %%k in (%KEYS%) do (
    if not defined FOUND (
        findstr /i /c:"%%k" "%APPS%" >nul 2>&1 && set "FOUND=%%k"
    )
)
if defined FOUND (
    REM находим фактическое название программы
    for /f "usebackq delims=" %%p in ("%APPS%") do (
        if not defined REALNAME (
            echo %%p | findstr /i /c:"!FOUND!" >nul && set "REALNAME=%%p"
        )
    )
    call :log "  [OK] !CAT!: !REALNAME!"
    endlocal & set /a BASE_OK+=1 & set /a BASE_TOTAL+=1
) else (
    call :log "  [!] !CAT!: !HINT!"
    endlocal & set /a BASE_NEED+=1 & set /a BASE_TOTAL+=1
)
exit /b 0

REM ============================================================
REM :find_group <заголовок группы> <признаки через пробел>
REM   Выводит найденные названия в подраздел отчёта
REM ============================================================
:find_group
setlocal EnableDelayedExpansion
set "GRP=%~1"
set "KEYS=%~2"
set "HITS="
for %%k in (%KEYS%) do (
    findstr /i /c:"%%k" "%APPS%" >nul 2>&1 && (
        for /f "usebackq delims=" %%p in ("%APPS%") do (
            echo %%p | findstr /i /c:"%%k" >nul && (
                echo !HITS! | findstr /i /c:"%%p" >nul || set "HITS=!HITS!;%%p"
            )
        )
    )
)
call :log ""
call :log "--- !GRP! ---"
if defined HITS (
    for %%h in ("!HITS:;=" "!") do (
        if not "%%~h"=="" call :log "  Найдено: %%~h"
    )
) else (
    call :log "  Не найдено — в порядке."
)
endlocal
exit /b 0
