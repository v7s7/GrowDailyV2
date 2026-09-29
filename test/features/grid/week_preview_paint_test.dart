// The week as this device last saw it, drawn while the server read is on its
// way (WeeklyGridState.preview).
//
// A cold start used to show a spinner in a card where the board goes, then a
// day card reading 0%, then the real numbers: the length of a server round
// trip, every launch. The device already had the week (Firestore keeps its
// own copy), so the board now paints from that at once.
//
// The rule that makes it safe is the one HabitMirror keeps for the habit
// list: painting early is harmless, deciding from it is not. The copy can be
// behind the server (a square marked on the web), so these pin that nothing
// which decides (a streak, a reward, a reminder, a room) can see it, and that
// what the board draws is the copy with anything written since laid over it.
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/grid/notifiers/weekly_grid_notifier.dart';

void main() {
  final today = DateTime.now().effectiveDay;
  final todayKey = today.toDateKey();
  final week = startOfGridWeek(DateTime.now());

  WeeklyGridState loading({
    Map<String, Map<String, SquareState>> states = const {},
    bool withPreview = true,
  }) =>
      WeeklyGridState(
        weekStart: week,
        states: states,
        notes: const {},
        isLoading: true,
        preview: withPreview
            ? (
                states: {
                  todayKey: {
                    'fajr': SquareState.complete,
                    'quran': SquareState.partial,
                  },
                },
                notes: {
                  todayKey: {'fajr': 'in the mosque'},
                },
              )
            : null,
      );

  group('what the board draws', () {
    test('while loading, the device copy of the week', () {
      final paint = loading().forPaint;
      expect(paint.squareFor('fajr', today), SquareState.complete);
      expect(paint.squareFor('quran', today), SquareState.partial);
      expect(paint.noteFor('fajr', today), 'in the mosque');
    });

    test('still loading, so the day card does not treat it as live', () {
      // The sprout greets and a perfect day celebrates only once the week
      // is really read (see _SummaryCard's `live`).
      expect(loading().forPaint.isLoading, isTrue);
    });

    test('anything written while loading is drawn over the copy', () {
      // A notification's Mark Done can land before the week does. The copy
      // says the habit was empty; the write says done, and the write wins.
      final paint = loading(states: {
        todayKey: {'quran': SquareState.complete},
      }).forPaint;
      expect(paint.squareFor('quran', today), SquareState.complete);
      expect(paint.squareFor('fajr', today), SquareState.complete);
    });

    test('once loaded, the week itself and nothing else', () {
      final loaded = loading().copyWith(
        states: {
          todayKey: {'fajr': SquareState.failed},
        },
        isLoading: false,
        dropPreview: true,
      );
      expect(identical(loaded.forPaint, loaded), isTrue);
      expect(loaded.squareFor('fajr', today), SquareState.failed);
      expect(loaded.squareFor('quran', today), SquareState.none,
          reason: 'the server answer replaces the copy, it is not merged');
    });

    test('a loaded state ignores a preview that was left on it', () {
      final loaded = loading().copyWith(isLoading: false);
      expect(identical(loaded.forPaint, loaded), isTrue);
      expect(loaded.forPaint.squareFor('fajr', today), SquareState.none);
    });
  });

  group('whether there is a board to draw', () {
    test('loading with nothing on the device: the skeleton, as before', () {
      expect(loading(withPreview: false).canPaint, isFalse);
    });

    test('loading with the device copy: the board', () {
      expect(loading().canPaint, isTrue);
    });

    test('loaded: the board', () {
      expect(loading().copyWith(isLoading: false).canPaint, isTrue);
    });
  });

  group('nothing that decides can see the copy', () {
    final state = loading();

    test('the squares themselves read as not yet known', () {
      expect(state.squareFor('fajr', today), SquareState.none);
      expect(state.states, isEmpty);
    });

    test('a quota cannot count a session from it', () {
      expect(state.currentWeekGreen, isNull);
      expect(state.currentWeekMark, isNull);
    });

    test('today has no known row, so reminders and the widget wait', () {
      expect(state.knownTodayRow, isNull);
      expect(state.halfDoneTodayIds(), isEmpty);
      expect(state.skippedTodayIds(), isEmpty);
    });

    test('no reward or ratio is priced from it', () {
      expect(state.rewardEligiblePoints(['fajr', 'quran']), 0);
      expect(state.todayCompletionRatio(['fajr', 'quran']), 0);
      expect(state.greenSquares(['fajr', 'quran']), 0);
    });
  });

  group('carrying it', () {
    test('a write while loading keeps the copy', () {
      final written = loading().copyWith(states: {
        todayKey: {'quran': SquareState.complete},
      });
      expect(written.preview, isNotNull);
    });

    test('dropPreview clears it', () {
      expect(loading().copyWith(dropPreview: true).preview, isNull);
    });
  });
}
