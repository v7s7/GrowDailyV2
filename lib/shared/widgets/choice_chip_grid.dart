import 'package:flutter/material.dart';

import '../../core/theme/game_theme.dart';

/// Equal-width chips laid out on a fixed number of columns.
///
/// Every cell gets the exact same width (available width ÷ columns, minus
/// gaps), so a row of chips lines up like a grid regardless of how long each
/// individual label is — a plain [Wrap] sizes each chip to its own text,
/// which produces a different chip count on every row and a lot of dead
/// space next to short labels.
///
/// Lifted out of Add Habit (where it started as `_ChipGrid`) so the Tasks
/// reminder picker can be the *same* control rather than a lookalike: those
/// two screens both ask "before or after, and by how much", and they should
/// not drift apart visually the first time either one is restyled.
class ChoiceChipGrid extends StatelessWidget {
  final int columns;
  final List<Widget> items;
  static const double _spacing = 8;

  const ChoiceChipGrid({
    super.key,
    required this.columns,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cellWidth =
            (constraints.maxWidth - _spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: _spacing,
          runSpacing: _spacing,
          children: [
            for (final item in items) SizedBox(width: cellWidth, child: item),
          ],
        );
      },
    );
  }
}

/// A single chip in a [ChoiceChipGrid].
///
/// [selectedColor] exists because the two callers accent differently: Add
/// Habit tints selection gold (its own accent throughout), while the Tasks
/// sheets tint it with the quadrant's colour, which is what every other
/// control in those sheets — including the reminder rows this sits above —
/// already uses. Same control, same geometry, same motion; only the accent
/// follows its host.
class PlainChoiceChip extends StatelessWidget {
  final bool selected;
  final String label;
  final Widget? icon;
  final Color? selectedColor;
  final VoidCallback onTap;

  const PlainChoiceChip({
    super.key,
    required this.selected,
    required this.label,
    required this.onTap,
    this.icon,
    this.selectedColor,
    this.semanticsLabel,
  });

  /// What a screen reader announces instead of [label]. The offset chips
  /// pass the spelled-out form ("15 minutes before"), because "15" on its
  /// own is a number, not a reminder setting.
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final accent = selectedColor ?? GameColors.gold;
    // Without this a screen reader announces the bare label and nothing
    // else — no button role, and no way to tell a selected chip from an
    // unselected one, which on a multi-select grid is most of the
    // information. The selected state is carried entirely by colour and
    // border weight above, both invisible to assistive tech.
    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 13,
        fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
        color: selected ? accent : gp.textPrimary,
        height: 1.1,
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      label: semanticsLabel,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: TweenAnimationBuilder<double>(
          key: ValueKey(selected),
          tween: Tween(begin: selected ? 0.88 : 1.0, end: 1.0),
          duration: GameMotion.standard,
          curve: Curves.easeOutBack,
          builder: (context, scale, child) =>
              Transform.scale(scale: scale, child: child),
          child: AnimatedContainer(
            duration: GameMotion.quick,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: selected ? accent.withOpacity(0.14) : gp.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? accent : gp.border.withOpacity(0.8),
                width: selected ? 1.1 : 0.8,
              ),
            ),
            // Centered, not left-hugged — now that ChoiceChipGrid gives every
            // chip the same fixed width, a short label like "5" would
            // otherwise sit at the left edge with empty space on the right.
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  icon!,
                  const SizedBox(width: 7),
                ],
                Flexible(child: text),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
