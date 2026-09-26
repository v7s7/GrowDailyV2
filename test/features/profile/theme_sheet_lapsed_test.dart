// The theme picker for an account whose Premium ended while it wore a
// Premium theme. The theme stays until sign-out, and the picker has to say
// so: until 2026-09-26 the theme in use carried a padlock where its check
// belongs (and the custom card a «Premium» pill instead of its check), so
// the sheet showed nothing selected and a tap on what you are wearing
// opened the paywall.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/core/constants/game_constants.dart';
import 'package:grow_daily_v2/core/providers/theme_provider.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/core/theme/theme_preset.dart';
import 'package:grow_daily_v2/features/premium/notifiers/premium_notifier.dart';
import 'package:grow_daily_v2/features/premium/screens/premium_screen.dart';
import 'package:grow_daily_v2/features/profile/screens/profile_screen.dart';

void main() {
  // Opened before any test body: real disk I/O started inside testWidgets
  // never finishes (see LandingHarness).
  setUp(() async {
    final tmp = await Directory.systemTemp.createTemp('theme_sheet_lapsed_');
    Hive.init(tmp.path);
    await Hive.openBox<dynamic>(GameConstants.boxSettings);
  });

  Future<void> openThemeSheet(WidgetTester tester, String wearing) async {
    await tester.binding.setSurfaceSize(const Size(402, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          premiumAccessProvider.overrideWithValue(false),
          themePresetProvider.overrideWith((ref) => ThemePresetNotifier(wearing)),
        ],
        child: MaterialApp(
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: GameTheme.light,
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
  }

  /// The row of the sheet's tile named [label].
  Finder tileRow(String label) => find
      .ancestor(
        of: find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text(label),
        ),
        matching: find.byType(Row),
      )
      .first;

  testWidgets('the Premium theme in use keeps its check, not a padlock',
      (tester) async {
    await openThemeSheet(tester, 'sage');
    final sage = tileRow('Sage');
    expect(
      find.descendant(of: sage, matching: find.byIcon(Icons.check_circle_rounded)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sage, matching: find.byIcon(Icons.lock_rounded)),
      findsNothing,
    );
    // Another Premium theme is still locked, and still the paywall.
    expect(
      find.descendant(
        of: tileRow('Ocean'),
        matching: find.byIcon(Icons.lock_rounded),
      ),
      findsOneWidget,
    );

    // Choosing what you are wearing changes nothing, and sells nothing.
    await tester.tap(find.descendant(
      of: find.byType(BottomSheet),
      matching: find.text('Sage'),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(PremiumScreen), findsNothing);
  });

  testWidgets('the custom theme in use keeps its check beside the pill',
      (tester) async {
    await openThemeSheet(tester, ThemePresets.customId);
    final card = tileRow('Your own colours');
    expect(
      find.descendant(of: card, matching: find.byIcon(Icons.check_circle_rounded)),
      findsOneWidget,
    );
    expect(find.descendant(of: card, matching: find.text('Premium')),
        findsOneWidget,
        reason: 'changing the colours is still Premium\'s');
  });
}
