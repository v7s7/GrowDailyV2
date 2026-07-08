import 'package:flutter/material.dart';

/// A selectable app-wide color scheme. Presets vary the *accent* colors
/// (the gold/blue/orange trio used for buttons, XP, streaks, and rarity
/// highlights) and the *light-mode* structural neutrals (background, card
/// surfaces, borders) — not dark mode, which stays the shared near-black
/// look every preset already shares, and not the semantic colors (green =
/// success, red = error), which stay fixed across presets so those
/// meanings never get ambiguous.
///
/// Deliberately NOT touching illustrated art (app icon, splash, onboarding
/// art, category glyphs) — those have colors baked into the actual PNGs,
/// so a preset only restyles UI chrome, not artwork.
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

  // Light-mode structural neutrals only.
  final Color lightBg;
  final Color lightSurface;
  final Color lightSurfaceHigh;
  final Color lightSurfaceHL;
  final Color lightBorder;
  final Color lightDivider;
  final Color lightTextPrimary;
  final Color lightTextSecondary;
  final Color lightTextTertiary;

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
    required this.lightBg,
    required this.lightSurface,
    required this.lightSurfaceHigh,
    required this.lightSurfaceHL,
    required this.lightBorder,
    required this.lightDivider,
    required this.lightTextPrimary,
    required this.lightTextSecondary,
    required this.lightTextTertiary,
  });
}

/// The original, free-for-everyone look — warm gold + emerald on a cream
/// backdrop. Kept as-is so nobody's app changes underneath them by default.
const _emeraldGold = ThemePreset(
  id: 'emerald_gold',
  nameEn: 'Emerald & Gold',
  nameAr: 'زمردي وذهبي',
  isPremium: false,
  gold: Color(0xFFE4B45F),
  goldDim: Color(0xFF9C7436),
  xpBlue: Color(0xFF5DADEC),
  xpBlueDim: Color(0xFF236EA8),
  streakOrange: Color(0xFFFF8A4C),
  streakOrangeDim: Color(0xFFC95B22),
  lightBg: Color(0xFFFFFCF5),
  lightSurface: Color(0xFFF5EFE3),
  lightSurfaceHigh: Colors.white,
  lightSurfaceHL: Color(0xFFEADFCB),
  lightBorder: Color(0xFFD8CDBA),
  lightDivider: Color(0xFFE8DDCB),
  lightTextPrimary: Color(0xFF18251F),
  lightTextSecondary: Color(0xFF657166),
  lightTextTertiary: Color(0xFF9AA397),
);

/// A cooler, calmer teal/blue take with a true-white light mode — the most
/// direct answer to "gold on cream feels muted in light mode."
const _ocean = ThemePreset(
  id: 'ocean',
  nameEn: 'Ocean',
  nameAr: 'المحيط',
  isPremium: true,
  gold: Color(0xFF2FA8A0),
  goldDim: Color(0xFF1F7973),
  xpBlue: Color(0xFF4C8DFF),
  xpBlueDim: Color(0xFF2E5FB8),
  streakOrange: Color(0xFFFF9F5A),
  streakOrangeDim: Color(0xFFCB7638),
  lightBg: Color(0xFFF7FAFB),
  lightSurface: Colors.white,
  lightSurfaceHigh: Colors.white,
  lightSurfaceHL: Color(0xFFE7F1F2),
  lightBorder: Color(0xFFD7E4E6),
  lightDivider: Color(0xFFE3EEEF),
  lightTextPrimary: Color(0xFF122327),
  lightTextSecondary: Color(0xFF5C7278),
  lightTextTertiary: Color(0xFF94A6AA),
);

/// Warm rose accent on a cool near-white base — the biggest structural
/// departure from the default's cream warmth, for anyone who wants light
/// mode to actually feel bright and crisp rather than warm and muted.
const _roseInk = ThemePreset(
  id: 'rose_ink',
  nameEn: 'Rose & Ink',
  nameAr: 'وردي وحبر',
  isPremium: true,
  gold: Color(0xFFE0637E),
  goldDim: Color(0xFFA83F55),
  xpBlue: Color(0xFF6E7BE0),
  xpBlueDim: Color(0xFF4650A3),
  streakOrange: Color(0xFFF08A5D),
  streakOrangeDim: Color(0xFFBD5F37),
  lightBg: Color(0xFFFDFAFB),
  lightSurface: Colors.white,
  lightSurfaceHigh: Colors.white,
  lightSurfaceHL: Color(0xFFF7E9ED),
  lightBorder: Color(0xFFEBDBDF),
  lightDivider: Color(0xFFF1E4E7),
  lightTextPrimary: Color(0xFF211419),
  lightTextSecondary: Color(0xFF6E5A61),
  lightTextTertiary: Color(0xFFA6979C),
);

/// Charcoal + gold only — minimal, no blue/orange competing for attention.
/// streakOrange and xpBlue are folded toward the same warm-neutral family
/// so nothing reads as an off-brand accent.
const _monochrome = ThemePreset(
  id: 'monochrome',
  nameEn: 'Monochrome',
  nameAr: 'أحادي اللون',
  isPremium: true,
  gold: Color(0xFFC9A24A),
  goldDim: Color(0xFF8C7134),
  xpBlue: Color(0xFF8C8067),
  xpBlueDim: Color(0xFF5F5745),
  streakOrange: Color(0xFFAF9058),
  streakOrangeDim: Color(0xFF7A6A45),
  lightBg: Color(0xFFFAF9F7),
  lightSurface: Color(0xFFF0EEEA),
  lightSurfaceHigh: Colors.white,
  lightSurfaceHL: Color(0xFFE6E2DA),
  lightBorder: Color(0xFFDAD5C9),
  lightDivider: Color(0xFFE6E2D9),
  lightTextPrimary: Color(0xFF201E1A),
  lightTextSecondary: Color(0xFF6B665C),
  lightTextTertiary: Color(0xFF9E988C),
);

abstract final class ThemePresets {
  static const String defaultId = 'emerald_gold';

  static const List<ThemePreset> all = [
    _emeraldGold,
    _ocean,
    _roseInk,
    _monochrome,
  ];

  static ThemePreset byId(String? id) =>
      all.firstWhere((p) => p.id == id, orElse: () => _emeraldGold);
}
