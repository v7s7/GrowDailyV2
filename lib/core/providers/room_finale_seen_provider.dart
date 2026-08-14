import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/local_store_service.dart';

// ─── "You've seen this room finish" ────────────────────────────────────────
//
// A room ending used to be announced by nothing at all. The finale card with
// the podium sits on the room screen and only appears if you happen to open
// it, so a 90-day challenge could finish and go unnoticed for days.
//
// The two obvious fixes are both wrong here. A local notification scheduled
// for the end date can't know the room was deleted, extended, or that you
// left it — it fires anyway, about a room that may not exist. A Cloud
// Function that pushes on the end date is a lot of moving parts (and cost)
// for one message a quarter.
//
// So this is state-driven instead, the same shape as every other "have they
// seen it yet" flag in the app: the codes whose ending has already been
// acknowledged. Whether a room *needs* announcing is recomputed from live
// data every launch — a room that was deleted simply isn't in your room list
// any more, so nothing fires, and one that got extended is no longer ended,
// so nothing fires either. Nothing can announce a room that isn't there.

const _kRoomFinaleSeenKey = 'room_finale_seen_codes_v1';

/// Room codes whose finale this device has already shown. Deliberately a set
/// of codes rather than a single bool: someone can be in several rooms, and
/// dismissing one ending must not silently swallow another's.
final roomFinaleSeenProvider = StateProvider<Set<String>>((ref) => const {});

/// Marks [code]'s ending as acknowledged, so it never announces again on this
/// device. Persisted, since "I saw my room finish" has to survive a restart.
Future<void> markRoomFinaleSeen(WidgetRef ref, String code) async {
  final current = ref.read(roomFinaleSeenProvider);
  if (current.contains(code)) return;
  ref.read(roomFinaleSeenProvider.notifier).state = {...current, code};
  final box = await LocalStoreService.settingsBox();
  final stored = (box.get(_kRoomFinaleSeenKey) as List?)
          ?.whereType<String>()
          .toSet() ??
      <String>{};
  await box.put(_kRoomFinaleSeenKey, [...stored, code]);
}

/// Forgets [code]'s ending, so a room that ends *again* announces again.
///
/// The seen-set is keyed by room code alone, which was right while a room
/// could only ever end once. Extending a finished room (see
/// RoomsController.extendRoom, surfaced on _FinaleCard) breaks that
/// assumption: the code is already in the set from the first ending, so
/// unseenFinishedRooms skips it forever and the second ending is announced to
/// nobody — the leader restarts the challenge and the finish passes in
/// silence. Called by whoever extends, on their own device.
///
/// Only the extending leader's device can clear its own set, so other members
/// still rely on the room simply being in their list; that is the same
/// local-first bargain the rest of this file already makes.
Future<void> clearRoomFinaleSeen(WidgetRef ref, String code) async {
  final current = ref.read(roomFinaleSeenProvider);
  if (!current.contains(code)) return;
  ref.read(roomFinaleSeenProvider.notifier).state = {...current}..remove(code);
  final box = await LocalStoreService.settingsBox();
  final stored = (box.get(_kRoomFinaleSeenKey) as List?)
          ?.whereType<String>()
          .toSet() ??
      <String>{};
  await box.put(_kRoomFinaleSeenKey, [...stored..remove(code)]);
}

/// Reads the persisted set, if any. Called once at boot (see main.dart) to
/// seed [roomFinaleSeenProvider] before the first frame.
Future<Set<String>> loadPersistedRoomFinaleSeen() async {
  final box = await LocalStoreService.settingsBox();
  return (box.get(_kRoomFinaleSeenKey) as List?)?.whereType<String>().toSet() ??
      <String>{};
}
