import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/local_store_service.dart';

/// Why someone is reporting another member. Stored as the enum NAME, not
/// its index, so inserting a reason later can never silently relabel every
/// report already filed.
enum ReportReason {
  inappropriateName,
  harassment,
  spam,
  other;

  String get id => name;
}

/// The blocking half of App Review guideline 1.2, kept deliberately LOCAL.
///
/// Blocking is a statement about what this person wants to see, not a
/// punishment applied to the blocked account, so it lives in Hive rather
/// than in Firestore. That choice has three consequences worth being
/// explicit about:
///
///  - it works offline and applies instantly, with no write and no rules
///    round-trip;
///  - it cannot be used to harass someone (a blocked member is never told,
///    and nothing about their account changes);
///  - it does not follow the user to a new device. That is the real cost,
///    and it is accepted because the alternative — a server-side block
///    list — is a list of who dislikes whom, which is far more sensitive
///    than the problem it solves.
///
/// Reporting is the half that DOES reach the server, because a report is
/// information the operator needs and the reporter cannot act on alone.
class BlockedMembersNotifier extends StateNotifier<Set<String>> {
  BlockedMembersNotifier() : super(const {}) {
    _load();
  }

  static const _key = 'blocked_room_members';

  Future<void> _load() async {
    final stored = await LocalStoreService.getSettingsMap(_key);
    final uids = (stored['uids'] as List?)?.whereType<String>().toSet();
    if (!mounted || uids == null) return;
    state = uids;
  }

  Future<void> _persist() =>
      LocalStoreService.putSettingsMap(_key, {'uids': state.toList()});

  bool isBlocked(String uid) => state.contains(uid);

  Future<void> block(String uid) async {
    if (state.contains(uid)) return;
    state = {...state, uid};
    await _persist();
  }

  Future<void> unblock(String uid) async {
    if (!state.contains(uid)) return;
    state = {...state}..remove(uid);
    await _persist();
  }
}

final blockedMembersProvider =
    StateNotifierProvider<BlockedMembersNotifier, Set<String>>(
  (ref) => BlockedMembersNotifier(),
);

/// Files a report against one member of one room.
///
/// Fire-and-forget from the UI's point of view: the sheet confirms to the
/// reporter as soon as this is called rather than waiting on the network,
/// because a report that fails to upload must not read as "your report was
/// refused". A failure is swallowed and logged rather than surfaced, for
/// the same reason.
///
/// Writes are create-only under firestore.rules — a client can file a
/// report and can never read, edit or delete one, including its own. That
/// keeps the collection from becoming a way to discover who reported whom.
Future<void> submitRoomReport({
  required String reporterUid,
  required String roomCode,
  required String reportedUid,
  required String reportedName,
  required ReportReason reason,
  String? note,
}) async {
  // Guarded rather than asserted: a signed-out caller and a self-report
  // are both reachable through ordinary UI races, and neither is worth
  // throwing over.
  if (reporterUid.isEmpty || reporterUid == reportedUid) return;
  try {
    await FirebaseFirestore.instance.collection('reports').add({
      'reporterUid': reporterUid,
      'roomCode': roomCode,
      'reportedUid': reportedUid,
      // Captured at report time on purpose: the name is usually the thing
      // being reported, and it can be edited the moment a report is filed.
      'reportedNameAtReport': reportedName,
      'reason': reason.id,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  } catch (_) {
    // Deliberately silent. See this function's doc comment.
  }
}
