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

  /// Take the whole width it is given, content centred, and shrink the
  /// content only if it could not otherwise fit. Set by [MilestoneTallyRows],
  /// which hands every chip in a row the same width.
  final bool fill;

  const MilestoneTallyChip({
    super.key,
    required this.icon,
    required this.color,
    required this.count,
    required this.label,
    this.fill = false,
  });

  MilestoneTallyChip _filled() => MilestoneTallyChip(
        key: key,
        icon: icon,
        color: color,
        count: count,
        label: label,
        fill: true,
      );

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final content = Row(
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
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      alignment: fill ? Alignment.center : null,
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
      child: fill
          ? FittedBox(fit: BoxFit.scaleDown, child: content)
          : content,
    );
  }
}

/// Milestone chips as full, even rows: every chip in a row the same width,
/// and no row left half empty.
///
/// A plain Wrap sized each chip to its own words, so "6 يوم مثالي", "6
/// ارتقاء مستوى" and "1 إنجاز سلسلة" came out three different widths, and a
/// fourth dropped onto a line of its own (Aziz, 2026-09-21: "make it fit and
/// clean size and not random sizes"). The two-column grid before the Wrap
/// had the opposite fault: an odd count left a ragged half-empty row. So the
/// chips are dealt into as few rows as hold three each, spread evenly (three
/// make one row, four make two and two, five make three and two), and every
/// row is shared out equally across the full width. A lone chip keeps its
/// own size: stretched across a whole card it would read as a button.
class MilestoneTallyRows extends StatelessWidget {
  final List<MilestoneTallyChip> chips;

  const MilestoneTallyRows({super.key, required this.chips});

  static const double _gap = 8;
  static const int _mostPerRow = 3;

  @override
  Widget build(BuildContext context) {
    if (chips.isEmpty) return const SizedBox.shrink();
    if (chips.length == 1) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: chips.single,
      );
    }
    final rowCount = (chips.length / _mostPerRow).ceil();
    final perRow = (chips.length / rowCount).ceil();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var start = 0; start < chips.length; start += perRow) ...[
          if (start > 0) const SizedBox(height: _gap),
          Row(
            children: [
              for (var i = start;
                  i < chips.length && i < start + perRow;
                  i++) ...[
                if (i > start) const SizedBox(width: _gap),
                Expanded(child: chips[i]._filled()),
              ],
            ],
          ),
        ],
      ],
    );
  }
}
