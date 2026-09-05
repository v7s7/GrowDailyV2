// The two choices stacked at the top of the Add Habit hub must have their
// DEFAULT on the same edge of the screen.
//
// The hub asks two questions one under the other: «إضافة هدف / خطط جاهزة»,
// then «أبني عادة / أترك أو أقلل عادة». Both open on their first option. But
// the rows were built in opposite orders, so in Arabic the first row's default
// sat on the left while the second row's sat on the right — the highlight
// jumped across the sheet between two questions that are read as one. Somebody
// opening the sheet had to find the selected pill twice.
//
// The rule, stated the way a user would: whatever is already chosen when the
// sheet opens is on the same side in both rows, so the only thing left to
// decide is whether to step sideways off it.
//
// Measured as GEOMETRY, in both locales, because "first child in the Row" is
// an implementation detail that says nothing about which edge it lands on —
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

  Future<ProviderContainer> boot() async {
    final c = ProviderContainer(overrides: [
      authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
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

    testWidgets('[$tag] both rows open with their default on the same edge',
        (tester) async {
      final container = await boot();
      addTearDown(container.dispose);
      await tester.pumpWidget(app(container, locale));
      await tester.pumpAndSettle();

      double centerX(String label) =>
          tester.getCenter(find.text(label).first).dx;

      // Row 1: the tab the sheet opens on, and the one it doesn't.
      final defaultTab = centerX(s.addGoalTitle);
      final otherTab = centerX(s.plansTab);
      // Row 2: the goal type the form opens on, and the one it doesn't.
      final defaultType = centerX(s.buildHabitTitle);
      final otherType = centerX(s.quitHabitTitle);

      // Guard the guard: a row whose two halves collapsed onto each other
      // would satisfy every comparison below without meaning anything.
      expect((defaultTab - otherTab).abs(), greaterThan(40),
          reason: 'the two tabs are not laid out side by side');
      expect((defaultType - otherType).abs(), greaterThan(40),
          reason: 'the two goal types are not laid out side by side');

      if (locale.languageCode == 'ar') {
        expect(defaultTab, greaterThan(otherTab),
            reason: 'in Arabic the already-chosen tab belongs on the right, '
                'where reading starts');
        expect(defaultType, greaterThan(otherType),
            reason: 'in Arabic the already-chosen goal type belongs on the '
                'right, where reading starts');
      } else {
        expect(defaultTab, lessThan(otherTab),
            reason: 'in English the already-chosen tab belongs on the left');
        expect(defaultType, lessThan(otherType),
            reason: 'in English the already-chosen goal type belongs on the '
                'left');
      }

      // And the point of all of it: the two defaults are stacked, not
      // diagonal. One eye position, not two.
      expect((defaultTab - defaultType).abs(), lessThan(24),
          reason: 'the two defaults sit on opposite sides of the sheet, so '
              'the highlight jumps between the first question and the second');
    });
  }
}
