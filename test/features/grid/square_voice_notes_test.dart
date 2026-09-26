// Where a square's voice notes live (square_voice_notes.dart): their own
// document per square plus one index document, never the day's `daily`
// document, and a guest's in Hive with no base64 copy.
import 'dart:async';
import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/grid/notifiers/square_voice_notes.dart';
import 'package:grow_daily_v2/features/matrix/models/matrix_task.dart';
import 'package:hive/hive.dart';

VoiceNote _note(String id, {String? audio}) => VoiceNote(
      id: id,
      path: '/tmp/$id.m4a',
      name: '',
      durationSeconds: 7,
      createdAt: DateTime(2026, 9, 25, 21),
      audioBase64: audio,
    );

/// A store whose counts arrive only when the test says so.
class _SlowStore extends SquareVoiceStore {
  final loaded = Completer<Map<String, int>>();

  @override
  Future<Map<String, int>> loadCounts(String? uid) => loaded.future;
}

void main() {
  final day = DateTime(2026, 9, 25);

  group('the square key', () {
    test('day first, then a habit id that may hold underscores of its own',
        () {
      final key = squareVoiceKey('prayer_maghrib', day);
      expect(key, '2026-09-25_prayer_maghrib');
      final back = parseSquareVoiceKey(key)!;
      expect(back.day, day);
      expect(back.habitId, 'prayer_maghrib');
    });

    test('anything else is not a key', () {
      for (final bad in ['', '2026-09-25', '2026-09-25-x', 'nonsense_key_x']) {
        expect(parseSquareVoiceKey(bad), isNull, reason: bad);
      }
    });

    test('the index keeps only real counts', () {
      expect(
        parseSquareVoiceCounts({
          'counts': {'a': 2, 'b': 0, 'c': 'x', 'd': -1},
        }),
        {'a': 2},
      );
      expect(parseSquareVoiceCounts(null), isEmpty);
      expect(parseSquareVoiceCounts({'counts': 'nope'}), isEmpty);
    });
  });

  group('a signed-in account', () {
    late FakeFirebaseFirestore db;
    late SquareVoiceStore store;
    final key = squareVoiceKey('prayer_maghrib', day);

    setUp(() {
      db = FakeFirebaseFirestore();
      store = SquareVoiceStore(firestore: db);
    });

    test('recordings go to their own document, never the daily one',
        () async {
      await store.save('u1', key, [_note('a', audio: 'QUJD'), _note('b')]);

      final doc =
          await db.doc('users/u1/square_voice/$key').get();
      expect(doc.exists, isTrue);
      expect(doc.data()!['dateKey'], '2026-09-25');
      expect(doc.data()!['habitId'], 'prayer_maghrib');
      expect((doc.data()!['notes'] as List), hasLength(2));
      expect((await db.collection('users/u1/daily').get()).docs, isEmpty,
          reason: 'audio in the day document would load for every reader '
              'of that day');

      final loaded = await store.load('u1', key);
      expect(loaded.map((n) => n.id), ['a', 'b']);
      expect(loaded.first.audioBase64, 'QUJD',
          reason: 'the base64 copy is what reaches a second phone');
    });

    test('the index counts the square, and forgets it when emptied',
        () async {
      await store.save('u1', key, [_note('a'), _note('b')]);
      expect(await store.loadCounts('u1'), {key: 2});

      await store.save('u1', key, const []);
      expect(await store.loadCounts('u1'), isEmpty);
      expect((await db.doc('users/u1/square_voice/$key').get()).exists,
          isFalse);
    });

    test('a new recording is appended, never written over the list',
        () async {
      // The editor may not have read the square (an index that never
      // loaded), so add must not need to: a rewrite from an editor that saw
      // "none" would have replaced both of these with the third.
      await store.save('u1', key, [_note('a'), _note('b')]);
      await store.add('u1', key, _note('c'));
      expect((await store.load('u1', key)).map((n) => n.id), ['a', 'b', 'c']);
      expect(await store.loadCounts('u1'), {key: 3});
    });

    test('adding to a square with nothing yet starts it', () async {
      await store.add('u1', key, _note('a'));
      final doc = await db.doc('users/u1/square_voice/$key').get();
      expect(doc.data()!['dateKey'], '2026-09-25');
      expect(doc.data()!['habitId'], 'prayer_maghrib');
      expect(await store.loadCounts('u1'), {key: 1});
    });

    test('two squares keep two rows in one index document', () async {
      final other = squareVoiceKey('morning_athkar', day);
      await store.save('u1', key, [_note('a')]);
      await store.save('u1', other, [_note('b'), _note('c')]);
      expect(await store.loadCounts('u1'), {key: 1, other: 2});
    });
  });

  group('a guest', () {
    late Directory tmp;
    final store = SquareVoiceStore();
    final key = squareVoiceKey('prayer_fajr', day);

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('square_voice_guest_');
      Hive.init(tmp.path);
      await Hive.openBox<dynamic>('box_settings');
    });

    tearDown(() async {
      await Hive.deleteFromDisk();
      await tmp.delete(recursive: true);
    });

    test('a guest\'s add appends to the phone\'s own list', () async {
      await store.save(null, key, [_note('a')]);
      await store.add(null, key, _note('b'));
      expect((await store.load(null, key)).map((n) => n.id), ['a', 'b']);
      expect(await store.loadCounts(null), {key: 2});
    });

    test('keeps recordings on the phone, without a base64 copy', () async {
      await store.save(null, key, [_note('a', audio: 'QUJD')]);

      final loaded = await store.load(null, key);
      expect(loaded.single.id, 'a');
      expect(loaded.single.audioBase64, isNull,
          reason: 'a guest has no second phone to carry audio to');
      expect(await store.loadCounts(null), {key: 1});

      await store.save(null, key, const []);
      expect(await store.load(null, key), isEmpty);
      expect(await store.loadCounts(null), isEmpty);
    });
  });

  group('the index notifier', () {
    test('a count set before the load arrives outlives the load', () async {
      final store = _SlowStore();
      final index = SquareVoiceIndexNotifier(store, 'u1');
      final fresh = squareVoiceKey('a', day);
      final deleted = squareVoiceKey('b', day);

      index.setCount(fresh, 1);
      index.setCount(deleted, 0);
      store.loaded.complete({deleted: 3, squareVoiceKey('c', day): 2});
      await Future<void>.delayed(Duration.zero);

      expect(index.state, {fresh: 1, squareVoiceKey('c', day): 2},
          reason: 'what this phone just did is newer than what was read');
      expect(index.has('a', day), isTrue);
      expect(index.has('b', day), isFalse);
      index.dispose();
    });

    test('an add is an increment: the load may already hold it', () async {
      final store = _SlowStore();
      final index = SquareVoiceIndexNotifier(store, 'u1');
      final key = squareVoiceKey('a', day);
      expect(index.loaded, isFalse,
          reason: 'until it has read, "no recordings" is not known');

      index.added(key); // 1 here, before the read lands
      store.loaded.complete({key: 3}); // the server already counted it
      await Future<void>.delayed(Duration.zero);

      expect(index.loaded, isTrue);
      expect(index.state[key], 3,
          reason: 'the larger, never the sum: the increment is in the 3');
      index.dispose();
    });

    test('a failed load leaves no corners and throws nothing', () async {
      final store = _SlowStore();
      final index = SquareVoiceIndexNotifier(store, 'u1');
      store.loaded.completeError(StateError('offline'));
      await Future<void>.delayed(Duration.zero);
      expect(index.state, isEmpty);
      index.dispose();
    });
  });
}
