// The day's two big moments (Aziz, 2026-09-28): the streak point, then every
// habit done, each bigger than the one before, and a tap that is both plays
// once, as the perfect day. See reaction_overlays.dart.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/l10n/wording_edits.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/dashboard/widgets/reaction_overlays.dart';

void main() {
  const ar = S(Locale('ar'));
  late List<String> buzzes;

  setUp(() {
    resetDayMoments();
    buzzes = [];
  });

  void listen(WidgetTester tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          buzzes.add((call.arguments as String).split('.').last);
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
  }

  final bursts = find.byWidgetPredicate(
    (w) => w.runtimeType.toString() == '_VictoryBurst',
  );

  /// Each burst on screen, by its number of pieces.
  List<int> burstSizes(WidgetTester tester) => [
        for (final w in tester.widgetList(bursts))
          (w as dynamic).particleCount as int,
      ];

  Widget app({required bool perfectDay, bool live = true}) => MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: GameTheme.dark,
        home: Scaffold(
          body: PerfectDayMoment(
            perfectDay: perfectDay,
            live: live,
            child: const SizedBox.expand(key: Key('card')),
          ),
        ),
      );

  BuildContext card(WidgetTester tester) =>
      tester.element(find.byKey(const Key('card')));

  /// Past every burst and the pop-up, so no timer outlives the test.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  }

  testWidgets('the streak point alone: a heavy buzz, one burst, the pop-up',
      (tester) async {
    listen(tester);
    await tester.pumpWidget(app(perfectDay: false));
    celebrateStreakPoint(card(tester));
    await tester.pump(const Duration(milliseconds: 300));
    expect(buzzes, ['heavyImpact']);
    expect(burstSizes(tester), [16]);
    expect(find.text(ar.perfectDayMsg), findsOneWidget);
    await settle(tester);
  });

  testWidgets('every habit done between two live readings: two bursts, each '
      'bigger than the streak point\'s, and a double buzz', (tester) async {
    listen(tester);
    await tester.pumpWidget(app(perfectDay: false));
    await tester.pumpWidget(app(perfectDay: true));
    await tester.pump();
    expect(buzzes, ['heavyImpact']);
    expect(burstSizes(tester), [30]);

    await tester.pump(const Duration(milliseconds: 300));
    expect(buzzes, ['heavyImpact', 'mediumImpact']);
    expect(burstSizes(tester), [30, 22]);
    expect(burstSizes(tester).every((n) => n > 16), isTrue);
    await settle(tester);
    expect(bursts, findsNothing);
  });

  testWidgets('never for numbers that are not live: the week landing at '
      'launch, or another week on screen', (tester) async {
    listen(tester);
    await tester.pumpWidget(app(perfectDay: false, live: false));
    await tester.pumpWidget(app(perfectDay: true));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpWidget(app(perfectDay: false, live: false));
    await tester.pumpWidget(app(perfectDay: true, live: false));
    await tester.pump(const Duration(milliseconds: 400));
    expect(bursts, findsNothing);
    expect(buzzes, isEmpty);
  });

  testWidgets('one tap that is both, the streak counted first: one moment, '
      'the perfect day\'s, and the streak\'s pop-up still says it counted',
      (tester) async {
    listen(tester);
    await tester.pumpWidget(app(perfectDay: false));
    celebrateStreakPoint(card(tester));
    await tester.pumpWidget(app(perfectDay: true));
    await tester.pump(const Duration(milliseconds: 300));
    expect(buzzes, ['heavyImpact', 'mediumImpact'],
        reason: 'one heavy buzz for the one moment');
    expect(burstSizes(tester), [30, 22],
        reason: 'the streak point\'s own burst gives way');
    expect(find.text(ar.perfectDayMsg), findsOneWidget);
    await settle(tester);
  });

  testWidgets('the admin\'s «دوم» page sets every burst\'s size, and 0 '
      'pieces fires none', (tester) async {
    addTearDown(() => WordingEditsStore.debugPublish(WordingEdits.empty));
    WordingEditsStore.debugPublish(const WordingEdits(
      pet: PetEdits(numbers: {
        'streakConfettiPieces': 9,
        'fullDayConfettiPieces': 44,
        'fullDaySecondConfettiPieces': 0,
      }),
    ));
    listen(tester);
    await tester.pumpWidget(app(perfectDay: false));
    celebrateStreakPoint(card(tester));
    await tester.pump(const Duration(milliseconds: 300));
    expect(burstSizes(tester), [9]);
    await settle(tester);

    resetDayMoments();
    await tester.pumpWidget(app(perfectDay: true));
    await tester.pump(const Duration(milliseconds: 300));
    expect(burstSizes(tester), [44],
        reason: 'the second burst was set to 0 pieces');
    await settle(tester);
  });

  testWidgets('one tap that is both, the board first: the streak point adds '
      'only its pop-up', (tester) async {
    listen(tester);
    await tester.pumpWidget(app(perfectDay: false));
    await tester.pumpWidget(app(perfectDay: true));
    await tester.pump();
    celebrateStreakPoint(card(tester));
    await tester.pump(const Duration(milliseconds: 300));
    expect(buzzes, ['heavyImpact', 'mediumImpact']);
    expect(burstSizes(tester), [30, 22]);
    expect(find.text(ar.perfectDayMsg), findsOneWidget);
    await settle(tester);
  });
}
