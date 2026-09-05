// Pausing a habit must not re-colour the days you already earned.
//
// The heatmap used to drop archived habits from its DENOMINATOR across all
// of history while its numerator kept their completions. The asymmetry is
// the exact one this file's own source called out as the thing to avoid,
// and it arrived by accident: the two halves were decided months apart and
// the second silently broke the first one's invariant.
//
// The damage was not one bad day. Pausing a habit re-coloured every day it
// had ever been active, right back to its creation: a day where that habit
// was one of two logged went from 1-of-2 (a half day) to 1-of-1 (a full
// one). The map rewrote the past to be better than it was, which is the
// one thing a record must not do.
//
// heatmapScheduledOn is the denominator, named so the rule has somewhere to
// be tested. What it must guarantee: an archived habit counts for exactly
// the days it was really active, and pausing changes nothing before the
// pause day.
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/features/grid/screens/monthly_heatmap_screen.dart'
    show heatmapScheduledOn, dayFill;
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';

void main() {
  IslamicHabitTemplate habit(
    String id, {
    required DateTime created,
    DateTime? archived,
  }) =>
      IslamicHabitTemplate(
        id: id,
        name: id,
        description: '',
        category: HabitCategory.custom,
        frequencyType: HabitFrequencyType.daily,
        frequencyTarget: 1,
        hasTimer: false,
        xpReward: 10,
        goldReward: 5,
        createdAt: created,
        archivedAt: archived,
      );

  final june = DateTime(2026, 6, 15);
  final pauseDay = DateTime(2026, 8, 2);
  final afterPause = DateTime(2026, 8, 20);

  test('an archived habit still counts for the days it was active', () {
    final habits = [
      habit('live', created: DateTime(2026, 1, 1)),
      habit('paused', created: DateTime(2026, 1, 1), archived: pauseDay),
    ];
    expect(heatmapScheduledOn(habits, june), 2,
        reason: 'in June both habits were on the board, so a June day owed '
            'two — pausing one in August cannot change that');
  });

  test('it stops counting after the pause day, and not before', () {
    final habits = [
      habit('live', created: DateTime(2026, 1, 1)),
      habit('paused', created: DateTime(2026, 1, 1), archived: pauseDay),
    ];
    // The pause day ITSELF still counts. That is deliberate elsewhere in
    // the app too: archiving at 11pm must not retroactively excuse the day.
    expect(heatmapScheduledOn(habits, pauseDay), 2,
        reason: 'the day you paused was still a day the habit was owed');
    expect(heatmapScheduledOn(habits, afterPause), 1,
        reason: 'after the pause only the live habit is owed');
  });

  test('the day that used to be re-coloured now reads honestly', () {
    // The regression, expressed as the user would see it: one of two
    // habits done on a June day.
    final habits = [
      habit('live', created: DateTime(2026, 1, 1)),
      habit('paused', created: DateTime(2026, 1, 1), archived: pauseDay),
    ];
    final planned = heatmapScheduledOn(habits, june);
    // dayFill's enum is private, so compare against the two references
    // rather than naming a value: a half day must paint like a half day,
    // not like a finished one.
    expect(dayFill(1, planned), isNot(dayFill(planned, planned)),
        reason: 'one of two done must not paint as a full day');
    expect(dayFill(1, planned), dayFill(1, 2),
        reason: 'and it must paint as exactly what it is: 1 of 2');
  });

  test('a habit paused before a day was never owed on it', () {
    final habits = [habit('paused', created: june, archived: pauseDay)];
    expect(heatmapScheduledOn(habits, DateTime(2026, 5, 1)), 0,
        reason: 'a day before the habit existed owes nothing');
    expect(heatmapScheduledOn(habits, afterPause), 0);
  });

  test('a day owing nothing is still distinguishable from a day owing one',
      () {
    // Guards the seam between this function and dayFill: planned == 0 has
    // its own meaning (rest / nothing asked), and collapsing it into
    // "planned == 1, not done" would turn quiet days into failures.
    expect(dayFill(0, 0), isNot(dayFill(0, 1)));
  });
}
