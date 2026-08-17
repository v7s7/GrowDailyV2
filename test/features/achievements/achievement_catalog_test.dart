import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/features/achievements/models/achievement_model.dart';

/// The achievement system had no test coverage at all, and the unlock
/// predicate was open-coded three times over (completeHabit,
/// applyGridSquareChange, and each screen's own progress bar) with the
/// copies quietly disagreeing — the grid path only ever tested two of the
/// five triggers. These lock down the shared layer those call sites now
/// share, plus the catalog invariants the family-ladder UI assumes.
void main() {
  AchievementStats stats({
    int streak = 0,
    int level = 1,
    int totalCompletions = 0,
    int greenSquares = 0,
    Map<String, int> categoryCompletions = const {},
  }) =>
      AchievementStats(
        streak: streak,
        level: level,
        totalCompletions: totalCompletions,
        greenSquares: greenSquares,
        categoryCompletions: categoryCompletions,
      );

  AchievementModel byId(String id) => AchievementCatalog.findById(id)!;

  group('AchievementStats — one predicate for all five triggers', () {
    test('reads the right counter for each trigger', () {
      final s = stats(
        streak: 12,
        level: 30,
        totalCompletions: 640,
        greenSquares: 88,
        categoryCompletions: {'quran': 41, 'health': 900},
      );
      expect(s.currentFor(byId('streak_7')), 12);
      expect(s.currentFor(byId('level_25')), 30);
      expect(s.currentFor(byId('completions_500')), 640);
      expect(s.currentFor(byId('green_100')), 88);
      // habitMastery reads only its own targetCategory — a big count in an
      // unrelated category must not leak into it.
      expect(s.currentFor(byId('quran_25')), 41);
    });

    test('a missing category counts as zero, not as an error', () {
      expect(stats().currentFor(byId('quran_25')), 0);
      expect(stats().progressFor(byId('quran_25')), 0);
    });

    test('meets() is inclusive at the threshold', () {
      expect(stats(streak: 6).meets(byId('streak_7')), isFalse);
      expect(stats(streak: 7).meets(byId('streak_7')), isTrue);
      expect(stats(streak: 8).meets(byId('streak_7')), isTrue);
    });

    test('progressFor clamps to 0..1', () {
      expect(stats(streak: 0).progressFor(byId('streak_30')), 0);
      expect(stats(streak: 15).progressFor(byId('streak_30')), 0.5);
      expect(stats(streak: 9999).progressFor(byId('streak_30')), 1.0);
    });
  });

  group('newlyUnlocked', () {
    test('returns every tier crossed at once, not just the lowest', () {
      // The case that motivated the fixed-point loop in _resolveUnlocks: a
      // single action can land past several rungs of the same ladder.
      final ids = AchievementCatalog.newlyUnlocked(
        stats(totalCompletions: 2500),
        const [],
      ).map((a) => a.id).toSet();
      expect(ids, containsAll(<String>[
        'completions_50',
        'completions_500',
        'completions_2000',
      ]));
      expect(ids, isNot(contains('completions_5000')));
    });

    test('never re-reports something already unlocked', () {
      final already = ['completions_50', 'completions_500'];
      final ids = AchievementCatalog.newlyUnlocked(
        stats(totalCompletions: 2500),
        already,
      ).map((a) => a.id);
      expect(ids, isNot(contains('completions_50')));
      expect(ids, contains('completions_2000'));
    });

    test('nothing qualifies on a blank account except the 1-square win', () {
      // green_1's threshold is 1, so a brand-new account with zero of
      // everything must unlock nothing at all.
      final ids = AchievementCatalog.newlyUnlocked(stats(), const []);
      expect(ids, isEmpty);
      expect(
        AchievementCatalog.newlyUnlocked(stats(greenSquares: 1), const [])
            .map((a) => a.id),
        ['green_1'],
      );
    });

    test('special-trigger achievements are never awarded by a counter', () {
      // None exist today; this guards the day one is added, so it can't be
      // handed out to everyone at once by a 0 >= 0 comparison.
      final specials = AchievementCatalog.all
          .where((a) => a.trigger == AchievementTrigger.special);
      for (final a in specials) {
        expect(stats().meets(a), isFalse, reason: a.id);
      }
    });
  });

  group('nextLockedIn — resolves by identity, not by counting', () {
    test('returns the lowest locked tier', () {
      expect(
        AchievementCatalog.nextLockedIn('streak', const [])?.id,
        'streak_7',
      );
      expect(
        AchievementCatalog.nextLockedIn('streak', const ['streak_7'])?.id,
        'streak_30',
      );
    });

    test('returns null once the whole ladder is climbed', () {
      final all =
          AchievementCatalog.tiersFor('streak').map((t) => t.id).toList();
      expect(AchievementCatalog.nextLockedIn('streak', all), isNull);
    });

    test('a gapped ladder resolves to the real gap, not to an index', () {
      // The regression this replaced: AchievementsScreen picked the active
      // tier with `tiers[unlockedCount]`. With gold unlocked but silver not
      // — reachable because uncompleteHabit walks greenSquares and
      // categoryCompletions back down while unlockedAchievements is never
      // pruned — the count is 2, so it described *gold* (index 2) as "next"
      // while the medal row showed gold already earned.
      final gapped = ['streak_7', 'streak_100'];
      expect(AchievementCatalog.nextLockedIn('streak', gapped)?.id,
          'streak_30');
      final tiers = AchievementCatalog.tiersFor('streak');
      expect(tiers[gapped.length].id, 'streak_100',
          reason: 'index-based lookup would have picked an unlocked tier');
    });
  });

  group('tierCounts', () {
    test('tallies per tier and reports zeros for untouched tiers', () {
      final counts = AchievementCatalog.tierCounts(
          const ['streak_7', 'level_10', 'green_1', 'streak_30']);
      expect(counts[AchievementTier.bronze], 3);
      expect(counts[AchievementTier.silver], 1);
      expect(counts[AchievementTier.gold], 0);
      expect(counts[AchievementTier.platinum], 0);
    });

    test('every tier key is present even with nothing unlocked', () {
      final counts = AchievementCatalog.tierCounts(const []);
      expect(counts.keys.toSet(), AchievementTier.values.toSet());
      expect(counts.values.every((v) => v == 0), isTrue);
    });

    test('a full clear tallies to the catalog size', () {
      final all = AchievementCatalog.all.map((a) => a.id).toList();
      final counts = AchievementCatalog.tierCounts(all);
      expect(counts.values.reduce((a, b) => a + b),
          AchievementCatalog.all.length);
    });
  });

  group('catalog invariants the ladder UI depends on', () {
    test('ids are unique', () {
      final ids = AchievementCatalog.all.map((a) => a.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('every achievement belongs to a declared family', () {
      final familyIds =
          AchievementCatalog.families.map((f) => f.id).toSet();
      for (final a in AchievementCatalog.all) {
        expect(familyIds, contains(a.familyId), reason: a.id);
      }
    });

    test('every family is exactly one bronze→platinum ladder', () {
      for (final f in AchievementCatalog.families) {
        final tiers = AchievementCatalog.tiersFor(f.id);
        expect(tiers.length, AchievementTier.values.length, reason: f.id);
        expect(tiers.map((t) => t.tier).toList(), AchievementTier.values,
            reason: '${f.id} must have one of each tier, in order');
      }
    });

    test('thresholds rise strictly with tier', () {
      for (final f in AchievementCatalog.families) {
        final tiers = AchievementCatalog.tiersFor(f.id);
        for (var i = 1; i < tiers.length; i++) {
          expect(tiers[i].threshold, greaterThan(tiers[i - 1].threshold),
              reason: '${f.id}: ${tiers[i].id} must cost more than '
                  '${tiers[i - 1].id}');
        }
      }
    });

    test('habitMastery achievements name a target category', () {
      for (final a in AchievementCatalog.all) {
        if (a.trigger == AchievementTrigger.habitMastery) {
          expect(a.targetCategory, isNotNull, reason: a.id);
          expect(a.targetCategory, isNotEmpty, reason: a.id);
        }
      }
    });

    test('thresholds are positive — a 0 threshold unlocks for everyone', () {
      for (final a in AchievementCatalog.all) {
        expect(a.threshold, greaterThan(0), reason: a.id);
      }
    });
  });

  group('copy', () {
    test('every achievement and family is fully translated', () {
      for (final a in AchievementCatalog.all) {
        expect(a.nameAr.trim(), isNotEmpty, reason: a.id);
        expect(a.descriptionAr.trim(), isNotEmpty, reason: a.id);
        expect(a.localName(true), a.nameAr, reason: a.id);
        expect(a.localName(false), a.name, reason: a.id);
      }
      for (final f in AchievementCatalog.families) {
        expect(f.titleAr.trim(), isNotEmpty, reason: f.id);
        expect(f.localTitle(true), f.titleAr, reason: f.id);
      }
    });

    test('Arabic copy uses Western digits, matching the counters', () {
      // The screen puts a description and a "86 / 500" fraction on the same
      // card. The descriptions used to be written in Arabic-Indic digits
      // ("أكمل عاداتك ٥٠٠ مرة") while every counter rendered Western, so a
      // single card showed the same number in two numeral systems.
      final arabicIndic = RegExp(r'[٠-٩]');
      for (final a in AchievementCatalog.all) {
        expect(arabicIndic.hasMatch(a.descriptionAr), isFalse,
            reason: '${a.id}: "${a.descriptionAr}"');
        expect(arabicIndic.hasMatch(a.nameAr), isFalse, reason: a.id);
      }
    });

    test('tier numerals are the four rungs, in order', () {
      expect(AchievementTier.values.map((t) => t.numeral).toList(),
          ['I', 'II', 'III', 'IV']);
    });
  });
}
