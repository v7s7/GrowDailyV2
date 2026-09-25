import 'package:flutter/widgets.dart';

import 'app_icon_catalog.dart';

part 'app_icon_art.g.dart';

// The picker's previews, drawn from the same paths and colours the iOS icon
// sets were rendered from (app_icon_art.g.dart and the icon sets are both
// written by tool/icons/make_alternate_icons.py), so a tile can never show a
// plant the phone would not get.

/// A colour's ground, or a seasonal icon's (kRamadanIconId).
Color appIconGround(String colourId) => Color(
      _kSeasonalArt[colourId]?.ground ??
          (_kColourArt[colourId] ?? _kColourArt['emerald_gold']!).ground,
    );

Color appIconSprout(String colourId) => Color(
      _kSeasonalArt[colourId]?.sprout ??
          (_kColourArt[colourId] ?? _kColourArt['emerald_gold']!).sprout,
    );

/// A seasonal icon's own mark colour (Ramadan's crescent), null for the
/// sixteen colours, which have none.
Color? appIconMarkColour(String colourId) {
  final season = _kSeasonalArt[colourId];
  return season == null ? null : Color(season.markColour);
}

/// The shape a seasonal icon's art is drawn on, as the generator drew it.
String? appIconSeasonalShape(String colourId) => _kSeasonalArt[colourId]?.shape;

/// The bloom's flower: the sprout colour moved toward white, so one rule
/// works in all sixteen colours. The same sum the icon generator uses.
Color appIconFlower(String colourId) {
  final c = appIconSprout(colourId);
  int lift(double v) {
    final byte = (v * 255).round();
    return (byte + (255 - byte) * _kFlowerLift).round();
  }

  return Color.fromARGB(255, lift(c.r), lift(c.g), lift(c.b));
}

/// The iOS icon mask's corner, as a share of the side.
const double kAppIconCornerShare = 0.2237;

/// One Home Screen icon, drawn at [size] exactly as the phone shows it:
/// the ground clipped to iOS's continuous corner, the plant on top.
class AppIconArt extends StatelessWidget {
  const AppIconArt({super.key, required this.choice, required this.size});

  final AppIconChoice choice;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _AppIconPainter(choice)),
    );
  }
}

class _ShapePaths {
  const _ShapePaths(this.sprout, this.flower, this.eye);
  final List<Path> sprout;
  final Path? flower;
  final Path? eye;
}

final Map<PlantShape, _ShapePaths> _parsed = {};

_ShapePaths _pathsFor(PlantShape shape) => _parsed.putIfAbsent(shape, () {
      final art = _kShapeArt[shape.name]!;
      return _ShapePaths(
        [for (final d in art.sprout) _parse(d)],
        art.flower == null ? null : _parse(art.flower!),
        art.eye == null ? null : _parse(art.eye!),
      );
    });

final Map<String, Path> _marks = {};

Path? _markFor(String colourId) {
  final season = _kSeasonalArt[colourId];
  if (season == null) return null;
  return _marks.putIfAbsent(colourId, () => _parse(season.mark));
}

final RegExp _token = RegExp(r'[MLZ]|-?\d+(?:\.\d+)?');

/// The art is M/L/Z only (see the generator), so this is the whole parser.
Path _parse(String d) {
  final path = Path();
  final tokens = _token.allMatches(d).map((m) => m.group(0)!).toList();
  var i = 0;
  var command = 'M';
  while (i < tokens.length) {
    final t = tokens[i];
    if (t == 'Z') {
      path.close();
      i++;
      continue;
    }
    if (t == 'M' || t == 'L') {
      command = t;
      i++;
      continue;
    }
    final x = double.parse(tokens[i]);
    final y = double.parse(tokens[i + 1]);
    i += 2;
    if (command == 'M') {
      path.moveTo(x, y);
      command = 'L';
    } else {
      path.lineTo(x, y);
    }
  }
  return path;
}

class _AppIconPainter extends CustomPainter {
  _AppIconPainter(this.choice);

  final AppIconChoice choice;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.save();
    canvas.clipRSuperellipse(
      RSuperellipse.fromRectAndRadius(
        rect,
        Radius.circular(size.shortestSide * kAppIconCornerShare),
      ),
    );
    final ground = appIconGround(choice.colourId);
    canvas.drawRect(rect, Paint()..color = ground);
    canvas.scale(size.width / 1024, size.height / 1024);
    final paths = _pathsFor(choice.shape);
    final sprout = Paint()
      ..color = appIconSprout(choice.colourId)
      ..isAntiAlias = true;
    for (final p in paths.sprout) {
      canvas.drawPath(p, sprout);
    }
    if (paths.flower != null) {
      canvas.drawPath(
        paths.flower!,
        Paint()..color = appIconFlower(choice.colourId),
      );
    }
    if (paths.eye != null) {
      canvas.drawPath(paths.eye!, Paint()..color = ground);
    }
    final mark = _markFor(choice.colourId);
    if (mark != null) {
      canvas.drawPath(
        mark,
        Paint()..color = appIconMarkColour(choice.colourId)!,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_AppIconPainter old) => old.choice != choice;
}
