// A tab asked for BEFORE HomeShell was built.
//
// That is what a Lock Screen control or widget does when it cold-starts the
// app: main.dart's _openFromOutside asks for the tab while the sign-in gate
// is still up, long before the shell exists. The shell's listener only hears
// requests made after it registers, so the request used to sit unread: the
// app opened on Habits whatever was tapped (Aziz, 2026-09-21), and because
// the provider still held that tab, the next tap asking for the same one was
// not a change either and did nothing at all.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/providers/home_tab_provider.dart';
import 'package:grow_daily_v2/core/providers/nav_layout_provider.dart';
import 'package:grow_daily_v2/features/matrix/screens/matrix_screen.dart';
import 'package:grow_daily_v2/shared/widgets/game_nav_bar.dart';
import 'package:grow_daily_v2/shared/widgets/home_shell.dart';

import '../helpers/landing_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// A phone, not the 800x600 default: MatrixScreen's quadrants overflow at
  /// 600pt, which no phone produces (same helper as nav_bar_labels_test).
  Future<void> phoneSized(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(402, 874));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  /// Fixed frames, not pumpAndSettle: an empty quadrant's "+" breathes
  /// forever, so settle would burn its whole timeout once Tasks is up.
  Future<void> pumpFrames(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  int barIndex(WidgetTester tester) => tester
      .widget<GameNavBar>(find.byType(GameNavBar, skipOffstage: false))
      .currentIndex;

  group('the default bar (Habits, Profile, Tasks)', () {
    late LandingHarness harness;

    setUp(() async {
      harness = LandingHarness();
      await harness.prepare();
    });

    tearDown(() => harness.dispose());

    testWidgets('opens on the tab that was asked for, not on Habits',
        (tester) async {
      await phoneSized(tester);
      // What _openFromOutside leaves behind on a cold start.
      harness.container.read(requestedHomeTabInstantProvider.notifier).state =
          true;
      harness.container.read(requestedHomeTabProvider.notifier).state =
          NavTab.matrix;

      await tester.pumpWidget(
          harness.app(home: const HomeShell(initialTab: NavTab.grid)));
      await pumpFrames(tester);

      expect(barIndex(tester), 2, reason: 'Tasks is the third tab');
      expect(find.byType(MatrixScreen), findsOneWidget);
    });

    testWidgets('consumes the request, so the next one is a change again',
        (tester) async {
      await phoneSized(tester);
      harness.container.read(requestedHomeTabInstantProvider.notifier).state =
          true;
      harness.container.read(requestedHomeTabProvider.notifier).state =
          NavTab.matrix;

      await tester.pumpWidget(
          harness.app(home: const HomeShell(initialTab: NavTab.grid)));
      await pumpFrames(tester);

      expect(harness.container.read(requestedHomeTabProvider), isNull,
          reason: 'left holding Tasks, the next Tasks tap would not be heard');
      expect(harness.container.read(requestedHomeTabInstantProvider), isFalse);

      // And the shell still answers requests once it is up: back to Habits,
      // then Tasks again, each landing where it asked.
      harness.container.read(requestedHomeTabInstantProvider.notifier).state =
          true;
      harness.container.read(requestedHomeTabProvider.notifier).state =
          NavTab.grid;
      await pumpFrames(tester);
      expect(barIndex(tester), 0);

      harness.container.read(requestedHomeTabInstantProvider.notifier).state =
          true;
      harness.container.read(requestedHomeTabProvider.notifier).state =
          NavTab.matrix;
      await pumpFrames(tester);
      expect(barIndex(tester), 2);
    });

    testWidgets('with nothing asked for, still opens on its own tab',
        (tester) async {
      await phoneSized(tester);
      await harness.pumpApp(tester,
          home: const HomeShell(initialTab: NavTab.grid));

      expect(barIndex(tester), 0);
      expect(find.byType(MatrixScreen), findsNothing);
    });
  });

  // Rooms LAST, as in nav_bar_labels_test: RoomsHubScreen opens Firestore
  // streams this harness has no Firebase for, and at index 4 it is never
  // built while the shell sits on Habits.
  group('a bar without Tasks', () {
    const layout = [
      NavTab.grid,
      NavTab.profile,
      NavTab.tasbih,
      NavTab.settings,
      NavTab.rooms,
    ];
    late LandingHarness harness;

    setUp(() async {
      harness = LandingHarness();
      await harness.prepare(extraOverrides: [
        navLayoutProvider.overrideWith((ref) => NavLayoutNotifier(layout)),
      ]);
    });

    tearDown(() => harness.dispose());

    testWidgets('a waiting request for Tasks is pushed over the shell',
        (tester) async {
      await phoneSized(tester);
      harness.container.read(requestedHomeTabProvider.notifier).state =
          NavTab.matrix;

      await tester.pumpWidget(
          harness.app(home: const HomeShell(initialTab: NavTab.grid)));
      await pumpFrames(tester);

      expect(find.byType(MatrixScreen), findsOneWidget);
      // A route over the shell, not a page in it.
      expect(barIndex(tester), 0);
      expect(harness.container.read(requestedHomeTabProvider), isNull);
    });
  });
}
