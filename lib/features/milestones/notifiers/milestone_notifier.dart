import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/notifiers/auth_notifier.dart';
import '../models/milestone_event.dart';

/// This account's full milestone history, newest first, streamed live from
/// `users/{uid}/milestones` — the same shared log [JourneyPage],
/// [MonthlyStoryScreen], and the Profile Legacy Shelf all read from. Empty
/// (never null) for a guest, same reasoning as myRoomCodesProvider
/// (rooms_notifier.dart): the log itself is account-only (see
/// [MilestoneEvent]'s doc comment), so screens built on this provider don't
/// need their own separate guest branch.
///
/// Capped at 500 (`limit`) rather than unbounded — even a multi-year power
/// user producing a handful of these a week lands nowhere near that, so
/// this is a safety ceiling against a pathological account, not a real
/// limit anyone hits; see JourneyPage for how a longer history would
/// eventually want pagination instead.
///
/// autoDispose: without it, this StreamProvider's live Firestore listener
/// would stay open for the rest of the app session the instant any one
/// screen first watches it, even after every watcher (Journey, Monthly
/// Story, Life Timeline, the Profile Legacy Shelf) unmounts — same
/// reasoning progressReportProvider (progress_hub_screen.dart) documents
/// for the identical situation. Safe against excess re-subscription on
/// ordinary tab/navigation: ProfileScreen stays mounted inside HomeShell's
/// PageView (see home_shell.dart) rather than being torn down on every tab
/// switch, so the Legacy Shelf keeps a baseline watch alive across normal
/// use — this only actually tears down and re-subscribes when nothing in
/// HomeShell is on screen at all (e.g. signed out).
final milestoneEventsProvider =
    StreamProvider.autoDispose<List<MilestoneEvent>>((ref) {
  final uid = ref.watch(authStateProvider).asData?.value?.uid;
  if (uid == null) return Stream.value(const <MilestoneEvent>[]);
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('milestones')
      .orderBy('occurredAt', descending: true)
      .limit(500)
      .snapshots()
      .map((snap) => snap.docs.map(MilestoneEvent.fromFirestore).toList());
});

/// [events] grouped by calendar month, most recent month first, each
/// month's own list kept in the same newest-first order [events] already
/// arrives in — what both JourneyPage's section headers and
/// MonthlyStoryScreen's month picker iterate over. A plain top-level
/// function (not another provider) so it's unit-testable with a hand-built
/// event list and no Firestore/Riverpod involved, same reasoning as
/// sortStarredFirst (rooms_notifier.dart).
Map<DateTime, List<MilestoneEvent>> groupMilestonesByMonth(
  List<MilestoneEvent> events,
) {
  final out = <DateTime, List<MilestoneEvent>>{};
  for (final e in events) {
    final key = DateTime(e.occurredAt.year, e.occurredAt.month);
    (out[key] ??= []).add(e);
  }
  return out;
}

/// Count of each [MilestoneType] across [events] — what Life Timeline's
/// per-year badges and Monthly Story's tally grid both need, computed here
/// once instead of twice: Life Timeline originally built this map inline
/// with its own for-loop, and Monthly Story separately re-derived the same
/// counts as five independent `.where((e) => e.type == t).length` passes
/// (O(n) per type instead of one O(n) pass total). Same "plain top-level
/// function, unit-testable with a hand-built list" reasoning as
/// [groupMilestonesByMonth] above.
Map<MilestoneType, int> tallyMilestonesByType(Iterable<MilestoneEvent> events) {
  final out = <MilestoneType, int>{};
  for (final e in events) {
    out[e.type] = (out[e.type] ?? 0) + 1;
  }
  return out;
}

/// Writes one meaningful moment to `users/{uid}/milestones` — the standalone
/// counterpart to DashboardNotifierCompleteHabit.completeHabit's own inline
/// batch writes (that method already holds an open batch touching the same
/// user doc, so it appends directly rather than calling this - see its
/// milestone-log section). Any other notifier logging a milestone outside
/// an existing batch (e.g. RoomsController for a future
/// [MilestoneType.roomChallengeComplete]) should call this instead of
/// hand-rolling the Firestore path again.
///
/// Fire-and-forget by design, same posture as AnalyticsService.track: a
/// failed write here means one fewer story beat later, never a lost
/// XP/gold/streak update (those land through their own already-verified
/// write path), so this swallows its own errors rather than surfacing them
/// to the caller.
Future<void> logMilestoneEvent(
  String? uid,
  MilestoneType type, {
  Map<String, dynamic> data = const {},
  DateTime? occurredAt,
}) async {
  if (uid == null) return;
  try {
    final event = MilestoneEvent(
      id: '',
      type: type,
      occurredAt: occurredAt ?? DateTime.now(),
      data: data,
    );
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('milestones')
        .add(event.toFirestore());
  } catch (_) {
    // Best-effort — see doc comment above.
  }
}
