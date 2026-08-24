/// HSV/RGB maths, shared by everything in the app that lets somebody choose
/// a colour.
///
/// It lives in core rather than beside the first picker that needed it
/// because there are now three callers with nothing else in common: the
/// habit icon picker, the Matrix quadrant colours, and the custom theme's
/// own readability guard, which has to solve for a luminance band in HSV
/// VALUE (see [fitPickerColour]). A second copy of this maths would be a
/// second copy to get subtly wrong, and the wrong one would be silent.
///
/// Deliberately hand-rolled rather than reading components back off a
/// [Color] (.value/.red/.green/.blue, or the newer .r/.g/.b doubles) — which
/// half of that API is "the" one changes across Flutter versions, and this
/// file has no way to know which this app is actually building against.
/// Every [Color] here is only ever *constructed* via the plain
/// `Color(0xAARRGGBB)` int constructor, which has never changed; the actual
/// picking math works entirely in plain ints/doubles instead.
library;

import 'package:flutter/material.dart';

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

