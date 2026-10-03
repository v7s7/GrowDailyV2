// Today's prayer times on Settings › موقع الصلاة
// (lib/features/settings/widgets/prayer_today_card.dart).
//
// Pinned: the sky picks the SAME moment the prayer widget's face shows, at
// every minute of the day (checked against PrayerWidgetFeed.flatten, the
// list the widget counts from), with the same words before and after it;
// the sky is the stretch of the day outside; the counter reads like the
// widget's; and the page lists all six of today's moments under the place,
// with nothing at all while no place is saved. A city picked by hand whose
// clock differs from the phone's today gets one line saying the times are
// on the phone's clock; the phone's own location never does.
//
// Harness built in setUp, never in a test body (see LandingHarness).
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/providers/day_clock_provider.dart';
import 'package:grow_daily_v2/core/services/geocoding_service.dart';
import 'package:grow_daily_v2/core/services/bahrain_prayer_table.dart';
import 'package:grow_daily_v2/core/services/prayer_times_service.dart';
import 'package:grow_daily_v2/core/services/prayer_widget_feed.dart';
import 'package:grow_daily_v2/features/habits/models/habit_cue.dart';
import 'package:grow_daily_v2/features/settings/models/notification_settings.dart';
import 'package:grow_daily_v2/features/settings/notifiers/notification_settings_notifier.dart';
import 'package:grow_daily_v2/features/settings/screens/prayer_location_screen.dart';
import 'package:grow_daily_v2/features/settings/widgets/prayer_today_card.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../helpers/landing_harness.dart';

/// One day, every time a wall-clock moment in Bahrain.
PrayerDayTimes _day(tz.Location zone, DateTime date) {
  tz.TZDateTime at(int hour, int minute) =>
      tz.TZDateTime(zone, date.year, date.month, date.day, hour, minute);
  return PrayerDayTimes(
    fajr: at(4, 10),
    sunrise: at(5, 30),
    dhuhr: at(11, 30),
    asr: at(14, 50),
    maghrib: at(17, 30),
    isha: at(19, 0),
  );
}

/// Settings as a test sets them, changed in memory only (see
/// prayer_location_screen_test.dart).
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

/// A zone whose clock differs from this machine's right now, whatever zone
/// the tests run in: the two are 25 hours apart, so no clock is both.
String _otherZone(DateTime now) =>
    now.timeZoneOffset == const Duration(hours: 14)
        ? 'Pacific/Pago_Pago'
        : 'Pacific/Kiritimati';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late tz.Location bahrain;
  setUpAll(() {
    tz_data.initializeTimeZones();
    bahrain = tz.getLocation('Asia/Bahrain');
  });

  group('PrayerToday.resolve', () {
    final date = DateTime(2026, 9, 25);
    late PrayerDayTimes today;
    late PrayerDayTimes tomorrow;
    setUp(() {
      today = _day(bahrain, date);
      tomorrow = _day(bahrain, DateTime(2026, 9, 26));
    });

    /// [hour]:[minute] in Bahrain on [date], as an instant.
    DateTime at(int hour, int minute) => DateTime.fromMillisecondsSinceEpoch(
          tz.TZDateTime(bahrain, 2026, 9, 25, hour, minute)
              .millisecondsSinceEpoch,
        );

    PrayerToday view(int hour, int minute) =>
        PrayerToday.resolve(today: today, tomorrow: tomorrow, now: at(hour, minute));

    test('lists the six moments of today, in order', () {
      final v = view(12, 0);
      expect(v.today.map((m) => m.key), PrayerToday.keys);
      expect(v.today.map((m) => m.key),
          ['fajr', 'sunrise', 'dhuhr', 'asr', 'maghrib', 'isha']);
      expect(v.today.first.at, at(4, 10));
      expect(v.today.last.at, at(19, 0));
    });

    test('before Fajr: counts down to it under the night sky', () {
      final v = view(3, 0);
      expect(v.focus.key, 'fajr');
      expect(v.focusIndex, 0);
      expect(v.elapsed, isFalse);
      expect(v.periodKey, 'isha');
    });

    test('inside a prayer\'s minutes after: counts up from it', () {
      final v = view(14, 58); // Asr 14:50, 25 minutes after
      expect(v.focus.key, 'asr');
      expect(v.elapsed, isTrue);
      expect(v.periodKey, 'asr');
    });

    test('once those minutes run out: the next one, same sky', () {
      final v = view(15, 15); // 14:50 + 25
      expect(v.focus.key, 'maghrib');
      expect(v.elapsed, isFalse);
      expect(v.periodKey, 'asr');
    });

    test('sunrise has its own quarter hour after, and its own sky', () {
      expect(view(5, 40).focus.key, 'sunrise');
      expect(view(5, 40).elapsed, isTrue);
      expect(view(5, 40).periodKey, 'sunrise');
      expect(view(5, 45).focus.key, 'dhuhr');
      expect(view(5, 45).focus.hasAdhan, isTrue);
    });

    test('after Isha\'s minutes: tomorrow\'s Fajr, no row of today marked',
        () {
      final v = view(19, 30);
      expect(v.focus.key, 'fajr');
      expect(v.focus.at.isAfter(v.today.last.at), isTrue);
      expect(v.focusIndex, -1);
      expect(v.periodKey, 'isha');
    });

    // The page must never disagree with the face that was tapped to open
    // it. The widget counts from PrayerWidgetFeed.flatten's list (its first
    // entry is the moment on the face), so walk every minute of the day
    // and hold the two equal.
    test('shows the moment the widget shows, at every minute of the day', () {
      for (var minute = 0; minute < 24 * 60; minute++) {
        final now = at(0, 0).add(Duration(minutes: minute));
        final v = PrayerToday.resolve(today: today, tomorrow: tomorrow, now: now);
        final face = PrayerWidgetFeed.flatten([today, tomorrow], from: now).first;
        expect(v.focus.key, face.key, reason: 'at $now');
        expect(v.focus.at, face.at, reason: 'at $now');
      }
    });
  });

  group('prayerCounterText', () {
    test('hours, minutes and seconds, like the widget\'s ticker', () {
      expect(
        prayerCounterText(
          const Duration(hours: 1, minutes: 23, seconds: 45),
          up: false,
        ),
        '1:23:45',
      );
      expect(prayerCounterText(const Duration(minutes: 7, seconds: 3), up: true),
          '7:03');
    });

    test('counting down rounds up, counting up rounds down', () {
      const d = Duration(minutes: 5, seconds: 3, milliseconds: 200);
      expect(prayerCounterText(d, up: false), '5:04');
      expect(prayerCounterText(d, up: true), '5:03');
      expect(prayerCounterText(const Duration(milliseconds: 1), up: false),
          '0:01');
      expect(prayerCounterText(Duration.zero, up: false), '0:00');
    });

    test('a negative span (the moment already behind) reads as its size', () {
      expect(
        prayerCounterText(const Duration(minutes: -2, seconds: -5), up: true),
        '2:05',
      );
    });
  });

  group('cityClockDiffers', () {
    final now = DateTime(2026, 9, 25, 15, 30);

    test('a zone on another clock differs', () {
      expect(cityClockDiffers(_otherZone(now), now), isTrue);
    });

    test('a zone on the phone\'s own clock does not, whatever its name', () {
      final same = tz.timeZoneDatabase.locations.keys.where(
        (name) =>
            tz.TZDateTime.from(now, tz.getLocation(name)).timeZoneOffset ==
            now.timeZoneOffset,
      );
      expect(same, isNotEmpty);
      for (final name in same.take(5)) {
        expect(cityClockDiffers(name, now), isFalse, reason: name);
      }
    });

    test('no zone, or one the database does not know, says nothing', () {
      expect(cityClockDiffers(null, now), isFalse);
      expect(cityClockDiffers('Nowhere/Atlantis', now), isFalse);
    });
  });

  group('a picked city\'s zone', () {
    test('comes from the city search', () {
      final r = CitySearchResult.fromJson({
        'name': 'London',
        'country': 'United Kingdom',
        'latitude': 51.5,
        'longitude': -0.12,
        'timezone': 'Europe/London',
      });
      expect(r.timezone, 'Europe/London');
    });

    test('is saved and read back with the place', () {
      const loc = NotificationLocation(
        lat: 51.5,
        lng: -0.12,
        label: 'London',
        auto: false,
        zone: 'Europe/London',
      );
      expect(NotificationLocation.fromMap(loc.toMap()), loc);
    });

    // The account copy is saved with a merge, which keeps any key a write
    // leaves out: a place with no zone must name the key to clear it.
    test('a place with no zone still writes the key, as empty', () {
      const loc = NotificationLocation(lat: 1, lng: 2, label: 'x', auto: true);
      expect(loc.toMap().containsKey('zone'), isTrue);
      expect(loc.toMap()['zone'], isNull);
      expect(NotificationLocation.fromMap(loc.toMap())!.zone, isNull);
    });
  });

  group('on the page', () {
    late LandingHarness h;
    tearDown(() => h.dispose());

    // A Bahrain afternoon inside the official table's range.
    final now = DateTime(2026, 9, 25, 15, 30);

    Future<void> prepare(NotificationSettings settings, {DateTime? at}) async {
      BahrainPrayerTable.resetForTest();
      await BahrainPrayerTable.ensureLoaded();
      h = LandingHarness();
      final clock = at ?? now;
      await h.prepare(
        extraOverrides: [
          notificationSettingsProvider
              .overrideWith((ref) => _Settings(settings)),
          dayClockProvider.overrideWithValue(clock),
          dayClockSourceProvider.overrideWithValue(() => clock),
        ],
      );
    }

    Future<void> open(WidgetTester tester) async {
      await tester.pumpWidget(
        h.app(
          home: const PrayerLocationScreen(),
          locale: const Locale('ar'),
        ),
      );
      await h.settle(tester);
    }

    group('with a place', () {
      setUp(
        () => prepare(
          const NotificationSettings(
            location: NotificationLocation(
              lat: 26.2285,
              lng: 50.5860,
              label: 'المنامة، البحرين',
              auto: true,
            ),
            resolvedCountryCode: 'BH',
          ),
        ),
      );
      tearDown(BahrainPrayerTable.resetForTest);

      testWidgets('lists today\'s six moments at their official times',
          (tester) async {
        await open(tester);
        expect(find.byType(PrayerTodayCard), findsOneWidget);
        expect(find.text('أوقات الصلاة'), findsOneWidget);
        final day = PrayerTimesService.calculateOfflineCorrected(
          latitude: _manama.lat,
          longitude: _manama.lng,
          date: now,
          countryCode: 'BH',
        );
        final official = BahrainPrayerTable.lookup(now)!;
        for (final key in PrayerToday.keys) {
          final at = DateTime.fromMillisecondsSinceEpoch(
            (key == 'sunrise' ? day.sunrise : day.forKey(key)!)
                .millisecondsSinceEpoch,
          );
          // The page's first answer is the official table's own.
          expect(
            at.millisecondsSinceEpoch,
            (key == 'sunrise' ? official.sunrise : official.forKey(key)!)
                .millisecondsSinceEpoch,
          );
          final name = key == 'sunrise'
              ? 'الشروق'
              : HabitCue.preset(key).labelForLocale(true);
          final clock = HabitCue.time(at.hour, at.minute).labelForLocale(true);
          expect(
            find.bySemanticsLabel('$name $clock'),
            findsOneWidget,
            reason: '$key at $clock',
          );
        }
      });

      testWidgets('the sky says what the counter means, in the widget\'s words',
          (tester) async {
        await open(tester);
        final official = BahrainPrayerTable.lookup(now)!;
        final view = PrayerToday.resolve(
          today: official,
          tomorrow: BahrainPrayerTable.lookup(DateTime(2026, 9, 26))!,
          now: now,
        );
        final label = view.focus.hasAdhan
            ? (view.elapsed ? 'مضى على الأذان' : 'باقي على الأذان')
            : (view.elapsed ? 'مضى على الشروق' : 'باقي على الشروق');
        expect(find.text(label), findsOneWidget);
        expect(
          find.text(
            prayerCounterText(view.focus.at.difference(now), up: view.elapsed),
          ),
          findsOneWidget,
        );
        // Today's date heads the list, with Western digits.
        expect(find.textContaining('25'), findsWidgets);
        expect(find.textContaining('٢٥'), findsNothing);
        // Only tomorrow's Fajr says tomorrow.
        expect(find.textContaining('باجر'), findsNothing);
      });
    });

    group('after Isha', () {
      // Aziz's screenshot, Thursday 2026-10-01 at 20:36: the sky counting
      // to Friday's Fajr at 4:13 over Thursday's list, whose Fajr is 4:12.
      final evening = DateTime(2026, 10, 1, 20, 36);
      setUp(
        () => prepare(
          const NotificationSettings(
            location: NotificationLocation(
              lat: 26.2285,
              lng: 50.5860,
              label: 'المنامة، البحرين',
              auto: true,
            ),
            resolvedCountryCode: 'BH',
          ),
          at: evening,
        ),
      );
      tearDown(BahrainPrayerTable.resetForTest);

      testWidgets('the sky says its Fajr is tomorrow\'s, the list stays today\'s',
          (tester) async {
        await open(tester);
        String clock(DateTime at) {
          final local =
              DateTime.fromMillisecondsSinceEpoch(at.millisecondsSinceEpoch);
          return HabitCue.time(local.hour, local.minute).labelForLocale(true);
        }

        final fajr = HabitCue.preset('fajr').labelForLocale(true);
        final today = clock(BahrainPrayerTable.lookup(evening)!.fajr);
        final tomorrow =
            clock(BahrainPrayerTable.lookup(DateTime(2026, 10, 2))!.fajr);
        // The evening this is about: the two Fajrs a minute apart.
        expect(tomorrow, isNot(today));
        expect(
          find.bySemanticsLabel('$fajr باجر $tomorrow، باقي على الأذان'),
          findsOneWidget,
        );
        expect(find.bySemanticsLabel('$fajr $today'), findsOneWidget);
      });
    });

    group('a city picked by hand on another clock', () {
      setUp(
        () => prepare(
          NotificationSettings(
            location: NotificationLocation(
              lat: _manama.lat,
              lng: _manama.lng,
              label: 'Somewhere',
              auto: false,
              zone: _otherZone(now),
            ),
            resolvedCountryCode: 'BH',
          ),
        ),
      );
      tearDown(BahrainPrayerTable.resetForTest);

      testWidgets('says the times are on the phone\'s clock', (tester) async {
        await open(tester);
        expect(
          find.text('الأوقات بتوقيت تلفونك، مو بتوقيت المدينة.'),
          findsOneWidget,
        );
      });
    });

    group('the phone\'s own location', () {
      setUp(
        () => prepare(
          NotificationSettings(
            location: NotificationLocation(
              lat: _manama.lat,
              lng: _manama.lng,
              label: 'Somewhere',
              auto: true,
              // Even with a zone left behind, the phone's place is on the
              // phone's clock by definition.
              zone: _otherZone(now),
            ),
            resolvedCountryCode: 'BH',
          ),
        ),
      );
      tearDown(BahrainPrayerTable.resetForTest);

      testWidgets('never says it', (tester) async {
        await open(tester);
        expect(find.byType(PrayerTodayCard), findsOneWidget);
        expect(
          find.text('الأوقات بتوقيت تلفونك، مو بتوقيت المدينة.'),
          findsNothing,
        );
      });
    });

    group('with no place', () {
      setUp(() => prepare(const NotificationSettings()));
      tearDown(BahrainPrayerTable.resetForTest);

      testWidgets('shows no times at all', (tester) async {
        await open(tester);
        expect(find.byType(PrayerTodayCard), findsNothing);
        expect(find.text('أوقات الصلاة'), findsNothing);
      });
    });
  });
}
