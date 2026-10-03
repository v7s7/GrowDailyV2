import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/rooms/models/room_model.dart';
import 'package:grow_daily_v2/features/rooms/models/room_strip_day.dart';
import 'package:grow_daily_v2/features/rooms/notifiers/rooms_notifier.dart'
    show roomRaceStripEnd, roomRaceStripFor;

/// Parity pins for the per-instance day memo on RoomParticipant
/// (room_model.dart, _DayMemo): [RoomParticipant.scheduledCountFor],
/// recordedScheduledCountFor, countedHabitCountOn and wasObservedOn keyed by
/// the date key; phantomWeightOn by the room instance and the date key;
/// dayIsCountableAt by the clock and the date key; and the conceded-days
/// walk by the room instance and its last counted day. Each key has a test
/// of its own below: two rooms alternating on one instance, both sides of
/// the 10:00 cutoff, and one room's own clock moved across midnight and on
/// (_ClockedRoom), the only way a test can move RoomModel.lastCountedDay.
///
/// The memo must not change one answer. Two checks say so:
///  * GOLDEN. Every answer the board, the strips and the Room Race widget
///    read, over the fixture matrix below, digested and FROZEN from the code
///    as it stood before the memo landed (2026-09-30). The questions are
///    asked of long-lived instances in an interleaved order, rooms and clocks
///    alternating, so once the memo is in most answers come out of it. Never
///    regenerate these: a changed digest is a changed number on somebody's
///    board.
///  * WARM AGAINST FRESH. The same questions, each asked of the long-lived
///    instance and of a fresh `copyWith()` (an empty memo), must agree
///    exactly, doubles included.
///
/// Every room here has ENDED before the day these were frozen, so the
/// wall-clock reads inside the walks (RoomModel.lastCountedDay) land on the
/// room's own end day whenever the suite runs, or on _ClockedRoom's own
/// clock; every other clock is passed in. The digests assume a device zone
/// with no daylight saving change between June and October 2026 (they were
/// frozen on Asia/Riyadh, +03:00).

DateTime _d(int month, int day, [int hour = 0, int minute = 0, int s = 0]) =>
    DateTime(2026, month, day, hour, minute, s);
String _k(int month, int day) => _d(month, day).toDateKey();

({String from, String to}) _span(int m1, int d1, int m2, int d2) =>
    (from: _k(m1, d1), to: _k(m2, d2));

/// A small fixed generator, so the fixtures (and with them the frozen
/// digests) never depend on the SDK's own Random.
class _Rng {
  _Rng(int seed) : _s = seed & 0x7fffffff;
  int _s;
  int next(int max) {
    _s = (_s * 1103515245 + 12345) & 0x7fffffff;
    return (_s >> 8) % max;
  }

  bool chance(int oneIn) => next(oneIn) == 0;
}

RoomHabitTemplate _slot(
  String name, {
  bool weekly = false,
  int target = 1,
  DateTime? addedAt,
  String? addedDay,
  DateTime? removedAt,
  String? stopsOn,
  List<({String from, String to})> offSpans = const [],
}) =>
    RoomHabitTemplate(
      name: name,
      category: HabitCategory.faith,
      frequencyType:
          weekly ? HabitFrequencyType.weekly : HabitFrequencyType.daily,
      frequencyTarget: target,
      addedAt: addedAt,
      addedDay: addedDay,
      removedAt: removedAt,
      removedBy: removedAt == null ? null : 'leader',
      stopsOn: stopsOn,
      offSpans: offSpans,
    );

RoomModel _room(
  String code, {
  List<RoomHabitTemplate> slots = const [],
  required DateTime start,
  required DateTime end,
  List<({String from, String to})> paused = const [],
}) =>
    RoomModel(
      code: code,
      name: code,
      createdBy: 'leader',
      createdByName: 'L',
      createdAt: start,
      habitMode: slots.isEmpty ? RoomHabitMode.own : RoomHabitMode.shared,
      sharedHabits: slots,
      duration: RoomDuration.fixed,
      startDate: start,
      endDate: end,
      pausedSpans: paused,
    );

RoomHabitRule _daily(String from) => RoomHabitRule(
      from: from,
      frequencyType: HabitFrequencyType.daily,
      frequencyTarget: 1,
    );

RoomHabitRule _weekly(String from, int target) => RoomHabitRule(
      from: from,
      frequencyType: HabitFrequencyType.weekly,
      frequencyTarget: target,
    );

/// Per-day records drawn from [rng] over [from]..[to]: a day is done (1 to
/// [slots] habits), half done, fully rested, or blank, and some days carry an
/// explicit scheduled count.
({
  Map<String, int> done,
  Map<String, int> partial,
  Map<String, int> rested,
  Map<String, int> sched,
}) _days(
  _Rng rng,
  DateTime from,
  DateTime to,
  int slots, {
  int schedOneIn = 5,
}) {
  final done = <String, int>{};
  final partial = <String, int>{};
  final rested = <String, int>{};
  final sched = <String, int>{};
  for (var d = from; !d.isAfter(to); d = DateTime(d.year, d.month, d.day + 1)) {
    final key = d.toDateKey();
    final roll = rng.next(10);
    if (roll < 5) done[key] = 1 + rng.next(slots < 1 ? 1 : slots);
    if (roll == 5) partial[key] = 1;
    if (roll == 6) rested[key] = slots < 1 ? 1 : slots;
    if (schedOneIn > 0 && rng.chance(schedOneIn)) {
      sched[key] = rng.next(slots + 1);
    }
  }
  return (done: done, partial: partial, rested: rested, sched: sched);
}

/// One fixture: a roster, the rooms it is scored against (distinct
/// instances, so the room-bound memo is rebound as they alternate), the
/// clocks it is read at, and the days asked about.
class _Scenario {
  _Scenario(this.name, this.rooms, this.roster, this.nows, this.days);
  final String name;
  final List<RoomModel> rooms;
  final List<RoomParticipant> roster;
  final List<DateTime> nows;
  final List<DateTime> days;
}

List<DateTime> _dayRange(DateTime from, DateTime to) => [
      for (var d = from;
          !d.isAfter(to);
          d = DateTime(d.year, d.month, d.day + 1))
        d,
    ];

/// The roster as gradedRoomParticipantsProvider hands it to the board: each
/// member with the three board-only inferences applied at [gradeNow], kept
/// beside the member as recorded.
List<RoomParticipant> _withGraded(
  List<RoomParticipant> members,
  RoomModel room,
  DateTime gradeNow,
) {
  final out = <RoomParticipant>[];
  for (final p in members) {
    out.add(p);
    final g = p
        .withClosedQuotaWeeksInferred(room, now: gradeNow)
        .withUnsyncedPlanInferred(room, now: gradeNow)
        .withUnsyncedQuotaRestInferred(room, now: gradeNow);
    if (!identical(g, p)) out.add(g);
  }
  return out;
}

/// A shared room of three slots (two daily, one 4x-a-week quota), an
/// extended copy with the dead days paused, and an edited copy with a slot
/// removed, a slot's off stretch, and two late additions (one stamped with
/// its day, one keyed from its instant only). Members cover a declined slot
/// with and without a date and a prior habit, a closed declined window, an
/// undated legacy decline (read from lastUpdated), a late joiner with a
/// late-linked habit, a relinked slot, away days, a departure, stand-downs,
/// declared rests with the weekly allowance, and every watermark shape.
_Scenario _planScenario() {
  final start = _d(7, 4);
  final end = _d(8, 29);
  final base = [
    _slot('a'),
    _slot('b'),
    _slot('q', weekly: true, target: 4),
  ];
  final room = _room('PLAN01', slots: base, start: start, end: end);
  final extended = _room(
    'PLAN01',
    slots: base,
    start: start,
    end: _d(9, 19),
    paused: [_span(8, 30, 9, 2)],
  );
  final edited = _room(
    'PLAN01',
    slots: [
      base[0],
      _slot('b', removedAt: _d(8, 10, 15), stopsOn: _k(8, 11)),
      _slot('q', weekly: true, target: 4, offSpans: [_span(8, 15, 8, 18)]),
      _slot('late-instant', addedAt: _d(7, 20, 23, 30)),
      _slot(
        'late-day',
        weekly: true,
        target: 2,
        addedAt: _d(8, 3, 21),
        addedDay: _k(8, 4),
      ),
    ],
    start: start,
    end: end,
  );
  final rng = _Rng(7);
  final window = (from: _d(7, 1), to: _d(9, 22));

  RoomParticipant member({
    required String uid,
    required List<String> ids,
    required Map<String, List<RoomHabitRule>> rules,
    DateTime? joinedAt,
    String? restFrom,
    List<String> okWeeks = const [],
    List<String> standDown = const [],
    List<({String from, String to})> away = const [],
    DateTime? leftAt,
    Map<int, String> declinedFrom = const {},
    Map<int, List<({String from, String to})>> declinedSpans = const {},
    Map<int, String> prior = const {},
    Map<int, List<({String habitId, String until})>> history = const {},
    String? syncedDay,
    DateTime? syncedAt,
    required DateTime lastUpdated,
    int schedOneIn = 5,
    bool allRestOnMondays = false,
  }) {
    final days = _days(
      rng,
      window.from,
      window.to,
      ids.length,
      schedOneIn: schedOneIn,
    );
    final rested = {...days.rested};
    final done = {...days.done};
    final partial = {...days.partial};
    if (allRestOnMondays) {
      for (final d in _dayRange(window.from, window.to)) {
        if (d.weekday != DateTime.monday) continue;
        final key = d.toDateKey();
        rested[key] = ids.length;
        done.remove(key);
        partial.remove(key);
      }
    }
    return RoomParticipant(
      uid: uid,
      displayName: uid,
      characterId: 'male_ghutra_blue',
      joinedAt: joinedAt ?? _d(7, 3, 20),
      linkedHabitIds: ids,
      dailyDoneCount: done,
      dailyPartialCount: partial,
      dailyRestedCount: rested,
      dailyScheduledCount: days.sched,
      habitRules: rules,
      restAllowanceFrom: restFrom,
      quotaOkWeeks: okWeeks,
      standDownDays: standDown,
      awaySpans: away,
      leftAt: leftAt,
      slotDeclinedFrom: declinedFrom,
      slotDeclinedSpans: declinedSpans,
      slotPriorHabitIds: prior,
      slotHabitHistory: history,
      lastSyncedDay: syncedDay,
      lastSyncedAt: syncedAt,
      lastUpdated: lastUpdated,
    );
  }

  final members = [
    member(
      uid: 'm0-full',
      ids: const ['a0', 'a1', 'a2'],
      rules: {
        'a0': [_daily(_k(7, 4))],
        'a1': [_daily(_k(7, 4))],
        'a2': [_weekly(_k(7, 4), 4), _weekly(_k(8, 8), 3)],
      },
      restFrom: _k(7, 10),
      okWeeks: [_k(7, 11), _k(8, 1), _k(8, 15)],
      standDown: [_k(7, 22), _k(7, 23)],
      syncedDay: _k(8, 20),
      syncedAt: _d(8, 20, 9, 30),
      lastUpdated: _d(8, 20, 9, 30),
    ),
    member(
      uid: 'm1-declined',
      ids: const ['b0', kDeclinedSlot, 'b2'],
      rules: {
        'b0': [_daily(_k(7, 4))],
        'b1old': [_daily(_k(7, 4))],
        'b2': [_weekly(_k(7, 4), 4)],
      },
      declinedFrom: {1: _k(7, 20)},
      prior: {1: 'b1old'},
      declinedSpans: {
        0: [_span(7, 10, 7, 12)],
      },
      syncedDay: _k(8, 15),
      lastUpdated: _d(8, 15, 22),
    ),
    member(
      uid: 'm2-legacy-decline',
      ids: const ['c0', kDeclinedSlot, 'c2'],
      rules: {
        'c0': [_daily(_k(7, 4))],
        'c2': [_weekly(_k(7, 4), 4)],
      },
      okWeeks: [_k(7, 25)],
      syncedDay: _k(8, 25),
      syncedAt: _d(8, 25, 11),
      lastUpdated: _d(8, 5, 13),
    ),
    member(
      uid: 'm3-late',
      ids: const ['d0', 'd1'],
      rules: {
        'd0prev': [_daily(_k(7, 15))],
        'd0': [_daily(_k(7, 21))],
        'd1': [_daily(_k(7, 25))],
      },
      joinedAt: _d(7, 15, 16),
      away: [_span(8, 1, 8, 5)],
      history: {
        0: [(habitId: 'd0prev', until: _k(7, 20))],
      },
      syncedDay: _k(8, 28),
      syncedAt: _d(8, 28, 12),
      lastUpdated: _d(8, 28, 12),
    ),
    member(
      uid: 'm4-nosync',
      ids: const ['e0', 'e1', 'e2'],
      rules: const {},
      leftAt: _d(8, 20, 18),
      lastUpdated: _d(8, 20, 18),
      schedOneIn: 0,
    ),
    member(
      uid: 'm5-rester',
      ids: const ['f0', 'f1', 'f2'],
      rules: {
        'f0': [_daily(_k(7, 4))],
        'f1': [_daily(_k(7, 4))],
        'f2': [_weekly(_k(7, 4), 4)],
      },
      restFrom: _k(7, 4),
      syncedDay: _k(8, 29),
      syncedAt: _d(8, 30, 10),
      lastUpdated: _d(8, 30, 10),
      allRestOnMondays: true,
    ),
  ];
  return _Scenario(
    'plan',
    [room, extended, edited],
    _withGraded(members, edited, _d(8, 26, 12)),
    [
      // The cutoff boundary on the morning after 08-10, both sides of it.
      _d(8, 11, 9, 59, 59),
      _d(8, 11, 10),
      // The room's last day, still open, then closed.
      _d(8, 30, 9),
      _d(9, 28, 12),
    ],
    _dayRange(_d(7, 1), _d(9, 21)),
  );
}

/// A daily habit removed from a daily-plus-quota plan, read by a board whose
/// member has not synced since: unsyncedPlanInference and
/// unsyncedQuotaRestInference both answer here.
_Scenario _removedDailyScenario() {
  final start = _d(7, 4);
  final end = _d(9, 12);
  final room = _room(
    'REMD01',
    slots: [
      _slot('daily', removedAt: _d(8, 11, 18), stopsOn: _k(8, 12)),
      _slot('quota', weekly: true, target: 3),
    ],
    start: start,
    end: end,
  );
  final roomKept = _room(
    'REMD01',
    slots: [
      _slot('daily'),
      _slot('quota', weekly: true, target: 3),
    ],
    start: start,
    end: end,
  );
  final rng = _Rng(11);
  RoomParticipant member(String uid, {required bool sessions}) {
    final done = <String, int>{};
    for (final d in _dayRange(start, _d(8, 12))) {
      if (rng.next(3) != 0) done[d.toDateKey()] = 1 + rng.next(2);
    }
    if (sessions) {
      for (final day in [15, 17, 19, 22, 23, 24, 29, 30]) {
        done[_k(8, day)] = 1;
      }
    }
    return RoomParticipant(
      uid: uid,
      displayName: uid,
      characterId: 'male_ghutra_blue',
      joinedAt: _d(7, 2),
      linkedHabitIds: const ['g0', 'g1'],
      dailyDoneCount: done,
      habitRules: {
        'g0': [_daily(_k(7, 4))],
        'g1': [_weekly(_k(7, 4), 3)],
      },
      quotaOkWeeks: [_k(8, 15), _k(8, 22), _k(8, 29)],
      lastSyncedDay: _k(8, 13),
      lastSyncedAt: _d(8, 13, 12),
      lastUpdated: _d(8, 13, 12),
    );
  }

  final members = [
    member('m6-quota-met', sessions: true),
    member('m7-quiet', sessions: false),
  ];
  return _Scenario(
    'removed-daily',
    [room, roomKept],
    _withGraded(members, room, _d(9, 5, 12)),
    [_d(8, 20, 9, 59, 59), _d(8, 20, 10), _d(9, 13, 9, 30), _d(9, 28, 12)],
    _dayRange(_d(7, 1), _d(9, 14)),
  );
}

/// An own-mode room on one 4x-a-week quota whose week of 08-01 closed short
/// after the member's last sync: closedQuotaWeekInference answers here.
_Scenario _closedWeekScenario() {
  final start = _d(7, 4);
  final room = _room('CLWK01', start: start, end: _d(9, 19));
  final shorter = _room('CLWK01', start: start, end: _d(8, 22));
  final done = <String, int>{
    _k(7, 4): 1,
    _k(7, 6): 1,
    _k(7, 8): 1,
    _k(7, 9): 1,
    _k(7, 13): 1,
    _k(7, 20): 1,
    _k(7, 21): 1,
    _k(8, 1): 1,
    _k(8, 3): 1,
  };
  final p = RoomParticipant(
    uid: 'm8-closed-week',
    displayName: 'm8',
    characterId: 'male_ghutra_blue',
    joinedAt: _d(7, 1),
    linkedHabitIds: const ['q'],
    dailyDoneCount: done,
    habitRules: {
      'q': [_weekly(_k(7, 4), 4)],
    },
    quotaOkWeeks: [_k(7, 4)],
    restAllowanceFrom: _k(7, 4),
    lastSyncedDay: _k(8, 7),
    lastSyncedAt: _d(8, 7, 20),
    lastUpdated: _d(8, 7, 20),
  );
  return _Scenario(
    'closed-week',
    [room, shorter],
    _withGraded([p], room, _d(8, 12, 12)),
    [_d(8, 8, 9, 59, 59), _d(8, 8, 10), _d(8, 12, 12), _d(9, 28, 12)],
    _dayRange(_d(7, 1), _d(9, 21)),
  );
}

/// Seeded breadth: random plans (daily, quota, late, removed and off
/// slots, with and without an addedDay), random members, an ended room
/// against an extended copy with its dead days paused.
_Scenario _randomScenario(int seed) {
  final r = _Rng(1000 + seed);
  final n = r.next(5); // 0 is an own-mode room
  final slots = <RoomHabitTemplate>[
    for (var i = 0; i < n; i++)
      () {
        final weekly = r.chance(3);
        final late = r.chance(3);
        final addedAt = late
            ? _d(7, 1 + r.next(40), r.next(24), r.next(60))
            : null;
        final stamped = late && r.next(2) == 0;
        final removed = r.chance(4);
        final removedAt =
            removed ? _d(7, 5 + r.next(50), r.next(24)) : null;
        final a = r.next(60);
        return _slot(
          's$i',
          weekly: weekly,
          target: weekly ? 1 + r.next(6) : 1,
          addedAt: addedAt,
          addedDay: stamped ? addedAt!.toDateKey() : null,
          removedAt: removedAt,
          stopsOn: removed && r.next(2) == 0
              ? DateTime(removedAt!.year, removedAt.month, removedAt.day + 1)
                  .toDateKey()
              : null,
          offSpans: [
            if (r.chance(4))
              (
                from: _d(7, 1 + a).toDateKey(),
                to: _d(7, 1 + a + r.next(6)).toDateKey(),
              ),
          ],
        );
      }(),
  ];
  final start = _d(7, 1 + r.next(10));
  final end = _d(8, 10 + r.next(30));
  final paused = [
    if (r.chance(3)) _span(7, 20 + r.next(5), 7, 26 + r.next(3)),
  ];
  final room = _room(
    'RND$seed',
    slots: slots,
    start: start,
    end: end,
    paused: paused,
  );
  final extEnd = DateTime(end.year, end.month, end.day + 5 + r.next(10));
  final extended = _room(
    'RND$seed',
    slots: slots,
    start: start,
    end: extEnd.isAfter(_d(9, 25)) ? _d(9, 25) : extEnd,
    paused: [
      ...paused,
      (
        from: DateTime(end.year, end.month, end.day + 1).toDateKey(),
        to: DateTime(end.year, end.month, end.day + 3).toDateKey(),
      ),
    ],
  );

  RoomParticipant member(int m) {
    final linkedN = n == 0 ? 1 : r.next(n + 1);
    final linked = [
      for (var i = 0; i < linkedN; i++) r.chance(4) ? kDeclinedSlot : 'h$m$i',
    ];
    final days = _days(r, _d(7, 1), _d(9, 22), linkedN);
    final rules = <String, List<RoomHabitRule>>{
      for (final id in linked)
        if (id != kDeclinedSlot && !r.chance(5))
          id: [
            RoomHabitRule(
              from: _k(7, 1 + r.next(30)),
              frequencyType: r.chance(3)
                  ? HabitFrequencyType.weekly
                  : HabitFrequencyType.daily,
              frequencyTarget: 1 + r.next(5),
            ),
          ],
    };
    return RoomParticipant(
      uid: 'u$seed-$m',
      displayName: 'x',
      characterId: 'male_ghutra_blue',
      joinedAt: _d(7, 1 + r.next(20), r.next(24)),
      linkedHabitIds: linked,
      dailyDoneCount: days.done,
      dailyPartialCount: days.partial,
      dailyRestedCount: days.rested,
      dailyScheduledCount: days.sched,
      standDownDays: [
        for (final d in _dayRange(_d(7, 1), _d(9, 22)))
          if (r.chance(12)) d.toDateKey(),
      ],
      habitRules: rules,
      restAllowanceFrom: r.next(2) == 0 ? _k(7, 1 + r.next(40)) : null,
      quotaOkWeeks: [
        for (var w = _d(6, 27); w.isBefore(_d(9, 26)); w = w.add(
          const Duration(days: 7),
        ))
          if (r.next(2) == 0) w.toDateKey(),
      ],
      awaySpans: [if (r.chance(4)) _span(8, 1 + r.next(10), 8, 12)],
      leftAt: r.chance(8) ? _d(8, 1 + r.next(40)) : null,
      slotDeclinedFrom: {
        for (var i = 0; i < linked.length; i++)
          if (linked[i] == kDeclinedSlot && r.next(2) == 0)
            i: _k(7, 1 + r.next(50)),
      },
      slotDeclinedSpans: {
        if (n > 0 && r.chance(4)) 0: [_span(7, 5 + r.next(20), 7, 28)],
      },
      slotPriorHabitIds: {
        for (var i = 0; i < linked.length; i++)
          if (linked[i] == kDeclinedSlot && r.next(2) == 0) i: 'old$m$i',
      },
      lastSyncedDay: r.next(2) == 0 ? _k(7, 10 + r.next(60)) : null,
      lastSyncedAt:
          r.next(2) == 0 ? _d(7, 10 + r.next(60), r.next(24)) : null,
      lastUpdated: _d(7, 10 + r.next(60), r.next(24)),
    );
  }

  final members = [member(0), member(1), member(2)];
  final gradeNow = DateTime(end.year, end.month, end.day - 3, 14);
  return _Scenario(
    'random-$seed',
    [room, extended],
    _withGraded(members, room, gradeNow),
    [
      DateTime(end.year, end.month, end.day - 6, 9, 59, 59),
      DateTime(end.year, end.month, end.day - 6, 10),
      _d(9, 28, 12),
    ],
    _dayRange(_d(7, 1), _d(9, 26)),
  );
}

List<_Scenario> _scenarios() => [
      _planScenario(),
      _removedDailyScenario(),
      _closedWeekScenario(),
      for (var seed = 0; seed < 40; seed++) _randomScenario(seed),
    ];

String _strip(RoomStripDay s) => '${s.credit}|${s.isStoodDown ? 1 : 0}'
    '${s.isRest ? 1 : 0}${s.isDeclaredRest ? 1 : 0}${s.isMissed ? 1 : 0}'
    '${s.isPending ? 1 : 0}';

/// One question: its label, and how to answer it with each participant
/// resolved through [pick] (the long-lived instance itself, or a fresh
/// copy of it).
typedef _Question = ({
  String label,
  String Function(RoomParticipant Function(RoomParticipant) pick) ask,
});

/// Every question the board, the strips, the day card and the Room Race
/// widget put to a participant, in the order the race snapshot asks them
/// (standings, then each row), then day by day.
List<_Question> _questions(_Scenario s) {
  final out = <_Question>[];
  void add(
    String label,
    String Function(RoomParticipant Function(RoomParticipant) pick) ask,
  ) =>
      out.add((label: label, ask: ask));
  for (var ri = 0; ri < s.rooms.length; ri++) {
    final room = s.rooms[ri];
    add(
      '${s.name} r$ri standings',
      (pick) => room
          .standings([for (final p in s.roster) pick(p)])
          .map((x) => '${x.participant.uid}:${x.rank}:${x.shared}')
          .join(','),
    );
    for (var ni = 0; ni < s.nows.length; ni++) {
      final now = s.nows[ni];
      final end = roomRaceStripEnd(room, now);
      final todayKey = room.lastCountedDayAt(now).toDateKey();
      for (var pi = 0; pi < s.roster.length; pi++) {
        final base = s.roster[pi];
        final tag = '${s.name} r$ri n$ni p$pi(${base.uid})';
        add('$tag row', (pick) {
          final p = pick(base);
          return [
            p.roomDaysCompleted(room, now: now),
            p.roomProgressRatio(room, now: now),
            p.roomDaysElapsedIn(room, now: now),
            p.currentStreak(room, now: now),
            p.isStoodDownOn(todayKey),
            p.isFullyDone(todayKey),
            roomRaceStripFor(room, p, end: end, now: now),
          ].join(' ');
        });
        add('$tag own', (pick) {
          final p = pick(base);
          return [
            p.progressRatio(room, now: now),
            p.daysElapsedIn(room, now: now),
            p.daysCompleted(room, now: now),
          ].join(' ');
        });
        for (final day in s.days) {
          final key = day.toDateKey();
          add('$tag $key day', (pick) {
            final p = pick(base);
            return [
              p.dayIsCountableAt(key, now),
              _strip(roomStripDayOf(room, p, day, now: now)),
              p.quotaWeekIsLost(key, room, now: now),
            ].join(' ');
          });
        }
      }
    }
    for (var pi = 0; pi < s.roster.length; pi++) {
      final base = s.roster[pi];
      final tag = '${s.name} r$ri p$pi(${base.uid})';
      add(
        '$tag conceded',
        (pick) =>
            (pick(base).concededDaysIn(room).toList()..sort()).join(','),
      );
      for (final day in s.days) {
        final key = day.toDateKey();
        add('$tag $key room', (pick) {
          final p = pick(base);
          return [
            p.phantomWeightOn(room, key),
            p.phantomSlotsOn(room, key),
            p.ownPlanWeightOn(room, key),
            p.roomCreditFor(room, key),
          ].join(' ');
        });
      }
    }
  }
  for (var pi = 0; pi < s.roster.length; pi++) {
    final base = s.roster[pi];
    final tag = '${s.name} p$pi(${base.uid})';
    add('$tag inferred', (pick) {
      final p = pick(base);
      String sorted(Map<String, int> m) =>
          (m.keys.toList()..sort()).map((k) => '$k=${m[k]}').join(',');
      return [
        sorted(p.inferredScheduledCount),
        sorted(p.planInferredScheduledCount),
        (p.unsyncedQuotaRestDays.toList()..sort()).join(','),
      ].join(' ');
    });
    for (final day in s.days) {
      final key = day.toDateKey();
      add('$tag $key record', (pick) {
        final p = pick(base);
        return [
          p.scheduledCountFor(key),
          p.recordedScheduledCountFor(key),
          p.countedHabitCountOn(key),
          p.wasObservedOn(key),
          p.creditFor(key),
          p.isRestDay(key),
          p.isFullyDone(key),
          p.isDeclaredRest(key),
          p.scheduledWeightFor(key),
        ].join(' ');
      });
    }
  }
  return out;
}

/// [questions] in a fixed shuffled order, so the same long-lived instance
/// is asked about one room, then another, at one clock, then another.
List<int> _interleaved(int count, int seed) {
  final order = [for (var i = 0; i < count; i++) i];
  final r = _Rng(seed);
  for (var i = count - 1; i > 0; i--) {
    final j = r.next(i + 1);
    final t = order[i];
    order[i] = order[j];
    order[j] = t;
  }
  return order;
}

/// 64-bit FNV-1a over every answer, in question order.
String _digest(List<String> answers) {
  var h = 0xcbf29ce484222325;
  for (final a in answers) {
    for (final u in a.codeUnits) {
      h = (h ^ u) * 0x100000001b3;
    }
    h = (h ^ 0x0a) * 0x100000001b3;
  }
  String hex(int word) => word.toRadixString(16).padLeft(8, '0');
  return hex((h >> 32) & 0xffffffff) + hex(h & 0xffffffff);
}

/// A two-habit member of [_simpleRoom] with one slot left unresolved: a
/// full day on 08-09, half a day on 08-12, a stored count on 08-13, and a
/// whole-plan rest on three days the weekly allowance can spend.
RoomParticipant _simple({DateTime? syncedAt, String? syncedDay}) =>
    RoomParticipant(
      uid: 'simple',
      displayName: 's',
      characterId: 'male_ghutra_blue',
      joinedAt: _d(7, 30, 18),
      linkedHabitIds: const ['x', 'y'],
      dailyDoneCount: {_k(8, 9): 2, _k(8, 12): 1},
      dailyScheduledCount: {_k(8, 13): 1},
      dailyRestedCount: {_k(8, 17): 2, _k(8, 24): 2, _k(9, 7): 2},
      habitRules: {
        'x': [_daily(_k(8, 1))],
        'y': [_weekly(_k(8, 1), 3)],
      },
      restAllowanceFrom: _k(8, 1),
      lastSyncedDay: syncedDay,
      lastSyncedAt: syncedAt,
      lastUpdated: _d(8, 12, 9),
    );

/// Three slots, the third unresolved by [_simple]; [edited] removes it from
/// 08-10, [extended] runs the room on to 09-19 with its dead days paused.
RoomModel _simpleRoom({bool edited = false, bool extended = false}) => _room(
      'SIMPLE',
      slots: [
        _slot('x'),
        _slot('y', weekly: true, target: 3),
        edited
            ? _slot('z', removedAt: _d(8, 9, 20), stopsOn: _k(8, 10))
            : _slot('z'),
      ],
      start: _d(8, 1),
      end: extended ? _d(9, 19) : _d(8, 29),
      paused: extended ? [_span(8, 30, 9, 2)] : const [],
    );

/// [_simpleRoom] with its wall clock in the test's hands: [lastCountedDay]
/// reads [clock] where a real room reads DateTime.now(). That read is the
/// one the kept conceded days are keyed on, so moving [clock] is the day
/// turning under one room instance, with nothing else about the room moved.
class _ClockedRoom extends RoomModel {
  _ClockedRoom(this.clock)
      : super(
          code: 'CLOCKED',
          name: 'CLOCKED',
          createdBy: 'leader',
          createdByName: 'L',
          createdAt: _d(8, 1),
          habitMode: RoomHabitMode.shared,
          sharedHabits: [
            _slot('x'),
            _slot('y', weekly: true, target: 3),
            _slot('z'),
          ],
          duration: RoomDuration.fixed,
          startDate: _d(8, 1),
          endDate: _d(8, 29),
        );

  DateTime clock;

  @override
  DateTime get lastCountedDay => lastCountedDayAt(clock);
}

RoomParticipant _same(RoomParticipant p) => p;
RoomParticipant _fresh(RoomParticipant p) => p.copyWith();

/// Frozen from the code before the memo (see the file comment). Each entry
/// is the digest of every answer and how many questions it covers.
///
/// Fifteen moved on purpose on 2026-10-03, not by the memo: random-4, 7,
/// 12, 13, 16, 17, 20, 21, 22, 25, 29, 31, 34, 37 and 39. Their members have
/// quota weeks whose recorded sessions already hold every place, which the
/// record, the board's rest for an edited plan and the strip now read as
/// the member's own phone grades them (RoomParticipant._quotaWeekPlacesHeld,
/// unsyncedQuotaRestInference, roomStripQuotaDemandOn): blank days a sync
/// never observed rest, and blank days left due are no longer crossed out.
/// Every changed answer was diffed against the code before: each is one of
/// those days turning from due to rest or from crossed to plain, or a total
/// that follows, and no day turned the other way.
const _goldens = <String, String>{
  'plan': '67e04dea900c8f9d/9495',
  'removed-daily': '12317cb3049ec215/3422',
  'closed-week': 'edcf7999e571961a/1866',
  'random-0': '76f0d1dec664f325/2423',
  'random-1': '841f6fa2a4239d27/2423',
  'random-2': '1bb8b586cae797b8/2423',
  'random-3': 'ed0a4cef3dc75a4d/2423',
  'random-4': 'e539d704005bb8de/3230',
  'random-5': '36493cd5c5348823/2423',
  'random-6': 'dab2690700f7bae8/2423',
  'random-7': 'b0c6006e7ba3ff44/3230',
  'random-8': '7fe287f893862073/4037',
  'random-9': '627d6a8adb1ec79a/2423',
  'random-10': '76a0431052cacd96/2423',
  'random-11': 'd391adac8e07744a/2423',
  'random-12': '8b81f370daf8025b/2423',
  'random-13': 'b210498a5e585efe/2423',
  'random-14': '9120db006f7c0d71/2423',
  'random-15': 'b77d5758570fede1/2423',
  'random-16': '518e2b3dda57f117/2423',
  'random-17': '43827eba91623197/4037',
  'random-18': 'e6cf2bbfd80c6acc/2423',
  'random-19': 'eb521cec9b6df14b/2423',
  'random-20': '41057dd40e629ddc/2423',
  'random-21': '288452e190bfc693/2423',
  'random-22': 'e01212513fb64bb0/2423',
  'random-23': '76c75b560080e80c/2423',
  'random-24': '8d0e552572e363eb/2423',
  'random-25': 'cfad105db17fdd80/2423',
  'random-26': 'b12fa2863c27a62f/2423',
  'random-27': '49d3a25ae25cb2e8/2423',
  'random-28': '12b09be89fd9f1b7/3230',
  'random-29': 'd1d7404a79f515c9/2423',
  'random-30': 'a73c48737b6c6291/3230',
  'random-31': '283d8832b8727cd9/2423',
  'random-32': '42118e4e27969136/3230',
  'random-33': 'f137165c22dd4d9e/2423',
  'random-34': '2fda51f8d5abdc03/3230',
  'random-35': 'fa525d7adb573b23/2423',
  'random-36': '7c3af0d05f381a38/4844',
  'random-37': 'b4659ba5abb284b4/2423',
  'random-38': '8516b44b72eb07e2/4037',
  'random-39': '32952b70157f889e/2423',
};

void main() {
  group('RoomParticipant day memo parity', () {
    test('the fixtures reach every path the memo covers', () {
      final all = _scenarios();
      final roster = [for (final s in all) ...s.roster];
      expect(
        roster.any((p) => p.inferredScheduledCount.isNotEmpty),
        isTrue,
        reason: 'closedQuotaWeekInference answered somewhere',
      );
      expect(
        roster.any((p) => p.planInferredScheduledCount.isNotEmpty),
        isTrue,
        reason: 'unsyncedPlanInference answered somewhere',
      );
      expect(
        roster.any((p) => p.unsyncedQuotaRestDays.isNotEmpty),
        isTrue,
        reason: 'unsyncedQuotaRestInference answered somewhere',
      );
      var conceded = false;
      var phantom = false;
      var observed = false;
      var unobserved = false;
      var pending = false;
      for (final s in all) {
        for (final room in s.rooms) {
          for (final p in s.roster) {
            if (p.concededDaysIn(room).isNotEmpty) conceded = true;
            for (final day in s.days) {
              final key = day.toDateKey();
              if (p.phantomWeightOn(room, key) > 0) phantom = true;
              if (p.wasObservedOn(key)) {
                observed = true;
              } else {
                unobserved = true;
              }
              if (!p.dayIsCountableAt(key, s.nows.first)) pending = true;
            }
          }
        }
      }
      expect(conceded, isTrue, reason: 'a rest allowance was spent');
      expect(phantom, isTrue, reason: 'an unlinked slot weighed something');
      expect(observed && unobserved, isTrue);
      expect(pending, isTrue, reason: 'a day was not countable yet');
    });

    test('every answer matches the frozen goldens', () {
      final digests = <String, String>{};
      for (final s in _scenarios()) {
        final qs = _questions(s);
        final answers = List<String>.filled(qs.length, '');
        final seed =
            s.name.codeUnits.fold(0, (a, b) => (a * 31 + b) & 0xffff);
        for (final i in _interleaved(qs.length, seed)) {
          answers[i] = qs[i].ask(_same);
        }
        digests[s.name] = '${_digest(answers)}/${qs.length}';
      }
      expect(digests, _goldens);
    });

    test('an inferred copy answers its own counts, not the warm ones', () {
      final p = _simple(syncedAt: _d(8, 12, 12));
      final key = _k(8, 10);
      expect(p.scheduledCountFor(key), 2);
      expect(p.recordedScheduledCountFor(key), 2);
      final inferred = p.copyWith(inferredScheduledCount: {key: 0});
      expect(inferred.scheduledCountFor(key), 0);
      expect(inferred.recordedScheduledCountFor(key), 2);
      expect(inferred.asRecorded.scheduledCountFor(key), 2);
      expect(p.copyWith(unsyncedQuotaRestDays: {key}).scheduledCountFor(key), 0);
      expect(
        p.copyWith(planInferredScheduledCount: {key: 1}).scheduledCountFor(key),
        1,
      );
      expect(p.scheduledCountFor(key), 2);
      expect(p.scheduledCountFor(_k(8, 13)), 1);
    });

    test('one instance scored against two rooms keeps each room its own', () {
      final p = _simple(syncedAt: _d(8, 12, 12));
      final room = _simpleRoom();
      final edited = _simpleRoom(edited: true);
      final key = _k(8, 15);
      final now = _d(9, 28, 12);
      for (var i = 0; i < 3; i++) {
        expect(p.phantomWeightOn(room, key), 1.0);
        expect(p.phantomWeightOn(edited, key), 0.0);
        expect(p.phantomWeightOn(room, _k(8, 5)), 1.0);
        expect(p.phantomWeightOn(edited, _k(8, 5)), 1.0);
        expect(p.roomDaysElapsedIn(room, now: now), 27);
        expect(p.roomDaysElapsedIn(edited, now: now), 27);
        expect(p.roomProgressRatio(room, now: now), 0.0326797385620915);
        expect(p.roomProgressRatio(edited, now: now), 0.04030501089324618);
      }
    });

    test('an ended room and its extended copy keep their own conceded days',
        () {
      final p = _simple(syncedAt: _d(8, 12, 12));
      final ended = _simpleRoom();
      final extended = _simpleRoom(extended: true);
      final now = _d(9, 28, 12);
      for (var i = 0; i < 3; i++) {
        expect(p.concededDaysIn(ended), {_k(8, 17), _k(8, 24)});
        expect(p.daysElapsedIn(ended, now: now), 27);
        expect(p.progressRatio(ended, now: now), 0.05555555555555555);
        expect(p.concededDaysIn(extended), {_k(8, 17), _k(8, 24), _k(9, 7)});
        expect(p.daysElapsedIn(extended, now: now), 43);
        expect(p.progressRatio(extended, now: now), 0.03488372093023256);
        expect(p.roomDaysElapsedIn(extended, now: now), 43);
      }
    });

    test("the conceded days follow one room instance's last counted day", () {
      // The same room instance while its day turns: 08-24 is a declared rest
      // the weekly allowance spends. Midnight makes it the last counted day,
      // and by 08-27 it is closed and conceded, so conceded days kept from
      // 08-20 (walked only to that day) would leave it in the denominator.
      // Frozen from the code before the memo.
      final p = _simple(syncedAt: _d(8, 12, 12));
      final room = _ClockedRoom(_d(8, 20, 12));
      String read(RoomParticipant q, DateTime now) => [
            (q.concededDaysIn(room).toList()..sort()).join(','),
            q.daysElapsedIn(room, now: now),
            q.progressRatio(room, now: now),
            q.roomDaysElapsedIn(room, now: now),
            q.roomProgressRatio(room, now: now),
          ].join(' ');
      final frozen = <DateTime, String>{
        _d(8, 20, 12): '2026-08-17 18 0.08333333333333333 18 '
            '0.04901960784313725',
        _d(8, 24): '2026-08-17,2026-08-24 21 0.07142857142857142 21 '
            '0.04201680672268907',
        _d(8, 27, 12): '2026-08-17,2026-08-24 24 0.0625 24 '
            '0.036764705882352935',
      };
      for (var i = 0; i < 3; i++) {
        for (final e in frozen.entries) {
          room.clock = e.key;
          expect(read(p, e.key), e.value, reason: '${e.key}');
          expect(read(p.copyWith(), e.key), e.value, reason: '${e.key}');
        }
      }
    });

    test('the 10:00 cutoff answers on each side of it, alternating', () {
      final p = _simple(syncedAt: _d(8, 12, 12));
      final room = _simpleRoom();
      final before = _d(8, 11, 9, 59, 59);
      final at = _d(8, 11, 10);
      final blank = _d(8, 10);
      for (var i = 0; i < 3; i++) {
        expect(p.dayIsCountableAt(blank.toDateKey(), before), isFalse);
        expect(p.dayIsCountableAt(_k(8, 9), before), isTrue);
        expect(roomStripDayOf(room, p, blank, now: before).isPending, isTrue);
        expect(p.dayIsCountableAt(blank.toDateKey(), at), isTrue);
        expect(p.dayIsCountableAt(_k(8, 9), at), isTrue);
        expect(roomStripDayOf(room, p, blank, now: at).isPending, isFalse);
        expect(p.dayIsCountableAt(_k(8, 11), at), isFalse);
      }
    });

    test('a malformed key fails on every call, as it always did', () {
      final synced = _simple(syncedAt: _d(8, 12, 12));
      for (var i = 0; i < 3; i++) {
        expect(() => synced.wasObservedOn('bad'), throwsFormatException);
        expect(() => synced.scheduledCountFor('bad'), throwsFormatException);
        expect(
          () => synced.recordedScheduledCountFor('bad'),
          throwsFormatException,
        );
      }
      final dayOnly = _simple(syncedDay: _k(8, 12));
      for (var i = 0; i < 3; i++) {
        expect(dayOnly.wasObservedOn('bad'), isFalse);
        expect(dayOnly.scheduledCountFor('bad'), 2);
        expect(dayOnly.dayIsCountableAt('bad', _d(8, 11, 10)), isTrue);
      }
    });

    test('a long-lived instance answers as a fresh copy does', () {
      var checked = 0;
      final mismatches = <String>[];
      for (final s in _scenarios()) {
        final qs = _questions(s);
        for (final i in _interleaved(qs.length, 77 + qs.length)) {
          final q = qs[i];
          final warm = q.ask(_same);
          final fresh = q.ask(_fresh);
          if (warm != fresh && mismatches.length < 20) {
            mismatches.add('${q.label}: $warm != $fresh');
          }
          checked++;
        }
      }
      expect(mismatches, isEmpty);
      expect(checked, greaterThan(10000));
    });
  });
}
