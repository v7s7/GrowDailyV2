import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/theme_preset.dart';
import '../../core/utils/ramadan_calendar.dart';
import 'app_icon_art.dart';

/// The Home Screen icon is a plant SHAPE in a COLOUR, chosen separately.
///
/// Designed on the "GrowDaily App Icons" canvas and decided by Aziz on
/// 2026-09-25: the Night family (a deep ground, a light sprout, the same
/// recipe as the shipped icon), a colour per theme plus five for custom
/// themes, and a plant that grows with someone's full days. Growing shapes
/// are free for everyone; colours follow the themes' own split (the two free
/// themes' colours are free, everything else Premium). One seasonal icon
/// besides: Ramadan, open to everyone during Ramadan ([AppIconChoice.ramadan]).
///
/// iPhone only. Android has no API for this (launcher activity-alias swaps,
/// which close the app or drop the icon off some home screens), and the web
/// has no Home Screen icon to change.
///
/// Every shape x colour is a real icon set in the app bundle (see
/// tool/icons/make_alternate_icons.py); iOS cannot draw a new one on the
/// phone, which is why a custom theme takes the NEAREST colour rather than
/// its own two.
enum PlantShape {
  seedling(0),
  sprout(0),
  grown(30),
  bloom(90);

  const PlantShape(this.daysNeeded);

  /// Full days that open this shape: days that reached 80% of their habits
  /// (see plantFullDaysProvider), counted over all time and never needing to
  /// be in a row. Aziz, 2026-09-25: the plant should grow with what someone
  /// achieves, not with days that merely passed, and "not only a streak,
  /// just achieve"; the bloom at 90. The first two are there from the first
  /// day.
  final int daysNeeded;

  String label(S s) => switch (this) {
        PlantShape.seedling => s.appIconShapeSeedling,
        PlantShape.sprout => s.appIconShapeSprout,
        PlantShape.grown => s.appIconShapeGrown,
        PlantShape.bloom => s.appIconShapeBloom,
      };

  /// The shape as it reads inside a sentence («النبتة الكبيرة بعد 18 يومًا
  /// كاملًا»). Only the two that are ever still ahead of someone need one.
  String labelInSentence(S s) => switch (this) {
        PlantShape.grown => s.appIconShapeGrownInSentence,
        PlantShape.bloom => s.appIconShapeBloomInSentence,
        _ => label(s),
      };
}

/// Where a colour sits in the picker, which is also what it costs.
enum IconColourTier { free, premium, more }

@immutable
class IconColour {
  const IconColour._(this.id, this.tier);

  /// A theme preset id for the first eleven, a colour word for the rest.
  final String id;
  final IconColourTier tier;

  bool get needsPremium => tier != IconColourTier.free;
  Color get ground => appIconGround(id);
  Color get sprout => appIconSprout(id);

  String label(S s) {
    switch (id) {
      case 'emerald_gold':
        return s.appIconColourOriginal;
      case 'red':
        return s.appIconColourRed;
      case 'yellow':
        return s.appIconColourYellow;
      case 'green':
        return s.appIconColourGreen;
      case 'brown':
        return s.appIconColourBrown;
      case 'grey':
        return s.appIconColourGrey;
    }
    final preset = ThemePresets.byId(id);
    return s.isAr ? preset.nameAr : preset.nameEn;
  }
}

/// The five colours no theme has, so every custom theme lands somewhere
/// close. Premium, like the custom theme itself.
const List<String> kExtraIconColourIds = [
  'red',
  'yellow',
  'green',
  'brown',
  'grey',
];

/// All sixteen, in picker order: the free themes' colours, the Premium
/// themes', then the extra five. Built from [ThemePresets] so a preset's
/// free/Premium flag is the one place that decides its icon's price.
final List<IconColour> kIconColours = [
  for (final p in ThemePresets.free) IconColour._(p.id, IconColourTier.free),
  for (final p in ThemePresets.premium)
    IconColour._(p.id, IconColourTier.premium),
  for (final id in kExtraIconColourIds) IconColour._(id, IconColourTier.more),
];

IconColour iconColourById(String id) => kIconColours
    .firstWhere((c) => c.id == id, orElse: () => kIconColours.first);

/// The Ramadan icon's id: its icon set, its art, and the colourId it rides
/// in [AppIconChoice.ramadan]. Not one of [kIconColours]: it is a whole icon
/// of its own, never a colour for the other shapes.
const String kRamadanIconId = 'ramadan';

/// One icon: a shape in a colour, or the Ramadan icon.
@immutable
class AppIconChoice {
  const AppIconChoice(this.shape, this.colourId);

  /// The icon the app ships with. iOS calls it by no name at all.
  static const shipped = AppIconChoice(PlantShape.sprout, 'emerald_gold');

  /// The Ramadan icon, from the canvas's Ramadan board: the sprout in gold
  /// on a night sky under a crescent. Free for everyone, and pickable only
  /// while Ramadan is on ([RamadanIconWindow]); whoever picked it keeps it
  /// after, since the app never changes the icon on its own.
  static const ramadan = AppIconChoice(PlantShape.sprout, kRamadanIconId);

  final PlantShape shape;
  final String colourId;

  bool get isRamadan => colourId == kRamadanIconId;

  /// The colour, for a shape-and-colour icon. Never read it for [ramadan],
  /// which has no entry among the sixteen: ask [needsPremium] and
  /// [colourName] instead, which know about it.
  IconColour get colour => iconColourById(colourId);

  /// Whether putting this on the phone is Premium's. Ramadan's is everyone's.
  bool get needsPremium => !isRamadan && colour.needsPremium;

  /// What the icon is called beside its shape (the Settings row, the
  /// preview): the colour, or «رمضان».
  String colourName(S s) => isRamadan ? s.appIconRamadan : colour.label(s);

  /// The name of the icon set in the bundle, null for [shipped].
  String? get iosName => this == shipped
      ? null
      : isRamadan
          ? 'AppIcon-$kRamadanIconId'
          : 'AppIcon-${shape.name}-$colourId';

  /// Reads back what iOS reports. Anything unrecognised (a name from a
  /// later build, say) reads as the shipped icon, which is what the picker
  /// then offers to keep.
  static AppIconChoice fromIosName(String? name) {
    if (name == null || !name.startsWith('AppIcon-')) return shipped;
    if (name == ramadan.iosName) return ramadan;
    final rest = name.substring('AppIcon-'.length);
    final dash = rest.indexOf('-');
    if (dash < 0) return shipped;
    final shapeName = rest.substring(0, dash);
    final colourId = rest.substring(dash + 1);
    final shape = PlantShape.values.where((s) => s.name == shapeName);
    if (shape.isEmpty || !kIconColours.any((c) => c.id == colourId)) {
      return shipped;
    }
    return AppIconChoice(shape.first, colourId);
  }

  /// [s] in this icon's colour. The Ramadan icon has none of its own for
  /// the other shapes, so they come in the original colours.
  AppIconChoice withShape(PlantShape s) =>
      AppIconChoice(s, isRamadan ? shipped.colourId : colourId);
  AppIconChoice withColour(String id) => AppIconChoice(shape, id);

  @override
  bool operator ==(Object other) =>
      other is AppIconChoice &&
      other.shape == shape &&
      other.colourId == colourId;

  @override
  int get hashCode => Object.hash(shape, colourId);

  @override
  String toString() => iosName ?? 'AppIcon';
}

/// The icon colour that goes with a theme.
///
/// A built-in preset has its own colour. The custom theme has two colours
/// of its choosing, and iOS can only show icons that were built into the
/// app, so it takes the colour nearest its ACCENT ([nearestIconColour]):
/// the accent is what paints the buttons and highlights, the colour people
/// think of as "my theme".
String iconColourForTheme(String presetId, Color customAccent) {
  if (presetId == ThemePresets.customId) return nearestIconColour(customAccent);
  return kIconColours.any((c) => c.id == presetId) ? presetId : 'emerald_gold';
}

/// The icons a custom accent can land on, each keyed by the hue it was drawn
/// from: a theme's accent, or the sprout of one of the extra five.
///
/// Three theme colours are left out on purpose, because their icons are two
/// colours rather than one and a custom theme would read them as someone
/// else's: Rose & Ink (rose on ink), Monochrome (gold on charcoal) and Teal
/// (a green sprout on teal; a custom teal lands on Ocean, which is teal all
/// through). Grey and brown are caught before the hue is looked at, below.
const List<String> _kMatchableIds = [
  'emerald_gold',
  'baby_pink',
  'ocean',
  'amber_dusk',
  'nour_violet',
  'sage',
  'baby_blue',
  'navy',
  'red',
  'yellow',
  'green',
];

double _keyHue(String id) {
  final source = kExtraIconColourIds.contains(id)
      ? appIconSprout(id)
      : ThemePresets.byId(id).gold;
  return HSLColor.fromColor(source).hue;
}

/// Nearest of the sixteen to [accent], by hue.
///
/// Two cases come first because hue alone gets them wrong. A colour with
/// almost no saturation has a hue that means nothing (a grey's reported hue
/// is noise), so it is grey. And brown IS orange with the chroma pulled down
/// (the custom palette's own brown column says as much), so a low-saturation
/// orange is brown rather than Amber Dusk. The same thresholds were checked
/// against all nine columns of the custom palette on 2026-09-25.
String nearestIconColour(Color accent) {
  final hsl = HSLColor.fromColor(accent);
  if (hsl.saturation < 0.15) return 'grey';
  if (hsl.hue >= 15 && hsl.hue <= 45 && hsl.saturation < 0.5) return 'brown';
  String best = _kMatchableIds.first;
  var bestDistance = double.infinity;
  for (final id in _kMatchableIds) {
    final d = (_keyHue(id) - hsl.hue).abs();
    final distance = d > 180 ? 360 - d : d;
    if (distance < bestDistance) {
      best = id;
      bestDistance = distance;
    }
  }
  return best;
}

/// The furthest shape [fullDays] has opened.
PlantShape grownShapeFor(int fullDays) =>
    PlantShape.values.lastWhere((s) => fullDays >= s.daysNeeded);

/// The next shape still ahead, or null once all four are open.
PlantShape? nextShapeFor(int fullDays) {
  for (final s in PlantShape.values) {
    if (fullDays < s.daysNeeded) return s;
  }
  return null;
}

/// When the Ramadan icon can be picked: from the day before 1 Ramadan
/// through Eid al-Fitr's day, on the Umm al-Qura dates (ramadan_calendar.dart).
///
/// A day of room at each end because the Gulf, and most of the world,
/// starts and ends Ramadan by sighting the moon, a day either side of the
/// published calendar at most; opening on the eve also matches the month
/// itself, whose first night (the first تراويح) is the evening before its
/// first fast. Aziz, 2026-09-25: open to everyone in Ramadan, and shown
/// locked, "opens in Ramadan", the rest of the year.
class RamadanIconWindow {
  RamadanIconWindow._(this.dates)
      : opens = DateTime(
          dates.start.year,
          dates.start.month,
          dates.start.day - 1,
        ),
        closes = DateTime(dates.eid.year, dates.eid.month, dates.eid.day + 1);

  /// The window [now] is in, or the next one; null past the calendar's end.
  static RamadanIconWindow? at(DateTime now) {
    final dates = ramadanOnOrAfter(now);
    return dates == null ? null : RamadanIconWindow._(dates);
  }

  final RamadanDates dates;

  /// The first day it can be picked, a local midnight.
  final DateTime opens;

  /// The first day it can no longer be picked, a local midnight.
  final DateTime closes;

  bool isOpenAt(DateTime now) =>
      !now.isBefore(opens) && now.isBefore(closes);

  /// Calendar days from [now]'s date until it opens; 0 once it has.
  int daysUntilOpen(DateTime now) {
    // Counted between UTC dates, so a daylight-saving night in between
    // cannot make a day 23 hours long and round it away.
    final today = DateTime.utc(now.year, now.month, now.day);
    final open = DateTime.utc(opens.year, opens.month, opens.day);
    final days = open.difference(today).inDays;
    return days < 0 ? 0 : days;
  }
}
