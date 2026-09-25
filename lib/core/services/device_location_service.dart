import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:geolocator/geolocator.dart';

/// A raw GPS fix, ready to hand straight to [PrayerTimesService.calculate]
/// or wrap in a [NotificationLocation]. Deliberately carries no city/country
/// name — reverse-geocoding that would mean a second package and a second
/// permission-adjacent surface for a purely cosmetic label, so callers
/// label it themselves (see NotificationSettingsScreen, which shows the
/// rounded coordinates — the exact same fallback convention the manual
/// "enter coordinates" mode in city_search_sheet.dart already uses when it
/// has no city name either).
class DeviceLocationFix {
  final double latitude;
  final double longitude;
  const DeviceLocationFix({required this.latitude, required this.longitude});
}

/// Why [DeviceLocationService.detect] didn't return a fix — every case the
/// caller has to show *some* explanation for and fall back to manual city
/// search (see NotificationSettingsScreen's long-press escape hatch).
enum DeviceLocationFailure {
  /// Location services are off system-wide (not an app permission at all —
  /// nothing this app can prompt its way past).
  serviceDisabled,

  /// Denied once — [Geolocator.requestPermission] can still ask again next
  /// time, so this isn't necessarily final.
  permissionDenied,

  /// Denied permanently ("Don't Allow" answered before, or turned off in
  /// iOS Settings) — iOS won't show the system prompt again; only
  /// `Geolocator.openAppSettings()` can get back here, which this service
  /// deliberately doesn't invoke itself (see [DeviceLocationService.detect]
  /// doc comment) since jumping a user straight to Settings without them
  /// asking for it would be jarring — the caller decides whether to offer
  /// that.
  permissionDeniedForever,

  /// Timed out, or some other platform-level failure acquiring a fix
  /// (indoors with a weak signal, airplane mode, etc.).
  unavailable,
}

/// Outcome of a [DeviceLocationService.detect] call — mirrors the app's
/// established "never throw, return a typed result" pattern (see
/// PurchaseService.purchase's PurchaseOutcome) rather than a `Future` that
/// can throw for any of several very-expected-in-practice reasons (denied
/// permission is not an exceptional case here, it's a normal branch).
class DeviceLocationOutcome {
  final DeviceLocationFix? fix;
  final DeviceLocationFailure? failure;

  const DeviceLocationOutcome._({this.fix, this.failure});

  factory DeviceLocationOutcome.success(DeviceLocationFix fix) =>
      DeviceLocationOutcome._(fix: fix);

  factory DeviceLocationOutcome.failed(DeviceLocationFailure reason) =>
      DeviceLocationOutcome._(failure: reason);

  bool get isSuccess => fix != null;
}

/// One-shot GPS lookup for prayer-time setup — see NotificationSettingsScreen's
/// doc comment for how this fits alongside the manual city-search fallback.
/// Wraps `geolocator`'s permission-check/request/getCurrentPosition dance
/// (see its README) into the single call a settings row needs, and never
/// throws — every failure path (services off, denied, timed out) resolves
/// to a [DeviceLocationOutcome] instead.
class DeviceLocationService {
  const DeviceLocationService._();

  /// How old the phone's last known fix may be and still be used as is,
  /// with no new fix asked for at all. Ten minutes is not "where the phone
  /// is this second", but a prayer time moves under a minute for every
  /// 25 km of travel, and nobody covers that much ground in the time it
  /// takes to reopen an app. This is what makes the common case instant.
  @visibleForTesting
  static const lastKnownFreshFor = Duration(minutes: 10);

  /// How long a new fix may take before the last known one is used instead.
  @visibleForTesting
  static const freshFixTimeLimit = Duration(seconds: 10);

  /// The oldest last known fix that may stand in for a new one that
  /// failed. A day old is still almost always the same city; a fix from
  /// last week's trip is not, and saving it would be worse than saying the
  /// location could not be found.
  @visibleForTesting
  static const lastKnownFallbackFor = Duration(hours: 24);

  /// Where the phone is, as fast as the answer can be had.
  ///
  /// 1. The last fix the system already holds, when it is recent
  ///    ([lastKnownFreshFor]): no wait at all.
  /// 2. Otherwise a new fix at [LocationAccuracy.low], about a kilometre on
  ///    iOS, from Wi-Fi and cell towers, and usually back in about a second
  ///    indoors where waiting on GPS could take many. Prayer times move
  ///    seconds over a kilometre, so the finer precision a navigation app
  ///    needs (this asked for `medium`, 100 m, until 2026-09-25) only made
  ///    the wait longer.
  /// 3. When that new fix fails or takes over [freshFixTimeLimit], the last
  ///    known fix, if it is under [lastKnownFallbackFor] old. A place from
  ///    this morning is still almost always the right city, and the app
  ///    checks again the next time it is opened.
  ///
  /// [mayAsk] false never shows the system prompt: a person who has not
  /// answered it yet gets [DeviceLocationFailure.permissionDenied], which
  /// is how autoLocatePrayerPlace looks without asking.
  static Future<DeviceLocationOutcome> detect({bool mayAsk = true}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return DeviceLocationOutcome.failed(DeviceLocationFailure.serviceDisabled);
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied && mayAsk) {
        permission = await Geolocator.requestPermission();
      }
      // A browser that cannot report the permission (no Permissions API)
      // still shows its own prompt on the position request below, which is
      // how a tap in Settings has always worked there; only a caller that
      // must not ask stops here.
      if (permission == LocationPermission.denied ||
          (permission == LocationPermission.unableToDetermine && !mayAsk)) {
        return DeviceLocationOutcome.failed(DeviceLocationFailure.permissionDenied);
      }
      if (permission == LocationPermission.deniedForever) {
        return DeviceLocationOutcome.failed(
            DeviceLocationFailure.permissionDeniedForever);
      }

      final last = await _lastKnown();
      final lastAge =
          last == null ? null : DateTime.now().difference(last.timestamp);
      if (last != null && lastAge! <= lastKnownFreshFor) {
        return _success(last);
      }
      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.low,
            timeLimit: freshFixTimeLimit,
          ),
        );
        return _success(position);
      } catch (_) {
        if (last != null && lastAge! <= lastKnownFallbackFor) {
          return _success(last);
        }
        rethrow;
      }
    } catch (_) {
      // Timeout, platform channel error, etc. — same "fall back to manual"
      // treatment as every other failure case here.
      return DeviceLocationOutcome.failed(DeviceLocationFailure.unavailable);
    }
  }

  /// The permission as it stands, without ever asking for it. Anything the
  /// plugin cannot answer (a browser without the Permissions API, a
  /// platform error) reads as [LocationPermission.unableToDetermine].
  static Future<LocationPermission> permission() async {
    try {
      return await Geolocator.checkPermission();
    } catch (_) {
      return LocationPermission.unableToDetermine;
    }
  }

  /// The system's own last fix, or null when it has none or cannot say
  /// (the web has no such thing and throws).
  static Future<Position?> _lastKnown() async {
    try {
      return await Geolocator.getLastKnownPosition();
    } catch (_) {
      return null;
    }
  }

  static DeviceLocationOutcome _success(Position p) =>
      DeviceLocationOutcome.success(
        DeviceLocationFix(latitude: p.latitude, longitude: p.longitude),
      );
}
