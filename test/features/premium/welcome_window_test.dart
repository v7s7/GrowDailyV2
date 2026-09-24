// One welcome window per person: started once, the first time the paywall
// can show it, and never restarted by the app. The device record covers
// guests; the account record makes it one window per account, so a second
// phone or a reinstall of a signed-in account can not open a fresh one.
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart'
    show SetOptions, Timestamp;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/premium/offers/offers_store.dart';
import 'package:grow_daily_v2/features/premium/offers/paywall_offer.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory tmp;
  late Box<dynamic> box;
  late FakeFirebaseFirestore db;
  final monday = DateTime(2026, 10, 5, 21, 15);

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('welcome_window_');
    Hive.init(tmp.path);
    box = await Hive.openBox<dynamic>('box_settings');
    db = FakeFirebaseFirestore();
    await db.collection('users').doc('u1').set({'displayName': 'Aziz'});
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await tmp.delete(recursive: true);
  });

  test('a guest: started once on this device, then read back unchanged',
      () async {
    expect(await WelcomeWindowStore.read(firestore: db, box: box), isNull);
    final first = await WelcomeWindowStore.ensureStarted(
        now: monday, firestore: db, box: box);
    expect(first, monday);
    final later = await WelcomeWindowStore.ensureStarted(
      now: monday.add(const Duration(days: 9)),
      firestore: db,
      box: box,
    );
    expect(later, monday, reason: 'a second open never restarts the window');
  });

  test('signed in: the start is saved to the account as well', () async {
    await WelcomeWindowStore.ensureStarted(
        now: monday, uid: 'u1', firestore: db, box: box);
    final user = await db.collection('users').doc('u1').get();
    expect(
      (user.data()![WelcomeWindowStore.accountField] as Timestamp).toDate(),
      monday,
    );
    expect(user.data()!['displayName'], 'Aziz',
        reason: 'a merge: nothing else on the account is touched');
  });

  test('a second phone signed into the same account gets no fresh window',
      () async {
    // The first phone opened the paywall on Monday.
    await db.collection('users').doc('u1').set(
      {WelcomeWindowStore.accountField: Timestamp.fromDate(monday)},
      SetOptions(merge: true),
    );
    // The second phone has never seen the paywall; its first open is Friday.
    final start = await WelcomeWindowStore.ensureStarted(
      now: monday.add(const Duration(days: 4)),
      uid: 'u1',
      firestore: db,
      box: box,
    );
    expect(start, monday);
    final config = OffersConfig.fallback;
    expect(
      resolveOffer(
        now: monday.add(const Duration(days: 4)),
        config: config,
        welcomeStartedAt: start,
      ),
      isNull,
      reason: 'Monday plus 72 hours was over by Friday',
    );
  });

  test('a guest who signs in keeps the earlier start from before', () async {
    await WelcomeWindowStore.ensureStarted(
        now: monday, firestore: db, box: box);
    final start = await WelcomeWindowStore.ensureStarted(
      now: monday.add(const Duration(hours: 5)),
      uid: 'u1',
      firestore: db,
      box: box,
    );
    expect(start, monday);
    final user = await db.collection('users').doc('u1').get();
    expect(
      (user.data()![WelcomeWindowStore.accountField] as Timestamp).toDate(),
      monday,
    );
  });

  test('offers config: the admin document, and the device copy when offline',
      () async {
    await db.doc(OffersConfigStore.docPath).set({
      'welcome': {'enabled': false, 'hours': 72},
    });
    final online = await OffersConfigStore.load(firestore: db, box: box);
    expect(online.welcomeEnabled, isFalse);
    expect(box.get(OffersConfigStore.cacheKey), isA<String>());
  });

  test('offers config: no document yet means the defaults', () async {
    final config = await OffersConfigStore.load(firestore: db, box: box);
    expect(config.welcomeEnabled, isTrue);
    expect(config.welcomeLength, kDefaultWelcomeLength);
    expect(config.sale, isNull);
  });
}
