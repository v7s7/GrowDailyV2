import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/game_theme.dart';

/// Which of step 3's two reminders a [ReminderKindCard] offers.
enum ReminderKind { clock, prayer }

/// One of step 3's two choices, «على ساعة معيّنة» or «مع وقت صلاة», as a
/// card with a small scene over its label: a clock face, or a mosque on the
/// horizon under a crescent and a few stars (the "Reminder choice redesign"
/// canvas, style 2; Aziz, 2026-10-01: "this is perfect ... it should work
/// with light mode also"). It replaced a 22pt outline icon over the label.
///
/// The scene is drawn rather than a picture so it takes the theme's own
/// colours: the accent's readable ink for its lines in either brightness,
/// the accent's tint for its fills, and the theme's gold for the crescent.
/// Picked, the lines go full strength, the card takes the accent's tint and
/// a check sits in its corner.
class ReminderKindCard extends StatelessWidget {
  const ReminderKindCard({
    super.key,
    required this.kind,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final ReminderKind kind;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(18);
    final accent = GameColors.gold;
    final colors = _SceneColors(
      line: selected ? gp.goldInk : gp.goldInk.withOpacity(0.78),
      fill: accent.withOpacity(selected ? 0.26 : (dark ? 0.16 : 0.12)),
      detail: gp.textPrimary,
      faint: gp.textTert,
      gold: gp.iconGold,
      ground: selected ? gp.goldInk : gp.goldInk.withOpacity(0.55),
      panel: selected
          ? Color.alphaBlend(accent.withOpacity(0.10), gp.bg)
          : gp.bg,
    );
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: AnimatedContainer(
            duration: GameMotion.quick,
            height: 152,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: selected ? accent.withOpacity(0.12) : gp.surface,
              borderRadius: radius,
              border: Border.all(
                color: selected ? accent.withOpacity(0.7) : gp.border,
                width: selected ? 1.5 : 0.5,
              ),
            ),
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: ExcludeSemantics(
                        child: AnimatedContainer(
                          duration: GameMotion.quick,
                          decoration: BoxDecoration(
                            color: colors.panel,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: switch (kind) {
                            ReminderKind.clock => Center(
                                child: CustomPaint(
                                  size: const Size(66, 66),
                                  painter: _ClockScene(colors),
                                ),
                              ),
                            ReminderKind.prayer => Align(
                                alignment: Alignment.bottomCenter,
                                child: FittedBox(
                                  fit: BoxFit.contain,
                                  child: CustomPaint(
                                    size: const Size(150, 80),
                                    painter: _MosqueScene(colors),
                                  ),
                                ),
                              ),
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: selected ? gp.goldInk : gp.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                ),
                PositionedDirectional(
                  top: 6,
                  end: 6,
                  child: AnimatedScale(
                    scale: selected ? 1 : 0,
                    duration: GameMotion.quick,
                    curve: Curves.easeOutBack,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.check_rounded,
                        size: 15,
                        color: GameColors.onGold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SceneColors {
  const _SceneColors({
    required this.line,
    required this.fill,
    required this.detail,
    required this.faint,
    required this.gold,
    required this.ground,
    required this.panel,
  });

  /// The shapes' outlines.
  final Color line;

  /// Inside the shapes.
  final Color fill;

  /// The clock's hands and the mosque's door.
  final Color detail;

  /// The clock's hour marks and the stars.
  final Color faint;

  /// The crescent.
  final Color gold;

  /// The horizon under the mosque.
  final Color ground;

  /// The scene's own panel, which the crescent is cut from.
  final Color panel;

  bool same(_SceneColors o) =>
      line == o.line &&
      fill == o.fill &&
      detail == o.detail &&
      faint == o.faint &&
      gold == o.gold &&
      ground == o.ground &&
      panel == o.panel;
}

Paint _stroke(Color color, double width) => Paint()
  ..color = color
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

Paint _fill(Color color) => Paint()..color = color;

/// A clock face with its four hour marks, the hands at ten past twelve and a
/// dot at the centre, drawn in a 66 x 66 box.
class _ClockScene extends CustomPainter {
  const _ClockScene(this.c);
  final _SceneColors c;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 66, size.height / 66);
    const center = Offset(33, 33);
    canvas.drawCircle(center, 26, _fill(c.fill));
    canvas.drawCircle(center, 26, _stroke(c.line, 2.5));
    final marks = _stroke(c.faint, 2.5);
    for (var i = 0; i < 4; i++) {
      final a = i * math.pi / 2;
      final dir = Offset(math.sin(a), -math.cos(a));
      canvas.drawLine(center + dir * 18, center + dir * 22, marks);
    }
    final hands = _stroke(c.detail, 3);
    canvas.drawLine(center, const Offset(33, 20), hands);
    canvas.drawLine(center, const Offset(42, 39), hands);
    canvas.drawCircle(center, 3, _fill(c.line));
  }

  @override
  bool shouldRepaint(_ClockScene old) => !c.same(old.c);
}

/// A domed mosque between two minarets, its arched door, a crescent and
/// three stars above, on a line of horizon, drawn in a 150 x 80 box that
/// sits on the panel's bottom edge.
class _MosqueScene extends CustomPainter {
  const _MosqueScene(this.c);
  final _SceneColors c;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 150, size.height / 80);

    // The crescent: a disc with a smaller one taken out of it.
    final moon = Path.combine(
      PathOperation.difference,
      Path()..addOval(Rect.fromCircle(center: const Offset(112, 18), radius: 8)),
      Path()..addOval(Rect.fromCircle(center: const Offset(116, 15), radius: 7)),
    );
    canvas.drawPath(moon, _fill(c.gold));
    final star = _fill(c.faint);
    canvas.drawCircle(const Offset(36, 16), 1.4, star);
    canvas.drawCircle(const Offset(58, 9), 1.1, star);
    canvas.drawCircle(const Offset(88, 26), 1.1, star);

    final line = _stroke(c.line, 2.5);
    final body = Path()
      ..moveTo(44, 76)
      ..lineTo(44, 54)
      ..arcToPoint(
        const Offset(106, 54),
        radius: const Radius.elliptical(31, 24),
      )
      ..lineTo(106, 76)
      ..close();
    canvas.drawPath(body, _fill(c.fill));
    canvas.drawPath(body, line);
    for (final x in const [20.0, 122.0]) {
      final minaret = Rect.fromLTRB(x, 34, x + 8, 76);
      canvas.drawRect(minaret, _fill(c.fill));
      canvas.drawRect(minaret, line);
      canvas.drawLine(Offset(x + 4, 34), Offset(x + 4, 26), line);
    }
    final door = Path()
      ..moveTo(68, 77)
      ..lineTo(68, 64)
      ..arcToPoint(const Offset(82, 64), radius: const Radius.circular(7))
      ..lineTo(82, 77);
    canvas.drawPath(door, _fill(c.panel));
    canvas.drawPath(door, _stroke(c.detail, 2.5));
    canvas.drawLine(
      const Offset(0, 77.5),
      const Offset(150, 77.5),
      _stroke(c.ground, 3),
    );
  }

  @override
  bool shouldRepaint(_MosqueScene old) => !c.same(old.c);
}
