import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/local_store_service.dart';

/// Whether the two cards at the top of a competitive room (today's faces,
/// and my plan) are folded to their header line. Aziz asked for both to be
/// collapsible (2026-09-06): once you know who is in the room, the faces
/// are a glance and the plan card is a status line, and the ranking is
/// what you came for.
///
/// Device-local like [roomRowsCompactProvider]: a way of looking, not a
/// fact about the account. Only the non-default (collapsed) is stored.
const _kTodayKey = 'room_today_collapsed_v1';
const _kPlanKey = 'room_plan_collapsed_v1';

final roomTodayCollapsedProvider = StateProvider<bool>((ref) => false);
final roomPlanCollapsedProvider = StateProvider<bool>((ref) => false);

Future<void> setRoomTodayCollapsed(WidgetRef ref, bool collapsed) async {
  if (ref.read(roomTodayCollapsedProvider) == collapsed) return;
  ref.read(roomTodayCollapsedProvider.notifier).state = collapsed;
  await persistRoomCardCollapsed(_kTodayKey, collapsed);
}

Future<void> setRoomPlanCollapsed(WidgetRef ref, bool collapsed) async {
  if (ref.read(roomPlanCollapsedProvider) == collapsed) return;
  ref.read(roomPlanCollapsedProvider.notifier).state = collapsed;
  await persistRoomCardCollapsed(_kPlanKey, collapsed);
}

Future<void> persistRoomCardCollapsed(String key, bool collapsed) async {
  try {
    final box = await LocalStoreService.settingsBox();
    if (collapsed) {
      await box.put(key, true);
    } else {
      await box.delete(key);
    }
  } catch (_) {}
}

Future<bool> loadPersistedRoomTodayCollapsed() => _load(_kTodayKey);
Future<bool> loadPersistedRoomPlanCollapsed() => _load(_kPlanKey);

Future<bool> _load(String key) async {
  try {
    final box = await LocalStoreService.settingsBox();
    return box.get(key) as bool? ?? false;
  } catch (_) {
    return false;
  }
}

/// The keys, for tests that read the box directly.
const roomTodayCollapsedKey = _kTodayKey;
const roomPlanCollapsedKey = _kPlanKey;
