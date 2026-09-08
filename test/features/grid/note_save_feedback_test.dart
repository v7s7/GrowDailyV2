// Saving a reflection used to be the quietest write on the Grid.
//
// One light haptic and a pop, while CLEARING a mark got a six-second bar with
// an Undo. The app was louder about a checkbox than about a paragraph someone
// had written, the persist was `.ignore()`d so a failed write looked exactly
// like a good one, and emptying a note was silent, unconfirmed and
// unrecoverable.
//
// These cover the feedback itself and the thing underneath it that makes the
// feedback honest: an emptied note DELETES its key rather than leaving a ''
// tombstone behind, which is what any presence check (the note index, the
// corner mark) would otherwise keep reading as writing forever.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/services/local_store_service.dart';
import 'package:grow_daily_v2/features/grid/notifiers/weekly_grid_notifier.dart';

import '../../helpers/landing_harness.dart';

void main() {
  const s = S(Locale('en'));

  group('the cell editor says what it did', () {
    late LandingHarness h;

    setUp(() async {
      h = LandingHarness();
      await h.prepare(activeCatalogIds: const ['inbox_zero']);
      // Hive boxes are process-wide and LandingHarness.dispose deliberately
      // does not close them, so a note written by one test is still in the
      // box when the next one loads its week.
      (await LocalStoreService.dailyBox()).clear();
    });
    tearDown(() => h.dispose());

    /// The label is the habit's localized name then the date, which is the
    /// only stable public handle on a private widget (the same one
    /// grid_square_alignment_test uses). Anchored on TODAY specifically: a
    /// future day's square has no long-press at all.
    Finder todaySquare() {
      final date =
          DateFormat('EEEE d MMMM', 'en').format(DateTime.now().effectiveDay);
      return find
          .bySemanticsLabel(RegExp('^Inbox Zero, ${RegExp.escape(date)}'));
    }

    Future<void> openEditor(WidgetTester tester) async {
      await h.pumpApp(tester);
      // The board sits under a summary card and can start off screen.
      await tester.ensureVisible(todaySquare());
      await h.settle(tester);
      await tester.longPress(todaySquare());
      await h.settle(tester);
      expect(find.text(s.gridSave), findsOneWidget,
          reason: 'the long-press editor did not open, so nothing after this '
              'is testing anything');
    }

    testWidgets('saving a note confirms it', (tester) async {
      await openEditor(tester);
      await tester.enterText(find.byType(TextField), 'cleared it, felt light');
      await tester.tap(find.text(s.gridSave));
      await h.settle(tester);

      expect(find.text(s.gridNoteSaved), findsOneWidget);
      // No Undo, because nothing was taken away, and a short duration because
      // there is nothing to reach for.
      final bar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(bar.action, isNull);
      expect(bar.duration, const Duration(seconds: 3));
    });

    testWidgets('an unchanged note says nothing at all', (tester) async {
      // Opening the sheet and tapping Save without touching the text is not
      // an event, and a bar for it would train people to ignore the bars that
      // matter.
      await openEditor(tester);
      await tester.tap(find.text(s.gridSave));
      await h.settle(tester);

      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('emptying a note offers it back', (tester) async {
      final today = DateTime.now().effectiveDay;
      await openEditor(tester);
      await tester.enterText(
          find.byType(TextField), 'a sentence worth keeping');
      await tester.tap(find.text(s.gridSave));
      await h.settle(tester);

      await tester.longPress(todaySquare());
      await h.settle(tester);
      await tester.enterText(find.byType(TextField), '');
      await tester.tap(find.text(s.gridSave));
      await h.settle(tester);

      expect(find.text(s.gridNoteCleared), findsOneWidget);
      final bar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(bar.action?.label, s.undo,
          reason: 'a clear is the only one of the three bars that took words '
              'away, so it is the only one that must be reversible');
      expect(bar.duration, const Duration(seconds: 6));
      // Flutter 3.41 defaults `persist` to `action != null`, which pins a bar
      // to the bottom of the screen for the rest of the session and rides it
      // over every screen opened next. See AppSnackBar.
      expect(bar.persist, isFalse);

      expect(h.container.read(weeklyGridProvider).noteFor('inbox_zero', today),
          isEmpty);

      await tester.tap(find.text(s.undo));
      await h.settle(tester);
      expect(h.container.read(weeklyGridProvider).noteFor('inbox_zero', today),
          'a sentence worth keeping');
    });

    testWidgets('the editor offers a way to all the notes', (tester) async {
      // The highest-intent moment in the product: someone is looking at a
      // note while thinking about their notes.
      await openEditor(tester);
      expect(find.text(s.gridNoteSeeAll), findsOneWidget);
    });
  });
}
