// The Reports header's percentage counts جزئي as half, as its cards do.
//
// Aziz, 2026-09-11, asked "Reports header: should جزئي count as half?":
// "yes". Every card divides its credit (جزئي worth 0.5, see markCredit) by
// what its habit owed, while the header above them divided green squares by
// the same owed days, so one habit with two greens and a جزئي in five owed
// days read 40% in the header over a card reading 50%.
//
// The rule these tests pin: the header's rate is the cards' credit summed
// over the cards' owed days summed, on the same days (the free floor too)
// and at the same clock, so a جزئي on a day still open waits in the header
// exactly as it waits on its card. The header's other numbers are counts of
// days and do not move: green squares, the best day, active days, the
// longest run, and the change against last period. No habit is capped before
// the sum, which is how the header already treated a quota habit that beat
// its target.
//
// The first groups are the arithmetic, built the way the reports hub builds
// it. The last mounts the real PeriodReportSection under a pinned day clock,
// as report_open_day_wiring_test.dart does, so a screen that handed the
// header anything but the cards' own stats would show here.
//
// Most of what follows fails on its numbers before this change. Four cases
// are guards instead, which the old header already satisfied: the calendar
// every weekday claim here rests on, the two placeholder cases where credit
// lands on a period that owed nothing, and the 100% cap, which reads the
// same either way and is now the only thing holding down a header holding
// more credit than it owed. The empty-state gate is NOT one of the guards,
// whatever it looks like: it pins this change too, because the week it reads
// prints 50% here and printed 0% before. The three questions still open (the
// gate, the per-habit cap, and the archived row whose marks are all halves)
// each have a case of their own, so none of them can be moved quietly.
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/core/providers/day_clock_provider.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/dashboard/notifiers/dashboard_notifier.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';
import 'package:grow_daily_v2/features/milestones/notifiers/habit_history_notifier.dart';
import 'package:grow_daily_v2/features/milestones/reports/period_report_section.dart';
import 'package:grow_daily_v2/features/milestones/reports/report_period.dart';
import 'package:grow_daily_v2/features/milestones/reports/report_sections.dart';
import 'package:grow_daily_v2/features/premium/notifiers/premium_notifier.dart';
import 'package:grow_daily_v2/shared/widgets/segmented_tabs.dart';
import 'package:hive/hive.dart';

class _Premium extends PremiumNotifier {
  _Premium(bool value) {
    state = value;
  }
}

/// A dashboard that is already loaded, as in report_open_day_wiring_test.dart:
/// the report renders a spinner while it loads, and every number read here
/// comes from the history override, not from this state.
class _LoadedDash extends DashboardNotifier {
  _LoadedDash() : super(null) {
    state = const DashboardState(
      level: 1,
      currentLevelXp: 0,
      cumulativeXp: 0,
      gold: 0,
      streak: 0,
      completions: {},
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  IslamicHabitTemplate habit(
    String id, {
    HabitFrequencyType type = HabitFrequencyType.daily,
    int target = 1,
    List<int> weekdays = const [],
    DateTime? createdAt,
    DateTime? archivedAt,
  }) =>
      IslamicHabitTemplate(
        id: id,
        name: id,
        description: '',
        category: HabitCategory.faith,
        frequencyType: type,
        frequencyTarget: target,
        scheduledWeekdays: weekdays,
        hasTimer: false,
        xpReward: 10,
        goldReward: 1,
        createdAt: createdAt,
        archivedAt: archivedAt,
      );

  String aug(int day) => DateTime(2026, 8, day).toDateKey();
  String sep(int day) => DateTime(2026, 9, day).toDateKey();

  /// Printed the way the header and the cards print it.
  String pct(double rate) => '${(rate * 100).round()}%';

  /// The header and the cards under it, built the way the reports hub builds
  /// them (period_report_section.dart): the window's elapsed days, floored to
  /// what the viewer may see, measured at [now] against the window's end, and
  /// the summary taken from those same stats.
  ///
  /// One difference under a floor, which nothing here leans on: the hub
  /// builds TWO stats lists, unfloored for the cards and floored for the
  /// header. This helper returns the floored pass for both, so a floored
  /// case here is the HEADER's own stats and promises nothing about the
  /// cards the hub draws beside it.
  ({PeriodSummary summary, List<HabitPeriodStat> stats}) report({
    required List<IslamicHabitTemplate> habits,
    required Map<String, Map<String, SquareState>> history,
    required ({DateTime start, DateTime end}) window,
    required DateTime now,
    DateTime? floor,
  }) {
    final days = visibleDaysFrom(
      days: elapsedDaysIn(
        start: window.start,
        end: window.end,
        today: now.effectiveDay,
      ),
      floor: floor,
    );
    final stats = computeHabitPeriodStats(
      habits: habits,
      history: history,
      days: days,
      now: now,
      windowEnd: window.end,
    );
    return (
      summary: computePeriodSummary(
        dayCounts: dayCountsFrom(stats),
        days: days,
        habitStats: stats,
        now: now,
      ),
      stats: stats,
    );
  }

  test('the calendar these tests rest on', () {
    expect(DateTime(2026, 8).weekday, DateTime.saturday);
    expect(DateTime(2026, 8, 3).weekday, DateTime.monday);
    expect(DateTime(2026, 8, 29).weekday, DateTime.saturday);
    expect(DateTime(2026, 9, 5).weekday, DateTime.saturday);
    expect(DateTime(2026, 9, 8).weekday, DateTime.tuesday);
    expect(DateTime(2026, 9, 11).weekday, DateTime.friday);
  });

  group('one habit: the header reads what its card reads', () {
    test('two greens and a جزئي in five owed days: 50%, not 40%', () {
      // Read at 10:00 on Thursday 6 August: the 1st to the 5th have closed,
      // the 6th is still open and blank.
      final r = report(
        habits: [habit('h')],
        history: {
          'h': {
            aug(1): SquareState.complete,
            aug(2): SquareState.complete,
            aug(3): SquareState.partial,
          },
        },
        window: reportWindow(ReportScope.week, DateTime(2026, 8, 6)),
        now: DateTime(2026, 8, 6, kDayCutoffHour),
      );
      final card = r.stats.single;
      expect(
        (card.expected, card.creditedUnits, pct(card.rate)),
        (5, 2.5, '50%'),
      );
      final summary = r.summary;
      expect(
        (summary.expectedTotal, summary.creditedTotal, pct(summary.rate)),
        (5, 2.5, '50%'),
        reason: 'green squares over owed days read 40%',
      );
      expect(summary.rate, card.rate);
      expect(
        (
          summary.totalDone,
          summary.activeDays,
          summary.bestDayCount,
          summary.longestRun,
        ),
        (2, 2, 1, 2),
        reason: 'the counts of days do not take the half',
      );
    });
  });

  group('several habits: credit summed over owed summed', () {
    test('not the mean of the cards', () {
      // h is the habit above, 2.5 of 5. monday owes Mondays only, and Monday
      // the 3rd was done: 1 of 1.
      final r = report(
        habits: [
          habit('h'),
          habit(
            'monday',
            type: HabitFrequencyType.weekly,
            weekdays: const [DateTime.monday],
          ),
        ],
        history: {
          'h': {
            aug(1): SquareState.complete,
            aug(2): SquareState.complete,
            aug(3): SquareState.partial,
          },
          'monday': {aug(3): SquareState.complete},
        },
        window: reportWindow(ReportScope.week, DateTime(2026, 8, 6)),
        now: DateTime(2026, 8, 6, kDayCutoffHour),
      );
      expect([for (final s in r.stats) pct(s.rate)], ['50%', '100%']);
      expect((r.summary.expectedTotal, r.summary.creditedTotal), (6, 3.5));
      expect(r.summary.rate, closeTo(3.5 / 6, 1e-9));
      expect(
        pct(r.summary.rate),
        '58%',
        reason: 'the mean of the two cards is 75%, and greens alone 50%',
      );
      expect(r.summary.totalDone, 3);
    });
  });

  group('a جزئي on a day still open', () {
    // أذكار الصباح in September, greens on the 3rd and the 7th as in
    // report_open_day_rate_test.dart, with Thursday the 10th marked جزئي.
    // 05:19 on Friday the 11th is the clock of Aziz's screenshot.
    final adhkar = habit('adhkar');
    final history = {
      'adhkar': {
        sep(3): SquareState.complete,
        sep(7): SquareState.complete,
        sep(10): SquareState.partial,
      },
    };
    final september = reportWindow(ReportScope.month, DateTime(2026, 9, 11));

    ({PeriodSummary summary, List<HabitPeriodStat> stats}) at(DateTime now) =>
        report(
          habits: [adhkar],
          history: history,
          window: september,
          now: now,
        );

    test('waits at 05:19, and counts half once the day closes at 10:00', () {
      final early = at(DateTime(2026, 9, 11, 5, 19));
      expect(
        (early.stats.single.expected, early.stats.single.creditedUnits),
        (9, 2.0),
      );
      expect(
        (
          early.summary.expectedTotal,
          early.summary.creditedTotal,
          pct(early.summary.rate),
        ),
        (9, 2.0, '22%'),
        reason: 'the 10th is still open: half of it is not yet a number',
      );

      final closed = at(DateTime(2026, 9, 11, kDayCutoffHour));
      expect(
        (closed.stats.single.expected, closed.stats.single.creditedUnits),
        (10, 2.5),
      );
      expect(
        (
          closed.summary.expectedTotal,
          closed.summary.creditedTotal,
          pct(closed.summary.rate),
        ),
        (10, 2.5, '25%'),
        reason: 'green squares alone read 20%',
      );
    });

    test('equals the card at every clock through the night and the next day',
        () {
      for (final now in [
        DateTime(2026, 9, 11),
        DateTime(2026, 9, 11, 5, 19),
        DateTime(2026, 9, 11, kDayCutoffHour - 1, 59),
        DateTime(2026, 9, 11, kDayCutoffHour),
        DateTime(2026, 9, 11, 23, 59),
        DateTime(2026, 9, 12, kDayCutoffHour - 1, 59),
        DateTime(2026, 9, 12, kDayCutoffHour),
      ]) {
        final r = at(now);
        final card = r.stats.single;
        expect(
          (r.summary.expectedTotal, r.summary.creditedTotal, r.summary.rate),
          (card.expected, card.creditedUnits, card.rate),
          reason: '$now',
        );
      }
    });
  });

  group('the free-tier floor', () {
    // One daily habit from December 2025, read on the year tab at 10:00 on
    // Saturday 12 September. July and August are green and the 1st to the
    // 11th of September جزئي; March, all جزئي, sits behind a free account's
    // wall, which starts in July (freeHistoryFloor).
    final h = habit('h', createdAt: DateTime(2025, 12));
    final history = {
      'h': {
        for (var d = 1; d <= 31; d++)
          DateTime(2026, 3, d).toDateKey(): SquareState.partial,
        for (var d = 1; d <= 31; d++) aug(d): SquareState.complete,
        for (var d = 1; d <= 31; d++)
          DateTime(2026, 7, d).toDateKey(): SquareState.complete,
        for (var d = 1; d <= 11; d++) sep(d): SquareState.partial,
      },
    };
    final year = reportWindow(ReportScope.year, DateTime(2026, 9, 12));
    final now = DateTime(2026, 9, 12, kDayCutoffHour);

    test('credit comes only from the days the strips show', () {
      final floor = historyFloorFor(
        windowStart: year.start,
        today: now.effectiveDay,
        isPremium: false,
      );
      expect(floor, DateTime(2026, 7));
      final free = report(
        habits: [h],
        history: history,
        window: year,
        now: now,
        floor: floor,
      );
      expect(
        (
          free.summary.totalDone,
          free.summary.expectedTotal,
          free.summary.creditedTotal,
        ),
        (62, 73, 67.5),
      );
      expect(
        pct(free.summary.rate),
        '92%',
        reason: "green squares alone read 85%, and March's halves let in "
            'would read 100%',
      );

      final premium = report(
        habits: [h],
        history: history,
        window: year,
        now: now,
      );
      expect(
        (premium.summary.expectedTotal, premium.summary.creditedTotal),
        (254, 83.0),
      );
      expect(pct(premium.summary.rate), '33%');
    });
  });

  group('a quota habit over its target, exactly as before', () {
    // A closed week, 1 to 7 August, read at 10:00 on the 8th. three: three
    // times a week, any three. daily: owed every day, and left blank.
    final habits = [
      habit('three', type: HabitFrequencyType.weekly, target: 3),
      habit('daily'),
    ];
    final week = reportWindow(ReportScope.week, DateTime(2026, 8, 7));
    final now = DateTime(2026, 8, 8, kDayCutoffHour);
    final fourGreens = {
      for (var d = 1; d <= 4; d++) aug(d): SquareState.complete,
    };

    test('no habit is capped before the sum', () {
      final greens = report(
        habits: habits,
        history: {'three': fourGreens},
        window: week,
        now: now,
      );
      final three = greens.stats.first;
      expect(
        (three.expected, three.creditedUnits, pct(three.rate)),
        (3, 4.0, '100%'),
      );
      expect(greens.summary.expectedTotal, 10);
      expect(
        greens.summary.rate,
        closeTo(0.4, 1e-9),
        reason: '4 of the 10 owed, as the header read before. Capped at its '
            'card, three would add only 3',
      );

      final withHalf = report(
        habits: habits,
        history: {
          'three': {...fourGreens, aug(5): SquareState.partial},
        },
        window: week,
        now: now,
      );
      final threeWithHalf = withHalf.stats.first;
      expect(
        (
          threeWithHalf.expected,
          threeWithHalf.creditedUnits,
          pct(threeWithHalf.rate),
        ),
        (3, 4.5, '100%'),
      );
      expect(
        withHalf.summary.rate,
        closeTo(0.45, 1e-9),
        reason: 'the half adds on top, as its fourth green already did',
      );
      expect(withHalf.summary.totalDone, 4);
    });
  });

  group('credit past what was owed stops at 100%', () {
    test('a half earned on a day nothing was owed cannot print above it', () {
      // Monday and Thursday, marked جزئي on Saturday the 5th, a day it never
      // asked for, beside a daily habit green on the 5th and the 6th. At
      // 05:19 on Tuesday the 8th the week owes those two days and nothing
      // else: Monday the 7th is still open and Thursday is ahead. The half
      // sits on top of a total that does not include the day it was earned
      // on, which is a second and ordinary way for credit to overflow. Green
      // squares could only do it when a quota habit beat its target.
      final r = report(
        habits: [
          habit(
            'monThu',
            type: HabitFrequencyType.weekly,
            target: 2,
            weekdays: const [DateTime.monday, DateTime.thursday],
          ),
          habit('daily'),
        ],
        history: {
          'monThu': {sep(5): SquareState.partial},
          'daily': {
            sep(5): SquareState.complete,
            sep(6): SquareState.complete,
          },
        },
        window: reportWindow(ReportScope.week, DateTime(2026, 9, 8)),
        now: DateTime(2026, 9, 8, 5, 19),
      );
      expect((r.summary.expectedTotal, r.summary.creditedTotal), (2, 2.5));
      expect(
        r.summary.creditedTotal / r.summary.expectedTotal,
        closeTo(1.25, 1e-9),
        reason: "the rate's cap is the only thing holding this down",
      );
      expect((r.summary.rate, pct(r.summary.rate)), (1.0, '100%'));
    });
  });

  group('a quota week still reachable owes nothing and holds credit', () {
    // A 3x a week habit added Saturday 5 September and marked جزئي that day,
    // beside a daily habit added Friday the 4th, green the 4th and blank the
    // 5th, read at 11:00 on Sunday the 6th.
    //
    // While its week can still fit all three sessions the quota habit owes 0
    // (owed = min(T, max(G, T - S)), see [expectedCompletions]), so its half
    // is credit the header has no denominator for, and its own card prints
    // the placeholder. Recorded as the reading that ships, not as a settled
    // rule: whether a habit's credit should be capped at what that habit
    // owed before the header sums it is Aziz's to answer. Capped, this reads
    // 50%, which is the one card on the screen that prints a number.
    final habits = [
      habit(
        'three',
        type: HabitFrequencyType.weekly,
        target: 3,
        createdAt: DateTime(2026, 9, 5),
      ),
      habit('daily', createdAt: DateTime(2026, 9, 4)),
    ];
    final history = {
      'three': {sep(5): SquareState.partial},
      'daily': {sep(4): SquareState.complete},
    };

    test('the header reads above the only card that prints a number', () {
      final r = report(
        habits: habits,
        history: history,
        window: reportWindow(ReportScope.month, DateTime(2026, 9, 6)),
        now: DateTime(2026, 9, 6, 11),
      );
      final three = r.stats.first;
      expect(
        (three.expected, three.creditedUnits, three.hasRate),
        (0, 0.5, false),
      );
      final daily = r.stats.last;
      expect(
        (daily.expected, daily.creditedUnits, pct(daily.rate)),
        (2, 1.0, '50%'),
      );
      expect((r.summary.expectedTotal, r.summary.creditedTotal), (2, 1.5));
      expect(
        pct(r.summary.rate),
        '75%',
        reason: 'green squares alone read 50%, the daily card exactly',
      );
    });
  });

  group('the empty-state gate still asks for a green square', () {
    test('a window of halves alone has a rate and records nothing', () {
      // One daily habit, جزئي on Saturday the 5th and Sunday the 6th, read
      // at 10:00 on Monday the 7th, so both halves have closed. hasAnything
      // is what the hub asks before it draws a header at all (see
      // period_report_section.dart), and it still counts green squares, so
      // this period holds a real 50% the empty state hides. Pinned where it
      // stands, both sides of it, while Aziz has not ruled on it.
      final r = report(
        habits: [habit('h')],
        history: {
          'h': {sep(5): SquareState.partial, sep(6): SquareState.partial},
        },
        window: reportWindow(ReportScope.week, DateTime(2026, 9, 7)),
        now: DateTime(2026, 9, 7, kDayCutoffHour),
      );
      expect(
        (
          r.summary.totalDone,
          r.summary.expectedTotal,
          r.summary.creditedTotal,
        ),
        (0, 2, 1.0),
      );
      expect(
        (r.summary.hasAnything, r.summary.hasRate, pct(r.summary.rate)),
        (false, true, '50%'),
      );
    });
  });

  group('an archived habit whose marks are all halves', () {
    test('its halves reach a header that shows no card for them', () {
      // A live daily habit green on Tuesday the 1st and Wednesday the 2nd,
      // beside a daily habit archived at midnight on Thursday the 3rd whose
      // only marks are جزئي on those same two days, read at 10:00 on the
      // 3rd, so both halves have closed. [splitArchived] keeps an archived
      // row only when it has a green square, so this habit prints on no card
      // anywhere, not even under the fold, while both sides of it reach the
      // header: 75% beside a single card reading 100%. Its owed days already
      // reached the header before this change, which read 50% here, so what
      // moved is the direction, not whether a card is missing. Pinned where
      // it stands while Aziz has not ruled on it: folding the row back in
      // means asking it for credit rather than green squares, and dropping it
      // has to take both sides of the rate, not only the numerator.
      final r = report(
        habits: [
          habit('live'),
          habit('gone', archivedAt: DateTime(2026, 9, 3)),
        ],
        history: {
          'live': {sep(1): SquareState.complete, sep(2): SquareState.complete},
          'gone': {sep(1): SquareState.partial, sep(2): SquareState.partial},
        },
        window: reportWindow(ReportScope.month, DateTime(2026, 9, 3)),
        now: DateTime(2026, 9, 3, kDayCutoffHour),
      );
      expect(
        (
          r.summary.totalDone,
          r.summary.expectedTotal,
          r.summary.creditedTotal,
        ),
        (2, 4, 3.0),
      );
      expect(
        pct(r.summary.rate),
        '75%',
        reason: 'green squares alone read 50%',
      );
      final split = splitArchived(r.stats);
      expect([for (final s in split.active) s.habit.id], ['live']);
      expect(split.archived, isEmpty);
      expect(
        pct(split.active.single.rate),
        '100%',
        reason: 'the only card on the screen, 25 points under the header',
      );
    });
  });

  group('nothing owed yet', () {
    test('credit with nothing owed has no rate to print', () {
      // Monday and Thursday, done on Saturday the 5th, a day it never asked
      // for. At 05:19 on Tuesday the 8th Monday is still open and Thursday
      // still ahead, so the week owes nothing yet while holding a day of
      // credit. Divided through, that credit would print 100%.
      final r = report(
        habits: [
          habit(
            'monThu',
            type: HabitFrequencyType.weekly,
            target: 2,
            weekdays: const [DateTime.monday, DateTime.thursday],
          ),
        ],
        history: {
          'monThu': {sep(5): SquareState.complete},
        },
        window: reportWindow(ReportScope.week, DateTime(2026, 9, 8)),
        now: DateTime(2026, 9, 8, 5, 19),
      );
      expect(
        (
          r.summary.totalDone,
          r.summary.expectedTotal,
          r.summary.creditedTotal,
        ),
        (1, 0, 1.0),
      );
      expect((r.summary.hasRate, r.summary.rate), (false, 0.0));
    });
  });

  group('the real screen', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('report_header_half_credit_');
      Hive.init(tmp.path);
    });

    tearDown(() async {
      await Hive.deleteFromDisk();
      await tmp.delete(recursive: true);
    });

    /// Fixed pumps, not pumpAndSettle: the reports hub runs flutter_animate
    /// effects that never reach a still frame.
    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }
    }

    /// Mounts the report at [clock] and opens [scope]. Nothing is live for
    /// the clock's own day, and no fixture records anything on it.
    Future<void> mountAt(
      WidgetTester tester,
      DateTime clock, {
      required List<IslamicHabitTemplate> habits,
      required Map<String, Map<String, SquareState>> history,
      required ReportScope scope,
      bool premium = true,
    }) async {
      // Tall enough that every card is laid out.
      tester.view.physicalSize = const Size(400 * 3, 3200 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dayClockSourceProvider.overrideWithValue(() => clock),
            authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
            premiumProvider.overrideWith((ref) => _Premium(premium)),
            dashboardProvider.overrideWith((ref) => _LoadedDash()),
            allHabitsEverProvider.overrideWithValue(habits),
            habitYearHistoryProvider.overrideWith((ref) async => history),
          ],
          child: MaterialApp(
            locale: const Locale('ar'),
            supportedLocales: const [Locale('en'), Locale('ar')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: GameTheme.dark,
            home: const Scaffold(body: PeriodReportSection()),
          ),
        ),
      );
      await settle(tester);
      if (scope != ReportScope.week) {
        tester
            .widget<SegmentedTabs>(find.byType(SegmentedTabs))
            .onChanged(scope.index);
        await settle(tester);
      }
    }

    ReportHeaderCard header(WidgetTester tester) =>
        tester.widget<ReportHeaderCard>(find.byType(ReportHeaderCard));

    /// The header's completion cell, as printed.
    String headerRate(WidgetTester tester) => tester
        .widget<Text>(
          find.descendant(
            of: find.byType(ReportHeaderCard),
            matching: find.textContaining('%'),
          ),
        )
        .data!;

    /// Every month card's printed percentage, by habit id.
    Map<String, String> monthCards(WidgetTester tester) => {
          for (final card in tester
              .widgetList<HabitMonthCard>(find.byType(HabitMonthCard)))
            card.stat.habit.id: card.stat.hasRate
                ? '${(card.stat.rate * 100).round()}%'
                : '–',
        };

    group('one habit, from Saturday 29 August', () {
      // Last week: the 29th and 30th green, Tuesday the 1st جزئي. This week:
      // the 5th to the 7th green, Tuesday the 8th جزئي, Thursday the 10th
      // جزئي. Read on Friday the 11th, the 10th is still open until 10:00.
      final habits = [habit('h', createdAt: DateTime(2026, 8, 29))];
      final history = <String, Map<String, SquareState>>{
        'h': {
          aug(29): SquareState.complete,
          aug(30): SquareState.complete,
          sep(1): SquareState.partial,
          sep(5): SquareState.complete,
          sep(6): SquareState.complete,
          sep(7): SquareState.complete,
          sep(8): SquareState.partial,
          sep(10): SquareState.partial,
        },
      };
      final at0519 = DateTime(2026, 9, 11, 5, 19);
      final at1000 = DateTime(2026, 9, 11, kDayCutoffHour);

      /// The counts of days, which the half never reaches.
      void expectCounts(WidgetTester tester) {
        final summary = header(tester).summary;
        expect(
          (
            summary.totalDone,
            summary.activeDays,
            summary.bestDayCount,
            summary.longestRun,
          ),
          (3, 3, 1, 3),
        );
      }

      testWidgets('أسبوعي at 05:19: 70%, the open 10th held back',
          (tester) async {
        await mountAt(
          tester,
          at0519,
          habits: habits,
          history: history,
          scope: ReportScope.week,
        );
        final summary = header(tester).summary;
        expect((summary.expectedTotal, summary.creditedTotal), (5, 3.5));
        expect(
          headerRate(tester),
          '70%',
          reason: 'three greens and the closed 8th of the 5th to the 9th; '
              'green squares alone read 60%',
        );
        final stat = tester
            .widget<WeeklyMatrixCard>(find.byType(WeeklyMatrixCard))
            .stats
            .single;
        expect(summary.rate, stat.rate);
        expectCounts(tester);
        expect(
          header(tester).delta,
          1,
          reason: 'still green squares: the 7th against a blank 31st. '
              "Counted as done, the open 10th's جزئي would add one more "
              'against a blank 3rd',
        );
      });

      testWidgets('أسبوعي at 10:00: the 10th has closed, and its half counts',
          (tester) async {
        await mountAt(
          tester,
          at1000,
          habits: habits,
          history: history,
          scope: ReportScope.week,
        );
        final summary = header(tester).summary;
        expect((summary.expectedTotal, summary.creditedTotal), (6, 4.0));
        expect(
          headerRate(tester),
          '67%',
          reason: 'green squares alone read 50%',
        );
        expectCounts(tester);
        expect(header(tester).delta, 1);
      });

      testWidgets('شهري at 05:19: the header and the card print one number',
          (tester) async {
        await mountAt(
          tester,
          at0519,
          habits: habits,
          history: history,
          scope: ReportScope.month,
        );
        expect(monthCards(tester), {'h': '44%'});
        expect(
          headerRate(tester),
          '44%',
          reason: 'the 1st and the 8th are half each, of the 1st to the '
              '9th; green squares alone read 33%',
        );
        expect(find.text('44%'), findsNWidgets(2));
        expect(
          header(tester).summary.rate,
          tester.widget<HabitMonthCard>(find.byType(HabitMonthCard)).stat.rate,
        );
        expectCounts(tester);
      });

      testWidgets('شهري at 10:00: still one number, now with the 10th',
          (tester) async {
        await mountAt(
          tester,
          at1000,
          habits: habits,
          history: history,
          scope: ReportScope.month,
        );
        expect(monthCards(tester), {'h': '45%'});
        expect(
          headerRate(tester),
          '45%',
          reason: 'green squares alone read 30%',
        );
        expectCounts(tester);
      });
    });

    group("Aziz's September cards, read at 10:00 on the 12th", () {
      // The four habits report_open_day_wiring_test.dart infers from his
      // screenshot: training's 8th is جزئي.
      final august = DateTime(2026, 8);
      final habits = [
        habit('adhkar', createdAt: august),
        habit(
          'sadaqa',
          type: HabitFrequencyType.weekly,
          target: 2,
          weekdays: const [DateTime.monday, DateTime.thursday],
          createdAt: august,
        ),
        habit('quran', createdAt: DateTime(2026, 9, 9)),
        habit(
          'training',
          type: HabitFrequencyType.weekly,
          target: 4,
          createdAt: august,
        ),
      ];
      final history = <String, Map<String, SquareState>>{
        'adhkar': {sep(3): SquareState.complete, sep(7): SquareState.complete},
        'sadaqa': {
          sep(7): SquareState.complete,
          sep(10): SquareState.complete,
        },
        'quran': {sep(9): SquareState.complete, sep(10): SquareState.complete},
        'training': {
          sep(2): SquareState.complete,
          sep(3): SquareState.complete,
          sep(8): SquareState.partial,
        },
      };

      testWidgets('شهري: the cards summed, not their mean', (tester) async {
        await mountAt(
          tester,
          DateTime(2026, 9, 12, kDayCutoffHour),
          habits: habits,
          history: history,
          scope: ReportScope.month,
        );
        expect(monthCards(tester), {
          'adhkar': '18%',
          'sadaqa': '67%',
          'quran': '67%',
          'training': '31%',
        });
        final summary = header(tester).summary;
        expect(
          (summary.totalDone, summary.expectedTotal, summary.creditedTotal),
          (8, 25, 8.5),
        );
        expect(
          headerRate(tester),
          '34%',
          reason: 'green squares alone read 32%, and the mean of the four '
              'cards 46%',
        );
      });
    });

    group('the free-tier floor, on سنوي at 10:00 on 12 September', () {
      // The habit and history of the pure floor test above: March جزئي
      // behind the wall, July and August green, September's first eleven
      // days جزئي.
      final habits = [habit('h', createdAt: DateTime(2025, 12))];
      final history = <String, Map<String, SquareState>>{
        'h': {
          for (var d = 1; d <= 31; d++)
            DateTime(2026, 3, d).toDateKey(): SquareState.partial,
          for (var d = 1; d <= 31; d++)
            DateTime(2026, 7, d).toDateKey(): SquareState.complete,
          for (var d = 1; d <= 31; d++) aug(d): SquareState.complete,
          for (var d = 1; d <= 11; d++) sep(d): SquareState.partial,
        },
      };
      final clock = DateTime(2026, 9, 12, kDayCutoffHour);

      testWidgets('free: the walled halves stay out of the header',
          (tester) async {
        await mountAt(
          tester,
          clock,
          habits: habits,
          history: history,
          scope: ReportScope.year,
          premium: false,
        );
        final summary = header(tester).summary;
        expect(
          (summary.totalDone, summary.expectedTotal, summary.creditedTotal),
          (62, 73, 67.5),
        );
        expect(
          headerRate(tester),
          '92%',
          reason: "green squares alone read 85%, and March's halves let in "
              'would read 100%',
        );
        expect(
          find.text('${summary.totalDone} يوم'),
          findsOneWidget,
          reason: 'the year row floors its own days count separately from '
              'the header, so the one pair on this tab must not split',
        );
      });

      testWidgets('premium: the same year reads in full', (tester) async {
        // The control, so the free test cannot pass by dropping March from
        // everyone.
        await mountAt(
          tester,
          clock,
          habits: habits,
          history: history,
          scope: ReportScope.year,
        );
        final summary = header(tester).summary;
        expect((summary.expectedTotal, summary.creditedTotal), (254, 83.0));
        expect(headerRate(tester), '33%');
      });
    });

    testWidgets('شهري: a reachable quota week reads above its only card',
        (tester) async {
      // The quota case above, on the screen itself: the 3x a week habit added
      // Saturday the 5th and marked جزئي that day, beside the daily habit
      // added Friday the 4th, green the 4th and blank the 5th, read at 11:00
      // on Sunday the 6th. Its week can still hold every session, so its card
      // prints the placeholder and the header's 75% stands above the 50% of
      // the only card that prints a number. Mounted rather than argued,
      // because this is the reading Aziz has to rule on.
      await mountAt(
        tester,
        DateTime(2026, 9, 6, 11),
        habits: [
          habit(
            'three',
            type: HabitFrequencyType.weekly,
            target: 3,
            createdAt: DateTime(2026, 9, 5),
          ),
          habit('daily', createdAt: DateTime(2026, 9, 4)),
        ],
        history: {
          'three': {sep(5): SquareState.partial},
          'daily': {sep(4): SquareState.complete},
        },
        scope: ReportScope.month,
      );
      expect(monthCards(tester), {'three': '–', 'daily': '50%'});
      final summary = header(tester).summary;
      expect(
        (summary.totalDone, summary.expectedTotal, summary.creditedTotal),
        (1, 2, 1.5),
      );
      expect(headerRate(tester), '75%', reason: 'green squares read 50%');
    });

    testWidgets('أسبوعي with credit and nothing owed yet prints the placeholder',
        (tester) async {
      // The pure case above, on screen: a Monday and Thursday habit done on
      // Saturday the 5th, read at 05:19 on Tuesday the 8th.
      await mountAt(
        tester,
        DateTime(2026, 9, 8, 5, 19),
        habits: [
          habit(
            'monThu',
            type: HabitFrequencyType.weekly,
            target: 2,
            weekdays: const [DateTime.monday, DateTime.thursday],
            createdAt: DateTime(2026, 8),
          ),
        ],
        history: {
          'monThu': {sep(5): SquareState.complete},
        },
        scope: ReportScope.week,
      );
      final summary = header(tester).summary;
      expect(
        (summary.expectedTotal, summary.creditedTotal, summary.hasRate),
        (0, 1.0, false),
      );
      expect(
        find.descendant(
          of: find.byType(ReportHeaderCard),
          matching: find.text('–'),
        ),
        findsOneWidget,
        reason: 'the best day is the 5th, so the only dash is the rate',
      );
      expect(
        find.descendant(
          of: find.byType(ReportHeaderCard),
          matching: find.textContaining('%'),
        ),
        findsNothing,
      );
    });
  });
}
