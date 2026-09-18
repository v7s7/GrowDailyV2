// The Grid's dates in Arabic, under the real localization delegates.
//
// Three places on the board printed a date through a raw DateFormat, and
// once flutter_localizations has loaded its 'ar' date symbols (as the app
// does at start) that prints Arabic-Indic digits:
//  * a square's spoken label, «تفريغ صندوق الوارد، الجمعة ١٨ سبتمبر، ...»,
//    which is also the handle every Grid test finds a square by;
//  * the long-press editor's date line, which on top of that put the month
//    first and kept the Latin comma: «الجمعة, سبتمبر ١٨»;
//  * the dialog before a past day's mark is cleared: «... منجزة يوم الجمعة
//    ١٨ سبتمبر.»
// The expected strings are built here from the weekday and month NAMES
// (no digits in either) and the plain day number, not from westernDate, so
// the helper under test is not also writing its own answer.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/services/local_store_service.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/grid/notifiers/weekly_grid_notifier.dart';

import '../../helpers/landing_harness.dart';

void main() {
  const ar = S(Locale('ar'));
  const name = 'تفريغ صندوق الوارد';
  final arabicIndic = RegExp('[٠-٩]');

  String weekday(DateTime d) => DateFormat('EEEE', 'ar').format(d);
  String month(DateTime d) => DateFormat('MMMM', 'ar').format(d);

  /// «الجمعة 18 سبتمبر», the square label's and the dialog's form.
  String plainDate(DateTime d) => '${weekday(d)} ${d.day} ${month(d)}';

  Finder square(DateTime d) => find.bySemanticsLabel(
      RegExp('^${RegExp.escape('$name، ${plainDate(d)}')}'));

  late LandingHarness h;

  setUp(() async {
    h = LandingHarness();
    await h.prepare(activeCatalogIds: const ['inbox_zero']);
    // Process-wide boxes, see note_save_feedback_test.
    (await LocalStoreService.dailyBox()).clear();
  });
  tearDown(() => h.dispose());

  Future<void> pumpArabic(WidgetTester tester) async {
    await tester.pumpWidget(h.app(locale: const Locale('ar')));
    await h.settle(tester);
  }

  testWidgets('every square speaks its date in Latin digits', (tester) async {
    await pumpArabic(tester);
    final today = DateTime.now().effectiveDay;
    expect(square(today), findsOneWidget,
        reason: "today's square, found by its Latin-digit date");
    expect(
      find.bySemanticsLabel(RegExp('^${RegExp.escape(name)}، .*[٠-٩]')),
      findsNothing,
      reason: 'a square still speaks an Arabic-Indic date',
    );
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('the long-press editor: weekday، day month, Latin digits',
      (tester) async {
    await pumpArabic(tester);
    final today = DateTime.now().effectiveDay;
    await tester.ensureVisible(square(today));
    await h.settle(tester);
    await tester.longPress(square(today));
    await h.settle(tester);
    expect(find.text(ar.gridSave), findsOneWidget,
        reason: 'the editor did not open, so nothing below is tested');

    expect(
      find.text('${weekday(today)}، ${today.day} ${month(today)}'),
      findsOneWidget,
      reason: 'drew «${weekday(today)}, ${month(today)} ١٨» before',
    );
    expect(
      find.byWidgetPredicate((w) =>
          w is RichText && arabicIndic.hasMatch(w.text.toPlainText())),
      findsNothing,
    );
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('clearing a past mark names the day in Latin digits',
      (tester) async {
    await pumpArabic(tester);
    // Last week, so every day on the board is closed whatever day the suite
    // runs on (a closed day's green square asks before it clears).
    final grid = h.container.read(weeklyGridProvider.notifier);
    grid.previousWeek();
    await h.settle(tester);
    final day = h.container.read(weeklyGridProvider).days[3];
    grid.setSquareStateOnly('inbox_zero', day, SquareState.complete);
    await h.settle(tester);

    await tester.ensureVisible(square(day));
    await h.settle(tester);
    await tester.tap(square(day));
    await h.settle(tester);

    expect(find.text(ar.gridClearPastMarkTitle), findsOneWidget,
        reason: 'the past-day dialog did not open');
    expect(
      find.text(ar.gridClearPastMarkBody(name, plainDate(day))),
      findsOneWidget,
    );

    // Leaves the mark where it was.
    await tester.tap(find.text(ar.habitActionsCancel));
    await h.settle(tester);
    expect(h.container.read(weeklyGridProvider).squareFor('inbox_zero', day),
        SquareState.complete);
    await tester.pump(const Duration(milliseconds: 1));
  });
}
