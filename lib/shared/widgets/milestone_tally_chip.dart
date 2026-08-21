import 'package:flutter/material.dart';

import '../../core/theme/game_theme.dart';
import '../../core/utils/western_digits.dart';

/// "3 ارتقاء مستوى" — one milestone type and how many times it happened,
/// on the monthly report card and on every Life Timeline year.
///
/// ── Why the colour is only on the icon ─────────────────────────────────
/// This used to paint its accent FOUR times per chip: a tinted fill, a
/// matching border, the icon, and the label text. Put three of those in a
/// row (gold, green, orange, each one shouting at the same volume) and the
/// eye has nowhere to land, so a row that holds three small facts reads
/// like a row of awards. Decoration was doing the work that hierarchy
/// should.
///
/// Now each chip says one thing in colour and the rest in the neutral
/// palette everything else on these screens uses: the ICON carries the
/// meaning (gold for an achievement, green for a perfect day, orange for a
/// streak — colours the rest of the app already assigns, see GameColors'
/// icon* set), the COUNT is the loud part because it is the actual fact,
/// and the LABEL is quiet because it only names what was counted. Three
/// chips now read as one row of three facts, which is what they are.
///
/// ── Why one widget and not two ─────────────────────────────────────────
/// The reports hub and Life Timeline each grew their own copy, and they had
/// already drifted: one wrote "3 ارتقاء مستوى", the other "ارتقاء مستوى ×3".
/// Same idea, same screenshot, two notations. The `×N` form went, both
/// because it disagreed with the older surface and because it reads like a
/// spec sheet rather than a sentence.
class MilestoneTallyChip extends StatelessWidget {
  /// Carries the meaning, and the only coloured element here.
  final IconData icon;
  final Color color;
  final int count;
  final String label;

  const MilestoneTallyChip({
    super.key,
    required this.icon,
    required this.color,
    required this.count,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        // A RELATIVE tint rather than a named surface: these chips sit on
        // gp.surface inside a Life Timeline year card and on a different
        // card in the reports hub, so anything absolute would vanish into
        // one of the two. This always lands exactly one step above whatever
        // is behind it, in either theme.
        color: gp.dark
            ? Colors.white.withOpacity(0.05)
            : Colors.black.withOpacity(0.04),
        borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
        border: Border.all(color: gp.border, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 6),
          Text(
            toWesternDigits('$count'),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: gp.textPrimary,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: gp.textSec,
            ),
          ),
        ],
      ),
    );
  }
}
