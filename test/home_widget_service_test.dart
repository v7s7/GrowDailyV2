// Deterministic tests for HomeWidgetService.recentHeatmap - the pure
// 28-day windowing/formatting logic behind the widget's mini heatmap.
// Promoted from a private instance method to a public, @visibleForTesting
// static one (see that method's doc comment) specifically so [now] can be
// pinned to a fixed instant here instead of depending on whatever day the
// suite happens to run - the same reasoning notification_scheduling_test.dart
// already applies to NotificationService.groupByFireTimeWindow.
//
// Every other public method on HomeWidgetService (updateWidgetData,
// updateRoomRaceData, takePendingCompletions, ...) is a thin wrapper around
// the home_widget plugin's platform channel and isn't covered here - there's
// no pure logic left in them once this windowing math is pulled out, and
// exercising the plugin itself needs a real iOS host, not a unit test.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/core/services/home_widget_service.dart';

void main() {
  group('HomeWidgetService.recentHeatmap', () {
    // A fixed, unambiguous instant - clear of both the 10am day-cutoff and
    // any month/year rollover - so every test below is about the windowing
    // math itself, never today's real date.
    final fixedNow = DateTime(2026, 3, 15, 12, 0);

    test('produces exactly 28 entries', () {
      final result = HomeWidgetService.recentHeatmap({}, now: fixedNow);
      expect(result.length, 28);
    });

    test('is oldest-first: last entry is today, first is 27 days earlier', () {
      final result = HomeWidgetService.recentHeatmap({}, now: fixedNow);
      final today = fixedNow.effectiveDay;
      expect(result.last['date'], today.toDateKey());
      expect(
        result.first['date'],
        today.subtract(const Duration(days: 27)).toDateKey(),
      );
    });

    test('entries are in strictly ascending date order', () {
      final result = HomeWidgetService.recentHeatmap({}, now: fixedNow);
      for (var i = 1; i < result.length; i++) {
        final prev = DateTime.parse(result[i - 1]['date'] as String);
        final curr = DateTime.parse(result[i]['date'] as String);
        expect(curr.isAfter(prev), isTrue);
      }
    });

    test('pulls the matching count for a date present in the map', () {
      final today = fixedNow.effectiveDay;
      final key = today.toDateKey();
      final result = HomeWidgetService.recentHeatmap({key: 4}, now: fixedNow);
      expect(result.last['count'], 4);
    });

    test('defaults to 0 for a date missing from the map', () {
      final result = HomeWidgetService.recentHeatmap({}, now: fixedNow);
      expect(result.every((e) => e['count'] == 0), isTrue);
    });

    test('ignores map entries outside the 28-day window', () {
      final farAway = fixedNow.effectiveDay
          .subtract(const Duration(days: 100))
          .toDateKey();
      final result =
          HomeWidgetService.recentHeatmap({farAway: 9}, now: fixedNow);
      expect(result.any((e) => e['count'] == 9), isFalse);
    });

    test(
        'respects the day-cutoff: just after midnight still counts as the '
        'previous calendar day (see DateTimeGameExt.effectiveDay)', () {
      // 1am is before kDayCutoffHour (10am) - effectiveDay should roll this
      // back onto March 14th, not March 15th.
      final justAfterMidnight = DateTime(2026, 3, 15, 1, 0);
      final result = HomeWidgetService.recentHeatmap(
        {},
        now: justAfterMidnight,
      );
      expect(result.last['date'], DateTime(2026, 3, 14).toDateKey());
    });

    test('defaults [now] to the real current time when omitted', () {
      final result = HomeWidgetService.recentHeatmap({});
      expect(result.last['date'], DateTime.now().effectiveDay.toDateKey());
    });
  });
}
