import 'package:flutter/material.dart';

import 'color_math.dart';

/// A selectable app-wide color scheme, built around two color roles per
/// preset — **accent** (`gold`) and **grid/success** (`emerald`) — plus two
/// "touches" (a tint or shade) that follow the accent: `xpBlue` is the
/// accent hue pushed into a deeper, richer shade; `streakOrange` is the
/// accent hue pushed into a lighter, softer tint. Every structural neutral
/// in both light mode and dark mode (background, card surfaces, borders,
/// body text) is itself tinted from the accent and emerald hues, so the
/// whole look — background, grid, buttons, highlights — traces back to
/// this preset's own colors, not a scattered palette. `error`/`warning`
/// stay fixed across every preset (so "something's wrong" never gets
/// ambiguous), and the app icon and native splash screen stay fixed too —
/// not a style choice, a platform one: both render before Dart/Flutter
/// (and any saved theme preference) has even loaded, so neither could read
/// the active preset if it wanted to. Category glyphs (category_*.png)
/// aren't fixed — see [HabitCategory.iconAsset]'s doc comment — they're
/// transparent-background PNGs tinted at render time via
/// `BlendMode.srcIn`, so they already track whichever color a call site
/// passes in (almost always a preset-driven one). The achievement-unlock
/// and empty-state illustrations (achievement_celebration_burst,
/// empty_state_no_habits, empty_state_all_done) keep their own fixed
/// foreground colors as brand art, same as the app icon, but their
/// backgrounds are transparent PNGs rather than a baked-in cream fill, so
/// the card/banner behind them can still be preset- and mode-aware — see
/// AchievementsScreen's and DashboardScreen's Container `color: gp.surface`
/// around each one.
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

  /// Builds a preset from the only two decisions a preset actually contains:
  /// the **accent** and the **grid/success** colour. Everything else — the
  /// four accent touches, the dim variants, and all eighteen structural
  /// neutrals in both modes — is derived, because it always was: read the
  /// class doc comment above and every hand-authored preset in this file is
  /// two hues run through the same relationships.
  ///
  /// Derivation is deliberately "re-hue the default preset" rather than
  /// invented from scratch. Each neutral keeps [_emeraldGold]'s exact
  /// saturation and LIGHTNESS and only takes a new hue, which means a custom
  /// theme cannot produce unreadable text no matter which two colours a user
  /// picks: contrast is a function of lightness, and no lightness moves.
  /// Dark neutrals follow the grid hue and light neutrals follow the accent
  /// hue, which is the crossover the built-in presets already use.
  factory ThemePreset.custom({
    required String id,
    required String nameEn,
    required String nameAr,
    required Color accent,
    required Color grid,
  }) {
    final a = HSLColor.fromColor(accent);
    final g = HSLColor.fromColor(grid);

    // Ratios measured off the default preset, so a custom accent relates to
    // its own touches exactly as gold relates to goldDim/xpBlue/streakOrange.
    Color from(HSLColor base, double lMul, double sMul) => base
        .withLightness((base.lightness * lMul).clamp(0.0, 1.0))
        .withSaturation((base.saturation * sMul).clamp(0.0, 1.0))
        .toColor();

    // Keeps the reference neutral's saturation and lightness, swapping only
    // the hue. This is the line that guarantees contrast survives.
    Color reHue(Color reference, double hue) =>
        HSLColor.fromColor(reference).withHue(hue).toColor();

    const ref = _emeraldGold;
    return ThemePreset(
      id: id,
      nameEn: nameEn,
      nameAr: nameAr,
      isPremium: true,
      gold: accent,
      goldDim: from(a, 0.651, 0.681),
      xpBlue: from(a, 0.821, 1.094),
      xpBlueDim: from(a, 0.558, 0.827),
      streakOrange: from(a, 1.071, 0.874),
      streakOrangeDim: from(a, 0.731, 0.654),
      emerald: grid,
      emeraldDim: from(g, 0.641, 1.107),
      // Light mode structure follows the ACCENT hue.
      lightBg: reHue(ref.lightBg, a.hue),
      lightSurface: reHue(ref.lightSurface, a.hue),
      // White stays white: re-hueing a zero-saturation colour is a no-op, but
      // saying so here stops anyone "fixing" it later.
      lightSurfaceHigh: ref.lightSurfaceHigh,
      lightSurfaceHL: reHue(ref.lightSurfaceHL, a.hue),
      lightBorder: reHue(ref.lightBorder, a.hue),
      lightDivider: reHue(ref.lightDivider, a.hue),
      // Light mode TEXT does the crossover and follows the grid hue.
      lightTextPrimary: reHue(ref.lightTextPrimary, g.hue),
      lightTextSecondary: reHue(ref.lightTextSecondary, g.hue),
      lightTextTertiary: reHue(ref.lightTextTertiary, g.hue),
      // Dark mode structure follows the GRID hue.
      darkBg: reHue(ref.darkBg, g.hue),
      darkSurface: reHue(ref.darkSurface, g.hue),
      darkSurfaceElevated: reHue(ref.darkSurfaceElevated, g.hue),
      darkSurfaceHighlight: reHue(ref.darkSurfaceHighlight, g.hue),
      darkBorder: reHue(ref.darkBorder, g.hue),
      darkDivider: reHue(ref.darkDivider, g.hue),
      // Dark mode TEXT crosses over to the accent hue.
      darkTextPrimary: reHue(ref.darkTextPrimary, a.hue),
      darkTextSecondary: reHue(ref.darkTextSecondary, a.hue),
      darkTextTertiary: reHue(ref.darkTextTertiary, a.hue),
    );
  }
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
  // The one non-default free preset (product decision: two free looks —
  // the original Emerald & Gold plus this one; everything else is
  // Premium). Free on purpose, not oversight.
  isPremium: false,
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

/// Twenty-seven colours: nine hues across, three tones down.
///
/// Rows are TONE and columns are HUE, which is what makes a grid scannable
/// instead of a wall of colour — find your hue by column, then choose how
/// loud you want it by row.
///
/// THREE TONES, NOT SIX. This table used to carry six (deep, rich, vivid,
/// bright, soft, muted), which made the grid 248pt tall and pushed the
/// sheet's own Done button off the bottom of the screen: the control that
/// ends the task was the one thing you had to scroll to reach. Three rows
/// is 99pt and the whole sheet fits without scrolling. The two tones that
/// went are the two that were hardest to want, "soft" and "muted", tints
/// pale enough to read as washed out rather than as colours. Fine-grained
/// lightness now lives in the free picker beside this grid, which is a
/// better home for it: this table's job is a fast, coarse, always-safe
/// choice, and precision is the other tab's job.
///
/// NINE HUES, NOT EIGHT. The added column is BROWN, and it carries a much
/// lower saturation than its neighbours (0.42 against 0.70 to 0.88) because
/// that is the entire difference between brown and orange: at hue 28 a
/// saturated colour IS orange, and only pulling the chroma down makes it
/// read as brown. Note what the luminance floor does to this column. A true
/// dark brown such as 0xFF8B5A2B measures 0.12, far below
/// [kAccentLuminanceMin], so it can never be an accent at all; what this
/// column can honestly offer is the readable end of brown, caramel and tan.
///
/// EVERY ROW IS SOLVED FOR A TARGET LUMINANCE rather than for a uniform HSL
/// lightness. Perceived brightness is not spread evenly across hues: a
/// yellow at "50% lightness" is several times as luminous as a blue at the
/// same number, so a uniform row produces swatches whose contrast ranges
/// wildly and a palette where some colours shout. Each of these was
/// bisected onto its row's target instead, so within a row every hue
/// carries the same contrast.
///
/// THE FLOOR THAT SHAPES THIS TABLE: the accent is the fill behind a
/// FilledButton whose label is DARK in both themes (GameColors.background
/// on dark, lightTextPrimary on light — see game_theme.dart). So an accent
/// that is too DARK makes its own button label unreadable. An earlier
/// version of this palette had a "deep" row at luminance 0.20 whose button
/// labels came out at 3.8:1, below the 4.5 floor, on every hue.
///
///   row      target L   worst button label   on white   on the dark card
///   deep       0.28            5.00            2.90          5.55
///   vivid      0.44            7.36            2.12          8.17
///   bright     0.60            9.79            1.60         10.87
///
/// The table measures 0.2810 to 0.6046 end to end, so every colour in it
/// sits inside [kAccentLuminanceMin]..[kAccentLuminanceMax] and the
/// readability guard returns all 27 exactly as printed. That is asserted in
/// the tests, because a swatch that stored a different colour than the one
/// drawn on it would be a worse bug than the one the guard prevents.
const List<List<Color>> kCustomSwatches = [
  // Columns: red, orange, brown, yellow, green, teal, blue, purple, pink.
  // deep
  [
    Color(0xFFEB675A),
    Color(0xFFE86D0F),
    Color(0xFFBA8657),
    Color(0xFFAD8E0E),
    Color(0xFF1BA737),
    Color(0xFF12A38F),
    Color(0xFF3894EF),
    Color(0xFFB276E7),
    Color(0xFFED5AA8),
  ],
  // vivid
  [
    Color(0xFFF29A92),
    Color(0xFFF49D59),
    Color(0xFFCFAB8A),
    Color(0xFFD5AD11),
    Color(0xFF21CD44),
    Color(0xFF16C7AF),
    Color(0xFF79B6F4),
    Color(0xFFCAA1EE),
    Color(0xFFF394C6),
  ],
  // bright
  [
    Color(0xFFF6BFB9),
    Color(0xFFF8C196),
    Color(0xFFE0C8B2),
    Color(0xFFEEC931),
    Color(0xFF61E57B),
    Color(0xFF19E5C9),
    Color(0xFFA7D0F8),
    Color(0xFFDDC1F4),
    Color(0xFFF7BADB),
  ],
];

/// Flat, for callers that just need "every colour we offer".
List<Color> get kCustomSwatchesFlat =>
    [for (final row in kCustomSwatches) ...row];

// ─── The readability guard ──────────────────────────────────────────────────
//
// [kCustomSwatches] above is a CURATED table: every colour in it was solved
// for a target luminance, which is what makes "any swatch you tap is
// readable" true by construction. The moment a hex field exists that
// guarantee stops being structural and has to be enforced, because a hex
// field accepts `000000` as happily as it accepts `E4B45F`.
//
// These two functions are that enforcement. They are the ONLY thing standing
// between a typed hex and [ThemePreset.custom], and they are deliberately
// here rather than in the picker UI: the picker is one call site, and a
// guarantee that lives in a call site is a guarantee that the next call site
// forgets. [ThemePresetNotifier.setCustom] applies them too, so no path into
// the stored colours can skip them.

/// Luminance floor for the ACCENT, and the single most load-bearing number
/// in this file.
///
/// The accent is the `backgroundColor` of every [FilledButton] in the app,
/// whose `foregroundColor` is DARK in both themes (`GameColors.background`
/// in dark mode, `lightTextPrimary` in light, see game_theme.dart). So a
/// dark accent does not merely look moody, it erases its own button labels.
///
/// 0.26 is measured, not chosen, and it is pinned between two numbers that
/// were both computed rather than eyeballed:
///
///   0.25521  the floor 4.5:1 actually demands. The binding label is light
///            mode's, and for a custom theme `lightTextPrimary` is itself
///            derived (re-hued per [ThemePreset.custom]), so this is the
///            worst case over all 360 hues of that derivation, not the one
///            fixed 0xFF18251F the built-in presets use.
///   0.27753  the DARKEST built-in swatch, 0xFFA0910D in the "deep" row.
///
/// Anything in between satisfies both constraints at once, and both
/// constraints matter. Below 0.25521 a button label drops under AA. Above
/// 0.27753 the guard would start "correcting" the app's own palette, so
/// tapping a built-in swatch would store a different colour than the one
/// printed on it, which is a worse bug than the one this guard prevents.
///
/// Note that [kCustomSwatches]' doc comment says "nothing is allowed below
/// luminance 0.28". That is the rounded statement of intent; the table it
/// describes actually bottoms out at 0.27753. Taking the prose literally
/// here is precisely the mistake the paragraph above exists to prevent, and
/// the swatches-are-left-untouched test is what catches it.
const double kAccentLuminanceMin = 0.26;

/// Luminance ceiling for the accent.
///
/// Nothing fails catastrophically up here the way it does at the floor: a
/// pale accent makes a BETTER button, because the label on it is dark. What
/// degrades is the accent used as text and icons on the light theme's white
/// surface. The shipped palette already tolerates that (its lightest row
/// measures 1.56:1 on white and shipped anyway), so this is not a promise
/// being kept, it is a cliff being avoided.
///
/// 0.72 puts a near-white accent at about 1.36:1 on white, the same regime
/// as the shipped 1.56:1 rather than a new one, and in practice only catches
/// colours paler than roughly 0xFFDFDFDF. Every built-in swatch tops out at
/// 0.62410, so nothing curated comes near it.
const double kAccentLuminanceMax = 0.72;

/// The grid colour answers to a different question, so it gets a different
/// band. Its job is to be visible as a filled square against the grid's own
/// background, not to carry dark text on top of itself, and
/// [GameColors.onEmerald] already flips black or white for the one place
/// where a fixed glyph does sit on it. The floor is what keeps a completed
/// square distinguishable from an empty one on the near-black dark
/// background; the ceiling keeps it from vanishing into the light theme's
/// white surface.
const double kGridLuminanceMin = 0.18;
const double kGridLuminanceMax = 0.85;

/// Pulls [c] into the accent's readable band, keeping its hue.
Color fitAccentColour(Color c) =>
    _fitLuminance(c, kAccentLuminanceMin, kAccentLuminanceMax);

/// Pulls [c] into the grid's visible band, keeping its hue.
Color fitGridColour(Color c) =>
    _fitLuminance(c, kGridLuminanceMin, kGridLuminanceMax);

/// True when [fitAccentColour] would leave [c] alone.
bool accentColourFits(Color c) {
  final l = c.computeLuminance();
  return l >= kAccentLuminanceMin && l <= kAccentLuminanceMax;
}

/// True when [fitGridColour] would leave [c] alone.
bool gridColourFits(Color c) {
  final l = c.computeLuminance();
  return l >= kGridLuminanceMin && l <= kGridLuminanceMax;
}

/// The same guard, solved in the space a PICKER is working in.
///
/// [fitAccentColour] corrects along HSL lightness, which is right when hue
/// and saturation are the whole of the input (a typed hex, a stored value, a
/// pair pulled off another device). It is wrong for a finger dragging across
/// a saturation field, and the reason is what sits at the bottom edge of
/// that field: pure black, which has neither hue nor saturation left to
/// preserve. Lifting the lightness of black can only ever return grey, so
/// dragging to the bottom of a red field used to hand back grey, which is a
/// visibly wrong answer to a completely ordinary gesture.
///
/// So the correction runs along the axis the user was actually moving: keep
/// their [hue] and [sat], raise [val] until the colour is back in band.
/// Luminance is linear in value at fixed hue and saturation, so a bisection
/// always converges.
///
/// Value alone is not always enough, and the exception is not exotic. A
/// fully saturated red peaks at luminance 0.222, a violet at 0.158 and a
/// blue at 0.072, all under [kAccentLuminanceMin], so no amount of
/// brightening reaches the floor and the colour has to be diluted toward
/// white instead. That is exactly what the HSL guard does, so when even
/// value 1 falls short this hands it the BRIGHTEST version of their hue
/// rather than the near-black one, and gets a desaturated colour of the
/// right hue back instead of another grey.
Color fitPickerColour({
  required double hue,
  required double sat,
  required double val,
  required bool accent,
}) {
  final lo = accent ? kAccentLuminanceMin : kGridLuminanceMin;
  final hi = accent ? kAccentLuminanceMax : kGridLuminanceMax;
  Color at(double v) => Color(hsvToArgb(hue, sat, v));

  final raw = at(val);
  final l = raw.computeLuminance();
  if (l >= lo && l <= hi) return raw;

  // Too dark AND out of headroom: only desaturation can save this hue.
  if (l < lo && at(1).computeLuminance() < lo) {
    return accent ? fitAccentColour(at(1)) : fitGridColour(at(1));
  }

  final target = l < lo ? lo : hi;
  var low = 0.0;
  var high = 1.0;
  for (var i = 0; i < 24; i++) {
    final mid = (low + high) / 2;
    if (at(mid).computeLuminance() < target) {
      low = mid;
    } else {
      high = mid;
    }
  }
  // Same rule as [_fitLuminance]'s tail: come up off the floor on the side
  // that is at or above target, come down off the ceiling on the side that
  // is at or below it.
  return at(l < lo ? high : low);
}

/// Moves [c] along HSL LIGHTNESS only, until its relative luminance lands on
/// the nearest edge of [lo]..[hi]. Hue and saturation are never touched, so
/// what comes back is recognisably the colour the user asked for: a navy
/// that is too dark comes back a lighter blue of the same hue, not a
/// different colour and not grey.
///
/// Lightness is the right axis and the only one that always works. Relative
/// luminance is monotonic in HSL lightness for a fixed hue and saturation
/// (lightness 0 is black at luminance 0, lightness 1 is white at luminance
/// 1), so a bisection over lightness can always reach any target in between,
/// for every hue, including the ones with no headroom on any other axis:
/// pure blue tops out at luminance 0.0722 no matter what you do to its
/// saturation, and only lightness can lift it.
///
/// Twenty-four steps because that is well past the point where the result
/// stops changing: lightness resolves to 1/255 after eight steps, and the
/// extra iterations cost nothing on a path that runs on a tap.
Color _fitLuminance(Color c, double lo, double hi) {
  final l = c.computeLuminance();
  if (l >= lo && l <= hi) return c;
  final target = l < lo ? lo : hi;

  final hsl = HSLColor.fromColor(c);
  // The invariant the loop maintains: `low` is always a lightness whose
  // luminance is BELOW target, `high` always one at or ABOVE it.
  var low = 0.0;
  var high = 1.0;
  for (var i = 0; i < 24; i++) {
    final mid = (low + high) / 2;
    if (hsl.withLightness(mid).toColor().computeLuminance() < target) {
      low = mid;
    } else {
      high = mid;
    }
  }
  // Which side of the converged pair to return is not a rounding detail, it
  // decides whether the guard actually holds. Coming up off the FLOOR the
  // answer has to be at or above target, so it is `high`; coming down off
  // the CEILING it has to be at or below, so it is `low`. Returning the
  // midpoint either way would leave a colour a hair outside the band it was
  // just corrected into, which is the whole thing this function exists to
  // prevent.
  return hsl.withLightness(l < lo ? high : low).toColor();
}

abstract final class ThemePresets {
  static const String defaultId = 'emerald_gold';

  /// The one preset that is not a constant: the user builds it.
  static const String customId = 'custom';

  /// The two colours [custom] is assembled from. Mutable statics for the same
  /// reason [GameColors]' own colour fields are: the theme has to be readable
  /// synchronously from anywhere, including the boot path that paints the
  /// first frame before any provider exists. [ThemePresetNotifier] owns
  /// writing them, and persists them next to the preset id.
  static Color customAccent = _emeraldGold.gold;
  static Color customGrid = _emeraldGold.emerald;

  /// Rebuilt on read rather than cached, so changing either colour above is
  /// immediately reflected without an invalidation step to forget.
  static ThemePreset get custom => ThemePreset.custom(
        id: customId,
        nameEn: 'Custom',
        nameAr: 'مخصص',
        accent: customAccent,
        grid: customGrid,
      );

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

  /// What the picker lists: the built-ins, then the user's own at the end.
  static List<ThemePreset> get selectable => [...all, custom];

  /// The two looks everyone gets. Listed first, because a free user should
  /// see what they already have before what they do not.
  static List<ThemePreset> get free =>
      all.where((p) => !p.isPremium).toList();

  /// Everything behind Premium, [custom] excluded — that one is presented on
  /// its own rather than as the twelfth item in a list.
  static List<ThemePreset> get premium =>
      all.where((p) => p.isPremium).toList();

  static ThemePreset byId(String? id) => id == customId
      ? custom
      : all.firstWhere((p) => p.id == id, orElse: () => _emeraldGold);

  /// Whether [id] names a preset this build knows how to render — used by the
  /// account sync, which must not apply an id written by a newer version.
  static bool isKnown(String? id) =>
      id == customId || all.any((p) => p.id == id);
}
