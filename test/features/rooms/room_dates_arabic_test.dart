// A room's two dates, in Arabic under the real localization delegates.
//
//  * The header's start line, DateFormat('d MMMM'): «بدأت ١ سبتمبر».
//  * The lobby's start caption under the countdown, DateFormat('EEE, MMM d')
//    and DateFormat('h:mm a'): «يبدأ الأربعاء, سبتمبر ٢٣ · ٨:٠٠ م», month
//    first, a Latin comma, Arabic-Indic digits, under countdown boxes
//    numbered in Latin.
//
// Pumped as the whole RoomDetailScreen with every stream overridden and
// nobody signed in, so the screen's own sync (which only runs for a member
// with linked habits) never reaches Firestore.
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';

import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/rooms/models/room_model.dart';
import 'package:grow_daily_v2/features/rooms/notifiers/rooms_notifier.dart';
import 'package:grow_daily_v2/features/rooms/screens/room_detail_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final arabicIndic = RegExp('[٠-٩]');

  setUp(() async {
    // Initialised, never opened: anything on this screen that reaches for a
    // box waits on it harmlessly instead of writing from the fake-async zone.
    Hive.init((await Directory.systemTemp.createTemp('room_dates_')).path);
  });

  RoomModel room({
    required DateTime startDate,
    String status = 'active',
    DateTime? scheduledStartAt,
  }) =>
      RoomModel(
        code: 'DATES1',
        name: 'غرفة التواريخ',
        createdBy: 'leader-uid',
        createdByName: 'Leader',
        createdAt: DateTime(2026, 8, 20),
        habitMode: RoomHabitMode.shared,
        duration: RoomDuration.fixed,
        startDate: startDate,
        endDate: startDate.add(const Duration(days: 30)),
        status: status,
        scheduledStartAt: scheduledStartAt,
        sharedHabits: const [
          RoomHabitTemplate(
            name: 'قراءة',
            category: HabitCategory.faith,
            frequencyType: HabitFrequencyType.daily,
            frequencyTarget: 1,
          ),
        ],
      );

  final leader = RoomParticipant(
    uid: 'leader-uid',
    displayName: 'Leader',
    characterId: 'male_ghutra_blue',
    joinedAt: DateTime(2026, 8, 20),
    linkedHabitIds: const [],
    lastUpdated: DateTime(2026, 8, 20),
  );

  Future<void> pump(WidgetTester tester, RoomModel r) async {
    tester.view.physicalSize = const Size(400 * 3, 1600 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
        roomProvider.overrideWith((ref, code) => Stream<RoomModel?>.value(r)),
        roomParticipantsProvider.overrideWith(
            (ref, code) => Stream<List<RoomParticipant>>.value([leader])),
        roomRosterHistoryProvider.overrideWith(
            (ref, code) => Stream<List<RoomParticipant>>.value([leader])),
      ],
      child: MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: GameTheme.dark,
        home: const RoomDetailScreen(code: 'DATES1'),
      ),
    ));
    // Not pumpAndSettle: the lobby countdown ticks every second.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  /// Unmounts the screen so the lobby's one-second ticker is cancelled
  /// before the binding checks for pending timers.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('a live room: «بدأت 1 سبتمبر»', (tester) async {
    await pump(tester, room(startDate: DateTime(2026, 9, 1)));
    expect(find.text('بدأت 1 سبتمبر'), findsOneWidget,
        reason: 'drew «بدأت ١ سبتمبر»');
    await unmount(tester);
  });

  testWidgets('a scheduled lobby: its start caption and the header',
      (tester) async {
    final now = DateTime.now();
    // Five days out, so the caption dates the day instead of saying
    // «اليوم» or «غدًا».
    final day = DateTime(now.year, now.month, now.day + 5);
    final at = day.add(const Duration(hours: 20));
    await pump(
      tester,
      room(startDate: day, status: 'lobby', scheduledStartAt: at),
    );

    final weekday = DateFormat('EEEE', 'ar').format(day);
    final month = DateFormat('MMMM', 'ar').format(day);
    expect(
      find.text('يبدأ $weekday، ${day.day} $month · 8:00 م'),
      findsOneWidget,
    );
    expect(find.text('تبدأ ${day.day} $month'), findsOneWidget);
    expect(
      find.byWidgetPredicate((w) =>
          w is RichText && arabicIndic.hasMatch(w.text.toPlainText())),
      findsNothing,
    );
    await unmount(tester);
  });
}
