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

  /// [LocationAccuracy.medium] (~100m on iOS) is deliberately not `.high`/
  /// `.best` — prayer times don't meaningfully change over a few hundred
  /// meters, so there's no reason to ask for the slower, more
  /// battery-hungry precision a navigation app would need.
  static Future<DeviceLocationOutcome> detect() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return DeviceLocationOutcome.failed(DeviceLocationFailure.serviceDisabled);
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        return DeviceLocationOutcome.failed(DeviceLocationFailure.permissionDenied);
      }
      if (permission == LocationPermission.deniedForever) {
        return DeviceLocationOutcome.failed(
            DeviceLocationFailure.permissionDeniedForever);
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 15),
        ),
      );
      return DeviceLocationOutcome.success(DeviceLocationFix(
        latitude: position.latitude,
        longitude: position.longitude,
      ));
    } catch (_) {
      // Timeout, platform channel error, etc. — same "fall back to manual"
      // treatment as every other failure case here.
      return DeviceLocationOutcome.failed(DeviceLocationFailure.unavailable);
    }
  }
}
