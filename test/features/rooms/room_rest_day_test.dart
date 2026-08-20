// Rooms recording a rest day, and the wall that keeps it from paying.
//
// The personal reports now excuse a تخطّي from the denominator entirely. A
// room cannot do that, and the reason is worth stating because the naive fix
// looks obviously right:
//
// If a rested habit were subtracted from a room's scheduledCount, then on a
// day with two linked habits you could do ONE, paint the other تخطّي, and
// watch the day settle at full credit instead of half. That is a dial, not a
// mercy: it buys rank for a paint stroke, it is repeatable every day, and the
// strip cell renders identically to a day where both habits were genuinely
// done, so nobody can see it happening.
//
// So Rooms records the rest and DRAWS it as a rest, and scores it as the
// nothing it is. What the app owes someone who rested is that it not call
// them a failure in public. It does not owe them the points.
//
// The last group here is the guard rail: any future change that lets
// dailyRestedCount reach a scoring function fails these tests.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/rooms/models/room_model.dart';
// roomStripCellFill lives in room_detail_screen_leaderboard_extend.dart,
// which is a `part of` this library, so it is reached through the parent.
import 'package:grow_daily_v2/features/rooms/screens/room_detail_screen.dart'
    show roomStripCellFill;

const _day = '2026-08-19';

RoomModel _room() => RoomModel(
      code: 'A8GEL7',
      name: 'الإلتزام',
      createdBy: 'leader-uid',
      createdByName: 'Leader',
      createdAt: DateTime(2026, 8, 1),
      habitMode: RoomHabitMode.own,
      duration: RoomDuration.fixed,
      startDate: DateTime(2026, 8, 1),
      endDate: DateTime(2026, 10, 30),
    );

RoomParticipant _p({
  List<String> linked = const ['h1', 'h2'],
  Map<String, int> done = const {},
  Map<String, int> scheduled = const {},
  Map<String, int> rested = const {},
}) =>
    RoomParticipant(
      uid: 'member-uid',
      displayName: 'Aziz',
      characterId: 'male_ghutra_blue',
      joinedAt: DateTime(2026, 8, 1),
      linkedHabitIds: linked,
      dailyDoneCount: done,
      dailyScheduledCount: scheduled,
      dailyRestedCount: rested,
      lastUpdated: DateTime(2026, 8, 19),
    );

void main() {
  group('isDeclaredRest', () {
    test('a day where everything was stood down reads as a rest', () {
      final p = _p(rested: const {_day: 2});
      expect(p.isDeclaredRest(_day), isTrue);
    });

    test('a MIXED day is not a rest', () {
      // The anti-gaming property, stated as a display rule. One habit done,
      // one rested is a half day and must look like a half day; borrowing
      // the calm of a full rest is exactly how the dial would have felt
      // legitimate.
      final p = _p(done: const {_day: 1}, rested: const {_day: 1});
      expect(p.isDeclaredRest(_day), isFalse);
    });

    test('a structurally empty day keeps its own treatment', () {
      // Nothing was owed. That is not a choice anybody made, and it already
      // has its own emerald tone and full credit.
      final p = _p(scheduled: const {_day: 0}, rested: const {_day: 1});
      expect(p.isRestDay(_day), isTrue);
      expect(p.isDeclaredRest(_day), isFalse);
    });

    test('standing down only SOME of the day is not a rest', () {
      // The case device testing caught. Three linked habits, one stood down,
      // nothing done. Two were plainly missed, and painting the day as a
      // calm rest forgives them in public.
      final p = _p(
        linked: const ['h1', 'h2', 'h3'],
        rested: const {_day: 1},
      );
      expect(p.isDeclaredRest(_day), isFalse);
    });

    test('standing down every one of them is', () {
      final p = _p(
        linked: const ['h1', 'h2', 'h3'],
        rested: const {_day: 3},
      );
      expect(p.isDeclaredRest(_day), isTrue);
    });

    test('it counts against what was SCHEDULED, not what was linked', () {
      // Two linked, only one due today (the other is a Mon/Thu habit on a
      // Tuesday). Standing down the one that was due is a full rest.
      final p = _p(
        linked: const ['h1', 'h2'],
        scheduled: const {_day: 1},
        rested: const {_day: 1},
      );
      expect(p.isDeclaredRest(_day), isTrue);
    });

    test('a day with nothing recorded at all is not a rest', () {
      expect(_p().isDeclaredRest(_day), isFalse);
    });

    test('a participant with nothing linked is not resting', () {
      final p = _p(linked: const [], rested: const {_day: 1});
      expect(p.isDeclaredRest(_day), isFalse);
    });
  });

  group('the strip draws it, and draws it apart from a miss', () {
    const backdrop = Color(0xFF101410);

    Color fill({
      double credit = 0,
      bool isRest = false,
      bool isMissed = false,
      bool isDeclaredRest = false,
    }) =>
        roomStripCellFill(
          credit: credit,
          isRest: isRest,
          isMissed: isMissed,
          isDeclaredRest: isDeclaredRest,
          dark: true,
          backdrop: backdrop,
        );

    test('a declared rest is not painted as a miss', () {
      expect(fill(isDeclaredRest: true), isNot(fill(isMissed: true)));
    });

    test('a declared rest is not painted as a structural rest either', () {
      // Two different facts: "you chose to rest" and "nothing was owed".
      expect(fill(isDeclaredRest: true), isNot(fill(isRest: true)));
    });

    test('a declared rest is not painted as a finished day', () {
      expect(fill(isDeclaredRest: true), isNot(fill(credit: 1)));
    });

    test('it outranks the miss arm even when credit is zero', () {
      // A rest is settled the instant it is marked, so it must win over the
      // miss styling rather than waiting for any week to close.
      expect(
        fill(isDeclaredRest: true, isMissed: true),
        fill(isDeclaredRest: true),
      );
    });
  });

  group('THE WALL: dailyRestedCount may never move a score', () {
    // Two participants identical in every way except that one has recorded
    // rest days. Every number a leaderboard sorts, renders or pays out on
    // must be indistinguishable between them.
    final room = _room();
    final silent = _p(done: const {_day: 1}, scheduled: const {_day: 2});
    final rested = _p(
      done: const {_day: 1},
      scheduled: const {_day: 2},
      rested: const {_day: 1},
    );

    test('creditFor is unmoved', () {
      expect(rested.creditFor(_day), silent.creditFor(_day));
      expect(rested.creditFor(_day), 0.5);
    });

    test('scheduledCountFor is unmoved', () {
      expect(rested.scheduledCountFor(_day), silent.scheduledCountFor(_day));
    });

    test('isFullyDone is unmoved', () {
      expect(rested.isFullyDone(_day), silent.isFullyDone(_day));
      expect(rested.isFullyDone(_day), isFalse);
    });

    test('isRestDay is unmoved', () {
      expect(rested.isRestDay(_day), silent.isRestDay(_day));
    });

    test('daysCompleted is unmoved', () {
      expect(rested.daysCompleted(room), silent.daysCompleted(room));
    });

    test('progressRatio, which the leaderboard SORTS on, is unmoved', () {
      expect(rested.progressRatio(room), silent.progressRatio(room));
    });

    test('currentStreak is unmoved', () {
      expect(rested.currentStreak(room), silent.currentStreak(room));
    });

    test('a fully rested day still earns nothing at all', () {
      // The headline case. Standing everything down does not buy a day.
      final allRested = _p(rested: const {_day: 2});
      expect(allRested.creditFor(_day), 0.0);
      expect(allRested.isFullyDone(_day), isFalse);
      // But it is no longer DRAWN as a failure, which was the whole point.
      expect(allRested.isDeclaredRest(_day), isTrue);
    });
  });
}
