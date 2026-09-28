// The confetti a square fires when a tap finishes its habit for the day is
// sized on the admin's «دوم» page (PetSettings.squareBurst, Aziz 2026-09-28:
// "add the confetti sizes too"), and 0 pieces fires none. Driven through the
// real Grid, where the burst is fired from the square's own tap.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:grow_daily_v2/core/l10n/wording_edits.dart';
import 'package:grow_daily_v2/core/services/local_store_service.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/grid/notifiers/weekly_grid_notifier.dart';

import '../../helpers/landing_harness.dart';

void main() {
  const id = 'sunnah_fasting';
  const name = 'صيام الاثنين والخميس';

  String weekday(DateTime d) => DateFormat('EEEE', 'ar').format(d);
  String month(DateTime d) => DateFormat('MMMM', 'ar').format(d);
  Finder square(DateTime d) => find.bySemanticsLabel(RegExp(
        '^${RegExp.escape('$name، ${weekday(d)} ${d.day} ${month(d)}')}',
      ));
  final bursts = find.byWidgetPredicate(
    (w) => w.runtimeType.toString() == '_VictoryBurst',
  );

  late LandingHarness h;

  setUp(() async {
    h = LandingHarness();
    await h.prepare(activeCatalogIds: const [id]);
    (await LocalStoreService.dailyBox()).clear();
  });
  tearDown(() {
    WordingEditsStore.debugPublish(WordingEdits.empty);
    h.dispose();
  });

  // One test: each tap writes the day to the real Hive box, and a write still
  // in flight when the next test's setUp opens the box hangs the file (see
  // rest_day_tap_test.dart).
  testWidgets('a finished square\'s confetti is the size the settings say, '
      'and 0 pieces fires none', (tester) async {
    await tester.pumpWidget(h.app(locale: const Locale('ar')));
    await h.settle(tester);
    // Last week: every day on the board is closed, whatever day this runs.
    h.container.read(weeklyGridProvider.notifier).previousWeek();
    await h.settle(tester);
    final days = h.container.read(weeklyGridProvider).days;
    final monday = days[2];
    final thursday = days[5];
    SquareState on(DateTime d) =>
        h.container.read(weeklyGridProvider).squareFor(id, d);

    WordingEditsStore.debugPublish(const WordingEdits(
      pet: PetEdits(numbers: {
        'squareConfettiPieces': 7,
        'squareConfettiSpread': 99,
        'squareConfettiMs': 900,
      }),
    ));
    await tester.ensureVisible(square(monday));
    await h.settle(tester);
    await tester.tap(square(monday));
    await tester.pump();
    expect(bursts, findsOneWidget);
    final burst = tester.widget(bursts) as dynamic;
    expect(
      (burst.particleCount, burst.spread, burst.duration),
      (7, 99.0, const Duration(milliseconds: 900)),
    );
    await h.settle(tester);
    expect(on(monday), SquareState.complete);

    WordingEditsStore.debugPublish(const WordingEdits(
      pet: PetEdits(numbers: {'squareConfettiPieces': 0}),
    ));
    await tester.ensureVisible(square(thursday));
    await h.settle(tester);
    await tester.tap(square(thursday));
    await tester.pump();
    expect(bursts, findsNothing);
    await h.settle(tester);
    expect(on(thursday), SquareState.complete,
        reason: 'no confetti, the square is still done');
    await tester.pump(const Duration(milliseconds: 1));
  });
}
