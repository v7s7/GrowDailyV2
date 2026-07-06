import 'package:flutter/material.dart';

import '../../../core/theme/game_theme.dart';

/// The colored state of a single square in the Weekly Victory Grid.
///
/// The whole product revolves around one idea: every completed action colors a
/// square, and the goal is to fill the week with green. States map to colors:
///
///   none     → white  (not completed)
///   partial  → yellow (partially completed)
///   complete → green  (completed)
///   failed   → red    (attempted but failed)
///   bonus    → blue   (bonus achievement)
///   skipped  → gray   (intentionally skipped)
///
/// A tap cycles white → yellow → green → white. A long-press opens the full
/// palette (including the red / blue / gray "advanced" states).
enum SquareState {
  none,
  partial,
  complete,
  failed,
  bonus,
  skipped;

  String toJson() => name;

  static SquareState fromJson(String? v) =>
      values.firstWhere((e) => e.name == v, orElse: () => SquareState.none);

  /// The three states reachable by a plain tap, in cycle order.
  static const List<SquareState> tapCycle = [none, partial, complete];

  /// Next state when the user taps the square: white → yellow → green → white.
  /// Any "advanced" state (failed/bonus/skipped) taps back to white so a
  /// mis-set square is always one tap away from a clean slate.
  SquareState get next => switch (this) {
        none => partial,
        partial => complete,
        complete => none,
        failed || bonus || skipped => none,
      };

  /// A filled green (or better) square — what the user is chasing.
  bool get isGreen => this == complete || this == bonus;

  /// Whether this state represents any deliberate mark (not the empty default).
  bool get isMarked => this != none;

  /// Fixed XP contribution of this square color, independent of the habit.
  /// This is the universal reward the whole progression system runs on:
  /// green pays the most reliable reward, blue is the bonus-achievement
  /// spike, yellow is half credit for partial effort, red is a small sting
  /// for a logged failure, and white/gray contribute nothing ("ignored").
  int get xpValue => switch (this) {
        complete => 10,
        bonus => 15,
        partial => 5,
        failed => -3,
        none || skipped => 0,
      };

  String get label => switch (this) {
        none => 'Not done',
        partial => 'Partial',
        complete => 'Completed',
        failed => 'Failed',
        bonus => 'Bonus',
        skipped => 'Skipped',
      };

  String get labelAr => switch (this) {
        none => 'لم يكتمل',
        partial => 'جزئي',
        complete => 'مكتمل',
        failed => 'فشل',
        bonus => 'إنجاز إضافي',
        skipped => 'تخطّي',
      };

  /// The accent color that identifies this state (theme-invariant hue).
  Color get accent => switch (this) {
        none => const Color(0xFF9AA397),
        partial => GameColors.warning,
        complete => GameColors.emerald,
        failed => GameColors.error,
        bonus => GameColors.xpBlue,
        skipped => const Color(0xFF8C9A92),
      };

  /// Fill color for the square, adapted to light/dark so the "white" empty
  /// state reads correctly in both themes.
  Color fill(bool dark) => switch (this) {
        none => dark ? const Color(0xFF17251F) : const Color(0xFFF2ECDE),
        partial => GameColors.warning.withOpacity(dark ? 0.30 : 0.28),
        complete => GameColors.emerald.withOpacity(dark ? 0.34 : 0.26),
        failed => GameColors.error.withOpacity(dark ? 0.30 : 0.22),
        bonus => GameColors.xpBlue.withOpacity(dark ? 0.32 : 0.24),
        skipped => (dark ? const Color(0xFF3A463F) : const Color(0xFFDCD5C5))
            .withOpacity(dark ? 0.6 : 1),
      };

  /// Border color for the square.
  Color border(bool dark) => switch (this) {
        none => dark ? const Color(0xFF2D4037) : const Color(0xFFD8CDBA),
        _ => accent.withOpacity(dark ? 0.55 : 0.5),
      };

  /// Small glyph drawn inside a marked square (null for the empty state).
  IconData? get icon => switch (this) {
        none => null,
        partial => Icons.timelapse_rounded,
        complete => Icons.check_rounded,
        failed => Icons.close_rounded,
        bonus => Icons.auto_awesome_rounded,
        skipped => Icons.remove_rounded,
      };
}
