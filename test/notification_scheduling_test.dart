import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'package:grow_daily_v2/core/services/notification_service.dart';

/// A minimal stand-in for the private `_ResolvedReminder` record
/// [NotificationService.groupByFireTimeWindow] is really called with in
/// production — the function only ever reaches into `fireTime` (via the
/// [fireTimeOf] extractor it's given), so this is all a test needs.
typedef _TestItem = ({int id, tz.TZDateTime fireTime});

void main() {
  group('NotificationService.isMinuteWithinQuietHours', () {
    test('same-day window (does not wrap past midnight)', () {
      const start = TimeOfDay(hour: 13, minute: 0); // 1pm
      const end = TimeOfDay(hour: 14, minute: 0); // 2pm
      expect(NotificationService.isMinuteWithinQuietHours(13 * 60, start, end),
          isTrue);
      expect(
          NotificationService.isMinuteWithinQuietHours(
              13 * 60 + 30, start, end),
          isTrue);
      // End is exclusive — exactly 2:00pm is already back "awake."
      expect(NotificationService.isMinuteWithinQuietHours(14 * 60, start, end),
          isFalse);
      expect(
          NotificationService.isMinuteWithinQuietHours(
              12 * 60 + 59, start, end),
          isFalse);
    });

    test('window wraps past midnight — the common quiet-hours case', () {
      const start = TimeOfDay(hour: 22, minute: 0); // 10pm
      const end = TimeOfDay(hour: 7, minute: 0); // 7am
      expect(NotificationService.isMinuteWithinQuietHours(23 * 60, start, end),
          isTrue, reason: '11pm is inside a 10pm-7am window');
      expect(NotificationService.isMinuteWithinQuietHours(0, start, end),
          isTrue, reason: 'just after midnight is still inside');
      expect(
          NotificationService.isMinuteWithinQuietHours(
              6 * 60 + 59, start, end),
          isTrue,
          reason: '6:59am is still inside');
      expect(NotificationService.isMinuteWithinQuietHours(7 * 60, start, end),
          isFalse,
          reason: '7:00am exactly is where the window ends (exclusive)');
      expect(NotificationService.isMinuteWithinQuietHours(13 * 60, start, end),
          isFalse,
          reason: 'mid-afternoon is clearly outside');
    });

    test(
        'a typical Fajr time sits inside a typical overnight quiet window — '
        'exactly why prayer reminders are exempt by default (see '
        'NotificationSettings.quietHoursAppliesToPrayer)', () {
      const start = TimeOfDay(hour: 22, minute: 0);
      const end = TimeOfDay(hour: 7, minute: 0);
      const fajr = TimeOfDay(hour: 4, minute: 50);
      expect(
        NotificationService.isMinuteWithinQuietHours(
          fajr.hour * 60 + fajr.minute,
          start,
          end,
        ),
        isTrue,
      );
    });

    test('a zero-width window (start == end) never suppresses anything', () {
      const same = TimeOfDay(hour: 9, minute: 0);
      expect(NotificationService.isMinuteWithinQuietHours(9 * 60, same, same),
          isFalse);
      expect(NotificationService.isMinuteWithinQuietHours(0, same, same),
          isFalse);
      expect(
          NotificationService.isMinuteWithinQuietHours(23 * 59, same, same),
          isFalse);
    });
  });

  group('NotificationService.groupByFireTimeWindow', () {
    // TZDateTime.utc doesn't actually need the timezone database the way a
    // named zone (e.g. 'America/New_York') would, but this is called
    // anyway so the suite doesn't quietly depend on that implementation
    // detail continuing to hold.
    setUpAll(() => tz_data.initializeTimeZones());

    // A fixed anchor, [minutes] after a fixed epoch — every test below only
    // cares about *relative* spacing between items, never a real calendar
    // date.
    tz.TZDateTime at(int minutes) =>
        tz.TZDateTime.utc(2026, 1, 1).add(Duration(minutes: minutes));

    _TestItem item(int id, int minutes) => (id: id, fireTime: at(minutes));

    List<int> ids(List<_TestItem> group) => group.map((e) => e.id).toList();

    test('empty input produces no groups', () {
      final groups = NotificationService.groupByFireTimeWindow<_TestItem>(
        [],
        enabled: true,
        window: const Duration(minutes: 15),
        fireTimeOf: (e) => e.fireTime,
      );
      expect(groups, isEmpty);
    });

    test('a single item is its own group', () {
      final groups = NotificationService.groupByFireTimeWindow<_TestItem>(
        [item(1, 0)],
        enabled: true,
        window: const Duration(minutes: 15),
        fireTimeOf: (e) => e.fireTime,
      );
      expect(groups.length, 1);
      expect(ids(groups.first), [1]);
    });

    test('two items within the window merge into one group', () {
      final groups = NotificationService.groupByFireTimeWindow<_TestItem>(
        [item(1, 0), item(2, 10)],
        enabled: true,
        window: const Duration(minutes: 15),
        fireTimeOf: (e) => e.fireTime,
      );
      expect(groups.length, 1);
      expect(ids(groups.first), [1, 2]);
    });

    test('two items outside the window stay separate', () {
      final groups = NotificationService.groupByFireTimeWindow<_TestItem>(
        [item(1, 0), item(2, 20)],
        enabled: true,
        window: const Duration(minutes: 15),
        fireTimeOf: (e) => e.fireTime,
      );
      expect(groups.length, 2);
      expect(ids(groups[0]), [1]);
      expect(ids(groups[1]), [2]);
    });

    test('exactly at the window boundary still merges (<=, not <)', () {
      final groups = NotificationService.groupByFireTimeWindow<_TestItem>(
        [item(1, 0), item(2, 15)],
        enabled: true,
        window: const Duration(minutes: 15),
        fireTimeOf: (e) => e.fireTime,
      );
      expect(groups.length, 1);
      expect(ids(groups.first), [1, 2]);
    });

    test('one minute past the window boundary no longer merges', () {
      final groups = NotificationService.groupByFireTimeWindow<_TestItem>(
        [item(1, 0), item(2, 16)],
        enabled: true,
        window: const Duration(minutes: 15),
        fireTimeOf: (e) => e.fireTime,
      );
      expect(groups.length, 2);
    });

    test(
        'enabled: false keeps every item in its own group regardless of '
        'spacing', () {
      final groups = NotificationService.groupByFireTimeWindow<_TestItem>(
        [item(1, 0), item(2, 1), item(3, 2)],
        enabled: false,
        window: const Duration(minutes: 15),
        fireTimeOf: (e) => e.fireTime,
      );
      expect(groups.length, 3);
    });

    test(
        'a group is anchored to its first member, not a sliding window off '
        'the previous item — a third item within range of the second but '
        'not the first starts a new group', () {
      final groups = NotificationService.groupByFireTimeWindow<_TestItem>(
        [item(1, 0), item(2, 10), item(3, 20)],
        enabled: true,
        window: const Duration(minutes: 15),
        fireTimeOf: (e) => e.fireTime,
      );
      // Item 3 is 10min after item 2 (within window) but 20min after item
      // 1 — the group's anchor — so it starts a fresh group instead of
      // joining [1, 2].
      expect(groups.length, 2);
      expect(ids(groups[0]), [1, 2]);
      expect(ids(groups[1]), [3]);
    });

    test(
        'unsorted input is grouped in fire-time order regardless of the '
        'order items were passed in', () {
      final groups = NotificationService.groupByFireTimeWindow<_TestItem>(
        [item(2, 10), item(1, 0), item(3, 100)],
        enabled: true,
        window: const Duration(minutes: 15),
        fireTimeOf: (e) => e.fireTime,
      );
      expect(groups.length, 2);
      expect(ids(groups[0]), [1, 2]);
      expect(ids(groups[1]), [3]);
    });
  });
}
