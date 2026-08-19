import 'package:flutter/material.dart';

import '../../../core/constants/game_constants.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';

/// The little "+20 XP · +8" that rises off a task's checkbox the first
/// time it is completed.
///
/// Tasks pay a real reward (GameConstants.matrixTaskXpReward/GoldReward,
/// once per task ever via MatrixTask.rewarded) and the page never said so:
/// the counters live on other tabs, and the level-up toasts are registered
/// by the Grid screen only. An economy nobody can see can't motivate
/// anyone and can't help sell anything either. This is deliberately tiny —
/// no sound, no confetti, ~900ms — because tasks complete many times a
/// day and habit completions already own the big celebration.
///
/// Inserted into the root overlay at the tile's own position, so it
/// renders above everything and needs no Stack cooperation from the board.
void showTaskRewardFloat(BuildContext tileContext) {
  final box = tileContext.findRenderObject();
  if (box is! RenderBox || !box.attached) return;
  final overlay = Overlay.of(tileContext, rootOverlay: true);
  final origin = box.localToGlobal(Offset.zero);
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _RewardFloat(
      // Above the row's vertical center, horizontally centered on the row:
      // readable in both text directions without knowing which side the
      // checkbox is on.
      anchor: Offset(origin.dx + box.size.width / 2, origin.dy),
      onDone: () => entry.remove(),
    ),
  );
  overlay.insert(entry);
}

class _RewardFloat extends StatefulWidget {
  final Offset anchor;
  final VoidCallback onDone;
  const _RewardFloat({required this.anchor, required this.onDone});

  @override
  State<_RewardFloat> createState() => _RewardFloatState();
}

class _RewardFloatState extends State<_RewardFloat>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward().whenComplete(widget.onDone);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final rise = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    final fade = CurvedAnimation(
      parent: _c,
      // Hold, then fade out over the back half.
      curve: const Interval(0.45, 1.0, curve: Curves.easeIn),
    );
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => Positioned(
        left: widget.anchor.dx - 70,
        top: widget.anchor.dy - 14 - 26 * rise.value,
        width: 140,
        child: Opacity(opacity: 1.0 - fade.value, child: child),
      ),
      child: Material(
        color: Colors.transparent,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xE61A2129),
              borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
              border: Border.all(color: GameColors.gold.withOpacity(0.45)),
            ),
            child: Text(
              s.matrixRewardFloat(
                GameConstants.matrixTaskXpReward,
                GameConstants.matrixTaskGoldReward,
              ),
              maxLines: 1,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: GameColors.gold,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
