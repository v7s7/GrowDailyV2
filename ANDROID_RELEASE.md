# Android release

The iOS half of this is `release.sh` and `RELEASE.md`. This file covers only
what is different on Android.

## One-time: the upload keystore

Play identifies your app by the key it is signed with. Generate the upload
key **once**, then never lose it.

```bash
keytool -genkey -v \
  -keystore ~/growdaily-upload.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias growdaily
```

`keytool` ships with the JDK. Answer the prompts (name, org, locale) and set
a strong password when asked. Then create `android/key.properties`:

```properties
storePassword=<the password you just chose>
keyPassword=<the same password, unless you set a separate key password>
keyAlias=growdaily
storeFile=/Users/<you>/growdaily-upload.jks
```

Both `android/key.properties` and `*.jks` are gitignored. That is deliberate:
the file holds the passwords in plaintext.

**Back the keystore up somewhere offline.** With Play App Signing enabled
(recommended, and the default for new apps) Google holds the real app signing
key, so a lost upload key can be reset through support. Without it, a lost
keystore means you can never update the listing again.

`android/app/build.gradle.kts` reads `key.properties` if it exists and falls
back to debug signing if it does not, so a fresh clone still builds. Only a
build with a real `key.properties` produces something Play will accept.

## Build

```bash
flutter build appbundle --release
```

Output: `build/app/outputs/bundle/release/app-release.aab`. Upload that, not
an APK. Play requires the App Bundle format for new apps.

To sanity-check on a real device without going through Play:

```bash
flutter build apk --release
```

### Locale note (this build machine only)

This Mac's system locale is `ar_BH`, and several Java-based Android tools
format numbers with the JVM default locale. They then emit Arabic-Indic
digits where ASCII is required. The failure that cost the most time:

```
Invalid dex file indices, expecting file 'classes٢.dex' but found 'classes2.dex'
```

The APK build was unaffected, so only the one format Play accepts was broken.
The fix is committed: `org.gradle.jvmargs` in `android/gradle.properties`
carries `-Duser.language=en -Duser.country=US`. It only pins the build
toolchain; the app still ships Arabic and English.

Standalone SDK tools do not read gradle.properties. When running `sdkmanager`,
`bundletool` or `avdmanager` by hand, export the same thing first:

```bash
export JAVA_TOOL_OPTIONS="-Duser.language=en -Duser.country=US"
```

## What is intentionally not here yet

- **In-app purchases.** `PurchaseService._androidApiKey` is empty, so the
  paywall shows its honest "not available yet" state on Android. See the
  numbered setup steps in that class's doc comment: Play products have to be
  created first, and Play will not let you create them until a build has been
  uploaded to some track at least once.
- **Home screen widgets.** iOS-only by design for the first Android release.
  `HomeWidgetService._supported` gates every call.

## Play Console: state as of 2026-09-01

Build 64 (1.0.0) is signed, uploaded, and live on the **internal testing**
track (26.2 MB install size). Everything below is recorded so the next
submission does not have to rediscover it.

Done:

- Store listing: title, descriptions, icon, feature graphic (1024x500),
  4 phone screenshots. Assets are in `tool/play-assets/`.
- Content rating: ESRB **Everyone**, PEGI **3**, interactive element
  "In-App Purchases".
- Advertising ID: **No**. This is only true because the manifest strips the
  three ad-ID permissions that Firebase and Play Services merge in
  (`AD_ID`, `ACCESS_ADSERVICES_AD_ID`, `ACCESS_ADSERVICES_ATTRIBUTION`,
  all with `tools:node="remove"`). If a future dependency reintroduces one,
  this declaration becomes false. Re-check the merged manifest with:
  `bundletool dump manifest --bundle=build/app/outputs/bundle/release/app-release.aab --xpath=/manifest/uses-permission/@android:name`
  (`aapt` will not read an .aab, only an .apk.) Note bundletool needs
  `JAVA_TOOL_OPTIONS="-Duser.language=en -Duser.country=US"` on this machine;
  see "Locale note" above.
- Government apps: No. Financial features: none. Health apps: **no health
  features**. The `health`, `fitness`, `sleep` and `mind` habit categories
  are user-chosen labels; the app records a completion boolean and reads no
  sensors, no Health Connect, and no health metric.
- Data safety: all 11 data types answered and **saved as a draft**. It
  cannot be submitted until Target audience is set (see below).

### Data safety answers, and why

| Data type | Collected | Shared | Required | Purpose |
|---|---|---|---|---|
| Name, Email address, User IDs | yes | no | optional | App functionality, Account management |
| Approximate + Precise location | yes | **yes** | optional | App functionality |
| Voice or sound recordings | yes | no | optional | App functionality |
| Crash logs, Diagnostics | yes | no | **required** | Analytics |
| App interactions | yes | no | **required** | Analytics |
| Other user-generated content | yes | no | optional | App functionality |
| Device or other IDs | yes | no | **required** | App functionality, Analytics |

- Account data is *optional* because guest mode is a real mode: the app works
  without an account, so the user chooses whether any of it is collected.
- Location is *shared* because coordinates leave the device to third-party
  APIs we do not control: `api.aladhan.com` (prayer times),
  `bigdatacloud` (reverse geocode), `open-meteo` (place search). It is also
  stored, not ephemeral: `notification_settings_notifier.dart:59` writes the
  lat/lng into Firestore.
- Voice notes count as collected even though the file stays local, because
  `VoiceNote.audioBase64` (`matrix_task.dart`) syncs the audio itself to
  Firestore when it fits the sync budget.
- Crashlytics and Analytics are *required* because nothing in the app lets a
  user turn them off (`main.dart:170` sets Crashlytics on unconditionally in
  release).

### SUBMITTED FOR REVIEW on 2026-09-01

All 11 App content declarations are complete ("You're all caught up") and
14 changes were submitted to Google. Publishing overview reads "Your changes
are now in review."

What went in: the closed test track (roll out 64, 176 countries plus rest of
world, resume track, testers = the "Internal testers" list), the store
listing, and the seven App content declarations.

Target audience was set to **18 and over only**. That choice skipped the
"appeals to children" and "store presence" steps, which only apply to
under-18 bands, and it keeps the app out of the Families programme. The
optional "Restrict users that Google has determined to be minors" box was
left **unticked** on purpose: it blocks people from finding or buying the
app, which is a much stronger action than declaring design intent. Both are
one-click changes.

**After the review passes**, the remaining work is not in the Console:

1. Share the closed test opt-in link with the 21 testers. The link only
   appears once the release is actually published.
2. Get at least **12 of them to opt in**. Google counts opted-in testers,
   not listed ones, and it read "0 testers currently opted-in".
3. Run 14 days. The clock starts from opt-in, not from submission.
4. "Apply for production" then unlocks, with questions about the closed test.

### Historical: the chain that gated all of this

Play gates them in order, which is not obvious from the App content page:

    Sign in details  ->  Target audience  ->  Data safety

Opening Target audience before Sign in details is done just shows
"You must complete the Sign in details section before starting the Target
audience and content questionnaire". So the single unblocking action is the
demo account in item 3.

1. **Target audience and content.** Blocks the Data safety submission. The
   form asks which age bands the app targets. Selecting any band under 18
   pulls the app into the Families programme, which adds its own policy
   requirements. Grow Daily has social Rooms, an account system and in-app
   purchases, so **18 and over** is the low-friction answer and is
   changeable later. Including teens is a reach decision, not a technical
   one, which is why it was left open.

2. ~~Select testers~~ **done.** An account-level list "Internal testers"
   (21 people, from the previous app) already existed but was not ticked on
   either track. It is now selected on **both** internal and closed testing.
   21 is comfortably above the 12 that closed testing requires.

   Internal testing opt-in link:
   `https://play.google.com/apps/internaltest/4700414198768706682`
   The link only works for accounts on that list; there is no "anyone with
   the link" option on internal testing.

3. **Sign in details.** Do this one first: it unblocks the other two. Google
   states plainly on the form: "We can't create new accounts". Rooms is gated
   behind email/password sign-in (`rooms_hub_screen.dart:116`), and guest
   mode also caps the habit limit and hides account deletion, so the honest
   answer is "Yes, part of the app is restricted" and a working demo login
   must be supplied. Create one in the app, then fill the form as:

   - Name: `Rooms test account`
   - Username: the demo account's email address
   - Password: that account's password
   - Any other information: `Most of the app is usable without signing in.
     Sign in is only needed for the Rooms tab (bottom navigation), which
     shows a sign-in gate to guests. There is no 2-step verification, no
     PIN, and no region restriction. The Premium tier is not purchasable on
     Android in this build, so no paid content needs to be unlocked to
     review the app.`

   That last sentence matters: the form counts "access tiers" as a
   restriction alongside sign in, and the Premium paywall is visible in the
   app. Saying it is inert on Android is both true today and stops a
   reviewer waiting on a purchase they cannot make. Delete that sentence
   once `_androidApiKey` is filled in.

### Closed testing track: prepared, waiting on the same gate

Production access for this **personal** developer account requires a closed
test with **at least 12 testers opted in, running for at least 14 days**,
before "Apply for production" unlocks. Internal testing does not count toward
that clock, so the 14 days only starts once the closed release is live and
people have actually opted in.

The "Closed testing - Alpha" track is now **4 of 5 complete**:

- Select countries and regions: done, all 177
- Select testers: done, the 21-person list
- Create a new release: done, build 64 (1.0.0) added from the library, release
  notes copied from the internal release
- Preview and confirm: done, Play reports "Ready to release", 26.2 MB
- **Send the release to Google for review: blocked**

That last step is gated on the three App content declarations, which is why
the dashboard still says "To start a closed test, finish setting up your app".
Nothing else about the closed test needs doing: finish Sign in details ->
Target audience -> Data safety, then roll out and the clock starts.

Ship to internal testing first, not straight to production.
