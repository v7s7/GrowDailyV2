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
  ///
  /// [partial] deliberately keeps a non-null IconData even though every site
  /// in the app now draws it through [glyph] instead. This is the safety net:
  /// four call sites write `state.icon ?? Icons.circle_outlined`, so returning
  /// null here would make a partial square render the EXACT same hollow circle
  /// as an empty one — a state marker becoming indistinguishable from "nothing
  /// happened". `contrast_rounded` is a hard 50/50 split disc, so a site that
  /// is added later and forgets [glyph] still says "half", not "a clock".
  ///
  /// It used to be `Icons.timelapse_rounded`, which is a clock face. The
  /// yellow square has always meant "counts as half a day" — the app says so
  /// in its own words in [S.squareStateEffect] — and a clock says the one
  /// thing it does not mean, that time is passing. See [levelFactor].
  IconData? get icon => switch (this) {
        none => null,
        partial => Icons.contrast_rounded,
        complete => Icons.check_rounded,
        failed => Icons.close_rounded,
        bonus => Icons.auto_awesome_rounded,
        skipped => Icons.remove_rounded,
      };

  /// How full to draw the square, 0..1 — null means paint it flat.
  ///
  /// Only [partial] has a level, and it is exactly a half. This is not a new
  /// metaphor: the Grid already fills a counted habit's square upward from
  /// the bottom as its count climbs (see the `_isCounting` block in
  /// _SquareCell), and a hand-marked جزئي is the same statement frozen at
  /// 50%. Geometry also survives the size range in a way a glyph does not —
  /// the cell clamps to 30..60pt, and at the low end a 15pt wedge collapses
  /// into a smudge while half of a square is still half of a square.
  double? get levelFactor => this == partial ? 0.5 : null;

  /// The risen part of a levelled square, painted OVER [fill].
  ///
  /// Dark is a second wash of the same token: 0.30 over 0.30 composites to
  /// 0.51, which measures 1.75:1 against the unrisen half — a clear step with
  /// no new colour to keep in sync across the 11 presets.
  ///
  /// Light cannot do that. #F7C948 has no headroom above a light card: a
  /// second wash moves almost only the blue channel, so the two halves come
  /// out 1.07:1 apart — a chroma step the eye reads as one flat square. Light
  /// mode therefore tints DOWNWARD toward [_partialInk] instead, which is a
  /// value step rather than a saturation one.
  ///
  /// The 0.45 is measured, not picked: it lands the light step at ~1.6:1,
  /// which is where dark already sits. Checked on a real board rather than
  /// on paper — at 0.30 the line was crisp up close but the two halves still
  /// read as one square at arm's length, which is the only distance that
  /// matters for a mark whose whole job is being scannable across a week.
  Color levelFill(bool dark) => dark
      ? GameColors.warning.withOpacity(0.30)
      : _partialInk.withOpacity(0.45);

  /// The 1pt line where the fill stops — the single element that carries this
  /// mark at 30pt, in light mode, and in greyscale. Not decoration.
  Color levelLine(bool dark) => dark ? GameColors.warning : _partialInk;

  /// #F7C948 taken down in VALUE at the same hue (H 44.2°, S 0.78, V 0.63)
  /// rather than to a different colour. Measures 2.97:1 against the light
  /// partial fill, which is what a structural hairline needs.
  static const Color _partialInk = Color(0xFFA18023);

  /// A drop-in for `Icon(state.icon, size: …, color: …)`.
  ///
  /// Same size×size box as an [Icon], so no call site changes shape. The only
  /// state that differs is [partial], which gets [HalfFullMark] — the board
  /// square in miniature — instead of an icon. A circle was the problem: a
  /// half-filled circle is a clock face, and every attempt to say "half" with
  /// one lands back where this started.
  Widget glyph({required double size, Color? color, IconData? fallback}) {
    final ink = color ?? accent;
    if (this == partial) return HalfFullMark(size: size, color: ink);
    final data = icon ?? fallback;
    return data == null
        ? SizedBox(width: size, height: size)
        : Icon(data, size: size, color: ink);
  }
}

/// A rounded square filled to its own halfway line — the Grid's partial
/// square, shrunk to glyph size.
///
/// Used wherever the state has to appear as a small mark beside a label
/// (the heatmap day sheet, Grid Journal, Progress Hub, a room's own plan
/// card) rather than as a full square on the board. Those tiles are 30-36pt
/// containers over an `accent.withOpacity(0.14)` ground, where a two-tone
/// fill would be invisible, so the mark is drawn as ink instead: an outline
/// for the whole day, solid for the half that happened.
class HalfFullMark extends StatelessWidget {
  final double size;
  final Color color;
  const HalfFullMark({super.key, required this.size, required this.color});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _HalfFullMarkPainter(color)),
      );
}

class _HalfFullMarkPainter extends CustomPainter {
  final Color color;
  const _HalfFullMarkPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    // Clamped, not proportional all the way down: below ~11pt a proportional
    // stroke thins to nothing and the outline stops reading as a container.
    final stroke = (size.width * 0.115).clamp(1.2, 2.4);
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );
    final rrect =
        RRect.fromRectAndRadius(rect, Radius.circular(size.width * 0.24));
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawRect(
      Rect.fromLTRB(0, size.height / 2, size.width, size.height),
      Paint()..color = color,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HalfFullMarkPainter old) => old.color != color;
}
