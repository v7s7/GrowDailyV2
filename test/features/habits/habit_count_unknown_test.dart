// The habit cap on a phone whose habits have not arrived.
//
// A signed-in board comes from the server, or from the device's copy of the
// last answer while the server is asked. A new phone offline has neither, so
// its list is empty because nothing has come, and until 2026-09-26 the cap
// read that as "no habits": a free account could add ten there and keep
// them on top of its real ten once it reconnected. Now the cap needs a count
// (habitCountIsKnown), and without one it says the habits have not reached
// the phone, rather than selling Premium over a limit nobody has hit.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';
import 'package:grow_daily_v2/features/premium/notifiers/premium_notifier.dart';
import 'package:grow_daily_v2/shared/widgets/habit_limit_gate.dart';

import '../../helpers/landing_harness.dart';

void main() {
  const s = S(Locale('en'));
  late LandingHarness h;
  tearDown(() => h.dispose());

  /// A free, signed-in board ([hydrated] or not), and a button that asks
  /// the cap the way every add does.
  Future<bool?> tapAdd(WidgetTester tester, {required bool hydrated}) async {
    h = LandingHarness();
    await tester.runAsync(() => h.prepare(extraOverrides: [
          guestModeProvider.overrideWith((ref) => false),
          premiumAccessProvider.overrideWithValue(false),
          habitsHydratedProvider.overrideWithValue(hydrated),
        ]));
    bool? answer;
    await tester.pumpWidget(h.app(
      home: Consumer(
        builder: (context, ref, _) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () {
                answer = canAddHabits(ref);
                if (answer == false) showHabitLimitGate(context, ref);
              },
              child: const Text('add'),
            ),
          ),
        ),
      ),
    ));
    await h.settle(tester);
    await tester.tap(find.text('add'));
    await tester.pump(const Duration(milliseconds: 300));
    return answer;
  }

  testWidgets('no count: no add, and it says the habits have not arrived',
      (tester) async {
    expect(await tapAdd(tester, hydrated: false), isFalse);
    expect(find.text(s.habitsNotLoadedNotice), findsOneWidget);
    expect(find.text(s.habitLimitTitle), findsNothing,
        reason: 'no limit was reached, so no Premium pitch');
    // The notice leaves on its own timer.
    await tester.pump(const Duration(seconds: 4));
    await h.settle(tester);
  });

  testWidgets('with a count, an empty board adds as it always did',
      (tester) async {
    expect(await tapAdd(tester, hydrated: true), isTrue);
    expect(find.text(s.habitsNotLoadedNotice), findsNothing);
  });
}
