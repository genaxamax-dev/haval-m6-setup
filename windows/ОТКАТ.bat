@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul 2>&1

set "HERE=%~dp0"
if "%HERE:~-1%"=="\" set "HERE=%HERE:~0,-1%"
set "ADB=%HERE%\platform-tools\adb.exe"
set "PKG=com.aistudio.havalm6launcher.kqtxzn"
set "LITE_PKG=YandexMusicLite.KorenskoyR"
set "LISTENER=%PKG%/com.example.media.YandexNotificationListener"
set "RADIO_PKG=com.adayo.ora.radio"
set "STOCK_LAUNCHER=com.adayo.launcher"
set "STOCK_ACT=%STOCK_LAUNCHER%/.ui.Launcher_MainActivity"
if "%FULL%"=="" set "FULL=0"

if not exist "%ADB%" (
  echo ОШИБКА: не найден %ADB%
  exit /b 1
)

echo == Проверка устройства ==
"%ADB%" start-server >nul
"%ADB%" wait-for-device
for /f "usebackq delims=" %%i in (`"%ADB%" shell getprop ro.product.model`) do echo Устройство: %%i

if /I not "%CONFIRM%"=="YES" (
  echo.
  echo Будет возвращено:
  echo   - штатный лаунчер %STOCK_LAUNCHER% как HOME;
  echo   - штатное радио %RADIO_PKG%;
  echo   - доступ к уведомлениям у нашего лаунчера будет снят.
  if "%FULL%"=="1" (
    echo   - приложения %PKG% и %LITE_PKG% будут УДАЛЕНЫ.
  ) else (
    echo   - приложения останутся установленными ^(FULL=1 — удалить^).
  )
  set /p "ANS=Продолжить? Введите YES: "
  if /I not "!ANS!"=="YES" (
    echo Отменено пользователем.
    exit /b 1
  )
)

"%ADB%" root >nul 2>&1
timeout /t 2 /nobreak >nul
"%ADB%" wait-for-device

echo.
echo == Возврат штатного лаунчера ==
set "STOCK_OK=0"
"%ADB%" shell "pm list packages %STOCK_LAUNCHER%" | findstr /C:"package:%STOCK_LAUNCHER%" >nul
if %errorlevel%==0 (
  "%ADB%" shell "pm enable %STOCK_LAUNCHER%" >nul 2>&1
  "%ADB%" shell "dumpsys package %STOCK_LAUNCHER%" | findstr /C:"%STOCK_ACT%" >nul
  if errorlevel 1 (
    for /f "usebackq delims=" %%i in (`"%ADB%" shell "dumpsys package %STOCK_LAUNCHER% | grep -oE '%STOCK_LAUNCHER%/[A-Za-z0-9_.]+' | grep -vE 'Receiver|Provider|Service' | head -1"`) do set "STOCK_ACT=%%i"
  )
  "%ADB%" shell "cmd package set-home-activity %STOCK_ACT%" >nul 2>&1
  echo HOME: %STOCK_ACT%
  set "STOCK_OK=1"
) else (
  echo Штатный лаунчер не найден — HOME не меняю.
)

echo.
echo == Возврат радио ==
"%ADB%" shell "pm enable %RADIO_PKG%" >nul 2>&1
for /f "usebackq delims=" %%i in (`"%ADB%" shell "dumpsys package %RADIO_PKG% | grep 'User 0:'"`) do echo Состояние: %%i

echo.
echo == Снятие доступа к уведомлениям ==
"%ADB%" shell "cmd notification disallow_listener %LISTENER%" >nul 2>&1
echo Готово.

if "%FULL%"=="1" (
  echo.
  echo == Удаление приложений ==
  if not "%STOCK_OK%"=="1" (
    echo ОШИБКА: штатный лаунчер не найден — не удаляю наш, чтобы ГУ не осталось без HOME
    exit /b 1
  )
  "%ADB%" shell "am force-stop %PKG%" >nul 2>&1
  "%ADB%" shell "am force-stop %LITE_PKG%" >nul 2>&1
  "%ADB%" uninstall "%PKG%" || echo   не удалось удалить %PKG%
  "%ADB%" uninstall "%LITE_PKG%" || echo   не удалось удалить %LITE_PKG%
)

echo.
echo == Запуск домашнего экрана ==
"%ADB%" shell "input keyevent KEYCODE_HOME" >nul 2>&1
timeout /t 2 /nobreak >nul
"%ADB%" shell "dumpsys activity activities | grep -m1 mResumedActivity"

echo.
echo Откат выполнен. Время и часовой пояс не менялись.
endlocal
exit /b 0
