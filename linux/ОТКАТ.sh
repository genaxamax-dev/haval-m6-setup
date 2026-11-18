#!/usr/bin/env bash
# ============================================================================
#  HAVAL M6 — откат установки
# ============================================================================
#  Возвращает штатный домашний экран и радио.
#  По умолчанию приложения НЕ удаляет — их можно удалить вручную или так:
#
#      FULL=1 ./ОТКАТ.sh
#
#  Время/зону откат не трогает.
# ============================================================================

set -Eeuo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd -- "$HERE"

ADB="$HERE/platform-tools/adb"
PKG="com.aistudio.havalm6launcher.kqtxzn"
LITE_PKG="YandexMusicLite.KorenskoyR"
LISTENER="$PKG/com.example.media.YandexNotificationListener"
RADIO_PKG="com.adayo.ora.radio"
STOCK_LAUNCHER="com.adayo.launcher"
STOCK_ACT="$STOCK_LAUNCHER/.ui.Launcher_MainActivity"
FULL="${FULL:-0}"

die() { printf '\nОШИБКА: %s\n' "$*" >&2; exit 1; }
say() { printf '%s\n' "$*"; }
sh_() { "$ADB" shell "$@" | tr -d '\r'; }

[ -x "$ADB" ] || die "нет $ADB"

say "== Проверка устройства =="
"$ADB" start-server >/dev/null
"$ADB" wait-for-device
mapfile -t DEV < <("$ADB" devices | awk 'NR>1 && $2=="device"{print $1}')
[ "${#DEV[@]}" -gt 0 ] || die "устройство не найдено"
say "Устройство: $(sh_ getprop ro.product.model)"

if [ "${CONFIRM:-}" != "YES" ]; then
    say ""
    say "Будет возвращено:"
    say "  - штатный лаунчер $STOCK_LAUNCHER как HOME;"
    say "  - штатное радио $RADIO_PKG;"
    say "  - доступ к уведомлениям у нашего лаунчера будет снят."
    if [ "$FULL" = "1" ]; then
        say "  - приложения $PKG и $LITE_PKG будут УДАЛЕНЫ."
    else
        say "  - приложения останутся установленными (FULL=1 — удалить)."
    fi
    read -r -p "Продолжить? Введите YES: " answer || answer=""
    [ "$answer" = "YES" ] || die "отменено пользователем"
fi

"$ADB" root >/dev/null 2>&1 || true
sleep 2
"$ADB" wait-for-device

say ""
say "== Возврат штатного лаунчера =="
STOCK_OK=0
if sh_ "pm list packages $STOCK_LAUNCHER" | grep -q "^package:$STOCK_LAUNCHER$"; then
    sh_ "pm enable $STOCK_LAUNCHER" >/dev/null 2>&1 || true
    if ! sh_ "dumpsys package $STOCK_LAUNCHER" | grep -q "$STOCK_ACT"; then
        FOUND="$(sh_ "dumpsys package $STOCK_LAUNCHER" | grep -oE "$STOCK_LAUNCHER/[A-Za-z0-9_.]+" | grep -vE 'Receiver|Provider|Service' | head -1)"
        case "$FOUND" in "$STOCK_LAUNCHER"/*) STOCK_ACT="$FOUND" ;; esac
    fi
    sh_ "cmd package set-home-activity $STOCK_ACT" >/dev/null 2>&1 || true
    say "HOME: $STOCK_ACT"
    STOCK_OK=1
else
    say "Штатный лаунчер не найден — HOME не меняю."
fi

say ""
say "== Возврат радио =="
sh_ "pm enable $RADIO_PKG" >/dev/null 2>&1 || true
say "Состояние: $(sh_ "dumpsys package $RADIO_PKG" | grep 'User 0:' | head -1)"

say ""
say "== Снятие доступа к уведомлениям =="
sh_ "cmd notification disallow_listener $LISTENER" >/dev/null 2>&1 || true
say "Готово."

if [ "$FULL" = "1" ]; then
    say ""
    say "== Удаление приложений =="
    if [ "$STOCK_OK" != "1" ]; then
        die "штатный лаунчер не найден — не удаляю наш, чтобы ГУ не осталось без HOME"
    fi
    sh_ "am force-stop $PKG" >/dev/null 2>&1 || true
    sh_ "am force-stop $LITE_PKG" >/dev/null 2>&1 || true
    "$ADB" uninstall "$PKG" || say "  не удалось удалить $PKG"
    "$ADB" uninstall "$LITE_PKG" || say "  не удалось удалить $LITE_PKG"
fi

say ""
say "== Запуск домашнего экрана =="
sh_ "input keyevent KEYCODE_HOME" >/dev/null 2>&1 || true
sleep 2
sh_ "dumpsys activity activities | grep -m1 mResumedActivity" || true

say ""
say "Откат выполнен. Время и часовой пояс не менялись."
