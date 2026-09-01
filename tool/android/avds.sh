#!/usr/bin/env bash
#
# Create the GrowDaily Android test device matrix.
#
#   ./tool/android/avds.sh create   # make the AVDs (idempotent)
#   ./tool/android/avds.sh list     # show them
#   ./tool/android/avds.sh delete   # tear them down
#
# Four devices, each chosen because it exercises a DIFFERENT Android
# behaviour this app depends on, not just a different screen size:
#
#   gd_api28_phone   Android 9, API 28 - the low end. Pre-13, so
#                    notifications need no runtime permission: exercises the
#                    branch where requestNotificationsPermission() returns
#                    null and NotificationService falls back to its cached
#                    answer.
#                    NOT API 24: Android 7.x arm64 images will not boot on
#                    Apple Silicon (three attempts, all crashed), which is
#                    part of why minSdk was raised to 26 - see
#                    android/app/build.gradle.kts.
#   gd_api33_phone   Android 13, API 33 - the POST_NOTIFICATIONS boundary.
#                    The single most important device for this app: every
#                    habit and prayer reminder depends on that runtime grant.
#   gd_api36_phone   Android 16, API 36 - the targetSdk. Newest behaviour
#                    changes, predictive back, and the strictest policy.
#   gd_api35_tablet  Android 15 tablet - large-screen layout, and the one
#                    device where a phone-shaped layout will visibly break.
#
# Arabic/RTL is not a separate AVD: it is a per-device setting, applied by
# tool/android/rtl.sh once a device is booted, since every one of these
# needs checking in both directions.
# Boot these ONE AT A TIME. Each emulator wants ~5GB and the tooling only
# warns ("Software GL rendering will be used due to system memory pressure")
# before failing in confusing ways - a second emulator alongside a Gradle
# build cost one device its `activity` system service mid-session, and
# crashed several others outright at boot.
set -euo pipefail

export JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home}"
export ANDROID_HOME="${ANDROID_HOME:-/opt/homebrew/share/android-commandlinetools}"
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"
# sdkmanager/avdmanager's table formatter throws
# UnknownFormatConversionException under an Arabic system locale (this Mac is
# ar-BH), so force an English locale for the Java tools only.
export JAVA_TOOL_OPTIONS="-Duser.language=en -Duser.country=US"

AVDM="$ANDROID_HOME/cmdline-tools/latest/bin/avdmanager"

# name | system image | device profile
DEVICES=(
  "gd_api28_phone|system-images;android-28;google_apis;arm64-v8a|pixel_2"
  "gd_api33_phone|system-images;android-33;google_apis_playstore;arm64-v8a|pixel_6"
  "gd_api36_phone|system-images;android-36;google_apis_playstore;arm64-v8a|pixel_9_pro"
  "gd_api35_tablet|system-images;android-35;google_apis_playstore_tablet;arm64-v8a|pixel_tablet"
)

create() {
  for entry in "${DEVICES[@]}"; do
    IFS='|' read -r name image profile <<<"$entry"
    if "$AVDM" list avd 2>/dev/null | grep -q "Name: $name"; then
      echo "  = $name already exists"
      continue
    fi
    echo "  + creating $name ($profile, $image)"
    echo "no" | "$AVDM" create avd --name "$name" --package "$image" --device "$profile" --force >/dev/null
  done
  echo "done."
}

case "${1:-create}" in
  create) create ;;
  list)   "$AVDM" list avd ;;
  delete) for entry in "${DEVICES[@]}"; do IFS='|' read -r name _ _ <<<"$entry"; "$AVDM" delete avd --name "$name" 2>/dev/null && echo "  - deleted $name" || true; done ;;
  *) echo "usage: $0 {create|list|delete}" >&2; exit 1 ;;
esac
