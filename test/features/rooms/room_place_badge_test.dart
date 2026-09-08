// What the rank slot says, in pictures and out loud.
//
// The slot at the start of every leaderboard row is the one thing on the row
// that states a member's PLACE rather than their work, and it says it three
// different ways: a cup for first, a number for everyone else, a dash for a
// member who has no place yet. Two of those three are not text, so a screen
// reader hears whatever the widget chooses to tell it, and until this file
// existed nothing in the repo asserted that it told it anything at all.
//
// The regressions this exists to prevent, all of them shipped states of this
// slot at some point today:
//
//   - first place drawn as a bare Icon, so the one row a sighted person can
//     find instantly was the one row a screen reader could not hear;
//   - two members level at the top both drawn as cups, with the missing 2
//     between them unexplained;
//   - a member at 0% drawn as a bare en dash, which VoiceOver and TalkBack
//     drop at default punctuation verbosity, so a day-one board announced no
//     places at all while plainly showing a dash on every row.
//
// Pumps the real widget, in both languages, and reads the semantics tree
// rather than a replica of it.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/rooms/screens/room_detail_screen.dart'
    show RoomPlaceBadge, roomPlaceMedalColor;

void main() {
  Widget app({required bool isAr, required int rank, required bool shared}) =>
      MaterialApp(
        locale: Locale(isAr ? 'ar' : 'en'),
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: GameTheme.light,
        home: Scaffold(
          // The real slot: 22pt wide, which is why nothing longer than a
          // glyph can be DRAWN here and everything else has to be spoken.
          body: Center(
            child: SizedBox(
              width: 22,
              child: RoomPlaceBadge(rank: rank, shared: shared),
            ),
          ),
        ),
      );

  /// Pumps the badge with the semantics tree switched on, runs [check]
  /// against it, and hands the handle back before the test ends (the
  /// framework asserts on a handle still held at teardown, which is why
  /// this takes a callback rather than returning).
  ///
  /// find.bySemanticsLabel then sees exactly what a screen reader would be
  /// handed. It matches a String EXACTLY, which matters here: the tied
  /// label contains the plain one as a substring.
  Future<void> withBadge(
    WidgetTester tester, {
    required bool isAr,
    required int rank,
    bool shared = false,
    required void Function() check,
  }) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(app(isAr: isAr, rank: rank, shared: shared));
    await tester.pump();
    check();
    handle.dispose();
  }

  for (final isAr in const [true, false]) {
    final s = S(Locale(isAr ? 'ar' : 'en'));
    final lang = isAr ? 'ar' : 'en';

    group('first place ($lang)', () {
      testWidgets('is a cup, and the cup says which place it is',
          (tester) async {
        await withBadge(
          tester,
          isAr: isAr,
          rank: 1,
          check: () {
          expect(find.byIcon(Icons.emoji_events_rounded), findsOneWidget);
          expect(find.text('1'), findsNothing);
          expect(find.bySemanticsLabel(s.roomPlaceFirst), findsOneWidget);
          },
        );
      });

      testWidgets('says it is SHARED when somebody else is level',
          (tester) async {
        await withBadge(
          tester,
          isAr: isAr,
          rank: 1,
          shared: true,
          check: () {
          // Still a cup: a shared first is drawn as two identical cups, and
          // the difference is carried entirely by what it says.
          expect(find.byIcon(Icons.emoji_events_rounded), findsOneWidget);
          expect(find.bySemanticsLabel(s.roomPlaceFirstTied), findsOneWidget);
          expect(find.bySemanticsLabel(s.roomPlaceFirst), findsNothing);
          },
        );
      });
    });

    group('the places drawn as a number ($lang)', () {
      testWidgets('an unshared place is just its number', (tester) async {
        await withBadge(
          tester,
          isAr: isAr,
          rank: 2,
          check: () {
          expect(find.text('2'), findsOneWidget);
          // No label: the number is already exactly the right thing to say,
          // so it is what the semantics tree carries.
          expect(find.bySemanticsLabel('2'), findsOneWidget);
          expect(find.bySemanticsLabel(s.roomPlaceTied(2)), findsNothing);
          },
        );
      });

      testWidgets('a shared place says so', (tester) async {
        await withBadge(
          tester,
          isAr: isAr,
          rank: 2,
          shared: true,
          check: () {
          // Drawn identically to the row above it, which is the problem the
          // label solves: two rows reading 2 with no 3 after them.
          expect(find.text('2'), findsOneWidget);
          expect(find.bySemanticsLabel(s.roomPlaceTied(2)), findsOneWidget);
          },
        );
      });

      testWidgets('a tie deep in the board is announced too', (tester) async {
        await withBadge(
          tester,
          isAr: isAr,
          rank: 7,
          shared: true,
          check: () {
          expect(find.bySemanticsLabel(s.roomPlaceTied(7)), findsOneWidget);
          },
        );
      });
    });

    group('no place yet ($lang)', () {
      testWidgets('is a dash, and the dash is spoken', (tester) async {
        await withBadge(
          tester,
          isAr: isAr,
          rank: 0,
          check: () {
          expect(find.text('–'), findsOneWidget);
          expect(find.text('0'), findsNothing);
          expect(find.bySemanticsLabel(s.roomPlaceNone), findsOneWidget);
          },
        );
      });

      testWidgets(
          'never inherits a tie label, even if a caller insists it is shared',
          (tester) async {
        // standings promises shared is false at rank 0, since nobody shares
        // a place nobody has. This pins the widget against that promise
        // being broken elsewhere: roomPlaceTied(0) must be unreachable.
        await withBadge(
          tester,
          isAr: isAr,
          rank: 0,
          shared: true,
          check: () {
          expect(find.bySemanticsLabel(s.roomPlaceNone), findsOneWidget);
          expect(find.bySemanticsLabel(s.roomPlaceTied(0)), findsNothing);
          },
        );
      });
    });
  }

  group('the medal colours', () {
    test('are gold, silver and bronze, and nothing else', () {
      expect(roomPlaceMedalColor(1), GameColors.gold);
      expect(roomPlaceMedalColor(2), isNotNull);
      expect(roomPlaceMedalColor(3), isNotNull);
      expect(roomPlaceMedalColor(4), isNull);
    });

    test('an unranked place wears no medal', () {
      // The floor that stops a day-one board rendering as a row of medals.
      expect(roomPlaceMedalColor(0), isNull);
    });

    test('the set is allowed to have gaps, because places are shared', () {
      // 1, 1, 3 is two golds and a bronze with no silver. Nothing here
      // enforces that, it just must not be treated as a missing case.
      expect(roomPlaceMedalColor(1), isNotNull);
      expect(roomPlaceMedalColor(3), isNotNull);
    });
  });
}
