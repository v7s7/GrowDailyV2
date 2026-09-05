// The tasbih glyph belongs to people who are actually doing dhikr.
//
// It used to hold a permanent slot in the Grid header for everybody, which
// cost a slot to every person who does not use a misbaha. It is now keyed to
// the board: an athkar-category habit is the honest test for "this person
// would use one".
//
// Deliberately not a setting. A toggle has to default to something and both
// answers are worse: default on changes nothing for the people it was meant
// to spare, default off makes the feature invisible to everyone who would
// have wanted it, including the people already using it.
//
// Harness built in setUp, never inside a test body — see LandingHarness,
// whose own doc says "call from setUp". Building one per test body hangs the
// run rather than failing it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/landing_harness.dart';

void main() {
  late LandingHarness h;
  tearDown(() => h.dispose());

  group('a board that does dhikr', () {
    setUp(() async {
      h = LandingHarness();
      await h.prepare(
        activeCatalogIds: const ['inbox_zero', 'morning_athkar'],
      );
    });

    testWidgets('gets the tasbih shortcut', (tester) async {
      await h.pumpApp(tester);
      expect(find.byTooltip('Tasbih'), findsWidgets);
    });
  });

  group('a board that does not', () {
    setUp(() async {
      h = LandingHarness();
      await h.prepare(
        activeCatalogIds: const ['inbox_zero', 'quran_daily_page'],
      );
    });

    testWidgets('never sees it', (tester) async {
      // quran_daily_page is its own category, not athkar. Widening the rule
      // to "anything religious" would put the glyph back in most people's
      // header, which is the thing this removed.
      await h.pumpApp(tester);
      expect(find.byTooltip('Tasbih'), findsNothing);
    });

    testWidgets('keeps every unconditional control', (tester) async {
      // The overflow menu especially: it is the only route to multi-select
      // and reorder in the whole app, and it must never become conditional
      // by accident.
      await h.pumpApp(tester);
      expect(find.byTooltip('Night Review'), findsWidgets);
      expect(find.byTooltip('List actions'), findsWidgets);
    });
  });
}
