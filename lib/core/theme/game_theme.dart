import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

// ─── Gamification Colors (theme-invariant) ────────────────────────────────────

abstract final class GameColors {
  // Warm amber + emerald gives the app a calmer deen/productivity identity than
  // bright arcade gold, while keeping reward moments visible.
  static const Color gold = Color(0xFFE4B45F);
  static const Color goldDim = Color(0xFF9C7436);
  static const Color emerald = Color(0xFF2ECF8F);
  static const Color emeraldDim = Color(0xFF188A61);
  static const Color xpBlue = Color(0xFF5DADEC);
  static const Color xpBlueDim = Color(0xFF236EA8);
  static const Color streakOrange = Color(0xFFFF8A4C);
  static const Color streakOrangeDim = Color(0xFFC95B22);
  static const Color success = emerald;
  static const Color error = Color(0xFFFF5A52);
  static const Color warning = Color(0xFFF7C948);
  static const Color rarityCommon = Color(0xFF8C9A92);
  static const Color rarityUncommon = emerald;
  static const Color rarityRare = xpBlue;
  static const Color rarityEpic = Color(0xFFB982FF);
  static const Color rarityLegendary = gold;

  // Dark-mode structural — kept for const TextStyles & ThemeData construction.
  static const Color background = Color(0xFF07100D);
  static const Color surface = Color(0xFF101B17);
  static const Color surfaceElevated = Color(0xFF17251F);
  static const Color surfaceHighlight = Color(0xFF20332B);
  static const Color textPrimary = Color(0xFFF7F3E8);
  static const Color textSecondary = Color(0xFFB5BCA8);
  static const Color textTertiary = Color(0xFF6F7A70);
  static const Color border = Color(0xFF2D4037);
  static const Color divider = Color(0xFF22352D);
}

// ─── Adaptive Palette — widgets call context.gp.* ────────────────────────────

class _GamePalette {
  final bool dark;
  const _GamePalette(this.dark);

  Color get bg => dark ? GameColors.background : const Color(0xFFFFFCF5);
  Color get surface => dark ? GameColors.surface : const Color(0xFFF5EFE3);
  Color get surfaceHigh => dark ? GameColors.surfaceElevated : Colors.white;
  Color get surfaceHL => dark ? GameColors.surfaceHighlight : const Color(0xFFEADFCB);
  Color get textPrimary => dark ? GameColors.textPrimary : const Color(0xFF18251F);
  Color get textSec => dark ? GameColors.textSecondary : const Color(0xFF657166);
  Color get textTert => dark ? GameColors.textTertiary : const Color(0xFF9AA397);
  Color get border => dark ? GameColors.border : const Color(0xFFD8CDBA);
  Color get divider => dark ? GameColors.divider : const Color(0xFFE8DDCB);
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
  static const TextStyle xpLabel = TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: GameColors.xpBlue, letterSpacing: 0.5, height: 1.2, fontFamilyFallback: fontFallback);
  static const TextStyle goldLabel = TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: GameColors.gold, letterSpacing: 0.5, height: 1.2, fontFamilyFallback: fontFallback);
  static const TextStyle levelDisplay = TextStyle(fontSize: 40, fontWeight: FontWeight.w800, color: GameColors.gold, letterSpacing: -1.0, height: 1.05, fontFamilyFallback: fontFallback);
  static const TextStyle streakDisplay = TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: GameColors.streakOrange, letterSpacing: -0.8, height: 1.05, fontFamilyFallback: fontFallback);

  static const TextStyle arabicTitle = TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: GameColors.textPrimary, height: 1.55, fontFamilyFallback: fontFallback);
  static const TextStyle arabicBody = TextStyle(fontSize: 16, fontWeight: FontWeight.w400, color: GameColors.textPrimary, height: 1.65, fontFamilyFallback: fontFallback);
  static const TextStyle arabicLabel = TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: GameColors.gold, height: 1.45, fontFamilyFallback: fontFallback);
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
  final fill = dark ? GameColors.surface : const Color(0xFFF5EFE3);
  final bd = dark ? GameColors.border : const Color(0xFFD8CDBA);
  final hint = dark ? GameColors.textTertiary : const Color(0xFF9AA397);
  final label = dark ? GameColors.textSecondary : const Color(0xFF657166);
  return InputDecorationTheme(
    filled: true,
    fillColor: fill,
    contentPadding: const EdgeInsets.symmetric(horizontal: GameSpacing.lg, vertical: GameSpacing.md),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(GameSpacing.buttonRadius), borderSide: BorderSide(color: bd, width: 0.5)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(GameSpacing.buttonRadius), borderSide: BorderSide(color: bd, width: 0.5)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(GameSpacing.buttonRadius), borderSide: const BorderSide(color: GameColors.gold)),
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
    floatingLabelStyle: const TextStyle(
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
        indicatorColor: const Color(0x2EE4B45F),
        iconTheme: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
            ? const IconThemeData(color: GameColors.gold, size: 24)
            : const IconThemeData(color: GameColors.textTertiary, size: 24)),
        labelTextStyle: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
            ? const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: GameColors.gold, fontFamilyFallback: GameTextStyles.fontFallback)
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
    const Color lBg = Color(0xFFFFFCF5);
    const Color lCard = Color(0xFFF5EFE3);
    const Color lHigh = Colors.white;
    const Color lHL = Color(0xFFEADFCB);
    const Color lTp = Color(0xFF18251F);
    const Color lTs = Color(0xFF657166);
    const Color lTt = Color(0xFF9AA397);
    const Color lBd = Color(0xFFD8CDBA);
    const Color lDv = Color(0xFFE8DDCB);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamilyFallback: GameTextStyles.fontFallback,
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
          textStyle: GameTextStyles.labelLarge,
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
        indicatorColor: const Color(0x2EE4B45F),
        iconTheme: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
            ? const IconThemeData(color: GameColors.gold, size: 24)
            : IconThemeData(color: lTt, size: 24)),
        labelTextStyle: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
            ? const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: GameColors.gold, fontFamilyFallback: GameTextStyles.fontFallback)
            : TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: lTt, fontFamilyFallback: GameTextStyles.fontFallback)),
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
        titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: lTp, fontFamilyFallback: GameTextStyles.fontFallback),
        contentTextStyle: TextStyle(fontSize: 15, color: lTs, fontFamilyFallback: GameTextStyles.fontFallback),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: lBg,
        contentTextStyle: const TextStyle(fontSize: 15, color: lTp, fontFamilyFallback: GameTextStyles.fontFallback),
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
