#!/usr/bin/env bash
#
# GrowDaily release.
#
#   ./release.sh                 preflight only, changes nothing
#   ./release.sh --ios           build + upload the iOS build to App Store Connect
#   ./release.sh --firebase      deploy Firestore rules, indexes, functions, hosting
#   ./release.sh --all           both, then tag and push
#
#   --skip-tests                 skip the suite (do not use for a real release)
#   --no-bump                    reuse the current build number
#   --yes                        answer every confirmation (for non-interactive runs)
#
# Everything that reaches the outside world asks first. Preflight is the
# whole point of this file: a release that fails at the upload step has
# already cost you a build, so every reason to stop is checked before
# anything is built.

set -euo pipefail
cd "$(dirname "$0")"

RED=$'\e[31m'; GRN=$'\e[32m'; YLW=$'\e[33m'; DIM=$'\e[2m'; OFF=$'\e[0m'
step() { printf '\n%s==>%s %s\n' "$GRN" "$OFF" "$1"; }
warn() { printf '%s!! %s%s\n' "$YLW" "$1" "$OFF"; }
die()  { printf '%sxx %s%s\n' "$RED" "$1" "$OFF" >&2; exit 1; }

confirm() {
  printf '\n%s%s%s\n' "$YLW" "$1" "$OFF"
  if [ "${ASSUME_YES:-0}" = "1" ]; then
    echo "  (--yes)"
    return 0
  fi
  reply=""
  # Read from the TERMINAL, not stdin. `flutter test` runs before this and
  # leaves stdin at EOF, so a plain `read` returned instantly with an empty
  # answer and refused a "yes" that had been typed correctly (2026-09-10:
  # tests passed, the prompt echoed "yes", and the script still said Stopped).
  if [ -r /dev/tty ]; then
    read -r -p "Type yes to continue: " reply < /dev/tty || true
  else
    read -r -p "Type yes to continue: " reply || true
  fi
  # Tolerant of a stray carriage return, surrounding spaces and capitals: the
  # answer is a confirmation, not a password.
  reply="$(printf '%s' "$reply" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
  [ "$reply" = "yes" ] || die "Stopped."
}

DO_IOS=0; DO_FIREBASE=0; DO_TAG=0; SKIP_TESTS=0; BUMP=1; ASSUME_YES=0
for arg in "$@"; do
  case "$arg" in
    --ios)        DO_IOS=1 ;;
    --firebase)   DO_FIREBASE=1 ;;
    --all)        DO_IOS=1; DO_FIREBASE=1; DO_TAG=1 ;;
    --skip-tests) SKIP_TESTS=1 ;;
    --no-bump)    BUMP=0 ;;
    --yes)        ASSUME_YES=1 ;;
    *) die "Unknown flag: $arg" ;;
  esac
done

# ── App Store Connect credentials ────────────────────────────────────
# Key files already live in ~/.appstoreconnect/private_keys/. The issuer
# id is not derivable from them, so it comes from the environment:
#
#   export ASC_KEY_ID=8672BSV59Q
#   export ASC_ISSUER_ID=<from appstoreconnect.apple.com > Users and Access > Integrations>
#
ASC_KEY_ID="${ASC_KEY_ID:-}"
ASC_ISSUER_ID="${ASC_ISSUER_ID:-}"

# ── Preflight ────────────────────────────────────────────────────────
step "Preflight"

[ -n "$(git status --porcelain)" ] && die "Working tree is dirty. Commit or stash first.
$(git status --short | head -20)"
echo "  clean tree"

BRANCH="$(git branch --show-current)"
[ "$BRANCH" = "main" ] || warn "On '$BRANCH', not main."
echo "  branch $BRANCH"

git fetch --quiet origin "$BRANCH" 2>/dev/null || true
if [ -n "$(git log "origin/$BRANCH..$BRANCH" --oneline 2>/dev/null)" ]; then
  warn "Local commits are not pushed yet."
fi

command -v flutter  >/dev/null || die "flutter not on PATH"
command -v firebase >/dev/null || warn "firebase CLI not found (needed for --firebase)"

# Bahrain's official prayer table ships inside the app and ends on the last
# day the government published. Past it, Bahrain falls back to calculated
# times (a minute or two off), which alarms set around Fajr would feel.
TABLE_LAST="$(python3 -c 'import json; print(json.load(open("assets/prayer/bahrain_official.json"))["last"])' 2>/dev/null || true)"
if [ -n "$TABLE_LAST" ]; then
  TABLE_DAYS=$(( ( $(date -j -f %Y-%m-%d "$TABLE_LAST" +%s) - $(date +%s) ) / 86400 ))
  [ "$TABLE_DAYS" -lt 30 ] && die "Bahrain prayer table ends $TABLE_LAST ($TABLE_DAYS days). Run scripts/refresh_bahrain_prayer_table.py"
  [ "$TABLE_DAYS" -lt 120 ] && warn "Bahrain prayer table ends $TABLE_LAST ($TABLE_DAYS days). Run scripts/refresh_bahrain_prayer_table.py"
  echo "  prayer table to $TABLE_LAST ($TABLE_DAYS days left)"
fi

# ── Signing ──────────────────────────────────────────────────────────
# A provisioning profile freezes the App ID's capabilities at the moment
# it is made. Add an entitlement to the app and the archive fails AFTER
# the build ("Provisioning profile ... doesn't include the ... entitlement",
# seen 2026-09-06 with Time Sensitive Notifications, 2026-09-02 with
# HealthKit). Checked here, before anything is built: every key in each
# .entitlements file must already be in the installed profile it signs
# with. The fix is a click on developer.apple.com and one script, see
# RELEASE.md.
check_profile() {
  local ent_file="$1" profile_name="$2" dir p name missing
  for dir in "$HOME/Library/MobileDevice/Provisioning Profiles" \
             "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"; do
    for p in "$dir"/*.mobileprovision; do
      [ -f "$p" ] || continue
      name="$(security cms -D -i "$p" 2>/dev/null | plutil -extract Name raw - 2>/dev/null)" || continue
      [ "$name" = "$profile_name" ] || continue
      missing="$(python3 - "$ent_file" "$p" <<'PYCHECK'
import plistlib, subprocess, sys
want = plistlib.load(open(sys.argv[1], 'rb'))
raw = subprocess.run(['security', 'cms', '-D', '-i', sys.argv[2]], capture_output=True).stdout
have = plistlib.loads(raw).get('Entitlements', {})
print(' '.join(k for k in want if k not in have))
PYCHECK
)"
      [ -z "$missing" ] || die "Profile '$profile_name' does not carry: $missing
Tick the capability on developer.apple.com > Identifiers, then run
  python3 scripts/regen_appstore_profile.py --profile '$profile_name' --entitlements $ent_file
and start again."
      echo "  $profile_name carries every entitlement of $ent_file"
      return 0
    done
  done
  warn "Profile '$profile_name' is not installed on this Mac; the archive will fail without it."
}
step "Signing"
check_profile ios/Runner/Runner.entitlements "GrowDaily AppStore"
check_profile ios/GrowDailyWidgetExtension.entitlements "GrowDailyWidget AppStore"

step "Analyzer"
ERRORS="$(flutter analyze lib 2>&1 | grep -cE '^\s*error' || true)"
[ "$ERRORS" = "0" ] || die "$ERRORS analyzer error(s). Fix before releasing."
echo "  0 errors"

if [ "$SKIP_TESTS" = "0" ]; then
  step "Tests"
  flutter test || die "Tests failed."
else
  warn "Tests skipped."
fi

CURRENT="$(grep '^version:' pubspec.yaml | awk '{print $2}')"
NAME="${CURRENT%%+*}"
BUILD="${CURRENT##*+}"
echo
echo "  current version  $CURRENT"

if [ "$DO_IOS" = "0" ] && [ "$DO_FIREBASE" = "0" ]; then
  printf '\n%sPreflight passed. Nothing else to do (pass --ios, --firebase or --all).%s\n' "$GRN" "$OFF"
  exit 0
fi

# ── Version bump ─────────────────────────────────────────────────────
if [ "$DO_IOS" = "1" ] && [ "$BUMP" = "1" ]; then
  NEXT=$((BUILD + 1))
  step "Version $NAME+$BUILD -> $NAME+$NEXT"
  # -i '' is the BSD/macOS form; GNU sed would need plain -i.
  sed -i '' "s/^version: .*/version: $NAME+$NEXT/" pubspec.yaml
  BUILD="$NEXT"
  # Committed here, not left loose: preflight refuses on a dirty tree, so
  # an uncommitted bump would block the NEXT release with a change this
  # script made itself.
  git add pubspec.yaml
  git commit -q -m "Build $NAME+$NEXT"
  echo "  pubspec.yaml updated and committed"
fi
VERSION="$NAME+$BUILD"

# ── iOS ──────────────────────────────────────────────────────────────
if [ "$DO_IOS" = "1" ]; then
  [ -n "$ASC_KEY_ID" ]    || die "ASC_KEY_ID is not set. See the header of this script."
  [ -n "$ASC_ISSUER_ID" ] || die "ASC_ISSUER_ID is not set. See the header of this script."

  confirm "About to build and UPLOAD $VERSION to App Store Connect. This is public-facing and cannot be undone."

  step "Clean"
  flutter clean >/dev/null
  flutter pub get >/dev/null
  ( cd ios && pod install --silent )

  step "Build IPA ($VERSION)"
  flutter build ipa --release \
    --export-options-plist=ios/ExportOptions.plist

  IPA="$(ls -t build/ios/ipa/*.ipa 2>/dev/null | head -1)"
  [ -n "$IPA" ] || die "No .ipa produced in build/ios/ipa/"
  echo "  $IPA"

  step "Validate with App Store Connect"
  xcrun altool --validate-app -f "$IPA" -t ios \
    --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID" \
    || die "Validation failed. Nothing was uploaded."

  step "Upload"
  xcrun altool --upload-app -f "$IPA" -t ios \
    --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
  echo "  uploaded. Processing takes ~10 to 30 minutes before it appears in TestFlight."
fi

# ── Firebase ─────────────────────────────────────────────────────────
if [ "$DO_FIREBASE" = "1" ]; then
  confirm "About to deploy Firestore rules, indexes, functions and hosting to grow-daily-339ef. Rules take effect immediately for every live user."

  step "Firestore rules and indexes"
  firebase deploy --only firestore:rules,firestore:indexes

  step "Functions"
  ( cd functions && npm ci --silent )
  firebase deploy --only functions

  # The web app is a hosting TARGET, and `--only hosting` deploys both it and
  # the marketing/action-page site. Deploying without rebuilding would push
  # whatever build/web happens to hold, which is how a stale bundle silently
  # replaces the live web app. Build it first, always.
  step "Web build (hosting target 'app')"
  flutter build web --release

  step "Hosting"
  firebase deploy --only hosting
fi

# ── Tag ──────────────────────────────────────────────────────────────
if [ "$DO_TAG" = "1" ]; then
  step "Tag v$VERSION"
  git tag -a "v$VERSION" -m "Release $VERSION"
  echo
  printf '%sTagged locally. Push it yourself when you are ready:%s\n' "$DIM" "$OFF"
  echo "  git push origin $BRANCH --follow-tags"
fi

printf '\n%sDone. %s%s\n' "$GRN" "$VERSION" "$OFF"
