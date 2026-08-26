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

// ─── Times per day ────────────────────────────────────────────────────────
//
// Option A from design/canvas.json: one quiet row, always present while
// Daily is selected, reading "مرة في اليوم" at its resting value of 1. The
// alternative was to hide it behind a disclosure, which costs nothing in
// height and is found by nobody; this row also teaches what the default is,
// which is most of the reason it earns its line.
//
// A daily habit's per-day count IS its frequencyTarget — see
// IslamicHabitTemplate.effectiveDailyTarget, which has always read it that
// way. So this control edits the same field the Weekly dropdown does; it is
// only the meaning of that field that differs between the two modes.

/// Upper bound on the stepper. Twelve is deliberately generous (hourly water
/// through a waking day is about this) and deliberately finite: the square
/// has to divide into visible slices, and past a dozen a single tap stops
/// moving it enough to feel like anything happened.
const int kMaxTimesPerDay = 12;

class _TimesPerDayRow extends StatelessWidget {
  final int count;
  final ValueChanged<int> onChanged;
  const _TimesPerDayRow({required this.count, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final isMulti = count > 1;
    final canDec = count > 1;
    final canInc = count < kMaxTimesPerDay;

    Widget step(IconData icon, bool enabled, int delta, String tip) => Semantics(
          button: true,
          enabled: enabled,
          label: tip,
          child: InkWell(
            borderRadius: BorderRadius.circular(GameSpacing.buttonRadius),
            onTap: enabled
                ? () {
                    HapticFeedback.selectionClick();
                    onChanged(count + delta);
                  }
                : null,
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: gp.surface,
                borderRadius: BorderRadius.circular(GameSpacing.buttonRadius),
                border: Border.all(color: gp.border),
              ),
              child: Icon(
                icon,
                size: 18,
                // Dimmed rather than removed at the ends, so the control
                // keeps its shape and the row never reflows under a thumb.
                color: enabled ? gp.textSec : gp.border,
              ),
            ),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            step(Icons.remove_rounded, canDec, -1, s.timesPerDayDecrease(count)),
            const SizedBox(width: 8),
            SizedBox(
              width: 34,
              child: Text(
                '$count',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  // Gold only once it is actually saying something — at 1
                  // this row is describing the default, not a choice.
                  color: isMulti ? GameColors.gold : gp.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            step(Icons.add_rounded, canInc, 1, s.timesPerDayIncrease(count)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    s.timesPerDayLabel(count),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: gp.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    s.timesPerDayHint(count),
                    style: TextStyle(fontSize: 11, color: gp.textTert),
                  ),
                ],
              ),
            ),
          ],
        ),
        // Only once the count is a choice. At 1 there is nothing to explain,
        // and a permanent paragraph under an untouched control is the exact
        // clutter Option A was supposed to avoid.
        if (isMulti) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: GameColors.gold.withOpacity(0.08),
              borderRadius: BorderRadius.circular(GameSpacing.buttonRadius),
              border: Border.all(color: GameColors.gold.withOpacity(0.25)),
            ),
            child: Text(
              s.timesPerDayNote(count),
              style: TextStyle(fontSize: 11, height: 1.5, color: gp.textSec),
            ),
          ),
        ],
      ],
    );
  }
}
