// The flex window itself: how long after midnight a completion still lands
// on the night before. effectiveDay is the single rule every streak key,
// grid square, and daily log goes through, and until now nothing pinned it
// — datetime_ext_test.dart covers only isRealToday, and day_closing_window
// _test.dart covers only the warning banner's window.
//
// The window was widened from 6 hours to 10 (kDayCutoffHour 6 -> 10) so
// that someone who sleeps until 9-something still opens yesterday's board.
// These tests are written against kDayCutoffHour rather than the literal
// 10, so they describe the RULE and survive the next move; the one place
// the number itself matters is the last group, which is the promise the
// widen was made to keep.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';

void main() {
  // A Wednesday, and the Thursday after it.
  final wed = DateTime(2026, 8, 19);
  final thu = DateTime(2026, 8, 20);

  DateTime thuAt(int h, [int m = 0]) => DateTime(2026, 8, 20, h, m);

  group('effectiveDay rolls at the cutoff, not at midnight', () {
    test('every hour before the cutoff still belongs to the day before', () {
      for (var h = 0; h < kDayCutoffHour; h++) {
        expect(
          thuAt(h).effectiveDay,
          wed,
          reason: '${h}:00 Thursday should still be Wednesday',
        );
      }
    });

    test('the cutoff hour itself is the first instant of the new day', () {
      expect(thuAt(kDayCutoffHour - 1, 59).effectiveDay, wed);
      expect(thuAt(kDayCutoffHour).effectiveDay, thu);
      expect(thuAt(kDayCutoffHour, 1).effectiveDay, thu);
    });

    test('everything after the cutoff is the new day, up to midnight', () {
      for (var h = kDayCutoffHour; h < 24; h++) {
        expect(thuAt(h).effectiveDay, thu, reason: '${h}:00 should be Thursday');
      }
    });

    test('the window is exactly kDayCutoffHour hours long', () {
      final firstOfDay = thu.add(const Duration(hours: kDayCutoffHour));
      final lastOfDay = firstOfDay
          .add(const Duration(days: 1))
          .subtract(const Duration(minutes: 1));
      expect(firstOfDay.effectiveDay, thu);
      expect(lastOfDay.effectiveDay, thu);
      // One minute either side falls into the neighbouring days.
      expect(
        firstOfDay.subtract(const Duration(minutes: 1)).effectiveDay,
        wed,
      );
      expect(
        lastOfDay.add(const Duration(minutes: 1)).effectiveDay,
        thu.add(const Duration(days: 1)),
      );
    });
  });

  group('isToday follows effectiveDay, so the board stays open', () {
    test('a marked-up day is still "today" for the whole flex window', () {
      // isToday reads DateTime.now() internally, so this asserts the
      // definition rather than a simulated clock: whatever the current
      // effective day is, it is isToday, and the calendar date one day on
      // from it is not.
      final today = DateTime.now().effectiveDay;
      expect(today.isToday, isTrue);
      expect(today.add(const Duration(days: 1)).isToday, isFalse);
      expect(today.subtract(const Duration(days: 1)).isYesterday, isTrue);
    });
  });

  group('the promise the widen was made to keep', () {
    test('a habit finished at 9:59am counts for the day before', () {
      // Slept through the night, woke at half nine, opened the app. The
      // board is still Wednesday's and marking it earns Wednesday's gold
      // and streak point, exactly as if the day had never rolled.
      expect(thuAt(9, 0).effectiveDay, wed);
      expect(thuAt(9, 59).effectiveDay, wed);
    });

    test('4am, the case the old 6am window already covered, still works', () {
      expect(thuAt(4, 0).effectiveDay, wed);
    });

    test('the four hours the widen added all land on the day before', () {
      // 06:00-09:59 is precisely what moving 6 -> 10 bought. Under the old
      // cutoff every one of these was already the new day.
      for (var h = 6; h < 10; h++) {
        expect(thuAt(h).effectiveDay, wed, reason: '${h}:00 should be Wednesday');
      }
    });

    test('10am is the hard stop, and it clears Dhuhr', () {
      // Ten, not twelve: Dhuhr in Bahrain runs 11:22-11:53 all year
      // (assets/prayer/bahrain_official.json), so a noon cutoff would have
      // banked every on-time Dhuhr against the previous day. The earliest
      // Dhuhr of the year is still comfortably past this boundary.
      expect(thuAt(10, 0).effectiveDay, thu);
      expect(thuAt(11, 22).effectiveDay, thu, reason: 'earliest Dhuhr of the year');
      expect(thuAt(11, 53).effectiveDay, thu, reason: 'latest Dhuhr of the year');
    });
  });
}
