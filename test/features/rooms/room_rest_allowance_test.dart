// The weekly rest allowance (رخصة) in a Room.
//
// One excused rest day a week, fixed for every room. The design property that
// makes it safe on a ranked surface is narrow and worth stating plainly:
//
//   A concession only ever removes a day that ALREADY SCORED ZERO.
//
// It requires isDeclaredRest, which needs every scheduled habit stood down and
// nothing done, and that by construction forces creditFor to 0. So a
// concession can never RAISE a day's credit; removing a zero from both sides
// is arithmetically identical to crediting that day at your own trailing
// rate. Somebody sitting at 0% gains exactly nothing by resting.
//
// A MIXED day is untouched, so there is no dial: standing down the one habit
// you did not do changes nothing at all.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/features/rooms/models/room_model.dart';

// 2026-08-01 is a Saturday, so this is one whole display week. Deliberately
// a week that has fully ELAPSED: RoomModel.lastCountedDay clamps to now, so a
// window straddling today silently shortens and every span assertion here
// would be off by the number of days still in the future.
final _weekStart = DateTime(2026, 8);
String _k(int offset) => DateTime(2026, 8, 1 + offset).toDateKey();

RoomModel _room({DateTime? end}) => RoomModel(
      code: 'A8GEL7',
      name: 'الإلتزام',
      createdBy: 'leader-uid',
      createdByName: 'Leader',
      createdAt: _weekStart,
      habitMode: RoomHabitMode.own,
      duration: RoomDuration.fixed,
      startDate: _weekStart,
      endDate: end ?? DateTime(2026, 8, 7),
    );

RoomParticipant _p({
  Map<String, int> done = const {},
  Map<String, int> rested = const {},
  Map<String, int> partial = const {},
  String? allowanceFrom,
}) =>
    RoomParticipant(
      uid: 'member-uid',
      displayName: 'Aziz',
      characterId: 'male_ghutra_blue',
      joinedAt: _weekStart,
      linkedHabitIds: const ['h1', 'h2'],
      dailyDoneCount: done,
      dailyRestedCount: rested,
      dailyPartialCount: partial,
      restAllowanceFrom: allowanceFrom,
      lastUpdated: DateTime(2026, 8, 7),
    );

void main() {
  group('nothing moves for a room that predates the allowance', () {
    test('an unstamped participant is excused nothing at all', () {
      // The ship-day guarantee. Until the stamp exists, concededDaysIn is
      // empty and every number comes out exactly as it did before.
      final p = _p(rested: {_k(0): 2});
      expect(p.concededDaysIn(_room()), isEmpty);
    });

    test('days before the stamp are never excused', () {
      final p = _p(
        rested: {_k(0): 2, _k(3): 2},
        allowanceFrom: _k(3),
      );
      final conceded = p.concededDaysIn(_room());
      expect(conceded, {_k(3)});
      expect(conceded, isNot(contains(_k(0))));
    });
  });

  group('one a week, and only one', () {
    test('a single full rest day is excused', () {
      final p = _p(rested: {_k(1): 2}, allowanceFrom: _k(0));
      expect(p.concededDaysIn(_room()), {_k(1)});
    });

    test('a second rest in the same week is not', () {
      final p = _p(
        rested: {_k(1): 2, _k(3): 2, _k(5): 2},
        allowanceFrom: _k(0),
      );
      expect(p.concededDaysIn(_room()).length, 1);
    });

    test('the allowance refills the following week', () {
      final room = _room(end: DateTime(2026, 8, 14));
      final p = _p(
        // One in the week of the 1st, one in the week of the 8th.
        rested: {_k(1): 2, _k(8): 2},
        allowanceFrom: _k(0),
      );
      expect(p.concededDaysIn(room).length, 2);
    });
  });

  group('it can only ever remove a zero, never invent a completion', () {
    test('a mixed day is untouched, so there is no dial', () {
      // One habit done, one stood down. Painting تخطّي on the one you did
      // not do buys nothing.
      final p = _p(
        done: {_k(1): 1},
        rested: {_k(1): 1},
        allowanceFrom: _k(0),
      );
      expect(p.concededDaysIn(_room()), isEmpty);
    });

    test('every conceded day scored exactly zero before it was excused', () {
      // The property the whole design rests on, asserted directly.
      final p = _p(rested: {_k(2): 2}, allowanceFrom: _k(0));
      for (final key in p.concededDaysIn(_room())) {
        expect(p.creditFor(key), 0.0);
      }
    });

    test('someone at zero percent gains nothing by resting', () {
      final room = _room();
      final resting = _p(rested: {_k(1): 2}, allowanceFrom: _k(0));
      final idle = _p(allowanceFrom: _k(0));
      expect(resting.progressRatio(room), idle.progressRatio(room));
      expect(resting.progressRatio(room), 0.0);
    });
  });

  group('what it actually buys someone who is doing the work', () {
    test('six of seven days done, one rested, reads as a full week', () {
      final room = _room();
      final p = _p(
        done: {
          for (var i = 0; i < 7; i++)
            if (i != 3) _k(i): 2,
        },
        rested: {_k(3): 2},
        allowanceFrom: _k(0),
      );
      expect(p.daysElapsedIn(room), 6, reason: 'the rested day left');
      expect(p.progressRatio(room), 1.0);
    });

    test('the same week without the allowance falls short', () {
      final room = _room();
      final p = _p(
        done: {
          for (var i = 0; i < 7; i++)
            if (i != 3) _k(i): 2,
        },
        rested: {_k(3): 2},
      );
      expect(p.daysElapsedIn(room), 7);
      expect(p.progressRatio(room), closeTo(6 / 7, 0.001));
    });

    test('resting every day of the week still does not reach a full week', () {
      // Only one of those days is excused, so the other six stay in the
      // denominator scoring zero. This is the ceiling that stops the
      // leaderboard becoming a contest about resting.
      final room = _room();
      final p = _p(
        rested: {for (var i = 0; i < 7; i++) _k(i): 2},
        allowanceFrom: _k(0),
      );
      expect(p.daysElapsedIn(room), 6);
      expect(p.progressRatio(room), 0.0);
    });
  });
}
