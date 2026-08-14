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
///  1. [linkHost] must serve `/.well-known/apple-app-site-association` over
///     HTTPS, as `application/json`, with no redirect. See `public/` and the
///     `hosting` block in firebase.json.
///  2. That file names `<TEAM_ID>.com.growdaily.v2`, and the app carries a
///     matching `com.apple.developer.associated-domains` entitlement
///     (`applinks:<linkHost>`) — see ios/Runner/Runner.entitlements.
///  3. The paths in the AASA must match what [roomJoinUrl] actually builds.
///
/// If any of those three drift apart the link silently degrades to opening
/// the web page instead of the app — which is why they are commented in all
/// three files as a set.
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
///   4. Re-deploy hosting and ship a build.
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
