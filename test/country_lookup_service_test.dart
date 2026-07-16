import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/services/country_lookup_service.dart';

void main() {
  group('CountryLookupService.requestUri', () {
    // Pure URL-building, asserted on directly rather than via a live call
    // — mirrors PrayerTimesService.aladhanRequestUri's testing approach
    // (see that file's test for why: this is the one place a wrong host,
    // path, or param name would silently break the whole lookup, so it's
    // worth locking down without needing a network call to do it).
    test(
        'builds the exact BigDataCloud reverse-geocode-client request',
        () {
      final uri = CountryLookupService.requestUri(26.2285, 50.5860);
      expect(uri.host, 'api.bigdatacloud.net');
      expect(uri.path, '/data/reverse-geocode-client');
      expect(uri.queryParameters['latitude'], '26.2285');
      expect(uri.queryParameters['longitude'], '50.586');
      expect(uri.queryParameters['localityLanguage'], 'en');
    });

    test('negative coordinates round-trip through the query string intact',
        () {
      final uri = CountryLookupService.requestUri(-6.2088, 106.8456);
      expect(uri.queryParameters['latitude'], '-6.2088');
      expect(uri.queryParameters['longitude'], '106.8456');
    });
  });
}
