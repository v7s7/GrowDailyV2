// A new account's first screen has to SHOW the way in.
//
// The Get Started card's four rows used to stand above the empty board, and on
// an iPhone 17 Pro that pushed «إضافة عادة» under the bottom bar (828pt, the
// bar from 814pt) and «استعرض الخطط» off the screen, right under a line saying
// «اضغط "إضافة عادة" تحت». The card now waits for the first habit.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/providers/nav_layout_provider.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';
import 'package:grow_daily_v2/shared/widgets/get_started_checklist_card.dart';
import 'package:grow_daily_v2/shared/widgets/home_shell.dart';

import '../../helpers/landing_harness.dart';

void main() {
  late LandingHarness h;
  setUp(() async {
    h = LandingHarness();
    // Habits and Tasks side by side: Profile reaches for Firebase, which a
    // widget test does not have, and is never built this way.
    await h.prepare(extraOverrides: [
      navLayoutProvider.overrideWith((ref) => NavLayoutNotifier(
          const [NavTab.grid, NavTab.matrix, NavTab.profile])),
    ]);
  });
  tearDown(() => h.dispose());

  Future<void> pumpFrames(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// iPhone 17 Pro: 402x874 points at 3x, 62pt status area, 34pt home bar.
  void iPhone17Pro(WidgetTester tester) {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.padding = const FakeViewPadding(top: 186, bottom: 102);
    tester.view.viewPadding = const FakeViewPadding(top: 186, bottom: 102);
    addTearDown(tester.view.reset);
  }

  testWidgets('an empty board shows both ways in, above the bar',
      (tester) async {
    iPhone17Pro(tester);
    await tester.pumpWidget(
        h.app(home: const HomeShell(), locale: const Locale('ar')));
    await pumpFrames(tester);

    expect(find.byType(GetStartedChecklistCard), findsNothing,
        reason: 'the empty state teaches step one on its own');

    final barTop = tester.getRect(find.text('العادات').first).top;
    for (final label in ['إضافة عادة', 'استعرض الخطط']) {
      final r = tester.getRect(find.text(label).last);
      expect(r.bottom, lessThan(barTop),
          reason: '«$label» has to be on screen without scrolling');
    }
  });

  testWidgets('the card arrives with the first habit', (tester) async {
    iPhone17Pro(tester);
    await tester.pumpWidget(
        h.app(home: const HomeShell(), locale: const Locale('ar')));
    await pumpFrames(tester);

    // In the real zone, so the save lands (see LandingHarness).
    await tester.runAsync(() async {
      h.container.read(customHabitsProvider.notifier).add(
            name: 'قراءة',
            category: HabitCategory.quran,
            frequencyType: HabitFrequencyType.daily,
            frequencyTarget: 1,
          );
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await pumpFrames(tester);

    expect(find.byType(GetStartedChecklistCard), findsOneWidget);
    expect(find.text('الخطوة 2 من 4'), findsOneWidget,
        reason: 'step one is already done, so the card opens on step two');
  });
}
