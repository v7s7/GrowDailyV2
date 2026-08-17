import 'package:flutter/material.dart';

import '../../../core/theme/game_theme.dart';
import '../models/achievement_model.dart';

/// The four shades one medal tier needs, already resolved for the active
/// light/dark mode.
///
/// Exists because "the color of Silver" isn't one value. A metal used as a
/// *fill* and the same metal used as *ink on a card* have opposite contrast
/// requirements, and the app got this wrong in a way that was invisible in
/// dark mode and unreadable in light: silver's `#B8C0C8` is a correct
/// medal fill, but as a progress-bar color and a "فضية" caption on a white
/// card it sits at roughly 1.6:1 — the Silver rung of every ladder simply
/// disappeared. `base`/`shine`/`deep` paint the medal; [ink] paints
/// everything that sits *on* a surface next to it.
///
/// Four call sites used to each carry their own `switch (tier)` returning a
/// single color (AchievementMedal, AchievementsScreen's family card,
/// AchievementUnlockSheet, ProgressHubScreen's preview strip). This is that
/// switch, once.
class TierPalette {
  /// The light catch at the top-left of the medal.
  final Color shine;

  /// The metal itself — the medal's mid-tone.
  final Color base;

  /// The shadowed bottom-right edge. Also the medal's rim: it's the one
  /// shade dark enough to separate a Silver or Gold medal from a white card
  /// without a drop shadow doing all the work.
  final Color deep;

  /// The on-surface variant — tier captions, progress rings, progress bars,
  /// mastered-card borders. Mode-dependent; the others aren't, because a
  /// medal carries its own background either way.
  final Color ink;

  const TierPalette({
    required this.shine,
    required this.base,
    required this.deep,
    required this.ink,
  });

  factory TierPalette.of(AchievementTier tier, {required bool dark}) =>
      switch (tier) {
        AchievementTier.bronze => TierPalette(
            shine: GameColors.tierBronzeShine,
            base: GameColors.tierBronze,
            deep: GameColors.tierBronzeDeep,
            ink: dark
                ? GameColors.tierBronzeInkDark
                : GameColors.tierBronzeInkLight,
          ),
        AchievementTier.silver => TierPalette(
            shine: GameColors.tierSilverShine,
            base: GameColors.tierSilver,
            deep: GameColors.tierSilverDeep,
            ink: dark
                ? GameColors.tierSilverInkDark
                : GameColors.tierSilverInkLight,
          ),
        AchievementTier.gold => TierPalette(
            shine: GameColors.tierGoldShine,
            base: GameColors.tierGold,
            deep: GameColors.tierGoldDeep,
            ink: dark
                ? GameColors.tierGoldInkDark
                : GameColors.tierGoldInkLight,
          ),
        AchievementTier.platinum => TierPalette(
            shine: GameColors.tierPlatinumShine,
            base: GameColors.tierPlatinum,
            deep: GameColors.tierPlatinumDeep,
            ink: dark
                ? GameColors.tierPlatinumInkDark
                : GameColors.tierPlatinumInkLight,
          ),
      };

  /// Convenience for widgets that already have a [BuildContext].
  factory TierPalette.from(BuildContext context, AchievementTier tier) =>
      TierPalette.of(
        tier,
        dark: Theme.of(context).brightness == Brightness.dark,
      );

  /// Black or white on top of [base], whichever reads better — same 0.1791
  /// luminance crossover [GameColors.onEmerald] uses, where black and white
  /// give exactly equal WCAG contrast.
  Color get onBase => base.computeLuminance() > 0.1791
      ? Colors.black
      : Colors.white;
}
