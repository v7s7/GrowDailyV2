// Crossing a rank.
//
// Two separate things are locked here.
//
// THE TRIGGER. A tier is unlocked purely by level (PrestigeCatalog.unlockedFor)
// so "did the ladder move" is a pure function of the level before and after,
// and needs no persisted state of its own. That is only true if the catalog
// and the mark table stay keyed the same way, so this also asserts every tier
// in one has a mark in the other.
//
// THE MOMENT. It animates the ladder's own ordering channels and invents
// nothing: the mark is on screen at the OLD rank from the first frame and
// opens into the new one. And it does not glow. That last one is not taste:
// this ladder renamed three tiers to move away from light imagery, so a halo
// behind the mark would undo in pixels what the names were changed to avoid.
//
// REDUCE MOTION, on both platforms. Two flags carry it and only one reaches
// MediaQuery (see prefersReducedMotion): Android's animator setting arrives as
// MediaQuery.disableAnimations, while iOS's Settings > Accessibility > Motion
// switch arrives only as accessibilityFeatures.reduceMotion, with MediaQuery
// still saying false. The iOS cases set that flag alone, so they go red if
// this moment ever goes back to asking MediaQuery.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/character/models/prestige_tier.dart';
import 'package:grow_daily_v2/features/character/widgets/prestige_mark.dart';
import 'package:grow_daily_v2/features/character/widgets/rank_up_celebration.dart';

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('the trigger', () {
    test('every catalog tier has a mark, and every mark has a tier', () {
      for (final t in PrestigeCatalog.tiers) {
        expect(prestigeMarkFor(t), isNotNull,
            reason: '${t.id} has no mark, so its unlock cannot be drawn');
      }
      expect(kPrestigeMarks.length, PrestigeCatalog.tiers.length);
    });

    test('a crossing is exactly a change of highest unlocked tier', () {
      final thresholds = PrestigeCatalog.tiers.map((t) => t.minLevel).toList();
      // Seeker is minLevel 1 and every account starts there, so it is never
      // crossed INTO. Eight moments exist in a lifetime, not nine.
      final crossings = <int>[];
      for (var level = 2; level <= 100; level++) {
        final was = PrestigeCatalog.highestFor(level - 1);
        final now = PrestigeCatalog.highestFor(level);
        if (was.id != now.id) crossings.add(level);
      }
      expect(crossings, thresholds.where((l) => l > 1).toList());
      expect(crossings.length, 8);
    });

    test('an ordinary level up is not a crossing', () {
      // 21 through 34 sit between Steadfast (20) and Accomplished (35).
      for (var level = 21; level < 35; level++) {
        expect(
          PrestigeCatalog.highestFor(level - 1).id,
          PrestigeCatalog.highestFor(level).id,
          reason: 'level $level fired a rank moment it should not have',
        );
      }
    });

    test('a multi rung jump still resolves to one moment', () {
      // A single completion can carry enough XP to cross two thresholds.
      final was = PrestigeCatalog.highestFor(4);
      final now = PrestigeCatalog.highestFor(12);
      expect(was.id, 'seeker');
      expect(now.id, 'steadfast');
      expect(prestigeMarkFor(now)!.rank - prestigeMarkFor(was)!.rank, 2,
          reason: 'the animation has to travel two rungs, not one');
    });
  });

  group('the moment', () {
    /// iOS's Reduce Motion, as the phone reports it: the accessibility
    /// feature on, and MediaQuery.disableAnimations left false, because that
    /// field is fed by Android's animator setting only.
    void iosReduceMotion(WidgetTester tester) {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(reduceMotion: true);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    }

    /// Pumps the celebration for a crossing into [toIndex] and returns the
    /// tester, without settling: the whole point is what it looks like partway.
    ///
    /// [disableAnimations] is Android's flag, set on MediaQuery; [ios] is
    /// iOS's Reduce Motion, set on the platform (see [iosReduceMotion]).
    Future<void> pumpCrossing(
      WidgetTester tester,
      int fromIndex,
      int toIndex, {
      bool disableAnimations = false,
      bool ios = false,
      Locale locale = const Locale('ar'),
    }) async {
      if (ios) iosReduceMotion(tester);
      final from = PrestigeCatalog.tiers[fromIndex];
      final to = PrestigeCatalog.tiers[toIndex];
      await tester.pumpWidget(MaterialApp(
        locale: locale,
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: GameTheme.dark,
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: Scaffold(
            body: RankUpCelebration(
              from: prestigeMarkFor(from)!,
              to: prestigeMarkFor(to)!,
              tier: to,
            ),
          ),
        ),
      ));
      await tester.pump();
    }

    PrestigeMarkSpec renderedSpec(WidgetTester tester) =>
        tester.widget<PrestigeMark>(find.byType(PrestigeMark).first).spec;

    testWidgets('opens on the mark the person already had', (tester) async {
      await pumpCrossing(tester, 3, 4); // Persistent into Steadfast
      final shown = renderedSpec(tester);
      final old = prestigeMarkFor(PrestigeCatalog.tiers[3])!;
      expect(shown.outerSweep, old.outerSweep);
      expect(shown.innerSweep, old.innerSweep,
          reason: 'nothing may appear out of nowhere: the thing being '
              'celebrated has to be visibly the thing they already had');
      // The assertion is about the FIRST frame, but the staggered text
      // entrances below the mark are still scheduled, so drain them before
      // the tree comes down.
      await tester.pumpAndSettle();
    });

    testWidgets('lands on the new mark, exactly', (tester) async {
      await pumpCrossing(tester, 3, 4);
      await tester.pumpAndSettle();
      final shown = renderedSpec(tester);
      final want = prestigeMarkFor(PrestigeCatalog.tiers[4])!;
      expect(shown.outerSweep, closeTo(want.outerSweep, 0.001));
      expect(shown.innerSweep, closeTo(want.innerSweep, 0.001));
      expect(shown.outerStroke, closeTo(want.outerStroke, 0.001));
      expect(shown.innerStroke, closeTo(want.innerStroke, 0.001));
      expect(shown.rank, want.rank);
    });

    testWidgets('the ink only ever grows on the way there', (tester) async {
      await pumpCrossing(tester, 0, 2); // a two rung jump
      var last = -1.0;
      for (var i = 0; i < 24; i++) {
        final now = prestigeMarkInkCoverage(renderedSpec(tester));
        expect(now, greaterThanOrEqualTo(last - 0.0001),
            reason: 'a promotion that visibly loses ink partway reads as a '
                'glitch, which is why the two sweeps run in sequence');
        last = now;
        await tester.pump(const Duration(milliseconds: 40));
      }
      await tester.pumpAndSettle();
    });

    testWidgets('nothing glows behind the mark', (tester) async {
      await pumpCrossing(tester, 7, 8); // into the summit, the loudest moment
      await tester.pumpAndSettle();
      // Every Container in the moment, checked for the two ways a halo gets
      // in: a BoxShadow, or a radial gradient.
      for (final c in tester.widgetList<Container>(find.byType(Container))) {
        final d = c.decoration;
        if (d is BoxDecoration) {
          expect(d.boxShadow, anyOf(isNull, isEmpty),
              reason: 'this ladder renamed three tiers to move away from '
                  'light imagery; a glow puts it straight back');
          expect(d.gradient, isNot(isA<RadialGradient>()));
        }
      }
      expect(find.byType(DecoratedBox), findsNothing);
    });

    for (final ios in [false, true]) {
      final how = ios ? 'iOS Reduce Motion' : 'Android animations off';

      testWidgets('$how gives the new mark at rest, not a fast one',
          (tester) async {
        await pumpCrossing(tester, 3, 4, disableAnimations: !ios, ios: ios);
        if (ios) {
          // The case the old MediaQuery-only check missed: MediaQuery really
          // does say false here, so only prefersReducedMotion can see it.
          expect(
              MediaQuery.disableAnimationsOf(
                  tester.element(find.byType(RankUpCelebration))),
              isFalse,
              reason: 'sanity: this is the iOS flag alone, not Android\'s');
        }
        final shown = renderedSpec(tester);
        final want = prestigeMarkFor(PrestigeCatalog.tiers[4])!;
        expect(shown.outerSweep, want.outerSweep);
        expect(shown.innerSweep, want.innerSweep,
            reason: 'the sweep IS the content, and a rushed sweep is worse '
                'than none');
        await tester.pumpAndSettle();
      });
    }

    testWidgets('iOS Reduce Motion: the summit arrives solid, with no sheen',
        (tester) async {
      // calm also stands down the summit's two later movements, the flood
      // growing over the rings and the sheen running across the medal after.
      // What is left is one mark, already solid, standing still.
      await pumpCrossing(tester, 7, 8, ios: true);
      final marks =
          tester.widgetList<PrestigeMark>(find.byType(PrestigeMark)).toList();
      expect(marks, hasLength(1),
          reason: 'no flood layer over the rings, just the summit itself');
      expect(marks.single.spec.solid, isTrue);
      expect(marks.single.animate, isFalse,
          reason: 'the sheen is exactly the movement Reduce Motion asks '
              'not to happen');
      expect(find.byType(ClipOval), findsNothing);
      await tester.pumpAndSettle();
      expect(tester.widget<PrestigeMark>(find.byType(PrestigeMark)).animate,
          isFalse,
          reason: 'and none is started once the moment has settled either');
    });

    testWidgets('without Reduce Motion the summit does flood (control)',
        (tester) async {
      // The same first frame with the setting off, so the case above is
      // proven to be looking at something that would otherwise be there.
      await pumpCrossing(tester, 7, 8);
      expect(find.byType(PrestigeMark), findsNWidgets(2));
      expect(find.byType(ClipOval), findsOneWidget);
      await tester.pumpAndSettle();
    });

    group('the sheet\'s own entrance', () {
      /// Opens the real dialog through [showRankUpCelebration] and stops a
      /// third of the way into its 300ms entrance.
      Future<void> openPartway(WidgetTester tester) async {
        await tester.pumpWidget(MaterialApp(
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          locale: const Locale('ar'),
          theme: GameTheme.dark,
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => unawaited(showRankUpCelebration(ctx,
                      from: PrestigeCatalog.tiers[3],
                      to: PrestigeCatalog.tiers[4])),
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        ));
        await tester.tap(find.text('go'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
      }

      Finder above(Type t) => find.ancestor(
          of: find.byType(RankUpCelebration), matching: find.byType(t));

      testWidgets('grows in when nobody asked for calm', (tester) async {
        await openPartway(tester);
        expect(above(ScaleTransition), findsOneWidget);
        await tester.pumpAndSettle();
      });

      testWidgets('iOS Reduce Motion: fades in, does not grow',
          (tester) async {
        iosReduceMotion(tester);
        await openPartway(tester);
        expect(MediaQuery.disableAnimationsOf(
                tester.element(find.byType(RankUpCelebration))),
            isFalse,
            reason: 'sanity: only the iOS flag is on');
        expect(above(ScaleTransition), findsNothing,
            reason: 'growing in from 90 percent is movement, which is what '
                'Reduce Motion asked to drop');
        expect(above(FadeTransition), findsWidgets,
            reason: 'the cross-fade is the one entrance it keeps');
        await tester.pumpAndSettle();
      });
    });

    testWidgets('the summit says there is nothing above it', (tester) async {
      final s = S(const Locale('ar'));
      await pumpCrossing(tester, 7, 8);
      await tester.pumpAndSettle();
      expect(find.text(s.rankUpSummitLine), findsOneWidget);
      expect(find.textContaining(s.rankUpMarkGrew), findsNothing,
          reason: 'promising a next rank at the top would be a lie');
    });

    testWidgets('every other rung points at the next one', (tester) async {
      final s = S(const Locale('ar'));
      await pumpCrossing(tester, 4, 5);
      await tester.pumpAndSettle();
      // Accomplished is minLevel 35; Distinguished is 50.
      expect(find.textContaining(s.rankUpNextAtLevel(50)), findsOneWidget);
    });

    testWidgets('the column names the rank once, not three times',
        (tester) async {
      final s = S(const Locale('ar'));
      await pumpCrossing(tester, 3, 4);
      await tester.pumpAndSettle();
      expect(find.text(s.rankUpEyebrow), findsOneWidget);
      expect(find.text(PrestigeCatalog.tiers[4].title(true)), findsOneWidget);
      expect(find.text(s.rankUpLadderPosition(5, 9)), findsOneWidget);
    });
  });
}
