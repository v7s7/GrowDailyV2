import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;

/// Resolves an ISO 3166-1 alpha-2 country code from coordinates — the one
/// extra signal PrayerTimesService.resolveRegion needs to pick a sensible
/// calculation-method default anywhere outside the 6 hand-verified GCC
/// bounding boxes (see that function's doc comment for the full tiered
/// design this feeds into).
///
/// Backed by BigDataCloud's free, keyless "reverse-geocode-client" endpoint
/// (https://www.bigdatacloud.com/free-api/free-reverse-geocode-to-city-api)
/// — no API key, no signup, and by design meant for exactly this shape of
/// call: a single client-side lookup for the device's own current or
/// just-picked location. That's also why this is only ever called once,
/// right when a location is newly set (see NotificationSettingsScreen's
/// `_LocationRow`), never on a recurring schedule or from
/// PrayerTimesService.calculate's hot path — BigDataCloud's fair-use
/// policy is for real-time, user-initiated lookups, not batch/background
/// use, and the result is cached in `NotificationSettings.
/// resolvedCountryCode` from then on, the same "resolve once" treatment
/// already given to the location itself.
class CountryLookupService {
  const CountryLookupService._();

  /// Pulled out as its own `@visibleForTesting` function — mirrors
  /// PrayerTimesService.aladhanRequestUri — so the request shape (host,
  /// path, params) can be asserted on directly without a live network
  /// call.
  @visibleForTesting
  static Uri requestUri(double latitude, double longitude) => Uri.https(
        'api.bigdatacloud.net',
        '/data/reverse-geocode-client',
        {
          'latitude': '$latitude',
          'longitude': '$longitude',
          'localityLanguage': 'en',
        },
      );

  /// Returns an uppercase ISO 3166-1 alpha-2 code (e.g. `'BH'`, `'EG'`), or
  /// null on any failure — no connection, a timeout, a non-200 response, a
  /// missing or blank `countryCode` field. A failed lookup never blocks
  /// setting the location itself; it just means PrayerTimesService.
  /// resolveRegion falls back to its global default for this user until
  /// the location is resolved again (e.g. GPS re-detected, or a fresh
  /// manual search).
  static Future<String?> lookup(double latitude, double longitude) async {
    try {
      final response = await http
          .get(requestUri(latitude, longitude))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      final code = decoded['countryCode'] as String?;
      if (code == null || code.isEmpty) return null;
      return code.toUpperCase();
    } catch (_) {
      return null;
    }
  }
}
