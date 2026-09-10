// The gold ring on today's square is an ASK, not a date stamp.
//
// Aziz, 2026-09-09, looking at his own Grid: "the habits that I don't need to
// do today, the square should not be outlined... make it clear that no need
// for today, and at the same time it does not feel like the user is missing
// days, because he doesn't have to do it."
//
// Every habit used to wear the ring on today's column, so a Monday/Thursday
// fast wore it on a Wednesday. A ring around an empty square reads as a task
// still outstanding, which turned a finished day into a column of apparent
// chores. covered_day_test.dart pins the RULE (showsTodayRing); this pins the
// WIRING - that the rule is what actually reaches the border, through the
// real GridScreen.
//
// Not date-fragile: the two catalog habits used here run on Monday/Thursday
// and on Friday, and no day is all three, so whatever weekday the suite runs
// on, at least one of them is off today. The test picks that one.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';

import '../../helpers/landing_harness.dart';

void main() {
  late LandingHarness h;

  // Mon/Thu fast, Friday check-in, and one plainly daily habit as the control.
  const monThu = 'Monday & Thursday Fast';
  const friday = 'Weekly Marriage Check-in';
  const daily = 'Quran Daily Page';

  setUp(() async {
    h = LandingHarness();
    await h.prepare(activeCatalogIds: const [
      'sunnah_fasting',
      'marriage_checkin',
      'quran_daily_page',
    ]);
  });

  tearDown(() => h.dispose());

  /// The border colour of [habitName]'s square for TODAY.
  ///
  /// Found by the square's own semantic label, which _GridTable builds as
  /// "<habit>, <EEEE d MMMM>, <state>" - the only stable handle on a private
  /// widget, and the same approach grid_square_alignment_test.dart uses.
  /// Addressed by date rather than by position, because the week view also
  /// renders the days AHEAD of today (see Aziz's own screenshot: Thursday and
  /// Friday sit past Wednesday), so the last square in a row is a future one.
  Color? todayBorder(WidgetTester tester, String habitName) {
    final label = DateFormat('EEEE d MMMM', 'en').format(DateTime.now());
    final square = find.bySemanticsLabel(
      RegExp('^${RegExp.escape(habitName)}, ${RegExp.escape(label)},'),
    );
    final found = square.evaluate();
    if (found.isEmpty) return null;
    final container = find
        .descendant(
          of: find.byWidget(found.first.widget),
          matching: find.byType(AnimatedContainer),
        )
        .evaluate();
    if (container.isEmpty) return null;
    final decoration = (container.first.widget as AnimatedContainer).decoration;
    final border = decoration is BoxDecoration ? decoration.border : null;
    return border is Border ? border.top.color : null;
  }

  testWidgets('a habit today asks nothing of is not outlined, and a daily one is',
      (tester) async {
    await h.pumpApp(tester);

    final weekday = DateTime.now().weekday;
    final offToday = weekday == DateTime.friday ? monThu : friday;
    final reason = weekday == DateTime.friday
        ? 'Mon/Thu fast is off on a Friday'
        : 'the Friday check-in is off on any other day';

    expect(todayBorder(tester, daily), GameColors.goldDim,
        reason: 'a daily habit is owed today, so today stays circled');
    expect(todayBorder(tester, offToday), isNot(GameColors.goldDim),
        reason: '$reason, so its today square must not wear the ask ring');
  });

  testWidgets('the habit that DOES run today is outlined', (tester) async {
    await h.pumpApp(tester);

    final weekday = DateTime.now().weekday;
    // Only assert the positive case on a day one of them genuinely runs.
    final onToday = weekday == DateTime.friday
        ? friday
        : (weekday == DateTime.monday || weekday == DateTime.thursday)
            ? monThu
            : null;
    if (onToday == null) return; // nothing scheduled today; nothing to assert

    expect(todayBorder(tester, onToday), GameColors.goldDim,
        reason: 'a scheduled, unfinished habit still asks for today');
  });
}
