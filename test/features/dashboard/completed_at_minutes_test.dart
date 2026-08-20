// The completion-time sidecar written into every daily doc.
//
// Nothing reads `completedAtMinutes` yet. It is tested anyway because the
// value is unrecoverable: a wrong stamp is not a bug that can be fixed
// later, it is history recorded wrong, and by the time a report exists to
// notice, the days it got wrong are gone.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
// The helper lives in dashboard_notifier_complete_habit.dart, which is a
// `part of` this library, so it is reached through the parent.
import 'package:grow_daily_v2/features/dashboard/notifiers/dashboard_notifier.dart';

void main() {
  group('minutesSinceMidnight', () {
    test('midnight is zero and the last minute of the day is 1439', () {
      expect(minutesSinceMidnight(DateTime(2026, 8, 20)), 0);
      expect(minutesSinceMidnight(DateTime(2026, 8, 20, 23, 59)), 1439);
    });

    test('counts from real local midnight, not the 6am day cutoff', () {
      // The wrinkle the doc comment warns about, pinned so nobody
      // "corrects" it into effectiveDay minutes later: 02:00 is 120, even
      // though effectiveDay still calls that moment the previous day.
      final twoAm = DateTime(2026, 8, 20, 2);
      expect(minutesSinceMidnight(twoAm), 120);
      // Same instant, and effectiveDay disagrees about which day it is.
      expect(twoAm.effectiveDay.day, 19);
    });

    test('a value below the cutoff marks the morning after the doc date', () {
      // Any stamp under 6 * 60 belongs to the calendar day AFTER the
      // document it sits on, which is the whole reason the wall-clock
      // choice is safe: the ambiguity is resolvable, an effectiveDay-based
      // offset would have thrown the real clock time away.
      const cutoffMinutes = 6 * 60;
      expect(minutesSinceMidnight(DateTime(2026, 8, 20, 2)),
          lessThan(cutoffMinutes));
      expect(minutesSinceMidnight(DateTime(2026, 8, 20, 9)),
          greaterThanOrEqualTo(cutoffMinutes));
    });

    test('is stable across the whole day', () {
      for (var h = 0; h < 24; h++) {
        for (final m in [0, 17, 59]) {
          expect(
            minutesSinceMidnight(DateTime(2026, 3, 9, h, m)),
            h * 60 + m,
          );
        }
      }
    });
  });
}
