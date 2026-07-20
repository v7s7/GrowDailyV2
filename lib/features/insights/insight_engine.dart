import '../grid/models/square_state.dart';
import '../habits/catalog/islamic_habit_catalog.dart';

/// One habit's aggregated record over the analysis window — scheduled vs
/// completed, overall and per weekday (DateTime.monday..sunday keys).
class HabitPattern {
  final String habitId;
  int scheduled = 0;
  int completed = 0;
  final Map<int, int> scheduledByWeekday = {};
  final Map<int, int> completedByWeekday = {};

  HabitPattern(this.habitId);

  double get rate => scheduled == 0 ? 0 : completed / scheduled;

  /// The weekday this habit misses most — only meaningful (non-null) when
  /// that weekday has at least [minSamples] scheduled occurrences AND its
  /// miss rate is at least 0.5: below either bar, calling it a "pattern"
  /// would just be noise dressed up as insight.
  int? worstWeekday({int minSamples = 3}) {
    int? worst;
    var worstMissRate = 0.5 - 1e-9;
    for (final e in scheduledByWeekday.entries) {
      if (e.value < minSamples) continue;
      final missRate = 1 - ((completedByWeekday[e.key] ?? 0) / e.value);
      if (missRate > worstMissRate) {
        worstMissRate = missRate;
        worst = e.key;
      }
    }
    return worst;
  }
}

/// Everything the Insights screen renders, distilled from the raw per-day
/// docs. Pure output of [computeInsights].
class InsightsResult {
  /// habitId → its pattern. Only habits with any scheduled day in-window.
  final Map<String, HabitPattern> patterns;

  /// Weekday (DateTime.monday..sunday) with the highest overall completion
  /// rate, or null when there isn't enough data to say.
  final int? strongestWeekday;

  /// Highest/lowest completion-rate habits (need >= 7 scheduled samples
  /// each, so a habit added two days ago can't claim either title).
  final String? mostConsistentHabitId;
  final String? needsPushHabitId;

  /// Total scheduled samples across everything — the "is there anything to
  /// analyze at all" signal the empty state keys off.
  final int totalSamples;

  const InsightsResult({
    required this.patterns,
    required this.strongestWeekday,
    required this.mostConsistentHabitId,
    required this.needsPushHabitId,
    required this.totalSamples,
  });
}

/// Aggregates [days] (each day paired with its daily doc — the same
/// squareStates/habitCompletions maps every other history surface reads)
/// against the current habit list. Pure and synchronous: all Firestore/Hive
/// work happens before this is called, so it's trivially unit-testable —
/// see test/features/insights/insight_engine_test.dart.
///
/// "Completed" = a green square (complete/bonus) OR any habitCompletions
/// count > 0 (multi-tap habits never mirror squares — same rule the
/// heatmap's day sheet uses). Skipped squares count as neither completed
/// nor missed: a deliberate skip is a decision, and it shouldn't poison a
/// habit's miss-rate the way a real slip does — so it's excluded from the
/// scheduled total entirely.
InsightsResult computeInsights({
  required List<IslamicHabitTemplate> habits,
  required List<(DateTime, Map<String, dynamic>)> days,
}) {
  final patterns = {for (final h in habits) h.id: HabitPattern(h.id)};
  final byId = {for (final h in habits) h.id: h};

  for (final (day, doc) in days) {
    final rawStates = (doc['squareStates'] as Map?) ?? const {};
    final rawCompletions = (doc['habitCompletions'] as Map?) ?? const {};
    for (final h in habits) {
      if (!h.isScheduledFor(day)) continue;
      final p = patterns[h.id]!;
      final sq = SquareState.fromJson(rawStates[h.id]?.toString());
      if (sq == SquareState.skipped) continue;
      final done = sq.isGreen ||
          (rawCompletions[h.id] is num &&
              (rawCompletions[h.id] as num) > 0);
      p.scheduled++;
      p.scheduledByWeekday[day.weekday] =
          (p.scheduledByWeekday[day.weekday] ?? 0) + 1;
      if (done) {
        p.completed++;
        p.completedByWeekday[day.weekday] =
            (p.completedByWeekday[day.weekday] ?? 0) + 1;
      }
    }
  }

  patterns.removeWhere((_, p) => p.scheduled == 0);

  // Overall strongest weekday, across all habits together.
  final weekdayScheduled = <int, int>{};
  final weekdayCompleted = <int, int>{};
  var totalSamples = 0;
  for (final p in patterns.values) {
    totalSamples += p.scheduled;
    for (final e in p.scheduledByWeekday.entries) {
      weekdayScheduled[e.key] = (weekdayScheduled[e.key] ?? 0) + e.value;
    }
    for (final e in p.completedByWeekday.entries) {
      weekdayCompleted[e.key] = (weekdayCompleted[e.key] ?? 0) + e.value;
    }
  }
  int? strongest;
  var strongestRate = -1.0;
  for (final e in weekdayScheduled.entries) {
    if (e.value < 4) continue; // too few samples to crown a day
    final rate = (weekdayCompleted[e.key] ?? 0) / e.value;
    if (rate > strongestRate) {
      strongestRate = rate;
      strongest = e.key;
    }
  }

  String? best;
  String? worst;
  var bestRate = -1.0;
  var worstRate = 2.0;
  for (final p in patterns.values) {
    if (p.scheduled < 7 || !byId.containsKey(p.habitId)) continue;
    if (p.rate > bestRate) {
      bestRate = p.rate;
      best = p.habitId;
    }
    if (p.rate < worstRate) {
      worstRate = p.rate;
      worst = p.habitId;
    }
  }
  // A single qualifying habit shouldn't be both the star and the problem.
  if (best != null && best == worst) worst = null;

  return InsightsResult(
    patterns: patterns,
    strongestWeekday: strongest,
    mostConsistentHabitId: best,
    needsPushHabitId: worst,
    totalSamples: totalSamples,
  );
}
