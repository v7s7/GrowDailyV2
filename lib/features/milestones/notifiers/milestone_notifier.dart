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
/// Capped at 500 (`limit`) rather than unbounded. That ceiling used to be
/// justified as "a handful a week, nowhere near it", and that estimate was
/// wrong by roughly 5x: a perfectDay is logged on every perfect day, so a
/// consistent account produces on the order of 30 a month and crosses 500
/// after about fourteen months. Past that, the OLDEST months silently fall
/// off the end of this newest-first window and tally zero milestones.
///
/// The damage stops there, and deliberately not further: every milestone
/// is written in the SAME batch as its dailyGreenCounts increment (see
/// dashboard_notifier_complete_habit.dart), and that map is loaded
/// uncapped, so a month holding milestones always holds green squares too
/// and can never fall through to the empty state. What an affected month
/// showed instead was its real square count above a tally grid of zeros —
/// quieter than an empty state, and wrong in a way nobody would question.
///
/// The cap stays, because this provider genuinely wants a bounded live
/// listener. What changed is that no screen now depends on it reaching
/// back forever: any surface that needs ONE specific month reads
/// [milestonesForMonthProvider], which queries that month directly and is
/// unaffected by how much history sits in front of it.
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

/// Exactly one calendar month of milestones, queried by date rather than
/// sliced out of [milestoneEventsProvider]'s newest-first window.
///
/// The distinction matters once an account has more than ~500 events: the
/// shared provider's window no longer reaches the older months at all, so
/// filtering it client-side reports zero for months that are simply out of
/// view. A range query has no such horizon, and reads only the handful of
/// documents the month actually contains.
///
/// [month] must be normalised to the first of the month; the family key is
/// the DateTime itself, so an un-normalised value would open a separate
/// listener per day.
final milestonesForMonthProvider = StreamProvider.autoDispose
    .family<List<MilestoneEvent>, DateTime>((ref, month) {
  final uid = ref.watch(authStateProvider).asData?.value?.uid;
  if (uid == null) return Stream.value(const <MilestoneEvent>[]);
  final start = DateTime(month.year, month.month);
  final end = DateTime(month.year, month.month + 1);
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('milestones')
      .where('occurredAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
      .where('occurredAt', isLessThan: Timestamp.fromDate(end))
      .orderBy('occurredAt', descending: true)
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
