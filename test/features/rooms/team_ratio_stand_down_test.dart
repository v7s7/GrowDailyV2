// The team card must excuse the same days every member's own row excuses.
//
// The bug: teamProgressRatio divided a stand-down-aware numerator
// (daysCompleted, which drops paused days) by a stand-down-blind
// denominator (participants.length * daysElapsed, which does not). Two
// members each honestly reading 100% on their own rows produced a team card
// of 74%.
//
// The sharp edge was not the percentage, it was the bonus. teamIsPerfect is
// an all-history ">= 1.0" check and it gates the claim button, so one
// paused stretch made claimTeamBonus permanently unreachable for that room.
// It did not heal on resume either: the dead days sat in the denominator
// forever. Pausing a habit is supposed to hold a percentage still — it does
// on the member's own row, and the team card was the one surface still
// punishing it.
//
// Everything here drives the pure model, so it says WHY it failed rather
// than needing a room on screen.
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/features/rooms/models/room_model.dart';

void main() {
  final start = DateTime(2026, 7, 1);
  // A fixed "now" the room has been running toward, so nothing here drifts
  // with the wall clock.
  final today = DateTime(2026, 7, 21);

  RoomModel room() => RoomModel(
        code: 'A8GEL7',
        name: 'الإلتزااام',
        createdBy: 'leader',
        createdByName: 'Leader',
        createdAt: start,
        habitMode: RoomHabitMode.own,
        duration: RoomDuration.fixed,
        startDate: start,
        endDate: today,
      );

  /// A member who was perfect on every day in [doneDays] and stood down on
  /// every day in [standDown].
  RoomParticipant member(
    String uid, {
    required List<DateTime> doneDays,
    List<DateTime> standDown = const [],
    DateTime? joined,
  }) =>
      RoomParticipant(
        uid: uid,
        displayName: uid,
        characterId: 'male_ghutra_blue',
        joinedAt: joined ?? start,
        lastUpdated: today,
        linkedHabitIds: const ['h1'],
        linkedHabitNames: const ['تمرين'],
        dailyDoneCount: {for (final d in doneDays) d.toDateKey(): 1},
        dailyScheduledCount: {for (final d in doneDays) d.toDateKey(): 1},
        standDownDays: [for (final d in standDown) d.toDateKey()],
      );

  List<DateTime> daysFrom(DateTime from, DateTime to) => [
        for (var d = from; !d.isAfter(to); d = d.add(const Duration(days: 1)))
          d,
      ];

  test('a stood-down member does not drag the team below 100%', () {
    final r = room();
    final all = daysFrom(start, today);
    // A: perfect the whole way. B: perfect for the first ten days, then
    // paused their only habit and has been stood down since.
    final pauseFrom = DateTime(2026, 7, 11);
    final b = member(
      'b',
      doneDays: daysFrom(start, DateTime(2026, 7, 10)),
      standDown: daysFrom(pauseFrom, today),
    );
    final participants = [member('a', doneDays: all), b];

    // Both members are individually perfect — that is the premise, and if
    // it ever stops being true this test is measuring something else.
    for (final p in participants) {
      expect(p.progressRatio(r), 1.0,
          reason: '${p.uid} should read 100% on their own row');
    }

    expect(r.teamProgressRatio(participants), 1.0,
        reason: 'the team card must agree with the rows it is made of');
    expect(r.teamIsPerfect(participants), isTrue,
        reason: 'and the bonus must stay claimable');
  });

  test('the ceiling drops by exactly the stood-down days', () {
    final r = room();
    final all = daysFrom(start, today);
    final standDown = daysFrom(DateTime(2026, 7, 15), today); // 7 days
    final participants = [
      member('a', doneDays: all),
      member('b',
          doneDays: daysFrom(start, DateTime(2026, 7, 14)),
          standDown: standDown),
    ];

    final flat = participants.length * r.daysElapsed;
    final actual = r.teamMaxPossibleDays(participants);
    expect(actual, flat - standDown.length,
        reason: 'the ceiling must shed one day per member-day nobody was '
            'asked about, and nothing more');
  });

  test('a real miss still costs the team, so the fix cannot launder one', () {
    // The guard on the fix: excusing paused days must not excuse days the
    // member was asked about and did not do. Otherwise "hold the
    // percentage still" would quietly become "never lose points".
    final r = room();
    final all = daysFrom(start, today);
    final missed = DateTime(2026, 7, 12);
    final participants = [
      member('a', doneDays: all),
      member('b', doneDays: all.where((d) => d != missed).toList()),
    ];

    expect(r.teamProgressRatio(participants), lessThan(1.0),
        reason: 'a plain missed day must still pull the team down');
    expect(r.teamIsPerfect(participants), isFalse);
  });

  // ── The payout gate ────────────────────────────────────────────────
  //
  // teamIsPerfect unlocks 150 XP and 75 gold, so it is held to a stricter
  // bar than the display ratio. It was briefly derived from that ratio,
  // and these three tests are the reasons it is not: each one passed the
  // ratio at exactly 1.0 while describing a team that had not earned it.

  test('a day-one joiner cannot inherit the room and claim the bonus', () {
    // The exploit: join an already-perfect room, do one day, take the
    // bonus on the strength of other people's months. Repeatable, because
    // leaving deletes the participant doc that remembers the claim.
    final r = room();
    final participants = [
      member('veteran', doneDays: daysFrom(start, today)),
      member('newcomer', doneDays: [today], joined: today),
    ];

    expect(r.teamProgressRatio(participants), 1.0,
        reason: 'the display ratio is per-member by design and does read '
            '100% here — which is exactly why the gate must not be it');
    expect(r.teamIsPerfect(participants), isFalse,
        reason: 'a member who has been here one day has not been perfect '
            'since the room started');
  });

  test('one member cannot subsidise another member s miss', () {
    // Summing across members and clamping only the total let an overshoot
    // on one row cover a real miss on another. Asking each member
    // separately makes that unrepresentable.
    final r = room();
    final all = daysFrom(start, today);
    final overshoot = member('a', doneDays: all);
    final misser = member('b',
        doneDays: all.where((d) => d != DateTime(2026, 7, 9)).toList());

    expect(r.teamIsPerfect([overshoot, misser]), isFalse,
        reason: 'b missed a day they were asked about; no arithmetic on '
            "a's row may hide it");
  });

  test('a stood-down member still passes the gate', () {
    // The other half: pausing must not lock the bonus for the whole team
    // forever, which is the bug that started all of this.
    final r = room();
    final participants = [
      member('a', doneDays: daysFrom(start, today)),
      member('b',
          doneDays: daysFrom(start, DateTime(2026, 7, 10)),
          standDown: daysFrom(DateTime(2026, 7, 11), today)),
    ];
    expect(r.teamIsPerfect(participants), isTrue,
        reason: 'a paused stretch holds a percentage still; it must not '
            'permanently disqualify the team');
  });

  test('numerator and denominator agree, so the card cannot exceed itself',
      () {
    final r = room();
    final all = daysFrom(start, today);
    final participants = [
      member('a', doneDays: all),
      member('b',
          doneDays: daysFrom(start, DateTime(2026, 7, 5)),
          standDown: daysFrom(DateTime(2026, 7, 6), today)),
    ];
    // "14 of 20" and the bar must be the same fraction; a card whose two
    // halves came from different denominators is how this bug read on
    // screen in the first place.
    expect(
      r.teamDaysCompleted(participants),
      lessThanOrEqualTo(r.teamMaxPossibleDays(participants)),
      reason: 'the printed numbers must not exceed their own ceiling',
    );
  });
}
