import 'package:flutter/material.dart';

import '../../../core/theme/game_theme.dart';

/// The colored state of a single square in the Weekly Victory Grid.
///
/// The whole product revolves around one idea: every completed action colors
/// a square, and the goal is to fill the week. States map to colors:
///
///   none     → white   (not completed)
///   partial  → yellow  (partially completed)
///   complete → emerald (completed) — green for most presets, or the
///              theme's own signature color for a few (see ThemePreset's
///              doc comment)
///   failed   → red     (attempted but failed)
///   bonus    → blue    (bonus achievement)
///   skipped  → gray    (intentionally skipped)
///
/// A tap cycles white → yellow → complete → white. A long-press opens the
/// full palette (including the red / blue / gray "advanced" states).
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

  /// The states reachable by a plain tap, in cycle order.
  static const List<SquareState> tapCycle = [none, complete];

  /// Next state when the user taps the square: white → green → white.
  ///
  /// One tap means done. The cycle used to stop at yellow on the way
  /// (white → yellow → green → white), which made the app's single most
  /// common action cost two taps and put a state nobody asked for in between:
  /// the first tap on an empty square produced "partly done", which is a
  /// claim, and rarely the one the person meant. Marking a habit done is the
  /// whole product, and it should take one tap.
  ///
  /// Yellow is not gone, it is just no longer something a tap can wander
  /// into. It is still reachable deliberately from the long-press palette,
  /// and it is still what a habit counted several times a day shows while its
  /// count is part done — which is the one place a partial square means
  /// something precise rather than a vague half.
  ///
  /// Every non-empty state taps back to white for the same reason it always
  /// did: a mis-set square is one tap from a clean slate. What guards that
  /// now is a confirmation rather than the length of the cycle — see
  /// _handleSquareTap.
  SquareState get next => switch (this) {
        none => complete,
        partial || complete => none,
        failed || bonus || skipped => none,
      };

  /// What this square is, said out loud — for screen readers.
  ///
  /// The Grid is a wall of coloured boxes: to a sighted person the colour IS
  /// the information, and to VoiceOver it was nothing at all. Every square
  /// announced itself as an unlabelled button, which made the app's central
  /// feature unusable rather than merely awkward. See _SquareCell, which
  /// builds the full "habit, date, state" label around this.
  String localLabel(bool isAr) => switch (this) {
        none => isAr ? 'فارغ' : 'empty',
        partial => isAr ? 'جزئي' : 'partly done',
        complete => isAr ? 'مكتمل' : 'done',
        failed => isAr ? 'لم يتم' : 'missed',
        bonus => isAr ? 'مكافأة' : 'bonus',
        skipped => isAr ? 'متخطى' : 'skipped',
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
        bonus => GameColors.iconXp,
        skipped => const Color(0xFF8C9A92),
      };

  // Dark-mode fill for the empty state — deliberately flat, hue-free gray,
  // not derived from the active ThemePreset. GameColors.surfaceHighlight
  // (the old source for this) is every preset's own "elevated surface"
  // tone reused all over the app, and for every single one of the 11
  // presets it's a green-leaning color by design (e.g. the default preset's
  // is #20332B — green channel visibly higher than red or blue) — a
  // reasonable choice for a generic card background, but here it's filling
  // the exact same squares that turn actual-green on completion, so an
  // empty square and a barely-there heatmap day both read as "a little bit
  // green" instead of "nothing happened." Picked to sit at roughly the same
  // brightness as the old #20332B (so nothing about contrast/visibility
  // regresses — see the fill() doc comment below on why that matters) with
  // the color pulled out entirely, R == G == B.
  static const Color _noneFillDark = Color(0xFF2B2B2B);

  /// Fill color for the square, adapted to light/dark so the "empty" state
  /// reads correctly in both themes. In dark mode this is a fixed neutral
  /// gray (see _noneFillDark) rather than a one-off hardcoded value close
  /// to the background — the previous fill was only a few RGB units off
  /// the card background behind it, so an empty square was almost
  /// invisible except for its thin border. That low-contrast outline then
  /// reads to the eye as smaller/inset than a solidly-filled square of the
  /// exact same size, which is what made whole columns look misaligned
  /// even though every square shares the same fixed dimensions. Light
  /// mode is untouched: GameColors.lightSurfaceHL is a warm cream tone,
  /// not a green one, so it was never the thing being reported here.
  Color fill(bool dark) => switch (this) {
        none => dark ? _noneFillDark : GameColors.lightSurfaceHL,
        partial => GameColors.warning.withOpacity(dark ? 0.30 : 0.28),
        complete => GameColors.emerald.withOpacity(dark ? 0.34 : 0.26),
        failed => GameColors.error.withOpacity(dark ? 0.30 : 0.22),
        bonus => GameColors.iconXp.withOpacity(dark ? 0.32 : 0.24),
        skipped => (dark ? const Color(0xFF3A463F) : const Color(0xFFDCD5C5))
            .withOpacity(dark ? 0.6 : 1),
      };

  /// Border color for the square.
  Color border(bool dark) => switch (this) {
        none => dark ? GameColors.border : GameColors.lightBorder,
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
