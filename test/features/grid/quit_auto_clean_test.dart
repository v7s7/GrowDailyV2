// Pure-logic tests for the quit-habit auto-clean eligibility rule — see
// isQuitAutoCleanEligible's own doc comment for why all four conditions
// must hold, and WeeklyGridNotifier.autoCleanQuitDay for what an eligible
// habit's untouched yesterday actually gets (a visual-only green square,
// never rewards).
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/grid/notifiers/weekly_grid_notifier.dart';

void main() {
  group('isQuitAutoCleanEligible', () {
    test('qualifies only when all four conditions hold', () {
      expect(
        isQuitAutoCleanEligible(
          isQuit: true,
          isSingleTap: true,
          wasScheduled: true,
          hasEverCompleted: true,
        ),
        isTrue,
      );
    });

    test('build habits never qualify — silence genuinely is a miss', () {
      expect(
        isQuitAutoCleanEligible(
          isQuit: false,
          isSingleTap: true,
          wasScheduled: true,
          hasEverCompleted: true,
        ),
        isFalse,
      );
    });

    test('weekly-target quit habits never qualify — no per-day square sync', () {
      expect(
        isQuitAutoCleanEligible(
          isQuit: true,
          isSingleTap: false,
          wasScheduled: true,
          hasEverCompleted: true,
        ),
        isFalse,
      );
    });

    test('an unscheduled day has nothing to be clean about', () {
      expect(
        isQuitAutoCleanEligible(
          isQuit: true,
          isSingleTap: true,
          wasScheduled: false,
          hasEverCompleted: true,
        ),
        isFalse,
      );
    });

    test(
        'a never-once-affirmed habit never qualifies — auto-clean continues '
        'a record, it does not invent the first day', () {
      expect(
        isQuitAutoCleanEligible(
          isQuit: true,
          isSingleTap: true,
          wasScheduled: true,
          hasEverCompleted: false,
        ),
        isFalse,
      );
    });
  });
}
