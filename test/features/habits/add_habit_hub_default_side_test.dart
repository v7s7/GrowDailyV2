// The Plans / Add Goal switcher at the top of the Add Habit hub opens with
// its default on the edge where reading starts.
//
// This used to guard two rows: the switcher, and the Build / Quit switch
// that sat directly under it in the form, which had to keep their defaults
// on the same edge so the highlight did not jump between two questions read
// as one. The second row is gone (the Build / Quit choice is a link under
// the form now, see first_habit_layout_test.dart), so what is left to pin
// is the first row on its own: the pill the sheet opens on sits at the
// reading-start edge, right in Arabic and left in English.
//
// Measured as GEOMETRY, in both locales, because "first child in the Row" is
// an implementation detail that says nothing about which edge it lands on;
// only the text direction resolves that, and it is the resolved position the
// user actually sees.
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/services/notification_service.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';
import 'package:grow_daily_v2/features/habits/widgets/add_habit_hub_sheet.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    NotificationService.instance.celebrationsEnabled = false;
    GoogleFonts.config.allowRuntimeFetching = false;
    tmp = await Directory.systemTemp.createTemp('hub_default_side_test_');
    Hive.init(tmp.path);
    await Hive.openBox<dynamic>('box_settings');
    await Hive.openBox<dynamic>('box_daily_logs');
    await Hive.openBox<dynamic>('box_habits');
  });

  tearDown(() async {
    await Hive.close();
    await tmp.delete(recursive: true);
  });

  // One habit on the account: a first habit opens with no switcher at all
  // (see first_habit_hub_test.dart), and this test is about the switcher.
  Future<ProviderContainer> boot() async {
    final c = ProviderContainer(overrides: [
      authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
      habitListProvider
          .overrideWithValue([IslamicHabitCatalog.templates.first]),
    ]);
    await c.read(authStateProvider.future);
    return c;
  }

  Widget app(ProviderContainer container, Locale locale) =>
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: locale,
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: GameTheme.dark,
          home: const Scaffold(
            body: AddHabitHub(initialTab: HubTab.addGoal),
          ),
        ),
      );

  for (final locale in const [Locale('ar'), Locale('en')]) {
    final tag = locale.languageCode;
    final s = S(locale);

    testWidgets('[$tag] the switcher opens with its default at the reading edge',
        (tester) async {
      final container = await boot();
      addTearDown(container.dispose);
      await tester.pumpWidget(app(container, locale));
      await tester.pumpAndSettle();

      double centerX(String label) =>
          tester.getCenter(find.text(label).first).dx;

      // The tab the sheet opens on, and the one it doesn't.
      final defaultTab = centerX(s.addGoalTitle);
      final otherTab = centerX(s.plansTab);

      // Guard the guard: a row whose two halves collapsed onto each other
      // would satisfy the comparison below without meaning anything.
      expect((defaultTab - otherTab).abs(), greaterThan(40),
          reason: 'the two tabs are not laid out side by side');

      if (locale.languageCode == 'ar') {
        expect(defaultTab, greaterThan(otherTab),
            reason: 'in Arabic the already-chosen tab belongs on the right, '
                'where reading starts');
      } else {
        expect(defaultTab, lessThan(otherTab),
            reason: 'in English the already-chosen tab belongs on the left');
      }
    });
  }
}
