// Add Habit's What step leads with the name box, for everyone.
//
// It used to open on the Build / Quit switch and, on a brand new account, a
// grid of suggestions and an "or write your own" label before the box, with
// the hub's Plans / Add Goal pills above all of it: three things to answer
// before the one thing to do, on a phone screen the keyboard then halves.
// Reported from Android as "it asks the option first, then the input, then
// the category". The page cut down for the first habit turned out to be the
// better page for every habit, so the order is now the same for all: the
// Build / Quit switch, the box, the categories under it, and the suggestions
// under those once a category is picked. What a first habit still does
// differently is the suggestions' label (the quickest way in, not a
// shortcut) and the hub's half, covered in first_habit_hub_test.dart.
//
// 2026-09-08: the Build / Quit choice moved from a quiet link under the form
// to the switch above the box (nobody saw the link), and the suggestions now
// wait for a category pick instead of showing six «مخصص» chips by default.
//
// These lock the ORDER and which controls lead, in both locales.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;

import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/services/notification_service.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';
import 'package:grow_daily_v2/features/habits/widgets/add_habit_sheet.dart';

void main() {
  const dpr = 3.0;
  late Directory tmp;

  setUp(() async {
    NotificationService.instance.celebrationsEnabled = false;
    GoogleFonts.config.allowRuntimeFetching = false;
    tmp = await Directory.systemTemp.createTemp('first_habit_test_');
    Hive.init(tmp.path);
    await Hive.openBox<dynamic>('box_settings');
    await Hive.openBox<dynamic>('box_daily_logs');
    await Hive.openBox<dynamic>('box_habits');
    // A phone, not the 800x600 default: tall enough that the whole What
    // step is on screen and the links under it can be tapped without
    // scrolling.
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
    view.physicalSize = const Size(390 * dpr, 844 * dpr);
    view.devicePixelRatio = dpr;
  });

  tearDown(() async {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
    await Hive.close();
    await tmp.delete(recursive: true);
  });

  /// A container whose habit list is exactly [habits] - the one input that
  /// decides the first-habit trimmings.
  Future<ProviderContainer> containerWith(
      List<IslamicHabitTemplate> habits) async {
    final c = ProviderContainer(overrides: [
      authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
      habitListProvider.overrideWithValue(habits),
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
          theme: GameTheme.light,
          home: const Scaffold(body: AddHabitSheet()),
        ),
      );

  /// Vertical position of the sheet's name box, whatever it is labelled.
  double fieldTop(WidgetTester tester) =>
      tester.getTopLeft(find.byType(TextField).first).dy;

  double topOf(WidgetTester tester, String text) =>
      tester.getTopLeft(find.text(text)).dy;

  for (final locale in const [Locale('ar'), Locale('en')]) {
    final tag = locale.languageCode;
    final s = S(locale);

    /// The order every account gets; [suggestionsLabel] is the one word
    /// that differs between a first habit and a returning account.
    Future<void> expectBoxFirst(
      WidgetTester tester, {
      required String suggestionsLabel,
    }) async {
      expect(find.byType(TextField), findsWidgets);
      // Above the box: the heading and the Build / Quit switch, nothing else.
      final above = find.byType(Text).evaluate().where((e) {
        final box = e.renderObject as RenderBox?;
        return box != null &&
            box.hasSize &&
            box.localToGlobal(Offset.zero).dy < fieldTop(tester);
      });
      expect(above.length, lessThanOrEqualTo(3),
          reason: 'only the heading and the two switch labels sit above the box');
      expect(find.text(s.goalTypeBuildOption), findsOneWidget);
      expect(find.text(s.goalTypeQuitOption), findsOneWidget);
      expect(topOf(tester, s.goalTypeBuildOption), lessThan(fieldTop(tester)),
          reason: 'the kind of habit is decided right above the box');

      expect(find.text(s.category), findsOneWidget);
      expect(topOf(tester, s.category), greaterThan(fieldTop(tester)),
          reason: 'the box first, the categories under it');

      expect(find.text(suggestionsLabel), findsNothing,
          reason: 'no suggestions until a category is picked');
      expect(find.text(s.categoryPickHint), findsOneWidget,
          reason: 'and the label says so');

      await tester.ensureVisible(
          find.text(HabitCategory.faith.localizedName(s.isAr)));
      await tester.tap(find.text(HabitCategory.faith.localizedName(s.isAr)));
      await tester.pumpAndSettle();

      expect(find.text(suggestionsLabel), findsOneWidget,
          reason: 'picking a category brings the one-tap suggestions');
      expect(topOf(tester, suggestionsLabel),
          greaterThan(topOf(tester, s.category)),
          reason: 'under the categories, never before the box');
      expect(find.text(s.categoryPickHint), findsNothing);

      // The Plans link needs a hub to go to, so standalone it is not drawn.
      expect(find.text(s.readyPlansLink), findsNothing);
    }

    testWidgets('[$tag] an empty account opens on the box, categories under it',
        (tester) async {
      final container = await containerWith(const []);
      addTearDown(container.dispose);
      await tester.pumpWidget(app(container, locale));
      await tester.pumpAndSettle();

      await expectBoxFirst(tester, suggestionsLabel: s.quickestStart);
      expect(find.text(s.smartSuggestions), findsNothing);
    });

    testWidgets('[$tag] a returning account gets the same page, relabelled',
        (tester) async {
      final container =
          await containerWith([IslamicHabitCatalog.templates.first]);
      addTearDown(container.dispose);
      await tester.pumpWidget(app(container, locale));
      await tester.pumpAndSettle();

      await expectBoxFirst(tester, suggestionsLabel: s.smartSuggestions);
      expect(find.text(s.quickestStart), findsNothing,
          reason: 'nothing here is anybody\'s quickest start any more');
    });

    testWidgets('[$tag] the switch flips the form and back',
        (tester) async {
      final container = await containerWith(const []);
      addTearDown(container.dispose);
      await tester.pumpWidget(app(container, locale));
      await tester.pumpAndSettle();

      expect(find.text(s.whatHabitBuild), findsOneWidget,
          reason: 'the box asks the Build question to start with');
      expect(find.text(s.goalStyle), findsNothing);

      await tester.tap(find.text(s.goalTypeQuitOption));
      await tester.pumpAndSettle();

      expect(find.text(s.whatReduce), findsOneWidget,
          reason: 'the box now asks the Quit question');
      expect(find.text(s.goalStyle), findsOneWidget,
          reason: 'and the avoid / limit choice appears');
      expect(find.text(s.goalTypeBuildOption), findsOneWidget,
          reason: 'both picks stay on screen; the other is the way back');

      await tester.tap(find.text(s.goalTypeBuildOption));
      await tester.pumpAndSettle();

      expect(find.text(s.whatHabitBuild), findsOneWidget);
      expect(find.text(s.goalStyle), findsNothing);
    });
  }

  testWidgets('typing a name puts the suggestions away, either layout',
      (tester) async {
    final container = await containerWith(const []);
    addTearDown(container.dispose);
    await tester.pumpWidget(app(container, const Locale('ar')));
    await tester.pumpAndSettle();

    const s = S(Locale('ar'));
    await tester.ensureVisible(find.text(HabitCategory.faith.localizedName(true)));
    await tester.tap(find.text(HabitCategory.faith.localizedName(true)));
    await tester.pumpAndSettle();
    expect(find.text(s.quickestStart), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'قيام الليل');
    await tester.pumpAndSettle();

    expect(find.text(s.quickestStart), findsNothing,
        reason: 'once there is a name the shortcut is noise');
    expect(find.text(s.smartSuggestions), findsNothing);
    expect(find.text(s.goalTypeQuitOption), findsOneWidget,
        reason: 'the switch is not about the name, so it stays');
  });
}
