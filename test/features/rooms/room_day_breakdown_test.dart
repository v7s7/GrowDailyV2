import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/rooms/models/room_day_breakdown.dart';
import 'package:grow_daily_v2/features/rooms/models/room_model.dart';

/// What a tapped day is allowed to say about itself.
///
/// The day card shows a score out of what was asked and, when it can, names
/// which habit did what. The room stores COUNTS per day, never which habit
/// each count was, so the naming is only honest on a day the counts pin
/// down. These tests are mostly about the days where they do not.
const _day = '2026-09-08';

RoomModel _room({
  List<String> plan = const ['تمرين'],
  RoomHabitMode mode = RoomHabitMode.shared,
  List<DateTime?> removedAt = const [],
}) =>
    RoomModel(
      code: 'YW68B9',
      name: 'NO STOOOOP',
      createdBy: 'leader-uid',
      createdByName: 'Leader',
      createdAt: DateTime(2026, 8, 21),
      habitMode: mode,
      duration: RoomDuration.fixed,
      startDate: DateTime(2026, 8, 21),
      endDate: DateTime(2026, 12, 31),
      sharedHabits: [
        for (var i = 0; i < plan.length; i++)
          RoomHabitTemplate(
            name: plan[i],
            category: HabitCategory.custom,
            frequencyType: HabitFrequencyType.daily,
            frequencyTarget: 1,
            removedAt: i < removedAt.length ? removedAt[i] : null,
          ),
      ],
    );

RoomParticipant _p({
  List<String> linked = const ['h1'],
  Map<String, int> done = const {},
  Map<String, int> partial = const {},
  Map<String, int> rested = const {},
  Map<String, int> scheduled = const {},
  Map<int, String> declinedFrom = const {},
  Map<String, List<RoomHabitRule>> rules = const {},
}) =>
    RoomParticipant(
      uid: 'member-uid',
      displayName: 'Aziz',
      characterId: 'male_ghutra_blue',
      joinedAt: DateTime(2026, 8, 21),
      linkedHabitIds: linked,
      dailyDoneCount: done,
      dailyPartialCount: partial,
      dailyRestedCount: rested,
      dailyScheduledCount: scheduled,
      slotDeclinedFrom: declinedFrom,
      habitRules: rules,
      lastUpdated: DateTime(2026, 9, 10),
    );

void main() {
  group('the score', () {
    test('a done day is 1 of 1', () {
      final b = roomDayBreakdown(
        room: _room(),
        participant: _p(done: const {_day: 1}),
        dateKey: _day,
      );
      expect(b.credited, 1);
      expect(b.scheduled, 1);
      expect(b.missed, 0);
      expect(b.ratio, 1);
    });

    test('a missed day is 0 of 1', () {
      final b = roomDayBreakdown(
        room: _room(),
        participant: _p(),
        dateKey: _day,
      );
      expect(b.credited, 0);
      expect(b.scheduled, 1);
      expect(b.missed, 1);
      expect(b.ratio, 0);
    });

    test('a جزئي is half a habit, the same half it is worth everywhere', () {
      // Aziz's own case: "if the train give him 0.5, show that with the done
      // mark". SquareState.xpValue pays it 5 against 10, the Grid's day ratio
      // scores it 0.5, and creditFor counts it 0.5. So does this.
      final b = roomDayBreakdown(
        room: _room(),
        participant: _p(partial: const {_day: 1}),
        dateKey: _day,
      );
      expect(b.credited, 0.5);
      expect(b.ratio, 0.5);
    });

    test('a rest counts for the display and never for the score', () {
      // dailyRestedCount is a display field behind a wall: subtracting a
      // rested habit from the denominator would let somebody mark تخطّي on
      // what they skipped and settle a half day at full credit.
      final b = roomDayBreakdown(
        room: _room(plan: const ['تمرين', 'قراءة']),
        participant: _p(
          linked: const ['h1', 'h2'],
          done: const {_day: 1},
          rested: const {_day: 1},
        ),
        dateKey: _day,
      );
      expect(b.rested, 1);
      expect(b.scheduled, 2);
      expect(b.credited, 1);
    });

    test('a day that asked nothing is a whole day, as creditFor has it', () {
      final b = roomDayBreakdown(
        room: _room(),
        participant: _p(scheduled: const {_day: 0}),
        dateKey: _day,
      );
      expect(b.asksNothing, isTrue);
      expect(b.ratio, 1);
      expect(b.credited, 0);
    });
  });

  group('naming the habit', () {
    test('one habit takes the whole day', () {
      final b = roomDayBreakdown(
        room: _room(),
        participant: _p(done: const {_day: 1}),
        dateKey: _day,
      );
      expect(b.shareEach, 1);
      expect(b.slots.single.share, 1);
    });

    test('two habits split the day in half, which is the whole point', () {
      // Aziz's own words: "if room started with 2 habit the info should be
      // +0.5 +0.5, so we know that this is how it being counted".
      final b = roomDayBreakdown(
        room: _room(plan: const ['تمرين', 'قراءة']),
        participant: _p(linked: const ['h1', 'h2'], done: const {_day: 2}),
        dateKey: _day,
      );
      expect(b.shareEach, 0.5);
      expect(b.slots.map((e) => e.share), everyElement(0.5));
    });

    test('three habits take a third each', () {
      final b = roomDayBreakdown(
        room: _room(plan: const ['تمرين', 'قراءة', 'وتر']),
        participant: _p(
          linked: const ['h1', 'h2', 'h3'],
          done: const {_day: 3},
        ),
        dateKey: _day,
      );
      expect(b.shareEach, closeTo(1 / 3, 1e-9));
      expect(b.slots, hasLength(3));
    });

    test('a جزئي is worth half of its own share', () {
      final b = roomDayBreakdown(
        room: _room(plan: const ['تمرين', 'قراءة']),
        participant: _p(linked: const ['h1', 'h2'], partial: const {_day: 2}),
        dateKey: _day,
      );
      expect(b.slots.map((e) => e.share), everyElement(0.25));
      expect(b.credited, 1);
    });

    test('a missed habit adds nothing', () {
      final b = roomDayBreakdown(
        room: _room(),
        participant: _p(),
        dateKey: _day,
      );
      expect(b.slots.single.share, 0);
    });

    test('a one-habit plan can always be named', () {
      final b = roomDayBreakdown(
        room: _room(),
        participant: _p(done: const {_day: 1}),
        dateKey: _day,
      );
      expect(b.slots, hasLength(1));
      expect(b.slots.single.name, 'تمرين');
      expect(b.slots.single.outcome, RoomSlotOutcome.done);
    });

    test('an all-done day names every habit', () {
      final b = roomDayBreakdown(
        room: _room(plan: const ['تمرين', 'قراءة']),
        participant: _p(linked: const ['h1', 'h2'], done: const {_day: 2}),
        dateKey: _day,
      );
      expect(b.slots.map((e) => e.outcome),
          everyElement(RoomSlotOutcome.done));
      expect(b.slots.map((e) => e.name), ['تمرين', 'قراءة']);
    });

    test('an all-missed day names every habit', () {
      final b = roomDayBreakdown(
        room: _room(plan: const ['تمرين', 'قراءة']),
        participant: _p(linked: const ['h1', 'h2']),
        dateKey: _day,
      );
      expect(b.slots.map((e) => e.outcome),
          everyElement(RoomSlotOutcome.missed));
    });

    test('a MIXED day names nothing, because the room cannot tell', () {
      // Two habits asked for, one done. The document records the counts and
      // not which habit each was, so saying "تمرين 1/1, قراءة 0/1" would be
      // the room telling somebody they skipped a habit they may have done.
      final b = roomDayBreakdown(
        room: _room(plan: const ['تمرين', 'قراءة']),
        participant: _p(linked: const ['h1', 'h2'], done: const {_day: 1}),
        dateKey: _day,
      );
      expect(b.slots, isEmpty);
      expect(b.done, 1);
      expect(b.missed, 1);
    });

    test('a day where something was excused names nothing either', () {
      // Two live slots, one scheduled: which one was excused is exactly the
      // fact the document does not carry.
      final b = roomDayBreakdown(
        room: _room(plan: const ['تمرين', 'قراءة']),
        participant: _p(
          linked: const ['h1', 'h2'],
          done: const {_day: 1},
          scheduled: const {_day: 1},
        ),
        dateKey: _day,
      );
      expect(b.slots, isEmpty);
    });

    test('a day that asked nothing rests every habit by name', () {
      final b = roomDayBreakdown(
        room: _room(plan: const ['تمرين', 'قراءة']),
        participant: _p(
          linked: const ['h1', 'h2'],
          scheduled: const {_day: 0},
        ),
        dateKey: _day,
      );
      expect(b.slots.map((e) => e.outcome),
          everyElement(RoomSlotOutcome.rest));
    });

    test('a declined slot is named, because that one IS certain', () {
      final b = roomDayBreakdown(
        room: _room(plan: const ['تمرين', 'قراءة']),
        participant: _p(
          linked: const ['h1', kDeclinedSlot],
          declinedFrom: const {1: '2026-08-21'},
          done: const {_day: 1},
        ),
        dateKey: _day,
      );
      expect(b.slots, hasLength(2));
      expect(b.slots.first.outcome, RoomSlotOutcome.done);
      expect(b.slots.last.name, 'قراءة');
      expect(b.slots.last.outcome, RoomSlotOutcome.declined);
    });

    test('a slot the leader withdrew is left out entirely', () {
      // The stored scheduled count is what the sync writes once a slot is
      // withdrawn; the participant document alone cannot know about it,
      // because the withdrawal lives on the room (see scheduledCountFor).
      final b = roomDayBreakdown(
        room: _room(
          plan: const ['تمرين', 'قراءة'],
          removedAt: [null, DateTime(2026, 9, 1)],
        ),
        participant: _p(
          linked: const ['h1', 'h2'],
          done: const {_day: 1},
          scheduled: const {_day: 1},
        ),
        dateKey: _day,
      );
      expect(b.slots, hasLength(1));
      expect(b.slots.single.name, 'تمرين');
    });

    test('a habit added later is absent from the days before it joined', () {
      // Aziz, 2026-09-10: "some habit are being added after, not from day 1
      // ... only the counted days for it should show it". The join test is
      // slotOpenBy, the same one countedHabitCountOn uses for the
      // denominator, so the rows and the number they sum to cannot disagree.
      final b = roomDayBreakdown(
        room: _room(plan: const ['تمرين', 'قراءة']),
        participant: _p(
          linked: const ['h1', 'h2'],
          done: const {_day: 1},
          scheduled: const {_day: 1},
          rules: {
            'h1': [
              const RoomHabitRule(
                from: '2026-08-21',
                frequencyType: HabitFrequencyType.daily,
                frequencyTarget: 1,
              ),
            ],
            // Joined the plan the day AFTER the one under test.
            'h2': [
              const RoomHabitRule(
                from: '2026-09-09',
                frequencyType: HabitFrequencyType.daily,
                frequencyTarget: 1,
              ),
            ],
          },
        ),
        dateKey: _day,
      );
      expect(b.slots, hasLength(1));
      expect(b.slots.single.name, 'تمرين');
      // And with only one slot in the day, it takes the whole of it.
      expect(b.slots.single.share, 1);
    });

    test('a habit added later IS shown on the days it counted for', () {
      final b = roomDayBreakdown(
        room: _room(plan: const ['تمرين', 'قراءة']),
        participant: _p(
          linked: const ['h1', 'h2'],
          done: const {'2026-09-09': 2},
          rules: {
            'h1': [
              const RoomHabitRule(
                from: '2026-08-21',
                frequencyType: HabitFrequencyType.daily,
                frequencyTarget: 1,
              ),
            ],
            'h2': [
              const RoomHabitRule(
                from: '2026-09-09',
                frequencyType: HabitFrequencyType.daily,
                frequencyTarget: 1,
              ),
            ],
          },
        ),
        dateKey: '2026-09-09',
      );
      expect(b.slots.map((e) => e.name), ['تمرين', 'قراءة']);
      expect(b.slots.map((e) => e.share), everyElement(0.5));
    });

    test('a mixed day groups the same arithmetic instead of naming it', () {
      final b = roomDayBreakdown(
        room: _room(plan: const ['تمرين', 'قراءة', 'وتر']),
        participant: _p(
          linked: const ['h1', 'h2', 'h3'],
          done: const {_day: 2},
        ),
        dateKey: _day,
      );
      expect(b.slots, isEmpty);
      expect(b.groups, hasLength(2));
      final doneGroup =
          b.groups.firstWhere((g) => g.outcome == RoomSlotOutcome.done);
      expect(doneGroup.count, 2);
      expect(doneGroup.share, closeTo(2 / 3, 1e-9));
      final missedGroup =
          b.groups.firstWhere((g) => g.outcome == RoomSlotOutcome.missed);
      expect(missedGroup.count, 1);
      expect(missedGroup.share, 0);
      // The groups sum to the day, which is the claim the card makes.
      expect(
        b.groups.fold<double>(0, (a, g) => a + g.share),
        closeTo(b.ratio, 1e-9),
      );
    });

    test('an attributable day carries no groups, and vice versa', () {
      final named = roomDayBreakdown(
        room: _room(),
        participant: _p(done: const {_day: 1}),
        dateKey: _day,
      );
      expect(named.slots, isNotEmpty);
      expect(named.groups, isEmpty);
    });

    test("an 'own'-mode room has no names to give", () {
      // Every member picks their own habits there and the document carries
      // ids, not names.
      final b = roomDayBreakdown(
        room: _room(mode: RoomHabitMode.own),
        participant: _p(done: const {_day: 1}),
        dateKey: _day,
      );
      expect(b.slots, isEmpty);
      expect(b.credited, 1);
    });
  });

  /// The printed numbers have to add up to the total printed beside them.
  ///
  /// Two thirds and a sixth print as 0.67 and 0.17, which sum to 0.84 while
  /// the day says 83%. That was on screen in the first build of this card,
  /// and arithmetic that does not add up defeats the reason for showing it.
  group('roundedShares', () {
    double sum(List<double> xs) => xs.fold(0, (a, b) => a + b);

    test('two thirds and a sixth are printed so they sum to the day', () {
      final out = roundedShares([2 / 3, 1 / 6]);
      expect(out, [0.67, 0.16]);
      expect(sum(out), closeTo(0.83, 1e-9));
    });

    test('three thirds print as a whole day, not 0.99', () {
      final out = roundedShares([1 / 3, 1 / 3, 1 / 3]);
      expect(sum(out), closeTo(1.0, 1e-9));
    });

    test('halves need no help', () {
      expect(roundedShares([0.5, 0.5]), [0.5, 0.5]);
    });

    test('a zero share is never rounded up into a contribution', () {
      // "This habit added nothing" is a fact, not a rounding choice.
      final out = roundedShares([1 / 3, 1 / 3, 0]);
      expect(out.last, 0);
      expect(sum(out), closeTo(2 / 3, 0.005));
    });

    test('an empty day rounds to nothing', () {
      expect(roundedShares(const []), isEmpty);
    });

    test('the sum property holds across every plan size', () {
      for (var n = 1; n <= 8; n++) {
        final shares = List<double>.filled(n, 1 / n);
        final out = roundedShares(shares);
        expect(sum(out), closeTo(1.0, 1e-9), reason: '\$n habits');
      }
    });
  });
}
