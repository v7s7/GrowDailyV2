// Editing a habit that carries several reminder times must not destroy it.
//
// This is the destructive path, and it was destructive by default. A cue
// holding two times fails the old single-value regex, falls through to the
// freeform branch, and comes back as TEXT — so reopening the sheet used to
// land in Custom Text mode with the literal token `custom_time:00:00,12:00`
// sitting in an editable field. Saving from there re-parses that token as
// freeform, and both times are gone, through an edit the person never
// intended to make.
//
// So the parser, the restore and the storage format have to ship together,
// and this is what proves they did: open on a real two-time habit, advance to
// the timing step, and the two times are there as times.
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
import 'package:grow_daily_v2/features/habits/models/habit_cue.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/habits/widgets/add_habit_sheet.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    NotificationService.instance.celebrationsEnabled = false;
    GoogleFonts.config.allowRuntimeFetching = false;
    tmp = await Directory.systemTemp.createTemp('multi_time_edit_');
    Hive.init(tmp.path);
    await Hive.openBox<dynamic>('box_settings');
    await Hive.openBox<dynamic>('box_daily_logs');
    await Hive.openBox<dynamic>('box_habits');
  });

  tearDown(() async {
    await Hive.close();
    await tmp.delete(recursive: true);
  });

  /// Aziz's protein habit as it lands on disk: twice a day, midnight and noon.
  IslamicHabitTemplate protein({String cue = 'custom_time:00:00,12:00'}) =>
      IslamicHabitTemplate(
        id: 'h-protein',
        name: 'Protein',
        nameAr: 'بروتين',
        description: '',
        cueAfter: cue,
        category: HabitCategory.health,
        frequencyType: HabitFrequencyType.daily,
        frequencyTarget: 2,
        hasTimer: false,
        xpReward: 20,
        goldReward: 5,
      );

  Future<ProviderContainer> boot() async {
    final c = ProviderContainer(overrides: [
      authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
    ]);
    await c.read(authStateProvider.future);
    return c;
  }

  Widget app(ProviderContainer container, IslamicHabitTemplate existing) =>
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: GameTheme.dark,
          home: Scaffold(body: AddHabitSheet(existing: existing)),
        ),
      );

  testWidgets('a two-time habit reopens as two times, not as raw text',
      (tester) async {
    final container = await boot();
    addTearDown(container.dispose);
    await tester.pumpWidget(app(container, protein()));
    await tester.pumpAndSettle();

    final s = S(const Locale('en'));

    // The token must never be shown to anybody, on any step.
    expect(find.textContaining('custom_time'), findsNothing,
        reason: 'the storage token is not user-facing text');

    // Step one holds the name; the times live on step two.
    await tester.tap(find.text(s.continueAction));
    await tester.pumpAndSettle();

    expect(find.text('12:00 AM'), findsOneWidget);
    expect(find.text('12:00 PM'), findsOneWidget);
    expect(find.text(s.pickATime), findsNothing,
        reason: 'both slots are filled, so neither row is still empty');
    expect(find.textContaining('custom_time'), findsNothing);
  });

  testWidgets('the count follows the stored times, never fewer pickers',
      (tester) async {
    // The two sources of N can legitimately disagree on a real document — a
    // habit edited from 3x to 2x keeps three stored times until it is saved.
    // The larger wins, so the third time is never silently dropped by an edit
    // that only ever rendered two rows.
    final container = await boot();
    addTearDown(container.dispose);
    await tester.pumpWidget(app(
      container,
      protein(cue: 'custom_time:06:00,12:00,18:00'),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text(S(const Locale('en')).continueAction));
    await tester.pumpAndSettle();

    expect(find.text('6:00 AM'), findsOneWidget);
    expect(find.text('12:00 PM'), findsOneWidget);
    expect(find.text('6:00 PM'), findsOneWidget);
  });

  testWidgets('a single-time habit is untouched by any of this', (tester) async {
    // The backward-compatibility half: every habit that exists today has one
    // time, and its screen must look exactly as it did.
    final container = await boot();
    addTearDown(container.dispose);
    await tester.pumpWidget(app(container, protein(cue: 'custom_time:07:30')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(S(const Locale('en')).continueAction));
    await tester.pumpAndSettle();

    expect(find.text('7:30 AM'), findsOneWidget);
    // Its stored form is byte-identical, which is what makes re-saving an
    // untouched habit a no-op rather than a migration.
    expect(
      HabitCue.fromStoredValue('custom_time:07:30').toStorageValue(),
      'custom_time:07:30',
    );
  });

  testWidgets('a damaged cue degrades to no time, never to editable text',
      (tester) async {
    final container = await boot();
    addTearDown(container.dispose);
    await tester.pumpWidget(app(container, protein(cue: 'custom_time:9x:99')));
    await tester.pumpAndSettle();

    expect(find.textContaining('custom_time'), findsNothing,
        reason: 'damage must not be rendered back as if the user typed it');
  });
}
