// The Grid is the app, and to a screen reader it was nothing.
//
// Every square announced itself as an unlabelled button: no habit, no date,
// no state, and no way to tell a completed day from an empty one or from a
// locked future day. Colour IS the information here, so a blind user got none
// of it — the central feature was unusable rather than merely awkward.
//
// _SquareCell now takes a prebuilt label (the caller is the only place that
// knows the habit's name and the language). These cover the piece that
// label is assembled from, which is where a regression would actually land:
// a new SquareState added without a spoken name would announce as nothing at
// all, silently, and only for people who can't see the colour.
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/features/grid/models/square_state.dart';

void main() {
  group('every square state can be said out loud', () {
    test('all six have a label, in both languages', () {
      for (final state in SquareState.values) {
        for (final isAr in [true, false]) {
          expect(state.localLabel(isAr).trim(), isNotEmpty,
              reason: '$state has no spoken label (isAr=$isAr)');
        }
      }
    });

    test('Arabic and English are actually different', () {
      // Catches a copy-paste leaving one language reading the other's text.
      for (final state in SquareState.values) {
        expect(state.localLabel(true), isNot(state.localLabel(false)),
            reason: '$state reads identically in both languages');
      }
    });

    test('each state sounds different from the others', () {
      // The whole point is telling them apart by ear. Two states sharing a
      // word would make "done" and "missed" indistinguishable.
      for (final isAr in [true, false]) {
        final spoken = SquareState.values.map((s) => s.localLabel(isAr));
        expect(spoken.toSet(), hasLength(SquareState.values.length),
            reason: 'two states share a spoken label (isAr=$isAr)');
      }
    });

    test('the states a tap cycles through are all distinguishable', () {
      // white -> yellow -> green is the core interaction; if these three
      // sound alike, tapping gives no feedback a blind user can use.
      final cycle = SquareState.tapCycle.map((s) => s.localLabel(false));
      expect(cycle.toSet(), hasLength(SquareState.tapCycle.length));
    });

    test('a done square does not announce as empty', () {
      // The single most important distinction on the screen.
      expect(SquareState.complete.localLabel(false),
          isNot(SquareState.none.localLabel(false)));
      expect(SquareState.complete.localLabel(true),
          isNot(SquareState.none.localLabel(true)));
    });
  });
}
