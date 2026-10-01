// The board draws exactly what it drew before its week's date facts were
// worked out once per build instead of once per square.
//
// _GridTableState used to ask the clock, build local midnights and format
// dates inside every square: about 330 clock reads and 3,000 native
// time-zone lookups for a board of 12 habits. The facts are now computed once
// per build (_WeekFacts) and once per row, and nothing a person sees may
// change. This pumps the REAL GridScreen over board_parity_fixture.dart and
// reads every _SquareCell's own fields, and every day header, then compares
// them with what the old per-square sequence of public helpers says they must
// be: isScheduledFor, isAliveOn, isCoveredDay and quotaDemandForRow without
// the precomputed arguments, westernDate, squareFor, noteFor and
// squareVoiceKey. On top of that, the fixed past weeks are pinned to a digest
// frozen from the board as it was before the change.
//
// Run it twice: as it is, and with TZ=America/New_York, where the week of
// 2025-11-01 (and of 2026-10-31) repeats a date and the week of 2026-03-07
// loses an hour, so a column's instant is not its midnight.
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/providers/day_clock_provider.dart';
import 'package:grow_daily_v2/core/services/health_steps_service.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/core/utils/western_digits.dart';
import 'package:grow_daily_v2/features/dashboard/notifiers/dashboard_notifier.dart';
import 'package:grow_daily_v2/features/grid/models/covered_day.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/grid/notifiers/square_voice_notes.dart';
import 'package:grow_daily_v2/features/grid/notifiers/weekly_grid_notifier.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_day_demand.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';
import 'package:grow_daily_v2/features/habits/step_auto_complete.dart';

import '../../helpers/landing_harness.dart';
import 'board_parity_fixture.dart';

/// Digests of the fixed past weeks, frozen from the board before the change
/// and never regenerated. Keyed by the zone's offsets across the pinned
/// weeks, the week and the language: a zone not listed here still runs every
/// comparison above, only without a frozen digest.
const Map<String, String> _frozen = {
  // Asia/Riyadh and Asia/Bahrain: no daylight saving.
  '180/180/180/180 2026-03-07 en':
      'ff85e4eb996190ea16614a79493b4391e58e300dc6151a852eeef6bdec498951',
  '180/180/180/180 2025-11-01 en':
      '1ecca40a7d4a8e6e7fb1a7732553db69cac37d2352d87e6903a9abb16f5b3a42',
  '180/180/180/180 2026-03-07 ar':
      '5aa1f6d7a21faadb9faf948cd035cd925691bc47639e9ccd0ce9b73ab2e3de80',
  '180/180/180/180 2025-11-01 ar':
      '6f36e680f3dc6e51734f2397de86f8e95928b52fe4a5bd21aee516fe123d9c06',
  // America/New_York: 2025-11-02 repeats an hour, 2026-03-08 loses one.
  '-240/-300/-300/-240 2026-03-07 en':
      '1c667440338b9f2a0d4928256bb95a209fb44477f23d8a240cda459f22b522a9',
  '-240/-300/-300/-240 2025-11-01 en':
      '8661347130e16573bfb8186322286590f5e1452708191516877ebf5037e0f99e',
  '-240/-300/-300/-240 2026-03-07 ar':
      '403ceabd1c4931f80b7fdc92ae144b2a9703c8b4bd4dc8af5658b198e0ed688b',
  '-240/-300/-300/-240 2025-11-01 ar':
      'a4a2b31dec5e8589b4ebf0495fba438b7ea86ee4a4c008f44b58d12e2ba066d4',
};

/// The zone's UTC offsets on the days the pinned weeks cross, in minutes.
String _zoneFingerprint() => [
      DateTime(2025, 11, 1),
      DateTime(2025, 11, 3),
      DateTime(2026, 3, 7),
      DateTime(2026, 3, 9),
    ].map((d) => d.timeZoneOffset.inMinutes).join('/');

bool _isSquareCell(Widget w) => w.runtimeType.toString() == '_SquareCell';
bool _isTable(Widget w) => w.runtimeType.toString() == '_GridTable';

/// One square as the board built it, read off the private widget's fields.
Map<String, Object?> _cellAsBuilt(Widget w) {
  final c = w as dynamic;
  return {
    'label': c.semanticLabel as String,
    'day': (c.day as DateTime).toIso8601String(),
    'isToday': c.isToday as bool,
    'isFuture': c.isFuture as bool,
    'isScheduled': c.isScheduled as bool,
    'isAlive': c.isAlive as bool,
    'isCovered': c.isCovered as bool,
    'square': (c.square as SquareState).name,
    'dayCount': '${c.dayCount}',
    'stepFraction': '${c.stepFraction}',
    'stepCount': '${c.stepCount}',
    'hasNote': c.hasNote as bool,
    'key': w.key != null,
    'onTap': c.onTap != null,
    'onLongPress': c.onLongPress != null,
  };
}

/// The same square worked out the way _habitRowBody worked it out before
/// the change, one public helper call at a time.
Map<String, Object?> _cellTheOldWay({
  required IslamicHabitTemplate habit,
  required DateTime day,
  required List<DateTime> days,
  required WeeklyGridState state,
  required List<DayDemand?>? demand,
  required DashboardState dash,
  required DateTime Function() clock,
  required Map<String, int> stepsByDay,
  required bool stepsStalled,
  required Map<String, int> voice,
  required S s,
  required bool holdsCellKey,
}) {
  final isAr = s.isAr;
  final today = DateTime.now().effectiveDay;
  int? dayCount() {
    if (day.isToday) return dash.completions[habit.id] ?? 0;
    if (dash.graceDayKey != day.toDateKey() || !day.isOpenDayAt(clock())) {
      return null;
    }
    return dash.graceCompletions[habit.id] ?? 0;
  }

  SquareState effective(int done) {
    final stored = state.squareFor(habit.id, day);
    if (habit.effectiveDailyTarget <= 1 || done <= 0) return stored;
    if (stored == SquareState.failed ||
        stored == SquareState.bonus ||
        stored == SquareState.skipped) {
      return stored;
    }
    return done >= habit.effectiveDailyTarget
        ? SquareState.complete
        : SquareState.partial;
  }

  final liveCount = habit.effectiveDailyTarget > 1 &&
          (day.isToday ||
              day.isSameDayAs(
                DateTime(today.year, today.month, today.day - 1),
              ))
      ? dayCount()
      : null;
  final square = effective(liveCount ?? 0);
  final steps = day.isToday && stepsStalled ? null : stepsByDay[day.toDateKey()];
  final stepGoal = habit.stepGoal;
  final stepFraction = stepFillFraction(
    steps: steps,
    goal: stepGoal,
    scheduled: habit.isScheduledFor(day),
    square: square,
  );
  final stepCount = stepSquareCount(
    steps: steps,
    goal: stepGoal,
    scheduled: habit.isScheduledFor(day),
    square: square,
  );
  final hasVoice = (voice[squareVoiceKey(habit.id, day)] ?? 0) > 0;
  final hasNote =
      hasVoice || state.noteFor(habit.id, day).trim().isNotEmpty;
  final covered = isCoveredDay(
    habit: habit,
    day: day,
    today: today,
    square: square,
    demand: demand == null || !days.contains(day)
        ? null
        : demand[days.indexOf(day)],
  );
  final label = [
    habit.localName(isAr),
    westernDate(day, 'EEEE d MMMM', isAr ? 'ar' : 'en'),
    square.localLabel(isAr),
    if (liveCount != null)
      s.timesPerDayProgress(liveCount, habit.effectiveDailyTarget),
    if (stepGoal != null &&
        habit.isScheduledFor(day) &&
        (day.isToday || steps != null))
      day.isToday
          ? s.stepsProgressLine(steps, stepGoal)
          : s.stepsWalkedLine(steps!, stepGoal),
    if (day.isAfter(today))
      isAr ? 'يوم قادم' : 'future day'
    else if (!habit.isScheduledFor(day))
      isAr ? 'غير مجدول' : 'not scheduled',
    if (hasNote) s.gridNoteSemantics,
  ].join(isAr ? '، ' : ', ');
  return {
    'label': label,
    'day': day.toIso8601String(),
    'isToday': day.isRealToday,
    'isFuture': day.startOfDay.isAfter(today) && !day.isRealToday,
    'isScheduled': habit.isScheduledFor(day),
    'isAlive': habit.isAliveOn(day),
    'isCovered': covered,
    'square': square.name,
    'dayCount': liveCount == null
        ? 'null'
        : '(done: $liveCount, target: ${habit.effectiveDailyTarget})',
    'stepFraction': '$stepFraction',
    'stepCount': '$stepCount',
    'hasNote': hasNote,
    'key': holdsCellKey && day.isRealToday,
    'onTap': true,
    'onLongPress': true,
  };
}

/// One day header as the board built it: its three lines, their styles, the
/// today circle and whether its column carries the scroll-to-today key.
Map<String, Object?> _headerAsBuilt(List<Element> texts, int i) {
  String line(Element e) {
    final t = e.widget as Text;
    return '${t.data}|${t.style?.color}|${t.style?.fontWeight}|'
        '${t.style?.fontSize}';
  }

  final number = texts[3 * i + 2];
  Container? circle;
  SizedBox? column;
  number.visitAncestorElements((e) {
    final w = e.widget;
    if (circle == null && w is Container) circle = w;
    if (w is SizedBox && w.width != null) {
      column = w;
      return false;
    }
    return true;
  });
  final decoration = circle?.decoration;
  return {
    'primary': line(texts[3 * i]),
    'secondary': line(texts[3 * i + 1]),
    'number': line(number),
    'circle': decoration is BoxDecoration ? '${decoration.color}' : 'null',
    'keyed': column?.key != null,
  };
}

/// Every table on the screen, read, checked against the old sequence, and
/// returned as one canonical string for the frozen digest, with the squares
/// as built so a test can check the fixture reached what it is for.
(String, List<Map<String, Object?>>) _readAndCompare(
    WidgetTester tester, LandingHarness h, S s) {
  final ctx = tester.element(find.byType(Scaffold).first);
  final goldInk = ctx.gp.goldInk;
  final tables = find.byWidgetPredicate(_isTable).evaluate().toList();
  expect(tables, isNotEmpty);
  final dash = h.container.read(dashboardProvider);
  final clock = h.container.read(dayClockSourceProvider);
  final stepsByDay = h.container.read(stepsByDayProvider);
  final stalled = h.container.read(stepsFailureProvider) != null;
  final voice = h.container.read(squareVoiceIndexProvider);
  final canonical = <Object?>[];
  final all = <Map<String, Object?>>[];
  for (final tableElement in tables) {
    final table = tableElement.widget as dynamic;
    final habits = (table.habits as List).cast<IslamicHabitTemplate>();
    final state = table.state as WeeklyGridState;
    final holdsCellKey = table.todayCellKey != null;
    final days = state.days;

    // The header: three lines a day, before any row.
    final texts = find
        .descendant(
          of: find.byWidget(tableElement.widget),
          matching: find.byType(Text),
        )
        .evaluate()
        .take(21)
        .toList();
    final header = <Map<String, Object?>>[];
    for (var i = 0; i < 7; i++) {
      final built = _headerAsBuilt(texts, i);
      header.add(built);
      final day = days[i];
      final today = day.isRealToday;
      expect(built['primary'],
          startsWith('${DateFormat('EEE', s.isAr ? 'ar' : 'en').format(day)}|'));
      expect(built['secondary'],
          startsWith('${DateFormat('EEE', s.isAr ? 'en' : 'ar').format(day)}|'));
      expect(built['number'], startsWith('${day.day}|'));
      for (final line in ['primary', 'secondary', 'number']) {
        expect((built[line] as String).contains('|$goldInk|'), today,
            reason: 'header $i $line is gold only on the real today');
      }
      expect(built['circle'] != 'null', today, reason: 'circle on day $i');
      expect(built['keyed'], today, reason: 'scroll key on day $i');
    }

    final cells = find
        .descendant(
          of: find.byWidget(tableElement.widget),
          matching: find.byWidgetPredicate(_isSquareCell),
        )
        .evaluate()
        .toList();
    expect(cells.length, habits.length * 7);
    final rows = <Object?>[];
    for (var r = 0; r < habits.length; r++) {
      final habit = habits[r];
      final demand = quotaDemandForRow(
        habit: habit,
        days: days,
        isGreenAt: (i) => state.squareFor(habit.id, days[i]).isGreen,
        isUnmarkedAt: (i) =>
            state.squareFor(habit.id, days[i]) == SquareState.none,
        isHalfAt: (i) =>
            state.squareFor(habit.id, days[i]) == SquareState.partial,
      );
      for (var i = 0; i < 7; i++) {
        final cell = cells[r * 7 + i];
        final built = _cellAsBuilt(cell.widget);
        final old = _cellTheOldWay(
          habit: habit,
          day: days[i],
          days: days,
          state: state,
          demand: demand,
          dash: dash,
          clock: clock,
          stepsByDay: stepsByDay,
          stepsStalled: stalled,
          voice: voice,
          s: s,
          holdsCellKey: holdsCellKey && r == 0,
        );
        expect(built, old, reason: '${habit.id} on day $i');
        rows.add({
          ...built,
          'size': '${(cell.widget as dynamic).size}',
        });
        all.add(built);
      }
    }
    canonical.add({
      'habits': [for (final h in habits) h.id],
      'header': header,
      'cells': rows,
    });
  }
  expect(all, isNotEmpty);
  return (jsonEncode(canonical), all);
}

void main() {
  final zone = _zoneFingerprint();

  /// One board: [weekStart] pinned, drawn in [lang].
  ///
  /// [preCutoff] stands the day clock at 02:18 today, inside yesterday's
  /// open tail, so yesterday's counted square draws its own count.
  /// [stalled] is a steps link whose last read failed. [frozenAs] names the
  /// digest this board is pinned to when the zone has one.
  void board(
    String name, {
    required DateTime Function() weekStart,
    required String lang,
    bool preCutoff = false,
    bool stalled = false,
    String? frozenAs,
  }) {
    group(name, () {
      late LandingHarness h;
      late BoardFixture fixture;

      setUp(() async {
        fixture = BoardFixture(weekStart(), now: DateTime.now());
        final t = DateTime.now();
        DateTime clock() => DateTime(t.year, t.month, t.day, 2, 18);
        h = LandingHarness();
        await h.prepare(extraOverrides: [
          habitListProvider.overrideWith((ref) => fixture.habits),
          habitsArchivedTodayProvider.overrideWith((ref) => const []),
          weeklyGridProvider
              .overrideWith((ref) => PinnedGrid(ref, fixture.state())),
          dashboardProvider
              .overrideWith((ref) => PinnedDashboard(fixture.dashboard())),
          stepsByDayProvider.overrideWith((ref) => fixture.steps()),
          if (stalled)
            stepsFailureProvider
                .overrideWith((ref) => HealthStepsFailure.notSupported),
          if (preCutoff) dayClockSourceProvider.overrideWithValue(clock),
        ]);
        h.container.read(weeklyGridProvider);
        h.container.read(dashboardProvider);
        final voice = h.container.read(squareVoiceIndexProvider.notifier);
        // Its load reads the guest store; let it land in the real zone.
        await Future<void>.delayed(const Duration(milliseconds: 50));
        for (final key in fixture.voiceKeys()) {
          voice.setCount(key, 1);
        }
      });
      tearDown(() => h.dispose());

      testWidgets('every square and header is what the old sequence drew',
          (tester) async {
        await tester.pumpWidget(h.app(locale: Locale(lang)));
        await h.settle(tester);
        final (canonical, cells) =
            _readAndCompare(tester, h, S(Locale(lang)));
        // The fixture reaches what it is for: a comparison that never meets
        // a covered square or a note proves nothing about them.
        int where(bool Function(Map<String, Object?> c) test) =>
            cells.where(test).length;
        expect(where((c) => c['isAlive'] == false), greaterThan(0));
        expect(where((c) => c['isScheduled'] == false), greaterThan(0));
        expect(where((c) => c['hasNote'] == true), greaterThan(0));
        expect(where((c) => c['stepFraction'] != 'null'), greaterThan(0));
        expect(where((c) => c['stepCount'] != 'null'), greaterThan(0));
        expect({for (final c in cells) c['square']},
            {for (final s in SquareState.values) s.name});
        final days = fixture.days;
        final now = DateTime.now();
        if (days.any((d) => d.isSameDayAs(now))) {
          expect(where((c) => c['key'] == true), 1);
          expect(where((c) => c['isToday'] == true), greaterThan(0));
          final counted = where((c) => c['dayCount'] != 'null');
          final yesterday = DateTime(now.year, now.month, now.day - 1);
          final yesterdayCounts = days.any((d) => d.isSameDayAs(yesterday)) &&
              yesterday.isOpenDayAt(h.container.read(dayClockSourceProvider)());
          expect(counted, yesterdayCounts ? 2 : 1,
              reason: "today's count, and yesterday's while it is open");
        } else if (days.first.isBefore(now)) {
          expect(where((c) => c['isCovered'] == true), greaterThan(0));
        } else {
          expect(where((c) => c['isFuture'] == true), cells.length);
        }
        if (frozenAs == null) return;
        final digest = sha256.convert(utf8.encode(canonical)).toString();
        final key = '$zone $frozenAs $lang';
        final frozen = _frozen[key];
        if (frozen == null) {
          // ignore: avoid_print
          print('no frozen digest for "$key": $digest');
          return;
        }
        expect(digest, frozen, reason: 'the board drawn for $key moved');
      });
    });
  }

  DateTime thisWeek() => startOfGridWeek(DateTime.now());

  board('this week, English, yesterday still open',
      weekStart: thisWeek, lang: 'en', preCutoff: true);
  board('this week, Arabic, yesterday closed, steps stalled',
      weekStart: thisWeek, lang: 'ar', stalled: true);
  board('this week, Arabic, yesterday still open',
      weekStart: thisWeek, lang: 'ar', preCutoff: true);
  for (final lang in ['en', 'ar']) {
    board('the week of 2026-03-07, $lang',
        weekStart: () => DateTime(2026, 3, 7),
        lang: lang,
        frozenAs: '2026-03-07');
    board('the week of 2025-11-01, $lang',
        weekStart: () => DateTime(2025, 11, 1),
        lang: lang,
        frozenAs: '2025-11-01');
    board('the week of 2026-10-31, $lang',
        weekStart: () => DateTime(2026, 10, 31), lang: lang);
  }
}
