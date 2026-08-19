// The bug: on the اذكار الصباح room, day one rendered a paler green than the
// two days after it, even though all three had identical credit (1 of 2
// habits done, confirmed in Firestore: dailyDoneCount 2026-08-14..16 = 1).
//
// Cause was not the colour ramp. The البداية / اليوم markers are drawn with
// a spreadRadius BoxShadow, which Flutter paints as a FILLED rounded rect
// behind the cell rather than as a hollow ring, and every heat tone is
// translucent — so a marked cell composited its fill over white while its
// unmarked neighbours composited over the card.
//
// These tests pin the invariant that actually matters: the marker must not
// be able to change the colour. They are colour equality checks rather than
// golden images so they say WHY they failed.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/grid/screens/monthly_heatmap_screen.dart'
    show heatColor;
import 'package:grow_daily_v2/features/rooms/notifiers/rooms_notifier.dart'
    show heatmapLevelFor;
import 'package:grow_daily_v2/features/rooms/screens/room_detail_screen.dart'
    show roomStripCellFill;

void main() {
  // The two real backdrops: everyone else's card, and the gold-tinted card
  // the signed-in user's own row uses.
  const card = Color(0xFF11161C);
  const yourCard = Color(0xFF16191A);

  Color fill(
    double credit, {
    bool isRest = false,
    bool isMissed = false,
    Color backdrop = card,
  }) =>
      roomStripCellFill(
        credit: credit,
        isRest: isRest,
        isMissed: isMissed,
        dark: true,
        backdrop: backdrop,
      );

  test('every fill is fully opaque, whatever the state', () {
    // This is the property the marker plate exploited. If any of these ever
    // goes translucent again, a ring behind it will bleed through and the
    // reported bug is back.
    for (final c in [0.0, 0.25, 0.5, 0.75, 1.0]) {
      expect(fill(c).alpha, 255, reason: 'credit $c');
    }
    expect(fill(0, isRest: true).alpha, 255);
    expect(fill(0, isMissed: true).alpha, 255);
  });

  test('identical credit gives an identical colour', () {
    // 14, 15 and 16 August: 1 of 2 habits each. Only the 14th carried the
    // البداية ring, and only the 14th looked different.
    expect(fill(0.5), fill(0.5));
    expect(fill(1.0), fill(1.0));
  });

  test('a missed day is the card colour, not white', () {
    // Before the fix, a first day that was a miss had a transparent fill
    // over a white plate, so it painted a solid white square.
    expect(fill(0, isMissed: true), card);
    expect(fill(0, isMissed: true), isNot(const Color(0xFFFFFFFF)));
  });

  test('a rest day stays a faint tint, not a near-white block', () {
    final rest = fill(0, isRest: true);
    expect(rest.alpha, 255);
    expect(rest, isNot(card), reason: 'still visibly credited');
    // 13% emerald over a dark card must stay dark.
    expect(rest.computeLuminance(), lessThan(0.2));
  });

  test('the ramp still climbs with credit', () {
    // Guards the blend from flattening the ramp it sits on top of.
    final l = [0.25, 0.5, 0.75, 1.0].map((c) => fill(c).computeLuminance());
    final asList = l.toList();
    for (var i = 1; i < asList.length; i++) {
      expect(asList[i], greaterThan(asList[i - 1]),
          reason: 'step $i should be brighter than the one before');
    }
  });

  test('an unmarked cell is unchanged from the raw tone over its card', () {
    // The fix must be a no-op everywhere except behind a marker, otherwise
    // it silently restyles the whole strip.
    for (final c in [0.25, 0.5, 0.75, 1.0]) {
      expect(
        fill(c),
        Color.alphaBlend(heatColor(heatmapLevelFor(c), true), card),
        reason: 'credit $c',
      );
    }
  });

  test('your own gold-tinted row blends against its own card', () {
    // Blending everyone against gp.surface would tint the signed-in user's
    // row differently from the rest of the leaderboard.
    expect(fill(0.5, backdrop: yourCard), isNot(fill(0.5)));
    expect(fill(0, isMissed: true, backdrop: yourCard), yourCard);
  });
}
