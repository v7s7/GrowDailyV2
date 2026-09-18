/// A habit's schedule over time: which cadence governed which days.
///
/// ── Why this exists ────────────────────────────────────────────────────────
///
/// Aziz, 2026-09-18: "i had a habit that is spec days, and after some weeks,
/// i made it daily habit, it should still for the previous days that is spec
/// days, like rest days and the other, and the days after are daily. so its
/// fair for the user."
///
/// A habit carried exactly one schedule, and every surface that looks back
/// (the Grid's past weeks, the progress map, the reports, Insights, the
/// streaks) judged every day the habit ever had by that one schedule. So the
/// moment a Monday-and-Thursday habit became daily, every Tuesday, Wednesday,
/// Friday, Saturday and Sunday behind it turned from a rest day into a miss:
/// weeks of kept promises rewritten as failure by an edit made today. The
/// opposite edit was just as wrong the other way, and quietly excused every
/// day a daily habit had really missed.
///
/// Rooms already solved this for their own grading (RoomHabitRule, a frozen
/// copy of the cadence per room, per period). This is the same idea for the
/// habit itself: the schedules it ran on before its current one, each with
/// the last day it governed, so a past day is always judged by the schedule
/// that was in force ON that day.
///
/// ── The rule ───────────────────────────────────────────────────────────────
///
/// A change takes effect on the day it is saved. That day and every later one
/// follow the new schedule; every earlier day keeps the one it had. The day
/// of the change follows the new one because it is the schedule the person is
/// looking at when they save, the same way a habit added today is asked for
/// today. Yesterday, still open for marking until kDayCutoffHour, is an
/// earlier day and keeps the old schedule.
///
/// Several edits on one day are one change: the schedule saved last is the
/// one that day follows, and an edit straight back to the schedule the day
/// started with leaves no trace at all. See [pastCadencesAfterChange].
///
/// Ints, lists and dates only, no habit and no clock, so the template, the
/// preset override and the tests all share one implementation.
library;

import 'package:flutter/foundation.dart' show immutable;

import '../../../core/extensions/datetime_ext.dart';
import 'habit_model.dart' show HabitFrequencyType;

/// The three things that decide which days a habit asks for: the same three
/// RoomHabitRule freezes, and the same three it compares in `differsFrom`. A
/// rename or a colour change is not a schedule change.
@immutable
class HabitCadence {
  final HabitFrequencyType frequencyType;

  /// Taps a day for a daily habit, days a week for a weekly one.
  final int frequencyTarget;

  /// DateTime.weekday values (1 = Monday ... 7 = Sunday); empty means every
  /// day, exactly as IslamicHabitTemplate.scheduledWeekdays stores it.
  final List<int> scheduledWeekdays;

  const HabitCadence({
    required this.frequencyType,
    required this.frequencyTarget,
    this.scheduledWeekdays = const [],
  });

  /// "N times a week, any days". The same test habit_day_demand.dart's
  /// isFlexibleQuota applies to a whole habit: "Specific Days" is stored as
  /// weekly too and is told apart only by its weekdays, and a target below 1
  /// can never be reached, so it is no quota either.
  bool get isFlexibleQuota =>
      frequencyType == HabitFrequencyType.weekly &&
      scheduledWeekdays.isEmpty &&
      frequencyTarget > 0;

  /// Whether this cadence lets [day] be one of its days. True on every day
  /// for a daily habit and for a flexible quota (any day will do).
  bool runsOnWeekday(DateTime day) =>
      scheduledWeekdays.isEmpty || scheduledWeekdays.contains(day.weekday);

  /// Whether [other] asks for exactly the same days. Weekday ORDER is not a
  /// difference: [1, 4] and [4, 1] are one schedule.
  bool sameAs(HabitCadence other) {
    if (frequencyType != other.frequencyType) return false;
    if (frequencyTarget != other.frequencyTarget) return false;
    final a = scheduledWeekdays.toSet();
    final b = other.scheduledWeekdays.toSet();
    return a.length == b.length && a.containsAll(b);
  }

  @override
  String toString() =>
      'HabitCadence(${frequencyType.name}/$frequencyTarget $scheduledWeekdays)';
}

/// A cadence the habit ran on up to and including [until], and no longer.
@immutable
class PastCadence {
  /// The last day this cadence governed, at local midnight. Inclusive.
  final DateTime until;
  final HabitCadence cadence;

  PastCadence({required DateTime until, required this.cadence})
      : until = DateTime(until.year, until.month, until.day);

  /// Stored as a plain date key, like RoomHabitRule.from, and beside the
  /// cadence's own three fields under the names the habit document already
  /// uses for them, so the admin tool reads one shape everywhere.
  Map<String, dynamic> toMap() => {
        'until': until.toDateKey(),
        'frequencyType': cadence.frequencyType.toJson(),
        'frequencyTarget': cadence.frequencyTarget,
        if (cadence.scheduledWeekdays.isNotEmpty)
          'scheduledWeekdays': cadence.scheduledWeekdays,
      };

  @override
  String toString() => 'PastCadence(until ${until.toDateKey()}, $cadence)';
}

/// Reads a stored `scheduleHistory` list back, oldest first.
///
/// Defensive in the way the rest of the habit parsers are: this arrives from
/// Firestore as `List<dynamic>` of maps, and from Hive (the guest store and
/// the launch mirror) as maps typed `Map<dynamic, dynamic>`. An entry that
/// cannot be read is dropped rather than thrown on: one malformed period
/// should cost that period, never the habit. Sorted, and deduped on its day
/// (the later entry wins), so a list written by any build answers
/// [cadenceOnDay] the same way.
List<PastCadence> parsePastCadences(Object? raw) {
  if (raw is! List) return const [];
  final byDay = <String, PastCadence>{};
  for (final item in raw) {
    if (item is! Map) continue;
    final until = DateTime.tryParse('${item['until']}');
    if (until == null) continue;
    final type = item['frequencyType'];
    final target = item['frequencyTarget'];
    final weekdays = item['scheduledWeekdays'];
    final entry = PastCadence(
      until: until,
      cadence: HabitCadence(
        frequencyType: HabitFrequencyType.fromJson(
          type is String ? type : 'daily',
        ),
        frequencyTarget: target is num ? target.toInt() : 1,
        scheduledWeekdays: weekdays is List
            ? List.unmodifiable(weekdays
                .whereType<num>()
                .map((n) => n.toInt())
                .where((n) => n >= DateTime.monday && n <= DateTime.sunday)
                .toSet()
                .toList()
              ..sort())
            : const [],
      ),
    );
    byDay[entry.until.toDateKey()] = entry;
  }
  if (byDay.isEmpty) return const [];
  final out = byDay.values.toList()
    ..sort((a, b) => a.until.compareTo(b.until));
  return List.unmodifiable(out);
}

/// The stored shape of [past]; see [PastCadence.toMap].
List<Map<String, dynamic>> pastCadencesToRaw(List<PastCadence> past) =>
    [for (final p in past) p.toMap()];

/// The cadence in force on [day]: the first period of [past] that had not
/// ended before it, or [current] once every period had.
///
/// [past] is oldest first, as [parsePastCadences] returns it. Each period
/// starts the day after the one before it ended, and the first reaches back
/// to the habit's birth, so every day has exactly one answer. Whether the
/// habit was alive on [day] at all is a different question, the one
/// IslamicHabitTemplate.isScheduledFor asks of createdAt and archivedAt.
HabitCadence cadenceOnDay(
  List<PastCadence> past,
  HabitCadence current,
  DateTime day,
) {
  if (past.isEmpty) return current;
  final d = DateTime(day.year, day.month, day.day);
  for (final period in past) {
    if (!d.isAfter(period.until)) return period.cadence;
  }
  return current;
}

/// [past] as it stands after the habit's cadence changes from [current] to
/// [next] on [today].
///
///  - Nothing changes when [next] asks for the same days as [current]:
///    saving a habit for its name or its colour is not a schedule change.
///  - Otherwise [current] is recorded as having governed every day up to
///    yesterday, and [next] governs from [today] on.
///  - Unless [current] never governed a finished day, because it only
///    started today (an earlier edit today, or a habit born today). Then it
///    is simply replaced, with nothing recorded: today follows whatever was
///    saved last. And if [next] is the very schedule the last recorded
///    period held, that period is reopened instead, so changing a habit and
///    changing it straight back leaves its history exactly as it was.
///
/// [bornOn] is the habit's createdAt, or null when no birth date is known;
/// such a habit is treated as long established, so its first change is
/// always recorded.
List<PastCadence> pastCadencesAfterChange({
  required List<PastCadence> past,
  required HabitCadence current,
  required HabitCadence next,
  required DateTime? bornOn,
  required DateTime today,
}) {
  if (next.sameAs(current)) return past;
  final t = DateTime(today.year, today.month, today.day);
  // The first day [current] governed: the day after the last recorded
  // period ended, or the habit's birth when nothing is recorded.
  final DateTime? currentFrom = past.isNotEmpty
      ? DateTime(past.last.until.year, past.last.until.month,
          past.last.until.day + 1)
      : (bornOn == null
          ? null
          : DateTime(bornOn.year, bornOn.month, bornOn.day));
  if (currentFrom != null && !currentFrom.isBefore(t)) {
    // [current] has not governed a single finished day. Replace it.
    if (past.isNotEmpty && past.last.cadence.sameAs(next)) {
      return List.unmodifiable(past.sublist(0, past.length - 1));
    }
    return past;
  }
  return List.unmodifiable([
    ...past,
    PastCadence(
      until: DateTime(t.year, t.month, t.day - 1),
      cadence: current,
    ),
  ]);
}
