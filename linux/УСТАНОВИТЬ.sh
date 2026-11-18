#!/usr/bin/env bash
# ============================================================================
#  HAVAL M6 (Adayo / mek_8q_car, Android 9) — установка всего за один запуск
# ============================================================================
#  Что делает:
#    1. проверяет ADB и головное устройство;
#    2. ставит лаунчер HAVAL M6 (в обход фильтра установки Adayo);
#    3. ставит Yandex Music Lite;
#    4. назначает лаунчер домашним экраном и отключает штатный;
#    5. отключает штатное FM/AM-радио;
#    6. включает доступ лаунчера к уведомлениям (метаданные трека);
#    7. ставит часовой пояс и время через вендорский сервис adayo.setting.
#
#  Автозапуск Lite уже встроен в лаунчер: после загрузки ГУ он открывается
#  через 2 секунды после события Adayo.
#
#  Ничего не прошивает, не перемонтирует разделы и НЕ перезагружает ГУ.
#
#  Использование:
#      ./УСТАНОВИТЬ.sh
#      CONFIRM=YES ./УСТАНОВИТЬ.sh      # без вопроса подтверждения
#      DO_TIME=0 ./УСТАНОВИТЬ.sh        # не трогать время
#      TZ_NAME=Europe/Moscow ./УСТАНОВИТЬ.sh
#
#  Откат: ./ОТКАТ.sh
# ============================================================================

set -Eeuo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd -- "$HERE"

ADB="$HERE/platform-tools/adb"
LAUNCHER_APK="$HERE/apk/havalm6-launcher.apk"
LITE_APK="$HERE/apk/YandexMusicLite-v1.14.8.apk"

PKG="com.aistudio.havalm6launcher.kqtxzn"
ACT="$PKG/com.example.MainActivity"
LITE_PKG="YandexMusicLite.KorenskoyR"
LISTENER="$PKG/com.example.media.YandexNotificationListener"
RADIO_PKG="com.adayo.ora.radio"
STOCK_LAUNCHER="com.adayo.launcher"

TZ_NAME="${TZ_NAME:-Europe/Moscow}"
DO_TIME="${DO_TIME:-1}"

die() { printf '\nОШИБКА: %s\n' "$*" >&2; exit 1; }
say() { printf '%s\n' "$*"; }
sh_() { "$ADB" shell "$@" | tr -d '\r'; }

# ---------------------------------------------------------------------------
say "============================================================"
say " HAVAL M6 — установка лаунчера, Yandex Music Lite и настроек"
say "============================================================"

[ -x "$ADB" ]           || die "нет $ADB (папка platform-tools повреждена)"
[ -f "$LAUNCHER_APK" ]  || die "нет $LAUNCHER_APK"
[ -f "$LITE_APK" ]      || die "нет $LITE_APK"
[ -f "$HERE/set-time.sh" ] || die "нет $HERE/set-time.sh"

say ""
say "== 1/7. Проверка ADB и устройства =="
"$ADB" start-server >/dev/null

mapfile -t DEV < <("$ADB" devices | awk 'NR>1 && $2=="device"{print $1}')
if [ "${#DEV[@]}" -eq 0 ]; then
    "$ADB" devices
    die "устройство не найдено.
  1) Включите на ГУ «Отладка по USB».
  2) Подключите кабель данных (не только зарядку).
  3) Подтвердите отпечаток RSA на экране ГУ.
  4) Проверьте: $ADB devices"
fi
if [ "${#DEV[@]}" -gt 1 ]; then
    die "подключено несколько устройств: ${DEV[*]}
  Оставьте только ГУ или задайте ANDROID_SERIAL."
fi

MODEL="$(sh_ getprop ro.product.model)"
SDK="$(sh_ getprop ro.build.version.sdk)"
BUILD="$(sh_ getprop ro.build.display.id)"
say "Устройство: $MODEL | Android API $SDK | $BUILD"
[ "$SDK" = "28" ] || say "ВНИМАНИЕ: ожидался Android 9 (API 28), получен API $SDK."
case "$MODEL" in
    MEK-MX8Q|mek_8q_car) ;;
    *) say "ВНИМАНИЕ: модель не MEK-MX8Q. Продолжаю, но проверьте, что это нужное ГУ." ;;
esac

say ""
say "Будет установлено:"
say "  лаунчер : $PKG"
say "  музыка  : $LITE_PKG (Yandex Music Lite)"
say "  радио   : $RADIO_PKG будет отключено"
say "  время   : $TZ_NAME (через adayo.setting)"
say ""
if [ "${CONFIRM:-}" = "YES" ]; then
    say "Подтверждено через CONFIRM=YES"
else
    read -r -p "Установить на это ГУ? Введите YES: " answer || answer=""
    [ "$answer" = "YES" ] || die "отменено пользователем"
fi

# ---------------------------------------------------------------------------
say ""
say "== 2/7. Root (нужен для времени и назначения HOME) =="
"$ADB" root >/dev/null 2>&1 || true
sleep 2
"$ADB" wait-for-device
ROOTED=0
if [ "$(sh_ id | cut -d' ' -f1)" = "uid=0(root)" ]; then
    ROOTED=1
    say "root получен"
else
    say "ВНИМАНИЕ: root не получен. Установка продолжится, но время может не встать."
fi

# ---------------------------------------------------------------------------
install_apk() {
    local apk="$1" name="$2" r
    say ""
    say "== Установка: $name =="
    r="$(sh_ "service call package 195 i32 1")"
    case "$r" in
        Result:*) ;;
        *) die "не удалось снять фильтр установки Adayo: $r" ;;
    esac
    "$ADB" install -r -g "$apk"
}

say ""
say "== 3/7. Установка приложений =="
install_apk "$LAUNCHER_APK" "лаунчер HAVAL M6"
install_apk "$LITE_APK" "Yandex Music Lite"

sh_ "pm path $PKG" | grep -q . || die "лаунчер не установился"
sh_ "pm path $LITE_PKG" | grep -q . || die "Yandex Music Lite не установился"
say "Пакеты на месте."

# ---------------------------------------------------------------------------
say ""
say "== 4/7. Домашний экран =="
# На случай другой сборки: если ожидаемого класса нет, ищем activity в dumpsys.
if ! sh_ "dumpsys package $PKG" | grep -q "$ACT"; then
    FOUND="$(sh_ "dumpsys package $PKG" | grep -oE "$PKG/[A-Za-z0-9_.]+" | grep -vE 'Receiver|Provider|Service' | head -1)"
    case "$FOUND" in
        "$PKG"/*) ACT="$FOUND"; say "Компонент определён: $ACT" ;;
        *) die "не удалось найти activity лаунчера в $PKG" ;;
    esac
fi

if sh_ "cmd package set-home-activity $ACT" >/dev/null 2>&1; then
    say "HOME назначен: $ACT"
else
    say "ВНИМАНИЕ: cmd package set-home-activity не сработал."
fi

HOME_NOW="$(sh_ "cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME" | tail -1)"
say "Сейчас HOME: $HOME_NOW"
case "$HOME_NOW" in
    *"$ACT"*)
        # Штатный лаунчер отключаем только после успешного назначения нашего,
        # чтобы ГУ не осталось без домашнего экрана.
        for p in "$STOCK_LAUNCHER" "org.fossify.home"; do
            if sh_ "pm list packages $p" | grep -q "^package:$p$"; then
                say "Отключаю штатный HOME: $p"
                sh_ "pm disable-user --user 0 $p" >/dev/null 2>&1 || say "  (не удалось, возможно уже отключён)"
                sh_ "am force-stop $p" >/dev/null 2>&1 || true
            fi
        done
        ;;
    *)
        say "ВНИМАНИЕ: HOME не указывает на наш лаунчер. Штатный лаунчер не отключаю."
        ;;
esac

# ---------------------------------------------------------------------------
say ""
say "== 5/7. Штатное радио =="
sh_ "pm disable-user --user 0 $RADIO_PKG" >/dev/null 2>&1 || true
sh_ "am force-stop $RADIO_PKG" >/dev/null 2>&1 || true
RADIO_STATE="$(sh_ "dumpsys package $RADIO_PKG" | grep 'User 0:' | head -1)"
say "Состояние: ${RADIO_STATE:-пакет не найден}"
case "$RADIO_STATE" in
    *enabled=2*|*enabled=3*) say "OK: радио отключено для пользователя 0." ;;
    *enabled=0*) say "OK: радио уже было отключено." ;;
    *) say "ВНИМАНИЕ: не удалось подтвердить отключение радио." ;;
esac

# ---------------------------------------------------------------------------
say ""
say "== 6/7. Доступ к уведомлениям (метаданные трека) =="
LISTENER_OK=0
if sh_ "cmd notification allow_listener $LISTENER" >/dev/null 2>&1; then
    LISTENER_OK=1
else
    CUR="$(sh_ "settings get secure enabled_notification_listeners")"
    case "$CUR" in
        *"$LISTENER"*) LISTENER_OK=1 ;;
        *)
            case "$CUR" in
                ""|"null") NEW="$LISTENER" ;;
                *) NEW="$CUR:$LISTENER" ;;
            esac
            if sh_ "settings put secure enabled_notification_listeners $NEW" >/dev/null 2>&1; then
                LISTENER_OK=1
            fi
            ;;
    esac
fi
sleep 1
if [ "$LISTENER_OK" = "1" ] && sh_ "settings get secure enabled_notification_listeners" | grep -q "$LISTENER"; then
    say "OK: доступ к уведомлениям включён."
else
    say "ВНИМАНИЕ: не удалось включить доступ к уведомлениям автоматически."
    say "Включите вручную: Настройки → Приложения → Специальный доступ → Доступ к уведомлениям."
fi

# ---------------------------------------------------------------------------
say ""
say "== 7/7. Время и часовой пояс =="
if [ "$DO_TIME" != "1" ]; then
    say "Пропущено (DO_TIME=0)."
elif [ "$ROOTED" != "1" ]; then
    say "Пропущено: без root время не поставить. Запустите позже: ./set-time.sh"
else
    say "Ставлю $TZ_NAME. Проверка занимает около 80 секунд, не закрывайте окно."
    if TZ_NAME="$TZ_NAME" "$HERE/set-time.sh"; then
        say "OK: время и зона установлены."
    else
        say "ВНИМАНИЕ: не удалось установить время."
        say "Повторите позже: ./set-time.sh"
    fi
fi

# ---------------------------------------------------------------------------
say ""
say "== Запуск лаунчера =="
sh_ "am start -n $ACT" >/dev/null 2>&1 || true
sleep 3
sh_ "dumpsys activity activities | grep -m1 mResumedActivity" || true

say ""
say "============================================================"
say " ГОТОВО"
say "============================================================"
say "Лаунчер : $PKG"
say "Музыка  : $LITE_PKG"
say "Радио   : отключено (вернуть: adb shell pm enable $RADIO_PKG)"
say "HOME    : $ACT"
say ""
say "Автозапуск Lite встроен в лаунчер:"
say "  после загрузки ГУ — через 2 с после события Adayo."
say ""
say "Перезагрузка НЕ выполнялась. Для проверки автозапуска"
say "можно перезагрузить ГУ вручную."
say ""
say "Если после полного отключения питания ГУ снова показывает"
say "неверное время — запустите:  ./set-time.sh"
say ""
say "Полный откат:  ./ОТКАТ.sh"
say "============================================================"
