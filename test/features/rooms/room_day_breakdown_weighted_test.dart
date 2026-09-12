// The tapped-day card under the weekly-share ruling.
//
// Aziz ruled on 2026-09-12 that a flexible weekly quota should carry its
// SHARE of a closed week (target/D per day) rather than counting as a whole
// habit on the days it is answerable for and vanishing from the ones it
// excuses. The grader writes that as a weighted pair beside the counts
// (RoomParticipant.dailyScheduledWeight), and the percentage is ranked on it.
//
// So the card has to divide by the same thing the board does. If it kept
// dividing by the whole-habit count it would print «3 من 3، 100%» for a day
// the leaderboard scores 89%, and the receipt would be arguing with the
// board it explains.
//
// Every other breakdown test builds a participant with no weights, where the
// weighted path is never entered and nothing here can fail. These are the
// ones that enter it, and the worked example is Aziz's own 11 September: all
// three habits done, in a week that banked 2 of its 4 تمرين sessions.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/rooms/models/room_day_breakdown.dart';
import 'package:grow_daily_v2/features/rooms/models/room_model.dart';

const _d = RoomHabitMark.done;
const _r = RoomHabitMark.rest;

/// ELQVF8's plan: تمرين 4x a week, صلاة الوتر and قراءة القرآن daily.
RoomModel _room() => RoomModel(
      code: 'ELQVF8',
      name: 'Being Better',
      createdBy: 'aziz',
      createdByName: 'Aziz',
      createdAt: DateTime(2026, 9),
      habitMode: RoomHabitMode.shared,
      sharedHabits: const [
        RoomHabitTemplate(
          name: 'تمرين',
          category: HabitCategory.health,
          frequencyType: HabitFrequencyType.weekly,
          frequencyTarget: 4,
        ),
        RoomHabitTemplate(
          name: 'صلاة الوتر',
          category: HabitCategory.faith,
          frequencyType: HabitFrequencyType.daily,
          frequencyTarget: 1,
        ),
        RoomHabitTemplate(
          name: 'قراءة القرآن',
          category: HabitCategory.faith,
          frequencyType: HabitFrequencyType.daily,
          frequencyTarget: 1,
        ),
      ],
      duration: RoomDuration.fixed,
      startDate: DateTime(2026, 9),
      endDate: DateTime(2026, 9, 30),
    );

RoomParticipant _member({
  required Map<String, int> done,
  required Map<String, int> scheduled,
  required Map<String, Map<String, RoomHabitMark>> marks,
  Map<String, double> demand = const {},
  Map<String, double> credit = const {},
}) =>
    RoomParticipant(
      uid: 'member',
      displayName: 'Aziz',
      characterId: 'none',
      joinedAt: DateTime(2026, 9),
      linkedHabitIds: const ['t', 'w', 'q'],
      dailyDoneCount: done,
      dailyScheduledCount: scheduled,
      dailyHabitMarks: marks,
      dailyScheduledWeight: demand,
      dailyDoneWeight: credit,
      habitRules: {
        't': [
          const RoomHabitRule(
            from: '2026-09-01',
            frequencyType: HabitFrequencyType.weekly,
            frequencyTarget: 4,
          ),
        ],
        'w': [
          const RoomHabitRule(
            from: '2026-09-01',
            frequencyType: HabitFrequencyType.daily,
            frequencyTarget: 1,
          ),
        ],
        'q': [
          const RoomHabitRule(
            from: '2026-09-01',
            frequencyType: HabitFrequencyType.daily,
            frequencyTarget: 1,
          ),
        ],
      },
      lastUpdated: DateTime(2026, 9, 12),
    );

void main() {
  // Two daily habits at a whole habit each, plus تمرين carrying 4/7 of a
  // closed week: 18/7 of demand. Two sessions banked of four: 16/7 of credit.
  const demand = 18 / 7;
  const twoOfFour = 16 / 7;
  const fourOfFour = 18 / 7;

  group('a day that did everything, in a week that did not', () {
    RoomDayBreakdown build() => roomDayBreakdown(
          room: _room(),
          participant: _member(
            done: const {'2026-09-11': 3},
            scheduled: const {'2026-09-11': 3},
            marks: const {
              '2026-09-11': {'t': _d, 'w': _d, 'q': _d},
            },
            demand: const {'2026-09-11': demand},
            credit: const {'2026-09-11': twoOfFour},
          ),
          dateKey: '2026-09-11',
        );

    test('the percentage divides by the weighted demand, not the count', () {
      // 16/7 over 18/7 is 8/9. Dividing by the count instead would say 100%
      // for a day the board scores 89%.
      expect(build().ratio, closeTo(8 / 9, 1e-12));
    });

    test('«3 من 3» still counts whole habits', () {
      // Three habits were done. Printing the weighted 2.29 against 3 would
      // describe nothing the person actually did.
      final b = build();
      expect(b.plainCredited, 3);
      expect(b.scheduled, 3);
    });

    test('the quota row takes the residual, the dailies take a whole habit',
        () {
      final b = build();
      expect(_shares(b), {
        'صلاة الوتر': closeTo(7 / 18, 1e-12),
        'قراءة القرآن': closeTo(7 / 18, 1e-12),
        // 2/7 of credit out of 18/7 of demand: a ninth of the day, not a
        // third, because that week banked half its sessions.
        'تمرين': closeTo(1 / 9, 1e-12),
      });
    });

    test('the rows sum to exactly the percentage beside them', () {
      final b = build();
      final total = b.slots.fold<double>(0, (a, s) => a + s.share);
      expect(total, closeTo(b.ratio, 1e-12));
    });

    test('and they still sum once rounded for printing', () {
      // What the card actually shows: 0.11 + 0.39 + 0.39 = 0.89, beside 89%.
      // Plan order, so تمرين leads and carries the smallest share of the
      // three, which is the whole point being made on screen.
      final b = build();
      final printed = roundedShares([for (final s in b.slots) s.share]);
      expect(printed, [0.11, 0.39, 0.39]);
      expect(
        printed.fold<double>(0, (a, v) => a + v),
        closeTo((b.ratio * 100).roundToDouble() / 100, 1e-12),
      );
    });

    test('no groups on a weighted day', () {
      // Groups cannot tell the quota from the rest, so an even split there
      // would print rows that do not add up to the total.
      expect(build().groups, isEmpty);
    });
  });

  group('a met quota still reads as a whole day', () {
    test('the excused day is «راحة» and the day is still 100%', () {
      // The property the ruling had to preserve. تمرين rested on this day,
      // yet the week banked all four sessions, so its 4/7 of demand is fully
      // earned and the day is whole.
      final b = roomDayBreakdown(
        room: _room(),
        participant: _member(
          done: const {'2026-09-10': 2},
          scheduled: const {'2026-09-10': 2},
          marks: const {
            '2026-09-10': {'t': _r, 'w': _d, 'q': _d},
          },
          demand: const {'2026-09-10': demand},
          credit: const {'2026-09-10': fourOfFour},
        ),
        dateKey: '2026-09-10',
      );
      expect(b.ratio, 1);
      expect(_shares(b), {
        'صلاة الوتر': closeTo(7 / 18, 1e-12),
        'قراءة القرآن': closeTo(7 / 18, 1e-12),
        // A rest row worth something: the week's quota is carried by every
        // day of it, including the ones it excused.
        'تمرين': closeTo(2 / 9, 1e-12),
      });
      expect(
        b.slots.fold<double>(0, (a, s) => a + s.share),
        closeTo(1, 1e-12),
      );
    });
  });

  group('a day with no weights is untouched', () {
    test('demand falls back to the count, and the split is even', () {
      // Every other test in this suite is this case, and it must keep
      // reading exactly as it did before the ruling.
      final b = roomDayBreakdown(
        room: _room(),
        participant: _member(
          done: const {'2026-09-02': 3},
          scheduled: const {'2026-09-02': 3},
          marks: const {
            '2026-09-02': {'t': _d, 'w': _d, 'q': _d},
          },
        ),
        dateKey: '2026-09-02',
      );
      expect(b.demand, 3);
      expect(b.ratio, 1);
      expect(b.shareEach, closeTo(1 / 3, 1e-12));
      expect(
        [for (final s in b.slots) s.share],
        everyElement(closeTo(1 / 3, 1e-12)),
      );
    });
  });
}

/// The rows as name -> share, so an expectation can name the habit it is
/// about. Returns the VALUES, not matchers built from them: a map of
/// `closeTo(s.share)` would compare every share against itself and pass
/// whatever the card did.
Map<String, double> _shares(RoomDayBreakdown b) => {
      for (final s in b.slots) s.name: s.share,
    };
