// The time wheel that replaced the Material dial in pickReminderMoment
// (reminder_picker.dart). The dial let a person pick a time that had
// already passed and only refused it afterwards; the wheel carries a floor
// so the past cannot be landed on. These tests pin the floor arithmetic and
// the sheet's contract: what the wheel is told, and what Done hands back.

import 'package:flutter/cupertino.dart'
    show CupertinoDatePicker, CupertinoPicker;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/matrix/widgets/reminder_picker.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('ar');
  });

  group('reminderTimeFloor', () {
    test('is the next whole minute, seconds dropped', () {
      expect(
        reminderTimeFloor(DateTime(2026, 9, 7, 15, 4, 30)),
        DateTime(2026, 9, 7, 15, 5),
      );
    });

    test('a clock exactly on the minute still moves to the next one', () {
      expect(
        reminderTimeFloor(DateTime(2026, 9, 7, 15, 4)),
        DateTime(2026, 9, 7, 15, 5),
      );
    });

    test('rolls across the hour and the day', () {
      expect(
        reminderTimeFloor(DateTime(2026, 9, 7, 15, 59, 10)),
        DateTime(2026, 9, 7, 16),
      );
      expect(
        reminderTimeFloor(DateTime(2026, 9, 7, 23, 59, 10)),
        DateTime(2026, 9, 8),
      );
    });
  });

  group('reminderWheelFloor', () {
    final now = DateTime(2026, 9, 7, 15, 4, 30);

    test('today is floored at the next whole minute', () {
      expect(
        reminderWheelFloor(day: DateTime(2026, 9, 7), now: now),
        DateTime(2026, 9, 7, 15, 5),
      );
    });

    test('any later day has no floor', () {
      expect(reminderWheelFloor(day: DateTime(2026, 9, 8), now: now), isNull);
      expect(reminderWheelFloor(day: DateTime(2026, 12), now: now), isNull);
    });

    test('the last minute of today has no floor rather than one on tomorrow',
        () {
      expect(
        reminderWheelFloor(
          day: DateTime(2026, 9, 7),
          now: DateTime(2026, 9, 7, 23, 59, 20),
        ),
        isNull,
      );
    });
  });

  group('reminderWheelInitial', () {
    test('places the suggested clock time on the picked day', () {
      expect(
        reminderWheelInitial(
          day: DateTime(2026, 9, 9),
          suggested: DateTime(2026, 9, 7, 16, 4),
          floor: null,
        ),
        DateTime(2026, 9, 9, 16, 4),
      );
    });

    test('a start below the floor is lifted to it', () {
      expect(
        reminderWheelInitial(
          day: DateTime(2026, 9, 7),
          suggested: DateTime(2026, 9, 7, 9),
          floor: DateTime(2026, 9, 7, 15, 5),
        ),
        DateTime(2026, 9, 7, 15, 5),
      );
    });

    test('a start at or above the floor is kept', () {
      expect(
        reminderWheelInitial(
          day: DateTime(2026, 9, 7),
          suggested: DateTime(2026, 9, 7, 16, 4),
          floor: DateTime(2026, 9, 7, 15, 5),
        ),
        DateTime(2026, 9, 7, 16, 4),
      );
    });
  });

  group('formatReminderDay', () {
    final now = DateTime(2026, 9, 7, 15, 4);

    test('names today and tomorrow', () {
      expect(formatReminderDay(DateTime(2026, 9, 7), false, now: now), 'Today');
      expect(formatReminderDay(DateTime(2026, 9, 7), true, now: now), 'اليوم');
      expect(
        formatReminderDay(DateTime(2026, 9, 8), false, now: now),
        'Tomorrow',
      );
      expect(formatReminderDay(DateTime(2026, 9, 8), true, now: now), 'غدًا');
    });

    test('spells out any other day', () {
      expect(
        formatReminderDay(DateTime(2026, 9, 12), false, now: now),
        'Saturday، 12 September',
      );
    });
  });

  group('showReminderTimeSheet', () {
    // The sheet's own future completes only when it closes, so it is kept
    // aside rather than awaited by the opener: awaiting it there would wait
    // on a Done tap that the test has not made yet.
    late Future<TimeOfDay?> result;

    Future<void> open(
      WidgetTester tester, {
      required DateTime day,
      required DateTime initial,
      required DateTime? floor,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () {
                  result = showReminderTimeSheet(
                    context,
                    day: day,
                    initial: initial,
                    floor: floor,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('the wheel is told the floor and starts on the initial time',
        (tester) async {
      // The real calendar day, because the sheet names the day off the real
      // clock: a fixed date read "today" only until midnight, and the full
      // suite crossed one.
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      await open(
        tester,
        day: today,
        initial: today.add(const Duration(hours: 16, minutes: 4)),
        floor: today.add(const Duration(hours: 15, minutes: 5)),
      );

      final wheel =
          tester.widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker));
      expect(wheel.minimumDate,
          today.add(const Duration(hours: 15, minutes: 5)));
      expect(wheel.initialDateTime,
          today.add(const Duration(hours: 16, minutes: 4)));
      expect(wheel.use24hFormat, isFalse);
      // The floor line names the earliest time, and the day is named.
      expect(find.textContaining('أقرب وقت'), findsOneWidget);
      expect(find.text('اليوم'), findsOneWidget);
    });

    testWidgets('another day has no floor and no floor line', (tester) async {
      await open(
        tester,
        day: DateTime(2026, 9, 9),
        initial: DateTime(2026, 9, 9, 16, 4),
        floor: null,
      );

      final wheel =
          tester.widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker));
      expect(wheel.minimumDate, isNull);
      expect(find.textContaining('أقرب وقت'), findsNothing);
    });

    testWidgets('Done hands back the untouched initial time', (tester) async {
      await open(
        tester,
        day: DateTime(2026, 9, 7),
        initial: DateTime(2026, 9, 7, 16, 4),
        floor: DateTime(2026, 9, 7, 15, 5),
      );
      await tester.tap(find.text('تم'));
      await tester.pumpAndSettle();
      expect(await result, const TimeOfDay(hour: 16, minute: 4));
    });

    testWidgets('a spin into the past settles back on the floor',
        (tester) async {
      await open(
        tester,
        day: DateTime(2026, 9, 7),
        initial: DateTime(2026, 9, 7, 15, 30),
        floor: DateTime(2026, 9, 7, 15, 5),
      );

      // Drag the wheel's hour column a long way towards earlier hours. The
      // picker greys those hours out and, once the spin stops, scrolls
      // itself back to the floor; Done must then report the floor, not the
      // hour the finger left it on.
      //
      // The three columns (hour, minute, AM/PM) are packed into the middle
      // of the sheet, not spread across it, and a drag that misses them
      // lands on the sheet itself and swipes it away. In RTL the hour
      // column is the right-most of the three.
      final columns = find.byType(CupertinoPicker);
      expect(columns, findsNWidgets(3));
      final hourColumn = List.generate(3, (i) => tester.getCenter(columns.at(i)))
          .reduce((a, b) => a.dx > b.dx ? a : b);
      await tester.dragFrom(hourColumn, const Offset(0, 260));
      await tester.pumpAndSettle();
      expect(find.text('تم'), findsOneWidget, reason: 'the sheet must survive the spin');

      await tester.tap(find.text('تم'));
      await tester.pumpAndSettle();
      final picked = await result;
      expect(picked, isNotNull);
      final asMinutes = picked!.hour * 60 + picked.minute;
      expect(asMinutes, greaterThanOrEqualTo(15 * 60 + 5));
    });

    testWidgets('tapping outside the sheet returns null', (tester) async {
      await open(
        tester,
        day: DateTime(2026, 9, 7),
        initial: DateTime(2026, 9, 7, 16, 4),
        floor: DateTime(2026, 9, 7, 15, 5),
      );
      // The dimmed page above the sheet.
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(await result, isNull);
    });
  });
}
