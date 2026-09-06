import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/local_store_service.dart';

/// How a room's ranking rows draw their days: the last seven (compact, the
/// default since 2026-09-06) or the whole room, the strip the rows had
/// before. Aziz wanted both kept, behind one clear switch in the room, so
/// this is the viewer's choice and applies to every row of every room.
///
/// Device-local on purpose: it is a way of looking, not a fact about the
/// account, so it is not mirrored to Firestore like the nav bar layout.
const _kRoomRowsCompactKey = 'room_rows_compact_v1';

final roomRowsCompactProvider = StateProvider<bool>((ref) => true);

Future<void> setRoomRowsCompact(WidgetRef ref, bool compact) async {
  if (ref.read(roomRowsCompactProvider) == compact) return;
  ref.read(roomRowsCompactProvider.notifier).state = compact;
  await persistRoomRowsCompact(compact);
}

/// The default leaves no key behind, so a device that never touched the
/// switch stays on whatever the default becomes later.
Future<void> persistRoomRowsCompact(bool compact) async {
  try {
    final box = await LocalStoreService.settingsBox();
    if (compact) {
      await box.delete(_kRoomRowsCompactKey);
    } else {
      await box.put(_kRoomRowsCompactKey, false);
    }
  } catch (_) {}
}

Future<bool> loadPersistedRoomRowsCompact() async {
  try {
    final box = await LocalStoreService.settingsBox();
    return box.get(_kRoomRowsCompactKey) as bool? ?? true;
  } catch (_) {
    return true;
  }
}
