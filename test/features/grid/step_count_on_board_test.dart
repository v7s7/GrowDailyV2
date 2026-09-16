// A linked walking habit's squares carry the day's count ("2730", "12k"), so
// a week of walking reads at a glance: Aziz, 2026-09-16, design option A.
//
// Rendered through the real GridScreen rather than a pure helper, because the
// helpers (fullStepCount, stepSquareCount) are covered on their own in
// test/features/habits/step_count_display_test.dart and what can still go
// wrong is the wiring: the count reaching the right square, today coming from
// the live read, and a future day staying empty.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/features/grid/notifiers/weekly_grid_notifier.dart';
import 'package:grow_daily_v2/features/grid/widgets/step_count_label.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';
import 'package:grow_daily_v2/features/habits/step_auto_complete.dart';

import '../../helpers/landing_harness.dart';

void main() {
  group('StepCountLabel picks the form that fits', () {
    Future<String> drawn(
      WidgetTester tester,
      int steps,
      double side, {
      bool narrowDigits = true,
    }) async {
      // flutter_test's font draws every glyph a full em wide, which no real
      // face does (four digits would never fit any square). Half-em advances
      // stand in for a real face's digits; narrowDigits: false keeps the full
      // em, which is how a square too small for four digits is made.
      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: SizedBox.square(
            dimension: side,
            child: DefaultTextStyle(
              style: TextStyle(
                letterSpacing:
                    narrowDigits ? -side * StepCountLabel.typeShare / 2 : 0,
              ),
              child: Center(
                child: StepCountLabel(
                  steps: steps,
                  squareSize: side,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ));
      return tester.widget<Text>(find.byType(Text)).data!;
    }

    testWidgets('every digit where they fit', (tester) async {
      expect(await drawn(tester, 9999, 200), '9999');
      expect(await drawn(tester, 2730, 200), '2730');
      expect(await drawn(tester, 12640, 200), '12k');
    });

    testWidgets('the short form where four digits do not', (tester) async {
      expect(await drawn(tester, 9999, 40, narrowDigits: false), '9.9k');
      expect(await drawn(tester, 2730, 40, narrowDigits: false), '2.7k');
    });

    testWidgets('never wider than the square, even when shrunk', (tester) async {
      await drawn(tester, 123456, 14, narrowDigits: false);
      expect(tester.getSize(find.byType(Text)).width,
          lessThanOrEqualTo(14 - 2 * StepCountLabel.sideRoom + 0.01));
    });
  });

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
              if (!week[i].isAfter(today)) week[i].toDateKey(): counts[i],
          }),
      // A count the day log does not back for any visible day: what
      // stepsTodayProvider still holds in the minutes after midnight, when it
      // is yesterday's walk. It must never be drawn (2026-09-17, 00:06: the
      // new day's square read yesterday's "12k").
      stepsTodayProvider.overrideWith((ref) => 77777),
    ]);
  });
  tearDown(() => h.dispose());

  testWidgets('every walked day shows its own short count', (tester) async {
    await h.pumpApp(tester);

    for (var i = 0; i < 7; i++) {
      final label = fullStepCount(counts[i])!;
      final day = week[i];
      if (day.isAfter(today)) {
        expect(find.text(label), findsNothing,
            reason: '${day.toDateKey()} is a future day and has no walk');
      } else {
        expect(find.text(label), findsOneWidget,
            reason: '${day.toDateKey()} should show $label from the day log');
      }
    }
  });

  testWidgets('a dateless count is never drawn on today', (tester) async {
    await h.pumpApp(tester);
    expect(find.text('77k'), findsNothing);
  });

  testWidgets('the count fits inside its square', (tester) async {
    await h.pumpApp(tester);
    final todayLabel = fullStepCount(
      counts[week.indexWhere((d) => d.isSameDayAs(today))],
    )!;
    final text = find.text(todayLabel);
    expect(text, findsOneWidget);
    final square = find.ancestor(
      of: text,
      matching: find.byType(AnimatedContainer),
    );
    final textRect = tester.getRect(text);
    final squareRect = tester.getRect(square.first);
    // Centred, not pushed to one side. On the simulator the first build drew
    // "2.7" off-centre with its "k" missing (invisible bidi marks threw the
    // FittedBox measurement off); centring is the part a test font can see.
    expect((textRect.center.dx - squareRect.center.dx).abs(), lessThan(1.0),
        reason: 'text $textRect is not centred in square $squareRect');
    expect(squareRect.contains(textRect.topLeft), isTrue,
        reason: 'text $textRect spills out of square $squareRect');
    expect(squareRect.contains(textRect.bottomRight - const Offset(0.01, 0.01)),
        isTrue,
        reason: 'text $textRect spills out of square $squareRect');
  });
}
