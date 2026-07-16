// Deterministic tests for DateTimeGameExt.isRealToday - the plain,
// midnight-based "is this today on the real device calendar" check added
// alongside the existing cutoff-aware isToday/effectiveDay (see that
// getter's doc comment for why both exist: isRealToday drives the "today"
// highlight in calendar-style views - Grid header, Monthly Heatmap, Night
// Review, Rooms, Matrix history - while isToday/effectiveDay still drives
// everything that earns a reward, unchanged).
//
// isRealToday calls DateTime.now() internally and can't be pointed at an
// arbitrary simulated clock (nothing in this codebase injects a fake
// clock), so these tests can only verify its own definition is correct
// relative to whatever "now" actually is when the suite runs - not the
// specific 12am-3am divergence from isToday, which depends on which exact
// moment the test happens to execute at. See room_model_test.dart's "room
// still active" group for the same constraint applied to a different
// getter.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';

void main() {
  group('DateTimeGameExt.isRealToday', () {
    test('true for right now', () {
      expect(DateTime.now().isRealToday, isTrue);
    });

    test('true for any time of day on the same real calendar date', () {
      final now = DateTime.now();
      expect(DateTime(now.year, now.month, now.day, 0, 1).isRealToday, isTrue);
      expect(DateTime(now.year, now.month, now.day, 12, 0).isRealToday, isTrue);
      expect(DateTime(now.year, now.month, now.day, 23, 59).isRealToday, isTrue);
    });

    test('false for yesterday', () {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      expect(yesterday.isRealToday, isFalse);
    });

    test('false for tomorrow', () {
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      expect(tomorrow.isRealToday, isFalse);
    });

    test('matches isSameDayAs(DateTime.now()) exactly, by definition', () {
      final now = DateTime.now();
      final aFewDaysOut = now.add(const Duration(days: 3));
      expect(aFewDaysOut.isRealToday, aFewDaysOut.isSameDayAs(now));
    });
  });
}
