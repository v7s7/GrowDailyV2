// Settings › موقع الصلاة (lib/features/settings/screens/prayer_location_screen.dart).
//
// Pinned: the page says where prayer times come from and which of the two
// ways it follows, ticked; a place saved before `auto` existed follows the
// phone only when location access is allowed; the method row names
// Bahrain's official timetable while it covers the day, and the calculated
// method after it; «اختر مدينة» opens the city search.
//
// Harness built in setUp, never in a test body (see LandingHarness).
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/providers/day_clock_provider.dart';
import 'package:grow_daily_v2/core/services/bahrain_prayer_table.dart';
import 'package:grow_daily_v2/core/services/prayer_times_service.dart';
import 'package:grow_daily_v2/features/settings/models/notification_settings.dart';
import 'package:grow_daily_v2/features/settings/notifiers/notification_settings_notifier.dart';
import 'package:grow_daily_v2/features/settings/screens/prayer_location_screen.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import '../../helpers/landing_harness.dart';

/// Settings as a test sets them, changed in memory only: a real save writes
/// the settings box, and disk writes from inside a widget test never finish.
class _Settings extends NotificationSettingsNotifier {
  _Settings(NotificationSettings initial)
      : super(firestore: FakeFirebaseFirestore()) {
    state = initial;
  }

  @override
  Future<void> update(
    NotificationSettings Function(NotificationSettings current) mutator,
  ) async {
    state = mutator(state);
  }
}

const _manama = (lat: 26.2285, lng: 50.5860);

NotificationSettings _at({bool? auto, String label = 'Manama, Bahrain'}) =>
    NotificationSettings(
      location: NotificationLocation(
        lat: _manama.lat,
        lng: _manama.lng,
        label: label,
        auto: auto,
      ),
      resolvedCountryCode: 'BH',
    );

/// Bahrain's table, read the way the app reads it at launch: its rows are
/// Bahrain wall-clock, so the time zones must be loaded first.
Future<void> _loadBahrainTable() async {
  tzdata.initializeTimeZones();
  BahrainPrayerTable.resetForTest();
  await BahrainPrayerTable.ensureLoaded();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LandingHarness h;
  tearDown(() => h.dispose());

  Future<void> prepare(NotificationSettings settings, {DateTime? today}) async {
    h = LandingHarness();
    await h.prepare(
      extraOverrides: [
        notificationSettingsProvider.overrideWith((ref) => _Settings(settings)),
        // A fixed day inside Bahrain's table, and no boundary timer left
        // running after the test.
        dayClockProvider.overrideWithValue(today ?? DateTime(2026, 9, 25, 14)),
      ],
    );
  }

  Future<void> open(WidgetTester tester, {Locale? locale}) async {
    await tester.pumpWidget(
      h.app(home: const PrayerLocationScreen(), locale: locale),
    );
    await h.settle(tester);
  }

  /// The tick in the row titled [title], if it has one.
  Finder tickIn(String title) => find.descendant(
        of: find.ancestor(of: find.text(title), matching: find.byType(InkWell)),
        matching: find.byIcon(Icons.check_circle_rounded),
      );

  group('nothing saved yet', () {
    setUp(() => prepare(const NotificationSettings()));

    testWidgets('says so, in Arabic, with neither way ticked', (tester) async {
      await open(tester, locale: const Locale('ar'));
      expect(find.text('موقع الصلاة'), findsOneWidget);
      expect(find.text('ما حددت موقعك بعد'), findsOneWidget);
      expect(find.text('أوقات الصلاة تحتاج موقعك'), findsOneWidget);
      expect(find.text('موقعي الحالي'), findsOneWidget);
      expect(find.text('اختر مدينة'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
    });
  });

  group('the phone\'s own location', () {
    setUp(() => prepare(_at(auto: true)));

    testWidgets('is named and ticked on «موقعي الحالي»', (tester) async {
      await open(tester);
      expect(find.text('Manama, Bahrain'), findsOneWidget);
      expect(find.text("From your phone's location"), findsOneWidget);
      expect(tickIn('My current location'), findsOneWidget);
      expect(tickIn('Choose a city'), findsNothing);
    });
  });

  group('inside Bahrain', () {
    setUp(() async {
      await _loadBahrainTable();
      await prepare(_at(auto: true));
    });
    tearDown(BahrainPrayerTable.resetForTest);

    testWidgets('the method row names the official timetable', (tester) async {
      await open(tester, locale: const Locale('ar'));
      expect(find.text('طريقة الحساب'), findsOneWidget);
      expect(find.text('الجدول الرسمي لمملكة البحرين'), findsOneWidget);
    });
  });

  group('inside Bahrain, past the table\'s last day', () {
    setUp(() async {
      await _loadBahrainTable();
      await prepare(_at(auto: true), today: DateTime(2027, 7, 1, 14));
    });
    tearDown(BahrainPrayerTable.resetForTest);

    testWidgets('the calculated method takes over', (tester) async {
      await open(tester);
      final method = PrayerTimesService.resolveRegion(
        _manama.lat,
        _manama.lng,
        countryCode: 'BH',
      ).method.label(false);
      expect(find.text(method), findsOneWidget);
      expect(find.text("Bahrain's official timetable"), findsNothing);
    });
  });

  group('a city picked by hand', () {
    setUp(() => prepare(_at(auto: false, label: 'Riyadh, Saudi Arabia')));

    testWidgets('is ticked on «اختر مدينة»', (tester) async {
      await open(tester);
      expect(find.text('Riyadh, Saudi Arabia'), findsOneWidget);
      expect(find.text('A city you picked'), findsOneWidget);
      expect(tickIn('Choose a city'), findsOneWidget);
      expect(tickIn('My current location'), findsNothing);
    });

    testWidgets('«اختر مدينة» opens the city search', (tester) async {
      await open(tester);
      await tester.tap(find.text('Choose a city'));
      await h.settle(tester);
      expect(find.text('e.g. Cairo, Istanbul, Jakarta'), findsOneWidget);
    });
  });

  group('a place saved before the app recorded which way', () {
    setUp(() => prepare(_at()));

    // No location access in a test (the plugin is not there to say yes),
    // and without it the app never moves the place: it reads as a city.
    testWidgets('without location access, reads as a city', (tester) async {
      await open(tester);
      expect(find.text('A city you picked'), findsOneWidget);
      expect(tickIn('Choose a city'), findsOneWidget);
    });
  });
}
