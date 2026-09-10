// The room score: every day graded against the room's plan as it stood that
// day, which is what the board ranks by; and the soft departure that stops
// leave-and-rejoin from being a reset.
//
// Two numbers, on purpose (see the section comment above
// RoomParticipant.roomCreditFor):
//
//   progressRatio       YOUR number. Done over the habits you linked, over
//                       your days. Never lies about your effort.
//   roomProgressRatio   THE ROOM SCORE. Every unlinked or declined slot the
//                       room asked for counts as not done. Same yardstick on
//                       every row, so the board can rank it honestly.
//
// Traced on Aziz's own room ELQVF8, 2026-09-09, and on the measured reset:
// leave on day 20 at 27%, rejoin, finish clean, read 100% and first place
// over a day-one member at 80%.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/rooms/models/room_model.dart';

const _h1 = 'witr';
const _h2 = 'tamreen';
const _h3 = 'quran';

RoomHabitRule _r(String from) => RoomHabitRule(
      from: from,
      frequencyType: HabitFrequencyType.daily,
      frequencyTarget: 1,
    );

RoomHabitTemplate _t(String name, {DateTime? addedAt, DateTime? removedAt}) =>
    RoomHabitTemplate(
      name: name,
      category: HabitCategory.faith,
      frequencyType: HabitFrequencyType.daily,
      frequencyTarget: 1,
      addedAt: addedAt,
      removedAt: removedAt,
    );

/// A "4x a week, any days" slot - the cadence the room score used to weigh
/// differently depending on which side of the plan it fell on.
RoomHabitTemplate _tw(String name) => RoomHabitTemplate(
      name: name,
      category: HabitCategory.fitness,
      frequencyType: HabitFrequencyType.weekly,
      frequencyTarget: 4,
    );

/// A 30 day room, three original slots, all dates in the past so the last
/// counted day is the end date and nothing depends on the clock.
RoomModel _room({
  List<RoomHabitTemplate>? slots,
  RoomHabitMode mode = RoomHabitMode.shared,
}) =>
    RoomModel(
      code: 'ROOM01',
      name: 'test',
      createdBy: 'leader',
      createdByName: 'Leader',
      createdAt: DateTime(2026, 7, 1),
      habitMode: mode,
      duration: RoomDuration.fixed,
      startDate: DateTime(2026, 7, 1),
      endDate: DateTime(2026, 7, 30),
      sharedHabits: slots ?? [_t('a'), _t('b'), _t('c')],
    );

Map<String, int> _everyDay(int perDay, {int from = 1, int to = 30}) => {
      for (var d = from; d <= to; d++)
        '2026-07-${d.toString().padLeft(2, '0')}': perDay,
    };

RoomParticipant _p({
  required String uid,
  required List<String> linked,
  Map<String, int> done = const {},
  Map<String, int> scheduled = const {},
  DateTime? joinedAt,
  DateTime? leftAt,
  List<({String from, String to})> awaySpans = const [],
  Map<String, List<RoomHabitRule>>? rules,
  // A decline with no date is not retroactive (see undatedDeclineFromKey), so
  // any test that wants one IN FORCE has to say when it was made - exactly
  // what a real decline records from the day it is made.
  Map<int, String> declinedFrom = const {},
}) =>
    RoomParticipant(
      uid: uid,
      displayName: uid,
      characterId: 'male_ghutra_blue',
      joinedAt: joinedAt ?? DateTime(2026, 7, 1),
      linkedHabitIds: linked,
      dailyDoneCount: done,
      dailyScheduledCount: scheduled,
      habitRules: rules ??
          {
            for (final id in linked)
              if (id != kDeclinedSlot) id: [_r('2026-07-01')],
          },
      slotDeclinedFrom: declinedFrom,
      lastUpdated: DateTime(2026, 7, 30),
      leftAt: leftAt,
      awaySpans: awaySpans,
    );

void main() {
  _restDayIsNotFreeOfTheRoom();
  group('the two numbers agree whenever nothing is missing', () {
    test('a member on the whole plan reads the same on both', () {
      final room = _room();
      final p = _p(uid: 'a', linked: const [_h1, _h2, _h3], done: _everyDay(2));
      expect(p.roomProgressRatio(room), p.progressRatio(room));
      expect(p.roomCreditFor(room, '2026-07-05'), p.creditFor('2026-07-05'));
    });

    test('an own-mode room has no plan to fall short of', () {
      final room = _room(mode: RoomHabitMode.own);
      final p = _p(uid: 'a', linked: const [_h1], done: _everyDay(1));
      expect(p.phantomSlotsOn(room, '2026-07-05'), 0);
      expect(p.planCoverageIn(room), isNull);
      expect(p.roomProgressRatio(room), 1.0);
    });
  });

  group('a declined or unlinked slot counts as not done on the room score', () {
    test('two of three done every day is 67%, not 100%', () {
      // THE DIAL this closes: a member who declined the hardest habit and
      // did the other two perfectly used to tie a member doing all three.
      final room = _room();
      final decliner = _p(
        uid: 'decl',
        linked: const [_h1, _h2, kDeclinedSlot],
        declinedFrom: const {2: '2026-07-01'},
        done: _everyDay(2),
      );
      final full = _p(
        uid: 'full',
        linked: const [_h1, _h2, _h3],
        done: _everyDay(3),
      );
      expect(decliner.progressRatio(room), 1.0,
          reason: 'their own number is honest: they did all they linked');
      expect(decliner.roomProgressRatio(room), closeTo(2 / 3, 1e-9));
      expect(full.roomProgressRatio(room), 1.0);
      final st = room.standings([decliner, full]);
      expect(st.first.participant.uid, 'full');
      expect(st.first.rank, 1);
      expect(st.last.rank, 2);
    });

    test('a slot never resolved counts the same as a declined one', () {
      final room = _room();
      final short = _p(uid: 's', linked: const [_h1, _h2], done: _everyDay(2));
      expect(short.phantomSlotsOn(room, '2026-07-05'), 1);
      expect(short.roomCreditFor(room, '2026-07-05'), closeTo(2 / 3, 1e-9));
    });

    test('a withdrawn slot is asked of nobody', () {
      final room = _room(slots: [
        _t('a'),
        _t('b'),
        _t('c', removedAt: DateTime(2026, 7, 2)),
      ]);
      final p = _p(uid: 'a', linked: const [_h1, _h2], done: _everyDay(2));
      expect(p.phantomSlotsOn(room, '2026-07-05'), 0);
      expect(p.planCoverageIn(room), (linked: 2, total: 2));
    });

    test('coverage is what the row prints beside the score', () {
      final room = _room();
      expect(
        _p(uid: 'a', linked: const [_h1, kDeclinedSlot, _h3])
            .planCoverageIn(room),
        (linked: 2, total: 3),
      );
      expect(
        _p(uid: 'b', linked: const [_h1]).planCoverageIn(room),
        (linked: 1, total: 3),
      );
    });

    test('a phantom never turns a day into a rest, and never into a miss', () {
      // Both linked habits excused by their schedule (stored 0), third slot
      // never linked. creditFor pays a zero denominator in full; the room
      // asked for the third habit, so the room score must not.
      final room = _room();
      final p = _p(
        uid: 'a',
        linked: const [_h1, _h2],
        scheduled: const {'2026-07-05': 0},
      );
      expect(p.creditFor('2026-07-05'), 1.0);

      // Two of the three slots are theirs and both were answered, as far as
      // the day asked anything at all. Two thirds.
      expect(p.roomCreditFor(room, '2026-07-05'), closeTo(2 / 3, 0.0001));

      // Both wrong answers, pinned. 1.0 would let an unlinked slot vanish on
      // any day the member's own habits happened not to be due.
      expect(p.roomCreditFor(room, '2026-07-05'), isNot(1.0));

      // 0.0 is what this actually shipped as, and it was worse: the old
      // arithmetic divided the day's raw done count by
      // scheduledCountFor + phantoms, so an excused habit left the numerator
      // as well as the denominator and a fully excused day read 0 / 0.5714.
      // A day the schedule granted scored exactly what a day of doing
      // nothing scored. Measured on room A8GEL7, that was 8 of Aziz's days
      // and 13 points of his room score.
      expect(p.roomCreditFor(room, '2026-07-05'), isNot(0.0));

      // The same day with the SCHEDULED habits actually missed is the thing
      // it must stay distinguishable from.
      final missed = _p(uid: 'b', linked: const [_h1, _h2]);
      expect(missed.roomCreditFor(room, '2026-07-05'), 0.0);
    });

    test('cadence does not change what carrying half a plan is worth', () {
      // The clearest statement of the rule. Two members, each carrying one
      // of their room's two identical slots and answering it perfectly. One
      // room's slots are daily, the other's are "4x a week". Same coverage,
      // same performance, so the same score - and it was not: the phantom
      // side discounted a weekly slot to 4/7 while the member's own side was
      // read off the day's raw scheduled count, which gave 50% and 40.7%.
      final daily = _room(slots: [_t('a'), _t('b')]);
      final weekly = _room(slots: [_tw('a'), _tw('b')]);

      final onDaily = _p(
        uid: 'daily',
        linked: const [_h1, kDeclinedSlot],
        declinedFrom: const {1: '2026-07-01'},
        done: _everyDay(1),
        rules: {_h1: [_r('2026-07-01')]},
      );
      // The weekly member trains 4 days of every 7 and the quota excuses the
      // other 3, which is what a met "4x a week" stores.
      final onWeekly = _p(
        uid: 'weekly',
        linked: const [_h1, kDeclinedSlot],
        declinedFrom: const {1: '2026-07-01'},
        done: {
          for (var d = 1; d <= 30; d++)
            if (d % 7 < 4) '2026-07-${d.toString().padLeft(2, '0')}': 1,
        },
        scheduled: {
          for (var d = 1; d <= 30; d++)
            if (d % 7 >= 4) '2026-07-${d.toString().padLeft(2, '0')}': 0,
        },
        rules: {_h1: [_r('2026-07-01')]},
      );

      expect(onDaily.progressRatio(daily), 1.0);
      expect(onWeekly.progressRatio(weekly), 1.0,
          reason: 'both answered their own half of the plan completely');
      expect(onDaily.roomProgressRatio(daily), closeTo(0.5, 0.0001));
      expect(onWeekly.roomProgressRatio(weekly), closeTo(0.5, 0.0001));
    });
  });

  group('a slot added mid-room, on the room score', () {
    final room = _room(slots: [
      _t('a'),
      _t('b'),
      _t('c', addedAt: DateTime(2026, 7, 9)),
    ]);

    test('is asked of an unlinked member only after the grace', () {
      final p = _p(uid: 'a', linked: const [_h1, _h2], done: _everyDay(2));
      expect(room.slotJoinedPlanKey(2), '2026-07-09');
      expect(room.slotAsksFromKey(2), '2026-07-12',
          reason: '${RoomModel.kNewSlotGraceDays} days of grace');
      expect(p.phantomSlotsOn(room, '2026-07-08'), 0);
      expect(p.phantomSlotsOn(room, '2026-07-11'), 0);
      expect(p.phantomSlotsOn(room, '2026-07-12'), 1);
      expect(p.roomCreditFor(room, '2026-07-08'), 1.0,
          reason: 'before the slot existed, two of two is a full day');
      expect(p.roomCreditFor(room, '2026-07-12'), closeTo(2 / 3, 1e-9));
    });

    test('counts for a member who linked it from the day they did', () {
      // Their own rule says so - the seed stamps the link day (see
      // rooms_notifier's planFloorFor / seedFrom). Same day, no wait.
      final p = _p(
        uid: 'a',
        linked: const [_h1, _h2, _h3],
        done: _everyDay(3),
        rules: {
          _h1: [_r('2026-07-01')],
          _h2: [_r('2026-07-01')],
          _h3: [_r('2026-07-09')],
        },
      );
      expect(p.phantomSlotsOn(room, '2026-07-09'), 0);
      expect(p.countedHabitCountOn('2026-07-08'), 2);
      expect(p.countedHabitCountOn('2026-07-09'), 3);
      expect(p.roomProgressRatio(room), 1.0);
    });

    test('an original slot has no grace: everyone chose it on joining', () {
      expect(room.slotAsksFromKey(0), '2026-07-01');
    });

    test('linking late keeps the phantom until the day you linked', () {
      // THE CRITICAL FINDING this closes. A member links the slot on day 20,
      // to a habit whose own schedule is Sunday-only. Its room rule starts
      // on day 20 and never earlier, so days 12 to 19 stay the plain
      // phantom miss they were for an unlinked member, and the sparse
      // cadence governs only from the link day. Before: the rule was stamped
      // from the room's start and every past weekday vanished from the
      // denominator, 50% -> 93% for no work.
      final p = _p(
        uid: 'late',
        linked: const [_h1, _h2, _h3],
        done: _everyDay(2),
        rules: {
          _h1: [_r('2026-07-01')],
          _h2: [_r('2026-07-01')],
          _h3: [
            RoomHabitRule(
              from: '2026-07-20',
              frequencyType: HabitFrequencyType.daily,
              frequencyTarget: 1,
              scheduledWeekdays: const [DateTime.sunday],
            ),
          ],
        },
      );
      expect(p.phantomSlotsOn(room, '2026-07-11'), 0,
          reason: 'inside the grace nobody is asked');
      expect(p.phantomSlotsOn(room, '2026-07-12'), 1,
          reason: 'from the grace day until the link, a phantom');
      expect(p.phantomSlotsOn(room, '2026-07-19'), 1);
      expect(p.phantomSlotsOn(room, '2026-07-20'), 0,
          reason: 'from the link day the habit itself is graded');
      expect(p.roomCreditFor(room, '2026-07-15'), closeTo(2 / 3, 1e-9));
      expect(p.countedHabitCountOn('2026-07-15'), 2,
          reason: 'and the read-side denominator agrees with the phantom');
    });
  });

  group('a decline counts from the day it was made', () {
    final room = _room();

    test('declining a slot on day 20 leaves days 1 to 19 as they were', () {
      // THE RETROACTIVE DROP this closes: unlinking one of three habits on
      // day 20 used to put its phantom on every past day, 100% -> 67% for
      // work already done. The slot was linked and graded until day 20; the
      // record says so, and stays.
      final p = RoomParticipant(
        uid: 'a',
        displayName: 'a',
        characterId: 'male_ghutra_blue',
        joinedAt: DateTime(2026, 7, 1),
        linkedHabitIds: const [_h1, _h2, kDeclinedSlot],
        dailyDoneCount: {..._everyDay(3, to: 19), ..._everyDay(2, from: 20)},
        habitRules: {
          _h1: [_r('2026-07-01')],
          _h2: [_r('2026-07-01')],
          _h3: [_r('2026-07-01')],
        },
        slotDeclinedFrom: const {2: '2026-07-20'},
        slotPriorHabitIds: const {2: _h3},
        lastUpdated: DateTime(2026, 7, 30),
      );
      expect(p.habitInSlotOn(2, '2026-07-19'), _h3);
      expect(p.habitInSlotOn(2, '2026-07-20'), isNull);
      expect(p.phantomSlotsOn(room, '2026-07-19'), 0);
      expect(p.phantomSlotsOn(room, '2026-07-20'), 1);
      expect(p.countedHabitCountOn('2026-07-19'), 3,
          reason: 'three habits were linked that day');
      expect(p.roomCreditFor(room, '2026-07-19'), 1.0);
      expect(p.roomCreditFor(room, '2026-07-20'), closeTo(2 / 3, 1e-9));
    });

    test('a closed declined window stays a phantom however it is refilled',
        () {
      // Declined days 10 to 14, then resolved again on day 15 with an old
      // habit that happened to be paused across exactly those days. Before:
      // the resync graded that habit, found it excused, and the five missed
      // days vanished. Now the window is a phantom no matter what fills it.
      final p = RoomParticipant(
        uid: 'a',
        displayName: 'a',
        characterId: 'male_ghutra_blue',
        joinedAt: DateTime(2026, 7, 1),
        linkedHabitIds: const [_h1, _h2, _h3],
        // Two of three across the declined window (the slot held nothing
        // then, so nothing could have been done in it), three otherwise.
        dailyDoneCount: {
          ..._everyDay(3, to: 9),
          ..._everyDay(2, from: 10, to: 14),
          ..._everyDay(3, from: 15),
        },
        habitRules: {
          _h1: [_r('2026-07-01')],
          _h2: [_r('2026-07-01')],
          _h3: [_r('2026-07-01')],
        },
        slotDeclinedSpans: const {
          2: [(from: '2026-07-10', to: '2026-07-14')],
        },
        lastUpdated: DateTime(2026, 7, 30),
      );
      expect(p.slotDeclinedOn(2, '2026-07-12'), isTrue);
      expect(p.habitInSlotOn(2, '2026-07-12'), isNull);
      expect(p.phantomSlotsOn(room, '2026-07-12'), 1);
      expect(p.phantomSlotsOn(room, '2026-07-15'), 0);
      expect(p.countedHabitCountOn('2026-07-12'), 2,
          reason: 'the slot had no habit in it that day');
      expect(p.roomCreditFor(room, '2026-07-12'), lessThan(1.0));
      expect(p.roomCreditFor(room, '2026-07-15'), 1.0);
    });

    test('a decline with no date is not retroactive', () {
      // It used to be declined on EVERY day, which read as a tidy default
      // and was a hole. slotDeclinedFrom's first three weeks of writes were
      // silently discarded by a dotted field key inside a set(merge:), so no
      // production document carries one - every real decline took that
      // branch and became a phantom across its room's entire history,
      // including the weeks the slot was linked and answered. On A8GEL7 that
      // reversed the podium on its own.
      //
      // Now it counts from the document's last write (2026-07-30 here), the
      // latest the decline can possibly have been made, so no day is charged
      // that has no record against it.
      final p = _p(uid: 'a', linked: const [_h1, _h2, kDeclinedSlot]);
      expect(p.undatedDeclineFromKey, '2026-07-30');

      expect(p.slotDeclinedOn(2, '2026-07-01'), isFalse);
      expect(p.phantomSlotsOn(room, '2026-07-01'), 0);
      expect(p.slotDeclinedOn(2, '2026-07-30'), isTrue);
      expect(p.phantomSlotsOn(room, '2026-07-30'), 1);
    });

    test('a dated decline ignores the fallback entirely', () {
      // The fallback must never override a real record, in either direction.
      final p = _p(uid: 'a', linked: const [_h1, _h2, kDeclinedSlot]);
      final dated = p.copyWith(slotDeclinedFrom: const {2: '2026-07-10'});
      expect(dated.slotDeclinedOn(2, '2026-07-09'), isFalse);
      expect(dated.slotDeclinedOn(2, '2026-07-10'), isTrue,
          reason: 'before lastUpdated, and still declined');
    });

    test('the slot timeline survives a Firestore round trip', () {
      final p = RoomParticipant(
        uid: 'a',
        displayName: 'a',
        characterId: 'male_ghutra_blue',
        joinedAt: DateTime(2026, 7, 1),
        linkedHabitIds: const [_h1, kDeclinedSlot],
        slotDeclinedFrom: const {1: '2026-07-20'},
        slotDeclinedSpans: const {
          1: [(from: '2026-07-03', to: '2026-07-04')],
        },
        slotPriorHabitIds: const {1: _h2},
        lastUpdated: DateTime(2026, 7, 30),
      );
      final map = p.toFirestore();
      expect(map['slotDeclinedFrom'], {'1': '2026-07-20'});
      expect(map['slotPriorHabitIds'], {'1': _h2});
      expect(map['slotDeclinedSpans'], {
        '1': [
          {'from': '2026-07-03', 'to': '2026-07-04'},
        ],
      });
    });
  });

  group('leaving keeps the record; away days score zero', () {
    final room = _room();

    test('a departed member is flagged and reads away from the day they left',
        () {
      final p = _p(
        uid: 'a',
        linked: const [_h1, _h2, _h3],
        leftAt: DateTime(2026, 7, 20, 14, 30),
      );
      expect(p.isDeparted, isTrue);
      expect(p.isAwayOn('2026-07-19'), isFalse);
      expect(p.isAwayOn('2026-07-20'), isTrue);
      expect(p.isAwayOn('2026-07-30'), isTrue);
    });

    test('THE RESET, closed: leave on day 21, come back, finish clean', () {
      // Measured before the fix: 27% -> 100% and rank 1 over a day-one
      // member at 80%. The record is kept, the twenty days are still
      // theirs, and the days out score zero.
      final honest = _p(
        uid: 'honest',
        linked: const [_h1, _h2, _h3],
        done: {..._everyDay(2, to: 20), ..._everyDay(3, from: 21)},
      );
      final rejoiner = _p(
        uid: 'rejoin',
        linked: const [_h1, _h2, _h3],
        // Away on days 21 to 25, back for 26 to 30 and perfect.
        done: {..._everyDay(2, to: 20), ..._everyDay(3, from: 26)},
        awaySpans: const [(from: '2026-07-21', to: '2026-07-25')],
      );
      expect(rejoiner.countedStartIn(room), DateTime(2026, 7, 1),
          reason: 'joinedAt is still the FIRST join');
      expect(rejoiner.daysElapsedIn(room), 30,
          reason: 'away days stay in the denominator');
      for (var d = 21; d <= 25; d++) {
        expect(rejoiner.roomCreditFor(room, '2026-07-$d'), 0.0);
      }
      expect(rejoiner.roomProgressRatio(room),
          lessThan(honest.roomProgressRatio(room)));
      final st = room.standings([rejoiner, honest]);
      expect(st.first.participant.uid, 'honest');
    });

    test('a member still out right now scores zero from leftAt onward', () {
      final p = _p(
        uid: 'a',
        linked: const [_h1, _h2, _h3],
        done: _everyDay(3),
        leftAt: DateTime(2026, 7, 16),
      );
      expect(p.roomCreditFor(room, '2026-07-15'), 1.0);
      expect(p.roomCreditFor(room, '2026-07-16'), 0.0);
    });

    test('leftAt and awaySpans survive a Firestore round trip', () {
      final p = _p(
        uid: 'a',
        linked: const [_h1],
        leftAt: DateTime(2026, 7, 16, 9),
        awaySpans: const [(from: '2026-07-03', to: '2026-07-04')],
      );
      final map = p.toFirestore();
      expect(map['leftAt'], isNotNull);
      expect(map['awaySpans'], [
        {'from': '2026-07-03', 'to': '2026-07-04'},
      ]);
      expect(RoomModel.spansFrom(map['awaySpans']),
          [(from: '2026-07-03', to: '2026-07-04')]);
      expect(_p(uid: 'b', linked: const [_h1]).toFirestore()
          .containsKey('leftAt'), isFalse,
          reason: 'absent means in the room, as every older doc was');
    });

    test('copyWith can clear a departure', () {
      final p = _p(uid: 'a', linked: const [_h1], leftAt: DateTime(2026, 7, 16));
      expect(p.copyWith().isDeparted, isTrue);
      expect(p.copyWith(clearLeftAt: true).isDeparted, isFalse);
    });
  });

  group('a place needs tenure', () {
    final room = _room();

    test('the one-day sniper reads 100% and holds no place', () {
      // Joined on the final day, did it, done. Before: rank 1, the cup and
      // 200 XP over 29 perfect days of 30.
      final sniper = _p(
        uid: 'snipe',
        linked: const [_h1, _h2, _h3],
        joinedAt: DateTime(2026, 7, 30),
        done: const {'2026-07-30': 3},
      );
      final honest = _p(
        uid: 'honest',
        linked: const [_h1, _h2, _h3],
        done: _everyDay(3, to: 29),
      );
      expect(sniper.roomProgressRatio(room), 1.0,
          reason: 'the score itself is still honest for their one day');
      expect(room.holdsPlaceIn(sniper), isFalse);
      final st = room.standings([sniper, honest]);
      final bySniper = st.firstWhere((s) => s.participant.uid == 'snipe');
      final byHonest = st.firstWhere((s) => s.participant.uid == 'honest');
      expect(bySniper.rank, 0);
      expect(byHonest.rank, 1);
    });

    test('joining in the first half of a room is enough', () {
      final p = _p(
        uid: 'a',
        linked: const [_h1, _h2, _h3],
        joinedAt: DateTime(2026, 7, 10),
        done: _everyDay(3, from: 10),
      );
      expect(room.holdsPlaceIn(p), isTrue);
    });

    test('day one of a room places everyone', () {
      final young = RoomModel(
        code: 'NEW',
        name: 'new',
        createdBy: 'l',
        createdByName: 'L',
        createdAt: DateTime(2026, 7, 1),
        habitMode: RoomHabitMode.shared,
        duration: RoomDuration.fixed,
        startDate: DateTime(2026, 7, 1),
        endDate: DateTime(2026, 7, 1),
        sharedHabits: [_t('a')],
      );
      final p = _p(uid: 'a', linked: const [_h1], done: const {'2026-07-01': 1});
      expect(young.holdsPlaceIn(p), isTrue);
      expect(young.standings([p]).single.rank, 1);
    });

    test('a pause is a stand-down, not a shorter membership', () {
      // Day-one member who stood down 6 of the room's days. daysElapsedIn
      // excuses those from the SCORE, and must not shrink their tenure.
      final p = RoomParticipant(
        uid: 'paused',
        displayName: 'paused',
        characterId: 'male_ghutra_blue',
        joinedAt: DateTime(2026, 7, 1),
        linkedHabitIds: const [_h1, _h2, _h3],
        dailyDoneCount: _everyDay(3, to: 12),
        standDownDays: [
          for (var d = 13; d <= 30; d++) '2026-07-$d',
        ],
        lastUpdated: DateTime(2026, 7, 30),
      );
      expect(p.daysElapsedIn(room), 12, reason: 'the score excuses the pause');
      expect(room.holdsPlaceIn(p), isTrue, reason: 'the place does not');
    });

    test('an open-ended room never asks for more than the cap', () {
      final open = RoomModel(
        code: 'OPEN',
        name: 'open',
        createdBy: 'l',
        createdByName: 'L',
        createdAt: DateTime(2026, 1, 1),
        habitMode: RoomHabitMode.shared,
        duration: RoomDuration.open,
        startDate: DateTime(2026, 1, 1),
        sharedHabits: [_t('a')],
      );
      // Joined well into the room's life; the cap is what places them.
      final lateJoiner = RoomParticipant(
        uid: 'late',
        displayName: 'late',
        characterId: 'male_ghutra_blue',
        joinedAt: DateTime.now().subtract(
          const Duration(days: RoomModel.kPlaceTenureCapDays + 1),
        ),
        linkedHabitIds: const [_h1],
        lastUpdated: DateTime.now(),
      );
      expect(open.daysElapsed, greaterThan(RoomModel.kPlaceTenureCapDays * 2));
      expect(open.holdsPlaceIn(lateJoiner), isTrue);
      final yesterday = RoomParticipant(
        uid: 'new',
        displayName: 'new',
        characterId: 'male_ghutra_blue',
        joinedAt: DateTime.now().subtract(const Duration(days: 1)),
        linkedHabitIds: const [_h1],
        lastUpdated: DateTime.now(),
      );
      expect(open.holdsPlaceIn(yesterday), isFalse);
    });

    test('away days count as tenure, so leaving cannot dodge it either way',
        () {
      final p = _p(
        uid: 'a',
        linked: const [_h1, _h2, _h3],
        done: _everyDay(3, to: 5),
        awaySpans: const [(from: '2026-07-06', to: '2026-07-30')],
      );
      expect(room.holdsPlaceIn(p), isTrue);
      expect(p.roomProgressRatio(room), closeTo(5 / 30, 1e-9),
          reason: 'and they pay for it in the score instead');
    });
  });
}

/// A rest day is free from YOUR plan, never from the ROOM's.
///
/// Making a day the schedule never asked for leave the denominator (see
/// daysElapsedIn) is right for the personal number and would be a hole in the
/// room score: a member who never linked one of the room's slots could sit
/// out that slot for free simply by having nothing of their own due. The
/// unlinked slot still asks every day it is open, so those days go back into
/// the room's denominator and only that one.
void _restDayIsNotFreeOfTheRoom() {
  group('a rest day leaves your denominator, not the room\'s', () {
    // Two slots, both live from day one. This member linked one of them and
    // never linked the other, and their own habit is not due on 5 of the 30
    // days. On the 25 days it IS due, they do it.
    final room = _room(slots: [_t('a'), _t('b')]);
    final restDays = ['2026-07-26', '2026-07-27', '2026-07-28', '2026-07-29', '2026-07-30'];

    final p = _p(
      uid: 'half',
      linked: const [_h1],
      done: {
        for (var d = 1; d <= 25; d++)
          '2026-07-${d.toString().padLeft(2, '0')}': 1,
      },
      scheduled: {for (final k in restDays) k: 0},
      rules: {_h1: [_r('2026-07-01')]},
    );

    test('the five rest days are gone from the personal number', () {
      for (final k in restDays) {
        expect(p.isRestDay(k), isTrue, reason: k);
      }
      expect(p.daysElapsedIn(room), 25);
      expect(p.daysCompleted(room), 25.0);
      // Their own plan asked 25 times and got 25. That is 100%, and it is
      // true: nothing they took on went undone.
      expect(p.progressRatio(room), 1.0);
    });

    test('and back in the room number, because slot b never stopped asking',
        () {
      // All 30 days count against the room's plan. The unlinked slot is a
      // phantom on every one of them, including the five that were free of
      // this member's own habit.
      expect(p.roomDaysElapsedIn(room), 30);
      for (final k in restDays) {
        expect(p.phantomWeightOn(room, k), greaterThan(0), reason: k);
      }
      // Half a plan, carried well: well under the 100% their own number
      // shows, and well above zero.
      final score = p.roomProgressRatio(room);
      expect(score, lessThan(0.7));
      expect(score, greaterThan(0.3));
    });

    test('a rest day is worth a trained day, and a missed day is not', () {
      // The two comparisons that fence the rule in on the room side, where
      // the personal one already has them: resting when the schedule says
      // to must cost nothing against actually training, and missing must
      // still cost. Only the second half was true - a phantom used to drive
      // an excused day to a flat 0.0, so the room score charged a member for
      // their own habit's rest days.
      final trained = _p(
        uid: 'half-trained',
        linked: const [_h1],
        done: _everyDay(1),
        rules: {_h1: [_r('2026-07-01')]},
      );
      final missing = _p(
        uid: 'half-missing',
        linked: const [_h1],
        done: {
          for (var d = 1; d <= 25; d++)
            '2026-07-${d.toString().padLeft(2, '0')}': 1,
        },
        rules: {_h1: [_r('2026-07-01')]},
      );

      expect(
        p.roomProgressRatio(room),
        closeTo(trained.roomProgressRatio(room), 0.0001),
        reason: 'resting on the five days the schedule granted is worth '
            'exactly what training on them was',
      );
      expect(
        p.roomProgressRatio(room),
        greaterThan(missing.roomProgressRatio(room)),
        reason: 'and the five days simply skipped still cost',
      );
    });
  });
}
