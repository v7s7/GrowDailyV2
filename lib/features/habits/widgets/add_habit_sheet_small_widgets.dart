part of 'add_habit_sheet.dart';


// ─── Equal-width pill (fixed 1/n row share, centered, shrink-to-fit text) ──
// Used wherever a fixed-size set of options (5 prayers, 7 weekdays) should
// always fill exactly one row at uniform width, rather than wrap unevenly.

class _EqualPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _EqualPill({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return InkWell(
      borderRadius: BorderRadius.circular(GameSpacing.buttonRadius),
      onTap: onTap,
      child: TweenAnimationBuilder<double>(
        key: ValueKey(selected),
        tween: Tween(begin: selected ? 0.9 : 1.0, end: 1.0),
        duration: GameMotion.standard,
        curve: Curves.easeOutBack,
        builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
        child: AnimatedContainer(
          duration: GameMotion.quick,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? GameColors.gold.withOpacity(0.12) : gp.surface,
            borderRadius: BorderRadius.circular(GameSpacing.buttonRadius),
            border: Border.all(color: selected ? GameColors.gold.withOpacity(0.5) : gp.border),
          ),
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected ? GameColors.gold : gp.textSec,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Fixed-column chip grid ─────────────────────────────────────────────
// Every cell gets the exact same width (available width ÷ columns, minus
// gaps), so a row of chips lines up like a grid regardless of how long
// each individual label is — the plain Wrap this replaced sized each chip
// to its own text, which produced a different chip count on every row and
// a lot of dead space next to short labels.
// Both now live in lib/shared/widgets/choice_chip_grid.dart so the Tasks
// reminder picker is literally the same control, not a copy that can
// drift. Aliased rather than renamed at every call site: this file has
// dozens of usages and the private names still read fine locally.
typedef _ChipGrid = ChoiceChipGrid;
typedef _PlainChoiceChip = PlainChoiceChip;



class _PlainActionChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  // Set on suggestion chips only — a small reward preview to make tapping
  // one feel like claiming a shortcut, not just filling in a text field.
  // Left null for plain action chips that aren't tied to any specific
  // reward.
  final int? xp;

  const _PlainActionChip({required this.label, required this.onTap, this.xp});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: gp.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: gp.border.withOpacity(0.9), width: 0.8),
        ),
        // Centered, and the label is the one that gives way (ellipsis) if
        // the fixed cell is too narrow for it — the XP badge stays fixed
        // size and always fully visible, same reasoning as
        // _PlainChoiceChip's centering above.
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: gp.textPrimary,
                  height: 1.1,
                ),
              ),
            ),
            if (xp != null) ...[
              const SizedBox(width: 6),
              Text(
                '+$xp',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: GameColors.gold,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.gp.textTert));
}

class _SmallPick extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SmallPick({required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return InkWell(
      borderRadius: BorderRadius.circular(GameSpacing.buttonRadius),
      onTap: onTap,
      child: TweenAnimationBuilder<double>(
        key: ValueKey(selected),
        tween: Tween(begin: selected ? 0.9 : 1.0, end: 1.0),
        duration: GameMotion.standard,
        curve: Curves.easeOutBack,
        builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
        child: AnimatedContainer(
          duration: GameMotion.quick,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? GameColors.gold.withOpacity(0.12) : gp.surface,
            borderRadius: BorderRadius.circular(GameSpacing.buttonRadius),
            border: Border.all(color: selected ? GameColors.gold.withOpacity(0.5) : gp.border),
          ),
          alignment: Alignment.center,
          child: Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: selected ? FontWeight.w800 : FontWeight.w600, color: selected ? GameColors.gold : gp.textSec)),
        ),
      ),
    );
  }
}
