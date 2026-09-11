// The day clock re-reads itself at the only two instants a day's settled
// state can change: kDayCutoffHour and midnight. nextDayBoundaryAfter is the
// arithmetic; dayClockProvider only arms a timer for it.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/core/providers/day_clock_provider.dart';

void main() {
  DateTime fri(int h, [int m = 0]) => DateTime(2026, 9, 11, h, m);
  final satMidnight = DateTime(2026, 9, 12);

  test('before the cutoff, the next boundary is the cutoff', () {
    expect(nextDayBoundaryAfter(fri(0)), fri(kDayCutoffHour));
    expect(nextDayBoundaryAfter(fri(kDayCutoffHour - 1, 59)),
        fri(kDayCutoffHour));
  });

  test('at the cutoff and after it, the next boundary is midnight', () {
    expect(nextDayBoundaryAfter(fri(kDayCutoffHour)), satMidnight);
    expect(nextDayBoundaryAfter(fri(23, 59)), satMidnight);
  });

  test('nothing the clock guards changes between two boundaries', () {
    // A clock held from the start of a stretch must answer every day
    // question exactly as a clock read at its last minute would.
    final stretches = [
      (fri(0), fri(kDayCutoffHour - 1, 59)),
      (fri(kDayCutoffHour), fri(23, 59)),
    ];
    final days = [
      for (var d = 9; d <= 12; d++) DateTime(2026, 9, d),
    ];
    for (final (start, end) in stretches) {
      expect(nextDayBoundaryAfter(start), nextDayBoundaryAfter(end));
      expect(start.effectiveDay, end.effectiveDay);
      for (final day in days) {
        expect(day.isSettledAt(start), day.isSettledAt(end),
            reason: '$day between $start and $end');
        expect(day.isOpenDayAt(start), day.isOpenDayAt(end),
            reason: '$day between $start and $end');
      }
    }
  });

  test('the provider hands out the wall clock and cleans up with its container',
      () {
    final container = ProviderContainer();
    final before = DateTime.now();
    final read = container.read(dayClockProvider);
    final after = DateTime.now();
    expect(read.isBefore(before), isFalse);
    expect(read.isAfter(after), isFalse);
    // Disposing cancels the boundary timer; a leaked one would keep a test
    // process, or a closed screen's container, alive for hours.
    container.dispose();
  });

  testWidgets('the provider re-reads itself at the cutoff, then at midnight',
      (tester) async {
    // dayClockSourceProvider stands in for the wall clock, and testWidgets
    // runs the boundary timer on fake time, so no real 10:00 is needed.
    final start = fri(kDayCutoffHour - 1, 59).add(const Duration(seconds: 30));
    var wall = start;
    final container = ProviderContainer(
      overrides: [dayClockSourceProvider.overrideWithValue(() => wall)],
    );
    final seen = <DateTime>[];
    final sub = container.listen<DateTime>(
      dayClockProvider,
      (_, next) => seen.add(next),
      fireImmediately: true,
    );
    Future<void> advance(Duration by) async {
      wall = wall.add(by);
      await tester.pump(by);
    }

    expect(seen, [start]);
    expect(DateTime(2026, 9, 10).isSettledAt(seen.last), isFalse);

    // The timer is armed for the boundary plus one second.
    await advance(const Duration(seconds: 30));
    expect(seen, hasLength(1), reason: 'exactly 10:00:00, a second early');
    await advance(const Duration(seconds: 1));
    expect(seen, hasLength(2), reason: 'the cutoff has passed');
    expect(DateTime(2026, 9, 10).isSettledAt(seen.last), isTrue,
        reason: 'Thursday closes with it');

    await advance(satMidnight.difference(wall));
    expect(seen, hasLength(2), reason: 'exactly midnight, a second early');
    await advance(const Duration(seconds: 1));
    expect(seen, hasLength(3));
    expect(seen.last.effectiveDay, DateTime(2026, 9, 12));

    sub.close();
    container.dispose();
  });

  test('each boundary is exactly where some day changes, in any time zone',
      () {
    // In Bahrain every day below is an ordinary day. Run under
    // TZ=Europe/London or TZ=America/New_York, the same walk crosses the
    // 2026 clock changes, where yesterday closes an hour either side of
    // 10:00 (closesAt is a fixed 34 hours) and a timer armed for a wall-clock
    // 10:00 fired an hour off.
    const tick = Duration(milliseconds: 1);
    List<Object> answersAt(DateTime instant, DateTime around) => [
          instant.effectiveDay,
          for (var k = -3; k <= 2; k++)
            DateTime(around.year, around.month, around.day + k)
                .isOpenDayAt(instant),
        ];
    final walks = [
      DateTime(2026, 3, 6),
      DateTime(2026, 3, 27),
      DateTime(2026, 9, 9),
      DateTime(2026, 10, 23),
      DateTime(2026, 10, 30),
    ];
    for (final start in walks) {
      final stop = start.add(const Duration(days: 4));
      for (var t = start;
          t.isBefore(stop);
          t = t.add(const Duration(minutes: 30))) {
        final next = nextDayBoundaryAfter(t);
        expect(next.isAfter(t), isTrue, reason: '$t');
        expect(answersAt(next.subtract(tick), t), answersAt(t, t),
            reason: 'nothing may change between $t and $next');
        expect(answersAt(next, t), isNot(answersAt(t, t)),
            reason: 'something must change at $next, read from $t');
      }
    }
  });

  group('dayClockIsStale, which a resume asks before re-reading the clock', () {
    test('false anywhere between two boundaries', () {
      expect(
        dayClockIsStale(seen: fri(0, 1), now: fri(kDayCutoffHour - 1, 59)),
        isFalse,
      );
      expect(dayClockIsStale(seen: fri(kDayCutoffHour), now: fri(23, 59)),
          isFalse);
      expect(dayClockIsStale(seen: fri(5, 19), now: fri(5, 19)), isFalse);
    });

    test('true from the boundary on', () {
      expect(dayClockIsStale(seen: fri(9), now: fri(kDayCutoffHour)), isTrue,
          reason: 'put away at 09:00 and opened at 10:00: Thursday has closed');
      expect(dayClockIsStale(seen: fri(22), now: satMidnight), isTrue);
      expect(
        dayClockIsStale(seen: fri(9), now: DateTime(2026, 9, 14, 8)),
        isTrue,
        reason: 'opened days later',
      );
    });

    test('true when the clock has been moved back', () {
      expect(dayClockIsStale(seen: fri(12), now: fri(11, 59)), isTrue);
    });

    test('stale exactly when some day answer has changed', () {
      // Every half hour across four days, and a millisecond before each, so
      // both sides of every boundary are in the walk.
      final instants = <DateTime>[
        for (var t = DateTime(2026, 9, 9);
            t.isBefore(DateTime(2026, 9, 13));
            t = t.add(const Duration(minutes: 30))) ...[
          t.subtract(const Duration(milliseconds: 1)),
          t,
        ],
      ];
      String answersAt(DateTime instant) => [
            instant.effectiveDay,
            for (var d = 7; d <= 15; d++)
              DateTime(2026, 9, d).isOpenDayAt(instant),
          ].join('|');
      final answers = {for (final t in instants) t: answersAt(t)};
      final wrong = <String>[];
      for (final seen in instants) {
        for (final now in instants) {
          if (now.isBefore(seen)) continue;
          final changed = answers[seen] != answers[now];
          if (dayClockIsStale(seen: seen, now: now) != changed) {
            wrong.add('$seen then $now');
          }
        }
      }
      expect(wrong, isEmpty);
    });
  });

  group('refreshDayClockIfStale, what main.dart runs on resume', () {
    // Plain tests on real time: the provider's own timer is hours away, and
    // disposing the container cancels it.
    ProviderContainer containerReading(DateTime Function() wall) {
      final container = ProviderContainer(
        overrides: [dayClockSourceProvider.overrideWithValue(wall)],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('re-reads the clock once a boundary has passed', () {
      var wall = fri(9);
      final container = containerReading(() => wall);
      expect(container.read(dayClockProvider), fri(9));
      wall = fri(11);
      expect(refreshDayClockIfStale(container), isTrue);
      expect(
        container.read(dayClockProvider),
        fri(11),
        reason: 'put away at 09:00 and opened at 11:00: Thursday has closed',
      );
    });

    test('leaves the clock alone between two boundaries', () {
      var wall = fri(kDayCutoffHour, 30);
      final container = containerReading(() => wall);
      final seen = <DateTime>[];
      container.listen<DateTime>(
        dayClockProvider,
        (_, next) => seen.add(next),
        fireImmediately: true,
      );
      wall = fri(23, 59);
      expect(refreshDayClockIfStale(container), isFalse);
      expect(container.read(dayClockProvider), fri(kDayCutoffHour, 30));
      expect(
        seen,
        [fri(kDayCutoffHour, 30)],
        reason: 'no watcher rebuilds for answers that have not changed',
      );
    });

    test('re-reads the clock when it has been moved back', () {
      var wall = fri(12);
      final container = containerReading(() => wall);
      expect(container.read(dayClockProvider), fri(12));
      wall = fri(11, 59);
      expect(refreshDayClockIfStale(container), isTrue);
      expect(container.read(dayClockProvider), fri(11, 59));
    });
  });
}
