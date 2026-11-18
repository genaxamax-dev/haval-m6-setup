#!/usr/bin/env bash
# Установка даты/времени и часового пояса на ГУ Haval M6 (MEK-MX8Q, Android 9).
#
# Почему не `date` и не `hwclock -w`:
#   время диктует MCU автомобиля. Нативный поток mcuCommClient в /system/bin/systemservice
#   раз в 60 секунд вызывает settimeofday() и возвращает часы к значению MCU (2021-01-01 CST).
#   RTC imx_sc_rtc принадлежит MCU, запись в него не сохраняется.
#
# Рабочий путь — вендорский binder-сервис `adayo.setting`
# (com.adayo.midware.settings, AIDL com.adayo.proxy.settings.aidl.ISettingsSvcInterfaceAIDL):
#   транзакция 13 = doDb_TimeZone(mode=0, ["Europe/Moscow"])
#       -> AlarmManager.setTimeZone() + отправка времени в MCU с учётом новой зоны
#   транзакция 18 = doFunc_UpdateDateTime(mode=0, [Y,M,D,h,m,s])
#       -> AlarmManager.setTime() + MCU-команда 0x0402 (set date/time)
# После этого MCU хранит новое время и сам рассылает его каждую минуту.
#
# Требуется root (`adb root`) — сервис системный.
#
# Использование:
#   ./set-time.sh                 # поставить текущее время Europe/Moscow
#   TZ_NAME=Europe/Moscow ./set-time.sh
#   ./set-time.sh --check         # только показать состояние

set -euo pipefail

ADB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/platform-tools/adb"
TZ_NAME="${TZ_NAME:-Europe/Moscow}"

say() { printf '%s\n' "$*"; }
# adb shell иногда подвисает (например, `service list`) — всегда с таймаутом.
dev() { timeout 30 "$ADB" shell "$@" | tr -d '\r'; }

"$ADB" wait-for-device >/dev/null

if [ "${1:-}" = "--check" ]; then
    say "== время =="
    dev 'date; hwclock'
    say "== зона =="
    dev 'getprop persist.sys.timezone'
    say "== сеть =="
    dev 'dumpsys connectivity' | grep -oE 'everValidated\{[a-z]+\} +lastValidated\{[a-z]+\}' | head -1 || true
    exit 0
fi

UID_NOW="$(dev id | cut -d' ' -f1)"
if [ "$UID_NOW" != "uid=0(root)" ]; then
    say "Нужен root. Выполняю: adb root"
    timeout 60 "$ADB" root >/dev/null 2>&1 || true
    sleep 3
    "$ADB" wait-for-device >/dev/null
    UID_NOW="$(dev id | cut -d' ' -f1)"
    [ "$UID_NOW" = "uid=0(root)" ] || { say "Не удалось получить root"; exit 1; }
fi

# Возвращает строку "Result: Parcel(...)"; ошибка, если сервис недоступен.
call_setting() {
    local out
    if ! out="$(timeout 30 "$ADB" shell "service call adayo.setting $*" 2>&1 | tr -d '\r')"; then
        say "Не удалось вызвать adayo.setting (сервис не отвечает)"; exit 1
    fi
    printf '%s\n' "$out"
    case "$out" in
        *"Result: Parcel("*"ffffff"*) say "Сервис вернул ошибку: $out"; exit 2 ;;
        *"Result: Parcel("*) ;;
        *) say "Неожиданный ответ сервиса: $out"; exit 2 ;;
    esac
}

say "== было =="
dev 'date; getprop persist.sys.timezone'

say "== ставим зону $TZ_NAME =="
call_setting 13 i32 0 i32 1 s16 "$TZ_NAME" i32 0

# Ждём, пока framework применит зону, и берём время уже в ней.
sleep 2
read -r Y MO D H MI S <<<"$(TZ="$TZ_NAME" date -d '+5 seconds' '+%Y %-m %-d %-H %-M %S')"
say "== ставим время $Y-$MO-$D $H:$MI:$S ($TZ_NAME) =="
call_setting 18 i32 0 i32 6 s16 "$Y" s16 "$MO" s16 "$D" s16 "$H" s16 "$MI" s16 "$S" i32 0

sleep 3
say "== стало =="
dev 'date; hwclock; getprop persist.sys.timezone'

say "== проверка через 70 с (MCU синхронизирует время раз в минуту) =="
BEFORE="$(dev date)"
sleep 70
AFTER="$(dev date)"
EXPECTED_YEAR="$(TZ="$TZ_NAME" date +%Y)"
say "до:    $BEFORE"
say "после: $AFTER"
case "$AFTER" in
    *"$EXPECTED_YEAR"*) say "OK: время держится." ;;
    *) say "ВНИМАНИЕ: время откатилось — MCU не принял команду."; exit 2 ;;
esac

say "== сеть =="
dev 'dumpsys connectivity' | grep -oE 'everValidated\{[a-z]+\} +lastValidated\{[a-z]+\}' | head -1 || true
