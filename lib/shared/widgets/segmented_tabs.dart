import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/game_theme.dart';

/// A full-width pill of equal segments, one selected at a time.
///
/// The app had no segmented control of any kind before this: the two
/// existing lookalikes (`_MatrixFilterToggle` on the Matrix board and
/// `_TabPill` in the add-habit sheet) are both private, both content-sized
/// rather than full-width, and neither could carry the reports hub's three
/// equal periods without the widest label (أسبوعي) shoving the others
/// off-centre. This is the shared one, styled to match `_FilterSegment` so
/// it reads as the same control family rather than a third invention.
///
/// Deliberately not Flutter's [SegmentedButton]: that renders Material 3
/// chrome (its own outline, check icons, ripple shape) which fights the
/// preset-driven palette everywhere else in this app, and the check icon
/// on the selected segment would push the Arabic labels around as the
/// selection moved.
///
/// Segments are laid out with [Expanded], so the reading direction is
/// whatever [Directionality] says: in Arabic أسبوعي sits at the right,
/// which is where a first tab belongs.
class SegmentedTabs extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;

  const SegmentedTabs({
    super.key,
    required this.labels,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: gp.surfaceHL,
        borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
        border: Border.all(color: gp.border, width: 0.5),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: _Segment(
                label: labels[i],
                active: i == selected,
                // A tap on the segment already showing is swallowed rather
                // than re-emitted: the callers rebuild a whole report body
                // on change, and re-selecting the current tab would throw
                // away a scroll position for nothing.
                onTap: i == selected ? null : () => onChanged(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback? onTap;

  const _Segment({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final color = active ? GameColors.gold : gp.textSec;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        child: AnimatedContainer(
          duration: GameMotion.relaxed,
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color:
                active ? GameColors.gold.withOpacity(0.16) : Colors.transparent,
            borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: GameColors.gold.withOpacity(0.18),
                      blurRadius: 8,
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: AnimatedScale(
              duration: GameMotion.relaxed,
              curve: Curves.easeOutBack,
              scale: active ? 1.0 : 0.96,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
