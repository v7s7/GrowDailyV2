import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/grid/notifiers/square_audit.dart';

/// Which square changes leave a trail.
///
/// The trail exists because a stored square records the VALUE and never the
/// writer. On 2026-09-10 noor's walking habit was completed at 15:38, paid
/// 20 XP and 8 gold, then reversed, and the day document's `lastUpdated`
/// (01:42 the next morning) was the only clue about when. Nothing in the
/// account could say by what, which made "the previous day resets after
/// 00:00" unanswerable from data.
///
/// Only LOSSES are recorded. Every square in the app is written through one
/// choke point, so recording all of them would put a document behind every
/// tap for no gain: nobody has ever asked why a square turned green.
void main() {
  group('squareChangeLosesCredit', () {
    test('a cleared green day is recorded', () {
      expect(
        squareChangeLosesCredit(SquareState.complete, SquareState.none),
        isTrue,
      );
    });

    test('a green day turned red is recorded', () {
      // Whatever the intent, the day lost its credit, and that is the event
      // worth being able to attribute later.
      expect(
        squareChangeLosesCredit(SquareState.complete, SquareState.failed),
        isTrue,
      );
    });

    test('a green day stood down is recorded', () {
      expect(
        squareChangeLosesCredit(SquareState.complete, SquareState.skipped),
        isTrue,
      );
    });

    test('a green day dropped to جزئي is recorded', () {
      expect(
        squareChangeLosesCredit(SquareState.complete, SquareState.partial),
        isTrue,
      );
    });

    test('a cleared جزئي is recorded', () {
      expect(
        squareChangeLosesCredit(SquareState.partial, SquareState.none),
        isTrue,
      );
    });

    test('earning a square is NOT recorded', () {
      expect(
        squareChangeLosesCredit(SquareState.none, SquareState.complete),
        isFalse,
      );
      expect(
        squareChangeLosesCredit(SquareState.none, SquareState.partial),
        isFalse,
      );
      expect(
        squareChangeLosesCredit(SquareState.partial, SquareState.complete),
        isFalse,
      );
      expect(
        squareChangeLosesCredit(SquareState.complete, SquareState.bonus),
        isFalse,
      );
    });

    test('a change that costs nothing is NOT recorded', () {
      // فشل to تخطّي is a person changing how they describe a day that paid
      // nothing either way. It is not a loss and the trail stays quiet.
      expect(
        squareChangeLosesCredit(SquareState.failed, SquareState.skipped),
        isFalse,
      );
      expect(
        squareChangeLosesCredit(SquareState.none, SquareState.failed),
        isFalse,
      );
    });

    test('no change is not a change', () {
      for (final s in SquareState.values) {
        expect(squareChangeLosesCredit(s, s), isFalse, reason: s.name);
      }
    });

    test('the blue square counts as a whole day, like the green one', () {
      // Otherwise إنجاز إضافي → أخضر would read as a loss and fill the trail
      // with noise on the one transition that is unambiguously fine.
      expect(squareCredit(SquareState.bonus), squareCredit(SquareState.complete));
    });
  });
}
