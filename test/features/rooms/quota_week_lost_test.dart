import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/rooms/models/room_model.dart';

/// When a quota week stops being rescuable.
///
/// A 4x-a-week habit buys three blank days out of seven. The fourth blank
/// does not put the week behind, it ENDS it: three sessions is the most that
/// can still be reached, so the week will grade as a miss whatever happens
/// on the days that are left. The strip used to sit on that answer until
/// Saturday, which reads as "nothing has happened yet" for days that were
/// already lost.
///
/// Every case here is pinned to a room that ENDED on Friday 2026-08-28, so
/// `lastCountedDay` is that date rather than whatever day the suite runs on.
/// The week under test is Saturday 2026-08-22 to Friday 2026-08-28.
const _weekStart = '2026-08-22';
const _mid = '2026-08-25';
const _weekEnd = '2026-08-28';

RoomModel _room({DateTime? endDate}) => RoomModel(
      code: 'A8GEL7',
      name: 'الإلتزام',
      createdBy: 'leader-uid',
      createdByName: 'Leader',
      createdAt: DateTime(2026, 8, 1),
      habitMode: RoomHabitMode.shared,
      duration: RoomDuration.fixed,
      startDate: DateTime(2026, 8, 1),
      // Runs well past the week under test, so `now` alone decides how much
      // of that week is still ahead of the person.
      endDate: endDate ?? DateTime(2026, 12, 31),
    );

/// Friday of the week under test, 12:00 — the last day, with only itself
/// left to spend.
final _friday = DateTime(2026, 8, 28, 12);

/// Wednesday of the week under test, 12:00 — three days still to come.
final _wednesday = DateTime(2026, 8, 26, 12);

RoomParticipant _p({
  Map<String, int> done = const {},
  List<String> quotaOkWeeks = const [],
  List<String> standDownDays = const [],
  int target = 4,
  HabitFrequencyType type = HabitFrequencyType.weekly,
  bool withRule = true,
  List<String> linked = const ['h1'],
  Map<String, List<RoomHabitRule>> rules = const {},
}) =>
    RoomParticipant(
      uid: 'member-uid',
      displayName: 'Aziz',
      characterId: 'male_ghutra_blue',
      joinedAt: DateTime(2026, 8, 1),
      linkedHabitIds: linked,
      dailyDoneCount: done,
      quotaOkWeeks: quotaOkWeeks,
      standDownDays: standDownDays,
      habitRules: rules.isNotEmpty
          ? rules
          : (withRule
              ? {
                  'h1': [
                    RoomHabitRule(
                      from: '2026-08-01',
                      frequencyType: type,
                      frequencyTarget: target,
                    ),
                  ],
                }
              : const {}),
      lastUpdated: DateTime(2026, 8, 28),
    );

void main() {
  group('quotaWeekIsLost', () {
    test('four blanks in a seven-day week end a 4x target', () {
      // Friday. Done on the 22nd and 23rd, so the 24th, 25th, 26th and 27th
      // are four blank days already spent and only Friday itself is left:
      // three is the most this week can still reach.
      final p = _p(done: const {'2026-08-22': 1, '2026-08-23': 1});
      expect(p.quotaWeekIsLost(_mid, _room(), now: _friday), isTrue);
    });

    test('three blanks do not: the target is still exactly reachable', () {
      final p = _p(done: const {
        '2026-08-22': 1,
        '2026-08-23': 1,
        '2026-08-24': 1,
      });
      expect(p.quotaWeekIsLost(_mid, _room(), now: _friday), isFalse);
    });

    test('mid-week, days still to come are days they can still spend', () {
      // Wednesday with two done. Wednesday, Thursday and Friday are all
      // still in hand, so two of the remaining three finish the week.
      final p = _p(done: const {'2026-08-22': 1, '2026-08-23': 1});
      expect(p.quotaWeekIsLost(_mid, _room(), now: _wednesday), isFalse);
    });

    test('a day the plan stood down is not a day they can spend', () {
      // Same three done days, but Friday is stood down, so there is no
      // fourth session available anywhere in the week.
      final p = _p(
        done: const {'2026-08-22': 1, '2026-08-23': 1, '2026-08-24': 1},
        standDownDays: const [_weekEnd],
      );
      expect(p.quotaWeekIsLost(_mid, _room(), now: _friday), isTrue);
    });

    test('a week the phone already banked is never lost', () {
      final p = _p(
        done: const {'2026-08-22': 1},
        quotaOkWeeks: const [_weekStart],
      );
      expect(p.quotaWeekIsLost(_mid, _room(), now: _friday), isFalse);
    });

    test('days past the room\'s own end are not days they can spend', () {
      // The room stops on Tuesday, so Wednesday to Friday cannot hold a
      // session even though the week runs on.
      final p = _p(done: const {'2026-08-22': 1});
      expect(
        p.quotaWeekIsLost(
          _mid,
          _room(endDate: DateTime(2026, 8, 25)),
          now: _wednesday,
        ),
        isTrue,
      );
    });

    test('yesterday still counts while the flex window is open', () {
      // 08:00 on Saturday. Friday is over on the calendar but stays markable
      // until kDayCutoffHour, and a session marked in that tail is one the
      // Grid pays and the room counts. Three done plus that one is four.
      final p = _p(done: const {
        '2026-08-22': 1,
        '2026-08-23': 1,
        '2026-08-24': 1,
      });
      expect(
        p.quotaWeekIsLost(_mid, _room(), now: DateTime(2026, 8, 29, 8)),
        isFalse,
      );
    });

    test('and stops counting once the flex window has passed', () {
      // 11:00 on Saturday, past the cutoff. Friday can no longer be marked,
      // so the fourth session has nowhere left to happen.
      final p = _p(done: const {
        '2026-08-22': 1,
        '2026-08-23': 1,
        '2026-08-24': 1,
      });
      expect(
        p.quotaWeekIsLost(_mid, _room(), now: DateTime(2026, 8, 29, 11)),
        isTrue,
      );
    });

    test('a DAILY habit is never graded by this arithmetic', () {
      final p = _p(done: const {}, type: HabitFrequencyType.daily);
      expect(p.quotaWeekIsLost(_mid, _room(), now: _friday), isFalse);
    });

    test('an unrecorded rule answers no rather than guessing', () {
      final p = _p(done: const {}, withRule: false);
      expect(p.quotaWeekIsLost(_mid, _room(), now: _friday), isFalse);
    });

    test('a mixed plan is left alone: one daily habit disables the whole check',
        () {
      final p = _p(
        linked: const ['h1', 'h2'],
        done: const {},
        rules: {
          'h1': [
            const RoomHabitRule(
              from: '2026-08-01',
              frequencyType: HabitFrequencyType.weekly,
              frequencyTarget: 4,
            ),
          ],
          'h2': [
            const RoomHabitRule(
              from: '2026-08-01',
              frequencyType: HabitFrequencyType.daily,
              frequencyTarget: 1,
            ),
          ],
        },
      );
      expect(p.quotaWeekIsLost(_mid, _room(), now: _friday), isFalse);
    });

    test('a zero target cannot be missed', () {
      final p = _p(done: const {}, target: 0);
      expect(p.quotaWeekIsLost(_mid, _room(), now: _friday), isFalse);
    });

    test('an empty week with a 7x target is lost the moment a day is blank',
        () {
      // Seven days, seven needed, and by Friday four have gone blank: the
      // arithmetic does not depend on the size of the target.
      final p = _p(done: const {}, target: 7);
      expect(p.quotaWeekIsLost(_mid, _room(), now: _friday), isTrue);
    });
  });
}
