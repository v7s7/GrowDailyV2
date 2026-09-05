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

    test('counts from real local midnight, and now agrees with the day', () {
      // This used to be the file's awkward case: 02:00 was 120 minutes while
      // effectiveDay called that same instant the PREVIOUS day, so the stamp
      // and the document it sat on disagreed and a reader had to resolve the
      // ambiguity. The day rolls at midnight now, so the two simply agree.
      final twoAm = DateTime(2026, 8, 20, 2);
      expect(minutesSinceMidnight(twoAm), 120);
      expect(twoAm.effectiveDay.day, 20,
          reason: 'the stamp and its document mean the same day');
    });

    test('a stamp always belongs to the document it sits on', () {
      // The property that replaced the old "a value below the cutoff means
      // the morning after" rule. No stamp is ever off-by-a-day now, at any
      // hour, so nothing downstream has to know a cutoff to read one.
      for (var h = 0; h < 24; h++) {
        final at = DateTime(2026, 8, 20, h, 30);
        expect(minutesSinceMidnight(at), h * 60 + 30);
        expect(at.effectiveDay, DateTime(2026, 8, 20), reason: '${h}:30');
      }
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
