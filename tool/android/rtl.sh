#!/usr/bin/env bash
#
# Flip a booted Android emulator between Arabic (RTL) and English (LTR).
#
#   ./tool/android/rtl.sh ar [serial]
#   ./tool/android/rtl.sh en [serial]
#
# Why the device locale and not just the in-app switcher: the app persists
# its own locale (loadPersistedLocale in lib/main.dart, supportedLocales
# en/ar), so the in-app toggle covers the returning-user path. It does NOT
# cover a FRESH INSTALL on an Arabic phone, which is what most of this app's
# real users are - that path resolves against the system locale before any
# preference exists, and is where a first-run layout bug would hide.
#
# Also flips Android's own force-RTL developer setting, which mirrors the
# system UI (dialogs, permission prompts, the notification shade) so a
# screenshot shows what a real Arabic user sees around the app, not just
# inside it.
set -euo pipefail

export ANDROID_HOME="${ANDROID_HOME:-/opt/homebrew/share/android-commandlinetools}"
export PATH="$ANDROID_HOME/platform-tools:$PATH"

LANG_ARG="${1:-ar}"
SERIAL_ARG="${2:-}"
ADB=(adb)
[ -n "$SERIAL_ARG" ] && ADB=(adb -s "$SERIAL_ARG")

case "$LANG_ARG" in
  ar) LOCALE="ar-BH"; RTL=1 ;;
  en) LOCALE="en-US"; RTL=0 ;;
  *)  echo "usage: $0 {ar|en} [serial]" >&2; exit 1 ;;
esac

echo "==> setting locale to $LOCALE (force_rtl=$RTL)"
"${ADB[@]}" shell settings put global debug.force_rtl "$RTL" >/dev/null
# persist.sys.locale needs the framework restarted to take effect. On an
# emulator image `adb root` succeeds; on a Play Store image it does not, so
# fall back to leaving force_rtl doing the visual half of the job.
if "${ADB[@]}" root >/dev/null 2>&1; then
  "${ADB[@]}" shell "setprop persist.sys.locale $LOCALE" >/dev/null 2>&1 || true
  "${ADB[@]}" shell "setprop ctl.restart zygote" >/dev/null 2>&1 || true
  echo "    system locale set; framework restarting (give it ~20s)"
else
  echo "    note: this image does not allow adb root (Play Store image)."
  echo "    force_rtl is applied; set the language in Settings > System >"
  echo "    Languages, or use the app's own language switcher, for a full test."
fi
