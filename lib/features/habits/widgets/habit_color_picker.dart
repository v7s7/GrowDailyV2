import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';

// ─── HSV/RGB math ───────────────────────────────────────────────────────────
//
// Deliberately hand-rolled rather than reading components back off a
// [Color] (.value/.red/.green/.blue, or the newer .r/.g/.b doubles) — which
// half of that API is "the" one changes across Flutter versions, and this
// file has no way to know which this app is actually building against.
// Every [Color] here is only ever *constructed* via the plain
// `Color(0xAARRGGBB)` int constructor, which has never changed; the actual
// picking math works entirely in plain ints/doubles instead.

/// Standard HSV → RGB, packed as an 0xFFRRGGBB int ready for [Color.new].
int hsvToArgb(double hue, double saturation, double value) {
  final h = hue % 360;
  final c = value * saturation;
  final hh = h / 60;
  final x = c * (1 - ((hh % 2) - 1).abs());
  double r, g, b;
  if (hh < 1) {
    r = c;
    g = x;
    b = 0;
  } else if (hh < 2) {
    r = x;
    g = c;
    b = 0;
  } else if (hh < 3) {
    r = 0;
    g = c;
    b = x;
  } else if (hh < 4) {
    r = 0;
    g = x;
    b = c;
  } else if (hh < 5) {
    r = x;
    g = 0;
    b = c;
  } else {
    r = c;
    g = 0;
    b = x;
  }
  final m = value - c;
  final ri = (((r + m) * 255).round()).clamp(0, 255);
  final gi = (((g + m) * 255).round()).clamp(0, 255);
  final bi = (((b + m) * 255).round()).clamp(0, 255);
  return 0xFF000000 | (ri << 16) | (gi << 8) | bi;
}

/// Inverse of [hsvToArgb] — used to move the picker's thumbs to match
/// whatever the user just typed into the hex field.
(double hue, double saturation, double value) argbToHsv(int argb) {
  final r = (argb >> 16 & 0xFF) / 255;
  final g = (argb >> 8 & 0xFF) / 255;
  final b = (argb & 0xFF) / 255;
  final maxC = [r, g, b].reduce((a, bb) => a > bb ? a : bb);
  final minC = [r, g, b].reduce((a, bb) => a < bb ? a : bb);
  final delta = maxC - minC;
  double h;
  if (delta == 0) {
    h = 0;
  } else if (maxC == r) {
    h = 60 * (((g - b) / delta) % 6);
  } else if (maxC == g) {
    h = 60 * (((b - r) / delta) + 2);
  } else {
    h = 60 * (((r - g) / delta) + 4);
  }
  if (h < 0) h += 360;
  final s = maxC == 0 ? 0.0 : delta / maxC;
  return (h, s, maxC);
}

// ─── Public entry point ─────────────────────────────────────────────────────

/// Opens the icon-color picker sheet and resolves to:
/// - a 6-digit hex string (no `#`), when the user picks a color and taps
///   Done;
/// - `''` (empty string), when the user taps "Use default color" — an
///   explicit request to clear any override, distinct from just closing the
///   sheet without changing anything;
/// - `null`, when the sheet is dismissed (back gesture/tap-outside) without
///   choosing either action.
///
/// [initialHex] seeds the picker with the habit's current custom color
/// (pass null for a habit that doesn't have one yet — the picker opens on a
/// friendly default instead of black).
///
/// [title]/[subtitle] override the sheet's heading text — despite the
/// function name (kept for the habit call site that made this first,
/// habit_icon_color / habit_icon_color_hint), the picker itself has no
/// habit-specific logic, so any other feature needing a color picker
/// (e.g. Matrix's quadrant customization) can reuse this same sheet by
/// passing its own wording here instead of forking a near-duplicate file.
Future<String?> showHabitColorPicker(
  BuildContext context, {
  String? initialHex,
  String? title,
  String? subtitle,
}) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => _HabitColorPickerSheet(
      initialHex: initialHex,
      title: title,
      subtitle: subtitle,
    ),
  );
}

class _HabitColorPickerSheet extends StatefulWidget {
  final String? initialHex;
  final String? title;
  final String? subtitle;
  const _HabitColorPickerSheet({this.initialHex, this.title, this.subtitle});

  @override
  State<_HabitColorPickerSheet> createState() =>
      _HabitColorPickerSheetState();
}

class _HabitColorPickerSheetState extends State<_HabitColorPickerSheet> {
  // Same warm gold the app's own default (Emerald & Gold) accent uses — a
  // friendly, on-brand starting point for a habit that has no color of its
  // own yet, rather than opening on black/red.
  static const int _fallbackSeedArgb = 0xFFE4B45F;

  late double _hue;
  late double _sat;
  late double _val;
  late final TextEditingController _hexCtrl;
  bool _updatingFromPicker = false;

  @override
  void initState() {
    super.initState();
    final raw = widget.initialHex;
    final seedArgb = raw != null && raw.length == 6
        ? 0xFF000000 | (int.tryParse(raw, radix: 16) ?? _fallbackSeedArgb)
        : _fallbackSeedArgb;
    final hsv = argbToHsv(seedArgb);
    _hue = hsv.$1;
    _sat = hsv.$2;
    _val = hsv.$3;
    _hexCtrl = TextEditingController(text: _currentHex);
  }

  @override
  void dispose() {
    _hexCtrl.dispose();
    super.dispose();
  }

  int get _currentArgb => hsvToArgb(_hue, _sat, _val);
  String get _currentHex =>
      _currentArgb.toRadixString(16).substring(2).toUpperCase();

  void _syncHexField() {
    _updatingFromPicker = true;
    _hexCtrl.value = TextEditingValue(
      text: _currentHex,
      selection: TextSelection.collapsed(offset: _currentHex.length),
    );
    _updatingFromPicker = false;
  }

  void _onHexChanged(String text) {
    if (_updatingFromPicker) return;
    final cleaned = text.replaceAll('#', '').trim();
    if (cleaned.length != 6) return;
    final parsed = int.tryParse(cleaned, radix: 16);
    if (parsed == null) return;
    final hsv = argbToHsv(0xFF000000 | parsed);
    setState(() {
      _hue = hsv.$1;
      _sat = hsv.$2;
      _val = hsv.$3;
    });
  }

  void _onSatValPan(Offset local, Size size) {
    final s = (local.dx / size.width).clamp(0.0, 1.0);
    final v = (1 - local.dy / size.height).clamp(0.0, 1.0);
    setState(() {
      _sat = s;
      _val = v;
    });
    _syncHexField();
  }

  void _onHuePan(double dx, double width) {
    final h = (dx / width).clamp(0.0, 1.0) * 360;
    setState(() => _hue = h);
    _syncHexField();
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final current = Color(_currentArgb);

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        decoration: BoxDecoration(
          color: gp.surfaceHigh,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: gp.border, width: 0.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: gp.border,
                  borderRadius: BorderRadius.circular(100),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: current,
                    shape: BoxShape.circle,
                    border: Border.all(color: gp.border, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: current.withOpacity(0.4),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title ?? s.habitIconColor,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: gp.textPrimary,
                        ),
                      ),
                      Text(
                        widget.subtitle ?? s.habitIconColorHint,
                        style: TextStyle(fontSize: 11.5, color: gp.textSec),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            // Saturation (x) / Value (y) field for the current hue.
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = Size(constraints.maxWidth, 180);
                  return GestureDetector(
                    onPanDown: (d) => _onSatValPan(d.localPosition, size),
                    onPanUpdate: (d) => _onSatValPan(d.localPosition, size),
                    child: SizedBox(
                      width: size.width,
                      height: size.height,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                colors: [
                                  Colors.white,
                                  Color(hsvToArgb(_hue, 1, 1)),
                                ],
                              ),
                            ),
                          ),
                          Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.transparent, Colors.black],
                              ),
                            ),
                          ),
                          Positioned(
                            left: (_sat * size.width) - 9,
                            top: ((1 - _val) * size.height) - 9,
                            child: _ThumbDot(color: current),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            // Hue slider.
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                return GestureDetector(
                  onPanDown: (d) => _onHuePan(d.localPosition.dx, width),
                  onPanUpdate: (d) => _onHuePan(d.localPosition.dx, width),
                  child: SizedBox(
                    width: width,
                    height: 26,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          height: 14,
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(7),
                            gradient: LinearGradient(
                              colors: [
                                for (var i = 0; i <= 360; i += 60)
                                  Color(hsvToArgb(i.toDouble(), 1, 1)),
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          left: (_hue / 360 * width) - 9,
                          top: -2,
                          child: _ThumbDot(
                            color: Color(hsvToArgb(_hue, 1, 1)),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Text(
                  '#',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: gp.textSec,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: TextField(
                    controller: _hexCtrl,
                    onChanged: _onHexChanged,
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 6,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]')),
                    ],
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: gp.textPrimary,
                    ),
                    decoration: InputDecoration(
                      counterText: '',
                      isDense: true,
                      labelText: s.hexCode,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      Navigator.pop(context, '');
                    },
                    child: Text(s.useDefaultColor),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      HapticFeedback.mediumImpact();
                      Navigator.pop(context, _currentHex);
                    },
                    child: Text(s.colorPickerDone),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The small draggable circle on both the saturation/value box and the hue
/// bar — a white ring + soft shadow so it stays visible against literally
/// any color underneath it, including near-white and near-black picks.
class _ThumbDot extends StatelessWidget {
  final Color color;
  const _ThumbDot({required this.color});

  @override
  Widget build(BuildContext context) => Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.5),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 4),
          ],
        ),
      );
}
