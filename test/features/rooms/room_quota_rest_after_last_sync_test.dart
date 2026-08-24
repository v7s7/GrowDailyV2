// Regression tests for the rest days a weekly quota earns you AFTER your
// device stops syncing.
//
// Written from real production data in room A8GEL7 ("الإلتزااام"), a shared
// 4x-a-week habit. On 2026-08-22 the leaderboard drew a red cross on Perla's
// 20th and 21st of August. Her stored document said, unambiguously, that she
// had earned both days off:
//
//   quotaOkWeeks       : [2026-08-01, 2026-08-15]
//   dailyDoneCount     : ... 2026-08-15, 2026-08-17, 2026-08-18, 2026-08-19
//   dailyScheduledCount: ... 2026-08-16: 0   <- and then nothing
//   lastSyncedDay      : 2026-08-19
//
// Four greens inside the Saturday week beginning 2026-08-15 is the target met,
// which is exactly why 2026-08-15 is in quotaOkWeeks. But scheduledCountFor
// used to read `dailyScheduledCount[dateKey] ?? countedHabitCount`, and the
// sync only ever writes a day while the app is open. Hitting your quota on
// Wednesday and then not opening the app is not an edge case; it is the
// feature working. So the 20th and 21st carried no entry, the fallback called
// them fully scheduled, and the strip crossed out the two days the quota had
// already bought her.
//
// The tell that this was a bug and not a policy: _keepsStreak already forgave
// those same two days, because it reads quotaOkWeeks instead. One participant
// document, two different answers about the same Thursday.
//
// These are pure model tests - no Firestore, no widgets, no DateTime.now().
// Every date below is a fixed calendar date lifted from the real document.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/rooms/models/room_model.dart';

const _kHabit = '6b9c755a-e74f-47bb-9399-9a915b8a83f5';
const _kDailyHabit = 'a-plain-daily-habit';

/// The 4x-a-week rule the room actually froze for Perla's linked habit.
const _weeklyRule = RoomHabitRule(
  from: '2026-07-28',
  frequencyType: HabitFrequencyType.weekly,
  frequencyTarget: 4,
);
const _dailyRule = RoomHabitRule(
  from: '2026-07-28',
  frequencyType: HabitFrequencyType.daily,
  frequencyTarget: 1,
);

/// Perla's participant document as it actually stood on 2026-08-22, trimmed to
/// the fields this behaviour depends on. [quotaOkWeeks] and
/// [dailyScheduledCount] are overridable so each test can isolate one variable.
RoomParticipant _perla({
  List<String> quotaOkWeeks = const ['2026-08-01', '2026-08-15'],
  Map<String, int> dailyScheduledCount = const {
    '2026-08-01': 0,
    '2026-08-02': 0,
    '2026-08-06': 0,
    '2026-08-08': 0,
    '2026-08-09': 0,
    '2026-08-12': 0,
    '2026-08-16': 0,
  },
  Map<String, int> dailyDoneCount = const {
    '2026-08-15': 1,
    '2026-08-17': 1,
    '2026-08-18': 1,
    '2026-08-19': 1,
  },
  Map<String, int> dailyPartialCount = const {},
  List<String> linkedHabitIds = const [_kHabit],
  Map<String, List<RoomHabitRule>> habitRules = const {
    _kHabit: [_weeklyRule],
  },
  String? lastSyncedDay = '2026-08-19',
}) =>
    RoomParticipant(
      uid: 'Z0FndO3iFYgrzWzkwJ4QlOPBLPr2',
      displayName: 'Perla',
      characterId: 'female_abaya_navy',
      joinedAt: DateTime(2026, 7, 28),
      linkedHabitIds: linkedHabitIds,
      habitRules: habitRules,
      dailyDoneCount: dailyDoneCount,
      dailyScheduledCount: dailyScheduledCount,
      dailyPartialCount: dailyPartialCount,
      quotaOkWeeks: quotaOkWeeks,
      lastSyncedDay: lastSyncedDay,
      lastUpdated: DateTime(2026, 8, 19),
    );

void main() {
  // 2026-08-15 is a Saturday, and the app buckets weeks Saturday-first
  // (DateTimeGameExt.startOfDisplayWeek). So the week keyed 2026-08-15 runs
  // through Friday 2026-08-21, and both crossed-out days sit inside it.
  group('a met weekly quota excuses days the sync never reached', () {
    test('THE BUG: Thursday 20th, quota already met, no stored entry', () {
      final p = _perla();
      expect(
        p.scheduledCountFor('2026-08-20'),
        0,
        reason: 'the week beginning 2026-08-15 is in quotaOkWeeks, so nothing '
            'was owed on the 20th',
      );
      expect(p.isRestDay('2026-08-20'), isTrue);
      expect(
        p.creditFor('2026-08-20'),
        1.0,
        reason: 'an excused day is finished, not missed',
      );
    });

    test('Friday 21st, the last day of the same met week', () {
      final p = _perla();
      expect(p.isRestDay('2026-08-21'), isTrue);
      expect(p.creditFor('2026-08-21'), 1.0);
    });

    test('a day she actually trained is never relabelled a rest', () {
      final p = _perla();
      // 2026-08-19 sits in the same met week but has a completion, so it must
      // keep a real scheduled count: it is a session, not a day off, and
      // isRestDay drives the words the calendar puts next to the square.
      expect(p.scheduledCountFor('2026-08-19'), 1);
      expect(p.isRestDay('2026-08-19'), isFalse);
      expect(p.creditFor('2026-08-19'), 1.0);
    });

    test('a partial day is not swallowed as a rest either', () {
      final p = _perla(
        dailyDoneCount: const {'2026-08-15': 1, '2026-08-17': 1},
        dailyPartialCount: const {'2026-08-20': 1},
      );
      expect(p.scheduledCountFor('2026-08-20'), 1);
      expect(p.isRestDay('2026-08-20'), isFalse);
    });
  });

  group('the fallback still fails safe', () {
    test('a week that never met its target keeps crossing out its misses', () {
      // The week beginning 2026-08-08 is deliberately absent from
      // quotaOkWeeks - she managed only three sessions that week - so an
      // unrecorded day inside it is still a genuine miss.
      final p = _perla(dailyScheduledCount: const {});
      expect(p.scheduledCountFor('2026-08-14'), 1);
      expect(p.isRestDay('2026-08-14'), isFalse);
      expect(p.creditFor('2026-08-14'), 0.0);
    });

    test('an explicit stored entry always wins over the inference', () {
      // Even inside a met week: the sync knows about things this inference
      // cannot see, including leader-withdrawn slots.
      final p = _perla(dailyScheduledCount: const {'2026-08-20': 1});
      expect(p.scheduledCountFor('2026-08-20'), 1);
      expect(p.isRestDay('2026-08-20'), isFalse);
    });

    test('a daily-only room is untouched: quotaOkWeeks is empty there', () {
      // The quota grader only ever records a week when it saw a weekly habit,
      // so a purely daily room can never take the new branch and every
      // unrecorded day stays a miss exactly as before.
      final p = _perla(quotaOkWeeks: const [], dailyScheduledCount: const {});
      expect(p.scheduledCountFor('2026-08-20'), 1);
      expect(p.isRestDay('2026-08-20'), isFalse);
    });

    test('an unparseable dateKey falls back rather than throwing', () {
      final p = _perla();
      expect(p.scheduledCountFor('not-a-date'), 1);
    });
  });

  // Caught by an adversarial review of the fix above, before it shipped.
  //
  // quotaOkWeeks and scheduledCountFor have different scopes. The grader that
  // writes quotaOkWeeks skips every non-weekly habit before deciding a week
  // held, so the set attests to the quota habits and nothing else. Returning 0
  // for the whole day therefore excuses any DAILY habit sharing that plan, on
  // the strength of an attestation that never looked at it.
  //
  // Measured on the un-gated version: 85.7% where the honest answer is 57.1%,
  // on a ranked leaderboard.
  group('a mixed plan never rides the weekly habit\'s attestation', () {
    test('a daily sibling still owes its day inside a met week', () {
      final p = _perla(
        linkedHabitIds: const [_kHabit, _kDailyHabit],
        habitRules: const {
          _kHabit: [_weeklyRule],
          _kDailyHabit: [_dailyRule],
        },
        dailyScheduledCount: const {},
      );
      expect(
        p.scheduledCountFor('2026-08-20'),
        2,
        reason: 'the daily habit was owed on the 20th and nobody graded it',
      );
      expect(p.isRestDay('2026-08-20'), isFalse);
      expect(p.creditFor('2026-08-20'), 0.0);
    });

    test('an all-weekly plan of two habits is still excused', () {
      // The gate asks "is there anything here that is NOT on a quota", not
      // "is there exactly one habit". Two quota habits are still fully
      // covered by the attestation.
      final p = _perla(
        linkedHabitIds: const [_kHabit, _kDailyHabit],
        habitRules: const {
          _kHabit: [_weeklyRule],
          _kDailyHabit: [_weeklyRule],
        },
        dailyScheduledCount: const {},
      );
      expect(p.scheduledCountFor('2026-08-20'), 0);
      expect(p.isRestDay('2026-08-20'), isTrue);
    });

    test('an unproven cadence fails safe rather than guessing weekly', () {
      // habitRules empty: this device has never recorded what cadence the
      // habit was on, so the inference must not run at all.
      final p = _perla(habitRules: const {}, dailyScheduledCount: const {});
      expect(p.scheduledCountFor('2026-08-20'), 1);
      expect(p.isRestDay('2026-08-20'), isFalse);
    });
  });

  // Also from the adversarial review. quotaOkWeeks is graded from raw square
  // history with no anti-backdating cap, so colouring in two of last week's
  // squares today can make that week read as met. Unbounded, the inference
  // would then excuse every blank day in it and pay out on the ranked
  // percentage: measured at +28.6 points. wasObservedOn keeps it to days no
  // sync ever watched, which is the only window it was ever meant for.
  group('back-dating cannot buy an excused day', () {
    test('a day the sync already watched keeps its observed value', () {
      // Same met week, but the watermark now covers the 20th, so the room WAS
      // looking that day and recorded nothing done. That is a real miss.
      final p = _perla(
        dailyScheduledCount: const {},
        lastSyncedDay: '2026-08-22',
      );
      expect(p.wasObservedOn('2026-08-20'), isTrue);
      expect(p.scheduledCountFor('2026-08-20'), 1);
      expect(p.isRestDay('2026-08-20'), isFalse);
      expect(p.creditFor('2026-08-20'), 0.0);
    });

    test('the day the watermark lands on is observed, not inferred', () {
      // Boundary: wasObservedOn is inclusive, so lastSyncedDay itself counts
      // as watched and must not be excused.
      final p = _perla(
        dailyScheduledCount: const {},
        dailyDoneCount: const {'2026-08-15': 1, '2026-08-17': 1},
        lastSyncedDay: '2026-08-20',
      );
      expect(p.scheduledCountFor('2026-08-20'), 1);
      expect(p.isRestDay('2026-08-20'), isFalse);
    });
  });

  group('the strip and the streak now agree', () {
    // The whole point. Before the fix isRestDay said "missed" for the 20th
    // while the streak said "kept", from the same document.
    test('both surfaces treat the 20th as earned', () {
      final p = _perla();
      expect(p.isRestDay('2026-08-20'), isTrue);
      expect(
        p.quotaOkWeeks.contains('2026-08-15'),
        isTrue,
        reason: 'the source _keepsStreak reads, and now scheduledCountFor too',
      );
    });
  });
}
