// The team-day rules behind the cooperative room (RoomCompeteMode.team).
//
// One rule, pinned from every side: the team wins a day when everyone who
// was asked something that day finished it. Everything else here is the
// consequences of that one sentence meeting the excuses the rest of the
// model already grants (late joins, pauses, stand-downs, rest days), and
// the two guards that stop the milestones being farmed (today in progress
// is not a miss; a newcomer inherits nothing).
//
// Pure model throughout, same as team_ratio_stand_down_test.dart, so a
// failure says WHY rather than needing a room on screen.
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/features/rooms/models/room_model.dart';

void main() {
  final start = DateTime(2026, 7, 1);
  // An ENDED room, so lastCountedDay is the fixed end date and nothing
  // here drifts with the wall clock.
  final end = DateTime(2026, 7, 10);

  RoomModel room({List<({String from, String to})> paused = const []}) =>
      RoomModel(
        code: 'TEAM01',
        name: 'فريق',
        createdBy: 'a',
        createdByName: 'A',
        createdAt: start,
        habitMode: RoomHabitMode.own,
        duration: RoomDuration.fixed,
        startDate: start,
        endDate: end,
        competeMode: RoomCompeteMode.team,
        pausedSpans: paused,
      );

  RoomParticipant member(
    String uid, {
    required List<DateTime> doneDays,
    List<DateTime> standDown = const [],
    DateTime? joined,
    List<int> claims = const [],
  }) =>
      RoomParticipant(
        uid: uid,
        displayName: uid,
        characterId: 'male_ghutra_blue',
        joinedAt: joined ?? start,
        lastUpdated: end,
        linkedHabitIds: const ['h1'],
        linkedHabitNames: const ['تمرين'],
        dailyDoneCount: {for (final d in doneDays) d.toDateKey(): 1},
        // Scheduled every day of the room, done only on doneDays.
        dailyScheduledCount: {
          for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1)))
            d.toDateKey(): 1,
        },
        standDownDays: [for (final d in standDown) d.toDateKey()],
        teamStreakClaims: claims,
      );

  List<DateTime> days(DateTime from, DateTime to) => [
        for (var d = from; !d.isAfter(to); d = d.add(const Duration(days: 1)))
          d,
      ];

  group('one day', () {
    test('won when everyone who counted finished', () {
      final r = room();
      final all = days(start, end);
      final ps = [member('a', doneDays: all), member('b', doneDays: all)];
      expect(r.teamDayResult(start.toDateKey(), start, ps), isTrue);
    });

    test('lost when one member who counted did not', () {
      final r = room();
      final ps = [
        member('a', doneDays: days(start, end)),
        member('b', doneDays: const []),
      ];
      expect(r.teamDayResult(start.toDateKey(), start, ps), isFalse);
    });

    test('skipped, not lost, when nobody was asked', () {
      // A room pause excuses everyone, and a day before anyone joined
      // has nobody to ask.
      final r = room(paused: [(from: '2026-07-03', to: '2026-07-04')]);
      final ps = [member('a', doneDays: const [])];
      final paused = DateTime(2026, 7, 3);
      expect(r.teamDayResult(paused.toDateKey(), paused, ps), isNull);
      final late = member('b', doneDays: const [], joined: DateTime(2026, 7, 5));
      expect(
          room().teamDayResult(start.toDateKey(), start, [late]), isNull,
          reason: 'nobody had joined yet');
    });

    test('a stood-down member is excused, not counted as a miss', () {
      final r = room();
      final d = DateTime(2026, 7, 2);
      final ps = [
        member('a', doneDays: [d]),
        member('b', doneDays: const [], standDown: [d]),
      ];
      expect(r.teamDayResult(d.toDateKey(), d, ps), isTrue);
    });
  });

  group('streak and days', () {
    test('counts won days in a row, skipping days nobody was asked', () {
      // Won 1-3, room paused 4-5, won 6-10: a streak of 8, not 5.
      final r = room(paused: [(from: '2026-07-04', to: '2026-07-05')]);
      final won = [...days(start, DateTime(2026, 7, 3)), ...days(DateTime(2026, 7, 6), end)];
      final ps = [member('a', doneDays: won), member('b', doneDays: won)];
      expect(r.teamStreak(ps), 8);
      expect(r.teamDays(ps), (won: 8, counted: 8));
    });

    test('a miss ends the streak, and the count says how many were won', () {
      // Everyone perfect except b on the 7th.
      final r = room();
      final all = days(start, end);
      final ps = [
        member('a', doneDays: all),
        member('b', doneDays: [for (final d in all) if (d.day != 7) d]),
      ];
      expect(r.teamStreak(ps), 3, reason: '8th, 9th, 10th');
      expect(r.teamDays(ps), (won: 9, counted: 10));
    });

    test('while the room is live, an unfinished today is in progress', () {
      // A room still running: lastCountedDay is today, and today is not
      // yet won. Yesterday's streak has to stay on the card.
      final today = DateTime.now().effectiveDay;
      final from = today.subtract(const Duration(days: 4));
      final live = RoomModel(
        code: 'LIVE01',
        name: 'live',
        createdBy: 'a',
        createdByName: 'A',
        createdAt: from,
        habitMode: RoomHabitMode.own,
        duration: RoomDuration.open,
        startDate: from,
        competeMode: RoomCompeteMode.team,
      );
      final past = days(from, today.subtract(const Duration(days: 1)));
      RoomParticipant m(String uid, List<DateTime> done) => RoomParticipant(
            uid: uid,
            displayName: uid,
            characterId: 'male_ghutra_blue',
            joinedAt: from,
            lastUpdated: today,
            linkedHabitIds: const ['h1'],
            linkedHabitNames: const ['تمرين'],
            dailyDoneCount: {for (final d in done) d.toDateKey(): 1},
            dailyScheduledCount: {
              for (final d in [...past, today]) d.toDateKey(): 1,
            },
          );
      final ps = [m('a', past), m('b', past)];
      expect(live.teamStreak(ps), 4,
          reason: 'today is not a miss until it closes');
      // ...and the moment everyone finishes today, it counts.
      final done = [m('a', [...past, today]), m('b', [...past, today])];
      expect(live.teamStreak(done), 5);
    });
  });

  group('milestones', () {
    test('a newcomer inherits nothing from the streak before them', () {
      final r = room();
      final all = days(start, end);
      final late = member('c', doneDays: days(DateTime(2026, 7, 9), end),
          joined: DateTime(2026, 7, 9));
      final ps = [member('a', doneDays: all), member('b', doneDays: all), late];
      expect(r.teamStreak(ps), 10, reason: 'the team itself never missed');
      expect(r.teamBestStreakWith(ps[0], ps), 10);
      expect(r.teamBestStreakWith(late, ps), 2,
          reason: 'only the two days c was actually asked');
    });

    test('the team-wide longest run ignores who was in it', () {
      final r = room();
      final all = days(start, end);
      final ps = [
        member('a', doneDays: all),
        member('b', doneDays: [for (final d in all) if (d.day != 4) d]),
      ];
      // Won 1-3, lost 4, won 5-10: longest run is 6.
      expect(r.teamBestStreak(ps), 6);
    });

    test('prizes and the next target', () {
      expect(RoomTeamProgress.teamMilestones, [7, 14, 30]);
      expect(RoomTeamProgress.teamMilestonePrize(7), (xp: 60, gold: 30));
      expect(RoomTeamProgress.teamMilestonePrize(30), (xp: 250, gold: 125));
      expect(RoomTeamProgress.teamMilestonePrize(9).xp, 0,
          reason: 'only the three milestones pay');
      expect(RoomTeamProgress.teamNextMilestone(0), 7);
      expect(RoomTeamProgress.teamNextMilestone(7), 14);
      expect(RoomTeamProgress.teamNextMilestone(30), isNull);
    });

    test('claims never ride the whole-document write', () {
      // Only claimTeamStreakBonus's arrayUnion may write this field. If it
      // sat in toFirestore(), any future merge built from a stale snapshot
      // could carry an older list over a claim that just landed, and pay
      // the same milestone twice.
      final m = member('a', doneDays: const [], claims: const [7, 14]);
      expect(m.toFirestore().containsKey('teamStreakClaims'), isFalse);
      expect(m.copyWith(teamStreakClaims: const [7, 14, 30]).teamStreakClaims,
          [7, 14, 30]);
    });

    test('a member\'s current run is theirs, not the team\'s', () {
      // Team perfect all ten days; c joined on the 9th. The team streak is
      // ten, c's own run is two, so c's "days to go" to 7 is five, not none.
      final r = room();
      final all = days(start, end);
      final late = member('c', doneDays: days(DateTime(2026, 7, 9), end),
          joined: DateTime(2026, 7, 9));
      final ps = [member('a', doneDays: all), member('b', doneDays: all), late];
      expect(r.teamStreak(ps), 10);
      expect(r.teamStreakWith(late, ps), 2);
      expect(r.teamStreakWith(ps[0], ps), 10);
    });
  });
}
