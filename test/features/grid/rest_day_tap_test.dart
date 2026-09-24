// A tap on a «–» square (a day the habit asks nothing of) asks first.
//
// Aziz, 2026-09-24, on the «سويتها يوم ثاني» sheet this replaced: "what if the
// user wants to add a Wednesday or a Thursday? why does it only show old
// days? the user can already mark a past day by clicking it. Just make any –
// days clickable, but with a pop up that it's rest and how it will be
// handled."
//
// The first group pins what the pop-up promises (restDayTapFor), on his own
// shampoo week. The second taps a real square on the real Grid, in Arabic:
// the pop-up opens, «إلغاء» leaves the day alone, «سويتها» records it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/services/local_store_service.dart';
import 'package:grow_daily_v2/features/grid/models/rest_day_tap.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/grid/notifiers/weekly_grid_notifier.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';

import '../../helpers/landing_harness.dart';

void main() {
  group('what the pop-up promises', () {
    // «شامبو ضد القشرة» as stored on his phone: Monday, Thursday and
    // Saturday, created Monday 21 September 2026. The week runs Saturday the
    // 19th to Friday the 25th; index 0 is that Saturday.
    final shampoo = IslamicHabitTemplate(
      id: 'shampoo',
      name: 'Anti-dandruff shampoo',
      nameAr: 'شامبو ضد القشرة',
      description: '',
      category: HabitCategory.custom,
      frequencyType: HabitFrequencyType.weekly,
      frequencyTarget: 3,
      scheduledWeekdays: const [
        DateTime.monday,
        DateTime.thursday,
        DateTime.saturday,
      ],
      hasTimer: false,
      xpReward: 10,
      goldReward: 5,
      createdAt: DateTime(2026, 9, 21),
    );
    final week = [for (var i = 0; i < 7; i++) DateTime(2026, 9, 19 + i)];
    const tue = 3, wed = 4, thu = 5;
    // Thursday 24 September, 10:30: Wednesday closed at 10:00.
    final thursdayMorning = DateTime(2026, 9, 24, 10, 30);

    RestDayTap tapOn(
      int index, {
      required Map<int, SquareState> marks,
      DateTime? now,
    }) =>
        restDayTapFor(
          habit: shampoo,
          days: week,
          index: index,
          isGreenAt: (i) => (marks[i] ?? SquareState.none).isGreen,
          isUnmarkedAt: (i) => (marks[i] ?? SquareState.none) == SquareState.none,
          now: now ?? thursdayMorning,
        );

    test('Wednesday, before it is recorded: covers Thursday, no points', () {
      final tap = tapOn(wed, marks: {2: SquareState.complete});
      expect(tap.reason, RestDayReason.offPlan);
      expect(tap.covers, week[thu]);
      expect(tap.pays, isFalse, reason: 'Wednesday closed at 10:00');
    });

    test('the same tap at 08:00 still pays: Wednesday is open until 10:00',
        () {
      final tap = tapOn(
        wed,
        marks: {2: SquareState.complete},
        now: DateTime(2026, 9, 24, 8),
      );
      expect((tap.covers, tap.pays), (week[thu], true));
    });

    test('Thursday, once Wednesday stands in for it: an extra, with points',
        () {
      final tap = tapOn(
        thu,
        marks: {2: SquareState.complete, wed: SquareState.complete},
      );
      expect(tap.reason, RestDayReason.coveredBySession);
      expect(tap.covers, isNull,
          reason: 'no other day of his week is left to stand in for');
      expect(tap.pays, isTrue, reason: 'today');
    });

    test('Tuesday, with the week already kept: an extra', () {
      final tap = tapOn(
        tue,
        marks: {2: SquareState.complete, wed: SquareState.complete},
      );
      expect((tap.reason, tap.covers), (RestDayReason.offPlan, null));
    });

    test('a Monday marked فشل is never the day it covers', () {
      final tap = tapOn(wed, marks: {2: SquareState.failed});
      expect(tap.covers, week[thu],
          reason: 'his own verdict on Monday stands; Thursday is the one');
    });

    test('a blank Monday is made up before Thursday', () {
      final tap = tapOn(wed, marks: const {});
      expect(tap.covers, week[2]);
    });

    test('a weekly count past its target says so', () {
      final threeTimes = IslamicHabitTemplate(
        id: 'gym',
        name: 'Gym',
        nameAr: 'تمرين',
        description: '',
        category: HabitCategory.custom,
        frequencyType: HabitFrequencyType.weekly,
        frequencyTarget: 3,
        hasTimer: false,
        xpReward: 10,
        goldReward: 5,
        createdAt: DateTime(2026, 9, 1),
      );
      RestDayTap quota(Set<int> done) => restDayTapFor(
            habit: threeTimes,
            days: week,
            index: 1,
            isGreenAt: done.contains,
            isUnmarkedAt: (i) => !done.contains(i),
            now: thursdayMorning,
          );
      final met = quota({0, 2, 3});
      expect((met.reason, met.weekAfter, met.weekTarget),
          (RestDayReason.quotaMet, 4, 3));
      final short = quota({2});
      expect((short.reason, short.weekAfter, short.weekTarget),
          (RestDayReason.notNeeded, 2, 3));
      expect(short.covers, isNull);
    });
  });

  group('the real Grid, in Arabic', () {
    const ar = S(Locale('ar'));
    const id = 'sunnah_fasting';
    const name = 'صيام الاثنين والخميس';

    String weekday(DateTime d) => DateFormat('EEEE', 'ar').format(d);
    String month(DateTime d) => DateFormat('MMMM', 'ar').format(d);
    Finder square(DateTime d) => find.bySemanticsLabel(RegExp(
          '^${RegExp.escape('$name، ${weekday(d)} ${d.day} ${month(d)}')}',
        ));

    late LandingHarness h;

    setUp(() async {
      h = LandingHarness();
      await h.prepare(activeCatalogIds: const [id]);
      // Process-wide boxes, see note_save_feedback_test.
      (await LocalStoreService.dailyBox()).clear();
    });
    tearDown(() => h.dispose());

    // One test, not three: each tap below writes the day to the real Hive
    // box, and a write still in flight when the next test's setUp opens the
    // box hangs the whole file (grid_dates_arabic_test only ever cancels for
    // the same reason).
    testWidgets('a «–» day asks first and only «سويتها» records it; a day '
        'of its own plan records on one tap', (tester) async {
      await tester.pumpWidget(h.app(locale: const Locale('ar')));
      await h.settle(tester);
      // Last week, so every day on the board is closed whatever day the suite
      // runs on.
      final grid = h.container.read(weeklyGridProvider.notifier);
      grid.previousWeek();
      await h.settle(tester);
      final days = h.container.read(weeklyGridProvider).days;
      final sunday = days[1];
      final monday = days[2];
      final thursday = days[5];
      SquareState on(DateTime d) =>
          h.container.read(weeklyGridProvider).squareFor(id, d);
      Future<void> tapSquare(DateTime d) async {
        await tester.ensureVisible(square(d));
        await h.settle(tester);
        await tester.tap(square(d));
        await h.settle(tester);
      }

      // Monday is one of its own days: no pop-up, one tap records it.
      await tapSquare(monday);
      expect(find.text(ar.restDayTitle), findsNothing);
      expect(on(monday), SquareState.complete);

      // Sunday is off the plan. With Monday done, the day a Sunday session
      // would stand in for is Thursday, the week's one blank day of its own.
      await tapSquare(sunday);
      expect(find.text(ar.restDayTitle), findsOneWidget,
          reason: 'the pop-up did not open');
      expect(find.text(ar.restDayOffPlan(weekday(sunday), name)),
          findsOneWidget);
      expect(find.text(ar.restDayCovers(weekday(thursday))), findsOneWidget);
      expect(find.text(ar.restDayNoPoints), findsOneWidget,
          reason: 'a closed day records without points');

      await tester.tap(find.text(ar.habitActionsCancel));
      await h.settle(tester);
      expect(on(sunday), SquareState.none,
          reason: '«إلغاء» must leave the day exactly as it was');

      await tapSquare(sunday);
      await tester.tap(find.text(ar.restDayConfirm));
      await h.settle(tester);
      expect(on(sunday), SquareState.complete);

      // Thursday is now stood in for by Sunday: a «–» of its own plan, which
      // asks too, and says a session there would be an extra.
      await tapSquare(thursday);
      expect(find.text(ar.restDayCoveredBySession(weekday(thursday))),
          findsOneWidget);
      expect(find.text(ar.restDayExtra), findsOneWidget);
      await tester.tap(find.text(ar.habitActionsCancel));
      await h.settle(tester);
      expect(on(thursday), SquareState.none);
      await tester.pump(const Duration(milliseconds: 1));
    });
  });
}
