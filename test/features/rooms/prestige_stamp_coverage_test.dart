// Every prestige tier must have a compact mark, because the leaderboard row
// has no room for the alternative.
//
// _PrestigeStamp falls back to the titled _PrestigeChip for any tier whose
// id is missing from kPrestigeMarks. That fallback exists so a row can never
// render an empty plate or throw, and it used to be nearly unreachable — the
// row only drew a stamp above level 1, and every tier above level 1 had a
// mark.
//
// It stopped being nearly unreachable the day the row began showing EVERY
// rank, base "Seeker" included (see _LeaderboardRow). Now a tier without a
// mark reaches a line that _PrestigeStamp's own doc comment measures as
// having "exactly 0.00pt of spare width at the largest text size", and the
// chip it falls back to is roughly twice the stamp's width. So the gap would
// not show up as a missing badge; it would show up as someone's name
// ellipsized away, or an overflow stripe across a room.
//
// Cheap to keep true (one map entry per tier) and easy to forget when adding
// a tier, which is exactly what a test is for.
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/features/character/models/prestige_tier.dart';
import 'package:grow_daily_v2/features/character/widgets/prestige_mark.dart';

void main() {
  test('every tier in the catalog has a mark', () {
    final missing = [
      for (final tier in PrestigeCatalog.tiers)
        if (prestigeMarkFor(tier) == null) tier.id,
    ];
    expect(missing, isEmpty,
        reason: 'these tiers would fall back to the wide titled chip on the '
            'leaderboard row, which has no spare width: $missing');
  });

  test('the base level-1 tier has one, since every room row now shows it', () {
    // Called out separately from the sweep above because this is the tier
    // the change actually put on screen: before, level 1 rendered nothing.
    final seeker = PrestigeCatalog.tiers.firstWhere((t) => t.minLevel == 1);
    expect(prestigeMarkFor(seeker), isNotNull,
        reason: 'the tier every account starts on is the one most rows will '
            'render, so it must have the compact form');
  });

  test('marks are ranked uniquely and contiguously from 1', () {
    // The stamp prints "rank of N", so a duplicate or a gap would put two
    // people at the same rung, or claim a rung that does not exist.
    final ranks = kPrestigeMarks.values.map((m) => m.rank).toList()..sort();
    expect(ranks, List.generate(kPrestigeMarks.length, (i) => i + 1),
        reason: 'prestige ranks must be 1..N with no gaps or duplicates: '
            '$ranks');
  });
}
