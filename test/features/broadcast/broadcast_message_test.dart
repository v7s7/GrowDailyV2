// The admin's pop-up to everyone, as a phone reads it.
//
// What has to hold:
//   - a malformed document costs a slot (or a field), never the app: no
//     crash, no blank pop-up, and the other slot still works;
//   - the reader sees their own language when the admin wrote it, and the
//     Arabic otherwise, with the direction following the words;
//   - a pop-up shows inside its window only, once per device, and a test
//     pop-up only to the accounts it names (by hash, the same hash the
//     admin tool computes);
//   - a test meant for this reader comes before everyone's.
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/broadcast/broadcast_message.dart';
import 'package:hive/hive.dart';

final _noon = DateTime.utc(2026, 9, 22, 9);

BroadcastPopup _popup({
  String id = 'p_1',
  String titleEn = '',
  String bodyEn = '',
  String buttonAr = '',
  DateTime? startsAt,
  DateTime? endsAt,
  Set<String> testUidHashes = const {},
}) =>
    BroadcastPopup(
      id: id,
      titleAr: 'تحديث جديد',
      bodyAr: 'صار عندك تذكير لكل صلاة.',
      titleEn: titleEn,
      bodyEn: bodyEn,
      buttonAr: buttonAr,
      startsAt: startsAt ?? _noon.subtract(const Duration(hours: 1)),
      endsAt: endsAt ?? _noon.add(const Duration(days: 7)),
      testUidHashes: testUidHashes,
    );

void main() {
  tearDown(BroadcastStore.reset);

  group('the uid hash', () {
    test('is SHA-256 hex, the same vectors the admin tool pins', () {
      // scripts/admin_lookup/test/broadcast.test.js asserts the same pair.
      expect(
        broadcastUidHash('abc'),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
      expect(
        broadcastUidHash('aZ9TestUidForBroadcast000001'),
        '0f32428f5f9a1caa8476f46575f0b24fcd87725cbbc9af84eda946a62f737941',
      );
    });
  });

  group('reading the document', () {
    test('anything that is not a document is nothing to show', () {
      for (final junk in [null, 'text', 42, <Object?>[], <String, Object?>{}]) {
        expect(BroadcastState.fromData(junk).isEmpty, isTrue, reason: '$junk');
      }
    });

    test(
        'a slot without an id or without its Arabic is empty; the other '
        'slot is kept', () {
      final state = BroadcastState.fromData(const {
        'everyone': {'titleAr': 'عنوان', 'bodyAr': 'نص'},
        'test': {
          'id': 'p_t',
          'titleAr': 'تجربة',
          'bodyAr': 'نص',
          'testUidHashes': ['abc', 7],
        },
        'version': 3.0,
      });
      expect(state.everyone, isNull);
      expect(state.test?.id, 'p_t');
      expect(
        state.test?.testUidHashes,
        {'abc'},
        reason: 'a non-string hash costs that entry only',
      );
      expect(state.version, 3);

      final noBody = BroadcastState.fromData(const {
        'everyone': {'id': 'p_1', 'titleAr': 'عنوان', 'bodyAr': '   '},
      });
      expect(noBody.everyone, isNull, reason: 'never a blank pop-up');
    });

    test('a test slot that names nobody is dropped, never read as everyone',
        () {
      final state = BroadcastState.fromData(const {
        'test': {'id': 'p_t', 'titleAr': 'تجربة', 'bodyAr': 'نص'},
      });
      expect(state.test, isNull);
      final junkHashes = BroadcastState.fromData(const {
        'test': {
          'id': 'p_t',
          'titleAr': 'تجربة',
          'bodyAr': 'نص',
          'testUidHashes': [7, null],
        },
      });
      expect(junkHashes.test, isNull);
    });

    test('a bad optional field costs that field, not the pop-up', () {
      final state = BroadcastState.fromData(const {
        'everyone': {
          'id': 'p_1',
          'titleAr': 'عنوان',
          'bodyAr': 'نص',
          'titleEn': 12,
          'endsAt': 'tomorrow',
        },
      });
      expect(state.everyone?.titleEn, '');
      expect(state.everyone?.endsAt, isNull);
    });

    test(
        'dates come as Firestore timestamps live and as milliseconds from '
        'the cache, and survive the round trip', () {
      final live = BroadcastState.fromData({
        'everyone': {
          'id': 'p_1',
          'titleAr': 'عنوان',
          'bodyAr': 'نص',
          'startsAt': Timestamp.fromDate(_noon),
          'endsAt': Timestamp.fromDate(_noon.add(const Duration(days: 3))),
        },
        'version': 2,
      });
      expect(live.everyone?.startsAt?.toUtc(), _noon);
      final cached = BroadcastState.fromData(live.toJson());
      expect(
        cached.everyone?.startsAt?.millisecondsSinceEpoch,
        _noon.millisecondsSinceEpoch,
      );
      expect(
        cached.everyone?.endsAt?.millisecondsSinceEpoch,
        _noon.add(const Duration(days: 3)).millisecondsSinceEpoch,
      );
      expect(cached.toJson(), live.toJson());
    });
  });

  group('what a reader sees', () {
    test('English only in an English app, and only when English was written',
        () {
      final both = _popup(
        titleEn: 'New update',
        bodyEn: 'Reminders per prayer.',
      );
      expect(both.title(false), 'New update');
      expect(both.showsArabic(false), isFalse);
      expect(both.title(true), 'تحديث جديد');
      expect(both.showsArabic(true), isTrue);

      final arabicOnly = _popup();
      expect(arabicOnly.title(false), 'تحديث جديد');
      expect(arabicOnly.body(false), 'صار عندك تذكير لكل صلاة.');
      expect(
        arabicOnly.showsArabic(false),
        isTrue,
        reason: 'the direction follows the words, not the app',
      );
    });

    test('an empty button falls back to the platform OK', () {
      expect(_popup().button(true), isNull);
      expect(_popup(buttonAr: 'تمام').button(true), 'تمام');
    });

    test('up from its start, gone at its end', () {
      final p = _popup(
        startsAt: _noon,
        endsAt: _noon.add(const Duration(days: 1)),
      );
      expect(
        p.isActiveAt(_noon.subtract(const Duration(minutes: 11))),
        isFalse,
      );
      expect(p.isActiveAt(_noon), isTrue);
      expect(p.isActiveAt(_noon.add(const Duration(days: 1))), isFalse);
    });

    test('a phone a few minutes slow still counts it as started', () {
      final p = _popup(startsAt: _noon);
      expect(
        p.isActiveAt(_noon.subtract(const Duration(minutes: 3))),
        isTrue,
        reason: 'the start is the Mac clock; phones drift',
      );
    });

    test('a test pop-up is for the named accounts only, never a guest', () {
      final p = _popup(testUidHashes: {broadcastUidHash('uidA')});
      expect(p.isFor('uidA'), isTrue);
      expect(p.isFor('uidB'), isFalse);
      expect(p.isFor(null), isFalse);
      expect(
        _popup().isFor(null),
        isTrue,
        reason: 'everyone means guests too',
      );
    });
  });

  group('which one to show', () {
    final everyone = _popup(id: 'p_everyone');
    final forUidA = _popup(
      id: 'p_test',
      testUidHashes: {broadcastUidHash('uidA')},
    );

    test("a test for this reader comes before everyone's", () {
      final state = BroadcastState(everyone: everyone, test: forUidA);
      expect(
        broadcastToShow(state, uid: 'uidA', now: _noon, seen: {})?.id,
        'p_test',
      );
      expect(
        broadcastToShow(state, uid: 'uidB', now: _noon, seen: {})?.id,
        'p_everyone',
      );
    });

    test('seen, not yet up, or already over: passed over', () {
      final state = BroadcastState(everyone: everyone, test: forUidA);
      expect(
        broadcastToShow(
          state,
          uid: 'uidA',
          now: _noon,
          seen: {'p_test', 'p_everyone'},
        ),
        isNull,
      );
      expect(
        broadcastToShow(
          state,
          uid: 'uidA',
          now: _noon.add(const Duration(days: 8)),
          seen: {},
        ),
        isNull,
      );
      expect(
        broadcastToShow(
          state,
          uid: 'uidA',
          now: _noon.subtract(const Duration(days: 1)),
          seen: {},
        ),
        isNull,
      );
    });
  });

  group('remembering what was shown', () {
    setUp(() => BroadcastStore.persistSeen = false);

    test('an id is remembered once, and the oldest goes at the limit', () {
      BroadcastStore.markSeen('p_first');
      BroadcastStore.markSeen('p_first');
      expect(BroadcastStore.seen, {'p_first'});
      for (var i = 0; i < BroadcastStore.seenLimit; i++) {
        BroadcastStore.markSeen('p_$i');
      }
      expect(BroadcastStore.seen.length, BroadcastStore.seenLimit);
      expect(BroadcastStore.seen.contains('p_first'), isFalse);
      expect(
        BroadcastStore.seen.contains('p_${BroadcastStore.seenLimit - 1}'),
        isTrue,
      );
    });
  });

  // The live document, followed the way the app follows it: every save the
  // admin makes arrives while the app is open, and the copy on the device
  // tracks it, so a cold start with no network still knows (and a pop-up
  // taken down is never shown from a stale copy).
  group('following the document', () {
    late Directory dir;
    late Box<dynamic> box;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('broadcast_store_test');
      Hive.init(dir.path);
      box = await Hive.openBox<dynamic>('settings_broadcast_test');
    });

    tearDown(() async {
      await box.deleteFromDisk();
      dir.deleteSync(recursive: true);
    });

    Map<String, Object?> popup(String id, String title) => {
          'id': id,
          'titleAr': title,
          'bodyAr': 'نص',
          'startsAt': Timestamp.fromDate(_noon),
          'endsAt': Timestamp.fromDate(_noon.add(const Duration(days: 7))),
        };

    test('each save arrives while the app is open, and the copy follows it',
        () async {
      final db = FakeFirebaseFirestore();
      BroadcastStore.listen(firestore: db, box: box, retryOnResume: false);
      await pumpEventQueue();
      expect(BroadcastStore.current.isEmpty, isTrue);

      await db.doc(kBroadcastDocPath).set({
        'everyone': popup('p_1', 'أول'),
        'test': null,
        'version': 1,
      });
      await pumpEventQueue();
      expect(BroadcastStore.current.everyone?.id, 'p_1');
      expect(box.get(BroadcastStore.cacheKey), contains('p_1'));

      // A second message replaces the first mid-session.
      await db.doc(kBroadcastDocPath).set({
        'everyone': popup('p_2', 'ثاني'),
        'test': null,
        'version': 2,
      });
      await pumpEventQueue();
      expect(BroadcastStore.current.everyone?.id, 'p_2');
      expect(box.get(BroadcastStore.cacheKey), contains('p_2'));

      // A cold start restores it from the device before any network.
      await BroadcastStore.reset();
      BroadcastStore.persistSeen = false;
      await BroadcastStore.loadCached(box);
      expect(BroadcastStore.current.everyone?.id, 'p_2');
    });

    test('a pop-up taken down leaves no copy to show later', () async {
      final db = FakeFirebaseFirestore();
      await db.doc(kBroadcastDocPath).set({
        'everyone': popup('p_1', 'أول'),
        'version': 1,
      });
      BroadcastStore.listen(firestore: db, box: box, retryOnResume: false);
      await pumpEventQueue();
      expect(box.get(BroadcastStore.cacheKey), isA<String>());

      await db.doc(kBroadcastDocPath).set({
        'everyone': null,
        'test': null,
        'version': 2,
      });
      await pumpEventQueue();
      expect(BroadcastStore.current.isEmpty, isTrue);
      expect(box.get(BroadcastStore.cacheKey), isNull);
    });

    test('what this device showed outlives a restart', () async {
      await BroadcastStore.loadCached(box);
      BroadcastStore.markSeen('p_1');
      await pumpEventQueue();
      expect(box.get(BroadcastStore.seenKey), ['p_1']);

      await BroadcastStore.reset();
      expect(BroadcastStore.seen, isEmpty);
      await BroadcastStore.loadCached(box);
      expect(BroadcastStore.seen, {'p_1'});
    });

    test('an unreadable copy on the device means nothing to show, not a crash',
        () async {
      await box.put(BroadcastStore.cacheKey, '{not json');
      await box.put(BroadcastStore.seenKey, 'not a list');
      await BroadcastStore.loadCached(box);
      expect(BroadcastStore.current.isEmpty, isTrue);
      expect(BroadcastStore.seen, isEmpty);
    });
  });
}
