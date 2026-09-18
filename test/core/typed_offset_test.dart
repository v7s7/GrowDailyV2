// A reminder shift typed by hand (typedOffsetMinutes), which Add Habit's
// offset sheet and a task's custom reminder sheet both read.
//
// Both fields took whole numbers only, on a keypad with no point, so a
// 4.5-hour reminder had to be worked out in minutes, and Aziz's came out as
// 260, ten short (2026-09-18). Hours and days now take a fraction.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/l10n/reminder_copy.dart' show ReminderUnit;
import 'package:grow_daily_v2/core/utils/typed_offset.dart';

void main() {
  test('4.5 hours is 270 minutes', () {
    expect(typedOffsetMinutes('4.5', ReminderUnit.hours), 270);
  });

  test('whole numbers read as they always did', () {
    expect(typedOffsetMinutes('45', ReminderUnit.minutes), 45);
    expect(typedOffsetMinutes('2', ReminderUnit.hours), 120);
    expect(typedOffsetMinutes('1', ReminderUnit.days), 1440);
  });

  test('fractions of hours and days', () {
    expect(typedOffsetMinutes('0.5', ReminderUnit.hours), 30);
    expect(typedOffsetMinutes('.5', ReminderUnit.hours), 30);
    expect(typedOffsetMinutes('1.25', ReminderUnit.hours), 75);
    expect(typedOffsetMinutes('1.5', ReminderUnit.days), 2160);
    expect(typedOffsetMinutes('4.', ReminderUnit.hours), 240,
        reason: 'a point typed with nothing after it yet');
  });

  test('whatever point the keypad gives', () {
    final arabicPoint = String.fromCharCode(0x066B);
    expect(typedOffsetMinutes('4,5', ReminderUnit.hours), 270);
    expect(typedOffsetMinutes('4${arabicPoint}5', ReminderUnit.hours), 270);
  });

  test('Arabic-Indic digits count the same as Latin ones', () {
    final arabicPoint = String.fromCharCode(0x066B);
    expect(typedOffsetMinutes('٤٥', ReminderUnit.minutes), 45);
    expect(typedOffsetMinutes('٤$arabicPoint٥', ReminderUnit.hours), 270);
  });

  test('rounded to the whole minute a reminder is kept in', () {
    expect(typedOffsetMinutes('2.5', ReminderUnit.minutes), 3);
    expect(typedOffsetMinutes('1.01', ReminderUnit.hours), 61);
  });

  test('null for anything that is not one positive amount', () {
    for (final text in ['', ' ', '.', '0', '0.0', '4.5.1', '4..5', 'abc',
        '1e2', 'Infinity', '-3', '0.004']) {
      expect(typedOffsetMinutes(text, ReminderUnit.hours), isNull,
          reason: '"$text"');
    }
    expect(typedOffsetMinutes('0.2', ReminderUnit.minutes), isNull,
        reason: 'under half a minute rounds to nothing');
  });

  test('a number too long to be finite is nothing, not a crash', () {
    expect(typedOffsetMinutes('1${'0' * 400}', ReminderUnit.hours), isNull);
  });

  test('spaces around the number are ignored', () {
    expect(typedOffsetMinutes(' 4.5 ', ReminderUnit.hours), 270);
  });
}
