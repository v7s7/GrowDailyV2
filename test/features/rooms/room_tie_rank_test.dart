// Two members who are level get the same place, and the same cup.
//
// A room's board used to carry an ORDER and nothing else. Every surface that
// wanted a number turned a list position into one: the leaderboard row with
// `indexOf + 1`, the finale podium with three hard-coded slots, and the prize
// section with `indexWhere + 1`. So two people who had done exactly the same
// work were shown as first and second, and paid as first and second, on the
// strength of whose uid sorted earlier. The cup went to one of them.
//
// RoomLeaderboard.standings is now the only thing that decides both, and it
// gives level members the same place: 1, 1, 3, never 1, 1, 2.
//
// Two rules in here are easy to read as bugs and are not:
//
//   LEVEL MEANS THE SAME NUMBER ON SCREEN. Every ranked surface prints a
//   rounded percent and each member divides by their own elapsed window, so
//   two rows both reading 86% are routinely 19/22 and 6/7. Grouping on the
//   raw double would have left the reported bug in place on the exact case
//   people notice.
//
//   0% IS NOT A PLACE. An unranked member (rank 0) draws a dash instead of a
//   position, which is what keeps a lobby, or day one, from rendering as a
//   column of trophies for work nobody has done yet.
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/features/rooms/models/room_model.dart';
import 'package:grow_daily_v2/features/rooms/screens/room_detail_screen.dart'
    show roomPodiumColumns;
import 'package:grow_daily_v2/features/rooms/notifiers/rooms_notifier.dart';

void main() {
  final start = DateTime(2026, 7, 1);
  // Deliberately in the past, so lastCountedDay is the end date and nothing
  // here drifts with the wall clock.
  final end = DateTime(2026, 7, 22);

  List<DateTime> daysFrom(DateTime from, DateTime to) => [
        for (var d = from; !d.isAfter(to); d = d.add(const Duration(days: 1)))
          d,
      ];

  RoomModel room() => RoomModel(
        code: 'A8GEL7',
        name: 'الإلتزام',
        createdBy: 'a',
        createdByName: 'A',
        createdAt: start,
        habitMode: RoomHabitMode.own,
        duration: RoomDuration.fixed,
        startDate: start,
        endDate: end,
      );

  /// A member asked for one habit on every day of their own window, who
  /// finished it on the first [done] of them.
  ///
  /// Every day carries a scheduled count on purpose: a day with none is a
  /// rest day and creditFor pays it a full 1.0, which would make every
  /// member in here perfect and every test below vacuous.
  RoomParticipant member(String uid, {required int done, DateTime? joined}) {
    final from = joined ?? start;
    final window = daysFrom(from, end);
    return RoomParticipant(
      uid: uid,
      displayName: uid,
      characterId: 'male_ghutra_blue',
      joinedAt: from,
      lastUpdated: end,
      linkedHabitIds: const ['h1'],
      linkedHabitNames: const ['تمرين'],
      dailyScheduledCount: {for (final d in window) d.toDateKey(): 1},
      dailyDoneCount: {
        for (final d in window.take(done)) d.toDateKey(): 1,
      },
    );
  }

  int rankOf(List<RoomStanding> board, String uid) =>
      board.firstWhere((m) => m.participant.uid == uid).rank;

  group('a shared first place', () {
    test('two level members are both first, and both get the cup', () {
      // 11 of 22 days each. The cup is drawn for rank 1 and nothing else,
      // so "both are rank 1" IS "both get the cup" - and that second half
      // is asserted for real, on the real widget, in
      // test/features/rooms/room_place_badge_test.dart.
      final board = room().standings([
        member('zoe', done: 11),
        member('ali', done: 11),
      ]);
      expect(board.map((m) => m.rank), [1, 1]);
    });

    test('the place after a two-way tie is 3, not 2', () {
      final board = room().standings([
        member('ali', done: 11),
        member('zoe', done: 11),
        member('omar', done: 5),
      ]);
      expect(rankOf(board, 'ali'), 1);
      expect(rankOf(board, 'zoe'), 1);
      // Competition places: the third member finished behind two people, so
      // they are third. A silver 2 that nobody holds is the correct shape.
      expect(rankOf(board, 'omar'), 3);
      expect(board.map((m) => m.rank).contains(2), isFalse);
    });

    test('a whole room that was perfect is a whole room of first places', () {
      final board = room().standings([
        member('ali', done: 22),
        member('zoe', done: 22),
        member('omar', done: 22),
      ]);
      expect(board.every((m) => m.rank == 1), isTrue);
    });

    test('rows are still in a stable order inside a tie, strongest first',
        () {
      // Same place, but the board is not allowed to reshuffle on every
      // stream rebuild, and the member who is fractionally ahead is drawn
      // first. List.sort is unstable above 32 elements, which is why the
      // uid key is still the last word.
      final board = room().standings([
        member('zoe', done: 6, joined: DateTime(2026, 7, 16)), // 6/7
        member('ali', done: 19), // 19/22, both read 86%
      ]);
      expect(board.map((m) => m.participant.uid), ['ali', 'zoe']);
    });
  });

  group('level means the same number on screen', () {
    test('19 of 22 days and 6 of 7 both read 86%, so both are first', () {
      // The case the raw-double version of this would have got wrong:
      // 0.8636 and 0.8571 are not equal, but every surface prints 86% for
      // both of them, so a single cup between them is the bug being fixed.
      final ali = member('ali', done: 19);
      final zoe = member('zoe', done: 6, joined: DateTime(2026, 7, 16));
      final r = room();
      expect((ali.progressRatio(r) * 100).round(), 86);
      expect((zoe.progressRatio(r) * 100).round(), 86);
      expect(ali.progressRatio(r) == zoe.progressRatio(r), isFalse);

      final board = r.standings([ali, zoe]);
      expect(board.map((m) => m.rank), [1, 1]);
    });

    test('a percentage that genuinely differs still separates places', () {
      final board = room().standings([
        member('ali', done: 22), // 100%
        member('zoe', done: 11), // 50%
      ]);
      expect(rankOf(board, 'ali'), 1);
      expect(rankOf(board, 'zoe'), 2);
    });
  });

  group('0% is not a place', () {
    test('a room where nobody has started has no places at all', () {
      // Day one, and every lobby. Without this the shared-place rule would
      // hand a cup to all six of them for having done nothing.
      final board = room().standings([
        member('ali', done: 0),
        member('zoe', done: 0),
        member('omar', done: 0),
      ]);
      expect(board.every((m) => m.rank == 0), isTrue);
    });

    test('a member still at 0% is unranked while the others keep theirs', () {
      final board = room().standings([
        member('ali', done: 22),
        member('zoe', done: 11),
        member('omar', done: 0),
      ]);
      expect(rankOf(board, 'ali'), 1);
      expect(rankOf(board, 'zoe'), 2);
      expect(rankOf(board, 'omar'), 0);
    });

    test('an ended room nobody competed in pays nobody', () {
      // podiumPrizeFor is a pure function of the place, so the floor above
      // is also what stops 200 XP and 100 gold being claimable for a room
      // in which nothing happened.
      final board = room().standings([
        member('ali', done: 0),
        member('zoe', done: 0),
      ]);
      for (final m in board) {
        expect(RoomsController.podiumPrizeFor(m.rank), isNull);
      }
    });
  });

  group('the prize follows the place that is drawn', () {
    test('two members level at the top are both paid a first prize', () {
      // The finale card cannot show two cups and then pay one of them a
      // runner-up prize. Stated here so the payout is a decision on the
      // record rather than a side effect.
      final board = room().standings([
        member('ali', done: 11),
        member('zoe', done: 11),
      ]);
      for (final m in board) {
        expect(RoomsController.podiumPrizeFor(m.rank), (xp: 200, gold: 100));
      }
    });

    test('a two-way tie for first means nobody is paid a second prize', () {
      final board = room().standings([
        member('ali', done: 11),
        member('zoe', done: 11),
        member('omar', done: 5),
      ]);
      final paid = [
        for (final m in board) RoomsController.podiumPrizeFor(m.rank),
      ];
      expect(paid.contains((xp: 120, gold: 60)), isFalse);
      expect(paid.last, (xp: 80, gold: 40));
    });
  });

  group('a tie says so, not just looks it', () {
    // First place is drawn as a cup instead of a number, so a shared first
    // is two identical pictures and a missing 2 with nothing explaining it.
    // shared is what the cup announces (S.roomPlaceFirstTied), on the row
    // while the room runs and on the podium once it has ended.
    test('both halves of a tie are marked shared', () {
      final board = room().standings([
        member('ali', done: 11),
        member('zoe', done: 11),
      ]);
      expect(board.every((m) => m.shared), isTrue);
    });

    test('a first place nobody is level with is not shared', () {
      final board = room().standings([
        member('ali', done: 22),
        member('zoe', done: 11),
      ]);
      expect(board.every((m) => m.shared), isFalse);
    });

    test('a tie further down the board is shared too', () {
      // 1, 2, 2. The lower two hold the same number, so the row that draws
      // a plain "2" twice can say why.
      final board = room().standings([
        member('ali', done: 22),
        member('zoe', done: 11),
        member('omar', done: 11),
      ]);
      expect(rankOf(board, 'zoe'), 2);
      expect(rankOf(board, 'omar'), 2);
      expect(board.where((m) => m.shared).length, 2);
    });

    test('an unranked member shares nothing, even with another unranked', () {
      // Nobody shares a place that nobody has. Without this, a lobby full
      // of 0% members would every one of them report a tie.
      final board = room().standings([
        member('ali', done: 0),
        member('zoe', done: 0),
      ]);
      expect(board.any((m) => m.shared), isFalse);
    });
  });

  group('the podium has three plinths and a tie can need more', () {
    // Places are shared, so a tie group can be wider than the podium. The
    // sharp edge is not the truncation itself, it is the claim button
    // directly underneath: a fourth co-first is paid a first prize by a
    // card that did not draw them among the winners.
    final r = room();

    List<String> namesOn(List<RoomStanding> board, String? myUid) =>
        [for (final m in roomPodiumColumns(board, myUid)) m.participant.uid];

    test('a small room draws everyone who has a place', () {
      final board = r.standings([
        member('ali', done: 22),
        member('zoe', done: 11),
      ]);
      expect(namesOn(board, 'zoe'), ['ali', 'zoe']);
    });

    test('a member with no place never stands on it', () {
      final board = r.standings([
        member('ali', done: 22),
        member('zoe', done: 11),
        member('omar', done: 0),
      ]);
      expect(namesOn(board, 'omar'), ['ali', 'zoe']);
    });

    test('the viewer takes the last column when they were cut off a tie', () {
      // Four members level at the top: all rank 1, all paid a first prize,
      // three plinths. Whoever is reading the card is one of the three.
      final board = r.standings([
        member('ali', done: 11),
        member('omar', done: 11),
        member('sara', done: 11),
        member('zoe', done: 11),
      ]);
      expect(board.every((m) => m.rank == 1), isTrue);
      // zoe sorts last on uid and would have been the one cut.
      expect(namesOn(board, null), ['ali', 'omar', 'sara']);
      expect(namesOn(board, 'zoe'), ['ali', 'omar', 'zoe']);
      // The places drawn are the same three either way: a co-holder
      // replaced a co-holder, nobody was promoted past anybody.
      expect(
        [for (final m in roomPodiumColumns(board, 'zoe')) m.rank],
        [1, 1, 1],
      );
    });

    test('it works the same for a tie further down', () {
      final board = r.standings([
        member('ali', done: 22), // 100%, rank 1
        member('omar', done: 11), // 50%, rank 2
        member('sara', done: 11), // 50%, rank 2
        member('zoe', done: 11), // 50%, rank 2
      ]);
      expect(namesOn(board, 'zoe'), ['ali', 'omar', 'zoe']);
      expect(
        [for (final m in roomPodiumColumns(board, 'zoe')) m.rank],
        [1, 2, 2],
      );
    });

    test('a genuine fourth place is NOT cut in, because it is not a place '
        'this podium draws', () {
      // No tie, no prize, no contradiction to fix. Putting them on the
      // podium would be the lie the swap exists to avoid.
      final board = r.standings([
        member('ali', done: 22),
        member('omar', done: 16),
        member('sara', done: 11),
        member('zoe', done: 5),
      ]);
      expect(namesOn(board, 'zoe'), ['ali', 'omar', 'sara']);
    });

    test('a viewer already on the podium is left where they are', () {
      final board = r.standings([
        member('ali', done: 22),
        member('omar', done: 16),
        member('sara', done: 11),
        member('zoe', done: 5),
      ]);
      expect(namesOn(board, 'omar'), ['ali', 'omar', 'sara']);
    });

    test('an unranked viewer is never cut in', () {
      final board = r.standings([
        member('ali', done: 22),
        member('omar', done: 16),
        member('sara', done: 11),
        member('zoe', done: 0),
      ]);
      expect(namesOn(board, 'zoe'), ['ali', 'omar', 'sara']);
    });
  });

  test('the percent that decides a place is the percent every surface prints',
      () {
    // The invariant the tie key rests on. standings groups places by
    // (progressRatio * 100).round(), and every surface that renders a
    // percentage rounds it again for itself: the leaderboard row, the
    // podium column, and the home-widget race snapshot. They agree because
    // they are the same expression, not because anything enforces it, and
    // if that ever drifts a board will show two rows reading 86% with one
    // cup between them, which is the exact bug this file exists for.
    final r = room();
    final members = [
      member('ali', done: 19),
      member('zoe', done: 6, joined: DateTime(2026, 7, 16)),
      member('omar', done: 11),
      member('sara', done: 0),
    ];
    for (final board in [r.standings(members)]) {
      for (final m in board) {
        final printed = (m.participant.progressRatio(r) * 100).round();
        // Same place for the same printed number, and no place at all for
        // a printed 0.
        if (printed == 0) {
          expect(m.rank, 0, reason: 'a row reading 0% has no place');
        } else {
          expect(
            board
                .where((o) =>
                    (o.participant.progressRatio(r) * 100).round() == printed)
                .map((o) => o.rank)
                .toSet(),
            {m.rank},
            reason: 'everyone printing $printed% must hold one place',
          );
        }
      }
    }
  });

  test('an empty room has an empty board', () {
    expect(room().standings(const []), isEmpty);
  });
}
