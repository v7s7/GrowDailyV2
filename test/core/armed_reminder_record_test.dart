// The record a reminder pass leaves in the App Group, and the rule the two
// Done paths outside the app read it by (lib/core/services/
// armed_reminder_record.dart). The widget reads the same JSON in Swift
// (ios/GrowDailyWidget/HabitReminderStandDown.swift), so the shape pinned
// here is the contract between the two languages.
//
// The case the record exists for: the headless engine and the widget cannot
// tell which of a slot's armed copies is today's, because that depends on
// when the last pass ran. It used to be guessed as depth 0, the next
// occurrence at pass time, which is today's only while the pass ran before
// today's reminder.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/services/armed_reminder_record.dart';
import 'package:grow_daily_v2/core/services/notification_action_queue.dart';

void main() {
  const day1 = '2026-09-21';
  const day2 = '2026-09-22';
  const day3 = '2026-09-23';

  ArmedHabitCopy note(String habit, int id, DateTime at) => (
        habitId: habit,
        id: id,
        fireTime: at,
        kind: ArmedReminderKind.notification,
      );

  ArmedHabitCopy alarm(String habit, int id, DateTime at) =>
      (habitId: habit, id: id, fireTime: at, kind: ArmedReminderKind.alarm);

  ReminderStandDown? plan(
    String json,
    String habitId,
    String day, {
    Set<String> done = const {},
  }) =>
      ArmedReminderRecord.standDownFor(
        json,
        habitId: habitId,
        day: day,
        doneOnDay: done,
      );

  group('standDownFor', () {
    test("takes the day's copy wherever the pass put it, and no other day's",
        () {
      // The pass ran on the 21st at 08:00, before that day's 09:00: depth 0
      // is the 21st, depth 1 the 22nd. A tap on the 22nd has to find its
      // copy at depth 1 (400123), and must leave the 23rd's alone.
      final json = ArmedReminderRecord.encode(
        copies: [
          note('fajr', 5123, DateTime(2026, 9, 21, 9)),
          note('fajr', 400123, DateTime(2026, 9, 22, 9)),
          note('fajr', 401123, DateTime(2026, 9, 23, 9)),
        ],
        bundles: const [],
        snoozeIds: const {'fajr': 6123},
      );
      final onDay2 = plan(json, 'fajr', day2)!;
      expect(onDay2.notifications, {400123, 6123});
      expect(onDay2.alarms, isEmpty);
      expect(plan(json, 'fajr', day3)!.notifications, {401123, 6123});
    });

    test("a day whose reminder the pass already let go of has nothing to "
        "take, so tomorrow's copy is not taken instead", () {
      // The pass ran at 10:00, after the day's 09:00 had gone: its next
      // occurrence (depth 0, 5123) is TOMORROW's. The old rule cancelled
      // depth 0 and so silenced tomorrow.
      final json = ArmedReminderRecord.encode(
        copies: [
          note('fajr', 5123, DateTime(2026, 9, 23, 9)),
          note('fajr', 400123, DateTime(2026, 9, 24, 9)),
        ],
        bundles: const [],
        snoozeIds: const {'fajr': 6123},
      );
      expect(plan(json, 'fajr', day2)!.notifications, {6123},
          reason: 'only a snooze, which is not about any one day');
    });

    test('every slot of a stacked habit, even when they sit at different '
        'depths', () {
      // An hour before Maghrib and on the dot, armed yesterday between the
      // two: yesterday's early one had gone, its on-time one had not, so
      // today's early copy is depth 0 and today's on-time copy depth 1.
      final json = ArmedReminderRecord.encode(
        copies: [
          note('maghrib', 5001, DateTime(2026, 9, 22, 16, 45)),
          note('maghrib', 5002, DateTime(2026, 9, 21, 17, 45)),
          note('maghrib', 400002, DateTime(2026, 9, 22, 17, 45)),
          note('maghrib', 400001, DateTime(2026, 9, 23, 16, 45)),
        ],
        bundles: const [],
        snoozeIds: const {},
      );
      expect(plan(json, 'maghrib', day2)!.notifications, {5001, 400002});
    });

    test('alarms come back apart from notifications', () {
      final json = ArmedReminderRecord.encode(
        copies: [
          alarm('fajr', 5123, DateTime(2026, 9, 22, 3, 30)),
          alarm('fajr', 400123, DateTime(2026, 9, 23, 3, 30)),
          // The far, day-keyed window of a month-long alarm.
          alarm('fajr', 523123, DateTime(2026, 9, 26, 3, 31)),
          note('fajr', 401123, DateTime(2026, 9, 22, 4, 30)),
        ],
        bundles: const [],
        snoozeIds: const {},
      );
      final onDay2 = plan(json, 'fajr', day2)!;
      expect(onDay2.alarms, {5123});
      expect(onDay2.notifications, {401123});
      expect(plan(json, 'fajr', '2026-09-26')!.alarms, {523123});
    });

    test('files a copy under the day it fires on, which rolls at midnight', () {
      final json = ArmedReminderRecord.encode(
        copies: [
          note('witr', 5200, DateTime(2026, 9, 22, 23, 59)),
          note('witr', 400200, DateTime(2026, 9, 23, 0, 30)),
        ],
        bundles: const [],
        snoozeIds: const {},
      );
      expect(plan(json, 'witr', day2)!.notifications, {5200});
      expect(plan(json, 'witr', day3)!.notifications, {400200});
    });

    group('a bundle', () {
      // «سنة المغرب» and «أذكار المساء» both at Maghrib: one notification
      // naming both.
      final json = ArmedReminderRecord.encode(
        copies: const [],
        bundles: [
          (
            id: 7000,
            fireTime: DateTime(2026, 9, 22, 17, 45),
            habitIds: ['sunnah', 'adhkar'],
          ),
          (
            id: 7001,
            fireTime: DateTime(2026, 9, 23, 17, 45),
            habitIds: ['sunnah', 'adhkar'],
          ),
        ],
        snoozeIds: const {},
      );

      test('stays while another habit in it is still owed', () {
        expect(plan(json, 'sunnah', day2)!.notifications, isEmpty);
      });

      test('goes once every other habit in it is done that day', () {
        expect(
          plan(json, 'sunnah', day2, done: {'adhkar'})!.notifications,
          {7000},
        );
        expect(
          plan(json, 'sunnah', day2, done: {'adhkar'})!.notifications,
          isNot(contains(7001)),
          reason: "tomorrow's bundle is tomorrow's",
        );
      });

      test('a habit the record does not know leaves the bundle alone', () {
        expect(plan(json, 'other', day2, done: {'sunnah', 'adhkar'})!
            .notifications, isEmpty);
      });
    });

    test('a habit or day with nothing armed takes nothing', () {
      final json = ArmedReminderRecord.encode(
        copies: [note('fajr', 5123, DateTime(2026, 9, 22, 4))],
        bundles: const [],
        snoozeIds: const {},
      );
      expect(plan(json, 'quran', day2), isNotNull);
      expect(plan(json, 'quran', day2)!.notifications, isEmpty);
      expect(plan(json, 'fajr', day1)!.notifications, isEmpty);
    });

    test('no record, a damaged one, or another version reads as none', () {
      for (final raw in [
        null,
        '',
        'not json',
        '[]',
        jsonEncode({'v': 2, 'habits': <String, Object>{}}),
        jsonEncode({'habits': <String, Object>{}}),
      ]) {
        expect(
          ArmedReminderRecord.standDownFor(
            raw,
            habitId: 'fajr',
            day: day2,
            doneOnDay: const {},
          ),
          isNull,
          reason: '$raw',
        );
      }
    });

    test('a malformed entry costs itself, not the record', () {
      final json = jsonEncode({
        'v': ArmedReminderRecord.version,
        'habits': {
          'fajr': {
            'days': {
              day2: {
                'notifications': [5123, 'x', null],
                'alarms': 'nope',
              },
            },
          },
          'quran': 'nope',
        },
        'bundles': {'7000': 'nope'},
      });
      expect(plan(json, 'fajr', day2)!.notifications, {5123});
      expect(plan(json, 'fajr', day2)!.alarms, isEmpty);
      expect(plan(json, 'quran', day2)!.notifications, isEmpty);
    });
  });

  group('encode', () {
    test('the shape the widget decodes, empty lists left out', () {
      final json = ArmedReminderRecord.encode(
        copies: [
          note('fajr', 5123, DateTime(2026, 9, 22, 4, 30)),
          alarm('fajr', 400123, DateTime(2026, 9, 23, 3, 30)),
        ],
        bundles: [
          (
            id: 7000,
            fireTime: DateTime(2026, 9, 22, 17, 45),
            habitIds: ['fajr', 'adhkar'],
          ),
        ],
        snoozeIds: const {'fajr': 6123, 'quran': 6456},
      );
      expect(jsonDecode(json), {
        'v': 1,
        'habits': {
          'fajr': {
            'snooze': 6123,
            'days': {
              day2: {
                'notifications': [5123],
                'bundles': [7000],
              },
              day3: {
                'alarms': [400123],
              },
            },
          },
          'quran': {'snooze': 6456},
          'adhkar': {
            'days': {
              day2: {
                'bundles': [7000],
              },
            },
          },
        },
        'bundles': {
          '7000': ['fajr', 'adhkar'],
        },
      });
    });

    test('nothing armed is still a record, which takes nothing', () {
      final json = ArmedReminderRecord.encode(
        copies: const [],
        bundles: const [],
        snoozeIds: const {},
      );
      expect(jsonDecode(json), {'v': 1, 'habits': <String, Object?>{}});
      expect(plan(json, 'fajr', day2)!.notifications, isEmpty);
    });
  });

  group('NotificationActionRules.doneOn', () {
    final list = jsonEncode([
      {'id': 'fajr', 'name': 'الفجر', 'done': true},
      {'id': 'quran', 'name': 'قرآن', 'done': false},
      {'id': 'witr', 'name': 'الوتر', 'done': true, 'count': 1, 'perDay': 1},
    ]);

    test("the checkmarks of the day's own list", () {
      expect(
        NotificationActionRules.doneOn(list, listDay: day2, day: day2),
        {'fajr', 'witr'},
      );
    });

    test("another day's list, or one with no day, knows nothing", () {
      expect(
        NotificationActionRules.doneOn(list, listDay: day1, day: day2),
        isEmpty,
        reason: "yesterday's checkmarks say nothing about today",
      );
      expect(
        NotificationActionRules.doneOn(list, listDay: null, day: day2),
        isEmpty,
        reason: 'a list written before the day was stamped beside it',
      );
      expect(
        NotificationActionRules.doneOn(null, listDay: day2, day: day2),
        isEmpty,
      );
    });
  });
}
