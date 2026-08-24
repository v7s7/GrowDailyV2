// The first habit is a different job from the fifth.
//
// On a brand new account this sheet opened on an empty text field, nine
// category chips and a greyed-out primary button. Four levels of choice
// before anything happens, put in front of somebody who has not yet seen a
// single square get coloured, and the one control that would get them there
// in one tap - the suggestions - sat below the fold under all of it.
//
// So on an empty account the suggestions lead ("the quickest start"), and
// the text field follows behind an "or write your own" label. Once there is
// at least one habit the old order comes back: by then the form is familiar
// and the suggestions are a shortcut, not the main road.
//
// These lock the ORDER, not the presence, because presence never broke: the
// chips were always on screen, just last.
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
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';
import 'package:grow_daily_v2/features/habits/widgets/add_habit_sheet.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    NotificationService.instance.celebrationsEnabled = false;
    GoogleFonts.config.allowRuntimeFetching = false;
    tmp = await Directory.systemTemp.createTemp('first_habit_test_');
    Hive.init(tmp.path);
    await Hive.openBox<dynamic>('box_settings');
    await Hive.openBox<dynamic>('box_daily_logs');
    await Hive.openBox<dynamic>('box_habits');
  });

  /// A container whose habit list is exactly [habits] - the one input that
  /// decides which layout the sheet uses.
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

  for (final locale in const [Locale('ar'), Locale('en')]) {
    final tag = locale.languageCode;
    final s = S(locale);

    testWidgets('[$tag] an empty account is offered the shortcut first',
        (tester) async {
      final container = await containerWith(const []);
      addTearDown(container.dispose);
      await tester.pumpWidget(app(container, locale));
      await tester.pumpAndSettle();

      final lead = find.text(s.quickestStart);
      expect(lead, findsOneWidget,
          reason: 'the first habit leads with the one-tap suggestions');
      expect(tester.getTopLeft(lead).dy, lessThan(fieldTop(tester)),
          reason: 'and they sit ABOVE the empty name box, not below it');

      final orWrite = find.text(s.orWriteYourOwn);
      expect(orWrite, findsOneWidget,
          reason: 'the field still has to say what it is for');
      expect(tester.getTopLeft(orWrite).dy, lessThan(fieldTop(tester)));
      expect(tester.getTopLeft(orWrite).dy,
          greaterThan(tester.getTopLeft(lead).dy),
          reason: 'suggestions, then "or write your own", then the box');

      // The old heading would be a second, duplicate suggestions block.
      expect(find.text(s.smartSuggestions), findsNothing);
    });

    testWidgets('[$tag] a returning account keeps the form first',
        (tester) async {
      final container =
          await containerWith([IslamicHabitCatalog.templates.first]);
      addTearDown(container.dispose);
      await tester.pumpWidget(app(container, locale));
      await tester.pumpAndSettle();

      expect(find.text(s.quickestStart), findsNothing,
          reason: 'nothing here is anybody\'s quickest start any more');
      expect(find.text(s.orWriteYourOwn), findsNothing,
          reason: 'the box is the main road again, so it needs no apology');

      final suggestions = find.text(s.smartSuggestions);
      expect(suggestions, findsOneWidget,
          reason: 'the shortcut stays available, just underneath');
      expect(tester.getTopLeft(suggestions).dy, greaterThan(fieldTop(tester)));
    });
  }

  testWidgets('typing a name puts the suggestions away, either layout',
      (tester) async {
    final container = await containerWith(const []);
    addTearDown(container.dispose);
    await tester.pumpWidget(app(container, const Locale('ar')));
    await tester.pumpAndSettle();

    const s = S(Locale('ar'));
    expect(find.text(s.quickestStart), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'قيام الليل');
    await tester.pumpAndSettle();

    expect(find.text(s.quickestStart), findsNothing,
        reason: 'once there is a name the shortcut is noise');
    expect(find.text(s.orWriteYourOwn), findsNothing);
    expect(find.text(s.smartSuggestions), findsNothing);
  });
}
