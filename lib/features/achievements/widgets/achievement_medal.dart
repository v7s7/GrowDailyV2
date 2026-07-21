import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/theme/game_theme.dart';
import '../models/achievement_model.dart';

/// How a single medal should currently read to the eye — derived by the
/// caller from unlock state plus which tier is "next" in its family (see
/// AchievementsScreen/_MiniAchievementCard for how each computes this).
enum MedalState {
  /// Already earned — full tier color, icon on top, a gentle shimmer so it
  /// never looks like just a static icon in a circle.
  unlocked,

  /// Not yet earned, but the very next one in its family — a thin
  /// progress ring instead of a flat locked fill, so it reads as
  /// "in reach" rather than just another gray circle.
  inProgress,

  /// Not yet earned and not next up either — flat, muted, no progress
  /// ring (nothing meaningful to show yet).
  locked,
}

/// A single achievement medal: a circular, metal-toned badge for [tier],
/// carrying [icon] (the achievement's own trigger icon — a Material glyph,
/// never an emoji). Used identically across the achievements grid, the
/// profile preview strip, and the unlock celebration sheet so "what a
/// medal looks like" is defined exactly once and can't drift between them.
class AchievementMedal extends StatelessWidget {
  final AchievementTier tier;
  final IconData icon;
  final MedalState state;
  final double size;

  /// Only meaningful when [state] is [MedalState.inProgress].
  final double progress;

  /// Whether the unlocked shimmer loops forever (the unlock celebration
  /// sheet — one medal, the sole focus of the screen) or plays once on
  /// appear and settles (every other surface — a grid of up to 20 of
  /// these shimmering at once would be more distracting than "fun").
  final bool loopShimmer;

  const AchievementMedal({
    super.key,
    required this.tier,
    required this.icon,
    required this.state,
    this.size = 56,
    this.progress = 0,
    this.loopShimmer = false,
  });

  (Color base, Color shine) get _colors => switch (tier) {
        AchievementTier.bronze => (
            GameColors.tierBronze,
            GameColors.tierBronzeShine
          ),
        AchievementTier.silver => (
            GameColors.tierSilver,
            GameColors.tierSilverShine
          ),
        AchievementTier.gold => (GameColors.tierGold, GameColors.tierGoldShine),
        AchievementTier.platinum => (
            GameColors.tierPlatinum,
            GameColors.tierPlatinumShine
          ),
      };

  /// Same crossover point GameColors.onEmerald (game_theme.dart) already
  /// uses: 0.1791 is where black and white give exactly equal contrast
  /// against a given background, so above it black actually reads better
  /// than white even for backgrounds that look "medium" rather than
  /// obviously light — reused here instead of guessing a per-tier icon
  /// color by eye.
  Color _iconOn(Color bg) =>
      bg.computeLuminance() > 0.1791 ? Colors.black : Colors.white;

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final (base, shine) = _colors;
    final isLocked = state != MedalState.unlocked;
    final iconColor = isLocked ? gp.textTert : _iconOn(base);

    Widget medal = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: isLocked
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [shine, base],
                stops: const [0.08, 0.95],
              ),
        color: isLocked ? gp.textTert.withOpacity(0.14) : null,
        border: Border.all(
          color: isLocked ? gp.border : shine.withOpacity(0.9),
          width: isLocked ? 1 : 1.5,
        ),
        boxShadow: isLocked
            ? null
            : [
                BoxShadow(
                  color: base.withOpacity(0.45),
                  blurRadius: size * 0.28,
                  spreadRadius: size * 0.02,
                ),
              ],
      ),
      child: Center(
        child: Icon(icon, size: size * 0.42, color: iconColor),
      ),
    );

    // A thin progress ring around an in-reach medal — the one thing that
    // separates "next up" from "locked and distant" at a glance.
    if (state == MedalState.inProgress) {
      medal = Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size + 8,
            height: size + 8,
            child: CircularProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              strokeWidth: 2.5,
              backgroundColor: gp.border,
              valueColor: AlwaysStoppedAnimation(base),
            ),
          ),
          medal,
        ],
      );
    }

    if (state != MedalState.unlocked) return medal;

    final shimmered = medal
        .animate(onPlay: (c) {
          if (loopShimmer) c.repeat();
        })
        .shimmer(duration: 1800.ms, color: shine.withOpacity(0.6));

    // Sparkle flecks — Icons.auto_awesome_rounded, a vector glyph, not an
    // emoji — reserved for the two hardest tiers so Gold/Platinum reads
    // as genuinely more special than Bronze/Silver, not just a recolor of
    // the same badge.
    if (tier != AchievementTier.gold && tier != AchievementTier.platinum) {
      return shimmered;
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        shimmered,
        Positioned(
          top: -size * 0.06,
          right: -size * 0.02,
          child: Icon(Icons.auto_awesome_rounded,
              size: size * 0.22, color: shine),
        ),
      ],
    );
  }
}

/// Maps an [AchievementTrigger]/family to the icon its medals show — one
/// place instead of the four call sites that used to each repeat this
/// switch (achievements_screen.dart, reaction_overlays.dart,
/// progress_hub_screen.dart, and now AchievementsScreen's family cards).
IconData achievementIconFor(AchievementTrigger trigger) => switch (trigger) {
      AchievementTrigger.streak => Icons.local_fire_department_rounded,
      AchievementTrigger.level => Icons.bolt_rounded,
      AchievementTrigger.totalCompletions => Icons.check_circle_rounded,
      AchievementTrigger.habitMastery => Icons.menu_book_rounded,
      AchievementTrigger.greenSquares => Icons.grid_view_rounded,
      AchievementTrigger.special => Icons.stars_rounded,
    };
