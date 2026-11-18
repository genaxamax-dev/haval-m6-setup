@echo off
setlocal EnableExtensions
chcp 65001 >nul 2>&1

set "HERE=%~dp0"
if "%HERE:~-1%"=="\" set "HERE=%HERE:~0,-1%"
set "ADB=%HERE%\platform-tools\adb.exe"
if "%TZ_NAME%"=="" set "TZ_NAME=Europe/Moscow"

if not exist "%ADB%" (
  echo ОШИБКА: не найден %ADB%
  exit /b 1
)

"%ADB%" wait-for-device >nul

if /I "%~1"=="--check" goto :check

echo == Проверка root ==
for /f "usebackq delims=" %%i in (`"%ADB%" shell id`) do set "IDLINE=%%i"
echo %IDLINE% | findstr /B /C:"uid=0(root)" >nul
if errorlevel 1 (
  echo Нужен root. Выполняю: adb root
  "%ADB%" root >nul 2>&1
  timeout /t 3 /nobreak >nul
  "%ADB%" wait-for-device >nul
  for /f "usebackq delims=" %%i in (`"%ADB%" shell id`) do set "IDLINE=%%i"
  echo %IDLINE% | findstr /B /C:"uid=0(root)" >nul
  if errorlevel 1 (
    echo ОШИБКА: не удалось получить root
    exit /b 1
  )
)
echo %IDLINE%

echo == Было ==
"%ADB%" shell "date; getprop persist.sys.timezone"

echo == Ставим зону %TZ_NAME% ==
"%ADB%" shell "service call adayo.setting 13 i32 0 i32 1 s16 \"%TZ_NAME%\" i32 0" > "%TEMP%\hm6_tz.txt"
type "%TEMP%\hm6_tz.txt"
findstr /C:"Result: Parcel" "%TEMP%\hm6_tz.txt" >nul || (echo ОШИБКА: не получен ответ сервиса & exit /b 2)
findstr /C:"ffffff" "%TEMP%\hm6_tz.txt" >nul && (echo ОШИБКА: сервис вернул ошибку & exit /b 2)

timeout /t 2 /nobreak >nul

for /f "usebackq delims=" %%i in (`powershell -NoProfile -Command "$tz='%TZ_NAME%'; $id=$tz; if($tz -eq 'Europe/Moscow'){ $id='Russian Standard Time' }; $z=$null; try { $z=[System.TimeZoneInfo]::FindSystemTimeZoneById($id) } catch { try { $z=[System.TimeZoneInfo]::FindSystemTimeZoneById($tz) } catch { $z=[System.TimeZoneInfo]::Local } }; $t=[System.TimeZoneInfo]::ConvertTimeFromUtc((Get-Date).ToUniversalTime().AddSeconds(5),$z); $t.ToString('yyyy M d H m s')"`) do set "PARTS=%%i"
if not defined PARTS (
  echo ОШИБКА: не удалось вычислить время
  exit /b 2
)
for /f "tokens=1-6" %%a in ("%PARTS%") do (
  set "Y=%%a" & set "MO=%%b" & set "D=%%c" & set "H=%%d" & set "MI=%%e" & set "S=%%f"
)

echo == Ставим время %Y%-%MO%-%D% %H%:%MI%:%S% (%TZ_NAME%) ==
"%ADB%" shell "service call adayo.setting 18 i32 0 i32 6 s16 \"%Y%\" s16 \"%MO%\" s16 \"%D%\" s16 \"%H%\" s16 \"%MI%\" s16 \"%S%\" i32 0" > "%TEMP%\hm6_time.txt"
type "%TEMP%\hm6_time.txt"
findstr /C:"Result: Parcel" "%TEMP%\hm6_time.txt" >nul || (echo ОШИБКА: не получен ответ сервиса & exit /b 2)
findstr /C:"ffffff" "%TEMP%\hm6_time.txt" >nul && (echo ОШИБКА: сервис вернул ошибку & exit /b 2)

timeout /t 3 /nobreak >nul
echo == Стало ==
"%ADB%" shell "date; hwclock; getprop persist.sys.timezone"

echo == Проверка через 70 с (MCU синхронизирует время раз в минуту) ==
for /f "usebackq delims=" %%i in (`"%ADB%" shell date`) do echo до:    %%i
timeout /t 70 /nobreak >nul
for /f "usebackq delims=" %%i in (`"%ADB%" shell date`) do set "AFTER=%%i"
echo после: %AFTER%
echo %AFTER% | findstr /C:"%Y%" >nul
if errorlevel 1 (
  echo ВНИМАНИЕ: время откатилось — MCU не принял команду.
  exit /b 2
) else (
  echo OK: время держится.
)
exit /b 0

:check
echo == Время ==
"%ADB%" shell "date; hwclock"
echo == Зона ==
"%ADB%" shell "getprop persist.sys.timezone"
echo == Сеть ==
"%ADB%" shell "dumpsys connectivity | grep -oE 'everValidated\{[a-z]+\} +lastValidated\{[a-z]+\}' | head -1"
exit /b 0
