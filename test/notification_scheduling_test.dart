import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/services/notification_service.dart';

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
}
