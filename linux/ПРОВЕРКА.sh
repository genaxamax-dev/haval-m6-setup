#!/usr/bin/env bash
# ============================================================================
#  HAVAL M6 — быстрая проверка состояния после установки
# ============================================================================
set -Eeuo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd -- "$HERE"
ADB="$HERE/platform-tools/adb"
PKG="com.aistudio.havalm6launcher.kqtxzn"
LITE_PKG="YandexMusicLite.KorenskoyR"
LISTENER="$PKG/com.example.media.YandexNotificationListener"
RADIO_PKG="com.adayo.ora.radio"

say() { printf '%s\n' "$*"; }
sh_() { "$ADB" shell "$@" 2>/dev/null | tr -d '\r'; }

[ -x "$ADB" ] || { echo "Нет $ADB" >&2; exit 1; }
"$ADB" start-server >/dev/null
"$ADB" wait-for-device

say "== Устройство =="
say "Модель : $(sh_ getprop ro.product.model)"
say "Android: $(sh_ getprop ro.build.version.release) (API $(sh_ getprop ro.build.version.sdk))"
say "Сборка : $(sh_ getprop ro.build.display.id)"
say ""

say "== Приложения =="
LAUNCHER_PATH="$(sh_ "pm path $PKG" || true)"
LITE_PATH="$(sh_ "pm path $LITE_PKG" || true)"
say "Лаунчер: $LAUNCHER_PATH"
say "Lite    : $LITE_PATH"
say ""

say "== Домашний экран =="
sh_ "cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME" | tail -1
say ""

say "== Штатный лаунчер =="
sh_ "dumpsys package com.adayo.launcher" | grep 'User 0:' | head -1 || true
say ""

say "== Радио =="
sh_ "dumpsys package $RADIO_PKG" | grep 'User 0:' | head -1 || true
say ""

say "== Доступ к уведомлениям =="
if sh_ "settings get secure enabled_notification_listeners" | grep -q "$LISTENER"; then
    say "OK: слушатель включён"
else
    say "НЕТ: слушатель не включён"
fi
say ""

say "== Медиасессии =="
sh_ "dumpsys media_session" | grep -E 'package=|active=|state=PlaybackState' | head -30 || true
say ""

say "== Время =="
sh_ "date" || true
say "Зона: $(sh_ getprop persist.sys.timezone)"
say ""

say "== Передний экран =="
sh_ "dumpsys activity activities" | grep -m1 mResumedActivity || true
