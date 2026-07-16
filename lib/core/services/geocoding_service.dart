import 'dart:convert';

import 'package:http/http.dart' as http;

/// One candidate location returned by [GeocodingService.search] — enough to
/// both display a disambiguating row ("Cairo, Al Qahirah, Egypt" vs. some
/// other "Cairo" the user didn't mean) and to feed straight into
/// [PrayerTimesService.calculate] once picked.
class CitySearchResult {
  final String name;
  final String? admin1; // state/governorate/province, when the API has one
  final String country;
  final double latitude;
  final double longitude;

  const CitySearchResult({
    required this.name,
    this.admin1,
    required this.country,
    required this.latitude,
    required this.longitude,
  });

  /// "Cairo, Al Qahirah, Egypt" — admin1 dropped when absent or a plain
  /// duplicate of the city name itself (common for city-states/small
  /// countries in this API's data), so the label never reads "Doha, Doha,
  /// Qatar".
  String get displayLabel {
    final parts = [
      name,
      if (admin1 != null && admin1!.isNotEmpty && admin1 != name) admin1!,
      country,
    ];
    return parts.join(', ');
  }

  factory CitySearchResult.fromJson(Map<String, dynamic> json) =>
      CitySearchResult(
        name: json['name'] as String? ?? '',
        admin1: json['admin1'] as String?,
        country: json['country'] as String? ?? '',
        latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
        longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
      );
}

/// City-name -> coordinates lookup for prayer-time setup — the manual
/// fallback path for whenever on-device GPS auto-detection isn't available
/// (permission denied, location services off) or the user just wants a
/// different city (e.g. traveling) — see DeviceLocationService and
/// NotificationSettingsScreen's doc comment for how the two fit together.
/// Backed by Open-Meteo's geocoding endpoint (https://open-meteo.com/en/docs/geocoding-api):
/// free for non-commercial use, no API key/signup, and built on GeoNames
/// data, so results cover far more than just capital cities. Only ever
/// called from an explicit, user-initiated search in the city-picker sheet
/// — never automatically, and never on a schedule.
class GeocodingService {
  const GeocodingService._();

  static Uri _searchUri(String query, String language) => Uri.https(
        'geocoding-api.open-meteo.com',
        '/v1/search',
        {'name': query, 'count': '8', 'language': language, 'format': 'json'},
      );

  /// Empty/1-character [query] returns no results without a network call
  /// (matches the API's own documented minimum), and any failure — no
  /// connection, a non-200 response, malformed JSON — returns an empty
  /// list rather than throwing, so the picker sheet can show a plain "no
  /// results" state instead of needing its own try/catch around every call
  /// site.
  static Future<List<CitySearchResult>> search(
    String query, {
    bool isAr = false,
  }) async {
    final trimmed = query.trim();
    if (trimmed.length < 2) return const [];
    try {
      final response = await http
          .get(_searchUri(trimmed, isAr ? 'ar' : 'en'))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return const [];
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return const [];
      final results = decoded['results'];
      if (results is! List) return const [];
      return results
          .whereType<Map<String, dynamic>>()
          .map(CitySearchResult.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
