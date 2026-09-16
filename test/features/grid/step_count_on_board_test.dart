// A linked walking habit's squares carry the day's count ("8.4k"), so a week
// of walking reads at a glance: Aziz, 2026-09-16, design option A.
//
// Rendered through the real GridScreen rather than a pure helper, because the
// helpers (compactStepCount, stepSquareCount) are covered on their own in
// test/features/habits/step_count_display_test.dart and what can still go
// wrong is the wiring: the count reaching the right square, today coming from
// the live read, and a future day staying empty.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/core/utils/bidi_fraction.dart';
import 'package:grow_daily_v2/features/grid/notifiers/weekly_grid_notifier.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';
import 'package:grow_daily_v2/features/habits/step_auto_complete.dart';

import '../../helpers/landing_harness.dart';

void main() {
  late LandingHarness h;

  final walk = IslamicHabitCatalog.findById('daily_walk')!;
  final linkedWalk = IslamicHabitTemplate.fromMap(
    walk.id,
    {...walk.toFirestore(), 'stepGoal': 8000},
  );

  final today = DateTime.now().effectiveDay;
  final week = List.generate(
    7,
    (i) {
      final start = startOfGridWeek(today);
      return DateTime(start.year, start.month, start.day + i);
    },
  );
  // A different count per day, so a count landing on the wrong column fails.
  const counts = [9120, 3210, 10240, 5480, 12640, 950, 7300];

  setUp(() async {
    h = LandingHarness();
    await h.prepare(extraOverrides: [
      habitListProvider.overrideWith((ref) => [linkedWalk]),
      stepsByDayProvider.overrideWith((ref) => {
            for (var i = 0; i < 7; i++)
              if (!week[i].isAfter(today) && !week[i].isSameDayAs(today))
                week[i].toDateKey(): counts[i],
          }),
      stepsTodayProvider.overrideWith(
        (ref) => counts[week.indexWhere((d) => d.isSameDayAs(today))],
      ),
    ]);
  });
  tearDown(() => h.dispose());

  testWidgets('every walked day shows its own short count', (tester) async {
    await h.pumpApp(tester);

    for (var i = 0; i < 7; i++) {
      final label = bidiIsolate(compactStepCount(counts[i])!);
      final day = week[i];
      if (day.isAfter(today)) {
        expect(find.text(label), findsNothing,
            reason: '${day.toDateKey()} is a future day and has no walk');
      } else {
        expect(find.text(label), findsOneWidget,
            reason: '${day.toDateKey()} should show $label '
                '(${day.isSameDayAs(today) ? 'today, from the live read' : 'from the day log'})');
      }
    }
  });

  testWidgets('the count fits inside its square', (tester) async {
    await h.pumpApp(tester);
    final todayLabel = bidiIsolate(compactStepCount(
      counts[week.indexWhere((d) => d.isSameDayAs(today))],
    )!);
    final text = find.text(todayLabel);
    expect(text, findsOneWidget);
    final square = find.ancestor(
      of: text,
      matching: find.byType(AnimatedContainer),
    );
    final textRect = tester.getRect(text);
    final squareRect = tester.getRect(square.first);
    expect(squareRect.contains(textRect.topLeft), isTrue,
        reason: 'text $textRect spills out of square $squareRect');
    expect(squareRect.contains(textRect.bottomRight - const Offset(0.01, 0.01)),
        isTrue,
        reason: 'text $textRect spills out of square $squareRect');
  });
}
