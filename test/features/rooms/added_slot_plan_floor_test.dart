// A habit added to a room that is already running counts from the day it
// joined the plan, not from the room's start date.
//
// The bug, traced on Aziz's own room ELQVF8 "Being Better" on 2026-09-09.
// The room started 2026-09-01 with two shared habits. On day 9 the leader
// added a third. Every past day's denominator became 3 while its stored
// numerator could not move, because the habit had not existed on those days
// and so had no squares behind it. His percentage fell from 58.3% to 38.9%
// and he lost first place, for work he had already done.
//
// The other member was untouched, because she had not resolved the new slot
// yet: her linkedHabitIds still held two entries. So the rule that actually
// shipped was "the leader who adds a habit takes a retroactive penalty and
// nobody else is touched until they opt in."
//
// Two mechanisms produced it, and both are covered here:
//
//   1. READ SIDE. dailyScheduledCount is sparse, so a perfect day stores no
//      key and scheduledCountFor falls back to the live linked-habit count.
//      A present-tense field answering a past-tense question.
//
//   2. WRITE SIDE, and the reason it never healed. syncLinkedHabitsProgress
//      seeded every freshly linked habit's room rule as `from: room.startDate`
//      (rooms_notifier.dart), which told the stint repair that the room had
//      been grading a day-9 habit since day 1. That repair exists to fix a
//      birth date corrupted by pause/resume, and it trusts the room's stamp
//      precisely because it is meant to be independent of the habit's own
//      dates. So it diagnosed a brand-new habit as damaged and forced it to
//      count across the room's whole history. habitExistedOn had already
//      drawn the line in the right place; the repair overrode it.
//
// The fix gives the plan a floor per slot, stamped from
// RoomHabitTemplate.addedAt, read on both sides through one value so a
// written key and an absent key can never mean different things about the
// same day.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/rooms/models/room_model.dart';
import 'package:grow_daily_v2/features/rooms/notifiers/rooms_notifier.dart';

const _start = '2026-09-01';
const _added = '2026-09-09';
const _h1 = 'habit-witr';
const _h2 = 'habit-tamreen';
const _hNew = 'habit-quran';

RoomHabitRule _rule(String from) => RoomHabitRule(
      from: from,
      frequencyType: HabitFrequencyType.daily,
      frequencyTarget: 1,
    );

RoomHabitTemplate _template(String name, {DateTime? addedAt}) =>
    RoomHabitTemplate(
      name: name,
      category: HabitCategory.faith,
      frequencyType: HabitFrequencyType.daily,
      frequencyTarget: 1,
      addedAt: addedAt,
    );

RoomModel _room({bool withThirdSlot = true}) => RoomModel(
      code: 'ELQVF8',
      name: 'Being Better',
      createdBy: 'leader-uid',
      createdByName: 'Aziz',
      createdAt: DateTime(2026, 9, 1),
      habitMode: RoomHabitMode.shared,
      duration: RoomDuration.fixed,
      startDate: DateTime(2026, 9, 1),
      endDate: DateTime(2026, 9, 30),
      sharedHabits: [
        _template('صلاة الوتر'),
        _template('تمرين'),
        if (withThirdSlot)
          _template('قراءة القرآن', addedAt: DateTime(2026, 9, 9)),
      ],
    );

RoomParticipant _member({
  required List<String> linked,
  required Map<String, List<RoomHabitRule>> rules,
  Map<String, int> done = const {},
  Map<String, int> scheduled = const {},
}) =>
    RoomParticipant(
      uid: 'leader-uid',
      displayName: 'Aziz',
      characterId: 'male_ghutra_blue',
      joinedAt: DateTime(2026, 9, 1),
      linkedHabitIds: linked,
      dailyDoneCount: done,
      dailyScheduledCount: scheduled,
      habitRules: rules,
      lastUpdated: DateTime(2026, 9, 9),
    );

void main() {
  group('slotOpenBy reads the room\'s own record of when a slot joined', () {
    test('an original slot is open on the room\'s first day', () {
      final p = _member(
        linked: const [_h1, _hNew],
        rules: {
          _h1: [_rule(_start)],
          _hNew: [_rule(_added)],
        },
      );
      expect(p.slotOpenBy(_h1, _start), isTrue);
    });

    test('a slot added on day 9 is closed on day 1 and open on day 9', () {
      final p = _member(
        linked: const [_h1, _hNew],
        rules: {
          _h1: [_rule(_start)],
          _hNew: [_rule(_added)],
        },
      );
      expect(p.slotOpenBy(_hNew, _start), isFalse);
      expect(p.slotOpenBy(_hNew, '2026-09-08'), isFalse);
      expect(p.slotOpenBy(_hNew, _added), isTrue,
          reason: 'the day it was added counts, "since the adding"');
      expect(p.slotOpenBy(_hNew, '2026-09-10'), isTrue);
    });

    test('it takes the MINIMUM from, not ruleFor\'s answer', () {
      // ruleFor deliberately falls back to the earliest period for a day
      // before any rule started, which is the right answer to "which cadence
      // applies" and the wrong one to "had this joined yet".
      final p = _member(
        linked: const [_hNew],
        rules: {
          _hNew: [_rule(_added), _rule('2026-09-20')],
        },
      );
      expect(p.ruleFor(_hNew, _start), isNotNull,
          reason: 'ruleFor still answers with a cadence');
      expect(p.slotOpenBy(_hNew, _start), isFalse);
    });

    test('FAILS OPEN with no recorded rule, so nothing moves on first launch',
        () {
      final p = _member(linked: const [_h1, _hNew], rules: const {});
      expect(p.slotOpenBy(_hNew, _start), isTrue);
      expect(p.countedHabitCountOn(_start), 2,
          reason: 'a doc with no habitRules grades exactly as it did before');
    });
  });

  group('the denominator is the plan as it stood on that day', () {
    RoomParticipant subject({Map<String, int> done = const {}}) => _member(
          linked: const [_h1, _h2, _hNew],
          rules: {
            _h1: [_rule(_start)],
            _h2: [_rule(_start)],
            _hNew: [_rule(_added)],
          },
          done: done,
        );

    test('a past day counts two habits, the day of the addition counts three',
        () {
      final p = subject();
      expect(p.countedHabitCountOn(_start), 2);
      expect(p.countedHabitCountOn('2026-09-08'), 2);
      expect(p.countedHabitCountOn(_added), 3);
    });

    test('a day that was fully done stays fully done', () {
      // THE REPORTED BUG. Both habits done on day 1; before the fix this read
      // 2/3 and the day stopped being "finished".
      final p = subject(done: const {_start: 2});
      expect(p.scheduledCountFor(_start), 2);
      expect(p.creditFor(_start), 1.0);
      expect(p.isFullyDone(_start), isTrue);
    });

    test('the new habit is owed from the day it was added', () {
      final p = subject(done: const {_added: 2});
      expect(p.scheduledCountFor(_added), 3);
      expect(p.creditFor(_added), closeTo(2 / 3, 1e-9));
      expect(p.isFullyDone(_added), isFalse,
          reason: 'it counts from the adding, so missing it is a real miss');
    });

    test('an explicitly stored count still wins over the fallback', () {
      // The sync knows more than the inference does. A stored 1 means one
      // habit really was excused that day.
      final p = _member(
        linked: const [_h1, _h2, _hNew],
        rules: {
          _h1: [_rule(_start)],
          _h2: [_rule(_start)],
          _hNew: [_rule(_added)],
        },
        done: const {_start: 1},
        scheduled: const {_start: 1},
      );
      expect(p.scheduledCountFor(_start), 1);
      expect(p.creditFor(_start), 1.0);
    });
  });

  group('the whole ratio, and the place it decides', () {
    // Aziz's real stored numbers from room ELQVF8 on 2026-09-09.
    const done = {
      '2026-09-01': 1,
      '2026-09-02': 2,
      '2026-09-03': 1,
      '2026-09-04': 1,
      '2026-09-05': 1,
      '2026-09-06': 1,
      '2026-09-07': 1,
      '2026-09-08': 2,
    };

    RoomParticipant aziz({required bool floored}) => RoomParticipant(
          uid: 'leader-uid',
          displayName: 'Aziz',
          characterId: 'male_ghutra_blue',
          joinedAt: DateTime(2026, 9, 1),
          linkedHabitIds: const [_h1, _h2, _hNew],
          dailyDoneCount: done,
          dailyPartialCount: const {'2026-09-03': 1},
          habitRules: {
            _h1: [_rule(_start)],
            _h2: [_rule(_start)],
            // The bug wrote room.startDate here for a slot added on day 9.
            _hNew: [_rule(floored ? _added : _start)],
          },
          lastUpdated: DateTime(2026, 9, 9),
        );

    double ratioThrough8(RoomParticipant p) {
      var total = 0.0;
      for (var d = 1; d <= 8; d++) {
        total += p.creditFor('2026-09-0$d');
      }
      return total / 8;
    }

    test('the reported drop, and that the floor undoes it exactly', () {
      expect(ratioThrough8(aziz(floored: false)), closeTo(3.50 / 8, 1e-9),
          reason: 'what the app showed him: 44% through 09-08');
      expect(ratioThrough8(aziz(floored: true)), closeTo(5.25 / 8, 1e-9),
          reason: 'what he had actually earned: 66%');
    });

    test('a day he had finished reads as finished again', () {
      expect(aziz(floored: false).isFullyDone('2026-09-02'), isFalse);
      expect(aziz(floored: true).isFullyDone('2026-09-02'), isTrue);
    });
  });

  group('what the floor must NOT do', () {
    test('it can never pay for a day nobody answered', () {
      // A member who declined every original slot and took only the
      // late-added one. A zero denominator is full credit in creditFor, so
      // this is the trapdoor: without the guard they would be handed 1.0 a
      // day for every day before the slot joined.
      final p = _member(
        linked: const [kDeclinedSlot, kDeclinedSlot, _hNew],
        rules: {
          _hNew: [_rule(_added)],
        },
      );
      expect(p.countedHabitCountOn(_start), 1,
          reason: 'falls back to the plain total rather than reaching zero');
      expect(p.creditFor(_start), 0.0,
          reason: 'the day scores zero, exactly as it does today');
      expect(p.scheduledCountFor(_start), 1);
    });

    test('a declined slot is still out of the count on every day', () {
      final p = _member(
        linked: const [_h1, kDeclinedSlot, _hNew],
        rules: {
          _h1: [_rule(_start)],
          _hNew: [_rule(_added)],
        },
      );
      expect(p.countedHabitCountOn(_start), 1);
      expect(p.countedHabitCountOn(_added), 2);
    });

    test('it does not touch a room whose plan never changed', () {
      final p = _member(
        linked: const [_h1, _h2],
        rules: {
          _h1: [_rule(_start)],
          _h2: [_rule(_start)],
        },
        done: const {_start: 2},
      );
      for (final d in ['2026-09-01', '2026-09-05', '2026-09-09']) {
        expect(p.countedHabitCountOn(d), p.countedHabitCount,
            reason: 'identical to the plain total for almost every room');
      }
      expect(p.creditFor(_start), 1.0);
    });

    test('back-painting the new habit cannot buy a pre-addition day', () {
      // Even with a green square recorded before the slot joined, the day's
      // denominator is 2 and its numerator cannot exceed what two habits can
      // earn. creditFor clamps at 1.0.
      final p = _member(
        linked: const [_h1, _h2, _hNew],
        rules: {
          _h1: [_rule(_start)],
          _h2: [_rule(_start)],
          _hNew: [_rule(_added)],
        },
        done: const {_start: 3},
      );
      expect(p.creditFor(_start), 1.0);
      expect(p.countedHabitCountOn(_start), 2);
    });
  });

  group('repairing a room this bug already mis-stamped', () {
    // Aziz's room had already synced, so habitRules[hNew] holds
    // `from: 2026-09-01` for a slot added on 2026-09-09. The seed only runs
    // for a slot with no rules at all, so without this correction nothing
    // would ever repair the rooms that actually hit the bug.
    RoomHabitRule weekly(String from, int target) => RoomHabitRule(
          from: from,
          frequencyType: HabitFrequencyType.weekly,
          frequencyTarget: target,
        );

    test('the mis-stamped period moves up to the day the slot joined', () {
      final fixed = rulesFromPlanFloor([_rule(_start)], _added);
      expect(fixed, hasLength(1));
      expect(fixed.single.from, _added);
    });

    test('it is a no-op when nothing starts before the floor', () {
      final original = [_rule(_start)];
      expect(identical(rulesFromPlanFloor(original, _start), original), isTrue,
          reason: 'an original slot, and every room that never edited a plan');
    });

    test('a re-locked slot keeps the cadence it was being graded by', () {
      // Stamped 4x a week at the room's start, re-locked to 6x on the 5th,
      // then corrected to a floor of the 9th. The cadence on the 9th is 6x.
      final fixed = rulesFromPlanFloor(
        [weekly(_start, 4), weekly('2026-09-05', 6)],
        _added,
      );
      expect(fixed, hasLength(1));
      expect(fixed.single.from, _added);
      expect(fixed.single.frequencyTarget, 6);
    });

    test('a period already at or after the floor is left alone', () {
      final fixed = rulesFromPlanFloor(
        [_rule(_start), weekly('2026-09-20', 3)],
        _added,
      );
      expect(fixed.map((r) => r.from), containsAll([_added, '2026-09-20']));
      expect(fixed.where((r) => r.from.compareTo(_added) < 0), isEmpty);
    });

    test('it never invents a duplicate at the floor', () {
      final fixed = rulesFromPlanFloor(
        [_rule(_start), _rule(_added)],
        _added,
      );
      expect(fixed.where((r) => r.from == _added), hasLength(1));
    });

    test('the corrected rule is what slotOpenBy then reads back', () {
      // The whole point: one value, written by the sync and read by the
      // model, so the two can never disagree about the same day.
      final fixed = rulesFromPlanFloor([_rule(_start)], _added);
      final p = _member(
        linked: const [_h1, _hNew],
        rules: {
          _h1: [_rule(_start)],
          _hNew: fixed,
        },
        done: const {_start: 1},
      );
      expect(p.slotOpenBy(_hNew, _start), isFalse);
      expect(p.countedHabitCountOn(_start), 1);
      expect(p.creditFor(_start), 1.0,
          reason: 'the one habit that existed on day 1 was done');
    });
  });

  group('a day the plan never reached is not a day the schedule excused', () {
    // THE TRAPDOOR the plan floor opens if this is got wrong. creditFor pays
    // a zero denominator in full ("nothing was asked, so nothing was fallen
    // short of"), which is right for a Mon/Wed/Fri habit on a Tuesday and
    // catastrophic for a day the member's plan did not exist on.
    test('a schedule-excused day still stores zero and still pays', () {
      expect(gradedScheduledCount(present: 2, computed: 0, planTotal: 2), 0,
          reason: 'both slots present, both excused by their own cadence');
    });

    test('a day no slot had reached falls back instead of storing zero', () {
      expect(gradedScheduledCount(present: 0, computed: 0, planTotal: 1), 1,
          reason: 'scores 0 and stays in the denominator, as it does today');
    });

    test('an ordinary day is untouched', () {
      expect(gradedScheduledCount(present: 3, computed: 2, planTotal: 3), 2);
      expect(gradedScheduledCount(present: 1, computed: 1, planTotal: 1), 1);
    });

    test('the stored zero is what would have been paid, end to end', () {
      // Decline both original slots, take only the one added on day 9.
      final p = _member(
        linked: const [kDeclinedSlot, kDeclinedSlot, _hNew],
        rules: {
          _hNew: [_rule(_added)],
        },
        scheduled: const {_start: 0},
      );
      expect(p.creditFor(_start), 1.0,
          reason: 'a stored zero outranks countedHabitCountOn and pays');
      expect(p.isRestDay(_start), isTrue);
    });

    test('and what the guard stores instead scores nothing', () {
      final p = _member(
        linked: const [kDeclinedSlot, kDeclinedSlot, _hNew],
        rules: {
          _hNew: [_rule(_added)],
        },
        scheduled: {
          _start: gradedScheduledCount(present: 0, computed: 0, planTotal: 1),
        },
      );
      expect(p.creditFor(_start), 0.0);
      expect(p.isRestDay(_start), isFalse);
      expect(p.isFullyDone(_start), isFalse);
    });
  });

  group('the room template carries the date the floor comes from', () {
    test('an added slot is stamped, an original one is not', () {
      final room = _room();
      expect(room.sharedHabits[0].addedAt, isNull,
          reason: 'everything the room was created with is born together');
      expect(room.sharedHabits[2].addedAt, DateTime(2026, 9, 9));
    });

    test('addedAt survives a Firestore round trip', () {
      final restored =
          RoomHabitTemplate.fromMap(_room().sharedHabits[2].toFirestore());
      expect(restored.addedAt, DateTime(2026, 9, 9));
    });
  });
}
