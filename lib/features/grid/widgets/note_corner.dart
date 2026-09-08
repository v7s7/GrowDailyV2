import 'package:flutter/material.dart';

/// The mark that says "there is writing on this day".
///
/// A solid right triangle filling the top-right corner of its own box, drawn
/// as the folded corner of a page. One shape, one ink, no interior detail,
/// so nothing about it degrades as it shrinks: at the Grid's 30pt square
/// floor it is roughly 40 square points of solid colour, against the 9pt
/// `sticky_note_2_rounded` glyph it replaces, whose paper-and-lines interior
/// was already illegible at that size and whose bounding box overlapped the
/// centred state glyph.
///
/// It is also the trained convention. A small corner triangle has meant "this
/// cell carries a note" in spreadsheets for thirty years, which is why it
/// needs no onboarding and no legend.
///
/// Deliberately a SHAPE and never a new hue. Colour on a Grid square already
/// carries six meanings (the six SquareStates), plus the covered-day emerald,
/// the missed-quota red and the gold today ring. There is no colour left to
/// spend, so the callers pass an ink already proven to read on the fill
/// underneath rather than introducing a note colour.
///
/// Kept in one file because the icon it replaces appeared exactly once in the
/// codebase and must not become three as it spreads to the heatmap.
class NoteCornerPainter extends CustomPainter {
  final Color ink;
  const NoteCornerPainter(this.ink);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width, size.height)
        ..close(),
      Paint()
        ..color = ink
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(NoteCornerPainter oldDelegate) => oldDelegate.ink != ink;
}

/// The mark, positioned in the physical top-right of [size] square points.
///
/// PHYSICAL top-right, not directional: the mark is a fixed piece of a
/// square's vocabulary, like the today ring, and a mark that swapped corners
/// with the app language would read as two different marks to anyone who has
/// ever switched.
class NoteCorner extends StatelessWidget {
  final double size;
  final Color ink;
  const NoteCorner({super.key, required this.size, required this.ink});

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.square(size),
        painter: NoteCornerPainter(ink),
      );
}
