// The create-room sheet after the 2026-09-06 rework: the two either/or
// decisions (روح الغرفة on step one, كيف تعمل العادة on step two) are pairs
// of cards that each say what they mean, the duration says it can be
// extended, and step two's header carries the spirit along with the name
// and length. Pumped in Arabic at iPhone width, with a real habit list and
// no Firebase.
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
import 'package:grow_daily_v2/features/rooms/widgets/create_room_sheet.dart';

void main() {
  late Directory tmp;
  final s = const S(Locale('ar'));

  setUp(() async {
    NotificationService.instance.celebrationsEnabled = false;
    GoogleFonts.config.allowRuntimeFetching = false;
    tmp = await Directory.systemTemp.createTemp('create_room_sheet_test_');
    Hive.init(tmp.path);
    await Hive.openBox<dynamic>('box_settings');
    await Hive.openBox<dynamic>('box_daily_logs');
    await Hive.openBox<dynamic>('box_habits');
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<ProviderContainer> container() async {
    final c = ProviderContainer(overrides: [
      authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
      habitListProvider
          .overrideWithValue(IslamicHabitCatalog.templates.take(3).toList()),
    ]);
    await c.read(authStateProvider.future);
    return c;
  }

  Widget app(ProviderContainer c, {double textScale = 1.0}) =>
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: GameTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: const Scaffold(body: CreateRoomSheet()),
        ),
      );

  Future<void> pumpSheet(WidgetTester tester, {double textScale = 1.0}) async {
    await tester.binding.setSurfaceSize(const Size(402, 874));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app(await container(), textScale: textScale));
    await tester.pump();
  }

  Future<void> goToHabits(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField).first, 'العائلة');
    await tester.pump();
    await tester.tap(find.text(s.roomCreateNext));
    await tester.pump();
  }

  testWidgets('step one explains both spirits, not just the picked one',
      (tester) async {
    await pumpSheet(tester);
    expect(find.text(s.roomCompeteModeCompetitive), findsOneWidget);
    expect(find.text(s.roomCompeteModeCompetitiveHint), findsOneWidget);
    expect(find.text(s.roomCompeteModeTeam), findsOneWidget);
    expect(find.text(s.roomCompeteModeTeamHint), findsOneWidget);
    expect(find.text(s.roomDurationExtendHint), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the spirit picked on step one is carried into step two',
      (tester) async {
    await pumpSheet(tester);
    await tester.tap(find.text(s.roomCompeteModeTeam));
    await tester.pump();
    await goToHabits(tester);

    expect(find.text(s.roomCreateStepHabitsTitle), findsOneWidget);
    expect(
      find.text(s.roomCreateRoomSummary(
          'العائلة', s.daysCount(14), s.roomCompeteModeTeam)),
      findsOneWidget,
    );
    // Both habit modes explained, same as the spirits.
    expect(find.text(s.roomHabitModeShared), findsOneWidget);
    expect(find.text(s.roomHabitModeSharedHint), findsOneWidget);
    expect(find.text(s.roomHabitModeOwnShort), findsOneWidget);
    expect(find.text(s.roomHabitModeOwnHint), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('picking a habit shows the count and unlocks Create',
      (tester) async {
    await pumpSheet(tester);
    await goToHabits(tester);

    expect(find.text(s.roomCreateNeedsHabit), findsOneWidget);
    expect(find.text(s.roomPlanSelectedCount(1)), findsNothing);

    final first = IslamicHabitCatalog.templates.first.localName(true);
    await tester.tap(find.text(first));
    await tester.pump();

    expect(find.text(s.roomPlanSelectedCount(1)), findsOneWidget);
    expect(find.text(s.roomCreateSubmit), findsOneWidget);
    expect(find.text(s.roomCreateNeedsHabit), findsNothing);
  });

  testWidgets('both steps still fit with large text', (tester) async {
    await pumpSheet(tester, textScale: 1.3);
    expect(tester.takeException(), isNull);
    await goToHabits(tester);
    expect(find.text(s.roomCreateStepHabitsTitle), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
