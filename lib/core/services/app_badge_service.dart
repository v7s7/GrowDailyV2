import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Sets the app icon badge count natively. `flutter_local_notifications`
/// deliberately has no API for this — its README's "Updating application
/// badge" section says so directly, and only lets a badge number ride along
/// with a notification that's actually being shown/scheduled, not a
/// standalone "set it to N right now" call. Rather than pull in a whole
/// extra third-party badge plugin for one native call, this talks directly
/// to a tiny handler added in AppDelegate.swift (see the "App icon badge"
/// section there) — no new pod, nothing extra to install.
class AppBadgeService {
  AppBadgeService._();
  static final instance = AppBadgeService._();

  static const _channel = MethodChannel('com.growdaily.v2/badge');

  /// Safe to call often — cheap, no network, silently no-ops on any
  /// platform without the native handler. [count] is however many habits
  /// scheduled for today are still incomplete; 0 clears the badge.
  ///
  /// iOS only, and checked BEFORE the call rather than caught after it.
  /// There is no Android half of this and there is no reason for one:
  /// Android draws its own launcher badge from the app's active
  /// notifications, with no equivalent "set it to N" API for an app to call.
  /// The catch below used to be the whole Android story, which worked but
  /// meant every dashboard change paid a platform-channel round trip to a
  /// channel with no handler and then threw and swallowed a
  /// MissingPluginException — twice per change, visible in logcat on every
  /// habit completion:
  ///
  ///   [AppBadgeService] set skipped: MissingPluginException(No
  ///   implementation found for method setBadgeCount on channel
  ///   com.growdaily.v2/badge)
  ///
  /// The try/catch stays for the case it was actually written for: an iOS
  /// build whose AppDelegate handler is missing or older than this call.
  Future<void> setCount(int count) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    try {
      await _channel.invokeMethod<void>('setBadgeCount', {'count': count});
    } catch (e) {
      debugPrint('[AppBadgeService] set skipped: $e');
    }
  }
}
