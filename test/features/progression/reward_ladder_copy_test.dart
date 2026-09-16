// Two gates that are easy to break silently, pinned so they cannot be.
//
// Both exist because the reward ladder grew in 2026-08: six new streak
// milestones were added to close the 264-day hole between day 101 and the
// streak_365 medal, and one character was recovered from an asset that had
// shipped unused since the character system landed. Neither change is
// self-checking. A milestone whose ladder link is wrong still renders, just
// pointing at the wrong day, and a character whose gate is dropped simply
// becomes free. A test is the only thing that notices either.
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/features/character/models/accessory.dart'
    show UnlockMetric;
import 'package:grow_daily_v2/features/character/models/character_option.dart';
import 'package:grow_daily_v2/features/character/notifiers/character_notifier.dart';
import 'package:grow_daily_v2/features/dashboard/notifiers/dashboard_notifier.dart';

void main() {
  group('the streak milestone overlay closes on the next threshold', () {
    const ar = S(Locale('ar'));
    const en = S(Locale('en'));

    // This group used to guard twelve flavor titles, one per threshold
    // ("7-Day Warrior" and an Arabic epithet to match), and the failure it
    // caught was a new threshold landing with no title of its own. The
    // titles are gone —
    // the overlay states the streak and names the next threshold instead —
    // so the copy is now derived from kStreakMilestones and cannot go
    // missing. What can still break is the ladder's shape: a threshold
    // pointing at a number that is not on the ladder, or the top pointing
    // past itself into a milestone that does not exist.
    test('each threshold points at the one after it', () {
      for (var i = 0; i < kStreakMilestones.length - 1; i++) {
        expect(
          nextStreakMilestone(kStreakMilestones[i]),
          kStreakMilestones[i + 1],
          reason: 'streak ${kStreakMilestones[i]} points at the wrong next',
        );
      }
    });

    test('the top of the ladder has nothing after it', () {
      expect(nextStreakMilestone(kStreakMilestones.last), isNull);
      // And a day past the top is still the top, not a crash or a wrap.
      expect(nextStreakMilestone(kStreakMilestones.last + 500), isNull);
    });

    test('a day before the first threshold still points at it', () {
      expect(nextStreakMilestone(0), kStreakMilestones.first);
    });

    test('both closing lines name the day count in their own language', () {
      // daysCount carries the Arabic plural rule (3 أيام / 14 يومًا), so the
      // line has to go through it rather than interpolating a bare number.
      expect(ar.milestoneNextStop(14), contains(ar.daysCount(14)));
      expect(ar.milestoneNextStop(3), contains(ar.daysCount(3)),
          reason: '3 أيام and 14 يومًا take different plural forms');
      expect(en.milestoneNextStop(14), 'Next up: 14 days.');
      expect(ar.milestoneLastStop, isNotEmpty);
      expect(en.milestoneLastStop, isNotEmpty);
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
