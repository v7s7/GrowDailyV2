import 'package:flutter/material.dart';

/// A selectable app-wide color scheme, built around two color roles per
/// preset — **accent** (`gold`) and **grid/success** (`emerald`) — plus two
/// "touches" (a tint or shade) that follow the accent: `xpBlue` is the
/// accent hue pushed into a deeper, richer shade; `streakOrange` is the
/// accent hue pushed into a lighter, softer tint. Every structural neutral
/// in both light mode and dark mode (background, card surfaces, borders,
/// body text) is itself tinted from the accent and emerald hues, so the
/// whole look — background, grid, buttons, highlights — traces back to
/// this preset's own colors, not a scattered palette. The only things that
/// stay fixed across every preset are `error`/`warning` (so "something's
/// wrong" never gets ambiguous) and illustrated art (app icon, splash,
/// onboarding art, category glyphs) — those have colors baked into the
/// actual PNGs, so a preset only restyles UI chrome, not artwork.
///
/// `emerald` started out as always a second, independent hue reserved for
/// the grid ("the goal is to fill the week with green," in the original
/// design). Most presets still work that way — it's a genuinely different
/// color from the accent, just tuned so it doesn't blend into gold/xpBlue/
/// streakOrange (see e.g. Sage's and Teal's doc comments below). A few
/// presets instead let `emerald` be a punchier, more saturated expression
/// of the *same* hue as their own `gold` — Ocean, Rose & Ink, Nour Violet,
/// Baby Blue, Baby Pink, and Navy — so completing a habit colors the grid
/// in that preset's own signature color rather than a green that would
/// clash with (or just feel disconnected from) the rest of the theme. Any
/// user-facing copy that names a color (grid/heatmap labels, achievement
/// text) was written to stay color-neutral for exactly this reason — see
/// AppStrings.gridGreenSquares and the greenSquares achievements.
///
/// Each preset's dark-mode structural colors are tinted toward its own
/// emerald, and its light-mode structural colors toward its own accent —
/// mirroring the original "Emerald & Gold" preset's own design, where both
/// signature hues run through the whole app rather than living only in
/// buttons. Body text does the reverse crossover (dark-mode text picks up
/// the accent hue, light-mode text picks up the emerald hue) so the two
/// colors stay woven through every screen without ever competing on the
/// same surface. This still holds even for the single-hue presets above —
/// "two hues" there just happen to be two shades of one color rather than
/// two different colors.
class ThemePreset {
  final String id;
  final String nameEn;
  final String nameAr;
  final bool isPremium;

  // Accent colors — shared between light and dark.
  final Color gold;
  final Color goldDim;
  final Color xpBlue;
  final Color xpBlueDim;
  final Color streakOrange;
  final Color streakOrangeDim;

  // Grid green — habit completions, heatmap, streak success. Shared
  // between light and dark, same as the accent trio above.
  final Color emerald;
  final Color emeraldDim;

  // Light-mode structural neutrals.
  final Color lightBg;
  final Color lightSurface;
  final Color lightSurfaceHigh;
  final Color lightSurfaceHL;
  final Color lightBorder;
  final Color lightDivider;
  final Color lightTextPrimary;
  final Color lightTextSecondary;
  final Color lightTextTertiary;

  // Dark-mode structural neutrals.
  final Color darkBg;
  final Color darkSurface;
  final Color darkSurfaceElevated;
  final Color darkSurfaceHighlight;
  final Color darkBorder;
  final Color darkDivider;
  final Color darkTextPrimary;
  final Color darkTextSecondary;
  final Color darkTextTertiary;

  const ThemePreset({
    required this.id,
    required this.nameEn,
    required this.nameAr,
    required this.isPremium,
    required this.gold,
    required this.goldDim,
    required this.xpBlue,
    required this.xpBlueDim,
    required this.streakOrange,
    required this.streakOrangeDim,
    required this.emerald,
    required this.emeraldDim,
    required this.lightBg,
    required this.lightSurface,
    required this.lightSurfaceHigh,
    required this.lightSurfaceHL,
    required this.lightBorder,
    required this.lightDivider,
    required this.lightTextPrimary,
    required this.lightTextSecondary,
    required this.lightTextTertiary,
    required this.darkBg,
    required this.darkSurface,
    required this.darkSurfaceElevated,
    required this.darkSurfaceHighlight,
    required this.darkBorder,
    required this.darkDivider,
    required this.darkTextPrimary,
    required this.darkTextSecondary,
    required this.darkTextTertiary,
  });
}

/// The original, free-for-everyone look — warm gold + emerald, in both
/// light (cream) and dark (near-black forest) form. Every value here is
/// byte-identical to the previous hardcoded constants, so nobody's app
/// changes underneath them by default.
const _emeraldGold = ThemePreset(
  id: 'emerald_gold',
  nameEn: 'Emerald & Gold',
  nameAr: 'زمردي وذهبي',
  isPremium: false,
  gold: Color(0xFFE4B45F),
  goldDim: Color(0xFF9C7436),
  // xpBlue/streakOrange are touches of gold's own hue (deeper shade / lighter
  // tint), not independent blue/orange hues — see the class doc comment.
  xpBlue: Color(0xFFE49F25),
  xpBlueDim: Color(0xFF8F6925),
  streakOrange: Color(0xFFE0BC7A),
  streakOrangeDim: Color(0xFFAD853F),
  emerald: Color(0xFF2ECF8F),
  emeraldDim: Color(0xFF188A61),
  lightBg: Color(0xFFFFFCF5),
  lightSurface: Color(0xFFF5EFE3),
  lightSurfaceHigh: Colors.white,
  lightSurfaceHL: Color(0xFFEADFCB),
  lightBorder: Color(0xFFD8CDBA),
  lightDivider: Color(0xFFE8DDCB),
  lightTextPrimary: Color(0xFF18251F),
  lightTextSecondary: Color(0xFF657166),
  lightTextTertiary: Color(0xFF9AA397),
  darkBg: Color(0xFF07100D),
  darkSurface: Color(0xFF101B17),
  darkSurfaceElevated: Color(0xFF17251F),
  darkSurfaceHighlight: Color(0xFF20332B),
  darkBorder: Color(0xFF2D4037),
  darkDivider: Color(0xFF22352D),
  darkTextPrimary: Color(0xFFF7F3E8),
  darkTextSecondary: Color(0xFFB5BCA8),
  darkTextTertiary: Color(0xFF6F7A70),
);

/// A cooler, calmer teal/blue take with a true-white light mode — the most
/// direct answer to "gold on cream feels muted in light mode." Dark mode
/// swaps the default's forest undertone for a blue-black deep-sea one.
/// Signature-color preset (see the class doc comment): the grid's
/// "complete" color is this same teal hue, pushed brighter and more
/// saturated than the accent, rather than a separate green — a completed
/// square reads as "more Ocean," not "a different theme peeking through."
const _ocean = ThemePreset(
  id: 'ocean',
  nameEn: 'Ocean',
  nameAr: 'المحيط',
  isPremium: true,
  gold: Color(0xFF2FA8A0),
  goldDim: Color(0xFF1F7973),
  xpBlue: Color(0xFF228F88),
  xpBlueDim: Color(0xFF205854),
  streakOrange: Color(0xFF3CB1A9),
  streakOrangeDim: Color(0xFF336E6A),
  emerald: Color(0xFF2ECFC4),
  emeraldDim: Color(0xFF188A82),
  lightBg: Color(0xFFF7FAFB),
  lightSurface: Colors.white,
  lightSurfaceHigh: Colors.white,
  lightSurfaceHL: Color(0xFFE7F1F2),
  lightBorder: Color(0xFFD7E4E6),
  lightDivider: Color(0xFFE3EEEF),
  lightTextPrimary: Color(0xFF122327),
  lightTextSecondary: Color(0xFF5C7278),
  lightTextTertiary: Color(0xFF94A6AA),
  darkBg: Color(0xFF07100E),
  darkSurface: Color(0xFF101B19),
  darkSurfaceElevated: Color(0xFF172522),
  darkSurfaceHighlight: Color(0xFF20332F),
  darkBorder: Color(0xFF2D403C),
  darkDivider: Color(0xFF223531),
  darkTextPrimary: Color(0xFFE8F7F6),
  darkTextSecondary: Color(0xFFA8BCBB),
  darkTextTertiary: Color(0xFF6F7A7A),
);

/// Warm rose accent on a cool near-white base — the biggest structural
/// departure from the default's cream warmth, for anyone who wants light
/// mode to actually feel bright and crisp rather than warm and muted. Dark
/// mode picks up a plum-black undertone instead of forest. Signature-color
/// preset (see the class doc comment): the grid's "complete" color is a
/// deeper, more magenta-leaning rose than the accent — distinct enough
/// from the fixed error-red at a glance, and from the softer accent gold —
/// rather than a separate green.
const _roseInk = ThemePreset(
  id: 'rose_ink',
  nameEn: 'Rose & Ink',
  nameAr: 'وردي وحبر',
  isPremium: true,
  gold: Color(0xFFE0637E),
  goldDim: Color(0xFFA83F55),
  xpBlue: Color(0xFFDF2A51),
  xpBlueDim: Color(0xFF8C283E),
  streakOrange: Color(0xFFDD7D92),
  streakOrangeDim: Color(0xFFAA4258),
  emerald: Color(0xFFCF2E8C),
  emeraldDim: Color(0xFF8A185A),
  lightBg: Color(0xFFFDFAFB),
  lightSurface: Colors.white,
  lightSurfaceHigh: Colors.white,
  lightSurfaceHL: Color(0xFFF7E9ED),
  lightBorder: Color(0xFFEBDBDF),
  lightDivider: Color(0xFFF1E4E7),
  lightTextPrimary: Color(0xFF211419),
  lightTextSecondary: Color(0xFF6E5A61),
  lightTextTertiary: Color(0xFFA6979C),
  darkBg: Color(0xFF07100B),
  darkSurface: Color(0xFF101B15),
  darkSurfaceElevated: Color(0xFF17251E),
  darkSurfaceHighlight: Color(0xFF20332A),
  darkBorder: Color(0xFF2D4037),
  darkDivider: Color(0xFF22352C),
  darkTextPrimary: Color(0xFFF7E8EB),
  darkTextSecondary: Color(0xFFBCA8AC),
  darkTextTertiary: Color(0xFF7A6F71),
);

/// Charcoal + gold only — the most muted preset in the set. Every
/// structural neutral in both modes runs at roughly a third of the usual
/// saturation, on purpose, so even the accent and green read as quiet
/// rather than competing for attention.
const _monochrome = ThemePreset(
  id: 'monochrome',
  nameEn: 'Monochrome',
  nameAr: 'أحادي اللون',
  isPremium: true,
  gold: Color(0xFFC9A24A),
  goldDim: Color(0xFF8C7134),
  xpBlue: Color(0xFFB48B2E),
  xpBlueDim: Color(0xFF6F5A2A),
  streakOrange: Color(0xFFC9AA66),
  streakOrangeDim: Color(0xFF8C7542),
  emerald: Color(0xFF7E874F),
  emeraldDim: Color(0xFF525933),
  lightBg: Color(0xFFFAF9F7),
  lightSurface: Color(0xFFF0EEEA),
  lightSurfaceHigh: Colors.white,
  lightSurfaceHL: Color(0xFFE6E2DA),
  lightBorder: Color(0xFFDAD5C9),
  lightDivider: Color(0xFFE6E2D9),
  lightTextPrimary: Color(0xFF201E1A),
  lightTextSecondary: Color(0xFF6B665C),
  lightTextTertiary: Color(0xFF9E988C),
  darkBg: Color(0xFF0C0D0A),
  darkSurface: Color(0xFF171714),
  darkSurfaceElevated: Color(0xFF20201C),
  darkSurfaceHighlight: Color(0xFF2C2D27),
  darkBorder: Color(0xFF393A34),
  darkDivider: Color(0xFF2E2F29),
  darkTextPrimary: Color(0xFFF2F0ED),
  darkTextSecondary: Color(0xFFB5B3AF),
  darkTextTertiary: Color(0xFF767573),
);

/// Warm terracotta/rust on sand — a desert palette. Green leans
/// olive-warm to sit comfortably next to the terracotta rather than
/// reading cold.
const _amberDusk = ThemePreset(
  id: 'amber_dusk',
  nameEn: 'Amber Dusk',
  nameAr: 'غسق العنبر',
  isPremium: true,
  gold: Color(0xFFD97A3A),
  goldDim: Color(0xFF8D542E),
  xpBlue: Color(0xFFC5601D),
  xpBlueDim: Color(0xFF774422),
  streakOrange: Color(0xFFD58B59),
  streakOrangeDim: Color(0xFF955E39),
  emerald: Color(0xFF32BD57),
  emeraldDim: Color(0xFF1E7D38),
  lightBg: Color(0xFFFFF9F5),
  lightSurface: Color(0xFFF5EAE3),
  lightSurfaceHigh: Colors.white,
  lightSurfaceHL: Color(0xFFEAD7CB),
  lightBorder: Color(0xFFD8C6BA),
  lightDivider: Color(0xFFE8D7CB),
  lightTextPrimary: Color(0xFF18251C),
  lightTextSecondary: Color(0xFF657268),
  lightTextTertiary: Color(0xFF97A39A),
  darkBg: Color(0xFF071009),
  darkSurface: Color(0xFF101B13),
  darkSurfaceElevated: Color(0xFF17251B),
  darkSurfaceHighlight: Color(0xFF203325),
  darkBorder: Color(0xFF2D4032),
  darkDivider: Color(0xFF223527),
  darkTextPrimary: Color(0xFFF7EEE8),
  darkTextSecondary: Color(0xFFBCB0A8),
  darkTextTertiary: Color(0xFF7A736F),
);

/// Deep indigo/violet — the moodiest, most "premium at night" preset.
/// Signature-color preset (see the class doc comment): the grid's
/// "complete" color is a deeper, richer violet than the accent, so a
/// filled week reads as a wall of jewel-toned purple rather than green
/// breaking the moody palette.
const _nourViolet = ThemePreset(
  id: 'nour_violet',
  nameEn: 'Nour Violet',
  nameAr: 'نور بنفسجي',
  isPremium: true,
  gold: Color(0xFFA38BDA),
  goldDim: Color(0xFF664AA9),
  xpBlue: Color(0xFF7A55D0),
  xpBlueDim: Color(0xFF53398E),
  streakOrange: Color(0xFF9F88D2),
  streakOrangeDim: Color(0xFF664E9E),
  emerald: Color(0xFF5E2ECF),
  emeraldDim: Color(0xFF3A188A),
  lightBg: Color(0xFFF8F5FF),
  lightSurface: Color(0xFFE8E3F5),
  lightSurfaceHigh: Colors.white,
  lightSurfaceHL: Color(0xFFD4CBEA),
  lightBorder: Color(0xFFC3BAD8),
  lightDivider: Color(0xFFD4CBE8),
  lightTextPrimary: Color(0xFF182521),
  lightTextSecondary: Color(0xFF65726E),
  lightTextTertiary: Color(0xFF97A3A0),
  darkBg: Color(0xFF07100D),
  darkSurface: Color(0xFF101B18),
  darkSurfaceElevated: Color(0xFF172521),
  darkSurfaceHighlight: Color(0xFF20332E),
  darkBorder: Color(0xFF2D403B),
  darkDivider: Color(0xFF223530),
  darkTextPrimary: Color(0xFFECE8F7),
  darkTextSecondary: Color(0xFFAEA8BC),
  darkTextTertiary: Color(0xFF726F7A),
);

/// Sage-forward — the one preset where the "gold" accent role itself is a
/// muted olive-green, and the dedicated grid-green pulls deeper/less
/// yellow than that accent so completions still read as clearly distinct
/// from buttons and highlights rather than blending into them.
const _sage = ThemePreset(
  id: 'sage',
  nameEn: 'Sage',
  nameAr: 'المريمية',
  isPremium: true,
  gold: Color(0xFF9CB65D),
  goldDim: Color(0xFF687843),
  xpBlue: Color(0xFF84A042),
  xpBlueDim: Color(0xFF576535),
  streakOrange: Color(0xFFA6BA75),
  streakOrangeDim: Color(0xFF72814D),
  emerald: Color(0xFF379566),
  emeraldDim: Color(0xFF226242),
  lightBg: Color(0xFFFCFFF5),
  lightSurface: Color(0xFFEFF5E3),
  lightSurfaceHigh: Colors.white,
  lightSurfaceHL: Color(0xFFE1EACB),
  lightBorder: Color(0xFFCFD8BA),
  lightDivider: Color(0xFFDFE8CB),
  lightTextPrimary: Color(0xFF18251F),
  lightTextSecondary: Color(0xFF65726B),
  lightTextTertiary: Color(0xFF97A39D),
  darkBg: Color(0xFF07100B),
  darkSurface: Color(0xFF101B15),
  darkSurfaceElevated: Color(0xFF17251E),
  darkSurfaceHighlight: Color(0xFF20332A),
  darkBorder: Color(0xFF2D4037),
  darkDivider: Color(0xFF22352C),
  darkTextPrimary: Color(0xFFF2F7E8),
  darkTextSecondary: Color(0xFFB6BCA8),
  darkTextTertiary: Color(0xFF777A6F),
);

/// A soft, gentle sky blue — the lightest, most "cute" end of the palette
/// range. Signature-color preset (see the class doc comment): the grid's
/// "complete" color is the same sky blue pushed brighter and more
/// saturated, so a filled week reads as one cohesive light-blue look
/// rather than a green interrupting it; every structural neutral in both
/// modes still carries the same soft touch the accent itself does, same
/// recipe every other preset uses.
const _babyBlue = ThemePreset(
  id: 'baby_blue',
  nameEn: 'Baby Blue',
  nameAr: 'أزرق سماوي',
  isPremium: true,
  gold: Color(0xFF7CBADE),
  goldDim: Color(0xFF3C85B0),
  xpBlue: Color(0xFF47A3D9),
  xpBlueDim: Color(0xFF316F92),
  streakOrange: Color(0xFF94C3DE),
  streakOrangeDim: Color(0xFF4C8BAF),
  emerald: Color(0xFF2E94CF),
  emeraldDim: Color(0xFF18608A),
  lightBg: Color(0xFFF7FBFD),
  lightSurface: Color(0xFFE3EEF5),
  lightSurfaceHigh: Colors.white,
  lightSurfaceHL: Color(0xFFCBDFEA),
  lightBorder: Color(0xFFBACDD8),
  lightDivider: Color(0xFFCBDDE8),
  lightTextPrimary: Color(0xFF18251F),
  lightTextSecondary: Color(0xFF65726B),
  lightTextTertiary: Color(0xFF97A39D),
  darkBg: Color(0xFF07100B),
  darkSurface: Color(0xFF101B15),
  darkSurfaceElevated: Color(0xFF17251E),
  darkSurfaceHighlight: Color(0xFF20332A),
  darkBorder: Color(0xFF2D4037),
  darkDivider: Color(0xFF22352C),
  darkTextPrimary: Color(0xFFE8F1F7),
  darkTextSecondary: Color(0xFFA8B5BC),
  darkTextTertiary: Color(0xFF6F767A),
);

/// A soft, dusty rose pink — the same gentle "cute" register as Baby Blue.
/// Signature-color preset (see the class doc comment): the grid's
/// "complete" color is a brighter, more saturated bubblegum pink rather
/// than a separate green, so the whole app stays in one playful pink
/// family from buttons to a filled week.
const _babyPink = ThemePreset(
  id: 'baby_pink',
  nameEn: 'Baby Pink',
  nameAr: 'وردي فاتح',
  isPremium: true,
  gold: Color(0xFFE4819A),
  goldDim: Color(0xFFBA3959),
  xpBlue: Color(0xFFE0486E),
  xpBlueDim: Color(0xFF9A2F4A),
  streakOrange: Color(0xFFE399AB),
  streakOrangeDim: Color(0xFFB74C66),
  emerald: Color(0xFFDE5499),
  emeraldDim: Color(0xFFAB2166),
  lightBg: Color(0xFFFDF7F8),
  lightSurface: Color(0xFFF5E3E7),
  lightSurfaceHigh: Colors.white,
  lightSurfaceHL: Color(0xFFEACBD3),
  lightBorder: Color(0xFFD8BAC1),
  lightDivider: Color(0xFFE8CBD2),
  lightTextPrimary: Color(0xFF18251E),
  lightTextSecondary: Color(0xFF65726B),
  lightTextTertiary: Color(0xFF97A39D),
  darkBg: Color(0xFF07100B),
  darkSurface: Color(0xFF101B15),
  darkSurfaceElevated: Color(0xFF17251E),
  darkSurfaceHighlight: Color(0xFF203329),
  darkBorder: Color(0xFF2D4036),
  darkDivider: Color(0xFF22352B),
  darkTextPrimary: Color(0xFFF7E8EC),
  darkTextSecondary: Color(0xFFBCA8AD),
  darkTextTertiary: Color(0xFF7A6F72),
);

/// A clean, vivid teal — richer and more saturated than Ocean's cooler,
/// cyan-leaning take, closer to a classic teal swatch. Green shifts
/// further toward yellow-green than usual so grid completions stay
/// clearly distinct from the teal accent instead of blending into it.
const _teal = ThemePreset(
  id: 'teal',
  nameEn: 'Teal',
  nameAr: 'أزرق مخضر',
  isPremium: true,
  gold: Color(0xFF1FBDAD),
  goldDim: Color(0xFF1F776E),
  xpBlue: Color(0xFF14A294),
  xpBlueDim: Color(0xFF19625B),
  streakOrange: Color(0xFF2DC5B6),
  streakOrangeDim: Color(0xFF2C7971),
  emerald: Color(0xFF31CC64),
  emeraldDim: Color(0xFF1D8740),
  lightBg: Color(0xFFF7FDFC),
  lightSurface: Color(0xFFE3F5F3),
  lightSurfaceHigh: Colors.white,
  lightSurfaceHL: Color(0xFFCBEAE7),
  lightBorder: Color(0xFFBAD8D5),
  lightDivider: Color(0xFFCBE8E5),
  lightTextPrimary: Color(0xFF18251C),
  lightTextSecondary: Color(0xFF657269),
  lightTextTertiary: Color(0xFF97A39B),
  darkBg: Color(0xFF07100A),
  darkSurface: Color(0xFF101B14),
  darkSurfaceElevated: Color(0xFF17251C),
  darkSurfaceHighlight: Color(0xFF203326),
  darkBorder: Color(0xFF2D4033),
  darkDivider: Color(0xFF223528),
  darkTextPrimary: Color(0xFFE8F7F5),
  darkTextSecondary: Color(0xFFA8BCBA),
  darkTextTertiary: Color(0xFF6F7A79),
);

/// A crisp royal/navy blue — cooler and more saturated than Baby Blue,
/// built to carry the deep-navy mood in dark mode's already-near-black
/// structural tones rather than in the accent itself (a true navy-black
/// button would leave the app's own dark button text unreadable — see
/// Nour Violet for the same "moody preset, lighter functional accent"
/// precedent). Signature-color preset (see the class doc comment): the
/// grid's "complete" color is the same royal blue as the accent, pushed
/// more saturated, rather than a separate green.
const _navy = ThemePreset(
  id: 'navy',
  nameEn: 'Navy',
  nameAr: 'كحلي',
  isPremium: true,
  gold: Color(0xFF5677D2),
  goldDim: Color(0xFF354E94),
  xpBlue: Color(0xFF2C56C9),
  xpBlueDim: Color(0xFF2B407B),
  streakOrange: Color(0xFF6F89D0),
  streakOrangeDim: Color(0xFF435995),
  emerald: Color(0xFF2E59CF),
  emeraldDim: Color(0xFF18368A),
  lightBg: Color(0xFFF7F9FD),
  lightSurface: Color(0xFFE3E8F5),
  lightSurfaceHigh: Colors.white,
  lightSurfaceHL: Color(0xFFCBD3EA),
  lightBorder: Color(0xFFBAC2D8),
  lightDivider: Color(0xFFCBD3E8),
  lightTextPrimary: Color(0xFF182521),
  lightTextSecondary: Color(0xFF65726E),
  lightTextTertiary: Color(0xFF97A39F),
  darkBg: Color(0xFF07100D),
  darkSurface: Color(0xFF101B18),
  darkSurfaceElevated: Color(0xFF172521),
  darkSurfaceHighlight: Color(0xFF20332D),
  darkBorder: Color(0xFF2D403A),
  darkDivider: Color(0xFF22352F),
  darkTextPrimary: Color(0xFFE8ECF7),
  darkTextSecondary: Color(0xFFA8ADBC),
  darkTextTertiary: Color(0xFF6F727A),
);

abstract final class ThemePresets {
  static const String defaultId = 'emerald_gold';

  static const List<ThemePreset> all = [
    _emeraldGold,
    _ocean,
    _roseInk,
    _monochrome,
    _amberDusk,
    _nourViolet,
    _sage,
    _babyBlue,
    _babyPink,
    _teal,
    _navy,
  ];

  static ThemePreset byId(String? id) =>
      all.firstWhere((p) => p.id == id, orElse: () => _emeraldGold);
}
