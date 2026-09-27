import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../premium/notifiers/premium_notifier.dart';
import '../models/room_model.dart';
import 'rooms_notifier.dart';

// ─── The free room limit ──────────────────────────────────────────────────
//
// Aziz, 2026-09-26: "make it only 3 rooms for free users". Before this a
// free account could be in any number of rooms; the only limit that touched
// Rooms was the habit cap, and only when a plan would add new habits.
//
// The rule lives here rather than in RoomsController on purpose: it is a
// Premium gate, asked by the screens at the moment somebody starts or joins
// a room, the same way canAddHabits is asked by every add-habit entry point.
// The controller's createRoom and joinRoom stay unaware of tiers.

/// How many of [rooms] take one of a free account's [kFreeRoomLimit] places
/// at [now]: every one that has not ended.
///
/// A lobby still waiting for Start counts, because it is a room the account
/// is in, and without it a free account could hold any number of rooms by
/// never starting them. So does an open-ended room, which has no end date to
/// reach. A room whose last day has closed ([RoomModel.isEndedAt], 10:00 the
/// morning after it) stays on the list as a record and stops counting, which
/// is what makes the limit "at a time". A room the account left is not on
/// its list at all (leaveRoom removes the code), and neither is one its
/// leader deleted once the list heals (forgetRoom). Pure, so the rule is
/// testable without Firestore.
int roomsHoldingAPlace(Iterable<RoomModel> rooms, DateTime now) =>
    rooms.where((room) => !room.isEndedAt(now)).length;

/// Whether an account holding [held] places may start or join one more room.
///
/// Premium always may. A free account may while it holds fewer than
/// [kFreeRoomLimit]. Past the limit (Premium that ended with five rooms) is
/// the same "no" as at it: the rooms are kept, only the next one waits.
bool mayTakeAnotherRoom({required int held, required bool isPremium}) =>
    isPremium || held < kFreeRoomLimit;

/// [mayTakeAnotherRoom] for this account, asked at the moment of starting or
/// joining a room: RoomsHubScreen's Create button, CreateRoomSheet's submit,
/// and JoinRoomSheet's Join, which is also where an invite link lands. A
/// "no" is answered with showRoomLimitGate.
///
/// Waited for (RoomsController.myRooms) rather than read, so a tap on a cold
/// start counts the rooms instead of a list that has not arrived yet. A room
/// document that cannot be read within myRooms' timeout is left out: a slow
/// network then opens the door rather than shutting it on somebody under the
/// limit. Starting and joining both need the server anyway, and the create
/// submit asks again.
///
/// A room list that fails outright, rather than slowly, is treated the same
/// way: it is not a limit anybody reached, so it is not answered with a
/// Premium pitch, and JoinRoomSheet, whose spinner is already on while this
/// runs, must not be left spinning on an exception.
///
/// Everything is read before the await, so a sheet closed while the rooms
/// load never has its ref used afterwards.
Future<bool> canTakeAnotherRoom(WidgetRef ref) async {
  if (ref.read(premiumAccessProvider)) return true;
  final controller = ref.read(roomsControllerProvider);
  final List<RoomModel> rooms;
  try {
    rooms = await controller.myRooms();
  } catch (e) {
    debugPrint('canTakeAnotherRoom: room list unreadable, not limiting: $e');
    return true;
  }
  return mayTakeAnotherRoom(
    held: roomsHoldingAPlace(rooms, DateTime.now()),
    isPremium: false,
  );
}
