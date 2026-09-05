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

## HealthKit on the App ID (done 2026-09-02)

The walking-habit steps link added `com.apple.developer.healthkit` to
`ios/Runner/Runner.entitlements`, and the App ID `com.growdaily.v2` did not
have the matching capability. Simulator builds never noticed, because they
are not provisioned; the first device or archive build would have failed
signing or been rejected for an invalid entitlement.

**Enabled on the App ID on 2026-09-02** (developer.apple.com > Certificates,
Identifiers & Profiles > Identifiers > GrowDaily > HealthKit > Save), and
verified ticked afterwards. Nothing further to do.

Changing a capability **invalidates every provisioning profile containing
this App ID**, and the first archive after it has to regenerate them. That
regeneration needs Xcode to be signed in, and it is where the first attempt
actually failed (2026-09-03):

```
Error (Xcode): No Accounts: Add a new account in Accounts settings.
Error (Xcode): Provisioning profile "iOS Team Provisioning Profile: com.growdaily.v2"
               doesn't include the HealthKit capability.
```

The second and third lines are the symptom; the FIRST line is the cause. The
cached profiles under `~/Library/Developer/Xcode/UserData/Provisioning
Profiles/` were last written 2026-08-15, before HealthKit was enabled, and
signing could not reach an Apple account to fetch a new one.

It is NOT a locked-keychain or wrong-shell problem, which was the first
guess and was wrong. Both were checked directly:

- `security find-identity -v -p codesigning` lists all three identities,
  including `Apple Distribution: Abdulaziz Alkubaisi (DSHFS6NXFM)`, and the
  login keychain reports `no-timeout`. The keychain is open.
- `defaults read com.apple.dt.Xcode DVTDeveloperAccountManagerAppleIDLists`
  returns `IDE.Identifiers.Prod = ()`. **Empty.** Xcode has no Apple ID
  signed in at all, so re-running from any shell fails the same way.

The signing identity in the keychain and the Apple ID in Xcode are two
different things. The identity signs the binary; the account is what talks to
the developer portal to fetch or regenerate a provisioning profile. Only the
second one can produce a profile carrying a newly-added capability.

Two ways out. **The second one is what was actually done**, on 2026-09-03,
and it is why signing looks the way it does now:

1. Sign in: Xcode > Settings > Accounts > **+** > Apple ID for team
   DSHFS6NXFM, then re-run. Automatic signing mints the profile itself.
   Nothing else changes. Still the better long-term answer.
2. **Manual release signing** (what is in the repo now). Two App Store
   profiles were created on developer.apple.com and installed under
   `~/Library/MobileDevice/Provisioning Profiles/`:

   | Profile | App ID |
   |---|---|
   | GrowDaily AppStore | `DSHFS6NXFM.com.growdaily.v2` |
   | GrowDailyWidget AppStore | `DSHFS6NXFM.com.growdaily.v2.GrowDailyWidget` |

   TWO, because the widget extension is its own target with its own bundle
   id and an App Store archive will not sign without one for it.

   `ios/ExportOptions.plist` maps both by bundle id, and `CODE_SIGN_STYLE =
   Manual` is set on exactly two build configurations, Runner Release and
   GrowDailyWidgetExtension Release. **Every Debug and Profile configuration
   is still Automatic**, so simulator and device development builds are
   unaffected by any of this.

   The price, and it is real: those profiles **expire 2027/03/01** and must
   be regenerated by hand before then, and again whenever a capability is
   added to either App ID. Automatic signing was doing that silently. Doing
   option 1 later lets you revert both files and get it back.

Build 1.0.0+65 uploaded successfully this way (delivery UUID
4a0a2ef8-643b-4226-ab50-3b670a7f77b4), so the path is proven, not theoretical.

The script is safe to re-run: `set -e` aborts before the upload step, so a
failed archive uploads nothing (verified on that run). It does bump the build
number in pubspec.yaml BEFORE building though, so a failed run leaves the
number one ahead of reality. Revert that line if you want the next upload to
use the number the failed run claimed.

## If `altool` ever stops working entirely

Apple has soft-deprecated `--upload-app` in favor of newer flows, though it
still works as of this writing. If it ever breaks outright: everything above
the upload step still ran fine, so just open the free **Transporter** app
from the Mac App Store and drag in the `.ipa` from `build/ios/ipa/` instead
of troubleshooting the script.
