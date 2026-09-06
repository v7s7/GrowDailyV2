// The pure rules behind a notification action tapped with the app closed
// (lib/core/services/notification_action_queue.dart).
//
// The headless engine that handles such a tap has no habit list and no
// provider tree, so everything it decides comes from two JSON strings in the
// App Group store: the widget's cached today-list and its own queue. These
// tests pin what it may conclude from them, because a wrong conclusion is
// either a habit drawn done that is not, a reminder silenced that was still
// owed, or a tap credited to the wrong day.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/services/notification_action_queue.dart';

void main() {
  const tap = QueuedNotificationAction(
    action: 'mark_done',
    habitId: 'fajr_prayer',
    day: '2026-09-06',
  );

  group('QueuedNotificationAction', () {
    test('round-trips through JSON', () {
      expect(QueuedNotificationAction.fromJson(tap.toJson()), tap);
    });

    test('rejects an incomplete or malformed record instead of throwing', () {
      expect(QueuedNotificationAction.fromJson(null), isNull);
      expect(QueuedNotificationAction.fromJson('mark_done'), isNull);
      expect(QueuedNotificationAction.fromJson({'action': 'mark_done'}),
          isNull);
      expect(
        QueuedNotificationAction.fromJson(
            {'action': '', 'habitId': 'x', 'day': '2026-09-06'}),
        isNull,
        reason: 'an empty field is as useless as a missing one',
      );
    });

    test('dayDate is the local midnight of the key it was written with', () {
      final day = tap.dayDate!;
      expect(day, DateTime(2026, 9, 6));
      expect(day.isUtc, isFalse,
          reason: 'the drain compares it against local effective days');
    });

    test('dayDate is null for a key nothing can parse', () {
      const broken = QueuedNotificationAction(
          action: 'mark_done', habitId: 'x', day: 'yesterday');
      expect(broken.dayDate, isNull);
    });
  });

  group('NotificationActionRules queue', () {
    test('an empty or missing store decodes to nothing', () {
      expect(NotificationActionRules.decodeQueue(null), isEmpty);
      expect(NotificationActionRules.decodeQueue(''), isEmpty);
      expect(NotificationActionRules.decodeQueue('not json'), isEmpty);
      expect(NotificationActionRules.decodeQueue('{"a":1}'), isEmpty);
    });

    test('append keeps order and drops only the broken entry', () {
      final first = NotificationActionRules.appendToQueue(null, tap);
      final withJunk = jsonEncode([
        ...jsonDecode(first) as List,
        {'action': 'quit_slipped'}, // incomplete
      ]);
      const second = QueuedNotificationAction(
          action: 'quit_slipped', habitId: 'coffee', day: '2026-09-06');
      final queue = NotificationActionRules.decodeQueue(
          NotificationActionRules.appendToQueue(withJunk, second));
      expect(queue, [tap, second]);
    });

    test('the queue is capped from the front', () {
      String? raw;
      for (var i = 0; i < NotificationActionRules.maxQueued + 5; i++) {
        raw = NotificationActionRules.appendToQueue(
          raw,
          QueuedNotificationAction(
              action: 'mark_done', habitId: 'h$i', day: '2026-09-06'),
        );
      }
      final queue = NotificationActionRules.decodeQueue(raw);
      expect(queue.length, NotificationActionRules.maxQueued);
      expect(queue.first.habitId, 'h5',
          reason: 'the oldest taps are the ones to lose');
      expect(queue.last.habitId, 'h${NotificationActionRules.maxQueued + 4}');
    });
  });

  group('NotificationActionRules today-list', () {
    String list(List<Map<String, Object?>> entries) => jsonEncode(entries);

    test('a one-a-day habit is drawn done after one tap', () {
      final raw = list([
        {'id': 'fajr_prayer', 'name': 'الفجر', 'done': false, 'count': 0,
          'perDay': 1},
        {'id': 'quran', 'name': 'قرآن', 'done': false, 'count': 0,
          'perDay': 1},
      ]);
      final out = jsonDecode(
          NotificationActionRules.markOneDone(raw, 'fajr_prayer')!) as List;
      expect(out[0], {
        'id': 'fajr_prayer', 'name': 'الفجر', 'done': true, 'count': 1,
        'perDay': 1,
      });
      expect(out[1]['done'], isFalse, reason: 'other habits untouched');
    });

    test('a counted habit only shows done when the count reaches perDay', () {
      final raw = list([
        {'id': 'water', 'name': 'ماء', 'done': false, 'count': 1,
          'perDay': 3},
      ]);
      final afterOne = NotificationActionRules.markOneDone(raw, 'water')!;
      final one = (jsonDecode(afterOne) as List).first;
      expect(one['count'], 2);
      expect(one['done'], isFalse,
          reason: 'two of three is not done, and the widget must not say so');
      final afterTwo = NotificationActionRules.markOneDone(afterOne, 'water')!;
      final two = (jsonDecode(afterTwo) as List).first;
      expect(two['count'], 3);
      expect(two['done'], isTrue);
      final afterThree =
          NotificationActionRules.markOneDone(afterTwo, 'water')!;
      expect((jsonDecode(afterThree) as List).first['count'], 3,
          reason: 'a tap past the target does not overshoot the count');
    });

    test('a list the widget re-encoded without counts still flips done', () {
      // MarkHabitDoneIntent in GrowDailyWidget.swift writes only id/name/done.
      final raw = list([
        {'id': 'water', 'name': 'ماء', 'done': false},
      ]);
      final out = (jsonDecode(NotificationActionRules.markOneDone(raw, 'water')!)
          as List)
          .first;
      expect(out['done'], isTrue);
      expect(out.containsKey('count'), isFalse,
          reason: 'no invented fields on a list that never had them');
    });

    test('nothing to rewrite when the habit is absent or the list unusable',
        () {
      expect(NotificationActionRules.markOneDone(null, 'x'), isNull);
      expect(NotificationActionRules.markOneDone('garbage', 'x'), isNull);
      expect(
        NotificationActionRules.markOneDone(
            list([{'id': 'other', 'name': 'o', 'done': false}]), 'x'),
        isNull,
      );
    });

    test('finishesDay is exact when counts are known', () {
      final raw = list([
        {'id': 'water', 'name': 'ماء', 'done': false, 'count': 1,
          'perDay': 3},
        {'id': 'fajr_prayer', 'name': 'الفجر', 'done': false, 'count': 0,
          'perDay': 1},
      ]);
      expect(NotificationActionRules.finishesDay(raw, 'water'), isFalse,
          reason: 'a second slice of three leaves the third reminder owed');
      expect(NotificationActionRules.finishesDay(raw, 'fajr_prayer'), isTrue);
    });

    test('finishesDay errs toward standing down when it cannot know', () {
      // The app never nags about a done habit; the next open re-arms what
      // is genuinely still owed.
      expect(NotificationActionRules.finishesDay(null, 'x'), isTrue);
      expect(
        NotificationActionRules.finishesDay(
            list([{'id': 'x', 'name': 'x', 'done': false}]), 'x'),
        isTrue,
      );
      expect(
        NotificationActionRules.finishesDay(
            list([{'id': 'other', 'name': 'o', 'done': false}]), 'x'),
        isTrue,
      );
    });

    test('habitName reads the localized name the app last wrote', () {
      final raw = list([
        {'id': 'fajr_prayer', 'name': 'صلاة الفجر', 'done': false},
      ]);
      expect(NotificationActionRules.habitName(raw, 'fajr_prayer'),
          'صلاة الفجر');
      expect(NotificationActionRules.habitName(raw, 'quran'), isNull);
      expect(NotificationActionRules.habitName(null, 'quran'), isNull);
    });
  });
}
