// Two gates that are easy to break silently, pinned so they cannot be.
//
// Both exist because the reward ladder grew in 2026-08: six new streak
// milestones were added to close the 264-day hole between day 101 and the
// streak_365 medal, and one character was recovered from an asset that had
// shipped unused since the character system landed. Neither change is
// self-checking. A milestone with no title still renders, just generically,
// and a character whose gate is dropped simply becomes free. A test is the
// only thing that notices either.
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/features/character/models/accessory.dart'
    show UnlockMetric;
import 'package:grow_daily_v2/features/character/models/character_option.dart';
import 'package:grow_daily_v2/features/character/notifiers/character_notifier.dart';
import 'package:grow_daily_v2/features/dashboard/notifiers/dashboard_notifier.dart';

void main() {
  group('every streak milestone has real copy', () {
    const ar = S(Locale('ar'));
    const en = S(Locale('en'));

    // milestoneTitle ends in `_ => 'Streak Milestone'` / 'إنجاز السلسلة', so a
    // threshold with no case of its own does not fail, it just quietly
    // celebrates with a generic line. That is exactly the kind of miss that
    // survives a release: the overlay looks fine, it just says nothing.
    test('no threshold falls through to the generic title', () {
      for (final m in kStreakMilestones) {
        expect(
          en.milestoneTitle(m),
          isNot('Streak Milestone'),
          reason: 'streak $m has no English title of its own',
        );
        expect(
          ar.milestoneTitle(m),
          isNot('إنجاز السلسلة'),
          reason: 'streak $m has no Arabic title of its own',
        );
      }
    });

    test('a non-milestone day still gets the generic title', () {
      // The fallback has to keep working: it is what any future threshold
      // lands on before someone writes its copy.
      expect(en.milestoneTitle(4), 'Streak Milestone');
      expect(ar.milestoneTitle(4), 'إنجاز السلسلة');
    });

    test('every title is distinct, in both languages', () {
      // Two thresholds sharing a title reads as a bug to the person who hits
      // the second one and is told the same thing twice.
      for (final s in [en, ar]) {
        final titles = kStreakMilestones.map(s.milestoneTitle).toList();
        expect(
          titles.toSet().length,
          titles.length,
          reason: 'two milestones share a title',
        );
      }
    });
  });

  group('the recovered character keeps its gate', () {
    // male_shmagh_red's art shipped in assets/images/character since the
    // character system landed and was wired to nothing: the numbering skipped
    // male3 and it was the only asset with no catalog entry. It was added at
    // level 33 to fill the first empty stretch after the ladder ends at 25.
    // Nothing else in the app would notice if that gate were dropped.
    CharacterOption shmagh() => CharacterCatalog.all.firstWhere(
          (c) => c.id == 'male_shmagh_red',
          orElse: () => throw StateError('male_shmagh_red left the catalog'),
        );

    // characterId omitted: its default is already the free blue ghutra, which
    // is exactly what "not wearing the shmagh" needs to mean here.
    const fresh = CharacterState(
      equippedAccessoryId: null,
      ownedAccessoryIds: {},
    );

    test('it is gated on level 33, not free', () {
      expect(shmagh().unlock, isNotNull, reason: 'it must not become free');
      expect(shmagh().unlock!.metric, UnlockMetric.level);
      expect(shmagh().unlock!.amount, 33);
    });

    test('an account below 33 cannot wear it', () {
      expect(
        fresh.canWear(shmagh(), level: 32, streak: 400, completions: 9999),
        isFalse,
        reason: 'no other axis may open a level gate',
      );
    });

    test('an account at 33 can', () {
      expect(
        fresh.canWear(shmagh(), level: 33, streak: 0, completions: 0),
        isTrue,
      );
    });

    test('someone who already wore it keeps it even below the gate', () {
      // canWear's whole reason for existing: raising a gate must never
      // confiscate a look somebody already had.
      const worn = CharacterState(
        equippedAccessoryId: null,
        ownedAccessoryIds: {},
        wornCharacterIds: {'male_shmagh_red'},
        isLoading: false,
      );
      expect(
        worn.canWear(shmagh(), level: 1, streak: 0, completions: 0),
        isTrue,
      );
    });

    test('it sits last in the ladder, so it fills the tail and not a gap', () {
      final males = CharacterCatalog.all
          .where((c) => c.gender == CharacterGender.male)
          .toList();
      expect(males.last.id, 'male_shmagh_red');
    });
  });
}
