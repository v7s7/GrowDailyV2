import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

// ─── Gamification Colors (theme-invariant) ────────────────────────────────────

abstract final class GameColors {
  static const Color gold = Color(0xFFF5C533);
  static const Color goldDim = Color(0xFFB8941F);
  static const Color xpBlue = Color(0xFF4A9EFF);
  static const Color xpBlueDim = Color(0xFF1C6EC4);
  static const Color streakOrange = Color(0xFFFF6B35);
  static const Color streakOrangeDim = Color(0xFFCC4A1A);
  static const Color success = Color(0xFF34C759);
  static const Color error = Color(0xFFFF3B30);
  static const Color warning = Color(0xFFFFCC00);
  static const Color rarityCommon = Color(0xFF8E8E93);
  static const Color rarityUncommon = Color(0xFF34C759);
  static const Color rarityRare = Color(0xFF4A9EFF);
  static const Color rarityEpic = Color(0xFFBF5AF2);
  static const Color rarityLegendary = Color(0xFFF5C533);

  // Dark-mode structural — kept for const TextStyles & ThemeData construction
  static const Color background = Color(0xFF000000);
  static const Color surface = Color(0xFF1C1C1E);
  static const Color surfaceElevated = Color(0xFF2C2C2E);
  static const Color surfaceHighlight = Color(0xFF3A3A3C);
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF8E8E93);
  static const Color textTertiary = Color(0xFF48484A);
  static const Color border = Color(0xFF38383A);
  static const Color divider = Color(0xFF2C2C2E);
}

// ─── Adaptive Palette — widgets call context.gp.* ────────────────────────────

class _GamePalette {
  final bool dark;
  const _GamePalette(this.dark);

  Color get bg => dark ? const Color(0xFF000000) : Colors.white;
  Color get surface => dark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);
  Color get surfaceHigh => dark ? const Color(0xFF2C2C2E) : Colors.white;
  Color get surfaceHL => dark ? const Color(0xFF3A3A3C) : const Color(0xFFE5E5EA);
  Color get textPrimary => dark ? Colors.white : const Color(0xFF1C1C1E);
  Color get textSec => dark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70);
  Color get textTert => dark ? const Color(0xFF48484A) : const Color(0xFFAEAEB2);
  Color get border => dark ? const Color(0xFF38383A) : const Color(0xFFD1D1D6);
  Color get divider => dark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA);
}

extension BuildContextGameTheme on BuildContext {
  _GamePalette get gp =>
      _GamePalette(Theme.of(this).brightness == Brightness.dark);
}

// ─── Typography ──────────────────────────────────────────────────────────────

abstract final class GameTextStyles {
  static TextStyle get displayLarge => GoogleFonts.cairo(fontSize: 34, fontWeight: FontWeight.w700, color: GameColors.textPrimary, letterSpacing: -0.5);
  static TextStyle get displayMedium => GoogleFonts.cairo(fontSize: 28, fontWeight: FontWeight.w700, color: GameColors.textPrimary, letterSpacing: -0.3);
  static TextStyle get headlineLarge => GoogleFonts.cairo(fontSize: 22, fontWeight: FontWeight.w700, color: GameColors.textPrimary, letterSpacing: -0.2);
  static TextStyle get headlineMedium => GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.w600, color: GameColors.textPrimary);
  static TextStyle get titleLarge => GoogleFonts.cairo(fontSize: 17, fontWeight: FontWeight.w600, color: GameColors.textPrimary);
  static TextStyle get titleMedium => GoogleFonts.cairo(fontSize: 15, fontWeight: FontWeight.w600, color: GameColors.textPrimary);
  static TextStyle get bodyLarge => GoogleFonts.cairo(fontSize: 17, fontWeight: FontWeight.w400, color: GameColors.textPrimary);
  static TextStyle get bodyMedium => GoogleFonts.cairo(fontSize: 15, fontWeight: FontWeight.w400, color: GameColors.textPrimary);
  static TextStyle get bodySmall => GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.w400, color: GameColors.textSecondary);
  static TextStyle get labelLarge => GoogleFonts.cairo(fontSize: 15, fontWeight: FontWeight.w600, color: GameColors.textPrimary, letterSpacing: 0.1);
  static TextStyle get labelSmall => GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.w500, color: GameColors.textSecondary, letterSpacing: 0.5);
  static TextStyle get xpLabel => GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.w700, color: GameColors.xpBlue, letterSpacing: 0.5);
  static TextStyle get goldLabel => GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.w700, color: GameColors.gold, letterSpacing: 0.5);
  static TextStyle get levelDisplay => GoogleFonts.cairo(fontSize: 40, fontWeight: FontWeight.w800, color: GameColors.gold, letterSpacing: -1.0);
  static TextStyle get streakDisplay => GoogleFonts.cairo(fontSize: 32, fontWeight: FontWeight.w800, color: GameColors.streakOrange, letterSpacing: -0.8);
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
  final fill = dark ? GameColors.surface : const Color(0xFFF2F2F7);
  final bd = dark ? GameColors.border : const Color(0xFFD1D1D6);
  final hint = dark ? GameColors.textTertiary : const Color(0xFFAEAEB2);
  final label = dark ? GameColors.textSecondary : const Color(0xFF6C6C70);
  return InputDecorationTheme(
    filled: true,
    fillColor: fill,
    contentPadding: const EdgeInsets.symmetric(horizontal: GameSpacing.lg, vertical: GameSpacing.md),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(GameSpacing.buttonRadius), borderSide: BorderSide(color: bd, width: 0.5)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(GameSpacing.buttonRadius), borderSide: BorderSide(color: bd, width: 0.5)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(GameSpacing.buttonRadius), borderSide: const BorderSide(color: GameColors.gold)),
    errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(GameSpacing.buttonRadius), borderSide: const BorderSide(color: GameColors.error)),
    focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(GameSpacing.buttonRadius), borderSide: const BorderSide(color: GameColors.error)),
    hintStyle: TextStyle(fontSize: 15, color: hint),
    labelStyle: TextStyle(fontSize: 15, color: label),
    floatingLabelStyle: const TextStyle(fontSize: 12, color: GameColors.gold),
  );
}

// ─── ThemeData Assembly ──────────────────────────────────────────────────────

abstract final class GameTheme {
  static ThemeData get dark {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: GameColors.background,
      colorScheme: const ColorScheme.dark(
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
        actionsIconTheme: const IconThemeData(color: GameColors.gold),
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
          side: const BorderSide(color: GameColors.gold),
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
        indicatorColor: const Color(0x26F5C533),
        iconTheme: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
            ? const IconThemeData(color: GameColors.gold, size: 24)
            : const IconThemeData(color: GameColors.textTertiary, size: 24)),
        labelTextStyle: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
            ? const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: GameColors.gold)
            : const TextStyle(fontSize: 11, fontWeight: FontWeight.w400, color: GameColors.textTertiary)),
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
      progressIndicatorTheme: const ProgressIndicatorThemeData(
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
    const Color lBg = Colors.white;
    const Color lCard = Color(0xFFF2F2F7);
    const Color lHigh = Colors.white;
    const Color lHL = Color(0xFFE5E5EA);
    const Color lTp = Color(0xFF1C1C1E);
    const Color lTs = Color(0xFF6C6C70);
    const Color lTt = Color(0xFFAEAEB2);
    const Color lBd = Color(0xFFD1D1D6);
    const Color lDv = Color(0xFFE5E5EA);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: lBg,
      colorScheme: const ColorScheme.light(
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
      appBarTheme: const AppBarTheme(
        backgroundColor: lBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
        titleTextStyle: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: lTp),
        iconTheme: IconThemeData(color: lTp),
        actionsIconTheme: IconThemeData(color: GameColors.gold),
      ),
      cardTheme: CardThemeData(
        color: lCard,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
          side: const BorderSide(color: lBd, width: 0.5),
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
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 0.1),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: GameColors.gold,
          side: const BorderSide(color: GameColors.gold),
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
        indicatorColor: const Color(0x26F5C533),
        iconTheme: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
            ? const IconThemeData(color: GameColors.gold, size: 24)
            : IconThemeData(color: lTt, size: 24)),
        labelTextStyle: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
            ? const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: GameColors.gold)
            : TextStyle(fontSize: 11, fontWeight: FontWeight.w400, color: lTt)),
        elevation: 0,
        shadowColor: Colors.black12,
        height: 72,
      ),
      dividerTheme: const DividerThemeData(color: lDv, space: 1, thickness: 0.5),
      dialogTheme: const DialogThemeData(
        backgroundColor: lBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(GameSpacing.cardRadius)),
        ),
        titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: lTp),
        contentTextStyle: TextStyle(fontSize: 15, color: lTs),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: lBg,
        contentTextStyle: const TextStyle(fontSize: 15, color: lTp),
        actionTextColor: GameColors.gold,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GameSpacing.chipRadius),
          side: const BorderSide(color: lBd, width: 0.5),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
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
      textTheme: GoogleFonts.cairoTextTheme(
        const TextTheme(
          displayLarge: TextStyle(fontSize: 34, fontWeight: FontWeight.w700, color: lTp, letterSpacing: -0.5),
          displayMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: lTp, letterSpacing: -0.3),
          headlineLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: lTp, letterSpacing: -0.2),
          headlineMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: lTp),
          titleLarge: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: lTp),
          titleMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: lTp),
          bodyLarge: TextStyle(fontSize: 17, fontWeight: FontWeight.w400, color: lTp),
          bodyMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w400, color: lTp),
          bodySmall: TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: lTs),
          labelLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: lTp, letterSpacing: 0.1),
          labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: lTs, letterSpacing: 0.5),
        ),
      ),
    );
  }
}
