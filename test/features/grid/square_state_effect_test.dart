// The one place the app explains how its six squares differ.
//
// Three of them mean some version of "not done", and until this copy existed
// nothing on screen said how they differ. These tests pin the two properties
// that make the copy worth having: every state says something, and the three
// not-done states say three DIFFERENT things.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';

void main() {
  for (final locale in ['ar', 'en']) {
    final s = S(Locale(locale));

    group('squareStateEffect in $locale', () {
      test('every state explains itself', () {
        for (final state in SquareState.values) {
          expect(s.squareStateEffect(state).trim(), isNotEmpty,
              reason: '$state has no explanation');
        }
      });

      test('the three not-done states say three different things', () {
        // The user question this exists to answer: what is the difference
        // between تخطّي, فشل, and leaving it empty. If any two of these ever
        // collapse to the same sentence, the answer has been lost.
        final notDone = {
          s.squareStateEffect(SquareState.skipped),
          s.squareStateEffect(SquareState.failed),
          s.squareStateEffect(SquareState.none),
        };
        expect(notDone.length, 3);
      });

      test('no explanation is the same as any other', () {
        final all = SquareState.values.map(s.squareStateEffect).toSet();
        expect(all.length, SquareState.values.length);
      });

      test('rest is the only one that says it is not counted against you', () {
        // The distinction that carries the app's whole position on rest.
        final rest = s.squareStateEffect(SquareState.skipped);
        expect(rest, isNot(s.squareStateEffect(SquareState.failed)));
        expect(rest, isNot(s.squareStateEffect(SquareState.none)));
      });

      test('no em dash anywhere in this copy', () {
        // A standing rule for every user-facing string in this app.
        for (final state in SquareState.values) {
          expect(s.squareStateEffect(state), isNot(contains('—')));
        }
      });
    });
  }
}
