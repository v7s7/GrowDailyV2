// The board while its week is still on its way from the server.
//
// A cold start used to put a spinner in a card where the board goes, for
// the length of a server round trip. The board now draws the week as this
// device last saw it (WeeklyGridState.preview) and takes no taps until the
// real week lands, because a tap prices its XP and streak from the square as
// the store has it and the device's copy can be behind. A tap in that moment
// says so rather than doing nothing (see _BoardUntilLoaded).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/grid/notifiers/weekly_grid_notifier.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';

import '../../helpers/landing_harness.dart';

/// A grid whose state is whatever the test pinned: the load the real
/// notifier starts would otherwise replace it the moment it resolves.
class _PinnedGrid extends WeeklyGridNotifier {
  _PinnedGrid(Ref ref, this.pinned) : super(null, ref) {
    super.state = pinned;
  }

  final WeeklyGridState pinned;

  @override
  set state(WeeklyGridState value) => super.state = pinned;
}

void main() {
  final today = DateTime.now().effectiveDay;
  final en = S(const Locale('en'));
  late LandingHarness h;

  WeeklyGridState loading({required bool withPreview}) => WeeklyGridState(
        weekStart: startOfGridWeek(DateTime.now()),
        states: const {},
        notes: const {},
        isLoading: true,
        preview: withPreview
            ? (
                states: {
                  today.toDateKey(): {'inbox_zero': SquareState.complete},
                },
                notes: const {},
              )
            : null,
      );

  /// Opens the boxes in setUp, in the real zone: prepare() does real disk
  /// work, which never finishes inside a testWidgets body's fake-async zone
  /// (see LandingHarness).
  void boardWith(WeeklyGridState Function() pinned) {
    setUp(() async {
      h = LandingHarness();
      await h.prepare(
        activeCatalogIds: const ['inbox_zero'],
        extraOverrides: [
          weeklyGridProvider.overrideWith((ref) => _PinnedGrid(ref, pinned())),
        ],
      );
    });
    tearDown(() => h.dispose());
  }

  Finder todaySquare(String state) {
    final name = h.container.read(habitListProvider).single.localName(false);
    return find.bySemanticsLabel(RegExp(
      '^${RegExp.escape('$name, '
          '${DateFormat('EEEE d MMMM', 'en').format(today)}, $state')}',
    ));
  }

  group('with the week on the device', () {
    boardWith(() => loading(withPreview: true));

    testWidgets('it is on the board, not a spinner', (tester) async {
      await h.pumpApp(tester);
      expect(
        todaySquare(SquareState.complete.localLabel(false)),
        findsOneWidget,
      );
    });

    testWidgets('a tap before the week lands says so and changes nothing',
        (tester) async {
      await h.pumpApp(tester);
      await tester.tap(todaySquare(SquareState.complete.localLabel(false)));
      await tester.pump();
      expect(find.text(en.squareNotReadyYet), findsOneWidget);
      // No confirm-to-clear dialog opened over a square the store has not
      // answered for yet, and nothing was written.
      expect(find.byType(AlertDialog), findsNothing);
      expect(h.container.read(weeklyGridProvider).states, isEmpty);
      await h.settle(tester);
    });
  });

  group('with nothing of the week on the device', () {
    boardWith(() => loading(withPreview: false));

    testWidgets('the skeleton, as before', (tester) async {
      // Frames, not a settle: the skeleton's spinner never settles.
      await tester.pumpWidget(h.app());
      await tester.pump(const Duration(milliseconds: 500));
      expect(todaySquare(''), findsNothing);
      expect(
        find.byWidgetPredicate(
          (w) => w is CircularProgressIndicator && w.value == null,
        ),
        findsOneWidget,
      );
      // Let the screen's own timers run out before the tree goes.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 30));
    });
  });
}
