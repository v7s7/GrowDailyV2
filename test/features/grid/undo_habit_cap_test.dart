// The Grid's Undo after a pause, and the habit cap.
//
// An Undo puts back what the board held a moment ago, so it may always climb
// back to that, even above the cap: an account whose Premium ended with 12
// habits that pauses one by mistake gets it back. Until 2026-09-26 it asked
// nothing at all, so a full board could pause a habit, add another inside
// the Undo's six seconds and Undo: one over the cap (and after a multi-select
// remove, as many over as the plan added). See undoFitsHabitCap.
//
// The harness is a guest, whose cap is kGuestHabitLimit (5).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/habits/catalog/habit_plans.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';

import '../../helpers/landing_harness.dart';

void main() {
  const s = S(Locale('en'));

  group('undoFitsHabitCap', () {
    test('Premium is never refused', () {
      expect(
        undoFitsHabitCap(limit: null, current: 40, returning: 5, hadBefore: 0),
        isTrue,
      );
    });

    test('a plain Undo climbs back to the board it had, even above the cap',
        () {
      // Premium ended at 12; one paused by mistake; Undo.
      expect(
        undoFitsHabitCap(limit: 10, current: 11, returning: 1, hadBefore: 12),
        isTrue,
      );
    });

    test('an Undo after an add in between is refused past the cap', () {
      // 10, pause one (9), add one (10), Undo: 11.
      expect(
        undoFitsHabitCap(limit: 10, current: 10, returning: 1, hadBefore: 10),
        isFalse,
      );
      // 10, remove 5, a 5-habit plan (10), Undo: 15.
      expect(
        undoFitsHabitCap(limit: 10, current: 10, returning: 5, hadBefore: 10),
        isFalse,
      );
    });

    test('an Undo that stays inside the cap is fine whatever came between',
        () {
      expect(
        undoFitsHabitCap(limit: 10, current: 8, returning: 2, hadBefore: 7),
        isTrue,
      );
    });
  });

  // One test, not two. The pause and the Undo save the guest's board to
  // Hive, and a save started on a widget test's fake clock never finishes:
  // the next test's setUp then waits on the box for ten minutes (the
  // widget-tests-and-Hive trap). Running the taps on the real clock instead
  // leaves SnackBar callbacks firing after the tree is gone. One setUp has
  // neither problem, and the harness never awaits Hive on the way out.
  group('the pause Undo on the Grid', () {
    late LandingHarness h;
    const board = [
      'inbox_zero',
      'daily_walk',
      'gym_consistency',
      'sleep_schedule',
      'deep_work_block',
    ];

    setUp(() async {
      h = LandingHarness();
      await h.prepare(
        activeCatalogIds: board,
        // Signed out is not guest mode on its own; the guest cap needs it.
        extraOverrides: [guestModeProvider.overrideWith((ref) => true)],
      );
    });
    tearDown(() => h.dispose());

    Set<String> active() => h.container.read(activeCatalogProvider);

    Future<void> pauseInboxZero(WidgetTester tester) async {
      // The last row sits below the 600pt test view.
      await tester.ensureVisible(find.text('Inbox Zero').first);
      await h.settle(tester);
      await tester.tap(find.text('Inbox Zero').first);
      await h.settle(tester);
      await tester.tap(find.text(s.habitPause));
      await h.settle(tester);
      // The «إلى متى؟» sheet: its confirm is the same word.
      await tester.tap(find.widgetWithText(FilledButton, s.habitPause));
      await h.settle(tester);
      expect(active().contains('inbox_zero'), isFalse,
          reason: 'sanity: the pause landed');
      expect(find.text(s.undo), findsOneWidget);
    }

    testWidgets(
        'straight back the Undo restores it; after another habit took its '
        'place the Undo is refused', (tester) async {
      await h.pumpApp(tester);
      expect(active(), hasLength(kGuestHabitLimit),
          reason: 'sanity: the board starts full');

      await pauseInboxZero(tester);
      await tester.tap(find.text(s.undo));
      await h.settle(tester);
      expect(active().contains('inbox_zero'), isTrue,
          reason: 'back to the board it had a moment ago');
      expect(find.text(s.guestLimitTitle), findsNothing);

      await pauseInboxZero(tester);
      h.container.read(activeCatalogProvider.notifier).toggle('daily_planning');
      await tester.pump();
      expect(active(), hasLength(kGuestHabitLimit));

      await tester.tap(find.text(s.undo));
      await h.settle(tester);
      expect(find.text(s.guestLimitTitle), findsOneWidget,
          reason: 'the cap answers, as it does for any add');
      expect(active().contains('inbox_zero'), isFalse,
          reason: 'it stays paused, where Resume asks the same cap');
      expect(active(), hasLength(kGuestHabitLimit));
    });
  });
}
