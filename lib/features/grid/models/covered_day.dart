import 'package:flutter/material.dart';

import '../../../core/theme/game_theme.dart';
import '../../habits/catalog/islamic_habit_catalog.dart'
    show IslamicHabitTemplate;
import '../../habits/models/weekly_quota_plan.dart' show DayDemand;
import 'square_state.dart';

/// Whether [day] is one the habit asked nothing of, so an empty square on
/// it is "covered" rather than missing.
///
/// Aziz, 2026-09-08: "some habits are not daily, so when the user sees the
/// grid it looks empty though they did what they had to", and for a
/// specific-days habit "the off-days are dark grey, like missing days". A
/// Monday-Wednesday-Friday habit drew four dimmed squares a week, and a
/// four-a-week habit drew three plain ones, and both read as failure. The
/// good trackers all keep a third state between done and missed that leans
/// toward done: Loop's faded check on the days a week already covered, the
/// faint "not due" cell of the Obsidian habits plugin. This is ours.
///
/// A day is covered when nothing was recorded on it AND the habit did not
/// ask for it:
///
/// - an off-day of a specific-days schedule, known in advance, so it is
///   covered from the first day, today included;
/// - a day of a flexible weekly quota that was never load-bearing (see
///   [DayDemand]): a `spare` day once it has passed, and an `earned` day the
///   moment the target is met, today included, so the week fills in the
///   instant the last session lands.
///
/// Never a day before the habit existed or after it was archived, never a
/// future day, and never a day that carries any mark: a real colour is a
/// record and stays what it is. Today's `spare` day is not covered either,
/// because it is still open, which is the one meaning the plain square is
/// left with.
bool isCoveredDay({
  required IslamicHabitTemplate habit,
  required DateTime day,
  required DateTime today,
  required SquareState square,
  DayDemand? demand,
}) {
  if (square != SquareState.none) return false;
  final d = DateTime(day.year, day.month, day.day);
  final t = DateTime(today.year, today.month, today.day);
  if (d.isAfter(t)) return false;
  final born = habit.createdAt;
  if (born != null && d.isBefore(DateTime(born.year, born.month, born.day))) {
    return false;
  }
  final died = habit.archivedAt;
  if (died != null && d.isAfter(DateTime(died.year, died.month, died.day))) {
    return false;
  }
  if (habit.scheduledWeekdays.isNotEmpty) {
    return !habit.scheduledWeekdays.contains(d.weekday);
  }
  if (demand == null) return false;
  if (demand == DayDemand.earned) return true;
  return demand == DayDemand.spare && d.isBefore(t);
}

/// The fill of a covered square on the Grid and the surfaces that copy its
/// squares: the system's own done green, soft. About half the strength of
/// [SquareState.complete]'s fill, so a covered week reads as one green
/// block in two tones, sessions bright and covered days soft, and the two
/// stay clearly apart. No border of its own: the empty square's hairline
/// keeps the shape.
Color coveredDayFill(bool dark) =>
    GameColors.emerald.withOpacity(dark ? 0.16 : 0.12);
