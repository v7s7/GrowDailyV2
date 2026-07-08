import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'theme_preset.dart';

// ─── Gamification Colors ──────────────────────────────────────────────────
//
// `gold`/`xpBlue`/`streakOrange` (+ Dim variants) and the light-mode
// structural neutrals below are preset-driven and mutable — call
// `GameColors.applyPreset(...)` to swap the whole app's look. Everything
// else (emerald/success, error, warning, dark-mode structural colors) stays
// fixed across every preset so semantic meaning (green = success, red =
// error) and dark mode's shared identity never change.

abstract final class GameColors {
  static Color gold = ThemePresets.byId(ThemePresets.defaultId).gold;
  static Color goldDim = ThemePresets.byId(ThemePresets.defaultId).goldDim;
  static const Color emerald = Color(0xFF2ECF8F);
  static const Color emeraldDim = Color(0xFF188A61);
  static Color xpBlue = ThemePresets.byId(ThemePresets.defaultId).xpBlue;
  static Color xpBlueDim = ThemePresets.byId(ThemePresets.defaultId).xpBlueDim;
  static Color streakOrange =
      ThemePresets.byId(ThemePresets.defaultId).streakOrange;
  static Color streakOrangeDim =
      ThemePresets.byId(ThemePresets.defaultId).streakOrangeDim;
  static const Color success = emerald;
  static const Color error = Color(0xFFFF5A52);
  static const Color warning = Color(0xFFF7C948);
  static const Color rarityCommon = Color(0xFF8C9A92);
  static const Color rarityUncommon = emerald;
  static Color get rarityRare => xpBlue;
  static const Color rarityEpic = Color(0xFFB982FF);
  static Color get rarityLegendary => gold;

  // Dark-mode structural — shared by every preset, kept const.
  static const Color background = Color(0xFF07100D);
  static const Color surface = Color(0xFF101B17);
  static const Color surfaceElevated = Color(0xFF17251F);
  static const Color surfaceHighlight = Color(0xFF20332B);
  static const Color textPrimary = Color(0xFFF7F3E8);
  static const Color textSecondary = Color(0xFFB5BCA8);
  static const Color textTertiary = Color(0xFF6F7A70);
  static const Color border = Color(0xFF2D4037);
  static const Color divider = Color(0xFF22352D);

  // Light-mode structural — preset-driven, mutable.
  static Color lightBg = ThemePresets.byId(ThemePresets.defaultId).lightBg;
  static Color lightSurface =
      ThemePresets.byId(ThemePresets.defaultId).lightSurface;
  static Color lightSurfaceHigh =
      ThemePresets.byId(ThemePresets.defaultId).lightSurfaceHigh;
  static Color lightSurfaceHL =
      ThemePresets.byId(ThemePresets.defaultId).lightSurfaceHL;
  static Color lightBorder =
      ThemePresets.byId(ThemePresets.defaultId).lightBorder;
  static Color lightDivider =
      ThemePresets.byId(ThemePresets.defaultId).lightDivider;
  static Color lightTextPrimary =
      ThemePresets.byId(ThemePresets.defaultId).lightTextPrimary;
  static Color lightTextSecondary =
      ThemePresets.byId(ThemePresets.defaultId).lightTextSecondary;
  static Color lightTextTertiary =
      ThemePresets.byId(ThemePresets.defaultId).lightTextTertiary;

  /// Swaps every preset-driven color in place. Callers must rebuild
  /// (`setState`/provider notify) after calling this — it doesn't trigger
  /// any rebuild itself.
  static void applyPreset(ThemePreset preset) {
    gold = preset.gold;
    goldDim = preset.goldDim;
    xpBlue = preset.xpBlue;
    xpBlueDim = preset.xpBlueDim;
    streakOrange = preset.streakOrange;
    streakOrangeDim = preset.streakOrangeDim;
    lightBg = preset.lightBg;
    lightSurface = preset.lightSurface;
    lightSurfaceHigh = preset.lightSurfaceHigh;
    lightSurfaceHL = preset.lightSurfaceHL;
    lightBorder = preset.lightBorder;
    lightDivider = preset.lightDivider;
    lightTextPrimary = preset.lightTextPrimary;
    lightTextSecondary = preset.lightTextSecondary;
    lightTextTertiary = preset.lightTextTertiary;
  }
}

// ─── Adaptive Palette — widgets call context.gp.* ────────────────────────────

class _GamePalette {
  final bool dark;
  const _GamePalette(this.dark);

  Color get bg => dark ? GameColors.background : GameColors.lightBg;
  Color get surface => dark ? GameColors.surface : GameColors.lightSurface;
  Color get surfaceHigh =>
      dark ? GameColors.surfaceElevated : GameColors.lightSurfaceHigh;
  Color get surfaceHL =>
      dark ? GameColors.surfaceHighlight : GameColors.lightSurfaceHL;
  Color get textPrimary =>
      dark ? GameColors.textPrimary : GameColors.lightTextPrimary;
  Color get textSec =>
      dark ? GameColors.textSecondary : GameColors.lightTextSecondary;
  Color get textTert =>
      dark ? GameColors.textTertiary : GameColors.lightTextTertiary;
  Color get border => dark ? GameColors.border : GameColors.lightBorder;
  Color get divider => dark ? GameColors.divider : GameColors.lightDivider;
}

extension BuildContextGameTheme on BuildContext {
  _GamePalette get gp =>
      _GamePalette(Theme.of(this).brightness == Brightness.dark);
}

// ─── Typography ──────────────────────────────────────────────────────────────

abstract final class GameTextStyles {
  static const List<String> fontFallback = <String>[
    'Noto Sans Arabic',
    'Noto Naskh Arabic',
    'DIN Next LT Arabic',
    'Segoe UI',
    'Roboto',
    'Arial',
    'sans-serif',
  ];

  static const TextStyle displayLarge = TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: GameColors.textPrimary, letterSpacing: -0.5, height: 1.12, fontFamilyFallback: fontFallback);
  static const TextStyle displayMedium = TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: GameColors.textPrimary, letterSpacing: -0.3, height: 1.15, fontFamilyFallback: fontFallback);
  static const TextStyle headlineLarge = TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: GameColors.textPrimary, letterSpacing: -0.2, height: 1.22, fontFamilyFallback: fontFallback);
  static const TextStyle headlineMedium = TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: GameColors.textPrimary, height: 1.25, fontFamilyFallback: fontFallback);
  static const TextStyle titleLarge = TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: GameColors.textPrimary, height: 1.25, fontFamilyFallback: fontFallback);
  static const TextStyle titleMedium = TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: GameColors.textPrimary, height: 1.28, fontFamilyFallback: fontFallback);
  static const TextStyle bodyLarge = TextStyle(fontSize: 17, fontWeight: FontWeight.w400, color: GameColors.textPrimary, height: 1.45, fontFamilyFallback: fontFallback);
  static const TextStyle bodyMedium = TextStyle(fontSize: 15, fontWeight: FontWeight.w400, color: GameColors.textPrimary, height: 1.45, fontFamilyFallback: fontFallback);
  static const TextStyle bodySmall = TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: GameColors.textSecondary, height: 1.42, fontFamilyFallback: fontFallback);
  static const TextStyle labelLarge = TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: GameColors.textPrimary, letterSpacing: 0.1, height: 1.25, fontFamilyFallback: fontFallback);
  static const TextStyle labelSmall = TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: GameColors.textSecondary, letterSpacing: 0.5, height: 1.25, fontFamilyFallback: fontFallback);

  // These five embed a preset-driven color, so they can't be compile-time
  // constants anymore — they're getters instead. (Confirmed unused outside
  // this file, so switching `static const` → `static ... get` needed no
  // call-site changes.)
  static TextStyle get xpLabel => TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: GameColors.xpBlue, letterSpacing: 0.5, height: 1.2, fontFamilyFallback: fontFallback);
  static TextStyle get goldLabel => TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: GameColors.gold, letterSpacing: 0.5, height: 1.2, fontFamilyFallback: fontFallback);
  static TextStyle get levelDisplay => TextStyle(fontSize: 40, fontWeight: FontWeight.w800, color: GameColors.gold, letterSpacing: -1.0, height: 1.05, fontFamilyFallback: fontFallback);
  static TextStyle get streakDisplay => TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: GameColors.streakOrange, letterSpacing: -0.8, height: 1.05, fontFamilyFallback: fontFallback);

  static const TextStyle arabicTitle = TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: GameColors.textPrimary, height: 1.55, fontFamilyFallback: fontFallback);
  static const TextStyle arabicBody = TextStyle(fontSize: 16, fontWeight: FontWeight.w400, color: GameColors.textPrimary, height: 1.65, fontFamilyFallback: fontFallback);
  static TextStyle get arabicLabel => TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: GameColors.gold, height: 1.45, fontFamilyFallback: fontFallback);
}
// ─── Spacing & Radii ─────────────────────────────────────────────────────────

abstract final class GameSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double cardRadius = 16;
  static const double buttonRadius = 12;
  static const double chipRadius = 8;
  static const double pillRadius = 100;
  static const EdgeInsets screenPadding = EdgeInsets.symmetric(horizontal: lg);
  static const EdgeInsets cardPadding = EdgeInsets.all(lg);
}

// ─── Shared input theme helper ────────────────────────────────────────────────

InputDecorationTheme _inputTheme(bool dark) {
  final fill = dark ? GameColors.surface : GameColors.lightSurface;
  final bd = dark ? GameColors.border : GameColors.lightBorder;
  final hint = dark ? GameColors.textTertiary : GameColors.lightTextTertiary;
  final label = dark ? GameColors.textSecondary : GameColors.lightTextSecondary;
  return InputDecorationTheme(
    filled: true,
    fillColor: fill,
    contentPadding: const EdgeInsets.symmetric(horizontal: GameSpacing.lg, vertical: GameSpacing.md),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(GameSpacing.buttonRadius), borderSide: BorderSide(color: bd, width: 0.5)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(GameSpacing.buttonRadius), borderSide: BorderSide(color: bd, width: 0.5)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(GameSpacing.buttonRadius), borderSide: BorderSide(color: GameColors.gold)),
    errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(GameSpacing.buttonRadius), borderSide: const BorderSide(color: GameColors.error)),
    focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(GameSpacing.buttonRadius), borderSide: const BorderSide(color: GameColors.error)),
    hintStyle: TextStyle(
      fontSize: 15,
      color: hint,
      fontFamilyFallback: GameTextStyles.fontFallback,
    ),
    labelStyle: TextStyle(
      fontSize: 15,
      color: label,
      fontFamilyFallback: GameTextStyles.fontFallback,
    ),
    floatingLabelStyle: TextStyle(
      fontSize: 12,
      color: GameColors.gold,
      fontFamilyFallback: GameTextStyles.fontFallback,
    ),
  );
}

// ─── ThemeData Assembly ──────────────────────────────────────────────────────

abstract final class GameTheme {
  static ThemeData get dark {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamilyFallback: GameTextStyles.fontFallback,
      scaffoldBackgroundColor: GameColors.background,
      colorScheme: ColorScheme.dark(
        primary: GameColors.gold,
        onPrimary: GameColors.background,
        secondary: GameColors.xpBlue,
        onSecondary: GameColors.textPrimary,
        tertiary: GameColors.streakOrange,
        onTertiary: GameColors.textPrimary,
        surface: GameColors.surface,
        onSurface: GameColors.textPrimary,
        surfaceContainerHighest: GameColors.surfaceElevated,
        onSurfaceVariant: GameColors.textSecondary,
        outline: GameColors.border,
        error: GameColors.error,
        onError: GameColors.textPrimary,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: GameColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
        titleTextStyle: GameTextStyles.titleLarge,
        iconTheme: const IconThemeData(color: GameColors.textPrimary),
        actionsIconTheme: IconThemeData(color: GameColors.gold),
      ),
      cardTheme: CardThemeData(
        color: GameColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
          side: const BorderSide(color: GameColors.border, width: 0.5),
        ),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: GameColors.gold,
          foregroundColor: GameColors.background,
          disabledBackgroundColor: GameColors.surfaceHighlight,
          disabledForegroundColor: GameColors.textTertiary,
          elevation: 0,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GameSpacing.buttonRadius)),
          textStyle: GameTextStyles.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: GameColors.gold,
          side: BorderSide(color: GameColors.gold),
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GameSpacing.buttonRadius)),
          textStyle: GameTextStyles.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: GameColors.gold,
          textStyle: GameTextStyles.labelLarge,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: GameColors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: GameColors.gold.withAlpha(46),
        iconTheme: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
            ? IconThemeData(color: GameColors.gold, size: 24)
            : const IconThemeData(color: GameColors.textTertiary, size: 24)),
        labelTextStyle: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
            ? TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: GameColors.gold, fontFamilyFallback: GameTextStyles.fontFallback)
            : const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: GameColors.textTertiary, fontFamilyFallback: GameTextStyles.fontFallback)),
        elevation: 0,
        height: 72,
      ),
      dividerTheme: const DividerThemeData(color: GameColors.divider, space: 1, thickness: 0.5),
      dialogTheme: DialogThemeData(
        backgroundColor: GameColors.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GameSpacing.cardRadius)),
        titleTextStyle: GameTextStyles.headlineMedium,
        contentTextStyle: const TextStyle(fontSize: 15, color: GameColors.textSecondary),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: GameColors.surfaceElevated,
        contentTextStyle: GameTextStyles.bodyMedium,
        actionTextColor: GameColors.gold,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GameSpacing.chipRadius)),
        behavior: SnackBarBehavior.floating,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: GameColors.xpBlue,
        circularTrackColor: GameColors.surfaceElevated,
        linearTrackColor: GameColors.surfaceElevated,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? GameColors.background : GameColors.textTertiary),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? GameColors.gold : GameColors.surfaceElevated),
      ),
      inputDecorationTheme: _inputTheme(true),
      textTheme: GoogleFonts.cairoTextTheme(
        TextTheme(
          displayLarge: GameTextStyles.displayLarge,
          displayMedium: GameTextStyles.displayMedium,
          headlineLarge: GameTextStyles.headlineLarge,
          headlineMedium: GameTextStyles.headlineMedium,
          titleLarge: GameTextStyles.titleLarge,
          titleMedium: GameTextStyles.titleMedium,
          bodyLarge: GameTextStyles.bodyLarge,
          bodyMedium: GameTextStyles.bodyMedium,
          bodySmall: GameTextStyles.bodySmall,
          labelLarge: GameTextStyles.labelLarge,
          labelSmall: GameTextStyles.labelSmall,
        ),
      ),
    );
  }

  static ThemeData get light {
    final Color lBg = GameColors.lightBg;
    final Color lCard = GameColors.lightSurface;
    final Color lHigh = GameColors.lightSurfaceHigh;
    final Color lHL = GameColors.lightSurfaceHL;
    final Color lTp = GameColors.lightTextPrimary;
    final Color lTs = GameColors.lightTextSecondary;
    final Color lTt = GameColors.lightTextTertiary;
    final Color lBd = GameColors.lightBorder;
    final Color lDv = GameColors.lightDivider;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamilyFallback: GameTextStyles.fontFallback,
      scaffoldBackgroundColor: lBg,
      colorScheme: ColorScheme.light(
        primary: GameColors.gold,
        onPrimary: lTp,
        secondary: GameColors.xpBlue,
        onSecondary: Colors.white,
        tertiary: GameColors.streakOrange,
        onTertiary: Colors.white,
        surface: lCard,
        onSurface: lTp,
        surfaceContainerHighest: lHigh,
        onSurfaceVariant: lTs,
        outline: lBd,
        error: GameColors.error,
        onError: Colors.white,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: lBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
        titleTextStyle: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: lTp, fontFamilyFallback: GameTextStyles.fontFallback),
        iconTheme: IconThemeData(color: lTp),
        actionsIconTheme: IconThemeData(color: GameColors.gold),
      ),
      cardTheme: CardThemeData(
        color: lCard,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
          side: BorderSide(color: lBd, width: 0.5),
        ),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: GameColors.gold,
          foregroundColor: lTp,
          disabledBackgroundColor: lHL,
          disabledForegroundColor: lTt,
          elevation: 0,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GameSpacing.buttonRadius)),
          textStyle: GameTextStyles.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: GameColors.gold,
          side: BorderSide(color: GameColors.gold),
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GameSpacing.buttonRadius)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: GameColors.gold),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: lBg,
        surfaceTintColor: Colors.transparent,
        indicatorColor: GameColors.gold.withAlpha(46),
        iconTheme: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
            ? IconThemeData(color: GameColors.gold, size: 24)
            : IconThemeData(color: lTt, size: 24)),
        labelTextStyle: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
            ? TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: GameColors.gold, fontFamilyFallback: GameTextStyles.fontFallback)
            : TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: lTt, fontFamilyFallback: GameTextStyles.fontFallback)),
        elevation: 0,
        shadowColor: Colors.black12,
        height: 72,
      ),
      dividerTheme: DividerThemeData(color: lDv, space: 1, thickness: 0.5),
      dialogTheme: DialogThemeData(
        backgroundColor: lBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(GameSpacing.cardRadius)),
        ),
        titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: lTp, fontFamilyFallback: GameTextStyles.fontFallback),
        contentTextStyle: TextStyle(fontSize: 15, color: lTs, fontFamilyFallback: GameTextStyles.fontFallback),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: lBg,
        contentTextStyle: TextStyle(fontSize: 15, color: lTp, fontFamilyFallback: GameTextStyles.fontFallback),
        actionTextColor: GameColors.gold,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GameSpacing.chipRadius),
          side: BorderSide(color: lBd, width: 0.5),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: GameColors.xpBlue,
        circularTrackColor: lCard,
        linearTrackColor: lCard,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? lBg : lTt),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? GameColors.gold : lHL),
      ),
      inputDecorationTheme: _inputTheme(false),
      // Same Cairo wrapping as the dark theme (see below) — without it, light
      // mode silently falls back to the platform default font while dark
      // mode renders Cairo, so Arabic and English text look inconsistent
      // depending on theme. Cairo is the standard pairing for bilingual
      // Arabic/English UI and reads correctly on iOS.
      textTheme: GoogleFonts.cairoTextTheme(
        const TextTheme(
          displayLarge: GameTextStyles.displayLarge,
          displayMedium: GameTextStyles.displayMedium,
          headlineLarge: GameTextStyles.headlineLarge,
          headlineMedium: GameTextStyles.headlineMedium,
          titleLarge: GameTextStyles.titleLarge,
          titleMedium: GameTextStyles.titleMedium,
          bodyLarge: GameTextStyles.bodyLarge,
          bodyMedium: GameTextStyles.bodyMedium,
          bodySmall: GameTextStyles.bodySmall,
          labelLarge: GameTextStyles.labelLarge,
          labelSmall: GameTextStyles.labelSmall,
        ).apply(
          bodyColor: lTp,
          displayColor: lTp,
        ),
      ),
    );
  }
}
