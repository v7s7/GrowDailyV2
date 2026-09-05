import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
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
///
/// ── Why registration keeps trying, and says what happened ──────────────
/// On 2026-09-05 the whole feature was measured against production: both
/// Cloud Functions deployed and running, the callable invoked from phones
/// that same day, every room event claimed correctly, and 0 of 113 accounts
/// holding a single device token. Nothing had ever been sent to anyone. The
/// registration path below had one attempt at launch, gave up after five
/// seconds if APNs had not answered yet, attached its token-refresh listener
/// only AFTER that attempt, and swallowed every failure without a trace, so
/// the app could not say why and neither could anyone reading its data.
///
/// So now: the refresh listener is attached first, a failed attempt retries
/// on a short bounded ladder ([pushRetryDelay]), every attempt's outcome is
/// logged, a failure is reported to Crashlytics once, and the last outcome
/// is mirrored to `users/{uid}.pushStatus` so an account that never
/// registers can be diagnosed from its own document.
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

/// How long to wait before registration attempt number [attempt] (1-based,
/// counting the attempt that is about to be made), or null once the ladder
/// is spent.
///
/// The APNs token can land any time in the first minute or so after launch,
/// and the FCM token a moment after that, so the early rungs are short. The
/// ladder is bounded on purpose: after it, the next app resume or a token
/// refresh event starts a fresh one, which is enough, and an unbounded
/// timer would keep a phone busy for an account that genuinely cannot
/// register (permission refused in system settings, say).
Duration? pushRetryDelay(int attempt) => switch (attempt) {
      1 => const Duration(seconds: 10),
      2 => const Duration(seconds: 30),
      3 => const Duration(seconds: 60),
      4 => const Duration(minutes: 2),
      5 => const Duration(minutes: 3),
      _ => null,
    };

class PushNotificationService {
  PushNotificationService._();
  static final instance = PushNotificationService._();

  StreamSubscription<String>? _refreshSub;
  String? _uid;
  String? _lastToken;
  bool _listenersAttached = false;

  /// One sync at a time. A resume, a refresh event and a retry timer can
  /// all ask within the same second; the second and later callers simply
  /// share the in-flight attempt's result rather than racing the write.
  Future<void>? _inFlight;
  Timer? _retryTimer;
  int _failedAttempts = 0;

  /// The last outcome written to `users/{uid}.pushStatus`, so the same
  /// outcome is not rewritten on every attempt.
  String? _lastStatusWritten;

  /// Failure messages already sent to Crashlytics this process. One report
  /// per distinct failure is the whole signal; a retry ladder repeating it
  /// five times would only bury it.
  final Set<String> _reported = {};

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

    // Sync the token now that permission actually exists. On iOS the APNs
    // token, and so the FCM token, can only follow the permission grant, so
    // this is the moment a first registration most often succeeds. Safe to
    // call unconditionally: _syncToken no-ops without a uid, and no-ops
    // again if the token is unchanged.
    _failedAttempts = 0;
    await _syncToken('permission');
  }

  /// Registers (or re-registers) this device's FCM token for [uid] and
  /// starts watching for a refreshed one. Call from main.dart's `_authSub`
  /// listener alongside every other pullFromAccount call, and again on
  /// app resume (harmless - [_syncToken] only ever writes when the token
  /// actually changed).
  ///
  /// The refresh listener is attached BEFORE the first attempt, not after
  /// it. On iOS the FCM token is issued a moment after APNs answers, and the
  /// plugin announces it through onTokenRefresh; attaching that listener
  /// only after a five-second first attempt meant the announcement could
  /// arrive into nothing, and nothing else asked again until the next
  /// resume.
  Future<void> registerForUser(String uid) async {
    final changed = _uid != uid;
    _uid = uid;
    if (_refreshSub == null || changed) {
      _refreshSub?.cancel();
      _refreshSub = FirebaseMessaging.instance.onTokenRefresh.listen((_) {
        _failedAttempts = 0;
        unawaited(_syncToken('refresh'));
      });
    }
    // A resume or a sign-in is a fresh reason to try, so the ladder starts
    // over rather than carrying on from where a previous one gave up.
    _failedAttempts = 0;
    _retryTimer?.cancel();
    await _syncToken(changed ? 'sign-in' : 'resume');
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
      final settings =
          await FirebaseMessaging.instance.getNotificationSettings();
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

  /// One registration attempt, coalesced: see [_inFlight].
  Future<void> _syncToken(String trigger) {
    final running = _inFlight;
    if (running != null) return running;
    final attempt = _attemptSync(trigger).whenComplete(() {
      _inFlight = null;
    });
    _inFlight = attempt;
    return attempt;
  }

  Future<void> _attemptSync(String trigger) async {
    final uid = _uid;
    if (uid == null) return;
    String outcome;
    try {
      // On iOS an FCM token cannot exist until APNs has issued one, and that
      // arrives asynchronously some time AFTER launch (and after the
      // permission grant, when there is one). A single check legitimately
      // returns null, so poll briefly here, and if that is still not enough
      // let the retry ladder below ask again in a while rather than giving
      // up for the whole session. On the Simulator, or with permission
      // refused, APNs may never issue one, and the ladder ends.
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        String? apns;
        for (var i = 0; i < 10; i++) {
          apns = await FirebaseMessaging.instance.getAPNSToken();
          if (apns != null) break;
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        if (apns == null) {
          _finish(uid, trigger, 'no-apns-token');
          return;
        }
      }
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) {
        _finish(uid, trigger, 'no-fcm-token');
        return;
      }
      if (token == _lastToken) {
        // Already mirrored by this process. Nothing to write, and nothing
        // to retry.
        _settle(trigger, 'unchanged');
        return;
      }
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('fcmTokens')
          .doc(token)
          .set(
        {
          'platform': defaultTargetPlatform.name,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      _lastToken = token;
      outcome = 'registered';
    } catch (e, st) {
      // The one thing this used to do here was nothing. The exception's
      // type and message are exactly what an "it never registers" report
      // needs, and the retry ladder gets another go regardless.
      outcome = 'error: ${e.runtimeType}: $e';
      if (_reported.add(outcome)) {
        try {
          unawaited(
            FirebaseCrashlytics.instance.recordError(
              e,
              st,
              reason: 'PushNotificationService: token registration failed',
            ),
          );
        } catch (_) {
          // No Firebase app to report to (unit tests); the log line below
          // still says what happened.
        }
      }
      _finish(uid, trigger, outcome);
      return;
    }
    _settle(trigger, outcome);
    _writeStatus(uid, outcome);
  }

  /// A failed attempt: log it, mirror it, and arm the next rung.
  void _finish(String uid, String trigger, String outcome) {
    debugPrint('[Push] $trigger: $outcome');
    _writeStatus(uid, outcome);
    _failedAttempts++;
    final delay = pushRetryDelay(_failedAttempts);
    _retryTimer?.cancel();
    if (delay == null) {
      debugPrint('[Push] giving up until the next resume or token refresh');
      return;
    }
    _retryTimer = Timer(
      delay,
      () => unawaited(_syncToken('retry $_failedAttempts')),
    );
  }

  /// A successful (or moot) attempt: log it and stand the ladder down.
  void _settle(String trigger, String outcome) {
    debugPrint('[Push] $trigger: $outcome');
    _failedAttempts = 0;
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  /// Mirrors the latest outcome onto the account, once per distinct
  /// outcome per process, so an account that never registers can be read
  /// from its own document (scripts/admin_lookup) instead of guessed at.
  /// Best-effort like every other account-sync write in main.dart.
  void _writeStatus(String uid, String outcome) {
    if (outcome == _lastStatusWritten) return;
    _lastStatusWritten = outcome;
    unawaited(
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set(
            {
              'pushStatus': {
                'outcome': outcome,
                'platform': defaultTargetPlatform.name,
                'at': FieldValue.serverTimestamp(),
              },
            },
            SetOptions(merge: true),
          )
          .catchError((_) {}),
    );
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
    _lastStatusWritten = null;
    _failedAttempts = 0;
    _retryTimer?.cancel();
    _retryTimer = null;
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
