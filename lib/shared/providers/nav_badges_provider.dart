import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/extensions/datetime_ext.dart';
import '../../core/providers/nav_badges_setting_provider.dart';
import '../../features/auth/notifiers/auth_notifier.dart';
import '../../features/matrix/notifiers/matrix_notifier.dart';
import '../../features/matrix/screens/matrix_screen.dart'
    show matrixOpenTodayCount;
import '../../features/night_review/notifiers/night_review_notifier.dart';
import '../../features/rooms/notifiers/rooms_notifier.dart';
import '../widgets/nav_tabs.dart';

/// Pure: how many live rooms are still waiting on this person today. A
/// credit of 1.0 is a finished day (or a rest day, which counts as done);
/// anything under it is a room that will grade today against them unless
/// they act. See RoomParticipant.creditFor.
int roomsWaitingToday(Iterable<({bool isLive, double todayCredit})> rooms) =>
    rooms.where((r) => r.isLive && r.todayCredit < 1).length;

/// Pure: whether the Night Review tab carries its dot. The same window and
/// the same "not yet saved" rule as Profile's _NightReviewPromptCard, so
/// the dot and the card never disagree about whether tonight is done.
bool nightReviewPending(NightReviewState review, DateTime now) =>
    !review.isLoading && !review.saved && now.isDayClosing;

/// The bottom bar's badges, keyed by tab. Tabs not in the map draw none.
///
/// Zero additional Firestore cost by construction, same argument as
/// pendingSharedPlanPromptsProvider: every room stream read here
/// (myRoomCodesProvider, roomProvider, roomParticipantsProvider) is already
/// held open app-wide from the first frame, and the Matrix and Night Review
/// notifiers are the ones their own screens already keep loaded. This only
/// re-reads what is in memory.
///
/// Time enters through DateTime.now() at build, so a badge that depends on
/// the clock (the evening dot, the day rolling over) moves on the next
/// rebuild the shell gets, not on a timer. That is the same limitation the
/// Profile prompt card lives with, and a wrong-by-minutes dot is not worth
/// a ticking provider.
final navBadgesProvider = Provider<Map<NavTab, NavBadge>>((ref) {
  // Switched off in the customiser: nothing is computed, not merely
  // hidden, so the bar does not keep the room and task streams busy for
  // marks nobody will see.
  if (!ref.watch(navBadgesEnabledProvider)) return const {};
  final out = <NavTab, NavBadge>{};
  final now = DateTime.now();

  // Rooms: live ones still waiting on today. A guest has no rooms, and the
  // codes stream is empty for them, so this is naturally silent.
  final uid = ref.watch(authStateProvider).asData?.value?.uid;
  if (uid != null) {
    final codes = ref.watch(myRoomCodesProvider).valueOrNull ?? const [];
    // Rooms grade on the cutoff-aware app day, not the calendar day.
    final todayKey = now.effectiveDay.toDateKey();
    final rooms = <({bool isLive, double todayCredit})>[];
    for (final code in codes) {
      final room = ref.watch(roomProvider(code)).valueOrNull;
      if (room == null || !room.isLive) continue;
      final participants =
          ref.watch(roomParticipantsProvider(code)).valueOrNull ?? const [];
      final mine = participants.where((p) => p.uid == uid);
      if (mine.isEmpty) continue;
      rooms.add((isLive: true, todayCredit: mine.first.creditFor(todayKey)));
    }
    final waiting = roomsWaitingToday(rooms);
    if (waiting > 0) out[NavTab.rooms] = NavBadge.count(waiting);
  }

  // Tasks: today's open ones, by the Today lens's own rule.
  final tasks = ref.watch(matrixProvider.select((s) => s.tasks));
  final open = matrixOpenTodayCount(tasks, now);
  if (open > 0) out[NavTab.matrix] = NavBadge.count(open);

  // Night Review: a dot in the evening until tonight's is saved.
  if (nightReviewPending(ref.watch(nightReviewProvider), now)) {
    out[NavTab.nightReview] = const NavBadge.dot();
  }
  return out;
});
