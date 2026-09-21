// The Grid summary card's ring and its "N of M habits today" line pull from
// several independent rules at once — daily/specific-days/weekly-quota
// scheduling (boardHabitsOn, exhaustively covered on its own in
// habit_day_demand_test.dart), a user's own تخطّي, and a hand-marked جزئي —
// and nothing had ever exercised them TOGETHER through the actual widget.
// This is that sweep, plus the one place two of the card's own rules
// disagreed with each other.
//
// The bug: todayCompletionRatio reads a day with nothing owed (every habit
// either skipped or resting on its weekly quota) as ratio 1.0 — "a finished
// day, not an empty one", by that function's own doc comment. _RingStat used
// to pop its gold trophy on that same `ratio >= 1.0`, while perfectDay — the
// SAME card's border and "Perfect day" text — additionally requires
// owedTodayCount > 0 and stayed false. A day where everything was skipped
// therefore showed a celebratory trophy next to a "0" and a plain tap hint.
// The trophy now checks perfectDay instead of a bare ratio.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/grid/notifiers/weekly_grid_notifier.dart';

import '../../helpers/landing_harness.dart';

void main() {
  late LandingHarness h;

  const daily = 'inbox_zero'; // Inbox Zero — daily, every weekday.
  const quota = 'gym_consistency'; // Gym Consistency — 3x/week, any days.

  setUp(() async {
    h = LandingHarness();
    await h.prepare(activeCatalogIds: const [daily, quota]);
  });
  tearDown(() => h.dispose());

  const s = S(Locale('en'));

  /// The ring's own percentage digits — never a bare `find.text(value)`,
  /// because the week's day-of-month header (a plain 1-31, whatever week the
  /// suite happens to run in) can collide with any number a test computes.
  /// fontSize 24 is unique to _RingStat's number; see grid_screen_summary.dart.
  Finder ringPercent(String value) => find.byWidgetPredicate((w) =>
      w is Text && w.data == value && w.style?.fontSize == 24);

  /// greensToday's own big number, for the same date-collision reason as
  /// [ringPercent]. fontSize 34 is unique to it.
  Finder bigNumber(String value) => find.byWidgetPredicate(
      (w) => w is Text && w.data == value && w.style?.fontSize == 34);

  /// Puts [quota] into a rest day (spare or earned) for TODAY, whatever the
  /// real weekday happens to be — see weekly_quota_plan.dart's day-local
  /// arithmetic. Early in the week (today's index < 4) zero sessions is
  /// already spare on its own; from Wednesday on, banking the target on 3
  /// days strictly before today makes it earned instead. Either way the
  /// quota habit leaves today's denominator, so every test below is really
  /// only exercising [daily].
  Future<void> restQuotaToday(WidgetTester tester) async {
    final grid = h.container.read(weeklyGridProvider.notifier);
    final days = h.container.read(weeklyGridProvider).days;
    final today = DateTime.now().effectiveDay;
    final todayIndex = days.indexWhere((d) => d.isSameDayAs(today));
    if (todayIndex >= 4) {
      for (var i = 0; i < 3; i++) {
        grid.setSquareStateOnly(quota, days[i], SquareState.complete);
      }
    }
    await h.settle(tester);
  }

  /// [LandingHarness.settle], plus enough extra time for the trophy's own
  /// shimmer (~1.7s) to finish. Without this, a perfect day's celebration
  /// animation is still mid-flight when the test ends: its Timer trips
  /// flutter_test's "no pending timers" teardown check, and the stale
  /// widget tree it leaves behind bleeds into whichever test runs next in
  /// the same file. Use this instead of [LandingHarness.settle] in any test
  /// that can land on a perfect day.
  Future<void> settleTrophy(WidgetTester tester) async {
    await h.settle(tester);
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets('a plain daily habit, done: 1 of 1, perfect day, trophy',
      (tester) async {
    await h.pumpApp(tester);
    await restQuotaToday(tester);
    final grid = h.container.read(weeklyGridProvider.notifier);
    final today = DateTime.now().effectiveDay;
    grid.setSquareStateOnly(daily, today, SquareState.complete);
    await settleTrophy(tester);

    expect(bigNumber('1'), findsOneWidget,
        reason: 'greensToday counts the one finished habit');
    expect(find.text(s.gridOfHabitsToday(1)), findsOneWidget,
        reason: 'the resting quota habit must not inflate the denominator');
    expect(find.text(s.gridPerfectDay), findsOneWidget);
    expect(find.byIcon(Icons.emoji_events_rounded), findsOneWidget);
  });

  testWidgets(
      'a half-done (جزئي) habit counts half toward the ring, zero toward the count',
      (tester) async {
    await h.pumpApp(tester);
    await restQuotaToday(tester);
    final grid = h.container.read(weeklyGridProvider.notifier);
    final today = DateTime.now().effectiveDay;
    grid.setSquareStateOnly(daily, today, SquareState.partial);
    await h.settle(tester);

    expect(bigNumber('0'), findsOneWidget,
        reason: 'a جزئي is not a finished habit');
    expect(find.text(s.gridOfHabitsToday(1)), findsOneWidget);
    expect(ringPercent('50'), findsOneWidget,
        reason: 'the ring reads the flat half a hand-marked جزئي gets');
    expect(find.text(s.gridPerfectDay), findsNothing);
    expect(find.byIcon(Icons.emoji_events_rounded), findsNothing);
  });

  testWidgets('a تخطّي leaves the day entirely, not just scores zero in it',
      (tester) async {
    await h.pumpApp(tester);
    await restQuotaToday(tester);
    final grid = h.container.read(weeklyGridProvider.notifier);
    final today = DateTime.now().effectiveDay;
    grid.setSquareStateOnly(daily, today, SquareState.skipped);
    await h.settle(tester);

    // Nothing owed today: the quota is resting and the only other habit was
    // skipped. todayCompletionRatio reads that as a finished day (1.0), but
    // perfectDay must not, or a fully-skipped day would earn the trophy this
    // test exists to catch.
    expect(find.text(s.gridTapHint), findsOneWidget,
        reason: 'owedTodayCount is 0, so the label must not claim "of 0"');
    expect(find.text(s.gridPerfectDay), findsNothing,
        reason: 'nothing was owed, so nothing was achieved either');
    expect(find.byIcon(Icons.emoji_events_rounded), findsNothing,
        reason: 'the bug this file exists for: a skipped day is not a trophy');
  });

  // A رست quota habit's own جزئي: not owed today, so it can never bank a
  // weekly session (a partial mark is never green — see habitOwesDay), but
  // the effort was real, and the ring is the one place it is now safe to
  // show it. See _SummaryCard._widenForRestingPartials.
  group('a resting quota habit\'s own جزئي', () {
    testWidgets('moves the ring when it can only help, not the "of N" count',
        (tester) async {
      await h.pumpApp(tester);
      await restQuotaToday(tester);
      final grid = h.container.read(weeklyGridProvider.notifier);
      final today = DateTime.now().effectiveDay;
      // daily explicitly none (LandingHarness never closes its Hive boxes
      // between tests in one file, so a bare assumption of "untouched" can
      // inherit a mark an earlier test in this same file left behind):
      // base ratio is 0/1. Adding the resting quota's own 0.5 raises it to
      // 0.5/2 = 25%, which the greedy check must accept since 25% > 0%.
      grid.setSquareStateOnly(daily, today, SquareState.none);
      grid.setSquareStateOnly(quota, today, SquareState.partial);
      await h.settle(tester);

      expect(ringPercent('25'), findsOneWidget,
          reason: 'the resting جزئي raised the ring from 0% to 25%');
      expect(bigNumber('0'), findsOneWidget,
          reason: 'greensToday still only counts finished, required habits');
      expect(find.text(s.gridOfHabitsToday(1)), findsOneWidget,
          reason: 'the resting habit still does not inflate what was owed');
    });

    testWidgets('never lowers the ring, or a perfect required day would stop reading perfect',
        (tester) async {
      await h.pumpApp(tester);
      await restQuotaToday(tester);
      final grid = h.container.read(weeklyGridProvider.notifier);
      final today = DateTime.now().effectiveDay;
      // daily finishes the one required habit: base ratio is already 1/1
      // (100%). Folding the resting quota's own 0.5 in would drag it down
      // to 1.5/2 = 75%, so the greedy check must refuse it.
      grid.setSquareStateOnly(daily, today, SquareState.complete);
      grid.setSquareStateOnly(quota, today, SquareState.partial);
      await settleTrophy(tester);

      expect(find.text(s.gridPerfectDay), findsOneWidget,
          reason: 'every REQUIRED habit is done; a bonus half-effort on '
              'something never asked for must not cost the trophy');
      expect(find.byIcon(Icons.emoji_events_rounded), findsOneWidget);
      expect(ringPercent('75'), findsNothing,
          reason: 'the resting جزئي must never be allowed to pull the day down');
    });
  });
}
