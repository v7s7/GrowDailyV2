// A pass that grades several rooms reads each CLOSED day of the member's own
// record once, not once per room (see RoomDayReads). Measured 2026-09-22:
// the room resync was about 56% of a typical account's Firestore reads, and a
// member in three rooms read every day of the window three times per pass.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/rooms/notifiers/room_day_reads.dart';

void main() {
  group('RoomDayReads', () {
    test('a closed day is read once for every room of the pass', () async {
      final reads = RoomDayReads<String>('member');
      var fetched = 0;
      Future<String> fetch() async {
        fetched++;
        return 'snapshot $fetched';
      }

      // Three rooms grading the same closed day.
      final a = await reads.read('2026-09-14', closed: true, fetch: fetch);
      final b = await reads.read('2026-09-14', closed: true, fetch: fetch);
      final c = await reads.read('2026-09-14', closed: true, fetch: fetch);
      expect(fetched, 1);
      expect([a, b, c], ['snapshot 1', 'snapshot 1', 'snapshot 1'],
          reason: 'every room grades from the very same snapshot');
    });

    test('different days are separate reads', () async {
      final reads = RoomDayReads<String>('member');
      var fetched = 0;
      Future<String> fetchFor(String key) async {
        fetched++;
        return key;
      }

      for (final key in ['2026-09-13', '2026-09-14', '2026-09-13']) {
        expect(
          await reads.read(key, closed: true, fetch: () => fetchFor(key)),
          key,
        );
      }
      expect(fetched, 2);
    });

    test('a day still open is read fresh for each room', () async {
      // Today (and yesterday until 10:00) can take a square between two rooms
      // of the pass, so it is never shared.
      final reads = RoomDayReads<String>('member');
      var fetched = 0;
      Future<String> fetch() async => 'read ${++fetched}';

      await reads.read('2026-09-22', closed: false, fetch: fetch);
      await reads.read('2026-09-22', closed: false, fetch: fetch);
      expect(fetched, 2);
    });

    test('concurrent rooms join the read already in flight', () async {
      final reads = RoomDayReads<String>('member');
      var fetched = 0;
      Future<String> fetch() async {
        fetched++;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return 'snapshot';
      }

      final both = await Future.wait([
        reads.read('2026-09-14', closed: true, fetch: fetch),
        reads.read('2026-09-14', closed: true, fetch: fetch),
      ]);
      expect(fetched, 1);
      expect(both, ['snapshot', 'snapshot']);
    });

    test('a failed read is not handed on: the next room retries it', () async {
      final reads = RoomDayReads<String>('member');
      var attempts = 0;
      Future<String> flaky() async {
        attempts++;
        if (attempts == 1) throw StateError('offline');
        return 'snapshot';
      }

      await expectLater(
        reads.read('2026-09-14', closed: true, fetch: flaky),
        throwsStateError,
      );
      expect(await reads.read('2026-09-14', closed: true, fetch: flaky),
          'snapshot');
      expect(await reads.read('2026-09-14', closed: true, fetch: flaky),
          'snapshot');
      expect(attempts, 2, reason: 'retried once, then shared');
    });

    test('it knows whose days it holds', () {
      expect(RoomDayReads<String>('member').uid, 'member');
    });
  });

  test('every multi-room pass shares its reads, a single sync does not', () {
    // Source sweep, the pattern of half_square_counts_everywhere_test: the
    // saving only exists where a caller hands the same RoomDayReads to each
    // room of a loop.
    final src = File('lib/features/rooms/notifiers/rooms_notifier.dart')
        .readAsStringSync();
    String body(String signature) {
      final start = src.indexOf(signature);
      expect(start, isNot(-1), reason: '$signature is missing');
      final end = src.indexOf('\n  }\n', start);
      return src.substring(start, end);
    }

    for (final pass in [
      'Future<void> resyncAllMyRooms()',
      'Future<void> syncHabitDay(',
      'Future<void> syncTodayForHabit(',
    ]) {
      expect(body(pass), contains('dayReads: dayReads'),
          reason: '$pass grades rooms in a loop and must share its reads');
    }
    // Only closed days go through the shared reads.
    expect(src, contains('closed: d.isBefore(firstOpen)'));
  });
}
