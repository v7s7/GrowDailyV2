// The tapped-day card naming every habit, every day, from the marks the sync
// writes beside the counts (RoomParticipant.dailyHabitMarks).
//
// Built from room ELQVF8 «Being Better» as it stood on 2026-09-11: تمرين 4x a
// week, صلاة الوتر and قراءة القرآن daily, the Quran slot added at 00:48 on
// the 9th. Before the marks, Hoor's 10th read «2 من عادتين» on a three-habit
// plan with no names at all, and Aziz's 9th read «2 من 3 عادات» with no word
// on which habit was missed. Aziz, 2026-09-11: "lets make it mention all the
// time".
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/rooms/models/room_day_breakdown.dart';
import 'package:grow_daily_v2/features/rooms/models/room_model.dart';

const _d = RoomHabitMark.done;
const _p = RoomHabitMark.partial;
const _s = RoomHabitMark.skipped;
const _m = RoomHabitMark.missed;
const _r = RoomHabitMark.rest;

RoomModel _room({RoomHabitMode mode = RoomHabitMode.shared}) => RoomModel(
      code: 'ELQVF8',
      name: 'Being Better',
      createdBy: 'aziz',
      createdByName: 'Aziz',
      createdAt: DateTime(2026, 9),
      habitMode: mode,
      sharedHabits: mode == RoomHabitMode.shared
          ? [
              const RoomHabitTemplate(
                name: 'تمرين',
                category: HabitCategory.health,
                frequencyType: HabitFrequencyType.weekly,
                frequencyTarget: 4,
              ),
              const RoomHabitTemplate(
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
                addedAt: DateTime(2026, 9, 9, 0, 48),
              ),
            ]
          : const [],
      duration: RoomDuration.fixed,
      startDate: DateTime(2026, 9),
      endDate: DateTime(2026, 9, 30),
    );

RoomHabitRule _rule(String from, {bool weekly = false}) => RoomHabitRule(
      from: from,
      frequencyType:
          weekly ? HabitFrequencyType.weekly : HabitFrequencyType.daily,
      frequencyTarget: weekly ? 4 : 1,
    );

RoomParticipant _member({
  String quranFrom = '2026-09-09',
  List<String> linked = const ['t', 'w', 'q'],
  Map<String, int> done = const {},
  Map<String, int> partial = const {},
  Map<String, int> rested = const {},
  Map<String, int> scheduled = const {},
  Map<int, String> declinedFrom = const {},
  Map<String, Map<String, RoomHabitMark>> marks = const {},
  List<String> quotaOk = const [],
}) =>
    RoomParticipant(
      uid: 'member',
      displayName: 'Hoor',
      characterId: 'none',
      joinedAt: DateTime(2026, 9),
      linkedHabitIds: linked,
      dailyDoneCount: done,
      dailyPartialCount: partial,
      dailyRestedCount: rested,
      dailyScheduledCount: scheduled,
      slotDeclinedFrom: declinedFrom,
      dailyHabitMarks: marks,
      quotaOkWeeks: quotaOk,
      habitRules: {
        't': [_rule('2026-09-01', weekly: true)],
        'w': [_rule('2026-09-01')],
        'q': [_rule(quranFrom)],
      },
      lastUpdated: DateTime(2026, 9, 11),
    );

List<(String, RoomSlotOutcome)> _rows(RoomDayBreakdown b) =>
    [for (final s in b.slots) (s.name, s.outcome)];

void main() {
  test('a quota rest is named as a rest, and the dailies take half each', () {
    // Hoor, Thursday 10 Sep. Her fourth تمرين of the week was on the 8th, so
    // the room stored 2 asked, and the old card said «2 من عادتين» with
    // nothing about the third habit on her plan.
    final b = roomDayBreakdown(
      room: _room(),
      participant: _member(
        quranFrom: '2026-09-08',
        done: {'2026-09-10': 2},
        scheduled: {'2026-09-10': 2},
        marks: {
          '2026-09-10': {'t': _r, 'w': _d, 'q': _d},
        },
      ),
      dateKey: '2026-09-10',
    );
    expect(_rows(b), [
      ('تمرين', RoomSlotOutcome.rest),
      ('صلاة الوتر', RoomSlotOutcome.done),
      ('قراءة القرآن', RoomSlotOutcome.done),
    ]);
    expect([for (final s in b.slots) s.share], [0, 0.5, 0.5]);
    expect(b.groups, isEmpty);
    expect(b.ratio, 1);
  });

  test('a quota rest is named even when the device wrote no marks', () {
    // The same Thursday for a member whose phone has never written
    // dailyHabitMarks. Hoor's own document has none of them, so this, not
    // the test above, is what her card actually renders.
    //
    // The counts alone are enough. Three slots were live, the day asked for
    // two, and only a FLEXIBLE quota can be excused without a weekday rule
    // saying so, so the excused slot is necessarily تمرين. A named-weekday
    // habit excused by its own weekday would leave more live slots than the
    // denominator accounts for, and this must not fire then.
    //
    // Aziz, 2026-09-12, looking at her 10th: "It shows 2 out of 2 and we are
    // in three habit room, so why no details like other days?"
    final b = roomDayBreakdown(
      room: _room(),
      participant: _member(
        quranFrom: '2026-09-08',
        done: {'2026-09-10': 2},
        scheduled: {'2026-09-10': 2},
      ),
      dateKey: '2026-09-10',
    );
    expect(_rows(b), [
      ('تمرين', RoomSlotOutcome.rest),
      ('صلاة الوتر', RoomSlotOutcome.done),
      ('قراءة القرآن', RoomSlotOutcome.done),
    ]);
    expect([for (final s in b.slots) s.share], [0, 0.5, 0.5]);
    expect(b.groups, isEmpty);
    expect(b.ratio, 1);
  });

  test('a mixed day with no marks still refuses to name', () {
    // Her Friday 11 September: 2 done of 3, no marks. quotaOkWeeks can prove
    // تمرين was one of them, but the document cannot say whether the second
    // was صلاة الوتر or قراءة القرآن, so the card groups rather than guesses.
    // The boundary matters as much as the inference above: one more step of
    // "reasoning" here would be the room telling somebody they skipped a
    // habit they had done.
    final b = roomDayBreakdown(
      room: _room(),
      participant: _member(
        quranFrom: '2026-09-08',
        done: {'2026-09-11': 2},
      ),
      dateKey: '2026-09-11',
    );
    expect(b.slots, isEmpty);
    expect(b.groups, isNotEmpty);
    // Refusing to ATTRIBUTE is not the same as refusing to name. All three
    // habits still reach the screen, under the rows rather than on them.
    expect(b.groupNames, ['تمرين', 'صلاة الوتر', 'قراءة القرآن']);
  });

  test('a banked quota week names the habit it proves was done', () {
    // Her Friday 11 September again, with the one piece of evidence the test
    // above withholds: quotaOkWeeks holding that week. A met quota leaves
    // only the days actually DONE in the denominator, so تمرين being counted
    // on the 11th proves she trained that day. The card may say so.
    //
    // 11 Sep 2026 is a Friday, and the Saturday-start week containing it
    // begins 2026-09-05, which is the key her own document banks.
    //
    // The other two stay a pair. Two habits were done, one of them تمرين, so
    // exactly one of صلاة الوتر and قراءة القرآن was missed and nothing
    // stored says which. Naming either would be a guess dressed as a fact.
    //
    // Aziz, 2026-09-12: "if u checked the data it should show that she
    // trained yesterday so how does it count".
    final b = roomDayBreakdown(
      room: _room(),
      participant: _member(
        quranFrom: '2026-09-08',
        done: {'2026-09-11': 2},
        quotaOk: const ['2026-09-05'],
      ),
      dateKey: '2026-09-11',
    );
    expect(_rows(b), [('تمرين', RoomSlotOutcome.done)]);
    expect(b.slots.single.share, closeTo(1 / 3, 1e-12));
    expect(
      [for (final g in b.groups) (g.outcome, g.count)],
      [
        (RoomSlotOutcome.done, 1),
        (RoomSlotOutcome.missed, 1),
      ],
    );
    expect(b.groups.first.share, closeTo(1 / 3, 1e-12));
    expect(b.groups.last.share, 0);
    // The named row plus the groups still sum to the day's own ratio, which
    // is what makes the card's arithmetic checkable on screen.
    final total = b.slots.fold<double>(0, (a, s) => a + s.share) +
        b.groups.fold<double>(0, (a, g) => a + g.share);
    expect(total, closeTo(b.ratio, 1e-12));
    expect(b.ratio, closeTo(2 / 3, 1e-12));
    // The pair the groups stand for, named. تمرين is NOT among them: it has
    // a row of its own above, and repeating it here would read as a third
    // habit the day is unsure about.
    expect(b.groupNames, ['صلاة الوتر', 'قراءة القرآن']);
  });

  test('a two-habit day names both when it cannot say which was which', () {
    // The shape نور's «اذكار الصباح» card shows: two daily habits, one done
    // and one not, on a phone that has never written a mark. Here it is the
    // Quran slot not having joined yet that leaves two live slots.
    //
    // Aziz, 2026-09-12, on exactly this card: "why the friday now not showing
    // all 3 habits? what is hard about that".
    final b = roomDayBreakdown(
      room: _room(),
      participant: _member(
        quranFrom: '2026-09-08',
        done: {'2026-09-05': 1},
      ),
      dateKey: '2026-09-05',
    );
    expect(b.slots, isEmpty);
    expect(
      [for (final g in b.groups) (g.outcome, g.count)],
      [
        (RoomSlotOutcome.done, 1),
        (RoomSlotOutcome.missed, 1),
      ],
    );
    expect(b.groupNames, ['تمرين', 'صلاة الوتر']);
  });

  test('a slot the day excused outside the rows is never listed', () {
    // Three live slots, a denominator of two, and a MIXED result, so no row
    // beneath can be pinned to a habit. تمرين is the slot the day excused,
    // and nothing in «أُنجز ١ / ما أُنجز ١» speaks for it: listing it there
    // would invite the reader to count it as the missed one.
    //
    // The guard that keeps the whole feature honest. Without it the pool is
    // just "every habit on the plan", which is a different and much weaker
    // claim than "the habits these rows are about".
    final b = roomDayBreakdown(
      room: _room(),
      participant: _member(
        quranFrom: '2026-09-08',
        done: {'2026-09-10': 1},
        scheduled: {'2026-09-10': 2},
      ),
      dateKey: '2026-09-10',
    );
    expect(b.slots, isEmpty);
    expect(b.groups, isNotEmpty);
    expect(b.groupNames, isEmpty);
  });

  test('the habit that was missed is named, not just counted', () {
    // Aziz, Wednesday 9 Sep: وتر and القرآن done, no تمرين.
    final b = roomDayBreakdown(
      room: _room(),
      participant: _member(
        done: {'2026-09-09': 2},
        marks: {
          '2026-09-09': {'t': _m, 'w': _d, 'q': _d},
        },
      ),
      dateKey: '2026-09-09',
    );
    expect(_rows(b), [
      ('تمرين', RoomSlotOutcome.missed),
      ('صلاة الوتر', RoomSlotOutcome.done),
      ('قراءة القرآن', RoomSlotOutcome.done),
    ]);
    expect(b.slots.first.share, 0);
    expect(b.slots[1].share, closeTo(1 / 3, 1e-9));
  });

  test('a slot added later has no row on the days before it joined', () {
    // Aziz, Tuesday 8 Sep: the Quran slot arrived at 00:48 on the 9th.
    final b = roomDayBreakdown(
      room: _room(),
      participant: _member(
        done: {'2026-09-08': 2},
        marks: {
          '2026-09-08': {'t': _d, 'w': _d},
        },
      ),
      dateKey: '2026-09-08',
    );
    expect(_rows(b), [
      ('تمرين', RoomSlotOutcome.done),
      ('صلاة الوتر', RoomSlotOutcome.done),
    ]);
  });

  test('a جزئي is named at half its share', () {
    // Aziz, Thursday 3 Sep.
    final b = roomDayBreakdown(
      room: _room(),
      participant: _member(
        done: {'2026-09-03': 1},
        partial: {'2026-09-03': 1},
        marks: {
          '2026-09-03': {'t': _p, 'w': _d},
        },
      ),
      dateKey: '2026-09-03',
    );
    expect(_rows(b), [
      ('تمرين', RoomSlotOutcome.partial),
      ('صلاة الوتر', RoomSlotOutcome.done),
    ]);
    expect([for (final s in b.slots) s.share], [0.25, 0.5]);
  });

  test('a تخطّي is named apart from a miss, and is worth the same nothing', () {
    final b = roomDayBreakdown(
      room: _room(),
      participant: _member(
        done: {'2026-09-04': 1},
        rested: {'2026-09-04': 1},
        marks: {
          '2026-09-04': {'t': _s, 'w': _d},
        },
      ),
      dateKey: '2026-09-04',
    );
    expect(_rows(b), [
      ('تمرين', RoomSlotOutcome.skipped),
      ('صلاة الوتر', RoomSlotOutcome.done),
    ]);
    expect(b.slots.first.share, 0);
    expect(b.credited, 1);
  });

  test('counts that moved without the marks fall back to the counts', () {
    final b = roomDayBreakdown(
      room: _room(),
      participant: _member(
        done: {'2026-09-09': 1},
        marks: {
          '2026-09-09': {'t': _m, 'w': _d, 'q': _d},
        },
      ),
      dateKey: '2026-09-09',
    );
    expect(b.slots, isEmpty);
    expect([
      for (final g in b.groups) (g.outcome, g.count)
    ], [
      (RoomSlotOutcome.done, 1),
      (RoomSlotOutcome.missed, 2),
    ]);
  });

  test('rows that would not add up to the total are never shown', () {
    // The map agrees with the counts only because of a habit no slot shows
    // any more. Its rows would be one done of two asked beside a total of
    // two of three, so the card uses the counts instead.
    final b = roomDayBreakdown(
      room: _room(),
      participant: _member(
        done: {'2026-09-09': 2},
        marks: {
          '2026-09-09': {'t': _m, 'w': _d, 'gone': _d},
        },
      ),
      dateKey: '2026-09-09',
    );
    expect(b.slots, isEmpty);
  });

  test('a declined slot is still named beside the marked ones', () {
    final b = roomDayBreakdown(
      room: _room(),
      participant: _member(
        linked: const ['t', kDeclinedSlot, 'q'],
        declinedFrom: const {1: '2026-09-01'},
        done: {'2026-09-10': 2},
        marks: {
          '2026-09-10': {'t': _d, 'q': _d},
        },
      ),
      dateKey: '2026-09-10',
    );
    expect(_rows(b), [
      ('تمرين', RoomSlotOutcome.done),
      ('قراءة القرآن', RoomSlotOutcome.done),
      ('صلاة الوتر', RoomSlotOutcome.declined),
    ]);
  });

  test('a day that asked nothing names every habit as a rest', () {
    final b = roomDayBreakdown(
      room: _room(),
      participant: _member(
        scheduled: {'2026-09-06': 0},
        marks: {
          '2026-09-06': {'t': _r, 'w': _r},
        },
      ),
      dateKey: '2026-09-06',
    );
    expect(_rows(b), [
      ('تمرين', RoomSlotOutcome.rest),
      ('صلاة الوتر', RoomSlotOutcome.rest),
    ]);
    expect(b.asksNothing, isTrue);
  });

  group('an own-mode room', () {
    RoomParticipant walker({bool hide = false}) => RoomParticipant(
          uid: 'm7md',
          displayName: 'm7md',
          characterId: 'none',
          joinedAt: DateTime(2026, 9),
          linkedHabitIds: const ['h1'],
          linkedHabitNames: const ['مشي'],
          hideDetails: hide,
          dailyDoneCount: const {'2026-09-05': 1},
          dailyHabitMarks: const {
            '2026-09-05': {'h1': RoomHabitMark.done},
          },
          lastUpdated: DateTime(2026, 9, 11),
        );

    test("names the member's own habit when the viewer may read it", () {
      final b = roomDayBreakdown(
        room: _room(mode: RoomHabitMode.own),
        participant: walker(),
        dateKey: '2026-09-05',
      );
      expect(_rows(b), [('مشي', RoomSlotOutcome.done)]);
    });

    test('names nothing when they hid it', () {
      final b = roomDayBreakdown(
        room: _room(mode: RoomHabitMode.own),
        participant: walker(hide: true),
        dateKey: '2026-09-05',
        namesVisible: false,
      );
      expect(b.slots, isEmpty);
    });
  });
}
