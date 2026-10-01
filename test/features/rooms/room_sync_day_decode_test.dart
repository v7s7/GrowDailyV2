// The room grader decodes each day document once per sync, and grades
// exactly as it did when it decoded one per question.
//
// syncLinkedHabitsProgress asked a day's snapshot for its data() inside every
// isGreen, isPartial and isSkipped call, and once more for the day's
// lastUpdated, and cloud_firestore copies the whole document on each of them
// (the fake deep-copies too). A regular habit asked up to 8 times on a blank
// day, so the copies grew with habits x days x document size: 778 for about
// 51 graded days in a 4-habit room, and 13,794 for the 851 days the month
// below grades, measured on 2026-09-30. Now it is 851. It also asked
// whether a habit was running that day (countedOn) in pass 1, again in the
// stand-down loop and, for a weekly habit, twice more in pass 2. Both answers
// are now worked out once per sync.
//
// Nothing a member sees may move. This drives the REAL controller over the
// fake Firestore through a month of evenings, in two rooms that share one
// member's day documents and between them reach every branch those reads
// feed:
//  * room A: a daily slot relinked from a habit since deleted, a Mon/Wed/Fri
//    habit paused and resumed (two stints), a 4x weekly quota, a 3x weekly
//    quota the leader removed on a Sunday (a week cut by the plan), a slot
//    declined with its prior habit deleted (graded by its squares), a daily
//    slot added mid-room whose habit's birth date was overwritten (the stint
//    repair), and a 2x weekly slot added later still. Its daily habit has no
//    stints at all (habitExistedOn's fallback);
//  * room B: a daily habit and a weekly quota both paused for the same five
//    days (the stand-down loop), one of them still paused;
//  * weeks that hold and weeks that fail on exactly the plan-cut clamp in
//    pass 2, in both directions;
//  * the day documents: every SquareState, a missing habit key, a value that
//    is no state at all, squareStates that is a string, a list and an empty
//    map, a day with no document, lastUpdated before and after the 10:00
//    close and missing, and squares back-painted after their day was graded;
//  * a grace-day row (todaySquares with liveDay), a today row, and one pass
//    where both rooms share a RoomDayReads, so each sync decodes its own
//    copy of the same snapshot.
// Every participant document the grader wrote is pinned to a digest frozen
// from the grader as it was before the change, and never regenerated.
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/rooms/models/room_model.dart';
import 'package:grow_daily_v2/features/rooms/notifiers/room_day_reads.dart';

import 'room_sync_harness.dart';

DateTime _d(int day, [int hour = 0, int minute = 0]) =>
    DateTime(2026, 7, day, hour, minute);

String _k(int day) => _d(day).toDateKey();

const _daily = HabitFrequencyType.daily;
const _weekly = HabitFrequencyType.weekly;

IslamicHabitTemplate _habit(
  String id, {
  HabitFrequencyType type = _daily,
  int target = 1,
  List<int> weekdays = const [],
  DateTime? createdAt,
  DateTime? archivedAt,
}) =>
    IslamicHabitTemplate(
      id: id,
      name: id,
      description: '',
      category: HabitCategory.faith,
      frequencyType: type,
      frequencyTarget: target,
      scheduledWeekdays: weekdays,
      hasTimer: false,
      xpReward: 10,
      goldReward: 5,
      createdAt: createdAt,
      archivedAt: archivedAt,
    );

RoomHabitTemplate _slot(
  String name, {
  HabitFrequencyType type = _daily,
  int target = 1,
  String? addedDay,
  String? stopsOn,
}) =>
    RoomHabitTemplate(
      name: name,
      category: HabitCategory.faith,
      frequencyType: type,
      frequencyTarget: target,
      addedAt: addedDay == null ? null : DateTime.parse(addedDay),
      addedDay: addedDay,
      removedAt: stopsOn == null ? null : _d(12, 21),
      removedBy: stopsOn == null ? null : 'L',
      stopsOn: stopsOn,
    );

/// Saturday 4 July to Friday 31 July 2026: four whole Saturday weeks, over
/// whenever the suite runs.
final _roomA = RoomModel(
  code: 'GOLDA1',
  name: 'A',
  createdBy: 'L',
  createdByName: 'L',
  createdAt: _d(4),
  habitMode: RoomHabitMode.shared,
  duration: RoomDuration.fixed,
  startDate: _d(4),
  endDate: _d(31),
  sharedHabits: [
    _slot('قراءة القرآن'),
    _slot('صيام'),
    _slot('تمرين', type: _weekly, target: 4),
    // Removed on Sunday 12 July, so it stops on Monday the 13th: the week of
    // Saturday 11 July is cut to two days, fewer than its target.
    _slot('مشي', type: _weekly, target: 3, stopsOn: _k(13)),
    _slot('صدقة'),
    _slot('أذكار', addedDay: _k(14)),
    _slot('سباحة', type: _weekly, target: 2, addedDay: _k(21)),
  ],
);

/// Saturday 11 July to Friday 31 July 2026.
final _roomB = RoomModel(
  code: 'GOLDB1',
  name: 'B',
  createdBy: 'L',
  createdByName: 'L',
  createdAt: _d(11),
  habitMode: RoomHabitMode.shared,
  duration: RoomDuration.fixed,
  startDate: _d(11),
  endDate: _d(31),
  sharedHabits: [
    _slot('ذكر'),
    _slot('جري', type: _weekly, target: 3),
  ],
);

final _memberA = RoomParticipant(
  uid: 'M',
  displayName: 'M',
  characterId: 'male_ghutra_blue',
  joinedAt: _d(4),
  linkedHabitIds: const [
    'm-q',
    'm-mwf',
    'm-w4',
    'm-w3',
    kDeclinedSlot,
    'm-late',
    'm-lw',
  ],
  linkedHabitNames: const [
    'قراءة القرآن',
    'صيام',
    'تمرين',
    'مشي',
    'صدقة',
    'أذكار',
    'سباحة',
  ],
  lastUpdated: _d(4),
  // «صدقة» declined from Saturday 11 July; m-old filled it before, and has
  // since been deleted from the Grid.
  slotDeclinedFrom: {4: _k(11)},
  slotPriorHabitIds: const {4: 'm-old'},
  // «قراءة القرآن» was m-q0 (since deleted) until Tuesday 7 July.
  slotHabitHistory: {
    0: [(habitId: 'm-q0', until: _k(7))],
  },
);

final _memberB = RoomParticipant(
  uid: 'M',
  displayName: 'M',
  characterId: 'male_ghutra_blue',
  joinedAt: _d(11),
  linkedHabitIds: const ['m-pz', 'm-pw'],
  linkedHabitNames: const ['ذكر', 'جري'],
  lastUpdated: _d(11),
);

final _active = [
  // No stints: habitExistedOn from its birth on Monday 6 July.
  _habit('m-q', createdAt: _d(6)),
  _habit(
    'm-mwf',
    weekdays: const [DateTime.monday, DateTime.wednesday, DateTime.friday],
  ),
  _habit('m-w4', type: _weekly, target: 4),
  _habit('m-w3', type: _weekly, target: 3),
  _habit('m-late'),
  _habit('m-lw', type: _weekly, target: 2, createdAt: _d(21)),
  _habit('m-pz', createdAt: _d(1)),
];

/// Paused on Sunday 26 July and not resumed.
final _paused = [
  _habit('m-pw', type: _weekly, target: 3, createdAt: _d(1), archivedAt: _d(26)),
];

final Map<String, List<(DateTime?, DateTime?)>> _stints = {
  // Paused from Thursday 9 to Sunday 12 July.
  'm-mwf': [(_d(1), _d(8)), (_d(13), null)],
  // Claims to be born on Monday 20 July, six days after its slot joined the
  // plan: the room's rule (from the 14th) is the floor the repair restores.
  'm-late': [(_d(20), null)],
  // Room B's whole plan paused from Thursday 16 to Monday 20 July.
  'm-pz': [(_d(1), _d(15)), (_d(21), null)],
  'm-pw': [(_d(1), _d(15)), (_d(21), _d(26))],
};

const _states = [
  SquareState.complete,
  SquareState.bonus,
  SquareState.partial,
  SquareState.skipped,
  SquareState.failed,
  SquareState.none,
];

/// Every habit the day documents carry: the ones the two rooms grade, and
/// two neither links, since a real day holds more than one room asks about.
const _dayHabits = [
  'm-q0',
  'm-q',
  'm-mwf',
  'm-w4',
  'm-w3',
  'm-old',
  'm-late',
  'm-lw',
  'm-pz',
  'm-pw',
  'x-1',
  'x-2',
];

/// Day [day]'s document as the Grid would have left it, or null for a day
/// with none. Every habit walks through every state over six days, and some
/// days have no key for it at all.
Map<String, Object?>? _dayDocument(int day) {
  if (day == 9) return null;
  final squares = <String, Object?>{
    for (var j = 0; j < _dayHabits.length; j++)
      if ((day + 2 * j) % 7 != 0)
        _dayHabits[j]: _states[(5 * day + 3 * j) % 6].toJson(),
  };
  // The quotas. Room A holds a week only when every weekly habit in it
  // does: the week of 4 July on its own targets, the week of 11 July only
  // because the plan cut m-w3's week to two days (its target clamps to 2),
  // and the week of 18 July with m-lw, added on the 21st. In room B, m-pw
  // holds the week of 11 July, and its pause does NOT clamp the weeks of 18
  // and 25 July: two sessions on the two days it was running is 2 of 3.
  const greens = {
    'm-w4': {4, 5, 7, 8, 11, 12, 14, 15, 18, 19, 21, 23},
    'm-w3': {4, 5, 7, 11, 12},
    'm-lw': {22, 23},
    'm-pw': {11, 13, 14, 21, 23, 25, 26},
  };
  for (final e in greens.entries) {
    if (e.value.contains(day)) squares[e.key] = 'complete';
  }
  switch (day) {
    // Values that are no state at all.
    case 13:
      squares['m-q'] = 'weird';
      squares['m-mwf'] = 2;
      squares['m-w4'] = null;
    // Room B's paused stretch: trained on the 17th, half a session on the
    // 19th, a rest on the 18th, nothing on the 16th and 20th.
    case 16:
      squares['m-pz'] = 'none';
      squares.remove('m-pw');
    case 17:
      squares['m-pz'] = 'complete';
      squares['m-pw'] = 'none';
    case 18:
      squares['m-pz'] = 'skipped';
      squares['m-pw'] = 'skipped';
    case 19:
      squares['m-pz'] = 'none';
      squares['m-pw'] = 'partial';
    case 20:
      squares.remove('m-pz');
      squares.remove('m-pw');
  }
  final Object stored = switch (day) {
    6 => 'broken',
    28 => const ['complete', 'partial'],
    30 => const <String, Object?>{},
    _ => squares,
  };
  final stamp = _stampOf(day);
  return {
    'squareStates': stored,
    'squareNotes': {'m-q': 'note $day'},
    'flatPaid': {
      for (final id in _dayHabits) id: {'xp': 10, 'gold': 5},
    },
    if (stamp != null) 'lastUpdated': Timestamp.fromDate(stamp),
  };
}

/// When the store last stamped day [day]: that evening, the next morning
/// after the 10:00 close (a late mark), the next morning inside the grace
/// tail, or never.
DateTime? _stampOf(int day) {
  if (day == 22) return null;
  if (day % 5 == 0) return _d(day + 1, 11);
  if (const {8, 17, 24}.contains(day)) return _d(day + 1, 9);
  return _d(day, 20);
}

/// The fields the profile write omits while the character is still loading
/// from Hive. When that load lands is real I/O, not the grader.
const _loadingFields = {'characterId', 'gender', 'accessoryId'};

Object? _plain(Object? v) {
  if (v is Timestamp) return 'ts ${v.toDate().toIso8601String()}';
  if (v is Map) {
    final keys = [for (final k in v.keys) k as String]..sort();
    return {for (final k in keys) k: _plain(v[k])};
  }
  if (v is List) return [for (final e in v) _plain(e)];
  return v;
}

String _digest(String canonical) =>
    sha256.convert(utf8.encode(canonical)).toString().substring(0, 16);

/// One sync the scenario ran: what it left in the room's participant
/// document, how many day documents it fetched and decoded (with the counter
/// on), and how many days it graded. The shared pass is one step per room,
/// and each of the two carries the whole pass's counts, both rooms'.
typedef _Step = ({
  String label,
  String doc,
  int fetches,
  int decodes,
  int days,
});

/// Runs the whole month and returns every sync in order.
Future<List<_Step>> _drive({bool countDayReads = false}) async {
  final h = RoomSyncHarness(
    room: _roomA,
    uid: 'M',
    habits: _active,
    paused: _paused,
    stints: _stints,
    countDayReads: countDayReads,
  );
  addTearDown(h.dispose);
  await h.createRoom();
  await h.join(_memberA);
  final roomBDoc = h.db.collection('rooms').doc(_roomB.code);
  final memberBDoc = roomBDoc.collection('participants').doc('M');
  await roomBDoc.set(_roomB.toFirestore());
  await memberBDoc.set(_memberB.toFirestore());

  final steps = <_Step>[];
  final reads = h.dayDocReads;

  DocumentReference<Map<String, dynamic>> docOf(RoomModel room) =>
      room.code == _roomA.code ? h.memberDoc : memberBDoc;

  Future<int> daysGraded(RoomModel room, DateTime at) async {
    final member = RoomParticipant.fromFirestore(await docOf(room).get());
    final from = member.countedStartIn(room);
    final to = room.lastCountedDayAt(at);
    return DateTime.utc(to.year, to.month, to.day)
            .difference(DateTime.utc(from.year, from.month, from.day))
            .inDays +
        1;
  }

  Future<void> record(String label, List<RoomModel> rooms, int days) async {
    for (final room in rooms) {
      final data = (await docOf(room).get()).data()!;
      for (final f in _loadingFields) {
        data.remove(f);
      }
      steps.add(
        (
          label: '${room.code == _roomA.code ? 'A' : 'B'} $label',
          doc: jsonEncode(_plain(data)),
          fetches: reads?.fetches ?? 0,
          decodes: reads?.decodes ?? 0,
          days: days,
        ),
      );
    }
    reads?.reset();
  }

  Future<void> sync(
    RoomModel room,
    DateTime at,
    String label, {
    Map<String, SquareState>? row,
    DateTime? liveDay,
  }) async {
    h.setClock(at);
    final days = await daysGraded(room, at);
    reads?.reset();
    await h.controller.syncLinkedHabitsProgress(
      room,
      todaySquares: row,
      liveDay: liveDay,
    );
    await record(label, [room], days);
  }

  Future<void> paint(int day) async {
    final doc = _dayDocument(day);
    if (doc != null) await h.dayDoc(_k(day)).set(doc);
  }

  Future<void> backPaint(
    int day,
    Map<String, SquareState> squares,
    DateTime at,
  ) =>
      h.dayDoc(_k(day)).set(
        {
          'squareStates': {
            for (final e in squares.entries) e.key: e.value.toJson(),
          },
          'lastUpdated': Timestamp.fromDate(at),
        },
        SetOptions(merge: true),
      );

  for (var day = 4; day <= 31; day++) {
    await paint(day);
    if (day == 14) {
      // Friday the 10th coloured in four days late: the room had watched it.
      await backPaint(
        10,
        {
          for (final id in ['m-q', 'm-mwf', 'm-w4', 'm-w3', 'm-old'])
            id: SquareState.complete,
        },
        _d(14, 12),
      );
    }
    if (day == 18) {
      // Yesterday's squares, still in flight to Firestore, in the grace tail.
      await sync(
        _roomA,
        _d(18, 8),
        '07-18 08:00 row for 07-17',
        row: const {
          'm-q': SquareState.complete,
          'm-mwf': SquareState.partial,
          'm-w4': SquareState.skipped,
          'm-late': SquareState.bonus,
          'm-lw': SquareState.failed,
        },
        liveDay: _d(17),
      );
      // The row empties a trained day of room B's paused stretch.
      await sync(
        _roomB,
        _d(18, 8, 5),
        '07-18 08:05 row for 07-17',
        row: const {
          'm-pz': SquareState.none,
          'm-pw': SquareState.skipped,
        },
        liveDay: _d(17),
      );
      // Today's own row, the weekly-quota detour.
      await sync(
        _roomA,
        _d(18, 20),
        '07-18 20:00 row for today',
        row: const {
          'm-q': SquareState.partial,
          'm-w4': SquareState.complete,
          'm-late': SquareState.skipped,
        },
      );
    }
    if (day == 21) {
      // Thursday the 16th un-ticked five days later.
      await backPaint(
        16,
        const {'m-q': SquareState.none, 'm-mwf': SquareState.none},
        _d(21, 13),
      );
    }
    if (day == 25) {
      // Friday the 24th marked in its grace tail, then both rooms graded in
      // one pass: the closed days are read once and handed to both.
      await backPaint(
        24,
        const {'m-w4': SquareState.complete, 'm-pz': SquareState.complete},
        _d(25, 8, 30),
      );
      final at = _d(25, 9);
      h.setClock(at);
      final days =
          await daysGraded(_roomA, at) + await daysGraded(_roomB, at);
      reads?.reset();
      final shared = RoomDayReads<DocumentSnapshot<Map<String, dynamic>>>('M');
      await h.controller.syncLinkedHabitsProgress(_roomA, dayReads: shared);
      await h.controller.syncLinkedHabitsProgress(_roomB, dayReads: shared);
      await record('07-25 09:00 shared pass', [_roomA, _roomB], days);
    }
    if (day == 27) {
      // Sunday the 26th is graded after its 10:00 close, and only then do two
      // marks made at 09:30 in its grace tail reach Firestore: on time, so
      // the clamp stands aside for them.
      await sync(_roomA, _d(27, 10, 30), '07-27 10:30');
      await sync(_roomB, _d(27, 10, 35), '07-27 10:35');
      await backPaint(
        26,
        const {'m-q': SquareState.complete, 'm-pz': SquareState.complete},
        _d(27, 9, 30),
      );
    }
    await sync(_roomA, _d(day, 22), '${_k(day).substring(5)} 22:00');
    if (day >= 11) {
      await sync(_roomB, _d(day, 22, 5), '${_k(day).substring(5)} 22:05');
    }
  }
  // The last day's grace tail, then both rooms ended.
  for (final room in [_roomA, _roomB]) {
    await sync(room, DateTime(2026, 8, 1, 8), '08-01 08:00');
    await sync(room, DateTime(2026, 8, 2, 12), '08-02 12:00');
  }
  return steps;
}

/// Frozen from the grader before the change, and never regenerated. Each
/// entry is the first 16 hex digits of the SHA-256 of the room's whole
/// participant document after that sync (keys sorted, timestamps as local
/// ISO, the character fields left out, see [_loadingFields]).
const Map<String, String> _frozen = {
  'A 07-04 22:00': 'af1b27b30ba23588',
  'A 07-05 22:00': '4c1f46406a46adf4',
  'A 07-06 22:00': '6eb846c1727811f9',
  'A 07-07 22:00': '40aaba54caa1bfff',
  'A 07-08 22:00': '1dcb9f66a468ae0b',
  'A 07-09 22:00': '5987fa3fa623ded7',
  'A 07-10 22:00': '60fb02492f0160f6',
  'A 07-11 22:00': '4a23d335dc151072',
  'B 07-11 22:05': '4110af23e11349f3',
  'A 07-12 22:00': 'ecfc0e3e145d3161',
  'B 07-12 22:05': 'edd97fbc84ce5a28',
  'A 07-13 22:00': '0aa10cac3326005c',
  'B 07-13 22:05': '68bbd65d0c545b75',
  'A 07-14 22:00': 'ae02496a4a2cd184',
  'B 07-14 22:05': 'ff9e578c0f155f4e',
  'A 07-15 22:00': '4f990d43396bf9a7',
  'B 07-15 22:05': '43abc45d96459787',
  'A 07-16 22:00': '8adbbfcd992eb47f',
  'B 07-16 22:05': 'de39ef1060b54d97',
  'A 07-17 22:00': '9d97b7a9381450af',
  'B 07-17 22:05': 'b88ba0eb4cc4ee80',
  'A 07-18 08:00 row for 07-17': 'c7ffbd4bb0ccf67e',
  'B 07-18 08:05 row for 07-17': '2fbf956438493129',
  'A 07-18 20:00 row for today': '188e9281b3a05de5',
  'A 07-18 22:00': '50b0af14c519382c',
  'B 07-18 22:05': '8ac2f2b076dd8b35',
  'A 07-19 22:00': 'e9b8a06d43b2eda4',
  'B 07-19 22:05': '0b6a93a64eca7c87',
  'A 07-20 22:00': '3568a139ae45f052',
  'B 07-20 22:05': '6cc5782c8f314f11',
  'A 07-21 22:00': 'df5687f24ab31a34',
  'B 07-21 22:05': 'c922dc94c4c9a1fa',
  'A 07-22 22:00': '9ed86a04251421fc',
  'B 07-22 22:05': '42b4f35a4f2cd521',
  'A 07-23 22:00': 'cb34eb021b7c56cb',
  'B 07-23 22:05': '445a52262e7c6613',
  'A 07-24 22:00': 'c28085bbc6fc5e29',
  'B 07-24 22:05': 'f015e03d3a5ca9ea',
  'A 07-25 09:00 shared pass': '125b14dfdc3a0c44',
  'B 07-25 09:00 shared pass': '1c1abc8d4b6aec28',
  'A 07-25 22:00': 'ab4c61ac3ac220b3',
  'B 07-25 22:05': 'e573feea2416341f',
  'A 07-26 22:00': '8f4de86a26f4a50f',
  'B 07-26 22:05': 'b4c9ade2e48fce9c',
  'A 07-27 10:30': '7e663ea4039b97bf',
  'B 07-27 10:35': 'ad7277ffc45fe462',
  'A 07-27 22:00': '5d35e401af911166',
  'B 07-27 22:05': '5c3c852d0a321334',
  'A 07-28 22:00': '9a036aeb6ccc95ed',
  'B 07-28 22:05': '1d961d309c160dc6',
  'A 07-29 22:00': '95f7c383fdef72fb',
  'B 07-29 22:05': 'e1ef31537f2943ec',
  'A 07-30 22:00': 'f61fe27225762a6f',
  'B 07-30 22:05': '74da390bd4056b98',
  'A 07-31 22:00': 'd35a73acee8d045e',
  'B 07-31 22:05': '090287785d0cdc80',
  'A 08-01 08:00': 'f52e76fbd3b6b2aa',
  'A 08-02 12:00': 'dec46c8eea938306',
  'B 08-01 08:00': '9bb2ce9c200a6076',
  'B 08-02 12:00': 'dc128b179ab67644',
};

void main() {
  setUpAll(initHarnessHive);

  test('every document the grader writes is the one it wrote before',
      () async {
    final steps = await _drive();
    final got = {for (final s in steps) s.label: _digest(s.doc)};
    expect(got, _frozen);

    // What those digests hold, spelt out: the month reaches every branch
    // the day reads and countedOn feed.
    Map<String, dynamic> doc(String label) =>
        jsonDecode(steps.firstWhere((s) => s.label == label).doc)
            as Map<String, dynamic>;
    final a = doc('A 07-31 22:00');
    final b = doc('B 07-31 22:05');
    // Pass 2: the week of 11 July holds only through the plan-cut clamp,
    // and room B's pause clamps nothing.
    expect(a['quotaOkWeeks'], [_k(4), _k(11), _k(18)]);
    expect(b['quotaOkWeeks'], [_k(11)]);
    // The stand-down loop: trained on the 17th, half a session on the 19th.
    expect(b['standDownDays'], [_k(16), _k(18), _k(20)]);
    // The grace-day row emptied the 17th, so that pass stood it down.
    expect(
      doc('B 07-18 08:05 row for 07-17')['standDownDays'],
      [_k(16), _k(17), _k(18)],
    );
    expect(doc('A 07-18 08:00 row for 07-17')['allDoneDate'], _k(17));
    // The finish edge.
    expect(doc('B 07-11 22:05')['allDoneToday'], isTrue);
    final marks = a['dailyHabitMarks'] as Map<String, dynamic>;
    // Graded by their squares once deleted: the relinked slot's m-q0 and
    // the declined slot's m-old.
    expect(marks[_k(5)], containsPair('m-q0', 'd'));
    expect(marks[_k(10)], containsPair('m-old', 'm'));
    // The stint repair: m-late graded from its slot's day, before the birth
    // it claims.
    expect(marks[_k(14)], containsPair('m-late', 'm'));
    // Paused from the 9th to the 12th: its Friday asks nothing of m-mwf.
    // Monday the 13th holds a 2 where its state should be: a miss.
    expect(marks[_k(10)], isNot(contains('m-mwf')));
    expect(marks[_k(13)], containsPair('m-mwf', 'm'));
    expect(a['dailyPartialCount'], isNotEmpty);
    expect(a['dailyRestedCount'], isNotEmpty);
  });

  test('each sync decodes each day document it reads once', () async {
    final steps = await _drive(countDayReads: true);
    // The counted snapshots grade exactly as the fake's own.
    expect({for (final s in steps) s.label: _digest(s.doc)}, _frozen);
    for (final s in steps) {
      if (s.label.contains('shared pass')) {
        // Room B's closed days came from room A's reads.
        expect(s.fetches, lessThan(s.days), reason: s.label);
      } else {
        expect(s.fetches, s.days, reason: s.label);
      }
    }
    // The month's totals take the shared pass once: its B step repeats the
    // counts its A step already holds.
    final once = [
      for (final s in steps)
        if (s.label != 'B 07-25 09:00 shared pass') s,
    ];
    expect(once, hasLength(steps.length - 1));
    final decodes = once.fold<int>(0, (n, s) => n + s.decodes);
    final days = once.fold<int>(0, (n, s) => n + s.days);
    // ignore: avoid_print
    print('day decodes: $decodes for $days graded days');
    expect(
      {for (final s in steps) s.label: s.decodes},
      {for (final s in steps) s.label: s.days},
    );
  });
}
