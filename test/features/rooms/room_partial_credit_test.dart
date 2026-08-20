// جزئي in a Room, and why it is allowed to score when a rest is not.
//
// Half the work is worth half the credit. That weight is not invented here:
// SquareState.xpValue already pays partial 5 against complete's 10, the
// Grid's own day ratio already scores it 0.5, and the personal reports
// already credit it 0.5. Rooms was the one surface still scoring it as
// nothing at all, so the same square meant two different things depending on
// which screen you were looking at.
//
// THE ASYMMETRY WITH REST IS THE POINT, and it is not arbitrary:
//
//   جزئي adds to the NUMERATOR, and is strictly dominated. Marking it can
//   only ever earn less than marking مكتمل, so nobody can improve a standing
//   by reaching for it. There is nothing to game.
//
//   تخطّي would shrink the DENOMINATOR, which is a dial: on a two-habit day
//   you could do one, rest the other, and watch a half day settle at full
//   credit. That is why dailyRestedCount may never reach a scoring function
//   while dailyPartialCount must.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/rooms/models/room_model.dart';

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
  Map<String, int> partial = const {},
  Map<String, int> rested = const {},
  Map<String, int> scheduled = const {},
}) =>
    RoomParticipant(
      uid: 'member-uid',
      displayName: 'Aziz',
      characterId: 'male_ghutra_blue',
      joinedAt: DateTime(2026, 8, 1),
      linkedHabitIds: linked,
      dailyDoneCount: done,
      dailyPartialCount: partial,
      dailyRestedCount: rested,
      dailyScheduledCount: scheduled,
      lastUpdated: DateTime(2026, 8, 19),
    );

void main() {
  group('half the work, half the credit', () {
    test('one of two habits half done is a quarter of the day', () {
      final p = _p(partial: const {_day: 1});
      expect(p.creditFor(_day), 0.25);
    });

    test('both habits half done is half the day', () {
      final p = _p(partial: const {_day: 2});
      expect(p.creditFor(_day), 0.5);
    });

    test('one done and one half done is three quarters', () {
      final p = _p(done: const {_day: 1}, partial: const {_day: 1});
      expect(p.creditFor(_day), 0.75);
    });

    test('it used to be worth nothing here', () {
      // The regression this exists to prevent: a partial scoring 0 in Rooms
      // while the personal reports gave it 0.5.
      final p = _p(partial: const {_day: 2});
      expect(p.creditFor(_day), isNot(0.0));
    });
  });

  group('but a half day is not a finished day', () {
    test('partials never satisfy isFullyDone', () {
      // Deliberately not read by isFullyDone, so a half day moves the bar
      // and the percentage without keeping a streak alive.
      final p = _p(partial: const {_day: 2});
      expect(p.creditFor(_day), 0.5);
      expect(p.isFullyDone(_day), isFalse);
    });

    test('even a full sweep of partials leaves the day unfinished', () {
      final p = _p(
        linked: const ['h1', 'h2', 'h3'],
        partial: const {_day: 3},
      );
      expect(p.isFullyDone(_day), isFalse);
    });
  });

  group('it cannot be gamed, which is why it is allowed to score', () {
    test('marking جزئي always earns less than marking مكتمل', () {
      // Strict domination. There is no arrangement of partials that beats
      // simply completing the same habits.
      final half = _p(partial: const {_day: 2});
      final full = _p(done: const {_day: 2});
      expect(half.creditFor(_day), lessThan(full.creditFor(_day)));
    });

    test('swapping a completion for a partial always costs you', () {
      final both = _p(done: const {_day: 2});
      final swapped = _p(done: const {_day: 1}, partial: const {_day: 1});
      expect(swapped.creditFor(_day), lessThan(both.creditFor(_day)));
    });

    test('credit still cannot exceed a whole day', () {
      // A stale count or a schedule that shrank must not print above 100%.
      final p = _p(
        done: const {_day: 2},
        partial: const {_day: 4},
        scheduled: const {_day: 2},
      );
      expect(p.creditFor(_day), 1.0);
    });
  });

  group('the asymmetry with rest, stated out loud', () {
    final room = _room();

    test('a partial MOVES the rank, a rest does not', () {
      final withPartial = _p(partial: const {_day: 2});
      final withRest = _p(rested: const {_day: 2});
      final neither = _p();
      expect(
        withPartial.progressRatio(room),
        greaterThan(neither.progressRatio(room)),
      );
      expect(withRest.progressRatio(room), neither.progressRatio(room));
    });

    test('resting everything still earns nothing', () {
      // Unchanged by this work, and it must stay that way: a rest shrinking
      // the denominator is the exploit, a partial adding to the numerator
      // is not.
      final p = _p(rested: const {_day: 2});
      expect(p.creditFor(_day), 0.0);
    });
  });
}
