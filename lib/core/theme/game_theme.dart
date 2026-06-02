import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─── Color Tokens ────────────────────────────────────────────────────────────

abstract final class GameColors {
  // Backgrounds
  static const Color background = Color(0xFF000000);
  static const Color surface = Color(0xFF1C1C1E);
  static const Color surfaceElevated = Color(0xFF2C2C2E);
  static const Color surfaceHighlight = Color(0xFF3A3A3C);

  // Gamification — primary hits
  static const Color gold = Color(0xFFF5C533);
  static const Color goldDim = Color(0xFFB8941F);
  static const Color xpBlue = Color(0xFF4A9EFF);
  static const Color xpBlueDim = Color(0xFF1C6EC4);
  static const Color streakOrange = Color(0xFFFF6B35);
  static const Color streakOrangeDim = Color(0xFFCC4A1A);

  // Semantic
  static const Color success = Color(0xFF34C759);
  static const Color error = Color(0xFFFF3B30);
  static const Color warning = Color(0xFFFFCC00);

  // Text hierarchy
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF8E8E93);
  static const Color textTertiary = Color(0xFF48484A);

  // Structural
  static const Color border = Color(0xFF38383A);
  static const Color divider = Color(0xFF2C2C2E);

  // Achievement rarity
  static const Color rarityCommon = Color(0xFF8E8E93);
  static const Color rarityUncommon = Color(0xFF34C759);
  static const Color rarityRare = Color(0xFF4A9EFF);
  static const Color rarityEpic = Color(0xFFBF5AF2);
  static const Color rarityLegendary = Color(0xFFF5C533);
}

// ─── Typography ──────────────────────────────────────────────────────────────

abstract final class GameTextStyles {
  static const TextStyle displayLarge = TextStyle(
    fontSize: 34,
    fontWeight: FontWeight.w700,
    color: GameColors.textPrimary,
    letterSpacing: -0.5,
  );

  static const TextStyle displayMedium = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: GameColors.textPrimary,
    letterSpacing: -0.3,
  );

  static const TextStyle headlineLarge = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    color: GameColors.textPrimary,
    letterSpacing: -0.2,
  );

  static const TextStyle headlineMedium = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: GameColors.textPrimary,
  );

  static const TextStyle titleLarge = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    color: GameColors.textPrimary,
  );

  static const TextStyle titleMedium = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: GameColors.textPrimary,
  );

  static const TextStyle bodyLarge = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w400,
    color: GameColors.textPrimary,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: GameColors.textPrimary,
  );

  static const TextStyle bodySmall = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: GameColors.textSecondary,
  );

  static const TextStyle labelLarge = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: GameColors.textPrimary,
    letterSpacing: 0.1,
  );

  static const TextStyle labelSmall = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: GameColors.textSecondary,
    letterSpacing: 0.5,
  );

  // Game-specific text styles
  static const TextStyle xpLabel = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w700,
    color: GameColors.xpBlue,
    letterSpacing: 0.5,
  );

  static const TextStyle goldLabel = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w700,
    color: GameColors.gold,
    letterSpacing: 0.5,
  );

  static const TextStyle levelDisplay = TextStyle(
    fontSize: 40,
    fontWeight: FontWeight.w800,
    color: GameColors.gold,
    letterSpacing: -1.0,
  );

  static const TextStyle streakDisplay = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w800,
    color: GameColors.streakOrange,
    letterSpacing: -0.8,
  );
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

  static const EdgeInsets screenPadding =
      EdgeInsets.symmetric(horizontal: lg);
  static const EdgeInsets cardPadding = EdgeInsets.all(lg);
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
      appBarTheme: const AppBarTheme(
        backgroundColor: GameColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
        titleTextStyle: GameTextStyles.titleLarge,
        iconTheme: IconThemeData(color: GameColors.textPrimary),
        actionsIconTheme: IconThemeData(color: GameColors.gold),
      ),
      cardTheme: CardThemeData(
        color: GameColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
          side: const BorderSide(
            color: GameColors.border,
            width: 0.5,
          ),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(GameSpacing.buttonRadius),
          ),
          textStyle: GameTextStyles.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: GameColors.gold,
          side: const BorderSide(color: GameColors.gold),
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(GameSpacing.buttonRadius),
          ),
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
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: GameColors.gold, size: 24);
          }
          return const IconThemeData(color: GameColors.textTertiary, size: 24);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: GameColors.gold,
            );
          }
          return const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w400,
            color: GameColors.textTertiary,
          );
        }),
        elevation: 0,
        height: 72,
      ),
      dividerTheme: const DividerThemeData(
        color: GameColors.divider,
        space: 1,
        thickness: 0.5,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: GameColors.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        ),
        titleTextStyle: GameTextStyles.headlineMedium,
        contentTextStyle: const TextStyle(
          fontSize: 15,
          color: GameColors.textSecondary,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: GameColors.surfaceElevated,
        contentTextStyle: GameTextStyles.bodyMedium,
        actionTextColor: GameColors.gold,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GameSpacing.chipRadius),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: GameColors.xpBlue,
        circularTrackColor: GameColors.surfaceElevated,
        linearTrackColor: GameColors.surfaceElevated,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return GameColors.background;
          }
          return GameColors.textTertiary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return GameColors.gold;
          return GameColors.surfaceElevated;
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: GameColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: GameSpacing.lg,
          vertical: GameSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(GameSpacing.buttonRadius),
          borderSide: const BorderSide(color: GameColors.border, width: 0.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(GameSpacing.buttonRadius),
          borderSide: const BorderSide(color: GameColors.border, width: 0.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(GameSpacing.buttonRadius),
          borderSide: const BorderSide(color: GameColors.gold),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(GameSpacing.buttonRadius),
          borderSide: const BorderSide(color: GameColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(GameSpacing.buttonRadius),
          borderSide: const BorderSide(color: GameColors.error),
        ),
        hintStyle: const TextStyle(
          fontSize: 15,
          color: GameColors.textTertiary,
        ),
        labelStyle: const TextStyle(
          fontSize: 15,
          color: GameColors.textSecondary,
        ),
        floatingLabelStyle: const TextStyle(
          fontSize: 12,
          color: GameColors.gold,
        ),
      ),
      textTheme: const TextTheme(
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
    );
  }
}
