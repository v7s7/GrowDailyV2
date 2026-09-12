// A member's sheet in a room has to be easy to close.
//
// It could only be closed by tapping the backdrop above it, a band about
// 14pt tall under the status bar. The card's own bottom padding reached the
// edge of the screen, so the dimmed rows under it ignored taps, and the grab
// handle sat inside the scroll view, so dragging it scrolled. Aziz,
// 2026-09-11: "its stuck some times... its nice if there is a slide smoother
// to close the pop up or a nice designed x mark".
//
// Pumped alone in Arabic at phone size, opened through the same
// showParticipantSheet the leaderboard calls.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/rooms/models/room_model.dart';
import 'package:grow_daily_v2/features/rooms/screens/room_detail_screen.dart'
    show showParticipantSheet;
import 'package:hive/hive.dart';

final _closeButton = find.byIcon(Icons.close_rounded);

/// Bounded pumps rather than pumpAndSettle: the route and the header's
/// entrance animations all finish well inside this, and a stated budget
/// fails loudly instead of hanging on anything that repeats.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late Directory tmp;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('participant_sheet_close');
    Hive.init(tmp.path);
    await Hive.openBox<dynamic>('box_settings');
  });

  tearDownAll(() async {
    await Hive.deleteFromDisk();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  // An ended room, so the calendar opens on a fixed month whatever day the
  // suite happens to run.
  final room = RoomModel(
    code: 'ELQVF8',
    name: 'Being Better',
    createdBy: 'aziz',
    createdByName: 'Aziz',
    createdAt: DateTime(2026, 8),
    habitMode: RoomHabitMode.shared,
    sharedHabits: const [
      RoomHabitTemplate(
        name: 'صلاة الوتر',
        category: HabitCategory.faith,
        frequencyType: HabitFrequencyType.daily,
        frequencyTarget: 1,
      ),
    ],
    duration: RoomDuration.fixed,
    startDate: DateTime(2026, 8),
    endDate: DateTime(2026, 8, 30),
  );
  final hoor = RoomParticipant(
    uid: 'hoor',
    displayName: 'Hoor',
    characterId: 'none',
    joinedAt: DateTime(2026, 8),
    linkedHabitIds: const ['w'],
    linkedHabitNames: const ['صلاة الوتر'],
    dailyDoneCount: const {'2026-08-05': 1},
    lastUpdated: DateTime(2026, 8, 30),
  );

  Future<void> openSheet(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(402, 874));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: GameTheme.light,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => showParticipantSheet(
                    context,
                    room: room,
                    participant: hoor,
                    isYou: false,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await _settle(tester);
    expect(_closeButton, findsOneWidget, reason: 'the sheet opened');
  }

  testWidgets('the X closes it', (tester) async {
    await openSheet(tester);
    await tester.tap(_closeButton);
    await _settle(tester);
    expect(_closeButton, findsNothing);
  });

  testWidgets('the X is a named button with a thumb-sized target',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await openSheet(tester);
    expect(find.bySemanticsLabel('إغلاق'), findsOneWidget);
    final target = tester.getSize(
      find.ancestor(of: _closeButton, matching: find.byType(InkResponse)),
    );
    expect(target.width, greaterThanOrEqualTo(44));
    expect(target.height, greaterThanOrEqualTo(44));
    semantics.dispose();
  });

  testWidgets('dragging the handle bar down closes it', (tester) async {
    await openSheet(tester);
    // Level with the X, in the middle of the bar: the handle's own row,
    // which is outside the scroll view.
    final bar = tester.getCenter(_closeButton);
    await tester.dragFrom(Offset(201, bar.dy), const Offset(0, 600));
    await _settle(tester);
    expect(_closeButton, findsNothing);
  });

  testWidgets('pulling the content down past its top closes it',
      (tester) async {
    await openSheet(tester);
    await tester.dragFrom(
      tester.getCenter(find.text('Hoor')),
      const Offset(0, 500),
    );
    await _settle(tester);
    expect(_closeButton, findsNothing);
  });

  testWidgets('a short pull springs back and stays open', (tester) async {
    await openSheet(tester);
    await tester.dragFrom(
      tester.getCenter(find.text('Hoor')),
      const Offset(0, 40),
    );
    await _settle(tester);
    expect(_closeButton, findsOneWidget);
  });

  testWidgets('the margin beside the card closes it', (tester) async {
    await openSheet(tester);
    final name = tester.getCenter(find.text('Hoor'));
    // Six points in from the screen edge: inside the sheet's 16pt margin,
    // outside the card.
    await tester.tapAt(Offset(6, name.dy));
    await _settle(tester);
    expect(_closeButton, findsNothing);
  });

  testWidgets('taps inside the card do not close it', (tester) async {
    await openSheet(tester);
    await tester.tap(find.text('Hoor'));
    await _settle(tester);
    expect(_closeButton, findsOneWidget);
    // Picking a day is the reason the sheet exists. The 5th was done, so its
    // card draws a tick, not a second close_rounded glyph.
    await tester.tap(find.text('5').first);
    await _settle(tester);
    expect(_closeButton, findsOneWidget);
  });
}
