// The habit reorder sheet drags from the grip only.
//
// Until 2026-09-30 the whole row was the drag handle, with no press-and-hold,
// on the theory that a row in a reorder sheet could mean nothing else. It
// could: with more habits than the sheet shows, the list scrolls, and a
// scroll that began on a row picked that habit up and moved it. Aziz kept
// moving habits by mistake while he only wanted to scroll.
//
// The invariant, stated as a user would: a finger that lands on a habit's
// name scrolls the list and never changes the order; a finger that lands on
// the ≡ grip (or the space around it) moves the habit at once.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/features/grid/screens/grid_screen.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';
import 'package:grow_daily_v2/features/habits/notifiers/habit_order_notifier.dart';

import '../../helpers/landing_harness.dart';

void main() {
  late LandingHarness h;

  // Sixteen rows of 52pt against a sheet capped at 70% of a 1000pt surface,
  // so the list has to scroll, which is the whole situation being tested.
  const ids = [
    'quran_daily_page',
    'quran_memorization',
    'morning_athkar',
    'evening_athkar',
    'tahajjud',
    'daily_walk',
    'gym_consistency',
    'sunnah_fasting',
    'daily_sadaqah',
    'sleep_schedule',
    'marriage_dua',
    'marriage_savings',
    'lower_gaze',
    'marriage_gratitude',
    'marriage_read',
    'marriage_checkin',
  ];

  setUp(() async {
    h = LandingHarness();
    await h.prepare(activeCatalogIds: ids);
    // The sheet copies the list once, in initState, and on the real Grid it
    // is long loaded by then. Nothing here watches it before the sheet
    // opens, so load it (and the guest ranks) in the real zone first, the
    // way habit_reorder_test.dart does.
    h.container.read(habitListProvider);
    h.container.read(habitOrderProvider);
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });
  tearDown(() => h.dispose());

  List<String> order() =>
      [for (final habit in h.container.read(habitListProvider)) habit.id];

  Future<void> openSheet(WidgetTester tester) async {
    await tester.pumpWidget(
      h.app(
        locale: const Locale('ar'),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showHabitReorderSheet(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await h.settle(tester);
    await tester.tap(find.text('open'));
    await h.settle(tester);
  }

  Finder nameOf(String id) => find.text(
        h.container
            .read(habitListProvider)
            .firstWhere((habit) => habit.id == id)
            .localName(true),
      );

  ScrollPosition listPosition(WidgetTester tester) => tester
      .state<ScrollableState>(
        find
            .descendant(
              of: find.byType(ReorderableListView),
              matching: find.byType(Scrollable),
            )
            .first,
      )
      .position;

  testWidgets('a drag that starts on a name scrolls and never reorders',
      (tester) async {
    await openSheet(tester);
    final before = order();
    expect(before.length, ids.length);
    expect(
      listPosition(tester).maxScrollExtent,
      greaterThan(0),
      reason: 'the list must be long enough to scroll',
    );

    // Down from the third row's name: under the old whole-row handle this
    // carried the habit three rows down.
    await tester.drag(nameOf(before[2]), const Offset(0, 150));
    await h.settle(tester);
    expect(order(), before);

    // Up from the same name: the list scrolls, the order stays.
    await tester.drag(nameOf(before[2]), const Offset(0, -200));
    await h.settle(tester);
    expect(order(), before);
    expect(listPosition(tester).pixels, greaterThan(0));
  });

  testWidgets('a drag from the grip moves the habit', (tester) async {
    await openSheet(tester);
    final before = order();
    final grip = find.byKey(ValueKey('reorder-grip-${before.first}'));
    expect(grip, findsOneWidget);

    // The grip zone is the full row height and 48pt wide, not just the
    // 20pt icon: start near its outer corner, off the icon itself.
    final zone = tester.getRect(grip);
    expect(zone.width, 48);
    expect(zone.height, 44);
    final gesture =
        await tester.startGesture(zone.topCenter + const Offset(0, 4));
    for (var i = 0; i < 8; i++) {
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await h.settle(tester);

    final after = order();
    expect(after.first, isNot(before.first));
    expect(after.indexOf(before.first), greaterThan(0));
    expect(after.toSet(), before.toSet());
  });
}
