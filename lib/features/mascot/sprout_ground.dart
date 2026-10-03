import 'package:flutter/material.dart';

import '../../core/theme/game_theme.dart';
import 'sprout.dart';

/// Doum standing on something, where nothing else on the page is under him:
/// a soft shadow at his feet and a short line to stand on.
///
/// Aziz, 2026-10-03, on how Doum is drawn across the app: on the empty
/// Habits page and the empty Rooms page he floated in the middle of the
/// screen with nothing under him, where everywhere else he stands on
/// something (the Habits page's board, the recap card) or sits inside a
/// card. This is the same idea for a page with nothing to stand on.
///
/// The shadow and the line are drawn under him, his feet over the middle of
/// the shadow. Every pose keeps about [_feetGap] of its height clear under
/// the feet, so the line meets the feet, not the picture's edge. His pop and
/// his breaths scale from his feet (Sprout), so he never leaves the line.
class GroundedSprout extends StatelessWidget {
  const GroundedSprout({
    super.key,
    required this.pose,
    required this.height,
    this.entrance = SproutEntrance.pop,
    this.idleBreaths = 3,
    this.semanticLabel,
  });

  final SproutPose pose;

  /// As Sprout.height: the front pose's height at this scale.
  final double height;
  final SproutEntrance entrance;
  final int idleBreaths;
  final String? semanticLabel;

  /// The share of a pose picture's height left clear under the feet
  /// (measured on the front and pencil poses: 12 of ~770 pixels).
  static const double _feetGap = 0.016;

  /// The shadow's size against Doum's width: a little wider than his feet
  /// (about half to two thirds of the picture's width).
  static const double _shadowWidth = 0.85;
  static const double _shadowHeight = 0.1;

  /// The line under him, against his width.
  static const double _lineWidth = 2.2;

  /// Where the ground is inside this widget's box, from its top: what a test
  /// measures the feet against.
  static double groundYFor(SproutPose pose, double height) =>
      Sprout.sizeOf(pose, height).height * (1 - _feetGap);

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final size = Sprout.sizeOf(pose, height);
    final groundY = groundYFor(pose, height);
    final shadowW = size.width * _shadowWidth;
    final shadowH = (size.width * _shadowHeight).clamp(8.0, 24.0);
    final shade = gp.dark
        ? Colors.black.withOpacity(0.45)
        : gp.textPrimary.withOpacity(0.14);
    // As wide as the line wants, and no wider than the slot it is given:
    // the empty Habits page's 170pt Doum asks for a 341pt line between
    // margins that leave 338 on an iPhone 17 Pro and less on a smaller
    // phone. Everything is centred by the Stack's alignment, never by
    // offsets worked out from the width asked for, so a squeezed box keeps
    // him centred; and no LayoutBuilder, which cannot answer the intrinsic
    // height the empty page's SliverFillRemaining asks for.
    final lineW = size.width * _lineWidth;
    return SizedBox(
      width: lineW > size.width ? lineW : size.width,
      height: groundY + shadowH / 2,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          // The line, then the shadow on it, then Doum over both.
          Positioned(
            key: const ValueKey('sprout-ground-line'),
            top: groundY,
            left: 0,
            right: 0,
            height: 1,
            child: ColoredBox(color: gp.border),
          ),
          Positioned(
            key: const ValueKey('sprout-ground-shadow'),
            top: groundY - shadowH / 2,
            child: SizedBox(
              width: shadowW,
              height: shadowH,
              // A circle's soft fade stretched into an ellipse: a radial
              // gradient alone stays round in a wide box.
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.diagonal3Values(shadowW / shadowH, 1, 1),
                child: Center(
                  child: SizedBox(
                    width: shadowH,
                    height: shadowH,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [shade, shade.withOpacity(0)],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            child: Sprout(
              pose: pose,
              height: height,
              entrance: entrance,
              idleBreaths: idleBreaths,
              semanticLabel: semanticLabel,
            ),
          ),
        ],
      ),
    );
  }
}
