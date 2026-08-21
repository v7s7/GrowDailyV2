import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'notification_service.dart';

/// The room-finish push notification's client-side half — the one remote
/// (server-sent) push category this app has, everything else being
/// scheduled locally by [NotificationService]. The server half is
/// functions/index.js's notifyRoomFinish Callable function — called
/// directly by RoomsController the instant a habit completion flips
/// allDoneToday to true (not a Firestore trigger; see that file's own doc
/// comment for why) — see NotificationSettings.roomActivityEnabled's doc
/// comment for the feature this serves end to end.
///
/// Owns exactly three things: getting an FCM token and mirroring it to this
/// account's own `users/{uid}/fcmTokens/{token}` doc (the only place the
/// function can find a device to actually send to), dropping that mirror on
/// sign-out so a shared/reset device stops being a delivery target for the
/// account that just left it, and routing a tapped push to the right room.
/// Registration is per-signed-in-account, same as every other
/// pullFromAccount-style sync in main.dart's `_authSub` listener — a guest
/// has no `users/{uid}` doc for a token to live on, so this is simply never
/// called for one.
/// Why a room push can or cannot reach this device, as three plain facts.
///
/// Room notifications had one failure mode and no way to see it. Every
/// in-app switch read "on", the Cloud Function ran on schedule and reported
/// success, and nothing ever arrived, because there was no device token to
/// deliver to. Nothing anywhere said so. "I never get a notification" and
/// "everything is working" were the same screen.
///
/// These three are the whole delivery chain, in order. The first one that is
/// false is the answer.
class PushDeliveryStatus {
  /// The OS notification permission. False means iOS is refusing delivery no
  /// matter what the app or the server does.
  final bool permissionGranted;

  /// A device token exists for this account. This is the one that was
  /// silently false: iOS issues no APNs token on the Simulator, and none
  /// before permission is granted, so there was simply nothing to send to.
  final bool tokenRegistered;

  /// The in-app room category switch, which the server also honours.
  final bool roomActivityEnabled;

  const PushDeliveryStatus({
    required this.permissionGranted,
    required this.tokenRegistered,
    required this.roomActivityEnabled,
  });

  /// Whether a room push could actually arrive right now.
  bool get canDeliver =>
      permissionGranted && tokenRegistered && roomActivityEnabled;
}

class PushNotificationService {
  PushNotificationService._();
  static final instance = PushNotificationService._();

  StreamSubscription<String>? _refreshSub;
  String? _uid;
  String? _lastToken;
  bool _listenersAttached = false;

  /// Set by main.dart once real navigation is safe (mirrors
  /// NotificationService.onAction's own "can't navigate from way down here,
  /// hand it to something that can" indirection) — called with the room
  /// code from a tapped push's data payload.
  void Function(String roomCode)? onOpenRoom;

  /// The room code this device is currently looking at, if any - set/
  /// cleared by RoomDetailScreen itself. A foreground push about *this*
  /// room is suppressed (see [_onForegroundMessage]): room_reactions.dart's
  /// live in-app snackbar already covers that exact moment for whoever's
  /// actually looking at the room right now, so the system banner too
  /// would just be a duplicate of something already on screen.
  String? currentlyOpenRoomCode;

  bool _requested = false;

  /// Call from a moment permission makes sense (RoomsHubScreen's build - see
  /// that screen's own call site - the first real Rooms touchpoint) — safe
  /// to call on every rebuild of a plain ConsumerWidget, unlike a real
  /// one-shot initState: [_requested] makes every call after the first a
  /// no-op, and
  /// even without that guard, iOS itself no-ops a repeat permission prompt
  /// once the person has already answered it, so this never doubles up with
  /// NotificationService.requestPermissions' own local-notification prompt,
  /// whichever of the two happens to run first.
  Future<void> requestPermissionAndInit() async {
    if (kIsWeb || _requested) return;
    _requested = true;
    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      // Deliberately NOT calling setForegroundNotificationPresentationOptions
      // here - leaving it unset means iOS shows nothing on its own for a
      // foreground remote message, which is exactly what's wanted: this
      // service decides for itself, per message, whether to show it (see
      // [_onForegroundMessage]) rather than letting iOS auto-show every one
      // unconditionally, which would have no way to skip the one case that
      // duplicates room_reactions.dart's own in-app reaction.
    } catch (_) {
      // Permission denied, or asked offline - the token registration below
      // still works fine without this (a token can exist with no
      // permission granted; it just won't show a visible alert until
      // permission is granted some other way, e.g. via Settings later).
    }
    if (_listenersAttached) return;
    _listenersAttached = true;
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedApp);
    // A push that cold-launched the app (tapped from a terminated state)
    // never fires onMessageOpenedApp - this is the one-shot catch for
    // exactly that case, same "check for one that already arrived" pattern
    // main.dart's _initDeepLinks uses for a cold-start growdaily:// link.
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) _onMessageOpenedApp(initial);

    // Sync the token now that permission actually exists.
    //
    // Without this, no device ever registers one. [registerForUser] runs
    // from main.dart's auth listener at launch — long before this prompt —
    // and on iOS getToken() returns null until APNs registration has
    // happened, which only follows the permission grant. So the launch-time
    // sync writes nothing, and the only other trigger is onTokenRefresh,
    // which fires when a token CHANGES and not when the first one is
    // issued. The result was an empty users/{uid}/fcmTokens for everyone:
    // notifyRoomFinish ran correctly, found no delivery target, and sent
    // zero pushes — indistinguishable from the feature being switched off.
    //
    // Safe to call unconditionally: _syncToken no-ops without a uid, and
    // no-ops again if the token is unchanged.
    await _syncToken();
  }

  /// Registers (or re-registers) this device's FCM token for [uid] and
  /// starts watching for a refreshed one. Call from main.dart's `_authSub`
  /// listener alongside every other pullFromAccount call, and again on
  /// app resume (harmless - [_syncToken] only ever writes when the token
  /// actually changed).
  Future<void> registerForUser(String uid) async {
    _uid = uid;
    await _syncToken();
    _refreshSub?.cancel();
    _refreshSub = FirebaseMessaging.instance.onTokenRefresh.listen((_) {
      _syncToken();
    });
  }

  /// Reads the delivery chain for the signed-in account.
  ///
  /// One Firestore read, and only when somebody has opened notification
  /// settings and is asking the question. Never called on a hot path.
  Future<PushDeliveryStatus> deliveryStatus({
    required bool roomActivityEnabled,
  }) async {
    final uid = _uid;
    if (uid == null) {
      // A guest is never registered at all, by design, so the honest answer
      // is "nothing can arrive" rather than a half-filled chain.
      return PushDeliveryStatus(
        permissionGranted: false,
        tokenRegistered: false,
        roomActivityEnabled: roomActivityEnabled,
      );
    }
    var granted = false;
    try {
      final settings = await FirebaseMessaging.instance.getNotificationSettings();
      granted = settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    } catch (_) {
      // Treated as not granted: claiming delivery works when the check
      // itself failed is the exact false reassurance this exists to end.
    }
    var registered = false;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('fcmTokens')
          .limit(1)
          .get();
      registered = snap.docs.isNotEmpty;
    } catch (_) {
      // Offline. Same reasoning as above.
    }
    return PushDeliveryStatus(
      permissionGranted: granted,
      tokenRegistered: registered,
      roomActivityEnabled: roomActivityEnabled,
    );
  }

  Future<void> _syncToken() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      // On iOS an FCM token cannot exist until APNs has issued one, and that
      // arrives asynchronously some time AFTER the permission grant. A single
      // check right after requestPermission() legitimately returns null, and
      // giving up there is what left every account with an empty fcmTokens
      // collection — notifyRoomFinish then ran correctly and delivered to
      // nobody, which looks exactly like the feature being switched off.
      //
      // So poll briefly rather than bail. ~5s total is far longer than the
      // grant normally takes and costs nothing when the token is already
      // there (first iteration wins). Still gives up eventually: on the
      // Simulator, or with permission denied, APNs never issues one and
      // there is genuinely nothing to register.
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        String? apns;
        for (var i = 0; i < 10; i++) {
          apns = await FirebaseMessaging.instance.getAPNSToken();
          if (apns != null) break;
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        if (apns == null) return;
      }
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token == _lastToken) return;
      _lastToken = token;
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('fcmTokens')
          .doc(token)
          .set({
        'platform': defaultTargetPlatform.name,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // Best-effort, same as every other account-sync call in this app's
      // main.dart listener - offline, or a transient failure, just leaves
      // the previous token (if any) as the delivery target until the next
      // successful sync (next resume, or the next onTokenRefresh).
    }
  }

  /// Signed out - drops this device's own token doc so a shared/reset
  /// device immediately stops being a push target for the account that
  /// just left it. Never touches any other device's token, and never
  /// blocks sign-out on this succeeding.
  Future<void> clearForSignOut() async {
    final uid = _uid;
    final token = _lastToken;
    _uid = null;
    _lastToken = null;
    _refreshSub?.cancel();
    _refreshSub = null;
    if (uid == null || token == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('fcmTokens')
          .doc(token)
          .delete();
    } catch (_) {}
  }

  void _onForegroundMessage(RemoteMessage message) {
    final roomCode = message.data['roomCode'] as String?;
    // Already covered by room_reactions.dart's live in-app reaction for
    // whoever's actually looking at this exact room right now - showing
    // the system banner too would just duplicate something already on
    // screen. Real suppression this time (unlike relying on iOS's own
    // foreground-presentation option, which is all-or-nothing): nothing
    // was auto-shown in the first place, so simply not calling
    // showForegroundRoomPush here is the whole suppression.
    if (roomCode != null && roomCode == currentlyOpenRoomCode) return;
    final title = message.notification?.title;
    final body = message.notification?.body;
    if (title == null || body == null) return;
    NotificationService.instance
        .showForegroundRoomPush(title: title, body: body);
  }

  void _onMessageOpenedApp(RemoteMessage message) {
    final roomCode = message.data['roomCode'] as String?;
    if (roomCode != null) onOpenRoom?.call(roomCode);
  }
}
