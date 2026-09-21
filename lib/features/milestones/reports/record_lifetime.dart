import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/datetime_ext.dart';
import '../../../core/providers/day_clock_provider.dart';
import '../../dashboard/notifiers/dashboard_notifier.dart';
import '../../grid/models/square_state.dart';
import '../../grid/notifiers/weekly_grid_notifier.dart' show weeklyGridProvider;
import '../../habits/catalog/islamic_habit_catalog.dart'
    show IslamicHabitTemplate;
import '../../habits/notifiers/custom_habits_notifier.dart';
import '../notifiers/habit_history_notifier.dart';
import 'habit_day_marks.dart';
import 'report_period.dart';

/// The whole record, counted once: every day from where it begins to today,
/// through the same pipeline the أسبوع / شهر / سنة tabs use for a single
/// period.
///
/// ── Why one provider ────────────────────────────────────────────────────
/// The Profile's «المجموع» said 244 while the map and the timeline said 216
/// for the same account (2026-09-21). The 244 was a stored counter that
/// only the check-off button moves: squares set from the Grid's long-press
/// never reached it, and a deleted habit's old completions stayed in it
/// while the record dropped its squares. The 216 is a recount of the squares
/// the record actually shows, one by one. When سجلّي replaced the three
/// record screens, the rule became one lifetime total counted one way, so
/// the Profile tile, the «الكل» tab and its year cards all read this.
///
/// Null until the history mirror has loaded, so no caller ever shows a
/// number it will have to take back.
class RecordLifetime {
  /// Every habit that ever existed, archived ones included, one entry each,
  /// each with a known start (see habitWithKnownStart).
  final List<IslamicHabitTemplate> habits;

  /// The mirror with today's live squares laid over it (see withLiveToday).
  final Map<String, Map<String, SquareState>> history;

  /// The first day anything was marked, or null for an empty record.
  final DateTime? firstMark;

  /// Where the record begins: the earlier of [firstMark] and the first day
  /// any habit was owed (see recordStartOf). «منذ» names it and every
  /// lifetime number counts from it.
  final DateTime? start;

  /// Every lived day from [start] to today.
  final List<DateTime> days;

  /// Green squares per day, keyed by dateKey.
  final Map<String, int> dayCounts;

  final PeriodSummary summary;

  const RecordLifetime({
    required this.habits,
    required this.history,
    required this.firstMark,
    required this.start,
    required this.days,
    required this.dayCounts,
    required this.summary,
  });

  /// Green squares in [year], from the same counts as the lifetime total, so
  /// the year cards always add up to it.
  int totalIn(int year) {
    var total = 0;
    final prefix = '$year-';
    dayCounts.forEach((key, count) {
      if (key.startsWith(prefix)) total += count;
    });
    return total;
  }
}

final recordLifetimeProvider = Provider<RecordLifetime?>((ref) {
  final mirror = ref.watch(habitYearHistoryProvider).valueOrNull;
  if (mirror == null) return null;
  final dash = ref.watch(dashboardProvider);
  final now = ref.watch(dayClockProvider);
  final today = now.effectiveDay;
  final grid = ref.watch(weeklyGridProvider);

  final habits = <IslamicHabitTemplate>[];
  final seen = <String>{};
  for (final h in ref.watch(allHabitsEverProvider)) {
    if (seen.add(h.id)) habits.add(h);
  }

  // Exactly the history the report tabs build (period_report_section.dart),
  // so a day is the same square here as on any tab.
  final history = withLiveToday(
    mirrored: mirror,
    habitIds: habits.map((h) => h.id),
    squareToday: (id) => grid.squareFor(id, today),
    completionsToday: (id) => dash.completions[id] ?? 0,
    dailyTargetOf: (id) {
      for (final h in habits) {
        if (h.id == id) return h.effectiveDailyTarget;
      }
      return 1;
    },
    todayKey: today.toDateKey(),
    gridKnowsToday: !grid.isLoading && grid.isCurrentWeek,
  );

  String? earliestKey;
  for (final marks in history.values) {
    for (final key in marks.keys) {
      if (earliestKey == null || key.compareTo(earliestKey) < 0) {
        earliestKey = key;
      }
    }
  }
  final firstMark = earliestKey == null ? null : DateTime.tryParse(earliestKey);
  // Every habit from its own start, and the record from the earliest of
  // them, which is how a year counts too: on a record that fits in one year,
  // «الكل» and «سنة» now give the same rate (they gave 52% and 28%).
  final known = [
    for (final h in habits)
      habitWithKnownStart(h, history[h.id] ?? const {}, today: today),
  ];
  final start = recordStartOf(known, firstMark);
  final days = start == null
      ? const <DateTime>[]
      : elapsedDaysIn(start: start, end: today, today: today);
  final stats = computeHabitPeriodStats(
    habits: known,
    history: history,
    days: days,
    now: now,
    windowEnd: today,
  );
  final dayCounts = dayCountsFrom(stats);
  return RecordLifetime(
    habits: known,
    history: history,
    firstMark: firstMark,
    start: start,
    days: days,
    dayCounts: dayCounts,
    summary: computePeriodSummary(
      dayCounts: dayCounts,
      days: days,
      habitStats: stats,
      now: now,
    ),
  );
});

/// Every habit that ever existed (stints included, as allHabitsEverProvider
/// emits them), each with a known start (see habitWithKnownStart), for a
/// screen that counts owed days over a long window outside the report tabs.
/// Insights reads this, so a habit's rate there is counted from the same
/// start as on سجلّي. The plain list until the history mirror has loaded.
final habitsWithKnownStartProvider =
    Provider<List<IslamicHabitTemplate>>((ref) {
  final habits = ref.watch(allHabitsEverProvider);
  final mirror = ref.watch(habitYearHistoryProvider).valueOrNull;
  if (mirror == null) return habits;
  final today = ref.watch(dayClockProvider).effectiveDay;
  return [
    for (final h in habits)
      habitWithKnownStart(h, mirror[h.id] ?? const {}, today: today),
  ];
});
