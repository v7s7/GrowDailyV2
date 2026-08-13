# Releasing to TestFlight

## One-time setup (per Mac)

1. App Store Connect → Users and Access → Integrations → App Store Connect API
   → generate a key with the **App Manager** role.
   Apple only lets you download the `.p8` file once — save it somewhere safe.
2. Move it into place:
   ```
   mkdir -p ~/.appstoreconnect/private_keys
   mv ~/Downloads/AuthKey_<KEY_ID>.p8 ~/.appstoreconnect/private_keys/
   ```
3. Add your Key ID and Issuer ID to `~/.zshrc` (Issuer ID is the UUID shown
   above the keys table on that same App Store Connect API page):
   ```
   echo 'export ASC_KEY_ID="<KEY_ID>"' >> ~/.zshrc
   echo 'export ASC_ISSUER_ID="<ISSUER_ID>"' >> ~/.zshrc
   ```
4. (Optional but recommended) add a one-word shortcut:
   ```
   echo 'alias growdaily-release="~/Documents/GrowDailyV2/scripts/release_testflight.sh"' >> ~/.zshrc
   ```
5. Open a new terminal (or `source ~/.zshrc`) so all of the above takes effect.

Steps 1-4 only need to happen once per Mac. If you ever build from a
different machine, repeat them there.

## Shipping a new build

```
growdaily-release
```

(or, without the alias: `./scripts/release_testflight.sh` from the project root)

This single command:
1. Bumps the build number in `pubspec.yaml` (`+1` each run — Apple rejects
   duplicate build numbers, so this is why it's automatic).
2. Runs `pod install` so native deps are current.
3. Builds a release `.ipa` via `flutter build ipa`.
4. Uploads it to App Store Connect via `xcrun altool` (Transporter's
   command-line side), authenticated with the API key from setup above.

Commit the `pubspec.yaml` build-number bump afterward so git stays in sync
with what's actually in App Store Connect.

## After upload

- **Internal testers** (your App Store Connect team, up to 100 people): see
  the new build within a few minutes, no review needed.
- **External testers** (anyone else, up to 10,000): must wait for Apple's
  Beta App Review first (usually well under a day). There's no way to skip
  this — it's enforced on Apple's side, not something the script controls.

## If the upload fails

The script now checks the actual upload output for an `ERROR:` line and
stops with a clear message if it finds one — earlier versions trusted
`altool`'s exit code alone, which it turns out isn't reliable (it can exit
successfully even when App Store Connect rejected the build). If you see
"Upload FAILED": the `.ipa` itself built fine, only the last step needs
retrying. The most common cause is a build-number conflict — App Store
Connect already has a build at or above the number this run tried. Check the
error for `previousBundleVersion: N` and either just re-run the script (it
auto-bumps past whatever pubspec.yaml has on file) or, if pubspec.yaml is
out of sync with what's actually on App Store Connect, edit its `version:`
line's `+N` by hand to one above `previousBundleVersion` first.

## If `altool` ever stops working entirely

Apple has soft-deprecated `--upload-app` in favor of newer flows, though it
still works as of this writing. If it ever breaks outright: everything above
the upload step still ran fine, so just open the free **Transporter** app
from the Mac App Store and drag in the `.ipa` from `build/ios/ipa/` instead
of troubleshooting the script.
