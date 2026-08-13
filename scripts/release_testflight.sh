#!/bin/bash
# One-command TestFlight release for GrowDailyV2.
#
# What it does: bumps the build number in pubspec.yaml, builds a release
# .ipa (flutter build ipa -> xcodebuild archive/export under the hood),
# then uploads it straight to App Store Connect via altool (the command-
# line half of Transporter) using App Store Connect API key auth.
#
# One-time setup required before this works — see README below the
# script, or just run it once: it'll tell you exactly what's missing.
#
# Usage (from anywhere):
#   ./scripts/release_testflight.sh

set -euo pipefail
cd "$(dirname "$0")/.."   # always run from the project root

# ---- 1. Check App Store Connect API key auth is configured ----------------
if [[ -z "${ASC_KEY_ID:-}" || -z "${ASC_ISSUER_ID:-}" ]]; then
  cat <<'EOF'
Missing ASC_KEY_ID / ASC_ISSUER_ID environment variables — one-time setup:

  1. App Store Connect -> Users and Access -> Integrations -> App Store Connect API
  2. Generate a key with at least the "App Manager" role.
     Apple only lets you download the .p8 file ONCE — save it somewhere safe.
  3. Move/rename it to:
       ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8
  4. Add these two lines to ~/.zshrc (or ~/.zprofile):
       export ASC_KEY_ID="<the Key ID shown next to your key>"
       export ASC_ISSUER_ID="<the Issuer ID shown at the top of that page>"
  5. Open a new terminal window (or run: source ~/.zshrc) and re-run this script.
EOF
  exit 1
fi

KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"
if [[ ! -f "$KEY_PATH" ]]; then
  echo "Can't find $KEY_PATH — see the one-time setup steps above (step 3)."
  exit 1
fi

# ---- 2. Bump the build number in pubspec.yaml ------------------------------
CURRENT=$(grep '^version:' pubspec.yaml | sed 's/version: //')
VERSION_NAME="${CURRENT%+*}"
BUILD_NUM="${CURRENT#*+}"
NEXT_BUILD=$((BUILD_NUM + 1))
sed -i '' "s/^version: .*/version: ${VERSION_NAME}+${NEXT_BUILD}/" pubspec.yaml
echo "Bumped build number: ${VERSION_NAME}+${BUILD_NUM} -> ${VERSION_NAME}+${NEXT_BUILD}"
echo "(pubspec.yaml was edited in place — commit that change when you commit this release.)"

# ---- 3. Make sure native deps are current ----------------------------------
(cd ios && pod install)

# ---- 4. Build the release .ipa ---------------------------------------------
flutter build ipa --release --export-options-plist=ios/ExportOptions.plist

IPA_PATH=$(find build/ios/ipa -name "*.ipa" | head -n1)
if [[ -z "$IPA_PATH" ]]; then
  echo "Build finished but no .ipa was found under build/ios/ipa — check the output above."
  exit 1
fi
echo "Built: $IPA_PATH"

# ---- 5. Upload to App Store Connect / TestFlight ---------------------------
# --upload-app is Apple's soft-deprecated-but-still-working altool flag as of
# 2026. If Apple finally kills it and this step errors out, everything above
# still worked — just open the free "Transporter" app from the Mac App Store
# and drag $IPA_PATH into it instead of fixing this script.
#
# altool's own exit code is NOT trustworthy for detecting a failed upload —
# it has a documented history of exiting 0 even when App Store Connect
# rejected the build (a duplicate/too-low build number, for instance) and
# only printed "ERROR:" in its own output. So `set -e` alone can't catch
# that here; the real pass/fail check below is grepping the captured output
# for "ERROR:" ourselves, which is what actually caused this script to once
# print "Uploaded" on a run that had, in fact, failed.
UPLOAD_LOG="$(mktemp)"
xcrun altool --upload-app \
  -f "$IPA_PATH" \
  -t ios \
  --apiKey "$ASC_KEY_ID" \
  --apiIssuer "$ASC_ISSUER_ID" 2>&1 | tee "$UPLOAD_LOG" || true

if grep -q "ERROR:" "$UPLOAD_LOG"; then
  echo ""
  echo "Upload FAILED — see the ERROR line(s) above."
  echo "pubspec.yaml's build number was still bumped to ${VERSION_NAME}+${NEXT_BUILD} and the .ipa built fine; nothing above this step needs redoing."
  echo "Common cause: App Store Connect already has a build at or above this number (check the error for 'previousBundleVersion: N') — if so, just run this script again; it bumps past it automatically. If the number it reports is still higher than what this run just tried, edit the +N in pubspec.yaml's version line by hand to one above it first."
  rm -f "$UPLOAD_LOG"
  exit 1
fi
rm -f "$UPLOAD_LOG"

echo "Uploaded ${VERSION_NAME}+${NEXT_BUILD}. It'll appear in App Store Connect once Apple finishes processing (usually a few minutes), then it's available to your Internal Testing group right away, or External groups after Beta App Review."
