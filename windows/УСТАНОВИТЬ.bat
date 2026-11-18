@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul 2>&1

set "HERE=%~dp0"
if "%HERE:~-1%"=="\" set "HERE=%HERE:~0,-1%"
cd /d "%HERE%"

set "ADB=%HERE%\platform-tools\adb.exe"
set "LAUNCHER_APK=%HERE%\apk\havalm6-launcher.apk"
set "LITE_APK=%HERE%\apk\YandexMusicLite-v1.14.8.apk"

set "PKG=com.aistudio.havalm6launcher.kqtxzn"
set "ACT=%PKG%/com.example.MainActivity"
set "LITE_PKG=YandexMusicLite.KorenskoyR"
set "LISTENER=%PKG%/com.example.media.YandexNotificationListener"
set "RADIO_PKG=com.adayo.ora.radio"
set "STOCK_LAUNCHER=com.adayo.launcher"

if "%TZ_NAME%"=="" set "TZ_NAME=Europe/Moscow"
if "%DO_TIME%"=="" set "DO_TIME=1"

echo ============================================================
echo  HAVAL M6 — установка лаунчера, Yandex Music Lite и настроек
echo ============================================================

if not exist "%ADB%" (echo ОШИБКА: нет %ADB% & exit /b 1)
if not exist "%LAUNCHER_APK%" (echo ОШИБКА: нет %LAUNCHER_APK% & exit /b 1)
if not exist "%LITE_APK%" (echo ОШИБКА: нет %LITE_APK% & exit /b 1)

echo.
echo == 1/7. Проверка ADB и устройства ==
"%ADB%" start-server >nul

set "COUNT=0"
set "SERIAL="
for /f "skip=1 tokens=1,2" %%A in ('"%ADB%" devices') do (
  if "%%B"=="device" (
    set /a COUNT+=1
    set "SERIAL=%%A"
  )
)
if "%COUNT%"=="0" (
  "%ADB%" devices
  echo ОШИБКА: устройство не найдено.
  echo   1^) Включите на ГУ "Отладка по USB".
  echo   2^) Подключите кабель данных ^(не только зарядку^).
  echo   3^) Подтвердите отпечаток RSA на экране ГУ.
  exit /b 1
)
if not "%COUNT%"=="1" (
  echo ОШИБКА: подключено несколько устройств. Оставьте только ГУ.
  "%ADB%" devices -l
  exit /b 1
)

for /f "usebackq delims=" %%i in (`"%ADB%" shell getprop ro.product.model`) do set "MODEL=%%i"
for /f "usebackq delims=" %%i in (`"%ADB%" shell getprop ro.build.version.sdk`) do set "SDK=%%i"
for /f "usebackq delims=" %%i in (`"%ADB%" shell getprop ro.build.display.id`) do set "BUILD=%%i"
echo Устройство: %MODEL% ^| Android API %SDK% ^| %BUILD%
if not "%SDK%"=="28" echo ВНИМАНИЕ: ожидался Android 9 ^(API 28^), получен API %SDK%.
if /I not "%MODEL%"=="MEK-MX8Q" if /I not "%MODEL%"=="mek_8q_car" echo ВНИМАНИЕ: модель не MEK-MX8Q. Продолжаю, но проверьте, что это нужное ГУ.

echo.
echo Будет установлено:
echo   лаунчер : %PKG%
echo   музыка  : %LITE_PKG% ^(Yandex Music Lite^)
echo   радио   : %RADIO_PKG% будет отключено
echo   время   : %TZ_NAME% ^(через adayo.setting^)
echo.
if /I "%CONFIRM%"=="YES" (
  echo Подтверждено через CONFIRM=YES
) else (
  set "ANS="
  set /p "ANS=Установить на это ГУ? Введите YES: "
  if /I not "!ANS!"=="YES" (
    echo Отменено пользователем.
    exit /b 1
  )
)

echo.
echo == 2/7. Root ==
"%ADB%" root >nul 2>&1
timeout /t 2 /nobreak >nul
"%ADB%" wait-for-device
set "ROOTED=0"
for /f "usebackq delims=" %%i in (`"%ADB%" shell id`) do set "IDLINE=%%i"
echo !IDLINE! | findstr /B /C:"uid=0(root)" >nul
if %errorlevel%==0 (
  set "ROOTED=1"
  echo root получен
) else (
  echo ВНИМАНИЕ: root не получен. Установка продолжится, но время может не встать.
)

echo.
echo == 3/7. Установка приложений ==
call :install_apk "%LAUNCHER_APK%" "лаунчер HAVAL M6" || exit /b 1
call :install_apk "%LITE_APK%" "Yandex Music Lite" || exit /b 1
"%ADB%" shell "pm path %PKG%" | findstr /C:"package:" >nul || (echo ОШИБКА: лаунчер не установился & exit /b 1)
"%ADB%" shell "pm path %LITE_PKG%" | findstr /C:"package:" >nul || (echo ОШИБКА: Yandex Music Lite не установился & exit /b 1)
echo Пакеты на месте.

echo.
echo == 4/7. Домашний экран ==
"%ADB%" shell "dumpsys package %PKG%" | findstr /C:"%ACT%" >nul
if errorlevel 1 (
  for /f "usebackq delims=" %%i in (`"%ADB%" shell "dumpsys package %PKG% | grep -oE '%PKG%/[A-Za-z0-9_.]+' | grep -vE 'Receiver|Provider|Service' | head -1"`) do set "ACT=%%i"
  echo Компонент определён: !ACT!
)

"%ADB%" shell "cmd package set-home-activity !ACT!" >nul 2>&1
if %errorlevel%==0 (echo HOME назначен: !ACT!) else (echo ВНИМАНИЕ: cmd package set-home-activity не сработал.)

set "HOME_NOW="
for /f "usebackq delims=" %%i in (`"%ADB%" shell "cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME"`) do set "HOME_NOW=%%i"
echo Сейчас HOME: !HOME_NOW!
echo !HOME_NOW! | findstr /C:"!ACT!" >nul
if %errorlevel%==0 (
  for %%P in (%STOCK_LAUNCHER% org.fossify.home) do (
    "%ADB%" shell "pm list packages %%P" | findstr /C:"package:%%P" >nul
    if !errorlevel!==0 (
      echo Отключаю штатный HOME: %%P
      "%ADB%" shell "pm disable-user --user 0 %%P" >nul 2>&1
      "%ADB%" shell "am force-stop %%P" >nul 2>&1
    )
  )
) else (
  echo ВНИМАНИЕ: HOME не указывает на наш лаунчер. Штатный лаунчер не отключаю.
)

echo.
echo == 5/7. Штатное радио ==
"%ADB%" shell "pm disable-user --user 0 %RADIO_PKG%" >nul 2>&1
"%ADB%" shell "am force-stop %RADIO_PKG%" >nul 2>&1
set "RADIO_STATE="
for /f "usebackq delims=" %%i in (`"%ADB%" shell "dumpsys package %RADIO_PKG% | grep 'User 0:'"`) do set "RADIO_STATE=%%i"
if defined RADIO_STATE (echo Состояние: !RADIO_STATE!) else (echo Состояние: пакет не найден)

echo.
echo == 6/7. Доступ к уведомлениям ==
set "LISTENER_OK=0"
"%ADB%" shell "cmd notification allow_listener %LISTENER%" >nul 2>&1
if %errorlevel%==0 set "LISTENER_OK=1"
if "%LISTENER_OK%"=="0" (
  for /f "usebackq delims=" %%i in (`"%ADB%" shell settings get secure enabled_notification_listeners`) do set "CUR=%%i"
  echo !CUR! | findstr /C:"%LISTENER%" >nul
  if !errorlevel!==0 (
    set "LISTENER_OK=1"
  ) else (
    if "!CUR!"=="" (set "NEW=%LISTENER%") else if "!CUR!"=="null" (set "NEW=%LISTENER%") else (set "NEW=!CUR!:%LISTENER%")
    "%ADB%" shell "settings put secure enabled_notification_listeners !NEW!" >nul 2>&1
    if !errorlevel!==0 set "LISTENER_OK=1"
  )
)
timeout /t 1 /nobreak >nul
for /f "usebackq delims=" %%i in (`"%ADB%" shell settings get secure enabled_notification_listeners`) do set "NLCHK=%%i"
echo !NLCHK! | findstr /C:"%LISTENER%" >nul
if %errorlevel%==0 (
  echo OK: доступ к уведомлениям включён.
) else (
  echo ВНИМАНИЕ: не удалось включить доступ к уведомлениям автоматически.
  echo Включите вручную: Настройки -^> Приложения -^> Специальный доступ -^> Доступ к уведомлениям.
)

echo.
echo == 7/7. Время и часовой пояс ==
if not "%DO_TIME%"=="1" (
  echo Пропущено ^(DO_TIME=0^).
) else if not "%ROOTED%"=="1" (
  echo Пропущено: без root время не поставить. Запустите позже: set-time.bat
) else (
  echo Ставлю %TZ_NAME%. Проверка занимает около 80 секунд, не закрывайте окно.
  call "%HERE%\set-time.bat"
  if errorlevel 1 (
    echo ВНИМАНИЕ: не удалось установить время. Повторите позже: set-time.bat
  ) else (
    echo OK: время и зона установлены.
  )
)

echo.
echo == Запуск лаунчера ==
"%ADB%" shell "am start -n !ACT!" >nul 2>&1
timeout /t 3 /nobreak >nul
"%ADB%" shell "dumpsys activity activities | grep -m1 mResumedActivity"

echo.
echo ============================================================
echo  ГОТОВО
echo ============================================================
echo Лаунчер : %PKG%
echo Музыка  : %LITE_PKG%
echo Радио   : отключено
echo HOME    : !ACT!
echo.
echo Перезагрузка НЕ выполнялась.
echo Откат: ОТКАТ.bat
echo ============================================================
endlocal
exit /b 0

:install_apk
set "APKFILE=%~1"
set "APKNAME=%~2"
echo.
echo == Установка: %APKNAME% ==
"%ADB%" shell "service call package 195 i32 1" > "%TEMP%\hm6_filter.txt"
set "FR="
for /f "usebackq delims=" %%i in (`type "%TEMP%\hm6_filter.txt"`) do if not defined FR set "FR=%%i"
echo !FR! | findstr /B /C:"Result:" >nul
if errorlevel 1 (
  echo ОШИБКА: не удалось снять фильтр установки Adayo: !FR!
  exit /b 1
)
"%ADB%" install -r -g "%APKFILE%"
if errorlevel 1 (
  echo ОШИБКА: установка %APKNAME% не удалась
  exit /b 1
)
exit /b 0
