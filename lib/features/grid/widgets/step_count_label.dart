import 'package:flutter/material.dart';

import '../../habits/step_auto_complete.dart'
    show compactStepCount, fullStepCount;

/// The step count drawn inside a linked walking habit's Grid square: "2730",
/// "9999", "12k", or "9.9k" where four digits do not fit.
///
/// Which form is decided here, by measuring, because it depends on the
/// square: Aziz asked for every digit "if it fits correct on devices screen,
/// if not, it be 9.9k" (2026-09-16). The full form is laid out at the
/// square's own type size; if it is wider than the square's inside, the
/// short form is used; if even that does not fit, the type shrinks to fit
/// rather than spilling over the border.
///
/// Its own file for one more reason: the Grid screen's library imports intl,
/// whose TextDirection shadows dart:ui's, so it cannot say TextDirection.ltr.
/// It used to reach for bidiIsolate instead, wrapping the count in invisible
/// LRI/PDI marks, and on the simulator that drew "2.7" pushed right with the
/// "k" gone. A plain left-to-right Text has nothing invisible to measure.
class StepCountLabel extends StatelessWidget {
  final int steps;

  /// The square's side, which the type is sized from.
  final double squareSize;

  final Color color;

  const StepCountLabel({
    super.key,
    required this.steps,
    required this.squareSize,
    required this.color,
  });

  /// Clear space kept between the number and each side of the square.
  static const double sideRoom = 3;

  /// Type size as a share of the square's side.
  static const double typeShare = 0.30;

  /// How tall a digit stands, as a share of the type size.
  ///
  /// What the number is centred on. Centring the Text's line box instead sat
  /// "2.7k" 0.83pt high on the simulator (measured in pixels, 2026-09-16):
  /// the app's face carries the tall ascent and descent Arabic script needs,
  /// and Latin digits only fill the lower part of that box above the
  /// baseline. So the baseline is placed half a digit below the square's
  /// middle, which puts the middle of the digits on the middle of the square.
  static const double digitHeightShare = 0.70;

  @override
  Widget build(BuildContext context) {
    final room = squareSize - 2 * sideRoom;
    final base = DefaultTextStyle.of(context).style.merge(
          TextStyle(
            fontSize: squareSize * typeShare,
            height: 1,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        );

    TextPainter measure(String text, TextStyle style) => TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: TextDirection.ltr,
          textScaler: TextScaler.noScaling,
          maxLines: 1,
        )..layout();

    var text = fullStepCount(steps) ?? '';
    var style = base;
    var painter = measure(text, style);
    if (painter.width > room) {
      text = compactStepCount(steps) ?? text;
      painter = measure(text, style);
    }
    if (painter.width > room && painter.width > 0) {
      style = style.copyWith(fontSize: style.fontSize! * room / painter.width);
      painter = measure(text, style);
    }

    // From the top of the Text's box to where the middle of its digits is,
    // against the middle of the box that Center lines up with the square.
    final baseline =
        painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    final digitsMiddle = baseline - style.fontSize! * digitHeightShare / 2;
    final nudge = painter.height / 2 - digitsMiddle;
    painter.dispose();

    return Transform.translate(
      offset: Offset(0, nudge),
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        // Latin inside an RTL row: without its own direction the "k" can
        // land on the wrong side of the digits.
        textDirection: TextDirection.ltr,
        // No text scaling: the square is a fixed 30..60pt. The exact number
        // is one hold away at any size.
        textScaler: TextScaler.noScaling,
        style: style,
      ),
    );
  }
}
