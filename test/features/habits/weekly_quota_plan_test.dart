// Proves the one property the whole weekly-quota redesign rests on: the system
// can identify a MISSED day on its own, exactly, without the user marking
// anything — and it can never accuse someone of more misses than they actually
// fell short by.
//
// The claim under test:
//
//   count(owed and not done) == max(0, target − done)
//
// checked exhaustively over every target 1..7 against all 128 completion
// patterns of a 7-day week. Not a sample — every case.
//
// Plus the stability property that motivated the day-local rule in the first
// place: a resolved day's verdict must not depend on anything that happens
// after it. That is what kills the retroactive flip, where a Tuesday silently
// turned from "missed" into "rest day" because of a session logged on Friday.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/habits/models/weekly_quota_plan.dart';

/// Every subset of a 7-day week, as index sets — all 128 of them.
Iterable<Set<int>> _allPatterns(int dayCount) sync* {
  for (var mask = 0; mask < (1 << dayCount); mask++) {
    yield {
      for (var i = 0; i < dayCount; i++)
        if (mask & (1 << i) != 0) i,
    };
  }
}

void main() {
  group('weeklyQuotaDemand — the system detects misses by itself', () {
    test(
        'missed days always equal the shortfall exactly — every target, every '
        'pattern', () {
      for (var target = 1; target <= 7; target++) {
        for (final done in _allPatterns(7)) {
          final demand =
              weeklyQuotaDemand(dayCount: 7, doneDays: done, target: target);

          final missed = [
            for (var i = 0; i < 7; i++)
              if (demand[i] == DayDemand.owed && !done.contains(i)) i,
          ].length;
          final shortfall = (target - done.length).clamp(0, 7);

          expect(
            missed,
            shortfall,
            reason: 'target $target, done $done: the app marked $missed day(s) '
                'as missed but the person was only $shortfall short',
          );
        }
      }
    });

    test('a met or beaten target produces zero missed days', () {
      // Doing MORE than promised must never be punished — 7 sessions on a
      // 4x week is someone exceeding their commitment, not failing it.
      for (var target = 1; target <= 7; target++) {
        for (final done in _allPatterns(7)) {
          if (done.length < target) continue;
          final demand =
              weeklyQuotaDemand(dayCount: 7, doneDays: done, target: target);
          final missed = [
            for (var i = 0; i < 7; i++)
              if (demand[i] == DayDemand.owed && !done.contains(i)) i,
          ];
          expect(missed, isEmpty,
              reason: 'target $target, done $done should have no misses');
        }
      }
    });

    test('every completed day reads as done, never as a miss', () {
      for (var target = 1; target <= 7; target++) {
        for (final done in _allPatterns(7)) {
          final demand =
              weeklyQuotaDemand(dayCount: 7, doneDays: done, target: target);
          for (final i in done) {
            expect(demand[i], DayDemand.done);
          }
        }
      }
    });

    test(
        'a resolved day never changes verdict because of a later day — the '
        'retroactive flip is gone', () {
      // The bug this rule exists to kill: under the old week-level rule a
      // Tuesday was graded using Friday's outcome, so the same Tuesday could
      // read "missed" on Wednesday and "rest day" on Saturday. Here, day d's
      // verdict is recomputed with every possible future and must not move.
      for (var target = 1; target <= 7; target++) {
        for (final done in _allPatterns(7)) {
          final full =
              weeklyQuotaDemand(dayCount: 7, doneDays: done, target: target);
          for (var d = 0; d < 7; d++) {
            final pastOnly = done.where((i) => i <= d).toSet();
            for (final future in _allPatterns(7)) {
              final alternate = {...pastOnly, ...future.where((i) => i > d)};
              final other = weeklyQuotaDemand(
                  dayCount: 7, doneDays: alternate, target: target);
              expect(
                other[d],
                full[d],
                reason: 'day $d flipped from ${full[d]} to ${other[d]} when '
                    'only later days changed (target $target)',
              );
            }
          }
        }
      }
    });

    test('the measured real case: 3x a week, done Sunday and Tuesday', () {
      // Sat=0 .. Fri=6. Two done, target 3 → exactly one day should be owed
      // and empty, and it must be the last day, because that is the only day
      // by which the target genuinely becomes unreachable.
      final demand =
          weeklyQuotaDemand(dayCount: 7, doneDays: {1, 3}, target: 3);

      expect(demand[1], DayDemand.done);
      expect(demand[3], DayDemand.done);
      expect(demand[6], DayDemand.owed, reason: 'Friday is the last chance');
      // Everything else was genuinely optional at the time it happened.
      for (final i in [0, 2, 4, 5]) {
        expect(demand[i], DayDemand.spare, reason: 'day $i was never required');
        expect(demand[i].isRest, isTrue);
      }
    });

    test('finishing early marks the remaining days earned, not owed', () {
      // 3x done on Sat/Sun/Mon. The rest of the week owes nothing, and those
      // days are settled immediately — a met target cannot become un-met.
      final demand =
          weeklyQuotaDemand(dayCount: 7, doneDays: {0, 1, 2}, target: 3);
      for (final i in [3, 4, 5, 6]) {
        expect(demand[i], DayDemand.earned);
        expect(demand[i].isRest, isTrue);
        expect(demand[i].isSettled, isTrue);
      }
    });

    test('a short week clamps the target instead of demanding the impossible',
        () {
      // A habit created on Thursday, or a room's final partial week: asking
      // for 5 sessions in 3 days would mark days missed that never existed.
      final demand =
          weeklyQuotaDemand(dayCount: 3, doneDays: {0, 1, 2}, target: 5);
      expect(demand.length, 3);
      expect(demand.every((d) => d == DayDemand.done), isTrue);
    });

    test('an empty week owes exactly its target, on its last days', () {
      final demand =
          weeklyQuotaDemand(dayCount: 7, doneDays: const {}, target: 3);
      expect(demand.where((d) => d == DayDemand.owed).length, 3);
      // The owed days are the tail — the days by which it became impossible.
      expect(demand.sublist(4), everyElement(DayDemand.owed));
      expect(demand.sublist(0, 4), everyElement(DayDemand.spare));
    });
  });
}
