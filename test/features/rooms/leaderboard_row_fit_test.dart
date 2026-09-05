// A leaderboard row must never spill its badges past the card.
//
// The row is a name plus a variable pile of fixed-width badges: أنت,
// القائد, موقوف, the rank stamp, and a 30pt more-actions button. As a Row
// the name was the only Flexible child, so under pressure it collapsed to
// zero and then the badges overflowed — and in RELEASE there is no warning
// stripe, because RenderFlex only paints that under an assert and
// clipBehavior is Clip.none. The badges simply spill past the card and the
// name renders as a bare ellipsis.
//
// Measured before the fix, with the app's real bundled font: a level-1 row
// carrying أنت + القائد + موقوف + stamp overflowed a 320pt screen at text
// scale 1.3 — an ordinary Large Text setting, not an accessibility extreme
// — and by 29pt at 1.6. Showing the base rank on every row is what made
// that reachable for a normal new account; the geometry was already that
// tight for level 5+ members with a Paused tag.
//
// The row is a Wrap now, which cannot overflow at any scale. These tests
// pin that at the widths and scales where it actually broke.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/theme/game_theme.dart';

void main() {
  /// A faithful replica of the row's width chain, so this test measures the
  /// same budget the real screen has.
  ///
  /// Deliberately a replica rather than a pump of the real widget: the row
  /// is private, needs a RoomModel + RoomParticipant + several providers,
  /// and pumping it would test Firestore plumbing rather than the layout
  /// decision. What matters here is that the badge cluster is laid out by
  /// something that can wrap — so the replica mirrors the real chain
  /// (ListView 16+16, card padding 10, rank 22, gap 6, avatar 30.24, gap
  /// 10) and the real child widths, and would fail identically if the Wrap
  /// were reverted to a Row.
  Widget rowReplica({
    required double screenWidth,
    required bool wrap,
    required List<Widget> badges,
  }) {
    const chrome = 16.0 + 16.0 + 10.0 + 10.0 + 22.0 + 6.0 + 30.24 + 10.0;
    final children = <Widget>[
      const Text('Abdulaziz', maxLines: 1, overflow: TextOverflow.ellipsis),
      ...badges,
    ];
    return SizedBox(
      width: screenWidth - chrome,
      child: wrap
          ? Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: children,
            )
          : Row(children: [Flexible(child: children.first), ...children.skip(1)]),
    );
  }

  Widget badge(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Text(label, style: const TextStyle(fontSize: 10)),
      );

  /// The widest real row: you, the leader, stood down, ranked, in a locale.
  List<Widget> worstCaseBadges(bool isAr) => [
        badge(isAr ? 'أنت' : 'YOU'),
        badge(isAr ? 'القائد' : 'LEADER'),
        badge(isAr ? 'موقوف' : 'Paused'),
        // The rank stamp: a fixed plate, the piece that showing every rank
        // added to rows that previously had none.
        const SizedBox(width: 30.3, height: 22),
      ];

  Future<List<String>> overflowsAt(
    WidgetTester tester, {
    required double width,
    required double scale,
    required bool isAr,
    bool wrap = true,
  }) async {
    final errors = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (d) => errors.add(d.exceptionAsString());
    addTearDown(() => FlutterError.onError = previous);

    await tester.pumpWidget(
      MaterialApp(
        theme: GameTheme.light,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Directionality(
            textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
            child: Align(
              alignment: Alignment.topLeft,
              child: rowReplica(
                screenWidth: width,
                wrap: wrap,
                badges: worstCaseBadges(isAr),
              ),
            ),
          ),
        ),
      ),
    );
    return errors.where((e) => e.contains('overflowed')).toList();
  }

  // The exact combinations the pre-fix row was measured failing at.
  for (final c in const [
    (width: 320.0, scale: 1.3),
    (width: 320.0, scale: 1.4),
    (width: 320.0, scale: 1.6),
    (width: 320.0, scale: 2.0),
    (width: 360.0, scale: 2.0),
    (width: 360.0, scale: 3.1),
  ]) {
    for (final isAr in const [true, false]) {
      testWidgets(
        'the badge cluster fits ${c.width.toInt()}pt at ${c.scale}x '
        '(${isAr ? "ar" : "en"})',
        (tester) async {
          final overflows = await overflowsAt(tester,
              width: c.width, scale: c.scale, isAr: isAr);
          expect(overflows, isEmpty,
              reason: 'the leaderboard row overflowed; it must wrap rather '
                  'than spill its badges past the card: $overflows');
        },
      );
    }
  }

  testWidgets('the replica really does catch a Row (guard the guard)',
      (tester) async {
    // Without this, a replica that silently stopped measuring anything
    // would let all twelve tests above pass vacuously. The same content in
    // a Row at the tightest measured case must still overflow.
    final overflows = await overflowsAt(tester,
        width: 320, scale: 2.0, isAr: false, wrap: false);
    expect(overflows, isNotEmpty,
        reason: 'the replica no longer reproduces the original overflow, so '
            'the passing cases above prove nothing');
  });
}
