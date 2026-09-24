import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/datetime_ext.dart';
import '../../../core/providers/day_clock_provider.dart';
import '../../../core/services/local_store_service.dart';
import '../../auth/notifiers/auth_notifier.dart';
import '../models/room_model.dart';
import 'rooms_notifier.dart';

// ─── "The leader changed your room's plan" ────────────────────────────────
//
// Aziz, 2026-09-22, on how members hear that the leader removed a habit:
// "make it a pop up when they open, no need for notification and extra
// cost, its not necessary". So no push and no Cloud Function: the same
// state-driven shape as the finale popup (see RoomFinaleAnnouncer). Whether
// something needs telling is recomputed from the room documents every time
// they change, against a device-local record of what was already shown, so
// a change that was undone, a room that was deleted or left, or a member who
// joined after the change simply has nothing to be told.
//
// Zero extra Firestore reads: every stream this watches (the room list, each
// room, each roster) is already held open app-wide by
// myLinkedRoomHabitsProvider.

/// What changed. Only these two: adding a habit already has its own push,
/// banner and resolve sheet.
enum RoomPlanNoticeKind { removed, restored }

/// One thing to tell this member about one slot of one room.
class RoomPlanNotice {
  final RoomModel room;
  final int slot;
  final RoomPlanNoticeKind kind;

  /// Whether this member had one of their own habits in the slot, which is
  /// what decides if they are told their habit stays in their list.
  final bool hadLinked;

  /// For a removal: whether the slot still counts today (the removal day).
  final bool countsToday;

  const RoomPlanNotice({
    required this.room,
    required this.slot,
    required this.kind,
    required this.hadLinked,
    required this.countsToday,
  });

  String get habitName => room.sharedHabits[slot].name;

  /// Identifies this one change, so it is shown once per device: a later
  /// removal of the same slot (after a restore) is a new change with its own
  /// key, and a change seen once is never shown again.
  String get key {
    final t = room.sharedHabits[slot];
    final at = kind == RoomPlanNoticeKind.removed ? t.removedAt : t.restoredAt;
    return '${room.code}:$slot:${kind.name}:${at?.millisecondsSinceEpoch}';
  }
}

/// How long a plan change stays worth telling. A member away for longer
/// still sees the room as it now is; this only keeps a reinstall (which
/// forgets what was shown) from replaying a month of old news.
const Duration kRoomPlanNoticeWindow = Duration(days: 14);

/// The plan changes [uid] has not been told about by construction of the
/// data (not by the seen record, which the announcer checks): for every room
/// they are in, every slot the leader removed or brought back since they
/// joined, by someone other than them, recently.
///
/// Pure and top-level for the same reason unseenFinishedRooms is: every
/// "should this announce?" case can be checked with hand-built arguments.
List<RoomPlanNotice> roomPlanNoticesFor({
  required String uid,
  required List<String> myCodes,
  required RoomModel? Function(String code) roomFor,
  required List<RoomParticipant>? Function(String code) participantsFor,
  required DateTime now,
}) {
  final out = <RoomPlanNotice>[];
  final todayKey = now.startOfDay.toDateKey();
  for (final code in myCodes) {
    final room = roomFor(code);
    // Gone, loading, finished (its plan is final and the finale speaks for
    // it), or an own-mode room with no shared plan to change.
    if (room == null || room.isEndedAt(now)) continue;
    if (room.habitMode != RoomHabitMode.shared) continue;
    final roster = participantsFor(code);
    if (roster == null) continue;
    final mineList = roster.where((p) => p.uid == uid);
    if (mineList.isEmpty) continue;
    final mine = mineList.first;
    if (mine.isDeparted) continue;
    for (var i = 0; i < room.sharedHabits.length; i++) {
      final t = room.sharedHabits[i];
      final hadLinked = i < mine.linkedHabitIds.length &&
          mine.linkedHabitIds[i] != kDeclinedSlot;
      final removedAt = t.removedAt;
      if (removedAt != null) {
        // A legacy removal predates this and was a data repair, not news.
        if (t.stopsOn == null) continue;
        if (t.removedBy == uid) continue;
        if (!removedAt.isAfter(mine.joinedAt)) continue;
        if (now.difference(removedAt) > kRoomPlanNoticeWindow) continue;
        // A slot that never counted (added and removed the same day, or
        // before the room started) is only news to someone who had linked
        // it; everyone else never had anything to lose.
        final everCounted = t.stopsOn!.compareTo(room.slotJoinedPlanKey(i)) > 0;
        if (!everCounted && !hadLinked) continue;
        out.add(RoomPlanNotice(
          room: room,
          slot: i,
          kind: RoomPlanNoticeKind.removed,
          hadLinked: hadLinked,
          countsToday: t.liveOn(todayKey),
        ));
        continue;
      }
      final restoredAt = t.restoredAt;
      if (restoredAt == null) continue;
      if (t.restoredBy == uid) continue;
      if (!restoredAt.isAfter(mine.joinedAt)) continue;
      if (now.difference(restoredAt) > kRoomPlanNoticeWindow) continue;
      out.add(RoomPlanNotice(
        room: room,
        slot: i,
        kind: RoomPlanNoticeKind.restored,
        hadLinked: hadLinked,
        countsToday: true,
      ));
    }
  }
  return out;
}

/// [roomPlanNoticesFor] over the live room streams, for the announcer.
final roomPlanNoticesProvider = Provider<List<RoomPlanNotice>>((ref) {
  final uid = ref.watch(authStateProvider).asData?.value?.uid;
  if (uid == null) return const [];
  return roomPlanNoticesFor(
    uid: uid,
    myCodes: ref.watch(myRoomCodesProvider).valueOrNull ?? const <String>[],
    roomFor: (code) => ref.watch(roomProvider(code)).valueOrNull,
    participantsFor: (code) =>
        ref.watch(roomParticipantsProvider(code)).valueOrNull,
    // The removal day's wording ("counts today") has to turn over at
    // midnight on its own.
    now: ref.watch(dayClockProvider),
  );
});

const _kRoomPlanNoticesSeenKey = 'room_plan_notices_seen_v1';

/// The notice keys this device has already shown, in memory. The same shape
/// as roomFinaleSeenProvider, and for the same reason: the announcer has to
/// answer "shown already?" without waiting on disk, and a write must never
/// be awaited from inside a widget flow (a Hive write awaited inside a
/// testWidgets body never completes, see the project notes).
final roomPlanNoticesSeenProvider =
    StateProvider<Set<String>>((ref) => const {});

/// Merges the persisted record into [roomPlanNoticesSeenProvider]. Called by
/// the announcer before it shows anything; the settings box is already open
/// by then (boot opens it), so this costs one in-memory read.
Future<void> loadRoomPlanNoticesSeen(WidgetRef ref) async {
  final box = await LocalStoreService.settingsBox();
  final stored = (box.get(_kRoomPlanNoticesSeenKey) as List?)
          ?.whereType<String>()
          .toSet() ??
      const <String>{};
  if (stored.isEmpty) return;
  final current = ref.read(roomPlanNoticesSeenProvider);
  if (stored.every(current.contains)) return;
  ref.read(roomPlanNoticesSeenProvider.notifier).state = {
    ...current,
    ...stored,
  };
}

/// How a seen key reaches the disk. A seam, so a widget test can leave the
/// disk alone: a Hive write started inside a testWidgets body never finishes
/// (fake async), and Hive.close() in a tearDown then waits on it forever.
final roomPlanNoticeWriterProvider =
    Provider<Future<void> Function(String key)>((ref) => persistPlanNoticeSeen);

/// Records [key] as shown: in memory at once, on disk in the background, so
/// it never pops up again on this device.
void markRoomPlanNoticeSeen(WidgetRef ref, String key) {
  final current = ref.read(roomPlanNoticesSeenProvider);
  if (current.contains(key)) return;
  ref.read(roomPlanNoticesSeenProvider.notifier).state = {...current, key};
  ref.read(roomPlanNoticeWriterProvider)(key).ignore();
}

/// Appends [key] to the persisted record, keeping the most recent 200, which
/// is years of plan changes for anyone.

Future<void> persistPlanNoticeSeen(String key) async {
  final box = await LocalStoreService.settingsBox();
  final stored = (box.get(_kRoomPlanNoticesSeenKey) as List?)
          ?.whereType<String>()
          .toList() ??
      <String>[];
  if (stored.contains(key)) return;
  stored.add(key);
  await box.put(
    _kRoomPlanNoticesSeenKey,
    stored.length > 200 ? stored.sublist(stored.length - 200) : stored,
  );
}
