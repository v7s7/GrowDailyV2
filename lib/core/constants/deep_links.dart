/// Everything about the app's own links, in one place.
///
/// ── Why this file exists ───────────────────────────────────────────────────
///
/// Room invites used to be shared as `growdaily://join/CODE`. That link is
/// dead on arrival in the place invites actually travel: WhatsApp, iMessage
/// and every other messenger only auto-linkify `http`/`https`, so a custom
/// scheme arrives as plain grey text the recipient cannot tap at all. Even
/// pasted into Safari it only works if the app is already installed — there
/// is no such thing as a fallback for a custom scheme, so someone who does
/// not have Grow Daily yet gets nothing, not even a hint of what the link
/// was for. That is the whole invite funnel leaking at its first step.
///
/// The fix is a Universal Link: a real `https://` URL that iOS hands
/// straight to the app when it is installed, and that otherwise loads a
/// normal web page which explains itself and offers the download. Same link,
/// both audiences, and it is tappable everywhere because it is just a URL.
///
/// ── What has to line up for that to work ───────────────────────────────────
///
///  1. [linkHost] must serve `/.well-known/apple-app-site-association` AND
///     `/.well-known/assetlinks.json` over HTTPS, as `application/json`, with
///     no redirect. See `public/` and the `hosting` block in firebase.json.
///  2. The AASA names `<TEAM_ID>.com.growdaily.v2`, and the app carries a
///     matching `com.apple.developer.associated-domains` entitlement
///     (`applinks:<linkHost>`) — see ios/Runner/Runner.entitlements.
///  3. assetlinks.json names `com.growdaily.v2` with the SHA-256 of every
///     certificate a shipped build can be signed by — the upload key AND the
///     Play App Signing key, which is a different key and only readable from
///     Play Console (see ANDROID_RELEASE.md) — and the app carries a matching
///     `autoVerify="true"` intent-filter in AndroidManifest.xml.
///  4. The paths in both files must match what [roomJoinUrl] actually builds.
///
/// If any of those drift apart the link silently degrades to opening the web
/// page instead of the app — which is why they are commented in every one of
/// those files as a set. Silently is the operative word on both platforms:
/// nothing throws, nothing logs, the app is simply never offered.
library;

/// The host that serves the association file and the fallback pages.
///
/// Firebase Hosting's free default domain, deliberately: the project already
/// exists (`grow-daily-339ef`), it is HTTPS with a valid certificate out of
/// the box, and it needs no DNS work before launch.
///
/// TO MOVE TO A CUSTOM DOMAIN LATER, e.g. growdaily.app:
///   1. Add it in Firebase Console → Hosting → Add custom domain.
///   2. Change this one constant.
///   3. Change `applinks:` in ios/Runner/Runner.entitlements to match.
///   4. Change `android:host` on the App Link intent-filter in
///      android/app/src/main/AndroidManifest.xml to match.
///   5. Re-deploy hosting — both public/.well-known/apple-app-site-association
///      AND public/.well-known/assetlinks.json have to be reachable on the new
///      host — and ship a build.
/// Old links keep working as long as the old host stays connected, because
/// [parseRoomJoinLink] matches on the PATH, not on the host — see its own
/// doc comment for why that matters for anyone who already shared a link.
const String linkHost = 'grow-daily-339ef.web.app';

/// Path prefix for a room invite. Kept as a constant because it appears in
/// three places that must agree: here, the AASA `paths` array, and the
/// Firebase Hosting rewrite.
const String joinPathPrefix = '/join';

/// The shareable invite URL for [code] — the thing that goes in a WhatsApp
/// message.
Uri roomJoinUrl(String code) =>
    Uri.https(linkHost, '$joinPathPrefix/${code.toUpperCase()}');

/// The legacy custom scheme, still registered in Info.plist and still parsed
/// on the way in.
///
/// Kept deliberately: links shared before this change are already sitting in
/// people's chat histories, and the home-screen widget's own
/// `growdaily://matrix/add` link has no reason to become a web URL — it never
/// leaves the device, so it never needed to be tappable by a stranger.
const String legacyScheme = 'growdaily';

/// Path for the password-reset action page. Three places must agree: here,
/// the AASA `components` array, and `public/reset/index.html` (which is what
/// a browser gets when the app is not installed).
const String resetPath = '/reset';

/// Path for a plain "open the app here" link: `growdaily://open?tab=grid`.
///
/// What the iOS Lock Screen / Control Center controls use (see
/// ios/GrowDailyWidget/GrowDailyControls.swift). One parameterised link
/// rather than a path per page, because the destinations are exactly
/// [NavTab]'s ids and a second list of names that has to agree with that
/// enum is a list that will eventually disagree with it.
const String openPath = '/open';

/// The tab id from an "open the app here" link, or null.
///
/// Returns the raw id rather than a NavTab: this file is in core/constants
/// and the enum lives in core/providers, so resolving it here would point a
/// constant at a provider. The caller maps it, and an id this build does not
/// know simply opens the app on its usual tab.
///
/// Accepts both shapes for the same reason [parsePasswordResetLink] does: a
/// custom scheme puts "open" in the host, an https link puts it in the path.
String? parseOpenTabLink(Uri uri) {
  final scheme = uri.scheme.toLowerCase();
  final isWeb = scheme == 'https' || scheme == 'http';
  if (!isWeb && scheme != legacyScheme) return null;

  final first = uri.pathSegments.isEmpty ? '' : uri.pathSegments.first;
  final target = isWeb ? first : (uri.host.isEmpty ? first : uri.host);
  if (target.toLowerCase() != 'open') return null;

  final tab = uri.queryParameters['tab']?.trim().toLowerCase() ?? '';
  return tab.isEmpty ? null : tab;
}

/// The link a control taps. Kept here so the Swift side has one spelling to
/// copy and the test can assert the round trip.
Uri openTabUrl(String tabId) =>
    Uri(scheme: legacyScheme, host: 'open', queryParameters: {'tab': tabId});

/// Parses a password-reset link into its Firebase `oobCode`, or null.
///
/// Two shapes reach the app, and both mean the same thing:
///   `https://<host>/reset?oobCode=...`  the App Link, which is what the
///       page in `public/reset/` is FOR: on a phone the system hands the URL
///       to the app and the page is never drawn.
///   `growdaily://reset?oobCode=...`     what that page falls back to when
///       the system did not do the handoff itself and the person taps
///       "change it in the app".
///
/// A `mode` that is present and is not `resetPassword` returns null on
/// purpose: Firebase puts every kind of email action through one URL shape,
/// and an email-verification link must not open a "set a new password"
/// screen. A link with no `mode` at all is accepted, because our own page
/// builds the growdaily:// form from the code alone.
///
/// Host is not checked here, for the reason [parseRoomJoinLink] documents at
/// length: the platform config already scoped it before the app is handed
/// anything.
String? parsePasswordResetLink(Uri uri) {
  final scheme = uri.scheme.toLowerCase();
  final isWeb = scheme == 'https' || scheme == 'http';
  if (!isWeb && scheme != legacyScheme) return null;

  // growdaily://reset?... puts "reset" in the HOST, not the path, because a
  // custom scheme has no authority of its own. Accept it from either.
  final first = uri.pathSegments.isEmpty ? '' : uri.pathSegments.first;
  final target = isWeb ? first : (uri.host.isEmpty ? first : uri.host);
  if (target.toLowerCase() != 'reset') return null;

  final mode = uri.queryParameters['mode'];
  if (mode != null && mode.isNotEmpty && mode != 'resetPassword') return null;

  final code = uri.queryParameters['oobCode']?.trim() ?? '';
  return code.isEmpty ? null : code;
}
