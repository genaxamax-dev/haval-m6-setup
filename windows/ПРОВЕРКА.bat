@echo off
setlocal EnableExtensions
chcp 65001 >nul 2>&1

set "HERE=%~dp0"
if "%HERE:~-1%"=="\" set "HERE=%HERE:~0,-1%"
set "ADB=%HERE%\platform-tools\adb.exe"
set "PKG=com.aistudio.havalm6launcher.kqtxzn"
set "LITE_PKG=YandexMusicLite.KorenskoyR"
set "LISTENER=%PKG%/com.example.media.YandexNotificationListener"
set "RADIO_PKG=com.adayo.ora.radio"

if not exist "%ADB%" (
  echo ОШИБКА: не найден %ADB%
  exit /b 1
)

"%ADB%" start-server >nul
"%ADB%" wait-for-device

echo == Устройство ==
for /f "usebackq delims=" %%i in (`"%ADB%" shell getprop ro.product.model`) do set "MODEL=%%i"
for /f "usebackq delims=" %%i in (`"%ADB%" shell getprop ro.build.version.release`) do set "REL=%%i"
for /f "usebackq delims=" %%i in (`"%ADB%" shell getprop ro.build.version.sdk`) do set "SDK=%%i"
for /f "usebackq delims=" %%i in (`"%ADB%" shell getprop ro.build.display.id`) do set "BUILD=%%i"
echo Модель : %MODEL%
echo Android: %REL% (API %SDK%)
echo Сборка : %BUILD%
echo.

echo == Приложения ==
for /f "usebackq delims=" %%i in (`"%ADB%" shell pm path %PKG%`) do echo Лаунчер: %%i
for /f "usebackq delims=" %%i in (`"%ADB%" shell pm path %LITE_PKG%`) do echo Lite    : %%i
echo.

echo == Домашний экран ==
"%ADB%" shell "cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME"
echo.

echo == Штатный лаунчер ==
"%ADB%" shell "dumpsys package com.adayo.launcher | grep 'User 0:'"
echo.

echo == Радио ==
"%ADB%" shell "dumpsys package %RADIO_PKG% | grep 'User 0:'"
echo.

echo == Доступ к уведомлениям ==
set "NL="
for /f "usebackq delims=" %%i in (`"%ADB%" shell settings get secure enabled_notification_listeners`) do set "NL=%%i"
echo %NL% | findstr /C:"%LISTENER%" >nul
if %errorlevel%==0 (echo OK: слушатель включён) else (echo НЕТ: слушатель не включён)
echo.

echo == Время ==
"%ADB%" shell date
for /f "usebackq delims=" %%i in (`"%ADB%" shell getprop persist.sys.timezone`) do echo Зона: %%i
echo.

echo == Передний экран ==
"%ADB%" shell "dumpsys activity activities | grep -m1 mResumedActivity"
echo.

endlocal
exit /b 0
