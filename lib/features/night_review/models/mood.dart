import 'package:flutter/material.dart';

import '../../../core/theme/game_theme.dart';

/// A single evening emotional check-in. Tracked per day so the app can
/// surface trends between mood and the habits/streaks logged that same day.
enum Mood {
  great,
  good,
  neutral,
  sad,
  exhausted;

  String toJson() => name;

  static Mood? fromJsonOrNull(String? v) {
    if (v == null) return null;
    for (final m in values) {
      if (m.name == v) return m;
    }
    return null;
  }

  String label(bool isAr) => switch (this) {
        great => isAr ? 'رائع' : 'Great',
        good => isAr ? 'جيد' : 'Good',
        neutral => isAr ? 'عادي' : 'Neutral',
        sad => isAr ? 'حزين' : 'Sad',
        exhausted => isAr ? 'منهك' : 'Exhausted',
      };

  /// Icon + tint shared by every mood-picker/history surface (NightReview's
  /// own picker, the history calendar's day cells and detail sheet) — one
  /// definition so a new screen can't quietly drift out of sync with what
  /// the picker itself uses. Icon-based, not emoji, to stay crisp at any
  /// size and theme consistently with the rest of the app's iconography.
  (IconData, Color) get visual => switch (this) {
        Mood.great =>
          (Icons.sentiment_very_satisfied_rounded, GameColors.emerald),
        Mood.good => (Icons.sentiment_satisfied_rounded, GameColors.iconXp),
        Mood.neutral =>
          (Icons.sentiment_neutral_rounded, GameColors.warning),
        Mood.sad =>
          (Icons.sentiment_dissatisfied_rounded, GameColors.iconStreak),
        Mood.exhausted =>
          (Icons.sentiment_very_dissatisfied_rounded, GameColors.error),
      };
}
