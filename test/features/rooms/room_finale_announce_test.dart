// Covers the decision behind the "your challenge finished" popup: WHICH
// rooms should announce their ending on the next app open.
//
// The whole reason this is computed from live state instead of a scheduled
// notification is that a queued notification can't take anything back. It
// fires on the end date whatever has happened since — the leader deleted the
// room, the leader extended it, you left. Each of those is a case below, and
// each one has to produce silence.
//
// Pure function tests: no Firestore, no auth, no widgets. unseenFinishedRooms
// takes the code list, the acknowledged set and a room lookup as plain
// arguments, so every case below is exercised directly.
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/features/rooms/models/room_model.dart';
import 'package:grow_daily_v2/features/rooms/notifiers/rooms_notifier.dart';

RoomModel _room({
  required String code,
  required DateTime start,
  DateTime? end,
  String name = 'Test Room',
}) =>
    RoomModel(
      code: code,
      name: name,
      createdBy: 'leader-uid',
      createdByName: 'Leader',
      createdAt: start,
      habitMode: RoomHabitMode.own,
      duration: end == null ? RoomDuration.open : RoomDuration.fixed,
      startDate: start,
      endDate: end,
    );

/// A room that finished a week ago, and one still running.
final _endedRoom = _room(
  code: 'ENDED1',
  start: DateTime.now().subtract(const Duration(days: 30)),
  end: DateTime.now().subtract(const Duration(days: 7)),
);
final _liveRoom = _room(
  code: 'LIVE01',
  start: DateTime.now().subtract(const Duration(days: 3)),
  end: DateTime.now().add(const Duration(days: 30)),
);

void main() {
  _sizeRules();

  /// Runs the real selection with hand-built inputs.
  List<RoomModel> unseen({
    required List<String> myCodes,
    Map<String, RoomModel?> rooms = const {},
    Set<String> seen = const {},
  }) =>
      unseenFinishedRooms(
        myCodes: myCodes,
        seenCodes: seen,
        roomFor: (code) => rooms[code],
      );

  test('a finished room this account is in announces itself', () {
    final result = unseen(
      myCodes: const ['ENDED1'],
      rooms: {'ENDED1': _endedRoom},
    );
    expect(result.map((r) => r.code), ['ENDED1']);
  });

  test('a room still running never announces', () {
    expect(
      unseen(myCodes: const ['LIVE01'], rooms: {'LIVE01': _liveRoom}),
      isEmpty,
    );
  });

  test('a room whose ending was already acknowledged stays quiet', () {
    expect(
      unseen(
        myCodes: const ['ENDED1'],
        rooms: {'ENDED1': _endedRoom},
        seen: const {'ENDED1'},
      ),
      isEmpty,
    );
  });

  test('a DELETED room announces nothing — its doc resolves to null', () {
    // The exact case a scheduled notification could not have handled: the
    // leader deleted the room after it ended, so there is nothing left to
    // announce, but a queued notification would have fired regardless.
    expect(
      unseen(myCodes: const ['ENDED1'], rooms: const {'ENDED1': null}),
      isEmpty,
    );
  });

  test('a room the leader EXTENDED announces nothing — it is not ended', () {
    // Second thing a queued notification could not take back: the end date
    // moved after it would have been scheduled.
    final extended = _room(
      code: 'ENDED1',
      start: DateTime.now().subtract(const Duration(days: 30)),
      end: DateTime.now().add(const Duration(days: 14)),
    );
    expect(
      unseen(myCodes: const ['ENDED1'], rooms: {'ENDED1': extended}),
      isEmpty,
    );
  });

  test('a room you LEFT announces nothing — the code is gone from your list',
      () {
    // Third: leaveRoom drops the code from users/{uid}.roomCodes, so an
    // ended room is no longer yours to be told about.
    expect(
      unseen(myCodes: const [], rooms: {'ENDED1': _endedRoom}),
      isEmpty,
    );
  });

  test('a room whose doc has not loaded yet stays quiet', () {
    // Never announce on a half-loaded picture; the next build will have it.
    expect(unseen(myCodes: const ['ENDED1']), isEmpty);
  });

  test('several finished rooms are all reported, in list order', () {
    // Being in more than one is normal. The announcer shows one at a time,
    // but the selection must not silently drop the others.
    final second = _room(
      code: 'ENDED2',
      start: DateTime.now().subtract(const Duration(days: 60)),
      end: DateTime.now().subtract(const Duration(days: 20)),
    );
    final result = unseen(
      myCodes: const ['ENDED1', 'ENDED2'],
      rooms: {'ENDED1': _endedRoom, 'ENDED2': second},
    );
    expect(result.map((r) => r.code), ['ENDED1', 'ENDED2']);
  });

  test('acknowledging one ending leaves another still due', () {
    final second = _room(
      code: 'ENDED2',
      start: DateTime.now().subtract(const Duration(days: 60)),
      end: DateTime.now().subtract(const Duration(days: 20)),
    );
    final result = unseen(
      myCodes: const ['ENDED1', 'ENDED2'],
      rooms: {'ENDED1': _endedRoom, 'ENDED2': second},
      seen: const {'ENDED1'},
    );
    expect(result.map((r) => r.code), ['ENDED2']);
  });

  test('an open-ended room never announces — it has no end date at all', () {
    final openRoom = _room(
      code: 'OPEN01',
      start: DateTime.now().subtract(const Duration(days: 100)),
    );
    expect(
      unseen(myCodes: const ['OPEN01'], rooms: {'OPEN01': openRoom}),
      isEmpty,
    );
  });
}

// ─── Large-room quiet-by-default ───────────────────────────────────────────
//
// Two mechanisms, deliberately both, because they solve different halves:
//  - kRoomAutoMuteMemberLimit decides what a NEW MEMBER hears by default. It
//    is visible (the room's bell) and one tap from being reversed.
//  - FANOUT_MEMBER_LIMIT in functions/index.js caps what the room may SEND at
//    all, so reversing the mute is pleasant rather than a ~199-a-day firehose.
// They must agree on the number, or a room could sit in the gap between them:
// quiet by default but still fanning out to whoever unmuted.
void _sizeRules() {
  group('large-room notification defaults', () {
    test('the threshold matches the Cloud Function it is paired with', () {
      // functions/index.js: const FANOUT_MEMBER_LIMIT = 12;
      expect(kRoomAutoMuteMemberLimit, 12);
    });

    test('a small room is not muted by default', () {
      expect(6 > kRoomAutoMuteMemberLimit, isFalse);
      expect(kRoomAutoMuteMemberLimit > kRoomAutoMuteMemberLimit, isFalse);
    });

    test('a room past the threshold is', () {
      expect(13 > kRoomAutoMuteMemberLimit, isTrue);
      expect(200 > kRoomAutoMuteMemberLimit, isTrue);
    });
  });
}
