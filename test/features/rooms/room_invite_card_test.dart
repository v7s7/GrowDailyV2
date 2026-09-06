// The card a competitive room shows while its creator is the only member
// (RoomInviteCard, in room_detail_screen_header_progress.dart). The room
// screen itself needs a live Firestore stream, so the card is pumped alone
// here, in Arabic at phone width, the way the simulator trace would see it.
//
// What matters: nothing overflows (the framework reports overflow as a test
// error), the code is shown as typed and never reshaped by RTL, and Copy
// really copies before it says it did.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/rooms/models/room_model.dart';
import 'package:grow_daily_v2/features/rooms/screens/room_detail_screen.dart'
    show RoomInviteCard;

void main() {
  final start = DateTime(2026, 9, 6);
  final room = RoomModel(
    code: 'BWAHKG',
    name: 'تحدي الفجر',
    createdBy: 'a',
    createdByName: 'A',
    createdAt: start,
    habitMode: RoomHabitMode.own,
    duration: RoomDuration.open,
    startDate: start,
    competeMode: RoomCompeteMode.competitive,
  );

  Widget app({double textScale = 1.0}) => MaterialApp(
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
        home: Scaffold(
          body: ListView(
            // The lobby's own horizontal padding.
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [RoomInviteCard(room: room)],
          ),
        ),
      );

  // iPhone 17 Pro points, the device the live trace uses.
  Future<void> pumpCard(WidgetTester tester, {double textScale = 1.0}) async {
    await tester.binding.setSurfaceSize(const Size(402, 874));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app(textScale: textScale));
    await tester.pump();
  }

  testWidgets('lays out at phone width with the code shown LTR',
      (tester) async {
    await pumpCard(tester);

    expect(find.text('ما في أحد غيرك بعد'), findsOneWidget);
    expect(find.text('شارك هذا الرمز مع أصدقائك لينضموا'), findsOneWidget);
    expect(find.text('نسخ الرمز'), findsOneWidget);
    expect(find.text('مشاركة'), findsOneWidget);

    final code = tester.widget<Text>(find.text('BWAHKG'));
    expect(code.textDirection, TextDirection.ltr,
        reason: 'a Latin code inside an RTL page must be pinned LTR');
    // The framework turns a RenderFlex overflow into a test failure; an
    // explicit check makes the reason readable if it ever happens.
    expect(tester.takeException(), isNull);
  });

  testWidgets('still fits with large text', (tester) async {
    await pumpCard(tester, textScale: 1.3);
    expect(find.text('BWAHKG'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('copy writes the code to the clipboard, then confirms',
      (tester) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await pumpCard(tester);
    await tester.tap(find.text('نسخ الرمز'));
    await tester.pump();

    final setData =
        calls.where((c) => c.method == 'Clipboard.setData').toList();
    expect(setData, hasLength(1));
    expect((setData.single.arguments as Map)['text'], 'BWAHKG');
    expect(find.text('تم نسخ الرمز'), findsOneWidget);
  });
}
