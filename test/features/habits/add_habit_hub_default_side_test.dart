// The Plans / Add Goal switcher at the top of the Add Habit hub keeps the
// form's pill, the hub's default tab, on the edge where reading starts.
//
// This used to guard two rows: the switcher, and the Build / Quit switch
// that sat directly under it in the form, which had to keep their defaults
// on the same edge so the highlight did not jump between two questions read
// as one. What is left to pin is the first row on its own: the Add Goal
// pill sits at the reading-start edge, right in Arabic and left in English.
//
// Since the three-step page (canvas v8, 2026-10-01) the hub opens on the
// form with no pills at all, for every account, so the switcher is only on
// screen in two states: opened on Plans (the Grid's «استعرض الخطط»), and
// after a plan was picked on the ideas page that step 1's card «أفكار وخطط
// جاهزة» opens (until later that day it was a Plans card inside an inline
// ideas door on the form). Both are pinned here.
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
import 'package:grow_daily_v2/features/habits/catalog/habit_ideas.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';
import 'package:grow_daily_v2/features/habits/widgets/add_habit_hub_sheet.dart';

import 'support/add_habit_flow.dart';

void main() {
  late Directory tmp;

  setUpAll(preloadIdeas);

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

  // One habit on the account. It no longer decides whether the switcher
  // shows (nobody gets it on the form's first screen now), so this is just
  // an ordinary returning account.
  Future<ProviderContainer> boot() async {
    final c = ProviderContainer(overrides: [
      authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
      habitListProvider
          .overrideWithValue([IslamicHabitCatalog.templates.first]),
    ]);
    await c.read(authStateProvider.future);
    return c;
  }

  Widget app(ProviderContainer container, Locale locale, HubTab tab) =>
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
          home: Scaffold(body: AddHabitHub(initialTab: tab)),
        ),
      );

  for (final locale in const [Locale('ar'), Locale('en')]) {
    final tag = locale.languageCode;
    final s = S(locale);

    /// The form's pill against the Plans pill, on the Plans tab (the form is
    /// offstage there, so each label is drawn once, in its pill).
    void expectFormPillAtReadingEdge(WidgetTester tester) {
      double centerX(String label) =>
          tester.getCenter(find.text(label).first).dx;

      // The hub's default tab, and the other one.
      final defaultTab = centerX(s.addGoalTitle);
      final otherTab = centerX(s.plansTab);

      // Guard the guard: a row whose two halves collapsed onto each other
      // would satisfy the comparison below without meaning anything.
      expect((defaultTab - otherTab).abs(), greaterThan(40),
          reason: 'the two tabs are not laid out side by side');

      if (locale.languageCode == 'ar') {
        expect(defaultTab, greaterThan(otherTab),
            reason: 'in Arabic the form\'s tab belongs on the right, '
                'where reading starts');
      } else {
        expect(defaultTab, lessThan(otherTab),
            reason: 'in English the form\'s tab belongs on the left');
      }
    }

    testWidgets('[$tag] opened on Plans, the form\'s pill is at the reading '
        'edge', (tester) async {
      final container = await boot();
      addTearDown(container.dispose);
      await tester.pumpWidget(app(container, locale, HubTab.plans));
      await tester.pumpAndSettle();

      expectFormPillAtReadingEdge(tester);
    });

    testWidgets('[$tag] after a plan picked on the ideas page, the form\'s '
        'pill is at the reading edge', (tester) async {
      final container = await boot();
      addTearDown(container.dispose);
      await tester.pumpWidget(app(container, locale, HubTab.addGoal));
      await tester.pumpAndSettle();
      expect(find.text(s.addGoalTitle), findsNothing,
          reason: 'sanity: no switcher on the form\'s first screen');

      await openIdeas(tester, s, withPlans: true);
      await tester.tap(find.text(shownPlans().first.name(s.isAr)));
      await tester.pumpAndSettle();
      expect(find.text(s.addGoalTitle), findsOneWidget,
          reason: 'sanity: the plan opened on the Plans tab, with the pills');

      expectFormPillAtReadingEdge(tester);
    });
  }
}
