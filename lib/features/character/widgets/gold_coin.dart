import 'package:flutter/material.dart';

import '../../../core/theme/game_theme.dart';

/// A struck gold coin, drawn rather than iconified.
///
/// The closet is where gold finally *means* something, and it was
/// previously represented everywhere by `Icons.toll_rounded` — two flat
/// concentric circles in a single flat color. That reads as a unit label,
/// not as treasure. This paints a real minted disc: a light catch at the
/// upper-right, the metal falling off to [GameColors.goldDim] at the
/// lower-left, a struck rim, and an eight-point star (خاتم سليمان, the
/// most common motif on Islamic-world coinage and tilework) pressed into
/// the face.
///
/// It is deliberately a painter and not an asset, so it can carry a real
/// three-stop metal gradient at any size.
///
/// The metal is [GameColors.iconGold], which is FIXED, not the
/// preset-driven [GameColors.gold] accent. Same argument the medal tiers
/// already make (see `tierGold`'s comment): "gold" is the name of an
/// accent *role* in ThemePreset, and it resolves to teal on Ocean, rose on
/// Rose & Ink, violet on Nour Violet. A currency the user is meant to read
/// as treasure cannot be teal on nine presets out of eleven. The rest of
/// the closet still follows the active preset; only the metal is pinned.
///
/// [dim] renders the same coin in dead metal, for a price the user cannot
/// currently afford — the shape stays identical so the eye reads "same
/// thing, out of reach" rather than "different thing".
class GoldCoin extends StatelessWidget {
  final double size;
  final bool dim;

  const GoldCoin({super.key, this.size = 20, this.dim = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _CoinPainter(
          face: dim ? const Color(0xFF6E7A70) : GameColors.iconGold,
          deep: dim ? const Color(0xFF3E4741) : const Color(0xFF6B4A15),
          shine: dim ? const Color(0xFF8D9A92) : const Color(0xFFFFEFCB),
        ),
      ),
    );
  }

}

class _CoinPainter extends CustomPainter {
  final Color face;
  final Color deep;
  final Color shine;

  const _CoinPainter({
    required this.face,
    required this.deep,
    required this.shine,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final c = Offset(r, r);

    // Body: light source upper-right, which is where the rest of the app's
    // elevation reads from.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0.34, -0.42),
          radius: 1.05,
          colors: [shine, face, deep],
          stops: const [0.0, 0.52, 1.0],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );

    // Struck rim, then an inner bead line — the two details that separate a
    // coin from a disc at 20px.
    canvas.drawCircle(
      c,
      r - r * 0.045,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.09
        ..color = deep.withOpacity(0.85),
    );
    canvas.drawCircle(
      c,
      r * 0.72,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.055
        ..color = deep.withOpacity(0.62),
    );

    // Eight-point star = two squares, one rotated 45°, unioned. Drawn as a
    // single path so the overlap doesn't double-darken.
    final a = r * 0.46;
    final star = Path()
      ..addRect(Rect.fromCenter(center: c, width: a * 2, height: a * 2))
      ..addPolygon([
        Offset(c.dx, c.dy - a * 1.42),
        Offset(c.dx + a * 1.42, c.dy),
        Offset(c.dx, c.dy + a * 1.42),
        Offset(c.dx - a * 1.42, c.dy),
      ], true);
    canvas.drawPath(
      star..fillType = PathFillType.nonZero,
      Paint()..color = deep.withOpacity(0.66),
    );
  }

  @override
  bool shouldRepaint(_CoinPainter old) =>
      old.face != face || old.deep != deep || old.shine != shine;
}

/// The header balance: the coin sitting in a soft pouch with the amount
/// beside it. Used in the closet AppBar.
class GoldPurse extends StatelessWidget {
  final int gold;

  const GoldPurse({super.key, required this.gold});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsetsDirectional.only(start: 6, end: 13),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            GameColors.iconGold.withOpacity(0.17),
            GameColors.iconGold.withOpacity(0.07),
          ],
        ),
        borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
        border: Border.all(color: GameColors.iconGold.withOpacity(0.34), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const GoldCoin(size: 24),
          const SizedBox(width: 7),
          // The balance is the point of the pill, so it gets real size —
          // the old one rendered it at 12px, smaller than a tile caption.
          Text(
            '$gold',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: GameColors.iconGold,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// A price, as a coin in a pill. [affordable] false swaps to dead metal and
/// neutral text instead of just dimming the number, so "can't afford this"
/// is legible at a glance across a whole grid.
class GoldPrice extends StatelessWidget {
  final int amount;
  final bool affordable;

  /// Sized for a three-column grid cell, where the pill has about 95pt to
  /// live in rather than a full-width row.
  final bool dense;

  const GoldPrice({
    super.key,
    required this.amount,
    this.affordable = true,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Container(
      height: dense ? 24 : 29,
      padding: dense
          ? const EdgeInsetsDirectional.only(start: 4, end: 9)
          : const EdgeInsetsDirectional.only(start: 5, end: 12),
      decoration: BoxDecoration(
        color: affordable ? GameColors.iconGold.withOpacity(0.14) : gp.surfaceHL,
        borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
        border: Border.all(
          color: affordable
              ? GameColors.iconGold.withOpacity(0.30)
              : Colors.transparent,
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GoldCoin(size: dense ? 16 : 19, dim: !affordable),
          SizedBox(width: dense ? 4 : 5),
          Text(
            '$amount',
            style: TextStyle(
              fontSize: dense ? 11.5 : 13.5,
              fontWeight: FontWeight.w700,
              color: affordable ? GameColors.iconGold : gp.textTert,
            ),
          ),
        ],
      ),
    );
  }
}
