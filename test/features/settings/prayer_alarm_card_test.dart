// «منبّه الأذان» on Settings › موقع الصلاة
// (lib/features/settings/widgets/prayer_alarm_card.dart).
//
// Pinned (Aziz, 2026-10-03): five switches, one per prayer, all off until
// turned on; a switch reads on only while its alarm will ring on this phone,
// and turns on only once it can. The permission is asked when a switch is
// turned on, and a refusal leaves it off. Where no alarm can ring the card
// is grey and says why, in place of its promise. The card shows only with a
// place saved, under the two ways to choose one.
//
// Harness built in setUp, never in a test body (see LandingHarness).
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/services/bahrain_prayer_table.dart';
import 'package:grow_daily_v2/features/settings/models/notification_settings.dart';
import 'package:grow_daily_v2/features/settings/notifiers/notification_settings_notifier.dart';
import 'package:grow_daily_v2/features/settings/screens/prayer_location_screen.dart';
import 'package:grow_daily_v2/features/settings/widgets/prayer_alarm_card.dart';

import 'package:timezone/data/latest.dart' as tzdata;

import '../../helpers/landing_harness.dart';

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

const _manama = NotificationLocation(
  lat: 26.2285,
  lng: 50.5860,
  label: 'المنامة، البحرين',
  auto: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const alarmChannel = MethodChannel('com.growdaily.v2/alarm');

  late LandingHarness h;
  // What the phone answers now; a test changes it as the phone would.
  late PrayerAlarmReadiness readiness;
  late List<String> asked;
  late bool allow;

  // The page works out today's times through tz.local and Bahrain's table,
  // loaded here once and outside any test, as prayer_location_screen_test
  // explains: a table read first started inside a widget test never ends.
  setUpAll(() async {
    tzdata.initializeTimeZones();
    BahrainPrayerTable.resetForTest();
    await BahrainPrayerTable.ensureLoaded();
  });

  Future<void> prepare(NotificationSettings settings) async {
    readiness = PrayerAlarmReadiness.ready;
    asked = [];
    allow = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(alarmChannel, (call) async {
      asked.add(call.method);
      return switch (call.method) {
        'isSupported' => true,
        'requestAuthorization' => allow,
        _ => null,
      };
    });
    h = LandingHarness();
    await h.prepare(
      extraOverrides: [
        notificationSettingsProvider.overrideWith((ref) => _Settings(settings)),
        prayerAlarmReadinessProvider.overrideWith((ref) async => readiness),
      ],
    );
  }

  tearDown(() {
    h.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(alarmChannel, null);
  });

  Future<void> openCard(WidgetTester tester) async {
    await tester.pumpWidget(
      h.app(
        home: const Scaffold(
          body: SingleChildScrollView(
            child: PrayerAlarmCard(),
          ),
        ),
        locale: const Locale('ar'),
      ),
    );
    await tester.pumpAndSettle();
  }

  Set<String> chosen() =>
      h.container.read(notificationSettingsProvider).prayerAlarms;

  List<Switch> switches(WidgetTester tester) =>
      tester.widgetList<Switch>(find.byType(Switch)).toList();

  group('with a place', () {
    setUp(() => prepare(const NotificationSettings(location: _manama)));

    testWidgets('five prayers, every switch off until turned on',
        (tester) async {
      await openCard(tester);
      expect(find.text('منبّه الأذان'), findsOneWidget);
      expect(
        find.text('يرن مثل المنبّه وقت الأذان، حتى لو الجوال صامت.'),
        findsOneWidget,
      );
      for (final name in ['الفجر', 'الظهر', 'العصر', 'المغرب', 'العشاء']) {
        expect(find.text(name), findsOneWidget, reason: name);
      }
      expect(
        find.text('الشروق'),
        findsNothing,
        reason: 'no adhan is called for sunrise',
      );
      expect(switches(tester).map((s) => s.value), List.filled(5, false));
    });

    testWidgets('a switch turned on is saved and reads on; off removes it',
        (tester) async {
      await openCard(tester);
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(chosen(), {'fajr'});
      expect(switches(tester).first.value, isTrue);
      expect(
        asked,
        isNot(contains('requestAuthorization')),
        reason: 'already allowed: nothing to ask',
      );

      await tester.tap(find.byType(Switch).last);
      await tester.pumpAndSettle();
      expect(chosen(), {'fajr', 'isha'});

      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(chosen(), {'isha'});
      expect(switches(tester).first.value, isFalse);
    });

    testWidgets('iOS, never asked: the first switch asks, then turns on',
        variant: TargetPlatformVariant.only(TargetPlatform.iOS),
        (tester) async {
      readiness = PrayerAlarmReadiness.askFirst;
      await openCard(tester);
      // Allowed on the sheet: the phone now answers "ready".
      readiness = PrayerAlarmReadiness.ready;
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(asked.where((m) => m == 'requestAuthorization'), hasLength(1));
      expect(chosen(), {'fajr'});
      expect(switches(tester).first.value, isTrue);
    });

    testWidgets('iOS, refused on the sheet: it stays off, and the card says so',
        variant: TargetPlatformVariant.only(TargetPlatform.iOS),
        (tester) async {
      readiness = PrayerAlarmReadiness.askFirst;
      allow = false;
      await openCard(tester);
      readiness = PrayerAlarmReadiness.alarmsDenied;
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(chosen(), isEmpty);
      expect(
        find.text('المنبّه يحتاج إذن. فعّله من إعدادات الجهاز.'),
        findsOneWidget,
      );
      expect(switches(tester).every((s) => s.onChanged == null), isTrue);
    });

    for (final (state, note) in [
      (PrayerAlarmReadiness.needsNewerIos, 'المنبّه يحتاج iOS 26 أو أحدث.'),
      (
        PrayerAlarmReadiness.alarmsDenied,
        'المنبّه يحتاج إذن. فعّله من إعدادات الجهاز.',
      ),
      (
        PrayerAlarmReadiness.exactAlarmsOff,
        'المنبّه يحتاج إذن «المنبّهات والتذكيرات». فعّله من إعدادات الجهاز.',
      ),
    ]) {
      testWidgets('${state.name}: grey, saying why in place of the promise',
          (tester) async {
        readiness = state;
        await openCard(tester);
        expect(find.text(note), findsOneWidget);
        expect(
          find.text('يرن مثل المنبّه وقت الأذان، حتى لو الجوال صامت.'),
          findsNothing,
        );
        expect(switches(tester).every((s) => s.onChanged == null), isTrue);
        await tester.tap(find.byType(Switch).first, warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(chosen(), isEmpty);
      });
    }

    testWidgets('unavailable: no card at all', (tester) async {
      readiness = PrayerAlarmReadiness.unavailable;
      await openCard(tester);
      expect(find.text('منبّه الأذان'), findsNothing);
    });
  });

  group('a choice saved where it cannot ring yet', () {
    setUp(
      () => prepare(
        const NotificationSettings(location: _manama, prayerAlarms: {'fajr'}),
      ),
    );

    testWidgets('reads off, and comes back on once the phone allows it',
        (tester) async {
      readiness = PrayerAlarmReadiness.askFirst;
      await openCard(tester);
      expect(
        switches(tester).first.value,
        isFalse,
        reason: 'a switch reads on only while its alarm will ring',
      );
      expect(chosen(), {'fajr'}, reason: 'the choice itself is kept');

      readiness = PrayerAlarmReadiness.ready;
      h.container.invalidate(prayerAlarmReadinessProvider);
      await tester.pumpAndSettle();
      expect(switches(tester).first.value, isTrue);
    });
  });

  group('on the page', () {
    Future<void> openPage(WidgetTester tester) async {
      await tester.pumpWidget(
        h.app(home: const PrayerLocationScreen(), locale: const Locale('ar')),
      );
      await h.settle(tester);
    }

    group('with a place', () {
      setUp(
        () => prepare(
          const NotificationSettings(
            location: _manama,
            resolvedCountryCode: 'BH',
          ),
        ),
      );

      testWidgets('sits under the two ways to choose a place', (tester) async {
        await openPage(tester);
        await tester.scrollUntilVisible(
          find.byType(PrayerAlarmCard),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(
          tester.getTopLeft(find.byType(PrayerAlarmCard)).dy,
          greaterThan(tester.getBottomLeft(find.text('اختر مدينة')).dy),
        );
      });
    });

    group('with no place', () {
      setUp(() => prepare(const NotificationSettings()));

      testWidgets('is not there: the alarms need its times', (tester) async {
        await openPage(tester);
        expect(find.byType(PrayerAlarmCard), findsNothing);
      });
    });
  });
}
