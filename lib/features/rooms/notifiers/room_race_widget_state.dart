import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/notifiers/auth_notifier.dart';
import 'rooms_notifier.dart'
    show
        RoomRaceSnapshot,
        myRoomCodesProvider,
        myRoomRaceSnapshotProvider,
        myStarredRoomCodesProvider,
        roomProvider;

/// [myRoomRaceSnapshotProvider] for the Room Race widget, with whether its
/// null only means the inputs have not arrived yet. main.dart writes a null
/// to the widget as "no room", so it must not write the null of a cold
/// start: it did until 2026-09-29, and every cold start cleared the widget
/// to «ما في غرفة شغالة» first, which is what the Home Screen kept if the
/// app went back into the background before the rooms arrived.
///
/// The flag lives in the value the listener compares, not in a read inside
/// the listener: a null followed by another null does not notify, so a
/// listener that skipped the loading null never heard the settled one, and
/// a room that had ended or been left while the app was closed would have
/// stayed on the Home Screen for good (found in review the same day).
final roomRaceWidgetStateProvider =
    Provider<({RoomRaceSnapshot? snapshot, bool loading})>((ref) {
  final snapshot = ref.watch(myRoomRaceSnapshotProvider);
  if (snapshot != null) return (snapshot: snapshot, loading: false);
  return (snapshot: null, loading: _roomRaceInputsLoading(ref));
});

/// Whether [myRoomRaceSnapshotProvider]'s null only means its inputs have
/// not arrived: the account, its room codes, or the rooms themselves still
/// on their first load, or a room still running whose members are (the
/// provider answers null for each). An input that failed is settled, not
/// loading, so an error still lets "no room" through.
///
/// Walks the codes in the provider's own order (starred first) and stops at
/// the first room that answers, so it only ever watches rooms the provider
/// has already walked, and opens no room listener of its own.
bool _roomRaceInputsLoading(Ref ref) {
  bool firstLoad(AsyncValue<Object?> v) => !v.hasValue && !v.hasError;
  final auth = ref.watch(authStateProvider);
  if (firstLoad(auth)) return true;
  if (auth.valueOrNull == null) return false;
  final codes = ref.watch(myRoomCodesProvider);
  final starred = ref.watch(myStarredRoomCodesProvider);
  if (firstLoad(codes) || firstLoad(starred)) return true;
  final all = codes.valueOrNull ?? const <String>[];
  final starredSet = (starred.valueOrNull ?? const <String>[]).toSet();
  for (final code in [...all.where(starredSet.contains), ...all]) {
    final room = ref.watch(roomProvider(code));
    if (firstLoad(room)) return true;
    // Loaded and still running, yet nothing picked: its members are what
    // is missing, and the snapshot follows as soon as they land.
    final model = room.valueOrNull;
    if (model != null && !model.isEnded) return true;
  }
  return false;
}
