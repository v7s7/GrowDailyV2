// The right Doum for the moment (Aziz, 2026-10-03, the canvas "Doum
// review"): the streak milestone, a finished room and Premium all drew him
// hugging the same heart. The heart is Premium's thanks; a streak step
// cheers, and a finished room plants its flag on a hill.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/dashboard/widgets/reaction_overlays.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/mascot/sprout.dart';
import 'package:grow_daily_v2/features/rooms/models/room_model.dart';
import 'package:grow_daily_v2/features/rooms/notifiers/room_plan_notices.dart';
import 'package:grow_daily_v2/features/rooms/notifiers/rooms_notifier.dart';
import 'package:grow_daily_v2/features/rooms/widgets/room_finale_announcer.dart';

Widget _app(Widget home, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: GameTheme.dark,
        home: home,
      ),
    );

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

RoomModel _finishedRoom() {
  final today = DateTime.now();
  final start = DateTime(today.year, today.month, today.day - 30);
  return RoomModel(
    code: 'FINALE',
    name: 'غرفة الختام',
    createdBy: 'leader-uid',
    createdByName: 'Leader',
    createdAt: start,
    habitMode: RoomHabitMode.shared,
    duration: RoomDuration.fixed,
    startDate: start,
    endDate: DateTime(today.year, today.month, today.day - 2),
    sharedHabits: [
      RoomHabitTemplate(
        name: 'قراءة',
        category: HabitCategory.faith,
        frequencyType: HabitFrequencyType.daily,
        frequencyTarget: 1,
      ),
    ],
  );
}

void main() {
  testWidgets('a streak milestone: Doum cheers, full size', (tester) async {
    await tester.pumpWidget(_app(Consumer(
      builder: (_, ref, __) => MilestoneCelebration(milestone: 7, ref: ref),
    )));
    await _settle(tester);

    final sprout = tester.widget<Sprout>(find.byType(Sprout));
    expect(sprout.pose, SproutPose.cheer);
    expect(sprout.height, 190);
    expect(sprout.entrance, SproutEntrance.popAndCelebrate);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a finished room: Doum plants his flag, and the dialog fits '
      'a small phone', (tester) async {
    // An iPhone SE: the flag's hill makes his box bigger than the heart's
    // was (147x141 at 120, against 102x123), so the dialog grows.
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(
      const RoomFinaleAnnouncer(child: Scaffold()),
      overrides: [
        unseenFinishedRoomsProvider.overrideWithValue([_finishedRoom()]),
        roomPlanNoticesProvider.overrideWithValue(const []),
      ],
    ));
    await _settle(tester);

    expect(find.text('انتهى التحدي'), findsOneWidget);
    final sprout = tester.widget<Sprout>(find.byType(Sprout));
    expect(sprout.pose, SproutPose.flagHill);
    // The same scale as every pose: the character is the heart's size, the
    // hill is extra.
    expect(sprout.height, 120);
    // The picture, not Sprout's box: the dialog's icon slot stretches the
    // box across the dialog and the picture sits in its middle.
    final box = tester.getSize(find.descendant(
        of: find.byType(Sprout), matching: find.byType(Image)));
    final want = Sprout.sizeOf(SproutPose.flagHill, 120);
    expect(box.width, closeTo(want.width, 0.5));
    expect(box.height, closeTo(want.height, 0.5));
    // Both buttons on screen, nothing overflowing.
    expect(find.byType(FilledButton), findsOneWidget);
    expect(tester.getRect(find.byType(FilledButton)).bottom,
        lessThanOrEqualTo(667));
    expect(tester.takeException(), isNull);
  });
}
