import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/services/health_steps_service.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/habits/step_auto_complete.dart';
import 'package:grow_daily_v2/features/habits/widgets/steps_day_card.dart';

/// flutter_test runs as Android unless told otherwise, and the card names
/// the store it read from.
final _iOS = TargetPlatformVariant.only(TargetPlatform.iOS);

/// Checking an earlier day's steps, asked for by Aziz on 2026-09-16: "a way
/// that the user can easily check his steps the pre days, maybe if he hold
/// it, or ... appear like 0.1k", and "it should match the health app 100%".
///
/// The board draws the short count inside each linked square (design option
/// A), and a held square's sheet shows the exact count read fresh from
/// Health (StepsDayCard).
void main() {
  group('compactStepCount', () {
    test('nothing to draw for zero', () {
      expect(compactStepCount(0), isNull);
      expect(compactStepCount(-5), isNull);
    });

    test('under a thousand is the plain number', () {
      expect(compactStepCount(1), '1');
      expect(compactStepCount(950), '950');
      expect(compactStepCount(999), '999');
    });

    test('one decimal below ten thousand, and a trailing .0 dropped', () {
      expect(compactStepCount(1000), '1k');
      expect(compactStepCount(1099), '1k');
      expect(compactStepCount(3210), '3.2k');
      expect(compactStepCount(8420), '8.4k');
      expect(compactStepCount(5000), '5k');
    });

    test('always rounds DOWN, so a square never claims the goal early', () {
      // 9,960 on a 10,000 goal is short of it. Rounded to nearest it would
      // read "10.0k", a finished day that was not.
      expect(compactStepCount(9960), '9.9k');
      expect(compactStepCount(9999), '9.9k');
      expect(compactStepCount(8499), '8.4k');
    });

    test('whole thousands from ten thousand up, still rounded down', () {
      expect(compactStepCount(10000), '10k');
      expect(compactStepCount(12640), '12k');
      expect(compactStepCount(99999), '99k');
      expect(compactStepCount(123456), '123k');
    });

    test('never longer than four characters below a million steps', () {
      // What keeps it inside a 30pt square without shrinking to nothing.
      for (final n in [1, 999, 1000, 9999, 10000, 99999, 100000, 999999]) {
        expect(compactStepCount(n)!.length, lessThanOrEqualTo(4),
            reason: '$n drew as "${compactStepCount(n)}"');
      }
    });
  });

  group('stepSquareCount', () {
    String? count({
      int? steps = 8420,
      int? goal = 8000,
      bool scheduled = true,
      SquareState square = SquareState.complete,
    }) =>
        stepSquareCount(
          steps: steps,
          goal: goal,
          scheduled: scheduled,
          square: square,
        );

    test('drawn on the four rungs the count itself can reach', () {
      for (final square in [
        SquareState.none,
        SquareState.partial,
        SquareState.complete,
        SquareState.bonus,
      ]) {
        expect(count(square: square), '8.4k', reason: '$square');
      }
    });

    test('فشل and تخطّي keep their glyph', () {
      expect(count(square: SquareState.failed), isNull);
      expect(count(square: SquareState.skipped), isNull);
    });

    test('nothing for an unlinked habit, an off day, or no count', () {
      expect(count(goal: null), isNull);
      expect(count(scheduled: false), isNull);
      expect(count(steps: null), isNull);
      expect(count(steps: 0, square: SquareState.none), isNull);
    });
  });

  group('StepsDayCard', () {
    final day = DateTime(2026, 9, 15);
    const key = '2026-09-15';

    Widget app({
      required Map<String, int> stored,
      required StepsDayReader read,
      Locale locale = const Locale('ar'),
    }) =>
        ProviderScope(
          overrides: [
            stepsByDayProvider.overrideWith((ref) => stored),
          ],
          child: MaterialApp(
            locale: locale,
            supportedLocales: const [Locale('en'), Locale('ar')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: GameTheme.dark,
            home: Scaffold(
              body: StepsDayCard(day: day, goal: 8000, read: read),
            ),
          ),
        );

    testWidgets('shows the exact count, grouped, with the goal and source',
        (tester) async {
      await tester.pumpWidget(app(
        stored: const {key: 5480},
        read: (ref, day) async =>
            HealthStepsRangeOutcome.success(const {key: 5480}),
      ));
      await tester.pumpAndSettle();
      expect(find.text('5,480'), findsOneWidget);
      expect(find.text('خطوة'), findsOneWidget);
      expect(find.text('الهدف 8,000'), findsOneWidget);
      expect(find.text('من Apple Health'), findsOneWidget);
    }, variant: _iOS);

    testWidgets('follows a fresh read that lands while it is open',
        (tester) async {
      // The card asks Health again when it opens; whatever that read records
      // is what it shows, so a count the log had wrong corrects itself on
      // screen rather than only on the next launch.
      await tester.pumpWidget(app(
        stored: const {key: 4000},
        read: (ref, day) async {
          ref.read(stepsByDayProvider.notifier).state = const {key: 11250};
          return HealthStepsRangeOutcome.success(const {key: 11250});
        },
      ));
      expect(find.text('4,000'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('11,250'), findsOneWidget);
      expect(find.text('4,000'), findsNothing);
    }, variant: _iOS);

    testWidgets('a day with no steps reads 0 once Health has answered',
        (tester) async {
      await tester.pumpWidget(app(
        stored: const {},
        read: (ref, day) async =>
            HealthStepsRangeOutcome.success(const {key: 0}),
      ));
      await tester.pumpAndSettle();
      expect(find.text('0'), findsOneWidget);
    }, variant: _iOS);

    testWidgets('a passing failure with nothing stored shows no card',
        (tester) async {
      // No number is better than an invented one.
      await tester.pumpWidget(app(
        stored: const {},
        read: (ref, day) async =>
            HealthStepsRangeOutcome.failed(HealthStepsFailure.unavailable),
      ));
      await tester.pumpAndSettle();
      expect(find.text('0'), findsNothing);
      expect(find.text('من Apple Health'), findsNothing);
    }, variant: _iOS);

    testWidgets('a failed read keeps the stored count', (tester) async {
      await tester.pumpWidget(app(
        stored: const {key: 7310},
        read: (ref, day) async =>
            HealthStepsRangeOutcome.failed(HealthStepsFailure.unavailable),
      ));
      await tester.pumpAndSettle();
      expect(find.text('7,310'), findsOneWidget);
    }, variant: _iOS);

    testWidgets('English reads the same way', (tester) async {
      await tester.pumpWidget(app(
        locale: const Locale('en'),
        stored: const {key: 10240},
        read: (ref, day) async =>
            HealthStepsRangeOutcome.success(const {key: 10240}),
      ));
      await tester.pumpAndSettle();
      expect(find.text('10,240'), findsOneWidget);
      expect(find.text('steps'), findsOneWidget);
      expect(find.text('Goal 8,000'), findsOneWidget);
      expect(find.text('From Apple Health'), findsOneWidget);
    }, variant: _iOS);
  });
}
