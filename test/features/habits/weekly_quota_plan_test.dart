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

  // Aziz, 2026-09-26: "0.5 is a day count, unless it's overwritten with a
  // full day". A جزئي is a session that holds one of the week's places at
  // half credit, and whole sessions take the places first. Every property
  // above is re-proved over weeks where each day is empty, whole or half:
  // 3^7 = 2187 weeks per target.
  group('weeklyQuotaDemand with half sessions (جزئي)', () {
    test('missed days equal the shortfall in SESSIONS, halves included', () {
      for (var target = 1; target <= 7; target++) {
        for (final week in _allMixedWeeks(7)) {
          final demand = weeklyQuotaDemand(
            dayCount: 7,
            doneDays: week.whole,
            halfDays: week.half,
            target: target,
          );
          final missed = [
            for (var i = 0; i < 7; i++)
              if (demand[i] == DayDemand.owed) i,
          ];
          final sessions = week.whole.length + week.half.length;
          expect(missed.length, (target - sessions).clamp(0, 7),
              reason: 'target $target, $week');
          // An owed day is only ever an empty one.
          for (final i in missed) {
            expect(week.whole.contains(i) || week.half.contains(i), isFalse);
          }
        }
      }
    });

    test('whole days read done; halves read half or, without a place, earned',
        () {
      for (var target = 1; target <= 7; target++) {
        for (final week in _allMixedWeeks(7)) {
          final demand = weeklyQuotaDemand(
            dayCount: 7,
            doneDays: week.whole,
            halfDays: week.half,
            target: target,
          );
          final places = quotaWeekPlaces(
            dayCount: 7,
            doneDays: week.whole,
            halfDays: week.half,
            target: target,
          );
          for (final i in week.whole) {
            expect(demand[i], DayDemand.done);
          }
          for (final i in week.half) {
            expect(
              demand[i],
              places.contains(i) ? DayDemand.half : DayDemand.earned,
              reason: 'target $target, $week, day $i',
            );
          }
          // The places are exactly min(target, sessions), wholes first.
          final sessions = week.whole.length + week.half.length;
          expect(places.length, target < sessions ? target : sessions);
          final wholePlaces = places.where(week.whole.contains).length;
          expect(wholePlaces,
              target < week.whole.length ? target : week.whole.length);
          // A half keeps a place only when the wholes leave one over.
          if (week.whole.length >= target) {
            expect(places.where(week.half.contains), isEmpty);
          }
        }
      }
    });

    test('a later half never pushes out an earlier one', () {
      for (var target = 1; target <= 7; target++) {
        for (final week in _allMixedWeeks(7)) {
          final places = quotaWeekPlaces(
            dayCount: 7,
            doneDays: week.whole,
            halfDays: week.half,
            target: target,
          );
          final halves = week.half.toList()..sort();
          final kept = halves.where(places.contains).toList();
          expect(kept, halves.take(kept.length).toList(),
              reason: 'target $target, $week: the halves keeping a place '
                  'must be the earliest ones');
        }
      }
    });

    test(
        "an empty day's verdict still depends only on the days before it, "
        'halves included', () {
      // Exhaustive on a 5-day week (3^5 = 243 weeks, every future of every
      // day), and the three uniform futures on a 7-day one.
      for (var target = 1; target <= 5; target++) {
        for (final week in _allMixedWeeks(5)) {
          final base = weeklyQuotaDemand(
            dayCount: 5,
            doneDays: week.whole,
            halfDays: week.half,
            target: target,
          );
          for (var d = 0; d < 5; d++) {
            if (week.whole.contains(d) || week.half.contains(d)) continue;
            for (final future in _allMixedWeeks(5)) {
              final other = weeklyQuotaDemand(
                dayCount: 5,
                doneDays: {
                  ...week.whole.where((i) => i <= d),
                  ...future.whole.where((i) => i > d),
                },
                halfDays: {
                  ...week.half.where((i) => i <= d),
                  ...future.half.where((i) => i > d),
                },
                target: target,
              );
              expect(other[d], base[d],
                  reason: 'target $target, $week: empty day $d flipped when '
                      'only later days changed');
            }
          }
        }
      }
      for (var target = 1; target <= 7; target++) {
        for (final week in _allMixedWeeks(7)) {
          final base = weeklyQuotaDemand(
            dayCount: 7,
            doneDays: week.whole,
            halfDays: week.half,
            target: target,
          );
          for (var d = 0; d < 7; d++) {
            if (week.whole.contains(d) || week.half.contains(d)) continue;
            final before = (
              whole: week.whole.where((i) => i <= d).toSet(),
              half: week.half.where((i) => i <= d).toSet(),
            );
            final later = {for (var i = d + 1; i < 7; i++) i};
            for (final future in [
              (whole: <int>{}, half: <int>{}),
              (whole: later, half: <int>{}),
              (whole: <int>{}, half: later),
            ]) {
              final other = weeklyQuotaDemand(
                dayCount: 7,
                doneDays: {...before.whole, ...future.whole},
                halfDays: {...before.half, ...future.half},
                target: target,
              );
              expect(other[d], base[d], reason: 'target $target, $week, $d');
            }
          }
        }
      }
    });

    test('doing more never lowers the week: a new session, or a half made whole',
        () {
      for (var target = 1; target <= 7; target++) {
        for (final week in _allMixedWeeks(7)) {
          double credit(Set<int> whole, Set<int> half) => quotaWeekCredit(
                dayCount: 7,
                doneDays: whole,
                halfDays: half,
                target: target,
              );
          final base = credit(week.whole, week.half);
          for (var i = 0; i < 7; i++) {
            if (week.whole.contains(i)) continue;
            // A half made whole, or an empty day given a whole session.
            expect(
              credit({...week.whole, i}, {...week.half}..remove(i)),
              greaterThanOrEqualTo(base),
              reason: 'target $target, $week, whole on $i',
            );
            if (week.half.contains(i)) continue;
            expect(
              credit(week.whole, {...week.half, i}),
              greaterThanOrEqualTo(base),
              reason: 'target $target, $week, half on $i',
            );
          }
        }
      }
    });

    test('without halves, nothing reads differently from before', () {
      for (var target = 1; target <= 7; target++) {
        for (final done in _allPatterns(7)) {
          expect(
            weeklyQuotaDemand(dayCount: 7, doneDays: done, target: target),
            _demandBeforeHalves(7, done, target),
            reason: 'target $target, done $done',
          );
        }
      }
    });

    // Sat = 0 .. Fri = 6, تمرين 4x a week: the three weeks Aziz described.
    test(
        "Aziz's 19 September: two halves then nothing is 1 of 4, three rest "
        'days and two misses', () {
      final demand = weeklyQuotaDemand(
        dayCount: 7,
        doneDays: const {},
        halfDays: const {0, 1},
        target: 4,
      );
      expect(demand, [
        DayDemand.half,
        DayDemand.half,
        DayDemand.spare,
        DayDemand.spare,
        DayDemand.spare,
        DayDemand.owed,
        DayDemand.owed,
      ]);
      expect(
        quotaWeekCredit(
          dayCount: 7,
          doneDays: const {},
          halfDays: const {0, 1},
          target: 4,
        ),
        1.0,
      );
    });

    test('two halves then four whole sessions counts the whole ones: 4 of 4',
        () {
      final demand = weeklyQuotaDemand(
        dayCount: 7,
        doneDays: const {2, 3, 4, 5},
        halfDays: const {0, 1},
        target: 4,
      );
      expect(demand, [
        DayDemand.earned,
        DayDemand.earned,
        DayDemand.done,
        DayDemand.done,
        DayDemand.done,
        DayDemand.done,
        DayDemand.earned,
      ]);
      expect(
        quotaWeekCredit(
          dayCount: 7,
          doneDays: const {2, 3, 4, 5},
          halfDays: const {0, 1},
          target: 4,
        ),
        4.0,
      );
    });

    test('two whole sessions and two halves is 3 of 4, the rest rest', () {
      final demand = weeklyQuotaDemand(
        dayCount: 7,
        doneDays: const {0, 1},
        halfDays: const {2, 3},
        target: 4,
      );
      expect(demand.sublist(0, 4), [
        DayDemand.done,
        DayDemand.done,
        DayDemand.half,
        DayDemand.half,
      ]);
      expect(demand.sublist(4), everyElement(DayDemand.earned));
      expect(
        quotaWeekCredit(
          dayCount: 7,
          doneDays: const {0, 1},
          halfDays: const {2, 3},
          target: 4,
        ),
        3.0,
      );
    });

    test('three whole and two halves: one half keeps the last place, 3.5', () {
      final demand = weeklyQuotaDemand(
        dayCount: 7,
        doneDays: const {2, 3, 4},
        halfDays: const {0, 1},
        target: 4,
      );
      expect(demand[0], DayDemand.half, reason: 'the earlier half stays');
      expect(demand[1], DayDemand.earned, reason: 'no place left for it');
      expect(
        quotaWeekCredit(
          dayCount: 7,
          doneDays: const {2, 3, 4},
          halfDays: const {0, 1},
          target: 4,
        ),
        3.5,
      );
    });
  });
}

typedef _MixedWeek = ({Set<int> whole, Set<int> half});

/// Every week of [dayCount] days where each day is empty, whole or half.
Iterable<_MixedWeek> _allMixedWeeks(int dayCount) sync* {
  var total = 1;
  for (var i = 0; i < dayCount; i++) {
    total *= 3;
  }
  for (var code = 0; code < total; code++) {
    final whole = <int>{};
    final half = <int>{};
    var c = code;
    for (var i = 0; i < dayCount; i++) {
      final digit = c % 3;
      c ~/= 3;
      if (digit == 1) whole.add(i);
      if (digit == 2) half.add(i);
    }
    yield (whole: whole, half: half);
  }
}

/// weeklyQuotaDemand exactly as it read before half sessions, kept as the
/// oracle that nothing without a جزئي in it moved.
List<DayDemand> _demandBeforeHalves(int dayCount, Set<int> done, int target) {
  final effectiveTarget = target.clamp(1, dayCount);
  final out = <DayDemand>[];
  var doneBefore = 0;
  for (var i = 0; i < dayCount; i++) {
    final need = effectiveTarget - doneBefore;
    if (need <= 0) {
      out.add(done.contains(i) ? DayDemand.done : DayDemand.earned);
    } else {
      out.add(done.contains(i)
          ? DayDemand.done
          : (dayCount - i - need <= 0 ? DayDemand.owed : DayDemand.spare));
    }
    if (done.contains(i)) doneBefore++;
  }
  return out;
}
