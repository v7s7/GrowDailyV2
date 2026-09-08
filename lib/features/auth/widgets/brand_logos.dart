import 'package:flutter/widgets.dart';

/// Google's "G" mark, drawn rather than shipped as an image.
///
/// A vector keeps it crisp at any size and in any theme without carrying four
/// PNG densities, and this project has no SVG package to load one with. The
/// four colours are Google's own and MUST NOT be restyled, tinted or
/// monochromed: their branding guidelines allow the full-colour mark or their
/// own supplied assets, and nothing else. That is also why this widget takes
/// no colour parameter.
///
/// The mark never mirrors in RTL. It is a logo, not an icon with a direction,
/// and a flipped G reads as a counterfeit. [CustomPaint] does not mirror on
/// its own, so this is preserved by not opting in rather than by opting out.
class GoogleLogo extends StatelessWidget {
  const GoogleLogo({super.key, required this.size});

  /// Required rather than defaulted: the size is what makes this logo sit
  /// level with the Apple one beside it, so a call site that omits it is
  /// almost certainly a mistake rather than a preference.
  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        width: size,
        height: size,
        child: const CustomPaint(painter: _GoogleLogoPainter()),
      ),
    );
  }
}

/// The official mark's four sub-paths, verbatim from Google's own asset in a
/// 48x48 viewBox, so they can be diffed against the source rather than
/// trusted. Scaled to whatever box the widget is given.
const List<(String, Color)> _googlePaths = [
  (
    'M45.12 24.5c0-1.56-.14-3.06-.4-4.5H24v8.51h11.84c-.51 2.75-2.06 5.08-4.39 '
        '6.64v5.52h7.11c4.16-3.83 6.56-9.47 6.56-16.17z',
    Color(0xFF4285F4),
  ),
  (
    'M24 46c5.94 0 10.92-1.97 14.56-5.33l-7.11-5.52c-1.97 1.32-4.49 2.1-7.45 '
        '2.1-5.73 0-10.58-3.87-12.31-9.07H4.34v5.7C7.96 41.07 15.4 46 24 46z',
    Color(0xFF34A853),
  ),
  (
    'M11.69 28.18C11.25 26.86 11 25.45 11 24s.25-2.86.69-4.18v-5.7H4.34C2.85 '
        '17.09 2 20.45 2 24s.85 6.91 2.34 9.88l7.35-5.7z',
    Color(0xFFFBBC05),
  ),
  (
    'M24 10.75c3.23 0 6.13 1.11 8.41 3.29l6.31-6.31C34.91 4.18 29.93 2 24 2 '
        '15.4 2 7.96 6.93 4.34 14.12l7.35 5.7c1.73-5.2 6.58-9.07 12.31-9.07z',
    Color(0xFFEA4335),
  ),
];

/// The four sub-paths as parsed, so a test can assert the transcribed data
/// really becomes the mark rather than silently drawing nothing at all: a
/// parser that bails on the first unrecognised character still returns a
/// valid, empty [Path], and an empty path paints exactly like a correct one
/// that happens to be off-screen.
@visibleForTesting
List<Path> googleLogoPathsForTest() =>
    [for (final (data, _) in _googlePaths) _parseSvgPath(data)];

class _GoogleLogoPainter extends CustomPainter {
  const _GoogleLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 48.0;
    canvas.save();
    canvas.scale(scale);
    for (final (data, color) in _googlePaths) {
      canvas.drawPath(
        _parseSvgPath(data),
        Paint()
          ..color = color
          ..isAntiAlias = true,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GoogleLogoPainter oldDelegate) => false;
}

/// A deliberately small SVG path-data reader: just the commands Google's mark
/// actually uses (M/m, L/l, H/h, V/v, C/c, S/s, Z/z).
///
/// Writing this beats hand-converting forty curve segments into `cubicTo`
/// calls, because the path strings above then stay byte-comparable with the
/// official asset and a mistake in transcription is visible rather than baked
/// into arithmetic nobody can check.
Path _parseSvgPath(String d) {
  final path = Path();
  final tokens = _tokenize(d);
  var i = 0;
  var x = 0.0;
  var y = 0.0;
  // Kept for the S/s shorthand, which reflects the previous curve's second
  // control point through the current point.
  var lastC1x = 0.0;
  var lastC1y = 0.0;
  var lastWasCurve = false;
  var startX = 0.0;
  var startY = 0.0;
  String? cmd;

  double next() => tokens[i++].number;

  while (i < tokens.length) {
    final token = tokens[i];
    if (token.isCommand) {
      cmd = token.command;
      i++;
    } else if (cmd == 'M') {
      // A repeated coordinate pair after a moveto is an implicit lineto.
      cmd = 'L';
    } else if (cmd == 'm') {
      cmd = 'l';
    }
    if (cmd == null) break;

    switch (cmd) {
      case 'M':
        x = next();
        y = next();
        path.moveTo(x, y);
        startX = x;
        startY = y;
        lastWasCurve = false;
      case 'm':
        x += next();
        y += next();
        path.moveTo(x, y);
        startX = x;
        startY = y;
        lastWasCurve = false;
      case 'L':
        x = next();
        y = next();
        path.lineTo(x, y);
        lastWasCurve = false;
      case 'l':
        x += next();
        y += next();
        path.lineTo(x, y);
        lastWasCurve = false;
      case 'H':
        x = next();
        path.lineTo(x, y);
        lastWasCurve = false;
      case 'h':
        x += next();
        path.lineTo(x, y);
        lastWasCurve = false;
      case 'V':
        y = next();
        path.lineTo(x, y);
        lastWasCurve = false;
      case 'v':
        y += next();
        path.lineTo(x, y);
        lastWasCurve = false;
      case 'C':
      case 'c':
        final rel = cmd == 'c';
        final c1x = (rel ? x : 0) + next();
        final c1y = (rel ? y : 0) + next();
        final c2x = (rel ? x : 0) + next();
        final c2y = (rel ? y : 0) + next();
        final ex = (rel ? x : 0) + next();
        final ey = (rel ? y : 0) + next();
        path.cubicTo(c1x, c1y, c2x, c2y, ex, ey);
        lastC1x = c2x;
        lastC1y = c2y;
        x = ex;
        y = ey;
        lastWasCurve = true;
      case 'S':
      case 's':
        final rel = cmd == 's';
        // With no preceding curve the first control point is the current
        // point, per the SVG spec.
        final c1x = lastWasCurve ? 2 * x - lastC1x : x;
        final c1y = lastWasCurve ? 2 * y - lastC1y : y;
        final c2x = (rel ? x : 0) + next();
        final c2y = (rel ? y : 0) + next();
        final ex = (rel ? x : 0) + next();
        final ey = (rel ? y : 0) + next();
        path.cubicTo(c1x, c1y, c2x, c2y, ex, ey);
        lastC1x = c2x;
        lastC1y = c2y;
        x = ex;
        y = ey;
        lastWasCurve = true;
      case 'Z':
      case 'z':
        path.close();
        x = startX;
        y = startY;
        lastWasCurve = false;
      default:
        // An unsupported command would otherwise spin here forever reading
        // the same token. Nothing in the data above reaches this.
        return path;
    }
  }
  return path;
}

class _Token {
  const _Token.command(this.command) : number = 0;
  const _Token.number(this.number) : command = null;

  final String? command;
  final double number;

  bool get isCommand => command != null;
}

List<_Token> _tokenize(String d) {
  final tokens = <_Token>[];
  final buffer = StringBuffer();

  void flush() {
    if (buffer.isEmpty) return;
    tokens.add(_Token.number(double.parse(buffer.toString())));
    buffer.clear();
  }

  for (var i = 0; i < d.length; i++) {
    final c = d[i];
    if (RegExp(r'[A-Za-z]').hasMatch(c)) {
      flush();
      tokens.add(_Token.command(c));
    } else if (c == ' ' || c == ',' || c == '\n' || c == '\t') {
      flush();
    } else if (c == '-' && buffer.isNotEmpty && !buffer.toString().endsWith('e')) {
      // A minus with digits already buffered starts the NEXT number: SVG
      // path data writes "24-5" for two values, with no separator.
      flush();
      buffer.write(c);
    } else if (c == '.' && buffer.toString().contains('.')) {
      // Likewise ".5.5" is two numbers, not one malformed one.
      flush();
      buffer.write(c);
    } else {
      buffer.write(c);
    }
  }
  flush();
  return tokens;
}
