// The prayer place, found by the phone whenever something needs it (see
// autoLocatePrayerPlace), and the faster lookup underneath it.
//
// What has to hold, from Aziz's report on 2026-09-25 ("user set a widget,
// the system didn't detect the correct prayer time"):
//  - a prayer widget or a prayer habit with no place gets one without
//    anyone opening Settings, asking for access at most once;
//  - a place the phone found moves when the phone travels, a city picked by
//    hand never does;
//  - nothing is read or asked when no prayer feature needs a place;
//  - a place found during sign-in never writes over the account's own
//    settings on their way down.
import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:grow_daily_v2/core/services/country_lookup_service.dart';
import 'package:grow_daily_v2/core/services/device_location_service.dart';
import 'package:grow_daily_v2/core/services/local_store_service.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_cue.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart'
    show habitListProvider;
import 'package:grow_daily_v2/features/settings/models/notification_settings.dart';
import 'package:grow_daily_v2/features/settings/notifiers/notification_settings_notifier.dart';
import 'package:grow_daily_v2/features/settings/notifiers/prayer_location_auto.dart';
import 'package:hive/hive.dart';

const _settingsKey = 'notification_settings_v1';

// Manama, a spot in Riffa about 12 km south, Isa Town about 5 km away,
// and Riyadh.
const _manama = (lat: 26.2285, lng: 50.5860);
const _riffa = (lat: 26.1300, lng: 50.5550);
const _isaTown = (lat: 26.1736, lng: 50.5478);
const _riyadh = (lat: 24.7136, lng: 46.6753);

Position _fix(double lat, double lng, {Duration age = Duration.zero}) =>
    Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime.now().subtract(age),
      accuracy: 50,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

/// The phone's location, scripted. Extends the platform class rather than
/// implementing it, which is what lets it be installed as the instance.
class _FakeGeo extends GeolocatorPlatform {
  bool serviceOn = true;
  LocationPermission permission = LocationPermission.whileInUse;
  LocationPermission answer = LocationPermission.whileInUse;
  Position? last;

  /// Null: the new fix times out.
  Position? fresh;

  int prompts = 0;
  int lastReads = 0;
  int freshReads = 0;
  LocationSettings? askedWith;

  @override
  Future<bool> isLocationServiceEnabled() async => serviceOn;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async {
    prompts++;
    return permission = answer;
  }

  @override
  Future<Position?> getLastKnownPosition({
    bool forceLocationManager = false,
  }) async {
    lastReads++;
    return last;
  }

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    freshReads++;
    askedWith = locationSettings;
    final f = fresh;
    if (f == null) throw TimeoutException('no fix');
    return f;
  }
}

/// The account's Firestore with its reads held until [gate] opens: a phone
/// on a slow network, still reading the account's settings when the place
/// is found (the fast path in DeviceLocationService makes that the usual
/// order, not a rare one). Writes go straight through.
class _HeldReads implements FirebaseFirestore {
  _HeldReads(this.inner, this.gate);
  final FirebaseFirestore inner;
  final Future<void> gate;

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _HeldCollection(inner.collection(path), gate);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _HeldCollection implements CollectionReference<Map<String, dynamic>> {
  _HeldCollection(this.inner, this.gate);
  final CollectionReference<Map<String, dynamic>> inner;
  final Future<void> gate;

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) =>
      _HeldDoc(inner.doc(path), gate);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _HeldDoc implements DocumentReference<Map<String, dynamic>> {
  _HeldDoc(this.inner, this.gate);
  final DocumentReference<Map<String, dynamic>> inner;
  final Future<void> gate;

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async {
    await gate;
    return inner.get(options);
  }

  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) =>
      inner.set(data, options);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

final _prayerHabit = IslamicHabitCatalog.templates
    .firstWhere((t) => HabitCue.fromStoredValue(t.cueAfter).isPrayer);
final _plainHabit = IslamicHabitCatalog.templates
    .firstWhere((t) => !HabitCue.fromStoredValue(t.cueAfter).isPrayer);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('autoLocateStep', () {
    const auto = NotificationLocation(
      lat: 26.2,
      lng: 50.5,
      label: 'Manama',
      auto: true,
    );
    const byHand = NotificationLocation(
      lat: 26.2,
      lng: 50.5,
      label: 'Manama',
      auto: false,
    );
    const legacy = NotificationLocation(lat: 26.2, lng: 50.5, label: 'Manama');

    AutoLocateStep step({
      NotificationLocation? saved,
      LocationPermission permission = LocationPermission.whileInUse,
      bool needed = true,
      bool askedBefore = false,
    }) =>
        autoLocateStep(
          saved: saved,
          permission: permission,
          needed: needed,
          askedBefore: askedBefore,
        );

    test('nothing needs a place: never read, never asked', () {
      expect(step(needed: false), AutoLocateStep.stay);
      expect(
        step(needed: false, permission: LocationPermission.denied),
        AutoLocateStep.stay,
      );
    });

    test('a city picked by hand is never moved', () {
      expect(step(saved: byHand), AutoLocateStep.stay);
    });

    test('with access granted the phone is read: to fill in, or to move', () {
      expect(step(), AutoLocateStep.locate);
      expect(step(saved: auto), AutoLocateStep.locate);
      expect(
        step(saved: legacy, permission: LocationPermission.always),
        AutoLocateStep.locate,
      );
    });

    test('never asked and nothing saved: ask, once', () {
      expect(
        step(permission: LocationPermission.denied),
        AutoLocateStep.askThenLocate,
      );
      expect(
        step(permission: LocationPermission.denied, askedBefore: true),
        AutoLocateStep.stay,
      );
    });

    test('a saved place is never a reason to ask', () {
      expect(
        step(saved: auto, permission: LocationPermission.denied),
        AutoLocateStep.stay,
      );
    });

    test('a refusal, or a platform that cannot say, is left alone', () {
      expect(
        step(permission: LocationPermission.deniedForever),
        AutoLocateStep.stay,
      );
      expect(
        step(permission: LocationPermission.unableToDetermine),
        AutoLocateStep.stay,
      );
    });
  });

  group('prayerPlaceMoved', () {
    const manama = NotificationLocation(
        lat: 26.2285, lng: 50.5860, label: 'Manama', auto: true);

    test('nothing saved always takes the fix', () {
      expect(prayerPlaceMoved(null, _manama.lat, _manama.lng), isTrue);
    });

    test('a few km inside the same area keeps the place', () {
      expect(prayerPlaceMoved(manama, _isaTown.lat, _isaTown.lng), isFalse);
    });

    test('ten km or more moves it', () {
      expect(prayerPlaceMoved(manama, _riffa.lat, _riffa.lng), isTrue);
      expect(prayerPlaceMoved(manama, _riyadh.lat, _riyadh.lng), isTrue);
    });
  });

  group('DeviceLocationService.detect', () {
    late _FakeGeo geo;
    late GeolocatorPlatform original;

    setUp(() {
      original = GeolocatorPlatform.instance;
      geo = _FakeGeo();
      GeolocatorPlatform.instance = geo;
    });
    tearDown(() => GeolocatorPlatform.instance = original);

    test('a recent last known fix answers at once, no new fix asked', () async {
      geo.last = _fix(_manama.lat, _manama.lng,
          age: const Duration(minutes: 3));
      geo.fresh = _fix(_riyadh.lat, _riyadh.lng);

      final out = await DeviceLocationService.detect();
      expect(out.fix!.latitude, _manama.lat);
      expect(geo.freshReads, 0);
    });

    test('an old last known fix: a new one, city-level and time-limited',
        () async {
      geo.last = _fix(_manama.lat, _manama.lng, age: const Duration(hours: 2));
      geo.fresh = _fix(_riyadh.lat, _riyadh.lng);

      final out = await DeviceLocationService.detect();
      expect(out.fix!.latitude, _riyadh.lat);
      expect(geo.askedWith!.accuracy, LocationAccuracy.low);
      expect(
          geo.askedWith!.timeLimit, DeviceLocationService.freshFixTimeLimit);
    });

    test('a new fix that fails falls back to a last known under a day old',
        () async {
      geo.last = _fix(_manama.lat, _manama.lng, age: const Duration(hours: 5));
      final out = await DeviceLocationService.detect();
      expect(out.isSuccess, isTrue);
      expect(out.fix!.longitude, _manama.lng);
    });

    test('but never to one from days ago', () async {
      geo.last = _fix(_manama.lat, _manama.lng, age: const Duration(days: 3));
      final out = await DeviceLocationService.detect();
      expect(out.failure, DeviceLocationFailure.unavailable);
    });

    test('mayAsk false never shows the prompt', () async {
      geo.permission = LocationPermission.denied;
      final out = await DeviceLocationService.detect(mayAsk: false);
      expect(out.failure, DeviceLocationFailure.permissionDenied);
      expect(geo.prompts, 0);
      expect(geo.lastReads + geo.freshReads, 0);
    });

    test('a browser that cannot say still gets its own prompt from a tap',
        () async {
      geo.permission = LocationPermission.unableToDetermine;
      geo.fresh = _fix(_manama.lat, _manama.lng);
      expect((await DeviceLocationService.detect()).isSuccess, isTrue);
      expect(
        (await DeviceLocationService.detect(mayAsk: false)).failure,
        DeviceLocationFailure.permissionDenied,
      );
    });

    test('the default still asks, as the Settings row always has', () async {
      geo.permission = LocationPermission.denied;
      geo.fresh = _fix(_manama.lat, _manama.lng);
      final out = await DeviceLocationService.detect();
      expect(geo.prompts, 1);
      expect(out.isSuccess, isTrue);
    });
  });

  group('autoLocatePrayerPlace', () {
    late Directory dir;
    late _FakeGeo geo;
    late GeolocatorPlatform original;
    late FakeFirebaseFirestore db;
    late ProviderContainer container;
    var widgetPlaced = false;

    ProviderContainer makeContainer({
      List<IslamicHabitTemplate>? habits,
      FirebaseFirestore? firestore,
    }) {
      final c = ProviderContainer(overrides: [
        notificationSettingsProvider.overrideWith(
          (_) => NotificationSettingsNotifier(firestore: firestore ?? db),
        ),
        habitListProvider.overrideWithValue(habits ?? const []),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    Future<void> seed(NotificationSettings settings) =>
        LocalStoreService.putSettingsMap(_settingsKey, settings.toMap());

    Future<NotificationSettings> run({DateTime? now}) async {
      await autoLocatePrayerPlace(container.read, now: now);
      // The place name and country arrive in the background.
      await pumpEventQueue();
      return container.read(notificationSettingsProvider);
    }

    setUp(() {
      dir = Directory.systemTemp.createTempSync('prayer_location_auto');
      Hive.init(dir.path);
      original = GeolocatorPlatform.instance;
      geo = _FakeGeo();
      GeolocatorPlatform.instance = geo;
      db = FakeFirebaseFirestore();
      widgetPlaced = false;
      debugPrayerWidgetPlaced = () async => widgetPlaced;
      CountryLookupService.debugPlaceResponder = (lat, lng) async =>
          lat < 25.5
              ? (code: 'SA', label: 'الرياض، السعودية')
              : (code: 'BH', label: 'المنامة، البحرين');
      resetAutoLocatePrayerPlace();
    });

    tearDown(() async {
      GeolocatorPlatform.instance = original;
      debugPrayerWidgetPlaced = null;
      CountryLookupService.debugPlaceResponder = null;
      await Hive.deleteFromDisk();
      dir.deleteSync(recursive: true);
    });

    test('a widget placed with no place: asks once, saves the phone\'s',
        () async {
      widgetPlaced = true;
      geo.permission = LocationPermission.denied; // never asked yet
      geo.fresh = _fix(_manama.lat, _manama.lng);
      container = makeContainer();

      final got = await run();
      expect(geo.prompts, 1);
      expect(got.location!.lat, _manama.lat);
      expect(got.location!.auto, isTrue);
      expect(got.location!.label, 'المنامة، البحرين');
      expect(got.resolvedCountryCode, 'BH');

      // Said no this time on Android, say: the next open does not ask again.
      final again = _FakeGeo()..permission = LocationPermission.denied;
      GeolocatorPlatform.instance = again;
      resetAutoLocatePrayerPlace();
      await LocalStoreService.putSettingsMap(
          _settingsKey, const NotificationSettings().toMap());
      container = makeContainer();
      await run();
      expect(again.prompts, 0);
    });

    test('a prayer habit is a need too', () async {
      geo.fresh = _fix(_manama.lat, _manama.lng);
      container = makeContainer(habits: [_prayerHabit]);
      final got = await run();
      expect(got.location, isNotNull);
    });

    test('no prayer feature: the location is not even read', () async {
      container = makeContainer(habits: [_plainHabit]);
      final got = await run();
      expect(got.location, isNull);
      expect(geo.lastReads + geo.freshReads + geo.prompts, 0);
    });

    test('travelled: the place moves, with the new country', () async {
      await seed(const NotificationSettings(
        location: NotificationLocation(
          lat: 26.2285,
          lng: 50.5860,
          label: 'المنامة، البحرين',
          auto: true,
        ),
        resolvedCountryCode: 'BH',
      ));
      widgetPlaced = true;
      geo.fresh = _fix(_riyadh.lat, _riyadh.lng);
      container = makeContainer();

      final got = await run();
      expect(got.location!.lat, _riyadh.lat);
      expect(got.location!.label, 'الرياض، السعودية');
      expect(got.resolvedCountryCode, 'SA');
    });

    test('a place moved while the name lookup fails loses the old country',
        () async {
      await seed(const NotificationSettings(
        location: NotificationLocation(
            lat: 26.2285, lng: 50.5860, label: 'Manama', auto: true),
        resolvedCountryCode: 'BH',
      ));
      CountryLookupService.debugPlaceResponder =
          (_, __) async => (code: null, label: null);
      widgetPlaced = true;
      geo.fresh = _fix(_riyadh.lat, _riyadh.lng);
      container = makeContainer();

      final got = await run();
      expect(got.location!.lat, _riyadh.lat);
      // Riyadh with Bahrain's code would be computed by Bahrain's rules.
      expect(got.resolvedCountryCode, isNull);
    });

    test('a place saved before `auto` existed moves too', () async {
      await seed(const NotificationSettings(
        location: NotificationLocation(
            lat: 26.2285, lng: 50.5860, label: 'Manama'),
      ));
      widgetPlaced = true;
      geo.fresh = _fix(_riyadh.lat, _riyadh.lng);
      container = makeContainer();
      final got = await run();
      expect(got.location!.lat, _riyadh.lat);
    });

    test('a few km away: nothing is written', () async {
      const home = NotificationLocation(
          lat: 26.2285, lng: 50.5860, label: 'Manama', auto: true);
      await seed(const NotificationSettings(
          location: home, resolvedCountryCode: 'BH'));
      widgetPlaced = true;
      geo.fresh = _fix(_isaTown.lat, _isaTown.lng);
      container = makeContainer();
      final got = await run();
      expect(got.location, home);
    });

    test('a city picked by hand stays, wherever the phone goes', () async {
      const mecca = NotificationLocation(
          lat: 21.3891, lng: 39.8579, label: 'Mecca', auto: false);
      await seed(const NotificationSettings(location: mecca));
      widgetPlaced = true;
      geo.fresh = _fix(_manama.lat, _manama.lng);
      container = makeContainer();
      final got = await run();
      expect(got.location, mecca);
      expect(geo.lastReads + geo.freshReads, 0);
    });

    test('a saved place is looked at again only after half an hour', () async {
      await seed(const NotificationSettings(
        location: NotificationLocation(
            lat: 26.2285, lng: 50.5860, label: 'Manama', auto: true),
      ));
      widgetPlaced = true;
      geo.fresh = _fix(_manama.lat, _manama.lng);
      container = makeContainer();
      final t0 = DateTime(2026, 9, 25, 10);

      await run(now: t0);
      expect(geo.lastReads, 1);
      await run(now: t0.add(const Duration(minutes: 10)));
      expect(geo.lastReads, 1);
      await run(now: t0.add(const Duration(minutes: 31)));
      expect(geo.lastReads, 2);
    });

    test('found during sign-in: waits for the account, keeps its settings',
        () async {
      // A new phone: nothing saved on it, the account has notifications
      // switched off, and the account read is slow. The place must join
      // those settings once they are down, not go up over them.
      await db.doc('users/u1').set({
        'notificationSettings': const NotificationSettings(
          masterEnabled: false,
        ).toMap(),
      });
      final gate = Completer<void>();
      widgetPlaced = true;
      geo.last = _fix(_manama.lat, _manama.lng,
          age: const Duration(minutes: 1));
      container = makeContainer(firestore: _HeldReads(db, gate.future));

      unawaited(container
          .read(notificationSettingsProvider.notifier)
          .pullFromAccount('u1'));
      final running = autoLocatePrayerPlace(container.read);
      // Every chance for a write to land while the account is still read.
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(container.read(notificationSettingsProvider).location, isNull,
          reason: 'nothing is written while the account is being read');

      gate.complete();
      await running;
      await pumpEventQueue();
      final got = container.read(notificationSettingsProvider);
      expect(got.masterEnabled, isFalse);
      expect(got.location!.lat, _manama.lat);

      final account = (await db.doc('users/u1').get())
          .data()!['notificationSettings'] as Map;
      expect(account['masterEnabled'], isFalse);
      expect((account['location'] as Map)['auto'], isTrue);
    });
  });

  group('saved settings', () {
    test('a location keeps where it came from, and old ones read as null',
        () {
      for (final auto in [true, false]) {
        final loc = NotificationLocation(
            lat: 1, lng: 2, label: 'x', auto: auto);
        expect(NotificationLocation.fromMap(loc.toMap()), loc);
      }
      final old = NotificationLocation.fromMap(
          {'lat': 1, 'lng': 2, 'label': 'x'});
      expect(old!.auto, isNull);
      expect(old.toMap().containsKey('auto'), isFalse);
    });

    test('a Hanafi choice saved by an older build is read and dropped', () {
      // The Asr madhab setting was removed on 2026-09-25; an account or a
      // phone that still carries 'hanafi' must load normally and stop
      // writing it.
      final map = const NotificationSettings().toMap()
        ..['madhab'] = 'hanafi';
      final read = NotificationSettings.fromMap(map);
      expect(read.toMap().containsKey('madhab'), isFalse);
    });
  });
}
