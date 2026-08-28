import 'dart:async' show unawaited;
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/text_moderation.dart';
import '../../../core/constants/deep_links.dart';
import '../../../core/extensions/datetime_ext.dart';
import '../../../core/providers/room_finale_seen_provider.dart';
import '../../auth/notifiers/auth_notifier.dart';
import '../../character/models/character_option.dart';
import '../../character/notifiers/character_notifier.dart';
import '../../character/notifiers/prestige_notifier.dart';
import '../../dashboard/notifiers/dashboard_notifier.dart';
import '../../grid/models/square_state.dart';
import '../../grid/notifiers/weekly_grid_notifier.dart';
import '../../habits/catalog/islamic_habit_catalog.dart';
import '../../habits/models/habit_model.dart';
import '../../habits/models/weekly_quota_plan.dart';
import '../../habits/notifiers/custom_habits_notifier.dart';
import '../models/room_model.dart';

/// This account's room codes, streamed live from `users/{uid}.roomCodes` so
/// RoomsHubScreen updates the instant a create/join/leave lands - no
/// separate refresh step. Empty (never null) for a guest: Rooms need an
/// account to sync a leaderboard across devices in the first place, so
/// RoomsHubScreen gates guests out before this is ever watched for real.
final myRoomCodesProvider = StreamProvider<List<String>>((ref) {
  final uid = ref.watch(authStateProvider).asData?.value?.uid;
  if (uid == null) return Stream.value(const <String>[]);
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .snapshots()
      .map(
        (snap) =>
            (snap.data()?['roomCodes'] as List?)
                ?.whereType<String>()
                .toList() ??
            const <String>[],
      );
});

/// This account's starred room codes, streamed live from
/// `users/{uid}.starredRoomCodes` — same shape and same reasoning as
/// [myRoomCodesProvider] (a personal, this-account-only preference, not
/// something any other member of a starred room ever sees - see
/// [RoomsController.toggleStarRoom]), kept as its own field/provider rather
/// than folded into [myRoomCodesProvider] so RoomsHubScreen can watch "which
/// rooms" and "which are starred" as two independently-updating streams. A
/// star/unstar tap reorders the list the instant it lands, same as any
/// other live provider in this file. Empty for a guest, same as
/// [myRoomCodesProvider].
final myStarredRoomCodesProvider = StreamProvider<List<String>>((ref) {
  final uid = ref.watch(authStateProvider).asData?.value?.uid;
  if (uid == null) return Stream.value(const <String>[]);
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .snapshots()
      .map(
        (snap) =>
            (snap.data()?['starredRoomCodes'] as List?)
                ?.whereType<String>()
                .toList() ??
            const <String>[],
      );
});

/// Stable-partitions [codes] so every starred one comes first, each group
/// keeping its original relative order - not a full re-sort by anything
/// else (join order, name, progress...), just "starred rooms float to the
/// top of whatever order they were already in." A plain top-level function
/// so this is unit-testable without any Firestore involved, same reasoning
/// as [nextLeaderAfter]/[removeLinkedHabit] below. The only caller is
/// RoomsHubScreen's _MyRooms.
List<String> sortStarredFirst(List<String> codes, Set<String> starred) {
  final starredCodes = codes.where(starred.contains).toList();
  final rest = codes.where((c) => !starred.contains(c)).toList();
  return [...starredCodes, ...rest];
}

/// One room's top-level doc, live. Null means no room has this code (never
/// existed, or the leader deleted it) - see RoomsController.forgetRoom for
/// how a stale code gets cleaned out of [myRoomCodesProvider].
final roomProvider = StreamProvider.family<RoomModel?, String>((ref, code) {
  return FirebaseFirestore.instance
      .collection('rooms')
      .doc(code)
      .snapshots()
      .map((snap) => snap.exists ? RoomModel.fromFirestore(snap) : null);
});

/// A room's full roster, live, in join order. Deliberately unsorted by
/// progress here - RoomDetailScreen re-sorts using RoomParticipant.
/// progressRatio(room), which needs the room's date range too; keeping that
/// math in one place (the screen, where both are already in scope) beats
/// splitting it across a provider and its consumer.
final roomParticipantsProvider =
    StreamProvider.family<List<RoomParticipant>, String>((ref, code) {
  return FirebaseFirestore.instance
      .collection('rooms')
      .doc(code)
      .collection('participants')
      .orderBy('joinedAt')
      .snapshots()
      .map((snap) => snap.docs.map(RoomParticipant.fromFirestore).toList());
});

/// One ranked row of the widget's Room Race face - a trimmed, JSON-ready
/// view of a single participant. See [myRoomRaceSnapshotProvider].
class RoomRaceRow {
  final String name;
  final int rank; // 1-based
  final int percent; // 0-100, rounded RoomParticipant.progressRatio
  final bool isMe;

  /// Days credited so far, and the days the room has actually run — the
  /// raw pair behind [percent], carried so the Lock Screen can render a
  /// concrete "5 / 6" instead of "83%". A fraction is both shorter and
  /// more meaningful at a glance on a cramped accessory widget: it says
  /// how many days are actually in play, so "5 / 6" and "50 / 60" don't
  /// collapse into the same number the way percentages do.
  ///
  /// Rounded for display (a partially-credited day contributes a
  /// fraction — see RoomParticipant.daysCompleted), which is why [percent]
  /// stays the source of truth for the progress ring itself.
  final int daysDone;
  final int daysTotal;

  /// This participant's real, stable Firebase uid - not shown anywhere,
  /// only carried so the widget can identify "the same person" across two
  /// separate timeline refreshes even after their rank moves. Without this,
  /// the Swift side would have to key rows by display name, which breaks
  /// (or at best animates oddly) the moment two participants share a first
  /// name - a real scenario for a small-friend-group room, not an edge case
  /// worth ignoring.
  final String uid;

  /// This participant's last [roomRaceHeatmapDays] days, oldest first, as
  /// [heatmapLevelFor] levels (0-4) - the same tiers the in-app
  /// _MiniHeatmapStrip (room_detail_screen.dart) renders, just windowed
  /// much tighter for a widget's own limited space. Every row carries this,
  /// even ones a given widget size has no room to draw a strip for -
  /// keeps this class one flat, uniform shape rather than an optional
  /// field only some rows populate, and the Swift side already follows the
  /// "Dart pushes everything, Swift decides what fits per size" pattern
  /// every other widget in this app uses (see GrowDailyLargeView's
  /// `.prefix(5)`, GrowDailyMatrixWidget's row limits).
  final List<int> heatmap;

  const RoomRaceRow({
    required this.name,
    required this.rank,
    required this.percent,
    required this.isMe,
    required this.uid,
    this.daysDone = 0,
    this.daysTotal = 0,
    this.heatmap = const [],
  });
}

/// How many of a participant's most recent days [myRoomRaceSnapshotProvider]
/// windows [RoomRaceRow.heatmap] to. Much tighter than _MiniHeatmapStrip's
/// in-app 30-day window - a widget has real estate for roughly two weeks of
/// small cells per row, not a full month, especially once name/rank/percent
/// already share that same row's width. 14 also mirrors this app's other
/// "recent window" default (ProgressHubScreen's 14-day chart), so a glance
/// at either one covers the same span.
const int roomRaceHeatmapDays = 14;

/// 0 (empty) or 1-4 for a day's [credit] (0.0-1.0, see
/// RoomParticipant.creditFor) - the same tiers [heatColor]
/// (monthly_heatmap_screen.dart) renders, and what both _MiniHeatmapStrip
/// (room_detail_screen.dart, the in-app per-participant strip) and
/// [RoomRaceRow.heatmap] above (the widget's own copy) key their shading
/// off of. Rounds any nonzero credit *up* to at least the lightest tier
/// rather than down toward empty, so a single habit done out of several
/// always shows as visibly different from a day with nothing done at all.
/// A top-level function, not a method on either call site, so the in-app
/// strip and the widget push always agree on exactly the same mapping
/// without one depending on the other - same reasoning as
/// [suggestExistingMatch]/[nextLeaderAfter] elsewhere in this file.
int heatmapLevelFor(double credit) {
  if (credit <= 0) return 0;
  return (credit * 4).ceil().clamp(1, 4);
}

/// Everything the widget's Room Race face needs for the one room
/// [myRoomRaceSnapshotProvider] picked - already ranked, so the widget
/// itself never has to touch RoomParticipant.progressRatio or Firestore.
class RoomRaceSnapshot {
  final String roomName;
  final bool isLive;
  final int daysRemaining; // matches RoomModel.daysRemaining - 0 if open-ended
  final List<RoomRaceRow> rows; // sorted by rank already
  const RoomRaceSnapshot({
    required this.roomName,
    required this.isLive,
    required this.daysRemaining,
    required this.rows,
  });
}

/// Picks one room for the widget's Room Race face (both the Home Screen
/// size and the Lock Screen size - see GrowDailyRoomRaceWidget and
/// GrowDailyRoomRaceLockScreenWidget in GrowDailyWidget.swift, which share
/// this exact result) and ranks its roster - the source
/// HomeWidgetService.updateRoomRaceData pushes to both (wired from
/// main.dart's _roomRaceSub, same ref.listenManual pattern as every other
/// widget-sync listener there).
///
/// A starred room (see RoomsController.toggleStarRoom/[myStarredRoomCodesProvider])
/// wins outright whenever one exists and hasn't ended - live or still in
/// its lobby, it's an explicit "show me this one" signal that overrides
/// everything below. Only once no starred room qualifies does this fall
/// back to the original heuristic: among the rest, a live one (started, not
/// ended - the actually-racing state) wins outright; otherwise the first
/// room found (e.g. still in its lobby) shows instead, so there's always
/// something on the widget rather than nothing just because the "best"
/// room hasn't started yet. Null when there's no room to show at all (no
/// rooms, or every room this account is in has ended) -
/// updateRoomRaceData treats null as "clear the widget's room face back to
/// its own join-or-create placeholder", not "leave whatever was there".
///
/// Before starring existed, this deliberately didn't let someone pick
/// *which* room shows when they're in several live ones at once - a full
/// WidgetKit AppIntent-backed configurable widget (an AppEntity +
/// EntityQuery that can enumerate rooms from inside the widget process,
/// which can't reach Firestore directly) was real extra surface for what
/// was a rare case. Starring covers the same need with far less machinery:
/// it's already a plain per-account field this provider can just read.
final myRoomRaceSnapshotProvider = Provider<RoomRaceSnapshot?>((ref) {
  final uid = ref.watch(authStateProvider).asData?.value?.uid;
  if (uid == null) return null;
  final codes = ref.watch(myRoomCodesProvider).valueOrNull ?? const [];
  final starred =
      (ref.watch(myStarredRoomCodesProvider).valueOrNull ?? const []).toSet();

  RoomModel? pickFrom(Iterable<String> fromCodes) {
    RoomModel? fallback;
    for (final code in fromCodes) {
      final room = ref.watch(roomProvider(code)).valueOrNull;
      if (room == null || room.isEnded) continue;
      if (room.isLive) return room;
      fallback ??= room;
    }
    return fallback;
  }

  final picked = pickFrom(codes.where(starred.contains)) ?? pickFrom(codes);
  if (picked == null) return null;
  final bestRoom = picked; // final capture - safe to use inside closures below

  final participants =
      ref.watch(roomParticipantsProvider(bestRoom.code)).valueOrNull ??
          const [];
  if (participants.isEmpty) return null;

  final ranked = [...participants]..sort((a, b) {
    final byProgress =
        b.progressRatio(bestRoom).compareTo(a.progressRatio(bestRoom));
    // Same deterministic tie-break the lobby leaderboard uses, so the two
    // ranked views never disagree on the order of tied members. List.sort is
    // unstable above 32 elements; uid is stable and unique.
    return byProgress != 0 ? byProgress : a.uid.compareTo(b.uid);
  });

  // Same trailing window every row's heatmap is built from - computed once
  // here rather than per-row, since it only depends on the room, not the
  // participant. Mirrors _MiniHeatmapStrip's own day-generation exactly
  // (oldest first, ending on lastCountedDay), just capped at
  // roomRaceHeatmapDays instead of that screen's 30.
  final heatmapDayCount = bestRoom.daysElapsed.clamp(1, roomRaceHeatmapDays);
  final lastDay = bestRoom.lastCountedDay;
  final heatmapDays = [
    for (var i = 0; i < heatmapDayCount; i++)
      lastDay.subtract(Duration(days: heatmapDayCount - 1 - i)),
  ];

  return RoomRaceSnapshot(
    roomName: bestRoom.name,
    isLive: bestRoom.isLive,
    daysRemaining: bestRoom.daysRemaining,
    rows: [
      for (var i = 0; i < ranked.length; i++)
        RoomRaceRow(
          name: ranked[i].displayName,
          rank: i + 1,
          percent: (ranked[i].progressRatio(bestRoom) * 100).round(),
          isMe: ranked[i].uid == uid,
          uid: ranked[i].uid,
          daysDone: ranked[i].daysCompleted(bestRoom).round(),
          daysTotal: bestRoom.daysElapsed,
          heatmap: [
            for (final day in heatmapDays)
              heatmapLevelFor(ranked[i].creditFor(day.toDateKey())),
          ],
        ),
    ],
  );
});

/// habitId -> rooms (this account only, and only rooms still accepting
/// progress - see [RoomModel.isEnded]) currently tracking it - the reverse
/// index Grid needs both for its "part of a Room" badge and for pushing a
/// live sync the instant a linked habit's square changes (see
/// RoomsController.syncTodayForHabit), without Grid needing to know
/// anything about Rooms' own data model beyond "is this habitId in here".
/// Ended rooms are filtered out right here, at the source, rather than in
/// every consumer - once a room's end date has passed it should stop
/// accruing "today" completions even if the linked habit is still ticked
/// green in Grid (see syncTodayForHabit's doc comment).
final myLinkedRoomHabitsProvider =
    Provider<Map<String, List<RoomModel>>>((ref) {
  final uid = ref.watch(authStateProvider).asData?.value?.uid;
  if (uid == null) return const {};
  final codes = ref.watch(myRoomCodesProvider).valueOrNull ?? const [];
  final result = <String, List<RoomModel>>{};
  for (final code in codes) {
    final room = ref.watch(roomProvider(code)).valueOrNull;
    if (room == null || room.isEnded) continue;
    final participants = ref.watch(roomParticipantsProvider(code)).valueOrNull;
    if (participants == null) continue;
    final mine = participants.where((p) => p.uid == uid);
    if (mine.isEmpty) continue;
    // countedHabitIdsIn, not linkedHabitIds: a slot this person skipped (see
    // kDeclinedSlot) isn't a real habit id at all, and a slot the leader
    // withdrew (see RoomHabitTemplate.removedAt) no longer counts here - so
    // neither should earn the Grid 2x room boost or trigger a per-tap room
    // sync, both of which read this index.
    for (final habitId in mine.first.countedHabitIdsIn(room)) {
      (result[habitId] ??= []).add(room);
    }
  }
  return result;
});

/// The subset of [myLinkedRoomHabitsProvider] where the habit is the ONLY
/// thing this member has counting in that room.
///
/// Pausing a habit is normally softened by [roomHasGradableHabit]: the habit
/// leaves both sides of the sum and the member is graded on whatever else
/// they linked. That softening has a floor, and this provider is it. When
/// the paused habit was the only one, there is no "whatever else" to be
/// graded on, so the anti-gaming fallback applies instead and every paused
/// day scores zero.
///
/// It exists because the copy was quietly lying about exactly this case.
/// Both the pause confirmation and Room Detail's paused notice promised that
/// "your percentage comes from the habits you can still do", which is true
/// of a three-habit plan and false, in the most consequential possible way,
/// of a one-habit plan. Someone pausing their only linked habit needs to be
/// told they are standing down from that room, not reassured.
final mySoleRoomHabitsProvider = Provider<Map<String, List<RoomModel>>>((ref) {
  final uid = ref.watch(authStateProvider).asData?.value?.uid;
  if (uid == null) return const {};
  final codes = ref.watch(myRoomCodesProvider).valueOrNull ?? const [];
  // The active (non-paused) habit ids — the exact set roomHasGradableHabit
  // resolves against. A counted link that is already paused or deleted is not
  // in here and grades nothing, so it must not be counted toward "sole" either.
  final activeIds = {for (final h in ref.watch(habitListProvider)) h.id};
  final result = <String, List<RoomModel>>{};
  for (final code in codes) {
    final room = ref.watch(roomProvider(code)).valueOrNull;
    if (room == null || room.isEnded) continue;
    final participants = ref.watch(roomParticipantsProvider(code)).valueOrNull;
    if (participants == null) continue;
    final mine = participants.where((p) => p.uid == uid);
    if (mine.isEmpty) continue;
    // "Sole" is about what is still GRADABLE, not how many habits were ever
    // linked. Counting every counted id (paused ones included) let a member
    // with one active and one already-paused habit read as having two, so
    // pausing the last active one slipped past this floor and got the
    // reassuring "graded on the rest" copy while nothing gradable remained and
    // every day scored zero. Filtering to the active list makes the floor fire
    // whenever this pause is the one that empties the gradable set — including
    // the pause-the-second-of-two and one-active-one-deleted cases.
    final activeCounted =
        mine.first.countedHabitIdsIn(room).where(activeIds.contains).toList();
    if (activeCounted.length != 1) continue;
    (result[activeCounted.first] ??= []).add(room);
  }
  return result;
});

/// Habit ids currently earning the 2x room boost: linked to at least one
/// room that's LIVE (leader started it, first day arrived, not ended).
/// Deliberately not lobby/countdown rooms — the boost is the reward for
/// competing, and competition hasn't begun yet there. Read by every
/// completeHabit/uncompleteHabit call site via [roomBoostedReward], and by
/// the Grid row's 2x badge.
final roomBoostedHabitsProvider = Provider<Set<String>>((ref) {
  final linked = ref.watch(myLinkedRoomHabitsProvider);
  return {
    for (final e in linked.entries)
      if (e.value.any((r) => r.isLive)) e.key,
  };
});

/// Rooms whose leader-curated shared plan has grown past what this account
/// has resolved — `mine.linkedHabitIds.length < room.sharedHabits.length`,
/// the exact condition _MyPlanCard's _NewHabitBanner renders for inside
/// Room Detail. Surfaced as its own app-wide provider so HomeShell can
/// prompt the member on app open (see _HomeShellState's
/// _maybePromptNewSharedHabits), instead of the news waiting silently
/// until they happen to visit the room screen.
///
/// Zero additional Firestore cost by construction: every stream this
/// watches (myRoomCodesProvider, roomProvider, roomParticipantsProvider)
/// is already held open app-wide by [myLinkedRoomHabitsProvider], which
/// the Grid's room-badge column keeps alive from the first frame. This
/// only re-reads what is already in memory.
final pendingSharedPlanPromptsProvider =
    Provider<List<({RoomModel room, RoomParticipant mine})>>((ref) {
  final uid = ref.watch(authStateProvider).asData?.value?.uid;
  if (uid == null) return const [];
  final codes = ref.watch(myRoomCodesProvider).valueOrNull ?? const [];
  final out = <({RoomModel room, RoomParticipant mine})>[];
  for (final code in codes) {
    final room = ref.watch(roomProvider(code)).valueOrNull;
    if (room == null || room.isEnded) continue;
    if (room.habitMode != RoomHabitMode.shared) continue;
    final participants =
        ref.watch(roomParticipantsProvider(code)).valueOrNull ?? const [];
    final mine = participants.where((p) => p.uid == uid).toList();
    if (mine.isEmpty) continue;
    if (mine.first.linkedHabitIds.length < room.sharedHabits.length) {
      out.add((room: room, mine: mine.first));
    }
  }
  return out;
});

/// The one seam that turns a habit's base XP/gold into its room-boosted
/// value — used symmetrically by every complete AND uncomplete call site,
/// so a boosted completion undone the same day refunds exactly what it
/// paid (both reads happen under the same live-room state; rooms only
/// change state at day boundaries).
int roomBoostedReward(WidgetRef ref, String habitId, int base) =>
    ref.read(roomBoostedHabitsProvider).contains(habitId) ? base * 2 : base;

/// Pushes this tap's *today* result to any Room tracking [habitId] — a
/// cheap no-op for the overwhelmingly common case where it isn't linked to
/// any room. Reads the already-updated local Grid state (rather than
/// re-reading Firestore) since Grid's own square write is fire-and-forget —
/// see [RoomsController.syncTodayForHabit]'s doc comment for why that
/// matters.
///
/// A shared top-level function (not private to one screen) specifically
/// because completing *and* uncompleting a habit both need to reach here
/// from more than one place: Grid's own square taps, and Dashboard/Today's
/// complete/slip/undo-slip actions (see dashboard_screen.dart's
/// _completeHabit/_slipHabit/_undoSlipHabit). Before this existed, only
/// Grid called the equivalent private helper — completing or removing a
/// completion from Today never reached a linked room at all, so a count
/// set from Today could only ever be corrected by the next full
/// [RoomsController.syncLinkedHabitsProgress] resync (Room Detail's own
/// screen-open sync), not live. Every screen that can flip a habit's today
/// state must call this right after doing so.
void syncRoomToday(WidgetRef ref, String habitId, DateTime day) {
  if (!day.isToday) {
    // A PAST day just changed - either back-filled, or un-ticked to correct a
    // mistake. The fast path below only ever rewrites TODAY's entry, so
    // before this the room kept showing the old number until someone happened
    // to open the room screen again. That's not theoretical: a square
    // corrected to `none` sat there crediting a day it shouldn't have,
    // looking exactly like a counting bug.
    //
    // Only a full resync can revise a past day (it's the only thing that
    // re-reads the day range), so run one for every room this habit is
    // linked to. Unawaited, same fire-and-forget posture as the fast path.
    final pastRooms = ref.read(myLinkedRoomHabitsProvider)[habitId];
    if (pastRooms == null || pastRooms.isEmpty) return;
    final controller = ref.read(roomsControllerProvider);
    for (final room in pastRooms) {
      controller.syncLinkedHabitsProgress(room).ignore();
    }
    return;
  }
  final todayRow =
      ref.read(weeklyGridProvider).states[day.toDateKey()] ?? const {};
  ref
      .read(roomsControllerProvider)
      .syncTodayForHabit(habitId, todayRow)
      .ignore();
}

/// Set the instant a `growdaily://join/CODE` deep link arrives (see
/// main.dart's AppLinks wiring + [parseRoomJoinLink]), consumed exactly
/// once by _OnboardingOrGrid's listener - the first widget that's safe to
/// navigate from, since it only ever builds once the language/auth/
/// onboarding gates are already behind the user - to jump straight to
/// Rooms with the code pre-filled instead of the normal tap-through (open
/// app -> Profile -> Rooms -> Join -> type the code by hand).
final pendingJoinCodeProvider = StateProvider<String?>((ref) => null);

/// Set the instant a room-finish push notification is tapped (see
/// PushNotificationService.onOpenRoom, wired from main.dart), consumed
/// exactly once by the same _OnboardingOrGrid listener that handles
/// [pendingJoinCodeProvider] - the first widget it's safe to navigate from.
/// Deliberately a separate provider rather than reusing
/// [pendingJoinCodeProvider]: that one always means "show the Join sheet
/// for this code," which would be wrong here - a push about a room only
/// ever reaches someone already a participant in it, so this jumps straight
/// to RoomDetailScreen instead, no join step in between.
final pendingOpenRoomCodeProvider = StateProvider<String?>((ref) => null);

/// Parses a `growdaily://join/CODE` deep link into a room code, or null if
/// [uri] doesn't match that shape - so a malformed link, or a link some
/// other feature/OS handler hands this app for an unrelated reason, is
/// silently ignored instead of ever being force-fit into a room-code
/// lookup. The code is upper-cased here to match [previewRoom]'s own
/// normalization, so a link's code always resolves the same way typing it
/// by hand would. See main.dart's AppLinks wiring - the only caller.
String? parseRoomJoinLink(Uri uri) {
  final scheme = uri.scheme.toLowerCase();

  // Universal Link: https://<host>/join/CODE — what every newly shared invite
  // now looks like (see roomJoinUrl).
  //
  // Deliberately NOT checking the host. iOS only ever hands this app an https
  // URL that already matched the associated-domains entitlement, so the host
  // has been verified by the OS before we ever see it — re-checking it here
  // would add nothing except a second place to update on the day the app
  // moves to a custom domain, and would silently break every invite already
  // sitting in someone's chat history from the old host. The path shape is
  // the real signal, and it is ours.
  if (scheme == 'https' || scheme == 'http') {
    final segments = uri.pathSegments;
    if (segments.length < 2) return null;
    if (segments.first.toLowerCase() != 'join') return null;
    final code = segments[1].trim().toUpperCase();
    return code.isEmpty ? null : code;
  }

  // Legacy custom scheme: growdaily://join/CODE. Still parsed because links
  // shared before Universal Links existed are already out there, and they
  // still work for anyone who has the app.
  if (scheme != legacyScheme) return null;
  if (uri.host.toLowerCase() != 'join') return null;
  if (uri.pathSegments.isEmpty) return null;
  final code = uri.pathSegments.first.trim().toUpperCase();
  return code.isEmpty ? null : code;
}

// ─── Name matching (Join Room's "link existing or add new" review step) ───

String _normalizeHabitName(String s) =>
    s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// Classic edit-distance, used only to catch minor spelling differences (see
/// [suggestExistingMatch]) - habit names are short, so the naive O(n*m) DP
/// table here is never worth optimizing further.
int _levenshtein(String a, String b) {
  final la = a.length, lb = b.length;
  if (la == 0) return lb;
  if (lb == 0) return la;
  var prev = List<int>.generate(lb + 1, (j) => j);
  var curr = List<int>.filled(lb + 1, 0);
  for (var i = 1; i <= la; i++) {
    curr[0] = i;
    for (var j = 1; j <= lb; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      curr[j] = min(min(curr[j - 1] + 1, prev[j] + 1), prev[j - 1] + cost);
    }
    final tmp = prev;
    prev = curr;
    curr = tmp;
  }
  return prev[lb];
}

/// Best-guess existing habit to pre-select for a plan entry named
/// [templateName], or null if nothing is close enough to suggest. Always
/// just a *suggestion* - JoinRoomSheet's review step shows it pre-filled but
/// lets the joiner change it before confirming, so a wrong guess here never
/// silently links the wrong habit ("auto-link when confident, otherwise ask"
/// - see the Rooms redesign this implements).
IslamicHabitTemplate? suggestExistingMatch(
  String templateName,
  List<IslamicHabitTemplate> myHabits,
) {
  final target = _normalizeHabitName(templateName);
  for (final h in myHabits) {
    if (_normalizeHabitName(h.name) == target) return h;
  }
  IslamicHabitTemplate? best;
  var bestDist = 1 << 30;
  for (final h in myHabits) {
    final candidate = _normalizeHabitName(h.name);
    if (candidate.length < 4 || target.length < 4) continue;
    final dist = _levenshtein(target, candidate);
    final threshold = (target.length * 0.25).ceil().clamp(1, 3);
    if (dist <= threshold && dist < bestDist) {
      best = h;
      bestDist = dist;
    }
  }
  return best;
}

/// The next leader when [leavingUid] (the room's current leader) leaves,
/// picked as the longest-standing remaining participant - or null if
/// nobody else is left, meaning the room should be deleted outright
/// instead of handed off to no one (see RoomsController.leaveRoom, the
/// only caller). [participants] is expected already sorted by joinedAt
/// ascending (RoomsController.leaveRoom's own Firestore query already
/// orders it that way) - this just picks the first entry that isn't the
/// leaving uid, it doesn't re-sort. A plain top-level function, not a
/// RoomsController method, specifically so it's testable without any
/// Firestore involved - same reasoning as [suggestExistingMatch] above.
RoomParticipant? nextLeaderAfter(
  String leavingUid,
  List<RoomParticipant> participants,
) {
  for (final p in participants) {
    if (p.uid != leavingUid) return p;
  }
  return null;
}

/// Removes [habitId] from a participant's linked-habit arrays, keeping
/// [linkedHabitIds]/[linkedHabitNames] in sync - they're parallel arrays,
/// same index means the same habit (see RoomParticipant.linkedHabitIds'
/// doc comment). A plain top-level function so the index-matching logic is
/// unit-testable without any Firestore involved - same reasoning as
/// [suggestExistingMatch]/[nextLeaderAfter] above. The only caller is
/// [RoomsController.unlinkHabitEverywhere]. A no-op (returns the inputs
/// unchanged) when [habitId] isn't actually present - callers don't need
/// to check first.
(List<String>, List<String>) removeLinkedHabit(
  List<String> linkedHabitIds,
  List<String> linkedHabitNames,
  String habitId, {
  /// True in a SHARED room, where linkedHabitIds is index-for-index parallel
  /// with RoomModel.sharedHabits and every read site in the feature relies
  /// on that (see kDeclinedSlot's doc comment).
  ///
  /// Deleting the entry shifts every later slot down one, so slot[1]'s habit
  /// silently starts being graded against slot[0]'s frozen rule — a member
  /// who unlinks the first of three shared habits gets the wrong cadence
  /// applied to the other two, permanently and invisibly. It also shortens
  /// the list, which is the exact condition the unresolved-plan banner reads
  /// as "hasn't decided yet", so the slot reappears as an unanswered prompt.
  /// The sentinel keeps the position and counts for nothing.
  bool preserveSlots = false,
}) {
  final idx = linkedHabitIds.indexOf(habitId);
  if (idx < 0) return (linkedHabitIds, linkedHabitNames);
  if (preserveSlots) {
    final ids = [...linkedHabitIds]..[idx] = kDeclinedSlot;
    final names = idx < linkedHabitNames.length
        ? ([...linkedHabitNames]..[idx] = '')
        : linkedHabitNames;
    return (ids, names);
  }
  final ids = [...linkedHabitIds]..removeAt(idx);
  // Older docs could in theory have a names list that's already shorter
  // than ids (never expected going forward, but cheap to guard) - only
  // remove the matching index when it's actually still there instead of
  // throwing a RangeError.
  final names = idx < linkedHabitNames.length
      ? ([...linkedHabitNames]..removeAt(idx))
      : linkedHabitNames;
  return (ids, names);
}

/// Compact "starts in ___" fragment for a countdown too small to spend a
/// full row on - RoomsHubScreen's list pill, next to every other room's
/// one-line status. Picks the single coarsest unit that still says
/// something useful (days, else hours, else minutes) rather than a full
/// breakdown - a list tile has room for "2d" or "45m", not "2d 03h 12m
/// 08s" the way RoomDetailScreen's own big countdown affords. A plain
/// top-level function (not part of the `S` l10n class) since a unit
/// letter/word glued straight onto a digit ("2d", "45m") isn't sentence
/// text needing grammatical agreement the way a full phrase would - same
/// reasoning as [_levenshtein]/[suggestExistingMatch] above for keeping
/// pure computation out of the controller and out of `S`. Never ticks on
/// its own (unlike RoomDetailScreen's per-second Timer) - a list of many
/// rooms re-renders this from scratch on every Firestore snapshot anyway,
/// which is coarse enough for a list.
String formatCompactRemaining(Duration remaining, {required bool isAr}) {
  final clamped = remaining.isNegative ? Duration.zero : remaining;
  final days = clamped.inDays;
  if (days > 0) {
    final hours = clamped.inHours % 24;
    return isAr ? '$daysي $hoursس' : '${days}d ${hours}h';
  }
  final hours = clamped.inHours;
  if (hours > 0) {
    final minutes = clamped.inMinutes % 60;
    return isAr ? '$hoursس $minutesد' : '${hours}h ${minutes}m';
  }
  final minutes = clamped.inMinutes;
  if (minutes > 0) return isAr ? '$minutesد' : '${minutes}m';
  return isAr ? 'أقل من دقيقة' : '<1m';
}

/// Result of checking one flexible weekly-quota linked habit ("N times a
/// week," HabitFrequencyType.weekly, not tied to specific weekdays)
/// against one calendar week - see [weeklyHabitCreditFor].
enum WeeklyHabitCredit {
  /// Target met (whether the week's over yet or not) - every day of this
  /// week counts as fully done for this habit.
  credited,

  /// Week's over and the target wasn't met - every day of this week
  /// counts as missed for this habit.
  missed,

  /// Week's still in progress and the target isn't met *yet* - too soon
  /// to call it either way, so every day of this week is excused (not
  /// counted as scheduled at all) until it resolves one way or the other.
  pending,
}

/// Whether one flexible weekly-quota linked habit should read as
/// [WeeklyHabitCredit.credited]/[missed]/[pending] for one calendar week,
/// given how many times it's actually been done that week so far.
///
/// A weekly-quota habit's whole *week* is pass/fail, not any single day
/// within it: "sport, 4x/week," done 5 times while skipping 2 other days,
/// is a perfect week, not "2 misses." [syncLinkedHabitsProgress] applies
/// whichever result this returns to *every* day of that week uniformly,
/// rather than trying to pin credit or blame on whichever specific days
/// were or weren't done - which days doesn't matter, only the total does.
///
/// [isWeekClosed] is whether every day of that calendar week has fully
/// *passed* — see [isQuotaWeekClosed] for the boundary, including why the
/// week's own last day still counts as open while it is today. While the
/// week is open and the target isn't met yet, this reads as
/// [WeeklyHabitCredit.pending] rather than [missed] - the same grace an
/// unfinished *today* already gets a regular habit's streak (see
/// [RoomParticipant.currentStreak]'s doc comment), extended here to a
/// whole week instead of a single day. Meeting the target early, before
/// the week is even over, still credits immediately (checked first, ahead
/// of [isWeekClosed]) rather than making someone wait until Sunday to see
/// it reflected.
WeeklyHabitCredit weeklyHabitCreditFor({
  required int completions,
  required int target,
  required bool isWeekClosed,
}) {
  if (completions >= target) return WeeklyHabitCredit.credited;
  return isWeekClosed ? WeeklyHabitCredit.missed : WeeklyHabitCredit.pending;
}

/// Which of one calendar week's days a flexible weekly-quota habit ("4x a
/// week, any days") is actually answerable for — the days that belong in that
/// day's denominator. Every other day of the week is an excused rest day, the
/// exact same standing a Mon/Wed-only habit's Tuesday already has (see
/// [RoomParticipant.creditFor]: "A day where nothing was scheduled at all is
/// full credit, not zero — there was nothing to fall short of").
///
/// This is the piece that used to be missing. Grading counted *every* day of
/// the week against a weekly-quota habit, because a habit like this has no
/// specific weekdays for the weekday check to rule any day out with. So "4x a
/// week", done faithfully 4 times, scored 4/7 = 57% — forever, by
/// construction — while the identical commitment expressed as four *named*
/// weekdays scored 100%. Two ways of saying the same thing, one of which
/// quietly told the person they were failing.
///
/// Returns indices into [presentDays] (which must be chronological, and
/// already filtered to the days this habit existed on within the room's
/// range). [doneDays] is the subset of those that are green.
///
/// The three cases:
///  - Target reached: only the days actually done are answerable; the rest of
///    the week is rest, and rest that was earned is not a miss. Checked first
///    so hitting the target early credits immediately rather than making
///    someone wait for the week to close, matching [weeklyHabitCreditFor].
///  - Target not reached and the week is still open: every day so far counts.
///    A week in progress is never handed its rest days in advance — that's
///    the same "credit before the fact" trap [quotaOkWeeks] documents for
///    streaks, and it would read as a spotless week that decays as the week
///    goes on. It reads steppy (the week jumps to full the moment the target
///    lands) and that is the deliberate trade: never inflated.
///  - Target not reached and the week is closed: the shortfall is real, so
///    that many days are answerable on top of the ones done — and *which*
///    days is not arbitrary: they are the week's [DayDemand.owed] days, the
///    exact days [weeklyQuotaDemand] says the target actually broke on and
///    the exact days the Grid paints red. An earlier version pinned the
///    shortfall on the earliest empty days instead, which meant the room's
///    strip could mark Saturday missed while the Grid marked Wednesday red
///    for the same week — same count, contradictory screens. The count is
///    unchanged either way (owed-and-empty days == the shortfall, proved in
///    weekly_quota_plan_test.dart), so scores and percentages are identical;
///    only the placement moved, onto the days the person actually saw break.
///
/// [target] is capped at [presentDays].length so a room's short first or last
/// week can't demand more days than it contains.
List<int> weeklyQuotaScheduledDays({
  required List<int> presentDays,
  required Set<int> doneDays,
  required int target,
  required bool isWeekClosed,
}) {
  if (presentDays.isEmpty) return const [];
  final effectiveTarget = target.clamp(1, presentDays.length);
  final done = presentDays.where(doneDays.contains).toList();
  if (done.length >= effectiveTarget) return done;
  if (!isWeekClosed) return presentDays;
  // Closed and short. weeklyQuotaDemand works in week positions (0-based),
  // presentDays holds indices into the sync's own day range — translate in,
  // then back out. Answerable = done days + owed days; spare/earned days are
  // the excused rest.
  final demand = weeklyQuotaDemand(
    dayCount: presentDays.length,
    doneDays: {
      for (var p = 0; p < presentDays.length; p++)
        if (doneDays.contains(presentDays[p])) p,
    },
    target: effectiveTarget,
  );
  return [
    for (var p = 0; p < presentDays.length; p++)
      if (!demand[p].isRest) presentDays[p],
  ];
}

/// Whether [weekStart]'s calendar week is final for quota grading — every one
/// of its days has fully PASSED, or the room itself is over.
///
/// The boundary matters and got it wrong once: the old inline check treated
/// the week as closed the moment [lastCountedDay] *reached* the week's last
/// day, i.e. all day Friday on a Saturday-start grid week. Friday morning a
/// "4x, 2 done" week was therefore graded as already failed: the shortfall
/// was pinned onto past days, Friday itself was excused as rest, and the plan
/// card greeted the person with "Done for today" on the one day that was
/// literally their last chance to act — while the Grid, asking the day-local
/// question (see weeklyQuotaDemand), correctly counted Friday as still owed.
/// A week's last day gets the same grace any unfinished *today* gets;
/// only a day that is fully behind you can be graded as final.
bool isQuotaWeekClosed({
  required DateTime weekStart,
  required DateTime lastCountedDay,
  required bool roomEnded,
}) =>
    weekStart.add(const Duration(days: 6)).isBefore(lastCountedDay) ||
    roomEnded;

/// How many trailing days [RoomsController.syncLinkedHabitsProgress] actually
/// re-reads and re-grades, rather than the room's whole history (see the
/// comment at its `windowStart`). Sized to comfortably cover both reasons a
/// past day can legitimately change: back-filling a forgotten Grid square,
/// and a flexible weekly quota filling up later in its own week. 45 days is
/// six full weeks plus slack, well beyond anything a person realistically
/// back-fills, while capping an open-ended room's per-visit read cost at a
/// constant instead of one-per-day-forever.
const int kRoomSyncWindowDays = 45;

/// Above this many members, a room joins MUTED by default (see
/// [RoomsController.joinRoom]).
///
/// Must stay in step with FANOUT_MEMBER_LIMIT in functions/index.js, which
/// uses the same number to decide when a room stops sending one push per
/// finisher. The two are the same idea from opposite ends: the server caps
/// what a big room may send, this decides what a new member hears by default.
///
/// Why default to silence rather than trusting the cap alone: the cap is a
/// decision nobody can see or undo, and a room this size is usually one
/// someone joined out of interest rather than to be pinged by. A muted bell
/// in the room's own app bar is visible, honest and one tap from reversing -
/// and thanks to the server cap, reversing it is pleasant (one "first to
/// finish today" a day) rather than the ~199-a-day firehose per-finisher
/// notifications would otherwise be in a 200-person room.
const int kRoomAutoMuteMemberLimit = 12;

/// The rule in force on [dateKey] out of [rules] - the latest period that
/// had already started by then, falling back to the earliest recorded period
/// for a day before any of them begin (a room day preceding the first
/// stamped rule, which can happen once an explicit re-lock appends a period
/// starting later than the room did). [rules] must not be empty; every
/// caller builds it so that it can't be. Plain top-level function, unit-
/// testable with a hand-built list and no Firestore involved, same reasoning
/// as [weeklyHabitCreditFor] above.
///
/// Date keys are YYYY-MM-DD, so string comparison is already chronological.
RoomHabitRule roomRuleAt(List<RoomHabitRule> rules, String dateKey) {
  var earliest = rules.first;
  RoomHabitRule? best;
  for (final r in rules) {
    if (r.from.compareTo(earliest.from) < 0) earliest = r;
    if (r.from.compareTo(dateKey) <= 0 &&
        (best == null || r.from.compareTo(best.from) > 0)) {
      best = r;
    }
  }
  return best ?? earliest;
}

/// Whether [habit] existed at all on [day] - the createdAt/archivedAt half
/// of IslamicHabitTemplate.isScheduledFor, split out so room grading can
/// apply the "was this habit alive yet" bound while taking the weekday
/// restriction from the room's own frozen [RoomHabitRule] instead of the
/// habit's current one. Mirrors that method's two date checks exactly,
/// including archivedAt's "the archive day itself still counts".
/// Names of [mine]'s linked habits whose live settings no longer match the
/// cadence this room is actually scoring them by (see
/// [RoomParticipant.habitRules]) - what the room's "your settings differ"
/// warning lists, and what [RoomsController.relockHabitRules] would bring
/// into line if the person opts in.
///
/// This is the visible half of freezing the rules. Without it, someone who
/// changes تمرين from 4x to 7x a week would see the room quietly keep
/// scoring 4x with no explanation, which trades a silent wrong number for a
/// silent confusing one. Naming the mismatch out loud, with a way to act on
/// it, is what makes the freeze honest rather than mysterious.
///
/// Empty (the overwhelmingly common case) whenever every linked habit still
/// matches, and for any habit with no recorded rule yet or no longer in this
/// account's own habit list. A plain top-level function for the same
/// unit-testability reasons as [roomRuleAt] above.
List<String> roomRuleMismatches(
  RoomParticipant mine,
  List<IslamicHabitTemplate> myHabits,
  String todayKey,
) {
  final habitById = {for (final h in myHabits) h.id: h};
  final out = <String>[];
  for (final id in mine.countedHabitIds) {
    final habit = habitById[id];
    if (habit == null) continue;
    final rule = mine.ruleFor(id, todayKey);
    if (rule == null) continue;
    if (rule.differsFrom(
      frequencyType: habit.frequencyType,
      frequencyTarget: habit.frequencyTarget,
      scheduledWeekdays: habit.scheduledWeekdays,
    )) {
      out.add(habit.name);
    }
  }
  return out;
}

/// The linked habits this device cannot find on the active board, split by
/// the two very different reasons that happens.
///
/// Pausing a habit archives it, and archiving drops it out of
/// habitListProvider immediately, exactly as deleting does. Room Detail
/// resolves its linked ids against that one list, so for a long time it
/// could only tell the deleted story: pausing a linked habit announced that
/// the habit no longer existed and advised leaving the room to relink it.
/// Every part of that is wrong for a pause, and the advice is the
/// destructive kind, since [RoomsController.leaveRoom] deletes the
/// participant doc and takes every day of room progress with it. Someone
/// who paused تمرين for a broken leg was being told to wipe a 90-day room
/// to fix something that un-fixes itself on Resume.
///
/// [pausedHabits] is pausedHabitsProvider, which is the only list that can
/// tell the two apart. Anything unresolved and NOT in it is genuinely gone.
///
/// Note this deliberately says nothing about grading, which does not change
/// either way: a paused habit stays in the room's denominator on purpose,
/// because dropping it would pay a member full marks for pausing everything
/// (see test/features/rooms/paused_habit_room_grading_test.dart). The split
/// only decides which sentence the member reads.
({List<String> pausedNames, bool hasDeleted}) roomUnresolvedLinks(
  RoomParticipant mine,
  List<IslamicHabitTemplate> myHabits,
  List<IslamicHabitTemplate> pausedHabits, {
  required bool isAr,
}) {
  final activeIds = {for (final h in myHabits) h.id};
  // Keyed by id: a catalog habit switched on and off more than once emits
  // one entry per stint here, all sharing an id (see pausedHabitsProvider).
  final pausedById = {for (final h in pausedHabits) h.id: h};
  final pausedNames = <String>[];
  var hasDeleted = false;
  // countedHabitIds, not linkedHabitIds: a slot this person skipped holds
  // the literal kDeclinedSlot placeholder, which is never a real habit id
  // and would otherwise trip this permanently.
  for (final id in mine.countedHabitIds) {
    if (activeIds.contains(id)) continue;
    final paused = pausedById[id];
    if (paused != null) {
      pausedNames.add(paused.localName(isAr));
    } else {
      hasDeleted = true;
    }
  }
  return (pausedNames: pausedNames, hasDeleted: hasDeleted);
}

/// Whether this device can grade at least one of [countedIds] right now.
///
/// The single switch behind how a room treats a linked habit it cannot
/// resolve, which is either a habit the member PAUSED or a link that
/// outlived its habit. Both leave habitListProvider, so neither appears in
/// [resolvableIds].
///
/// ── Why this exists ─────────────────────────────────────────────────────
/// The two sync paths used to answer this question separately and gave
/// opposite answers. syncLinkedHabitsProgress credited an unresolvable link
/// as DONE (numerator and denominator both up); syncTodayForHabit counted it
/// as scheduled and never done (denominator only). Both comments called
/// themselves "fails open". A member's percentage therefore depended on
/// which path had written their doc last: tapping a Grid square scored a
/// paused habit as a miss, and opening Room Detail regraded the same 45 days
/// as a pass. The number visibly moved on its own.
///
/// ── The rule both paths now follow ──────────────────────────────────────
/// A habit this device cannot grade is dropped from BOTH sides: it is not
/// scheduled and not done, so a member with a paused habit is scored on
/// what they can actually do. Somebody who paused one of three is graded
/// out of two, and doing those two reads 100%, which is the honest number.
///
/// The exception is the degenerate case this returns false for. If NOTHING
/// is resolvable, dropping everything would leave a day that asks nothing,
/// and a day that asks nothing is full credit here by design (see
/// RoomParticipant.creditFor and paused_habit_room_grading_test) — so
/// pausing every linked habit would pay 100% a day forever.
///
/// What the caller does about that has changed once. It used to count every
/// id as scheduled and never done, scoring the member ZERO for each of those
/// days, on the reasoning that they had paused their entire commitment and
/// were not participating. True as far as it went, and far too blunt in
/// practice: measured on room A8GEL7, pausing a 4x-a-week habit on 2 Aug read
/// 13% against 93%, took a 26-day streak to 0, and filled a month of the
/// member's strip with red crosses for days nobody had asked them about.
/// Standing a habit down was worse than never opening the app.
///
/// The caller now records those days in RoomParticipant.standDownDays
/// instead, which excludes them from BOTH sides — so the percentage holds
/// still rather than collapsing, and the free-100% hole stays shut because a
/// stand-down day is not a rest day: creditFor returns 0 for it and
/// isFullyDone is false. A link with no habit behind it at all is NOT a
/// stand-down (nobody chose to step back from a habit that was deleted) and
/// still falls to the old scheduled-and-never-done treatment.
bool roomHasGradableHabit(
  List<String> countedIds,
  Set<String> resolvableIds,
) =>
    countedIds.any(resolvableIds.contains);

bool habitExistedOn(IslamicHabitTemplate habit, DateTime day) {
  final born = habit.createdAt;
  if (born != null && day.isBefore(DateTime(born.year, born.month, born.day))) {
    return false;
  }
  final died = habit.archivedAt;
  if (died != null && day.isAfter(DateTime(died.year, died.month, died.day))) {
    return false;
  }
  return true;
}

/// Every write in this feature goes through here rather than sitting on a
/// StateNotifier: there's no single piece of UI state to own (the stream
/// providers above already give every screen a live view), just a set of
/// one-off actions - create, join, leave, sync - so a plain read-only
/// Provider handing out this controller is a better fit than forcing an
/// empty/dummy StateNotifier state to hang them off of.
class RoomsController {
  RoomsController(this._ref);
  final Ref _ref;

  String? get _uid => _ref.read(authStateProvider).asData?.value?.uid;

  CollectionReference<Map<String, dynamic>> get _rooms =>
      FirebaseFirestore.instance.collection('rooms');

  DocumentReference<Map<String, dynamic>> _userRef(String uid) =>
      FirebaseFirestore.instance.collection('users').doc(uid);

  /// Denormalized display fields every participant write refreshes, so a
  /// leaderboard row never shows a stale name/avatar from whenever this
  /// person first joined - same idea as CharacterNotifier snapshotting
  /// itself onto users/{uid} for other features to read cheaply.
  Map<String, dynamic> _profileFields() {
    final dashboard = _ref.read(dashboardProvider);
    final savedName = dashboard.displayName.trim();
    final email = _ref.read(authStateProvider).asData?.value?.email;
    // Every branch here ends up on a public leaderboard, so every branch
    // is screened. savedName went through setDisplayName's filter when it
    // was set, but screening again costs nothing and covers names saved
    // before the filter existed; the email local-part never met any filter
    // at all (see _createUserDoc for the same reasoning at the seed).
    final rawName = savedName.isNotEmpty
        ? savedName
        : (email?.split('@').first ?? 'Warrior');
    final displayName = isObjectionable(rawName) ? 'Warrior' : rawName;
    final character = _ref.read(characterProvider);
    // Same cosmetic mirror as characterId/accessoryId above - the real
    // source of truth stays prestigeProvider/DashboardState.level; this is
    // just what the leaderboard row (RoomParticipant.prestigeTierId) reads
    // without a per-room-member Firestore round trip. Written unconditionally,
    // even at the base "Seeker" tier - whether a chip is worth showing off
    // is _LeaderboardRow's own display-time call (mirroring the Profile hero
    // header's identical restraint), not something baked into the write.
    final prestigeTierId =
        _ref.read(prestigeProvider).displayedTier(dashboard.level).id;
    return {
      'displayName': displayName,
      // Omitted entirely while the character is still loading, rather than
      // written as whatever CharacterState's constructor defaults to.
      //
      // This was a real, visible bug: `_ref.read(characterProvider)` CREATES
      // the notifier on first read and returns `const CharacterState()`
      // synchronously — characterId 'male_ghutra_blue', isLoading true —
      // while its `_load()` is still in flight. Every sync that ran before
      // anything had rendered the Profile hero (app resume, a deep link, or
      // ticking a linked habit from the Grid) therefore *overwrote* the
      // member's real character with the male default, and the leaderboard
      // then faithfully drew a man for someone who had picked otherwise.
      // The Profile hero already guards on isLoading for exactly this
      // reason; this call site trusted the same state blindly.
      //
      // Leaving the key out is what makes it safe: these go through
      // SetOptions(merge: true) / update(), so an absent key preserves
      // whatever is already stored, and a genuinely-unknown id is already
      // handled downstream (RoomParticipant reads '' and the leaderboard
      // falls back to a neutral silhouette).
      if (!character.isLoading) 'characterId': character.characterId,
      // Gender, mirrored purely so the room-finish push can be written in
      // correct Arabic.
      //
      // Arabic verbs agree with the subject, and functions/index.js had only
      // a masculine form: a woman finishing her habits was announced as
      // «أنهى عاداته» — "he finished HIS habits". The Cloud Function has no
      // access to the Dart character catalog, and inferring from the id's
      // "male_"/"female_" prefix would silently break the first time an id
      // is renamed. So resolve it here, where the catalog actually lives.
      //
      // Gated on isLoading for the same reason characterId is, and omitted
      // rather than defaulted when the character is unknown — the function
      // falls back to neutral phrasing, which is better than confidently
      // misgendering someone.
      if (!character.isLoading)
        'gender':
            CharacterCatalog.findById(character.characterId)?.gender.name,
      if (!character.isLoading && character.equippedAccessoryId != null)
        'accessoryId': character.equippedAccessoryId,
      'prestigeTierId': prestigeTierId,
    };
  }

  /// Re-writes this user's character onto every room they're in, once the
  /// character is genuinely loaded.
  ///
  /// The repair half of the fix above. Stopping the bad write protects
  /// rooms from here on, but it does nothing for the docs already corrupted
  /// — those keep showing the male default until something happens to
  /// rewrite them, and nothing routinely does. This runs after a confirmed
  /// load and fixes them in place.
  ///
  /// Cheap and idempotent: one merge-set per room the user belongs to,
  /// writing two cosmetic fields, and a no-op once the stored value already
  /// agrees. Failures are swallowed on purpose — a cosmetic backfill must
  /// never surface an error over a screen the user didn't ask it from.
  Future<void> repairMyCharacterEverywhere() async {
    final uid = _uid;
    if (uid == null) return;
    final character = _ref.read(characterProvider);
    if (character.isLoading || character.characterId.isEmpty) return;
    final codes =
        _ref.read(myRoomCodesProvider).valueOrNull ?? const <String>[];
    for (final code in codes) {
      final roster = _ref.read(roomParticipantsProvider(code)).valueOrNull;
      final mine = roster?.where((p) => p.uid == uid).firstOrNull;
      // No roster loaded yet, or already correct — nothing to repair. The
      // next call picks it up once the stream has data.
      if (mine == null) continue;
      if (mine.characterId == character.characterId) continue;
      try {
        await _rooms.doc(code).collection('participants').doc(uid).set(
          {
            'characterId': character.characterId,
            if (character.equippedAccessoryId != null)
              'accessoryId': character.equippedAccessoryId,
          },
          SetOptions(merge: true),
        );
      } catch (_) {
        // Cosmetic only — see the doc comment.
      }
    }
  }

  /// Generates codes until one isn't already taken. Collisions are
  /// astronomically unlikely (see generateRoomCode's doc comment) - this
  /// loop is just defensive, matching how carefully everything else in the
  /// app double-checks writes rather than assuming they can't collide.
  Future<String> _newUniqueCode() async {
    for (var attempt = 0; attempt < 6; attempt++) {
      final code = generateRoomCode();
      final snap = await _rooms.doc(code).get();
      if (!snap.exists) return code;
    }
    throw Exception('room-code-generation-failed');
  }

  /// Creates a room and adds the caller as its first participant. In
  /// 'shared' mode, [planHabitIds] are the *leader's own* existing habit
  /// ids that make up the plan - each gets snapshotted onto the room as a
  /// [RoomHabitTemplate] (for joiners to match/clone against) while the
  /// leader's own participant doc links those exact ids directly, no
  /// cloning needed for the person who already has them. In 'own' mode,
  /// [leaderLinkedHabitIds] are the leader's own existing habit ids to
  /// track for this room directly - one or more, no cloning/plan snapshot
  /// involved since every participant (leader included) always picks from
  /// their own list. Returns the new code, or null if nobody's signed in
  /// (RoomsHubScreen's guest gate should mean this never actually happens
  /// in practice).
  Future<String?> createRoom({
    required String name,
    required RoomHabitMode habitMode,
    List<String> planHabitIds = const [],
    required RoomDuration duration,
    int? lengthDays,
    List<String> leaderLinkedHabitIds = const [],
    List<String> leaderLinkedHabitNames = const [],
    RoomCompeteMode competeMode = RoomCompeteMode.competitive,
  }) async {
    final uid = _uid;
    if (uid == null) return null;
    final code = await _newUniqueCode();
    // Rooms are now born in the LOBBY: members gather, nothing counts, and
    // the real dates get written when the leader presses Start (see
    // [startRoom]) — everyone begins the same fair, full first day instead
    // of late joiners entering a race that started without them. startDate
    // here is a placeholder that startRoom overwrites; endDate stays null
    // until then (lengthDays rides along on the doc for fixed rooms).
    final startDate = DateTime.now().effectiveDay;
    final profile = _profileFields();

    final myHabits = _ref.read(habitListProvider);
    final planHabits = habitMode == RoomHabitMode.shared
        ? [
            for (final id in planHabitIds)
              if (myHabits.where((h) => h.id == id).isNotEmpty)
                myHabits.firstWhere((h) => h.id == id),
          ]
        : const <IslamicHabitTemplate>[];

    final room = RoomModel(
      code: code,
      name: name.trim(),
      createdBy: uid,
      createdByName: profile['displayName'] as String,
      createdAt: DateTime.now(),
      habitMode: habitMode,
      sharedHabits: planHabits
          .map(
            (h) => RoomHabitTemplate(
              name: h.name,
              category: h.category,
              iconColorHex: h.iconColorHex,
              frequencyType: h.frequencyType,
              frequencyTarget: h.frequencyTarget,
            ),
          )
          .toList(),
      duration: duration,
      startDate: startDate,
      status: 'lobby',
      lengthDays: duration == RoomDuration.fixed ? lengthDays : null,
      competeMode: competeMode,
    );
    final participant = RoomParticipant(
      uid: uid,
      displayName: profile['displayName'] as String,
      characterId: profile['characterId'] as String,
      accessoryId: profile['accessoryId'] as String?,
      prestigeTierId: profile['prestigeTierId'] as String?,
      joinedAt: DateTime.now(),
      linkedHabitIds: habitMode == RoomHabitMode.shared
          ? planHabits.map((h) => h.id).toList()
          : leaderLinkedHabitIds,
      linkedHabitNames: habitMode == RoomHabitMode.shared
          ? planHabits.map((h) => h.name).toList()
          : leaderLinkedHabitNames,
      lastUpdated: DateTime.now(),
    );

    await _rooms.doc(code).set(room.toFirestore());
    await _rooms
        .doc(code)
        .collection('participants')
        .doc(uid)
        .set(participant.toFirestore());
    await _userRef(uid).set(
      {
        'roomCodes': FieldValue.arrayUnion([code]),
      },
      SetOptions(merge: true),
    );
    // Immediate sync so today's progress (if already done before the room
    // even existed) shows up right away instead of waiting for the next
    // Grid tap or Room Detail open.
    if (participant.linkedHabitIds.isNotEmpty) {
      await syncLinkedHabitsProgress(room);
    }
    return code;
  }

  /// One-shot lookup for the Join sheet, so it can show "Aziz's Fajr
  /// Challenge - 4 members" before actually joining anything. Null means no
  /// room has this code.
  Future<RoomModel?> previewRoom(String code) async {
    final snap = await _rooms.doc(code.trim().toUpperCase()).get();
    return snap.exists ? RoomModel.fromFirestore(snap) : null;
  }

  /// Resolves one [RoomHabitTemplate] slot to a real habit id/name pair -
  /// the one shared decision every "which real habit covers this plan
  /// entry" moment in this file boils down to, whether that's [joinRoom]
  /// working through a whole plan at once or [resolvePlanHabit] catching up
  /// on a single slot added after the fact. [existingHabitId], when given
  /// and still actually present in this account's own habit list, links
  /// straight to it - no cloning needed for a habit already owned. Anything
  /// else (no choice made, or the chosen habit's since been deleted) clones
  /// a fresh one from the template's own snapshot, same as a plan entry
  /// nobody already had a match for.
  (String, String) _resolveTemplate(
    RoomHabitTemplate template,
    String? existingHabitId,
  ) {
    if (existingHabitId != null) {
      final myHabits = _ref.read(habitListProvider);
      final found = myHabits.where((h) => h.id == existingHabitId);
      if (found.isNotEmpty) {
        final match = found.first;
        return (match.id, match.name);
      }
    }
    final created = _ref.read(customHabitsProvider.notifier).add(
          name: template.name,
          category: template.category,
          frequencyType: template.frequencyType,
          frequencyTarget: template.frequencyTarget,
          iconColorHex: template.iconColorHex,
        );
    return (created.id, created.name);
  }

  /// Joins [room] (already fetched via [previewRoom]). Safe to call again
  /// for a room already joined - refreshes the profile snapshot (and linked
  /// habits, if new ones were passed) instead of erroring, so re-tapping a
  /// stale invite never breaks anything.
  ///
  /// In 'shared' mode, [planResolutions] is one entry per [RoomModel.
  /// sharedHabits], in the same order - either an existing habit id to link,
  /// or null to create a fresh habit from that plan entry's own snapshot
  /// (see JoinRoomSheet's review step, where these decisions are made with
  /// a smart pre-filled suggestion the joiner can always override).
  ///
  /// Refuses an already-[RoomModel.isEnded] room (returns false) - belt and
  /// suspenders alongside JoinRoomSheet's own `_canJoin` gate, since a deep
  /// link (see parseRoomJoinLink) can land here too and shouldn't rely on
  /// the sheet's UI state alone to keep a dead room from accepting new
  /// members.
  Future<bool> joinRoom(
    RoomModel room, {
    List<String> linkedHabitIds = const [],
    List<String> linkedHabitNames = const [],
    List<String?> planResolutions = const [],
  }) async {
    final uid = _uid;
    if (uid == null || room.isEnded) return false;
    final participantRef =
        _rooms.doc(room.code).collection('participants').doc(uid);
    final existing = await participantRef.get();
    final profile = _profileFields();

    var resolvedIds = const <String>[];
    var resolvedNames = const <String>[];
    if (room.habitMode == RoomHabitMode.shared &&
        room.sharedHabits.isNotEmpty) {
      final ids = <String>[];
      final names = <String>[];
      for (var i = 0; i < room.sharedHabits.length; i++) {
        final resolution =
            i < planResolutions.length ? planResolutions[i] : null;
        final (id, name) = _resolveTemplate(room.sharedHabits[i], resolution);
        ids.add(id);
        names.add(name);
      }
      resolvedIds = ids;
      resolvedNames = names;
    } else if (room.habitMode == RoomHabitMode.own &&
        linkedHabitIds.isNotEmpty) {
      resolvedIds = linkedHabitIds;
      resolvedNames = linkedHabitNames;
    }

    if (existing.exists) {
      await participantRef.set(
        {
          ...profile,
          if (resolvedIds.isNotEmpty) ...{
            'linkedHabitIds': resolvedIds,
            'linkedHabitNames': resolvedNames,
          },
        },
        SetOptions(merge: true),
      );
      // The rejoin path is also the only self-heal a half-applied first
      // join has: the first join's three writes are sequential and
      // unbatched, so a kill or dropped connection after the participant
      // doc landed left this account on the leaderboard with the room
      // permanently missing from its own roomCodes list (the sole source
      // of "my rooms") — and retrying the join used to end here without
      // ever writing it. arrayUnion is idempotent, so an ordinary rejoin
      // costs one no-op write.
      await _userRef(uid).set(
        {
          'roomCodes': FieldValue.arrayUnion([room.code]),
        },
        SetOptions(merge: true),
      );
      await syncLinkedHabitsProgress(room);
      return true;
    }

    // A big room arrives muted - see [kRoomAutoMuteMemberLimit]. memberCount
    // rather than a fresh roster read: this is a threshold, not a headcount,
    // and being one or two out either side of 12 changes nothing.
    final joinsMuted = room.memberCount > kRoomAutoMuteMemberLimit;
    final participant = RoomParticipant(
      uid: uid,
      displayName: profile['displayName'] as String,
      characterId: profile['characterId'] as String,
      accessoryId: profile['accessoryId'] as String?,
      prestigeTierId: profile['prestigeTierId'] as String?,
      joinedAt: DateTime.now(),
      linkedHabitIds: resolvedIds,
      linkedHabitNames: resolvedNames,
      notificationsMuted: joinsMuted,
      lastUpdated: DateTime.now(),
    );
    await participantRef.set(participant.toFirestore());
    await _rooms.doc(room.code).set(
      {
        'memberCount': FieldValue.increment(1),
      },
      SetOptions(merge: true),
    );
    await _userRef(uid).set(
      {
        'roomCodes': FieldValue.arrayUnion([room.code]),
      },
      SetOptions(merge: true),
    );
    if (resolvedIds.isNotEmpty) await syncLinkedHabitsProgress(room);
    return true;
  }

  /// Resolves this participant's own link for exactly one shared-plan slot
  /// that appeared *after* they joined (or last resolved) - the catch-up
  /// counterpart to [joinRoom]'s full-plan pass, for when [addSharedHabit]
  /// adds a habit to a room someone's already in. Appends to the END of
  /// [RoomParticipant.linkedHabitIds]/[linkedHabitNames] rather than
  /// rebuilding them, preserving the 1:1 positional correspondence with
  /// [RoomModel.sharedHabits] every other read site (joinRoom included)
  /// already assumes.
  ///
  /// [templateIndex] must be exactly this participant's current
  /// linkedHabitIds.length - i.e. "the very next slot in line" - anything
  /// else is a no-op, so a stale call (e.g. two taps before the UI catches
  /// up, or the room having changed again since this was queued) can never
  /// resolve the same slot twice or skip one out of order.
  Future<void> resolvePlanHabit(
    RoomModel room,
    int templateIndex, {
    String? existingHabitId,
  }) async {
    final uid = _uid;
    if (uid == null) return;
    if (templateIndex < 0 || templateIndex >= room.sharedHabits.length) return;
    final participantRef =
        _rooms.doc(room.code).collection('participants').doc(uid);
    final snap = await participantRef.get();
    if (!snap.exists) return;
    final participant = RoomParticipant.fromFirestore(snap);
    // Either the very next slot in line (the ordinary catch-up case), or an
    // earlier slot this participant previously SKIPPED and is now changing
    // their mind about (see [kDeclinedSlot]/[declineSharedHabit]) - a skip
    // was never meant to be permanent. Anything else is a stale call and a
    // no-op, same as before.
    final isNextSlot = participant.linkedHabitIds.length == templateIndex;
    final isUndoingSkip = templateIndex < participant.linkedHabitIds.length &&
        participant.linkedHabitIds[templateIndex] == kDeclinedSlot;
    if (!isNextSlot && !isUndoingSkip) return;

    final (id, name) =
        _resolveTemplate(room.sharedHabits[templateIndex], existingHabitId);
    final ids = [...participant.linkedHabitIds];
    final names = [...participant.linkedHabitNames];
    if (isUndoingSkip) {
      ids[templateIndex] = id;
      if (templateIndex < names.length) {
        names[templateIndex] = name;
      } else {
        names.add(name);
      }
    } else {
      ids.add(id);
      names.add(name);
    }
    await participantRef.set(
      {
        'linkedHabitIds': ids,
        'linkedHabitNames': names,
      },
      SetOptions(merge: true),
    );
    await syncLinkedHabitsProgress(room);
  }

  /// Leader-only: adds one more habit to an already-existing [RoomHabitMode.
  /// shared] room's plan - the only kind of post-creation room edit that
  /// makes sense to gate on the leader specifically, since shared mode's
  /// entire premise is one common plan everyone follows (contrast
  /// [addMyLinkedHabit], 'own' mode's equivalent, which is deliberately
  /// *not* leader-gated - there's no shared plan there for a leader to
  /// curate in the first place, just each person's own choices).
  ///
  /// [habitId] must be one of the leader's own existing habits, same as
  /// [createRoom]'s planHabitIds - snapshotted into a fresh
  /// [RoomHabitTemplate] stamped with [RoomHabitTemplate.addedAt] (see that
  /// field's own doc comment for why this doesn't need any special
  /// retroactive-credit handling beyond what late joiners already get).
  /// Links it straight into the leader's own participant doc immediately -
  /// they already own the source habit, so unlike a guest there's nothing
  /// left for them to pick. Every other already-joined participant instead
  /// sees this new slot the next time [resolvePlanHabit] runs for them (see
  /// RoomDetailScreen's unresolved-plan banner).
  ///
  /// A no-op for a non-leader, an 'own'-mode room, or a habit id that isn't
  /// actually one of the leader's own.
  Future<void> addSharedHabit(RoomModel room, String habitId) async {
    final uid = _uid;
    if (uid == null || uid != room.createdBy) return;
    if (room.habitMode != RoomHabitMode.shared) return;
    final myHabits = _ref.read(habitListProvider);
    final found = myHabits.where((h) => h.id == habitId);
    if (found.isEmpty) return;
    final habit = found.first;

    final template = RoomHabitTemplate(
      name: habit.name,
      category: habit.category,
      iconColorHex: habit.iconColorHex,
      frequencyType: habit.frequencyType,
      frequencyTarget: habit.frequencyTarget,
      addedAt: DateTime.now(),
    );
    await _rooms.doc(room.code).set(
      {
        'sharedHabits': FieldValue.arrayUnion([template.toFirestore()]),
      },
      SetOptions(merge: true),
    );

    final participantRef =
        _rooms.doc(room.code).collection('participants').doc(uid);
    final snap = await participantRef.get();
    if (snap.exists) {
      final participant = RoomParticipant.fromFirestore(snap);
      // Only auto-links if this really is the very next slot for the
      // leader too - same defensive positional check as resolvePlanHabit,
      // in case their own doc is somehow already out of sync.
      if (participant.linkedHabitIds.length == room.sharedHabits.length) {
        await participantRef.set(
          {
            'linkedHabitIds': [...participant.linkedHabitIds, habit.id],
            'linkedHabitNames': [...participant.linkedHabitNames, habit.name],
          },
          SetOptions(merge: true),
        );
      }
    }
    // syncLinkedHabitsProgress re-reads linkedHabitIds fresh from Firestore
    // itself, so the original (pre-addition) `room` is fine to pass here -
    // it only needs room.startDate/lastCountedDay/hasStarted/isEnded, none
    // of which this method just changed.
    await syncLinkedHabitsProgress(room);
  }

  /// The 'own'-mode equivalent of [addSharedHabit] - lets ANY participant
  /// (not just the leader; see that method's doc comment for why the two
  /// differ) add one more of their own existing habits to their own
  /// tracking for [room], at any time after joining. [habitId] must be one
  /// of this account's own habits and not already linked here - a no-op
  /// otherwise, same "can't happen from the UI, but never trust that alone"
  /// belt-and-suspenders every other write in this file already applies.
  Future<void> addMyLinkedHabit(
    RoomModel room,
    String habitId,
    String habitName,
  ) async {
    final uid = _uid;
    if (uid == null || room.habitMode != RoomHabitMode.own) return;
    final participantRef =
        _rooms.doc(room.code).collection('participants').doc(uid);
    final snap = await participantRef.get();
    if (!snap.exists) return;
    final participant = RoomParticipant.fromFirestore(snap);
    if (participant.linkedHabitIds.contains(habitId)) return;

    await participantRef.set(
      {
        'linkedHabitIds': [...participant.linkedHabitIds, habitId],
        'linkedHabitNames': [...participant.linkedHabitNames, habitName],
      },
      SetOptions(merge: true),
    );
    await syncLinkedHabitsProgress(room);
  }

  /// Leaves [room] - it keeps running for whoever's left even if the
  /// leader is the one leaving. Two edge cases that used to leave a room
  /// broken are handled explicitly here:
  ///
  ///  - **The leader leaves, others remain.** Leadership automatically
  ///    passes to the longest-standing remaining member (see
  ///    [nextLeaderAfter]) rather than leaving the room ownerless. Without
  ///    this, nobody left in the room could ever delete or extend it again
  ///    - both firestore.rules' /rooms/{roomId} delete rule and
  ///    [extendRoom]/[deleteRoom]'s own leader-only checks are gated on
  ///    `createdBy`, which would otherwise go on pointing at someone no
  ///    longer even in the room.
  ///  - **The leader leaves and was the only member.** There's nobody to
  ///    hand off to, so this deletes the room outright (via [deleteRoom])
  ///    instead of leaving a permanently empty, ownerless doc behind with
  ///    no one able to ever clean it up.
  ///
  /// Idempotent: reads this account's own participant doc first and
  /// returns early if it's already gone (already left - a double-tap
  /// before the UI updates, or a retried call after a dropped response -
  /// is a safe no-op, not a double `memberCount` decrement or a repeated
  /// leadership handoff for a departure that already happened).
  Future<void> leaveRoom(RoomModel room) async {
    final uid = _uid;
    if (uid == null) return;
    final participantRef =
        _rooms.doc(room.code).collection('participants').doc(uid);
    final mySnap = await participantRef.get();
    if (!mySnap.exists) return;

    if (uid == room.createdBy) {
      final rosterSnap = await _rooms
          .doc(room.code)
          .collection('participants')
          .orderBy('joinedAt')
          .get();
      final roster =
          rosterSnap.docs.map(RoomParticipant.fromFirestore).toList();
      final successor = nextLeaderAfter(uid, roster);
      if (successor == null) {
        await deleteRoom(room);
        return;
      }
      await _rooms.doc(room.code).set(
        {
          'createdBy': successor.uid,
          'createdByName': successor.displayName,
        },
        SetOptions(merge: true),
      );
    }

    await participantRef.delete();
    await _rooms.doc(room.code).set(
      {
        'memberCount': FieldValue.increment(-1),
      },
      SetOptions(merge: true),
    ).catchError((_) {});
    await _userRef(uid).set(
      {
        'roomCodes': FieldValue.arrayRemove([room.code]),
        'starredRoomCodes': FieldValue.arrayRemove([room.code]),
      },
      SetOptions(merge: true),
    );
  }

  /// Drops [code] from this device's own room list without touching the
  /// room itself - called when a room this account used to belong to no
  /// longer exists (the leader deleted it), so a dead code doesn't keep
  /// showing up in "my rooms" forever. Same self-healing idea as the app's
  /// other stale-field cleanups: each account quietly tidies its own list;
  /// nobody reaches into another account's data to do it for them.
  Future<void> forgetRoom(String code) async {
    final uid = _uid;
    if (uid == null) return;
    await _userRef(uid).set(
      {
        'roomCodes': FieldValue.arrayRemove([code]),
        'starredRoomCodes': FieldValue.arrayRemove([code]),
      },
      SetOptions(merge: true),
    );
  }

  /// Leader-only: permanently deletes the room and every participant's
  /// entry in it - including participants other than the caller, which is
  /// why firestore.rules' /rooms/{roomId}/participants/{uid} block grants
  /// a delete exception to the room's own createdBy specifically (its
  /// normal write rule is owner-only, i.e. only that one uid can touch
  /// their own doc - without the exception, this whole batch would fail
  /// permission-denied for every room with more than one member, since
  /// most of these deletes belong to someone other than the caller).
  /// Mirrors AuthNotifier._deleteAllUserData's chunked-batch delete for
  /// the same reason - a room with many participants could exceed
  /// Firestore's 500-write batch limit otherwise.
  Future<void> deleteRoom(RoomModel room) async {
    final uid = _uid;
    if (uid == null || uid != room.createdBy) return;
    final participantsRef = _rooms.doc(room.code).collection('participants');
    final snap = await participantsRef.get();
    const chunkSize = 400;
    for (var i = 0; i < snap.docs.length; i += chunkSize) {
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in snap.docs.skip(i).take(chunkSize)) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
    await _rooms.doc(room.code).delete();
    await _userRef(uid).set(
      {
        'roomCodes': FieldValue.arrayRemove([room.code]),
        'starredRoomCodes': FieldValue.arrayRemove([room.code]),
      },
      SetOptions(merge: true),
    );
  }

  /// Applies this account's *current* habit settings to [room] from today
  /// forward - the deliberate, opt-in escape hatch from the rule freezing
  /// [RoomParticipant.habitRules] enforces. Appends a new rule period
  /// starting today for every linked habit whose live settings no longer
  /// match what the room is scoring (see [roomRuleMismatches], which drives
  /// the warning this is offered from); habits already in agreement are left
  /// alone.
  ///
  /// Crucially forward-only: the earlier periods stay exactly as they were,
  /// so every finished day keeps the grade it actually earned. That's the
  /// whole difference between this and the old behaviour, where an edit
  /// silently re-scored history - here the person is choosing to change the
  /// rules from now on, which is a completely different (and honest) thing.
  Future<void> relockHabitRules(RoomModel room) async {
    final uid = _uid;
    if (uid == null) return;
    final participantRef =
        _rooms.doc(room.code).collection('participants').doc(uid);
    final snap = await participantRef.get();
    if (!snap.exists) return;
    final mine = RoomParticipant.fromFirestore(snap);
    final habitById = {for (final h in _ref.read(habitListProvider)) h.id: h};
    final todayKey = DateTime.now().effectiveDay.toDateKey();

    final updated = <String, List<RoomHabitRule>>{...mine.habitRules};
    var changed = false;
    for (final id in mine.countedHabitIds) {
      final habit = habitById[id];
      if (habit == null) continue;
      final current = mine.ruleFor(id, todayKey);
      if (current != null &&
          !current.differsFrom(
            frequencyType: habit.frequencyType,
            frequencyTarget: habit.frequencyTarget,
            scheduledWeekdays: habit.scheduledWeekdays,
          )) {
        continue;
      }
      final fresh = RoomHabitRule(
        from: todayKey,
        frequencyType: habit.frequencyType,
        frequencyTarget: habit.frequencyTarget,
        scheduledWeekdays: habit.scheduledWeekdays,
      );
      // Replaces rather than appends when a period already starts today -
      // relocking twice in one day should leave one rule for today, not a
      // pile of same-dated ones roomRuleAt would have to tie-break between.
      final existing = [...(updated[id] ?? const <RoomHabitRule>[])]
        ..removeWhere((r) => r.from == todayKey);
      updated[id] = [...existing, fresh];
      changed = true;
    }
    if (!changed) return;
    await participantRef.set(
      {
        'habitRules': updated.map(
          (k, v) => MapEntry(k, v.map((r) => r.toFirestore()).toList()),
        ),
        'lastUpdated': Timestamp.now(),
      },
      SetOptions(merge: true),
    );
    await syncLinkedHabitsProgress(room);
  }

  /// Skips one shared-plan slot for this participant - the "no thanks" the
  /// unresolved-plan prompt offers alongside picking a habit (see
  /// [kDeclinedSlot] for how a skip is stored, and why it holds its position
  /// instead of shortening the array). The slot then counts for nothing at
  /// all: excluded from both the numerator and the denominator, so it can
  /// neither earn nor cost this person anything.
  ///
  /// Same "must be exactly the next slot in line" guard as
  /// [resolvePlanHabit], for the same reason - a stale call can never skip
  /// the wrong slot or jump one out of order.
  Future<void> declineSharedHabit(RoomModel room, int templateIndex) async {
    final uid = _uid;
    if (uid == null) return;
    if (templateIndex < 0 || templateIndex >= room.sharedHabits.length) return;
    final participantRef =
        _rooms.doc(room.code).collection('participants').doc(uid);
    final snap = await participantRef.get();
    if (!snap.exists) return;
    final participant = RoomParticipant.fromFirestore(snap);
    if (participant.linkedHabitIds.length != templateIndex) return;

    await participantRef.set(
      {
        'linkedHabitIds': [...participant.linkedHabitIds, kDeclinedSlot],
        'linkedHabitNames': [
          ...participant.linkedHabitNames,
          room.sharedHabits[templateIndex].name,
        ],
        'lastUpdated': Timestamp.now(),
      },
      SetOptions(merge: true),
    );
    await syncLinkedHabitsProgress(room);
  }

  /// Leader-only: withdraws one habit from a shared room's plan - the undo
  /// for [addSharedHabit] that didn't exist before, so a mistaken addition
  /// no longer sticks to the room forever.
  ///
  /// A soft delete (stamps [RoomHabitTemplate.removedAt]) rather than
  /// actually dropping the entry, because every participant's
  /// linkedHabitIds is positionally parallel to sharedHabits and the leader
  /// may only write their OWN participant doc - see that field's doc comment
  /// for the full reasoning. Nobody's arrays shift, the slot simply stops
  /// counting for everyone, and it stays reversible.
  ///
  /// Re-syncs only the caller's own progress; every other participant's
  /// device picks the change up through its own next
  /// syncLinkedHabitsProgress (room open, habit tap), same single-writer
  /// rule every other per-participant field in this feature follows.
  Future<void> removeSharedHabit(RoomModel room, int index) async {
    final uid = _uid;
    if (uid == null || uid != room.createdBy) return;
    if (room.habitMode != RoomHabitMode.shared) return;
    if (index < 0 || index >= room.sharedHabits.length) return;
    if (room.sharedHabits[index].isRemoved) return;

    final updated = [
      for (var i = 0; i < room.sharedHabits.length; i++)
        if (i == index)
          RoomHabitTemplate(
            name: room.sharedHabits[i].name,
            category: room.sharedHabits[i].category,
            iconColorHex: room.sharedHabits[i].iconColorHex,
            frequencyType: room.sharedHabits[i].frequencyType,
            frequencyTarget: room.sharedHabits[i].frequencyTarget,
            addedAt: room.sharedHabits[i].addedAt,
            removedAt: DateTime.now(),
          )
        else
          room.sharedHabits[i],
    ];
    // A whole-array rewrite, not arrayUnion/arrayRemove: those can only add
    // or drop exact element values, and this has to *change* one element in
    // place while keeping every index where it is.
    await _rooms.doc(room.code).set(
      {
        'sharedHabits': updated.map((h) => h.toFirestore()).toList(),
      },
      SetOptions(merge: true),
    );
    await syncLinkedHabitsProgress(room);
  }

  /// Leader-only: leaves the lobby and starts the challenge right now, for
  /// everyone, on the same starting line - the manual "skip the wait"
  /// escape hatch offered next to a running countdown (see
  /// RoomDetailScreen's _ScheduledLobbyCard). Shares its actual write with
  /// [autoStartIfDue] via [_beginChallenge] - see that method's doc
  /// comment for why "today" is correct here, not the moment that was
  /// originally scheduled. A no-op for non-leaders, already-started rooms,
  /// or a missing room.
  Future<void> startRoom(RoomModel room) async {
    final uid = _uid;
    if (uid == null || uid != room.createdBy || !room.isLobby) return;
    await _beginChallenge(room);
  }

  /// Leader-only: sets (or changes) this lobby's scheduled start moment -
  /// the exact instant the room should flip to active, shown to every
  /// member as a live countdown (see RoomDetailScreen's
  /// _ScheduledLobbyCard). Safe to call again before it fires: the leader
  /// changing their mind just overwrites the old moment on the room doc,
  /// and every device watching [roomProvider] picks up the new value on
  /// its next snapshot - there's nothing to explicitly cancel first, and
  /// nothing else to keep in sync (the countdown itself is derived, never
  /// stored). A no-op for non-leaders or a room that's already left the
  /// lobby.
  Future<void> scheduleStart(RoomModel room, DateTime startAt) async {
    final uid = _uid;
    if (uid == null || uid != room.createdBy || !room.isLobby) return;
    await _rooms.doc(room.code).set(
      {
        'scheduledStartAt': Timestamp.fromDate(startAt),
      },
      SetOptions(merge: true),
    );
  }

  /// Fires the moment a lobby's [RoomModel.scheduledStartAt] actually
  /// arrives (see [RoomModel.scheduledStartDue]) - called by *every*
  /// device currently watching this room's countdown tick down (see
  /// RoomDetailScreen's _LobbyCardState), not just the leader's, so the
  /// room still flips on time even if the leader's own app isn't open
  /// right at that second. Deliberately not leader-gated, unlike every
  /// other write in this controller: firestore.rules' /rooms/{roomId}
  /// update rule is already open to any signed-in member for exactly this
  /// kind of reason (memberCount's increment faces the same need). Safe to
  /// call repeatedly, or from several members' devices at once - the
  /// isLobby guard inside [_beginChallenge]'s caller check here makes
  /// every call after the first a no-op, so racing devices can never
  /// re-run the transition or stomp on each other.
  Future<void> autoStartIfDue(RoomModel room) async {
    if (!room.isLobby || !room.scheduledStartDue) return;
    await _beginChallenge(room);
  }

  /// The one write that actually leaves the lobby - shared by the leader's
  /// manual [startRoom] override and [autoStartIfDue]'s automatic trigger,
  /// since both mean the exact same thing (start the challenge, first day
  /// is today) and differ only in *who* may call them and *when*. Always
  /// uses *today's* effectiveDay as [RoomModel.startDate], never the
  /// originally-scheduled moment's own day: by the time this runs, "now"
  /// either already more or less *is* the scheduled moment (the ordinary
  /// auto-start case), or the leader has deliberately chosen to start
  /// early (the manual override case, where waiting for the day the old
  /// schedule pointed at would leave the room stuck showing a stale
  /// day-level countdown even after status flips to active). Everyone
  /// already had advance notice via the countdown itself before this ever
  /// fires, which is what makes "today" safe here - unlike the old
  /// no-warning-at-all instant Start button this replaced, where day one
  /// was always forced to tomorrow specifically to avoid surprising
  /// latecomers with a day that had already mostly happened.
  Future<void> _beginChallenge(RoomModel room) async {
    final start = DateTime.now().effectiveDay;
    final days = room.lengthDays;
    await _rooms.doc(room.code).set(
      {
        'status': 'active',
        'startDate': Timestamp.fromDate(start),
        'scheduledStartAt': FieldValue.delete(),
        if (room.duration == RoomDuration.fixed && days != null)
          'endDate': Timestamp.fromDate(start.add(Duration(days: days - 1))),
      },
      SetOptions(merge: true),
    );
  }

  /// Leader-only: pushes a fixed-duration room's end date forward, starting
  /// a fresh [lengthDays]-day countdown from today - or switches it
  /// open-ended (never locks again) when [lengthDays] is null. The one way
  /// to keep a room going once RoomModel.isEnded would otherwise freeze it
  /// for good. Deliberately restarts the countdown from *today* rather than
  /// adding days onto the old end date - simpler to reason about, and the
  /// only sensible option once a room's already ended (adding days to a
  /// date in the past would just land somewhere else in the past). Doesn't
  /// touch [RoomModel.startDate] or anyone's history - every participant's
  /// [RoomParticipant.dailyDoneCount] so far, and every day already counted
  /// toward [RoomModel.daysElapsed], stays exactly as it was; only the
  /// cutoff for *future* progress moves. A no-op for anyone but the room's
  /// own creator.
  /// Extends a room — never restarts one. History is kept exactly as it is;
  /// only the finish line moves.
  ///
  /// [resumeFrom] is the day counting picks up again, defaulting to today.
  /// Any dead time between the old end and that day is recorded as a paused
  /// span (see RoomModel.pausedSpans) and excluded from every score, so
  /// extending a room that finished a week ago costs nobody a single point.
  /// Before this, those days went straight into the denominator and every
  /// member's percentage dropped the moment the leader tapped extend.
  Future<void> extendRoom(
    RoomModel room,
    int? lengthDays, {
    DateTime? resumeFrom,
  }) async {
    final uid = _uid;
    if (uid == null || uid != room.createdBy) return;

    final today = DateTime.now().effectiveDay;
    final resume = (resumeFrom ?? today).startOfDay;
    // Never resume before the room's own end, and never before today —
    // back-dating a resume would re-open days that have already been graded
    // and settled.
    final start = resume.isBefore(today) ? today : resume;

    // The gap: the day after the old end, through the day before we resume.
    // Empty when the room hasn't ended yet, or is being extended the same
    // day it ended — in both cases nothing was ever dead.
    final oldEnd = room.endDate;
    // Existing spans are clipped to end before the new resume point, never
    // blindly carried forward. A leader who resumes on a FUTURE date leaves
    // a pause covering days that are about to become live; extending again
    // before that date arrives used to carry the stale span through intact,
    // permanently excluding live days of a running room from every score.
    final startKey = start.toDateKey();
    final spans = <Map<String, String>>[];
    for (final sp in room.pausedSpans) {
      if (sp.from.compareTo(startKey) >= 0) continue; // wholly in the future
      final to = sp.to.compareTo(startKey) >= 0
          ? start.subtract(const Duration(days: 1)).toDateKey()
          : sp.to;
      if (sp.from.compareTo(to) <= 0) spans.add({'from': sp.from, 'to': to});
    }
    if (oldEnd != null) {
      final gapFrom = oldEnd.add(const Duration(days: 1));
      final gapTo = start.subtract(const Duration(days: 1));
      if (!gapFrom.isAfter(gapTo)) {
        spans.add({'from': gapFrom.toDateKey(), 'to': gapTo.toDateKey()});
      }
    }

    if (lengthDays == null) {
      // Open-ended. endDate is CLEARED but duration flips to open, which is
      // what bounds the strip — see _MiniHeatmapStrip._maxOpenRoomDays.
      // Previously this also left the room impossible to re-bound, because
      // every extend affordance is gated on duration == fixed; the menu no
      // longer gates that way, so an open room can be given an end again.
      await _rooms.doc(room.code).set(
        {
          'duration': RoomDuration.open.toJson(),
          'endDate': FieldValue.delete(),
          if (spans.isNotEmpty) 'pausedSpans': spans,
        },
        SetOptions(merge: true),
      );
      return;
    }

    final newEnd = start.add(Duration(days: lengthDays - 1));
    await _rooms.doc(room.code).set(
      {
        'duration': RoomDuration.fixed.toJson(),
        'endDate': Timestamp.fromDate(newEnd),
        if (spans.isNotEmpty) 'pausedSpans': spans,
      },
      SetOptions(merge: true),
    );
  }

  /// Shows or hides this participant's linked-habit name(s) from other
  /// members' leaderboard rows - progress (%, heatmap, day count) is always
  /// visible either way, this only toggles the habit-name chips. Purely a
  /// display flag on this participant's own doc.
  Future<void> toggleHideDetails(String code, bool hide) async {
    final uid = _uid;
    if (uid == null) return;
    await _rooms.doc(code).collection('participants').doc(uid).set(
      {
        'hideDetails': hide,
      },
      SetOptions(merge: true),
    );
  }

  /// This account's own choice to silence the room-finish push notification
  /// for room [code] - see RoomParticipant.notificationsMuted's doc
  /// comment. Same single-writer, own-doc-only pattern as [toggleHideDetails]
  /// right above; the room-finish Cloud Function reads this field on every
  /// other participant's doc before sending, so toggling it takes effect
  /// the next time anyone else in the room finishes, with nothing further
  /// to do on this end.
  Future<void> setRoomMuted(String code, bool muted) async {
    final uid = _uid;
    if (uid == null) return;
    await _rooms.doc(code).collection('participants').doc(uid).set(
      {
        'notificationsMuted': muted,
      },
      SetOptions(merge: true),
    );
  }

  /// Grants this account's one-time [RoomCompeteMode.team] bonus for room
  /// [code] - called only once [RoomTeamProgress.teamIsPerfect] is true and
  /// [mine].teamBonusClaimed is still false (see _TeamProgressCard's claim
  /// button, the only caller). Awards through the exact same
  /// DashboardNotifier.awardBonus every other lump-sum reward in the app
  /// already uses (Focus Timer sessions, Weekly Challenges), then persists
  /// the claimed flag on this account's own participant doc - the same
  /// single-writer field [toggleHideDetails] above writes - so re-opening
  /// Room Detail, or the same account on another device, never pays this
  /// out twice. [mine] is passed in rather than re-fetched since every
  /// caller already has it from the same roomParticipantsProvider stream
  /// driving the rest of the screen.
  Future<void> claimTeamBonus(
    String code,
    RoomParticipant mine, {
    required int xp,
    required int gold,
  }) async {
    final uid = _uid;
    if (uid == null) return;
    // Cheap early-out on the snapshot the UI already has; the real guard is
    // the transaction below.
    if (mine.teamBonusClaimed) return;

    // ── Claim the flag first, and only pay out if THIS call won ──────────
    // This used to check `mine.teamBonusClaimed`, award the XP and gold, and
    // then write the flag. `mine` is a snapshot from the participants
    // stream, and the claim button has no disabled state, so two quick taps
    // both read false, both paid out, and both wrote true afterwards — 150
    // XP and 75 gold, twice, for one bonus. A transaction that flips
    // false -> true is the only thing that can decide a winner between them:
    // Firestore re-runs the callback if the doc changed under it, so exactly
    // one call ever sees false and returns true here.
    //
    // Deliberately claim-then-pay rather than pay-then-claim. If the payout
    // somehow fails after the flag is set the person loses a bonus, which is
    // recoverable by hand; the other order mints currency, which isn't. Same
    // transactional reasoning syncTodayForHabit already documents.
    final participantRef = _rooms.doc(code).collection('participants').doc(uid);
    final didClaim =
        await FirebaseFirestore.instance.runTransaction<bool>((txn) async {
      final snap = await txn.get(participantRef);
      if (!snap.exists) return false;
      if (snap.data()?['teamBonusClaimed'] == true) return false;
      txn.set(
        participantRef,
        {'teamBonusClaimed': true},
        SetOptions(merge: true),
      );
      return true;
    });
    if (!didClaim) return;
    // Guarded by the didClaim transaction above, so it is once per room
    // episode and exempt from the daily earn ceiling.
    await _ref
        .read(dashboardProvider.notifier)
        .awardBonus(xp: xp, gold: gold, countsTowardDailyCap: false);
  }

  /// The end-of-room prize for finishing in [rank] (1-based), or null for
  /// anyone off the podium — a plain function so the finale card and any
  /// future summary can quote identical numbers without either re-deriving
  /// them.
  ///
  /// Competitive rooms paid out nothing at all before this: a podium
  /// graphic, and no XP, no gold, no medal, at the end of a race that can
  /// run ninety days. Scaled by place so first actually means something,
  /// and stopping at three so the podium stays the prize rather than a
  /// participation payout.
  static ({int xp, int gold})? podiumPrizeFor(int rank) => switch (rank) {
        1 => (xp: 200, gold: 100),
        2 => (xp: 120, gold: 60),
        3 => (xp: 80, gold: 40),
        _ => null,
      };

  /// Pays [mine] their podium prize for a finished competitive room, exactly
  /// once. Same claim-then-pay transaction as [claimTeamBonus] — see that
  /// method for why the flag has to be won inside a transaction before any
  /// currency moves.
  ///
  /// Refuses on a room that hasn't ended, so a leaderboard position mid-race
  /// can never be cashed in; and refuses off the podium, where there is no
  /// prize to claim.
  Future<void> claimPodiumBonus(
    RoomModel room,
    RoomParticipant mine, {
    required int rank,
  }) async {
    final uid = _uid;
    if (uid == null) return;
    if (!room.isEnded) return;
    if (mine.podiumBonusClaimed) return;
    // A podium needs someone to stand above. Rank alone is trivially 1 in a
    // room of one, so without this a person could create a room, let it end
    // alone, and collect first place — 200 XP and 100 gold for competing
    // against nobody. The claim transaction below makes that once per room,
    // but nothing caps rooms per account, so it was repeatable by simply
    // making another. Mirrors the "no competition, no prize" rule the
    // leaderboard already implies.
    if (room.memberCount < 2) return;
    final prize = podiumPrizeFor(rank);
    if (prize == null) return;

    final participantRef =
        _rooms.doc(room.code).collection('participants').doc(uid);
    final didClaim =
        await FirebaseFirestore.instance.runTransaction<bool>((txn) async {
      final snap = await txn.get(participantRef);
      if (!snap.exists) return false;
      if (snap.data()?['podiumBonusClaimed'] == true) return false;
      txn.set(
        participantRef,
        {'podiumBonusClaimed': true},
        SetOptions(merge: true),
      );
      return true;
    });
    if (!didClaim) return;
    await _ref
        .read(dashboardProvider.notifier)
        .awardBonus(
          xp: prize.xp,
          gold: prize.gold,
          // A podium prize is settled once when the room ends.
          countsTowardDailyCap: false,
        );
  }

  /// Stars/unstars [code] for this account only, on `users/{uid}` - the
  /// exact same arrayUnion/arrayRemove shape [roomCodes] itself already
  /// uses (see [joinRoom]/[leaveRoom]), just a second, independent field.
  /// A personal "keep this one at the top of my list" preference (see
  /// [sortStarredFirst]) - nothing about a room's own shared doc changes,
  /// so nobody else in the room ever sees this. A no-op when signed out.
  Future<void> toggleStarRoom(String code, bool starred) async {
    final uid = _uid;
    if (uid == null) return;
    await _userRef(uid).set(
      {
        'starredRoomCodes': starred
            ? FieldValue.arrayUnion([code])
            : FieldValue.arrayRemove([code]),
      },
      SetOptions(merge: true),
    );
  }

  /// Strips [habitId] from every one of this account's currently-linked,
  /// still-open rooms (see [myLinkedRoomHabitsProvider] - the exact reverse
  /// index Grid's own room badge and [syncTodayForHabit] already rely on)
  /// - called right before a habit actually gets deleted (see
  /// AddHabitSheet._deleteExisting/GridScreen._deleteSelected), so a
  /// room's [RoomParticipant.linkedHabitIds] never keeps pointing at a
  /// habit that no longer exists.
  ///
  /// This replaces "delete and just leave the stale id behind" (which
  /// [RoomParticipant.scheduledCountFor] used to silently paper over by
  /// falling back to the *old*, now-too-large linkedHabitIds.length forever
  /// - since a deleted habit's square can never turn green again, that
  /// permanently capped the participant below 100% and permanently broke
  /// their streak, with the only advertised way out being to leave and
  /// rejoin the room - which itself wipes every prior day of progress,
  /// since [leaveRoom] deletes the whole participant doc outright). Actually
  /// unlinking here keeps that trap from ever opening in the first place:
  /// the moment a habit's gone, this room's denominator adjusts to the
  /// smaller, still-linked set immediately, so tomorrow can be a full day
  /// again. Callers are expected to warn the user before deleting (see
  /// app_strings.dart's habitLinkedRoomWarningBody) since this does change
  /// what "100%" for this room means going forward - never a surprise,
  /// just no longer a dead end either.
  ///
  /// Never touches [RoomParticipant.dailyDoneCount]/[dailyScheduledCount] -
  /// every day already recorded stays exactly as it was; only today onward
  /// is affected, same as [RoomModel]'s per-day credit math already implies.
  /// A silent no-op for the overwhelmingly common case where [habitId]
  /// isn't linked to any room at all.
  Future<void> unlinkHabitEverywhere(String habitId) async {
    final uid = _uid;
    if (uid == null) return;

    // ── Read the room list from Firestore, not from the in-memory index ──
    // This used to start from myLinkedRoomHabitsProvider and bail when it
    // came back empty. That provider is built from three Firestore streams
    // (my codes, each room, each roster) and is legitimately empty until all
    // three have delivered — so deleting a habit any time before the Rooms
    // data had warmed up silently unlinked nothing at all.
    //
    // Which mattered far more than a stale id normally would: grading treats
    // a linked habit it can no longer find as DONE (see
    // syncLinkedHabitsProgress' `habit == null` branch, which fails open so a
    // dead link can't make every day harder). A link that outlives its habit
    // therefore pays full credit every single day, forever — deleting a habit
    // right after launch could put you at 100% in a competitive room you had
    // stopped participating in.
    //
    // `users/{uid}.roomCodes` is the same list that index is derived from and
    // it is authoritative the moment it is read, so this no longer depends on
    // any stream having arrived first.
    final userSnap = await _userRef(uid).get();
    final codes = (userSnap.data()?['roomCodes'] as List?)
            ?.whereType<String>()
            .toList() ??
        const <String>[];
    if (codes.isEmpty) return;

    for (final code in codes) {
      final participantRef =
          _rooms.doc(code).collection('participants').doc(uid);
      final snap = await participantRef.get();
      if (!snap.exists) continue;
      final ids = (snap.data()?['linkedHabitIds'] as List?)
              ?.whereType<String>()
              .toList() ??
          const [];
      if (!ids.contains(habitId)) continue;
      final names = (snap.data()?['linkedHabitNames'] as List?)
              ?.whereType<String>()
              .toList() ??
          const [];
      // Shared plans keep the slot as a declined sentinel; an 'own' room has
      // no parallel array to protect, so it genuinely removes the entry.
      final room = _ref.read(roomProvider(code)).valueOrNull;
      final (newIds, newNames) = removeLinkedHabit(
        ids,
        names,
        habitId,
        preserveSlots: room?.habitMode == RoomHabitMode.shared,
      );
      await participantRef.set(
        {
          'linkedHabitIds': newIds,
          'linkedHabitNames': newNames,
          'lastUpdated': Timestamp.now(),
        },
        SetOptions(merge: true),
      );
    }
  }

  /// Recomputes this participant's per-day completion counts for [room]
  /// straight from their real daily habit history (`users/{uid}/daily/
  /// {date}`, the same records the Grid screen reads) across *all* of their
  /// currently-linked habits for this room - each linked habit is detected
  /// and counted independently (see RoomParticipant.dailyDoneCount's doc
  /// comment), so a day with only some of them green still earns partial
  /// credit instead of nothing.
  ///
  /// Two different rules decide whether a linked habit counts against a
  /// given day, depending on its own cadence:
  ///  - A regular (daily-cadence, optionally weekday-restricted) habit
  ///    checks its own schedule (IslamicHabitTemplate.isScheduledFor) for
  ///    every day in range, so a day it isn't scheduled on - the exact
  ///    same "blocked, nothing to do" state its own Grid square shows - is
  ///    excused from that day's count instead of silently counting as
  ///    missed (see RoomParticipant.dailyScheduledCount).
  ///  - A flexible weekly-quota habit (HabitFrequencyType.weekly - "N
  ///    times a week," no specific weekdays) is judged by whole calendar
  ///    week instead - hitting the target on 5 of 7 days and skipping the
  ///    other 2 is a perfect week for a 4x/week habit, not "2 missed
  ///    days," so isScheduledFor's own everyday-true answer for a habit
  ///    like this (there's no specific weekday to rule any day out) is
  ///    deliberately not used to gate it day-by-day the way it does for a
  ///    regular habit above - but ONLY for the streak. Its day counts are
  ///    plain: do it today and today is a whole done day, in full colour,
  ///    like any other habit. The quota's only job is deciding whether a
  ///    finished week keeps the streak alive (see
  ///    RoomParticipant.quotaOkWeeks).
  ///
  /// Always re-reads this participant's own current linkedHabitIds from
  /// Firestore first rather than trusting a stale in-memory list, so this
  /// can safely be called from anywhere (Room Detail on open, pull-to-
  /// refresh, or right after joining) without any caller needing to track
  /// which habits are linked itself - the lighter-weight
  /// [syncTodayForHabit] below is what actually fires on every Grid tap
  /// instead. A full recompute (not an incremental add) each time, since a
  /// day's square can also be *un*-set after the fact - this keeps the
  /// room's copy from ever silently drifting out of sync with the real
  /// thing.
  ///
  /// [todaySquares] is an optional habitId -> SquareState map for *today*
  /// only, straight from the caller's already-updated local Grid state. Pass
  /// it whenever this is being run in direct response to a tap (see
  /// [syncTodayForHabit]'s weekly-quota detour): the daily reads below can
  /// still be racing the Grid's own fire-and-forget write, and today is the
  /// one day where the caller knows better than Firestore does. Omit it for
  /// every other caller (room open, pull-to-refresh, join), where Firestore
  /// is already the settled truth.
  Future<void> syncLinkedHabitsProgress(
    RoomModel room, {
    Map<String, SquareState>? todaySquares,
  }) async {
    final uid = _uid;
    if (uid == null) return;
    // Nothing counts before the leader starts the room and its first day
    // arrives — a lobby room's placeholder startDate must never credit
    // the gathering days as challenge days.
    if (!room.hasStarted) return;
    final participantRef =
        _rooms.doc(room.code).collection('participants').doc(uid);
    final participantSnap = await participantRef.get();
    if (!participantSnap.exists) return;
    // Parsed once, up front - every id/name/rule/count question below reads
    // from this rather than re-digging through the raw doc data.
    final mineNow = RoomParticipant.fromFirestore(participantSnap);
    // rawIds keeps every slot in its original position (that positional
    // parallelism with RoomModel.sharedHabits is what resolvePlanHabit and
    // the unresolved-plan banner both rely on); habitIds is the subset that
    // actually counts - see RoomParticipant.countedHabitIdsIn for the two
    // kinds of non-counting slot and why they're excluded from the numerator
    // AND the denominator.
    final rawIds = mineNow.linkedHabitIds;
    if (rawIds.isEmpty) return;
    final habitIds = mineNow.countedHabitIdsIn(room);
    if (habitIds.isEmpty) return;

    // Looked up once, up front, so each day's scheduling check below is a
    // plain map lookup rather than a re-scan of the whole habit list.
    //
    // Paused habits are resolved too, and that is load-bearing. This map
    // used to hold only the active list, so a habit paused today became
    // unresolvable for EVERY day in the 45-day window, including the days
    // before the pause when it was live and being completed. Excluding it
    // from those days would throw away real finished work: someone who did
    // تمرين all week and paused it on Friday would have Monday through
    // Thursday regraded as though the habit had never been part of their
    // plan. Resolving it instead lets habitExistedOn draw the line in the
    // right place, since it already returns false only for days strictly
    // after archivedAt.
    final myHabits = _ref.read(habitListProvider);
    final habitById = {
      for (final h in _ref.read(pausedHabitsProvider)) h.id: h,
      // Active last so a habit that somehow appears in both wins as active.
      for (final h in myHabits) h.id: h,
    };
    // Every window each habit was really active for. habitById can only ever
    // describe the CURRENT one, which is the wrong question for a habit that
    // has been paused and resumed: the resumed template claims a birth date of
    // the resume day (catalog) or claims it never stopped (custom), so grading
    // off it either pays full credit for the whole pre-pause stretch or turns
    // an excused pause into a run of misses. See habitStintsProvider.
    final stintsById = _ref.read(habitStintsProvider);
    // A day this habit was genuinely being tracked on. Falls back to the old
    // single-window rule when no stint history exists, so an account that has
    // never paused anything grades byte-for-byte as it did before.
    // ── Repairing a habit whose birth date was overwritten ──────────────
    //
    // Resuming a habit used to move its birth date to the resume day even when
    // the window it closed could not be recorded (a habit with no known start;
    // see CustomHabitsNotifier.unarchive and ActiveCatalogNotifier.toggle, both
    // fixed now). The habit came back claiming it was born that day, so every
    // earlier day graded as "this did not exist", a scheduled count of ZERO was
    // written across the member's whole history, and a zero denominator reads
    // as a rest day worth full credit (see RoomParticipant.creditFor). The
    // visible result was a high percentage sitting above a completely blank
    // strip.
    //
    // The damage is not self-healing: those days are stored as 0 and the
    // anti-backdating hatch only steps aside when the scheduled count RISES,
    // which 0 > 0 never does. But the ROOM kept its own record. effectiveRules
    // is stamped `from: room.startDate` the first time this room ever graded
    // the habit and is never re-stamped, so it is an attestation of when the
    // habit joined the plan that is completely independent of every date the
    // habit itself carries. Where the two disagree in the one direction that
    // only damage produces — the habit claims to be YOUNGER than the room's own
    // record of it — the room's record is the floor.
    //
    // Bounded on purpose, and only ever widens BACKWARDS: from that floor up to
    // (not past) the habit's own damaged start. So it cannot excuse a miss, it
    // cannot reach past a pause (the closed window still ends at archivedAt, so
    // the stand-down days still fall through to hadStartedBy and still score
    // zero), and an account whose dates are intact never enters this branch at
    // all, which is what keeps every stored percentage identical on the first
    // launch after this ships.
    final stintFloorById = <String, DateTime>{};
    final damagedStartById = <String, DateTime>{};

    bool countedOn(IslamicHabitTemplate habit, DateTime day) {
      if (habitCountedOn(
        stintsById[habit.id],
        day,
        fallback: () => habitExistedOn(habit, day),
      )) {
        return true;
      }
      final floor = stintFloorById[habit.id];
      final damaged = damagedStartById[habit.id];
      if (floor == null || damaged == null) return false;
      final d = DateTime(day.year, day.month, day.day);
      if (d.isBefore(floor) || !d.isBefore(damaged)) return false;
      // Never past the pause: a stood-down day is not a tracked day.
      final died = habit.archivedAt;
      if (died != null &&
          d.isAfter(DateTime(died.year, died.month, died.day))) {
        return false;
      }
      return true;
    }

    // Refuse to grade against a habit list that hasn't loaded.
    //
    // This is the single most destructive failure this method has. Pass 1's
    // "linked habit not found" branch below fails OPEN — it credits every day
    // in the window as scheduled=1/done=1 and skips the weekly branch and
    // pass 2 entirely. That fail-open is right for its intended case (a habit
    // genuinely deleted from Grid after being linked, where punishing someone
    // for a stale link would be worse). It is catastrophic for a habit that
    // merely hasn't loaded yet, because the pass then computes
    // dailyScheduledCount as dense — every day scheduled, so every key is
    // REMOVED — and quotaOkWeeks as empty, so previously-earned weeks are
    // REVOKED. All of it lands in one atomic update(). A weekly-quota member
    // loses every rest day they had banked and drops ~19 points, while their
    // doc still looks freshly synced.
    //
    // It is reachable because nothing gated it: _resyncMyRooms fires on app
    // resume and cold start (main.dart) with no UI involved, and
    // habitListProvider is empty until customHabits and the catalog settle —
    // and it resets to empty on every authStateProvider emission. The room
    // providers depend only on uid and room docs, so the sync wins that race
    // routinely. Observed in production on room A8GEL7.
    //
    // Bailing is always safe: this method is called on resume, on room open,
    // and after taps, so skipping one warm-up pass costs a deferred update,
    // never data. Exactly the same treatment _profileFields already applies
    // to characterProvider for the same reason — see its isLoading guard,
    // which exists because the identical race was silently overwriting
    // people's chosen avatar with the constructor default.
    if (_ref.read(habitsStillLoadingProvider)) return;
    // Belt and braces: even once loading is over, a linked id that resolves
    // to nothing means this device cannot grade this room correctly. That is
    // indistinguishable here from the deleted-habit case, but the cost of
    // guessing wrong is asymmetric — a deleted habit costs one deferred
    // sync, a not-yet-loaded one costs the member their banked weeks — so
    // this defers rather than fails open.
    if (habitIds.any((id) => !habitById.containsKey(id))) return;

    // How far back to actually re-read. This used to always be the room's
    // ENTIRE history, which meant one `daily` document fetch per day of the
    // room, every single time anyone opened it - fine for a 7-day room, but
    // an open-ended room a year in was 365 parallel Firestore reads per
    // visit, growing forever. Since a finished day's credit is already stored
    // (see RoomParticipant.dailyDoneCount) there's nothing to gain from
    // re-deriving it, so the recompute is windowed and everything older is
    // simply kept as previously written.
    //
    // The window still has to be generous enough to cover the two things that
    // legitimately change an already-past day: back-filling a forgotten
    // square in the Grid, and a flexible weekly quota filling up later in its
    // week. [kRoomSyncWindowDays] plus the rewind to a week boundary below
    // covers both with room to spare.
    //
    // One exception: a participant with no recorded day at all (a fresh link,
    // or someone who just joined a room that's been running a while) gets the
    // full range, so they're credited from the room's start date like any
    // other late joiner rather than only from the window's edge.
    final needsFullBackfill = mineNow.dailyDoneCount.isEmpty;
    // Never earlier than the day this person joined. The grading model
    // already ignores pre-join days (see RoomParticipant.countedStartIn), so
    // computing them here would only write counts nothing reads — and, worse,
    // a first sync would spend one Firestore read per day of a long room's
    // pre-join history to do it.
    var windowStart = mineNow.countedStartIn(room);
    if (!needsFullBackfill) {
      final trimmed = room.lastCountedDay
          .subtract(const Duration(days: kRoomSyncWindowDays - 1));
      // Rewound to that day's Monday so a weekly-quota habit is never graded
      // against a half-visible week (its target applies to the whole week -
      // see weeklyHabitCreditFor).
      final aligned = startOfGridWeek(trimmed);
      if (aligned.isAfter(windowStart)) windowStart = aligned;
    }

    final days = <DateTime>[];
    for (var day = windowStart;
        !day.isAfter(room.lastCountedDay);
        day = day.add(const Duration(days: 1))) {
      days.add(day);
    }
    final userRef = _userRef(uid);
    final snaps = await Future.wait(
      days.map((d) => userRef.collection('daily').doc(d.toDateKey()).get()),
    );
    final todayKey = DateTime.now().effectiveDay.toDateKey();
    bool isGreen(int dayIndex, String habitId) {
      // Today comes from the caller's own already-updated Grid state when it
      // handed us one. [syncTodayForHabit] routes a room with any
      // weekly-quota link through this full resync (only the whole week can
      // decide that habit's credit), and without this that detour would
      // re-derive today from the reads above - while the Grid's own square
      // write is still fire-and-forget in flight (see
      // WeeklyGridNotifier._persistSquare's .ignore()). Losing that race
      // wrote today down as 0, and once today became yesterday the clamp
      // above pinned the 0 in place for good. Passing the tap's own truth
      // through is the same reason the fast path takes `todaySquares` at all.
      final live = todaySquares;
      if (live != null && days[dayIndex].toDateKey() == todayKey) {
        return (live[habitId] ?? SquareState.none).isGreen;
      }
      final raw = snaps[dayIndex].data()?['squareStates'];
      return raw is Map &&
          SquareState.fromJson(raw[habitId]?.toString()).isGreen;
    }

    /// Whether this habit was half done (جزئي) that day.
    ///
    /// Feeds RoomParticipant.dailyPartialCount, which DOES score, at half a
    /// habit each. See creditFor for why that is safe on a ranked surface.
    bool isPartial(int dayIndex, String habitId) {
      final live = todaySquares;
      if (live != null && days[dayIndex].toDateKey() == todayKey) {
        return (live[habitId] ?? SquareState.none) == SquareState.partial;
      }
      final raw = snaps[dayIndex].data()?['squareStates'];
      return raw is Map &&
          SquareState.fromJson(raw[habitId]?.toString()) ==
              SquareState.partial;
    }

    /// Whether this habit was deliberately stood down (تخطّي) that day.
    ///
    /// Mirrors [isGreen] exactly, including the todaySquares override, for
    /// the same race reason documented there. Feeds ONLY
    /// RoomParticipant.dailyRestedCount, which nothing that scores may read.
    bool isSkipped(int dayIndex, String habitId) {
      final live = todaySquares;
      if (live != null && days[dayIndex].toDateKey() == todayKey) {
        return (live[habitId] ?? SquareState.none) == SquareState.skipped;
      }
      final raw = snaps[dayIndex].data()?['squareStates'];
      return raw is Map &&
          SquareState.fromJson(raw[habitId]?.toString()) ==
              SquareState.skipped;
    }

    // The rules this ROOM grades each linked habit by, which is
    // deliberately NOT the same thing as the habit's current settings - see
    // RoomParticipant.habitRules' doc comment for the whole reason this
    // indirection exists (editing a habit used to silently re-score every
    // finished day in the room). Anything with no rules recorded yet gets
    // one seeded from its current settings, stamped from the room's own
    // start date: the best available answer for a doc written before this
    // field existed, and exactly what a freshly-linked habit should get.
    // Starts from the stored map rather than an empty one so a skipped or
    // withdrawn slot keeps its own history intact for if it ever comes back.
    final startKey = room.startDate.toDateKey();
    final effectiveRules = <String, List<RoomHabitRule>>{...mineNow.habitRules};
    for (final id in habitIds) {
      if (effectiveRules[id]?.isNotEmpty ?? false) continue;
      final habit = habitById[id];
      effectiveRules[id] = [
        RoomHabitRule(
          from: startKey,
          frequencyType: habit?.frequencyType ?? HabitFrequencyType.daily,
          frequencyTarget: habit?.frequencyTarget ?? 1,
          scheduledWeekdays: habit?.scheduledWeekdays ?? const [],
        ),
      ];
    }

    // See stintFloorById. The MINIMUM `from`, not the first: recordHabitRuleChange
    // appends later rule periods, so the list is not sorted.
    for (final id in habitIds) {
      final rules = effectiveRules[id];
      if (rules == null || rules.isEmpty) continue;
      var from = rules.first.from;
      for (final r in rules) {
        if (r.from.compareTo(from) < 0) from = r.from;
      }
      final roomSaw = DateTime.tryParse(from);
      if (roomSaw == null) continue;
      DateTime? earliest;
      for (final stint in stintsById[id] ?? const <(DateTime?, DateTime)>[]) {
        final start = stint.$1;
        // A null start is already unbounded, so nothing is damaged here.
        if (start == null) { earliest = null; break; }
        if (earliest == null || start.isBefore(earliest)) earliest = start;
      }
      if (earliest == null) continue;
      if (earliest.isAfter(roomSaw)) {
        stintFloorById[id] = DateTime(roomSaw.year, roomSaw.month, roomSaw.day);
        damagedStartById[id] =
            DateTime(earliest.year, earliest.month, earliest.day);
      }
    }

    // Running per-day totals across every linked habit, regular and weekly
    // alike - written to Firestore sparsely at the end, matching
    // RoomParticipant.dailyScheduledCount/dailyDoneCount's own "absent means
    // everything as normal" convention (see below).
    //
    // Every habit is weighed identically here: due that day, and done or not.
    // A flexible weekly-quota habit gets no special treatment at all on this
    // side - do it today and today is a whole done day. Its quota only ever
    // decides whether a WEEK keeps the streak, collected in `okWeeks`.
    final scheduledCount = <String, int>{
      for (final d in days) d.toDateKey(): 0,
    };
    final doneCount = <String, int>{for (final d in days) d.toDateKey(): 0};
    // Display only. See RoomParticipant.dailyRestedCount for why this is
    // walled off from everything that produces a score.
    final restedCount = <String, int>{
      for (final d in days) d.toDateKey(): 0,
    };
    final partialCount = <String, int>{
      for (final d in days) d.toDateKey(): 0,
    };
    // Weeks whose weekly-quota habits all held - see
    // RoomParticipant.quotaOkWeeks. Filled in pass 2.
    final okWeeks = <String>{};

    // Every calendar week (Monday start, matching DateTimeGameExt.
    // startOfGridWeek - SATURDAY, the same week boundary the Grid screen
    // itself draws) this room's day range touches, oldest first, each mapped
    // to which of `days` fall in it. A room that starts mid-week just gets a
    // shorter-than-7-day first bucket (still checked against the habit's full
    // weekly target, not a prorated one; a known, deliberately simple edge
    // case that only ever affects a room's first partial week).
    //
    // Saturday, not DateTimeGameExt.startOfWeek's Monday, on purpose: this
    // used to bucket by Monday while the Grid showed Saturday-to-Friday
    // weeks, so "4 times this week" in a room silently meant a different
    // seven days than the week the person was looking at. Whichever week the
    // Grid draws IS the week to a user, so the quota has to agree with it.
    final weeks = <DateTime, List<int>>{};
    for (var i = 0; i < days.length; i++) {
      weeks.putIfAbsent(startOfGridWeek(days[i]), () => []).add(i);
    }

    // ── Pass 1: the day counts. ──────────────────────────────────────────
    // Due that day and done, or due and not. This is what the percentage,
    // the "X of Y" fraction and the heatmap colour all come from.
    //
    // A day is only ever counted against someone if the habit was actually
    // due then. For a regular habit that means its own weekday list; for a
    // flexible weekly-quota habit it means its quota (see
    // [weeklyQuotaScheduledDays]) - a rest day it was entitled to take is
    // excused, not missed, exactly like a Mon/Wed habit's Tuesday. What does
    // NOT change either way is the numerator: a day the habit was done is a
    // whole done day, in full colour, never a fraction of one.
    // Deliberately the ACTIVE list, not habitById, which now also resolves
    // paused habits. The question here is "is anything still running", and
    // a plan whose every habit is paused must answer no. See
    // roomHasGradableHabit.
    final anyGradable =
        roomHasGradableHabit(habitIds, {for (final h in myHabits) h.id});
    for (final id in habitIds) {
      final habit = habitById[id];
      final rules = effectiveRules[id]!;
      // A linked habit this device cannot resolve: paused by the member, or
      // a link that outlived its habit. It used to be credited as DONE here
      // while syncTodayForHabit counted the identical situation as a miss,
      // which is what made a paused habit's percentage move on its own.
      // Now it leaves the numerator AND the denominator, so the member is
      // graded on what they can actually do. See roomHasGradableHabit for
      // the one case that cannot be excused.
      if (habit == null) {
        if (anyGradable) continue;
        // Everything is paused or gone. Scheduled, never done, so this
        // scores zero rather than paying full credit for an empty day.
        for (final d in days) {
          final key = d.toDateKey();
          scheduledCount[key] = scheduledCount[key]! + 1;
        }
        continue;
      }
      // Walked a week at a time rather than a day at a time, because a
      // weekly-quota habit's answerable days can only be decided by looking
      // at its whole week at once. Whether this habit IS one is read from the
      // room's frozen rule at the week's first day - the same way pass 2
      // below already resolves it.
      for (final entry in weeks.entries) {
        final dayIndices = entry.value;
        final weekRule = roomRuleAt(rules, days[dayIndices.first].toDateKey());

        if (weekRule.frequencyType == HabitFrequencyType.weekly) {
          final present =
              dayIndices.where((i) => countedOn(habit, days[i])).toList();
          if (present.isEmpty) continue;
          final done = {
            for (final i in present)
              if (isGreen(i, id)) i,
          };
          for (final i in weeklyQuotaScheduledDays(
            presentDays: present,
            doneDays: done,
            target: weekRule.frequencyTarget,
            isWeekClosed: isQuotaWeekClosed(
              weekStart: entry.key,
              lastCountedDay: room.lastCountedDay,
              roomEnded: room.isEnded,
            ),
          )) {
            final key = days[i].toDateKey();
            scheduledCount[key] = scheduledCount[key]! + 1;
            if (done.contains(i)) {
              doneCount[key] = doneCount[key]! + 1;
            } else if (isPartial(i, id)) {
              partialCount[key] = partialCount[key]! + 1;
            } else if (isSkipped(i, id)) {
              restedCount[key] = restedCount[key]! + 1;
            }
          }
          continue;
        }

        // Regular habit: due every day, or only on its own weekdays. The
        // rule is re-resolved per day here (not once per week like the
        // cadence check above) so a mid-week re-lock still applies from the
        // exact day it starts.
        for (final i in dayIndices) {
          final key = days[i].toDateKey();
          // Not due this day (a day before the habit existed, or a
          // Mon/Wed/Fri habit on a Tuesday) doesn't count against the day at
          // all - it was never something to do, not something skipped. The
          // weekday list comes from the room's frozen rule, so editing a
          // habit's days can't re-grade finished history.
          if (!countedOn(habit, days[i])) continue;
          final rule = roomRuleAt(rules, key);
          if (rule.scheduledWeekdays.isNotEmpty &&
              !rule.scheduledWeekdays.contains(days[i].weekday)) {
            continue;
          }
          scheduledCount[key] = scheduledCount[key]! + 1;
          if (isGreen(i, id)) {
            doneCount[key] = doneCount[key]! + 1;
          } else if (isPartial(i, id)) {
            partialCount[key] = partialCount[key]! + 1;
          } else if (isSkipped(i, id)) {
            restedCount[key] = restedCount[key]! + 1;
          }
        }
      }
    }

    // ── Closing the pause-everything hole ────────────────────────────────
    //
    // Pass 1 counts a habit only on the days it was genuinely active, which
    // correctly excuses a paused stretch whenever something else is running.
    //
    // It is wrong when NOTHING is. A plan whose every habit is paused has no
    // habit scheduled on any of those days, and a day that asks nothing is
    // full credit by design (see RoomParticipant.creditFor), so standing your
    // whole commitment down would pay 100% a day for the rest of the room.
    // This marks those days, and only those days, as STOOD DOWN.
    //
    // ── Stood down, not missed ──────────────────────────────────────────
    // This used to put each paused habit back in the DENOMINATOR instead —
    // scheduled and never done — which closed the hole by scoring the days
    // zero. It closed it far too hard. Measured on room A8GEL7: a member
    // doing 4x a week faithfully and pausing on 2 Aug read 13% against 93%,
    // with a 26-day streak gone and a month of red crosses on a strip for
    // days the room had never asked them about. Pausing was strictly worse
    // than quietly doing nothing, which is the opposite of the promise.
    //
    // RoomParticipant.standDownDays is the third answer: the day leaves BOTH
    // sides, exactly as a room-level pause does, so the percentage holds
    // still instead of collapsing — and it is not a rest day, so it can never
    // be farmed as a free finished day either (creditFor returns 0 for it and
    // isFullyDone is false). The exploit stays closed; the punishment goes.
    //
    // Asked PER DAY, not per "right now". The condition used to be the
    // notifier-level anyGradable, which describes the member's habits at the
    // moment of the sync — so resuming a single habit flipped it to true and
    // silently un-injected the whole paused stretch, handing back the exact
    // 100% this rule exists to deny. Whether a day had anything running is a
    // fact about that day, and resuming tomorrow cannot change it.
    //
    // Note this asks whether a habit was ACTIVE that day, not whether it was
    // due. A member with one live habit that simply is not scheduled on a
    // Tuesday has not stood anything down, so their Tuesday stays the rest day
    // it always was.
    bool hadStartedBy(String id, IslamicHabitTemplate habit, DateTime day) {
      final stints = stintsById[id];
      final d = DateTime(day.year, day.month, day.day);
      if (stints == null || stints.isEmpty) {
        final born = habit.createdAt;
        return born == null ||
            !d.isBefore(DateTime(born.year, born.month, born.day));
      }
      return stints.any((stint) {
        final start = stint.$1;
        return start == null ||
            !d.isBefore(DateTime(start.year, start.month, start.day));
      });
    }

    // Loop-invariant: which links resolve to a habit at all does not vary by
    // day, only whether each one was ACTIVE on a given day does.
    final resolvable = [
      for (final id in habitIds)
        if (habitById[id] case final IslamicHabitTemplate h) (id, h),
    ];
    // Every counted link has to resolve before any day can be a stand-down.
    //
    // A link with no habit behind it is a habit deleted out from under the
    // room, not one the member stepped back from — it keeps the old
    // scheduled-and-never-done treatment and its own warning
    // (roomLinkedHabitDeletedHint). Without this gate a MIXED plan (one habit
    // paused, one deleted) would have marked the day a stand-down and the
    // write loop below would then have dropped the deleted link's miss with
    // it, quietly excusing a day that had a real unanswered obligation on it.
    //
    // Identical to the tap path's `resolvedToday.length == linkedIds.length`
    // on purpose: the two must decide the same day the same way, which is the
    // whole invariant roomHasGradableHabit exists to hold.
    final everyLinkResolves =
        resolvable.length == habitIds.length && resolvable.isNotEmpty;
    final standDown = <String>{};
    for (var i = 0; i < days.length; i++) {
      if (!everyLinkResolves) break;
      final d = days[i];
      // Anything actually running that day means this is not a stand-down.
      if (resolvable.any((e) => countedOn(e.$2, d))) continue;
      // ── A day somebody actually TRAINED is never a stand-down ──────────
      //
      // countedOn answers "was the habit active", which is false for every
      // day after archivedAt — but a real square can still exist on such a
      // day. Back-painting one in the Grid puts it there, and so does a pause
      // whose recorded window ends earlier than the work did. Blanking those
      // days would drop credit the member had genuinely earned, which is the
      // opposite failure to the one this whole rule exists to fix: the point
      // is that a pause costs you nothing, not that it quietly erases the
      // last thing you did before it.
      //
      // Caught by Aziz on the trace screenshot: "I already did it yesterday",
      // about a day the strip had drawn as a stand-down bar.
      //
      // Green AND partial, because both score (see creditFor, where a جزئي is
      // worth half a habit). Deliberately NOT isSkipped: a تخطّي is a day you
      // said you were resting, it earns nothing, and it has no credit to
      // protect.
      if (resolvable.any((e) => isGreen(i, e.$1) || isPartial(i, e.$1))) {
        continue;
      }
      // Nothing had started yet: this is before the plan existed, not a
      // stretch anybody walked away from.
      if (!resolvable.any((e) => hadStartedBy(e.$1, e.$2, d))) continue;
      standDown.add(d.toDateKey());
    }

    // ── Pass 2: the weekly quota, which ONLY affects streaks. ─────────────
    // Records which WEEKS held: every flexible weekly-quota habit in them
    // reached its target, or is still in progress with time left. Those are
    // the weeks whose rest days are allowed to keep a streak alive (see
    // RoomParticipant.quotaOkWeeks / _keepsStreak).
    //
    // Phrased as "weeks that held" rather than "days that broke" on purpose:
    // an absent week then means "not excused", so a participant this device
    // knows nothing about yet scores 0 instead of being handed a phantom
    // streak. A week with no weekly-quota habit in it is simply never added -
    // there's no rest day to excuse, and its days stand or fall on
    // isFullyDone like any ordinary habit's.
    for (final entry in weeks.entries) {
      final dayIndices = entry.value;
      var sawWeeklyHabit = false;
      var allHeld = true;
      for (final id in habitIds) {
        final habit = habitById[id];
        if (habit == null) continue;
        final rule =
            roomRuleAt(effectiveRules[id]!, days[dayIndices.first].toDateKey());
        if (rule.frequencyType != HabitFrequencyType.weekly) continue;
        final window =
            dayIndices.where((i) => countedOn(habit, days[i])).toList();
        if (window.isEmpty) continue;
        sawWeeklyHabit = true;
        final credit = weeklyHabitCreditFor(
          completions: window.where((i) => isGreen(i, id)).length,
          target: rule.frequencyTarget,
          isWeekClosed: isQuotaWeekClosed(
            weekStart: entry.key,
            lastCountedDay: room.lastCountedDay,
            roomEnded: room.isEnded,
          ),
        );
        // ONLY a week that actually reached its target excuses its rest days.
        // Pending deliberately does not, even though the week is still open
        // and could still make it.
        //
        // Treating pending as "held" was a real bug: it meant every day of
        // the current week kept a streak alive regardless of whether anything
        // had been done in it, so a habit with an entirely empty week still
        // showed a streak equal to however many days the week was old. The
        // grace a still-open week deserves is the chance to *become*
        // credited, not credit in advance.
        //
        // Consequence worth knowing: mid-week, a rest day between two done
        // days does break the streak, and then the streak jumps back up to
        // the whole week the moment the target is reached. It reads slightly
        // steppy, but it is never inflated, and inflated is the failure that
        // actually misleads someone about their own habit.
        if (credit != WeeklyHabitCredit.credited) allHeld = false;
      }
      if (sawWeeklyHabit && allHeld) okWeeks.add(entry.key.toDateKey());
    }

    // Seeded from what's already stored, then overwritten for the recomputed
    // window only - anything older than `windowStart` keeps exactly the value
    // it was last written with, which is the whole point of windowing (see
    // the comment where windowStart is worked out). A full-backfill pass
    // starts from the room's first day anyway, so seeding is a no-op there.
    final dailyCounts = <String, int>{...mineNow.dailyDoneCount};
    final dailyScheduled = <String, int>{...mineNow.dailyScheduledCount};
    final dailyRested = <String, int>{...mineNow.dailyRestedCount};
    final dailyPartial = <String, int>{...mineNow.dailyPartialCount};
    // Same merge-then-overwrite-the-window treatment: keep every held week
    // from outside this window, replace the ones inside it.
    final okWeekSet = <String>{...mineNow.quotaOkWeeks};
    for (final wk in weeks.keys) {
      final wkKey = wk.toDateKey();
      if (okWeeks.contains(wkKey)) {
        okWeekSet.add(wkKey);
      } else {
        okWeekSet.remove(wkKey);
      }
    }
    // And again for the stand-down days (RoomParticipant.standDownDays):
    // recomputed for every day in this window, untouched outside it. Resuming
    // a habit therefore un-marks the days it covers on the next resync, which
    // is what makes a pause reversible rather than merely survivable.
    final standDownSet = <String>{...mineNow.standDownDays};
    for (final d in days) {
      final key = d.toDateKey();
      if (standDown.contains(key)) {
        standDownSet.add(key);
      } else {
        standDownSet.remove(key);
      }
    }
    // Whether this participant has any recorded day at all. False only for a
    // genuinely fresh link (or a brand-new room), where there's no earned
    // history to preserve and capping against nothing would zero out a real
    // room's first sync.
    final hasPriorRecord = mineNow.dailyDoneCount.isNotEmpty;
    for (final d in days) {
      final dateKey = d.toDateKey();
      final scheduled = scheduledCount[dateKey]!;
      // ── Back-dating can take credit away, never add it ────────────────
      // Ticking a past day's square in the Grid must not earn room progress
      // after the fact. That's the same stance the rest of the app already
      // takes on retroactive completions - setSquare's past-day branch gives
      // no XP, no gold and no streak for them, and a competition room is
      // exactly where letting someone fill in last week would matter most.
      //
      // So a past day is capped at whatever it had already earned while it
      // was still today: a fresh back-fill can't raise it, but un-ticking a
      // day it wrongly claimed still lowers it, which is the correcting
      // direction and should keep working. Today itself is never capped, and
      // neither is the one-time establishing pass for a participant who has
      // no recorded history yet (there's nothing to preserve, and capping
      // everything at zero would wipe a real room).
      //
      // ── ...but only for a day the room was actually watching ───────────
      // "What the room already recorded" is only a fair stand-in for "what
      // you earned on time" on the days a sync actually ran (see
      // RoomParticipant.lastSyncedDay). For every day this device spent
      // closed, offline, or with a fire-and-forget sync that quietly failed,
      // the stored count is 0 because nobody was looking - not because
      // nothing was done. Capping against that was permanent: the day could
      // never be recovered by any means, so the Grid kept showing the square
      // green while the room insisted the day never happened, and someone
      // who had genuinely trained looked like they were always behind.
      //
      // Days past the watermark are therefore taken from the real daily
      // history instead. The anti-cheat intent survives intact for the case
      // it was written for - someone actively using the app still can't
      // scroll back and colour in last week for credit, because those days
      // are exactly the observed ones.
      // A paused day is not graded at all: it keeps no credit and records
      // no miss, matching RoomParticipant.daysCompleted/daysElapsedIn which
      // both skip it. Writing a 0 here instead would make the day look
      // missed to anything that reads the raw map.
      //
      // A member's own stand-down day leaves by the same door, and for the
      // same reason: it is excluded from both sides of their ratio, so any
      // number written here could only ever be read as a claim about a day
      // nobody was asked about. See RoomParticipant.standDownDays.
      if (room.isPausedOn(dateKey) || standDown.contains(dateKey)) {
        dailyCounts.remove(dateKey);
        dailyScheduled.remove(dateKey);
        dailyRested.remove(dateKey);
        dailyPartial.remove(dateKey);
        continue;
      }
      var earned = doneCount[dateKey]!;
      final isPastDay = dateKey.compareTo(todayKey) < 0;
      // ── ...but only while the day is asking the SAME thing it asked before ──
      //
      // The clamp compares today's recomputed numerator against the one already
      // stored, which is only a fair comparison while the denominator has not
      // moved. When the scheduled count RISES, this day is being graded under a
      // rule it was not graded under before, and the stored numerator was
      // recorded under the old one.
      //
      // That is exactly the shape of the pause/resume repair. An account that
      // resumed a catalog habit before this fix had its pre-pause days written
      // as scheduled = 0 with their done keys deleted, because the resumed
      // habit claimed to have been born on the resume day. The stint rule above
      // now correctly restores scheduled = 1 for those days — and clamping the
      // numerator against the deleted 0 would have turned every genuinely
      // completed pre-pause day into a permanent, unrecoverable miss, which is
      // worse than the laundering it was meant to repair. Skipping the clamp on
      // a rise lets the numerator be re-derived from the squares the person
      // actually earned.
      //
      // Deliberately only on a RISE. Back-painting a past square for credit
      // leaves the scheduled count untouched, so it still meets the clamp; and
      // a FALLING count (a habit unlinked, a shared slot withdrawn) keeps it
      // too, so nothing can be farmed by shrinking a day's obligations.
      final storedScheduled = mineNow.scheduledCountFor(dateKey);
      final asksMoreThanBefore = scheduled > storedScheduled;
      // Capping the credit is all that's needed to deny the streak too: the
      // streak reads isFullyDone, which reads these very counts, so a day held
      // down to 0 can't hold a streak either. That's the "no XP, no gold, no
      // streak" rule falling out of one clamp instead of two places.
      if (hasPriorRecord &&
          isPastDay &&
          !asksMoreThanBefore &&
          mineNow.wasObservedOn(dateKey)) {
        final alreadyEarned = mineNow.dailyDoneCount[dateKey] ?? 0;
        if (earned > alreadyEarned) earned = alreadyEarned;
      }
      // remove-when-zero, not just set-when-nonzero: this day may have HAD a
      // stored value that no longer applies (a square un-ticked, a habit
      // unlinked), and a sparse map has to actually drop the key for that to
      // read as zero rather than keeping the stale number forever.
      // Compared against countedHabitCount, which is what
      // [RoomParticipant.scheduledCountFor] falls back to when the key is
      // absent, NOT against habitIds.length.
      //
      // The two differ by exactly the slots whose shared template the leader
      // has withdrawn: countedHabitIdsIn drops them, countedHabitCount does
      // not. Comparing against habitIds.length meant that after a withdrawal
      // a fully done day looked equal to the total, wrote no key, and then
      // fell back to the LARGER count. One of two slots withdrawn left every
      // day in the window at 0.5 credit with isFullyDone false, permanently,
      // and the clamp above pinned it there.
      //
      // The invariant room_model.dart:805-809 asserts is exactly this: a key
      // is written whenever the true count differs from the plain total the
      // fallback assumes. Both sides now say "plain total" the same way.
      if (scheduled != mineNow.countedHabitCount) {
        dailyScheduled[dateKey] = scheduled;
      } else {
        dailyScheduled.remove(dateKey);
      }
      // NO clamp on this one, unlike `earned` above. The clamp exists to stop
      // someone back-painting a past day for CREDIT, and this field pays
      // nothing. A تخطّي marked on an old day must reach the strip, or the
      // Grid and the room would sit side by side telling the user two
      // different stories about the same square.
      final rested = restedCount[dateKey]!;
      if (rested > 0) {
        dailyRested[dateKey] = rested;
      } else {
        dailyRested.remove(dateKey);
      }
      // This one DOES pay, so it takes the same clamp `earned` takes: a past
      // day the room was watching cannot be improved by back-painting a
      // جزئي onto it, exactly as it cannot by back-painting a green.
      var partial = partialCount[dateKey]!;
      if (hasPriorRecord && isPastDay && mineNow.wasObservedOn(dateKey)) {
        final alreadyPartial = mineNow.dailyPartialCount[dateKey] ?? 0;
        if (partial > alreadyPartial) partial = alreadyPartial;
      }
      if (partial > 0) {
        dailyPartial[dateKey] = partial;
      } else {
        dailyPartial.remove(dateKey);
      }
      if (earned > 0) {
        dailyCounts[dateKey] = earned;
      } else {
        dailyCounts.remove(dateKey);
      }
    }
    // Sorted so the stored array is stable between syncs - an unordered set
    // would rewrite the field with a reshuffled list every time, making real
    // changes impossible to spot when reading the doc.
    final storedOkWeeks = okWeekSet.toList()..sort();
    final storedStandDown = standDownSet.toList()..sort();

    // Built from rawIds, not habitIds - linkedHabitNames has to stay
    // index-for-index parallel with linkedHabitIds, so a skipped slot keeps
    // its stored name in place rather than collapsing the array and
    // silently shifting every later habit's name onto the wrong slot.
    // Refreshed only when every position resolved to a real name; a single
    // unresolvable slot (a habit deleted from Grid) leaves the whole stored
    // array untouched rather than writing a half-correct one.
    final storedNames = mineNow.linkedHabitNames;
    final names = <String>[];
    var namesComplete = true;
    for (var i = 0; i < rawIds.length; i++) {
      if (rawIds[i] == kDeclinedSlot) {
        names.add(i < storedNames.length ? storedNames[i] : '');
        continue;
      }
      final match = habitById[rawIds[i]];
      if (match == null) {
        namesComplete = false;
        break;
      }
      names.add(match.name);
    }

    // Mirrors isFullyDone(todayKey) at the moment of this write - this used
    // to be read by a Firestore-triggered Cloud Function's own before/after
    // diff (see room_reactions.dart's doc comment for why that approach was
    // dropped: Eventarc trigger creation for this project's Firestore
    // location turned out to be unavailable, not just a region-picking
    // choice). The edge is now detected right here instead - see
    // `shouldNotify` below - and the same field is still written, since
    // RoomParticipant.allDoneToday/allDoneDate remain what the in-app
    // reactions (room_reactions.dart) and the Rooms UI itself read.
    // `days` only reaches today's key while the room is still active
    // (lastCountedDay caps at today, see RoomModel.lastCountedDay) - once a
    // room has ended, today's key falls outside the computed range and
    // this is skipped entirely, leaving whatever value was last written in
    // place rather than guessing at a day this sync didn't actually cover.
    final todayScheduled = scheduledCount[todayKey];
    final allDoneTodayUpdate = todayScheduled == null
        ? const <String, Object?>{}
        : <String, Object?>{
            'allDoneToday':
                todayScheduled == 0 || doneCount[todayKey]! >= todayScheduled,
            'allDoneDate': todayKey,
          };
    // The false/missing -> true edge, for *today specifically* - checking
    // allDoneDate alongside allDoneToday (not just the bool alone) matters:
    // without it, a leftover `allDoneToday: true` from a day this
    // participant last touched the room (say, yesterday) would look
    // identical to "already notified today" and silently swallow a real,
    // fresh finish the first time this syncs today.
    final wasAlreadyNotifiedToday =
        mineNow.allDoneToday && mineNow.allDoneDate == todayKey;
    // ...and only when something was actually done today. `allDoneToday` is
    // true on a day with nothing outstanding, which now includes a weekly
    // quota's rest days once its target is met (see
    // [weeklyQuotaScheduledDays]) as well as a Mon/Wed habit's Tuesday. That
    // is the right answer for the plan card's checkmark and the wrong one
    // for a push: it would announce "Aziz finished their habits today" to
    // the whole room on each of the remaining rest days of a week whose
    // target was hit on Tuesday. See RoomParticipant.didCompleteAnythingOn.
    final shouldNotify = allDoneTodayUpdate['allDoneToday'] == true &&
        (doneCount[todayKey] ?? 0) > 0 &&
        !wasAlreadyNotifiedToday;

    // update(), NOT set(merge: true). This write's whole job includes
    // DELETING stale keys from the three sparse maps (see the
    // remove-when-zero comment above), and a merge-set physically cannot do
    // that: Firestore deep-merges map fields on merge, so a key absent from
    // the written map is kept, not dropped. Every removal this method ever
    // computed was silently ignored — which is exactly how a
    // dailyScheduledCount day once written as excused (0) stayed excused
    // through every later resync, and how un-ticking a square could leave
    // the room's old done-count in place. update() replaces each named
    // field wholesale, so the maps stored are exactly the maps computed.
    // The doc is guaranteed to exist (participantSnap.exists is checked at
    // the top, and this uid's own doc is only ever deleted by leaving the
    // room, which makes a failed update the correct outcome anyway).
    await participantRef.update({
      ..._profileFields(),
      if (namesComplete && names.length == rawIds.length)
        'linkedHabitNames': names,
      'dailyDoneCount': dailyCounts,
      'dailyScheduledCount': dailyScheduled,
      'dailyRestedCount': dailyRested,
      'dailyPartialCount': dailyPartial,
      // Stamped once and never moved. Everything behind it is outside the
      // rest allowance, which is what makes shipping this move nobody's
      // standing: on the first launch after the update every stored
      // percentage comes out identical, and the allowance earns from today.
      if (mineNow.restAllowanceFrom == null) 'restAllowanceFrom': todayKey,
      'quotaOkWeeks': storedOkWeeks,
      'standDownDays': storedStandDown,
      // Persists whatever this pass had to seed (see effectiveRules above),
      // so the room's frozen grading rules survive to the next sync instead
      // of being re-derived from the habit's current settings every time -
      // which would defeat the entire point of freezing them.
      'habitRules': effectiveRules.map(
        (k, v) => MapEntry(k, v.map((r) => r.toFirestore()).toList()),
      ),
      'lastUpdated': Timestamp.now(),
      // The room was watching today - which is what lets tomorrow's clamp
      // treat today's stored count as a real observation rather than an
      // absence of one. Advanced only to the day actually just graded, never
      // further, so the days between this and the previous watermark stay
      // correctly marked as unobserved. See RoomParticipant.lastSyncedDay.
      //
      // lastCountedDay, not today: for a room that has already ENDED those
      // two diverge, and writing today here broke the invariant the comment
      // above states. Grading stops at endDate (see RoomModel.lastCountedDay),
      // but merely *opening* an ended room ran this sync and pushed the
      // watermark to today - marking every day from endDate+1 to today as
      // "the room observed you and you did nothing". Those days are already
      // in the past, so the anti-backdating clamp then pinned them at 0
      // permanently. Invisible while the room stays ended (nothing reads past
      // lastCountedDay), but the moment a leader extends the room those zeros
      // fold straight into the larger denominator and every member who had
      // opened the finished room takes an unrecoverable score hit. Clamping
      // here keeps "observed" meaning "actually graded", which is what makes
      // extending a finished room safe at all.
      'lastSyncedDay': room.lastCountedDay.toDateKey(),
      ...allDoneTodayUpdate,
    });

    if (shouldNotify) unawaited(_notifyRoomFinish(room.code));
  }

  /// Called right after *any* screen changes *today's* square for
  /// [habitId] — Grid's own square taps, and Dashboard/Today's complete/
  /// slip/undo-slip actions alike (see [syncRoomToday], the shared
  /// call-site wrapper every one of them actually calls) - if that habit is
  /// linked to any still-open room (see [myLinkedRoomHabitsProvider] - it
  /// already filters out ended rooms, so a room that finished never gets a
  /// fresh "today" write from here), updates just today's entry in that
  /// room's dailyDoneCount using [todaySquares] (habitId -> SquareState for
  /// every habit, read straight from weeklyGridProvider's already-updated
  /// local state right after the change) rather than re-reading Firestore.
  /// Grid's own square write is fire-and-forget (see
  /// WeeklyGridNotifier._persistSquare's `.ignore()`), so reading it back
  /// immediately could still see the pre-change value; the local state
  /// right after a change never can, since it's updated synchronously
  /// before that write is even dispatched. This is deliberately a smaller,
  /// cheaper operation than [syncLinkedHabitsProgress] - just today's
  /// count, one participant-doc transaction per linked room, no day-range
  /// history re-fetch - since it fires on every single tap. A silent no-op
  /// for the (overwhelmingly common) case where [habitId] isn't linked to
  /// any open room at all.
  Future<void> syncTodayForHabit(
    String habitId,
    Map<String, SquareState> todaySquares,
  ) async {
    final rooms = _ref.read(myLinkedRoomHabitsProvider)[habitId];
    if (rooms == null || rooms.isEmpty) return;
    final uid = _uid;
    if (uid == null) return;
    // The same warm-up guard syncLinkedHabitsProgress carries, and for a
    // worse version of the same reason. habitListProvider is empty until
    // custom habits, the catalog and the overrides have all landed, and an
    // empty habitById sends EVERY linked id down the stale-link fail-open
    // below — so all of them land in today's denominator while only the
    // tapped square is green, and the doc is written that way with
    // lastSyncedDay advanced to claim the day as graded.
    //
    // A Grid tap is unlikely to beat the load (the row has to be on screen
    // to be tapped), but this method is also reached with no UI involved
    // at all: main.dart's notification actions complete a habit straight
    // from a banner on a cold start. Bailing costs one deferred update,
    // exactly as the comment on the transaction below already says — the
    // next full resync regrades the whole range.
    if (_ref.read(habitsStillLoadingProvider)) return;
    final todayDate = DateTime.now().effectiveDay;
    final today = todayDate.toDateKey();
    // Paused habits resolved alongside active ones, same as the full resync
    // (see its own note): this path only ever writes TODAY, so the history
    // argument does not bite here, but the two must agree about what a
    // linked id means or the divergence this whole rule exists to remove
    // comes straight back.
    final activeHabits = _ref.read(habitListProvider);
    final habitById = {
      for (final h in _ref.read(pausedHabitsProvider)) h.id: h,
      for (final h in activeHabits) h.id: h,
    };
    final activeIds = {for (final h in activeHabits) h.id};

    for (final room in rooms) {
      // Same guard as syncLinkedHabitsProgress: lobby/countdown days never
      // count.
      if (!room.hasStarted) continue;
      final participantRef =
          _rooms.doc(room.code).collection('participants').doc(uid);

      // A flexible weekly-quota linked habit (HabitFrequencyType.weekly)
      // can't be judged from today's tap alone - whether it counts depends
      // on the *whole week's* total, which only syncLinkedHabitsProgress's
      // full day-range read actually computes (see weeklyHabitCreditFor).
      // This fast path used to fall straight into the plain per-day
      // transaction below regardless, which - since isScheduledFor has
      // nothing weekday-specific to rule out for a habit like this -
      // credited it the instant *any* single day was ticked, full stop.
      // That briefly showed credit for a day the actual weekly quota
      // hadn't been met yet, which the next real resync (e.g. opening Room
      // Detail) then "corrected" back down - credit appearing on a tap and
      // vanishing on reopen, with nothing wrong actually happening. Routing
      // a room with any weekly-quota link through the full resync instead
      // means there's exactly one place that ever decides its credit, so
      // the two paths can never disagree. Slightly more expensive per tap
      // (one extra read plus, for a hit, a full day-range resync instead
      // of a single-day transaction) - but only for rooms that actually
      // have this kind of habit linked; the common all-regular-habits case
      // below is untouched.
      final freshSnap = await participantRef.get();
      if (!freshSnap.exists) continue;
      final freshMine = RoomParticipant.fromFirestore(freshSnap);
      // Judged by the room's own FROZEN rule (see RoomParticipant.habitRules)
      // rather than the habit's current settings, since the frozen rule is
      // what actually grades the day - a habit switched to weekly in the app
      // but still graded daily by this room belongs on the fast path, and
      // vice versa.
      // Three independent sources, ORed, and that redundancy is the whole
      // point. This guard decides whether a room's quota bookkeeping gets
      // computed at all, and every source it used to rely on can be empty
      // at the moment of a tap:
      //
      //   * countedHabitIds is empty for a participant whose link list
      //     hasn't loaded yet,
      //   * ruleFor returns null before habitRules has ever been written
      //     (i.e. before this device's first full resync),
      //   * habitById is empty until habitListProvider resolves.
      //
      // Miss on all three and the tap falls into the fast transaction below,
      // which writes dailyDoneCount and lastSyncedDay but NOT quotaOkWeeks,
      // and only ever touches dailyScheduledCount for *today*. A device that
      // only ever taps — never opens Room Detail — therefore accumulates a
      // participant doc with current done-counts and permanently empty quota
      // bookkeeping. Every met week silently stops excusing its rest days,
      // and that member reads far below what they actually earned while
      // someone doing identical work reads correctly. That is a real
      // production bug, found on room A8GEL7: two members, same shared 4x
      // habit, same 11 sessions, 76% vs 57%.
      //
      // The room's own shared plan is the source that cannot be empty when
      // it matters — in shared mode the plan IS the rule, it arrives with
      // the room document, and it needs nothing loaded on this device.
      final roomPlanIsQuota = room.sharedHabits
          .any((h) => h.frequencyType == HabitFrequencyType.weekly);
      final hasWeeklyLink = roomPlanIsQuota ||
          freshMine.countedHabitIds.any((id) {
            final rule = freshMine.ruleFor(id, today);
            final type = rule?.frequencyType ?? habitById[id]?.frequencyType;
            return type == HabitFrequencyType.weekly;
          });
      if (hasWeeklyLink) {
        // Hands the full resync this tap's own view of today (see that
        // method's [todaySquares] parameter) rather than letting it re-read
        // a square whose write may still be in flight.
        await syncLinkedHabitsProgress(room, todaySquares: todaySquares);
        continue;
      }

      // Set from inside the transaction body below, read back out here
      // once the transaction actually commits - never call the Cloud
      // Function from inside the callback itself, since Firestore retries
      // this whole block on contention and a network call inside it would
      // retry right along with it, double-sending a push for one real
      // finish.
      var shouldNotify = false;
      // A transaction, not a bare get()-then-set(): marking a habit done
      // and then immediately undoing it (exactly the "refund" case this
      // exists for) fires this twice in quick succession, each its own
      // async round-trip. Without a transaction, the second write to land
      // can be built from a read taken *before* the first write committed
      // - silently resurrecting the count the second call was supposed to
      // correct down. Firestore reruns this whole callback automatically
      // if the doc changes between its read and its write, so whatever
      // count this settles on is always computed from the latest data,
      // never a stale one.
      await FirebaseFirestore.instance.runTransaction((txn) async {
        final snap = await txn.get(participantRef);
        if (!snap.exists) return;
        final mine = RoomParticipant.fromFirestore(snap);
        // Exactly the same counting set syncLinkedHabitsProgress uses - a
        // skipped or leader-withdrawn slot must not sit in this path's
        // denominator either, or one tap would disagree with the next full
        // resync.
        final linkedIds = mine.countedHabitIdsIn(room);
        if (linkedIds.isEmpty) return;
        // Same "excuse today's unscheduled habits" logic as
        // syncLinkedHabitsProgress, and same use of the room's FROZEN
        // weekday rule rather than the habit's current one, so editing a
        // habit's days can't make this path and the full resync disagree
        // about whether today was even due. Falls back to the habit's own
        // current schedule only when no rule has been recorded yet.
        // Last line of defence. The caller already diverts a quota room to
        // the full resync, but that guard reads several things that can be
        // empty mid-load; this one reads the doc the transaction just
        // fetched, so it cannot be fooled by load order. If a quota rule is
        // recorded here, this path must not run at all — it is structurally
        // incapable of maintaining quotaOkWeeks, so completing it would
        // write a doc that looks synced (fresh lastSyncedDay) while silently
        // dropping every rest day the member earned.
        //
        // Bailing leaves the doc untouched rather than half-written: the
        // next full resync grades the whole range and gets it right. A
        // missed tap costs one deferred update; a half-write cost a member
        // 19 percentage points until someone noticed.
        final quotaRuleRecorded = linkedIds.any(
          (id) =>
              mine.ruleFor(id, today)?.frequencyType ==
              HabitFrequencyType.weekly,
        );
        if (quotaRuleRecorded) return;

        // The same single answer the full resync reads, so a tap and a
        // resync can no longer grade the same paused habit differently.
        // ACTIVE ids, not habitById, which also resolves paused habits.
        final anyGradable = roomHasGradableHabit(linkedIds, activeIds);
        // Today with every counted habit paused. The same day the full
        // resync's closing pass records in RoomParticipant.standDownDays, and
        // it has to be decided identically here or a tap and a room-open would
        // grade the same day two different ways — the exact class of bug
        // roomHasGradableHabit was written to end.
        //
        // A link with NO habit behind it is not a stand-down: that is a habit
        // deleted out from under the room, it has its own warning
        // (roomLinkedHabitDeletedHint), and nobody chose to step back from it.
        // So this asks specifically whether every resolvable link is one the
        // member paused.
        final resolvedToday = [
          for (final id in linkedIds)
            if (habitById[id] case final IslamicHabitTemplate h) h,
        ];
        final isStandDownToday = !anyGradable &&
            resolvedToday.isNotEmpty &&
            resolvedToday.length == linkedIds.length &&
            !resolvedToday.any((h) => habitExistedOn(h, todayDate)) &&
            // Same guard as the full resync's closing pass: a day with real
            // work on it is never a stand-down, or this path would blank a
            // square the member had just earned. Green and partial both
            // score; a تخطّي does not, so it does not protect the day.
            !resolvedToday.any((h) {
              final square = todaySquares[h.id] ?? SquareState.none;
              return square.isGreen || square == SquareState.partial;
            });
        final scheduledIds = linkedIds.where((id) {
          final habit = habitById[id];
          // A link with no habit at all behind it: gone, not paused. Off
          // both sides while anything else is running, and in the
          // denominator when nothing is, which is the one case that must
          // not pay for an empty day. See roomHasGradableHabit.
          if (habit == null) return !anyGradable;
          // Paused habits resolve, so this is where today falls out for
          // them: habitExistedOn is false for any day after archivedAt.
          // A stand-down day drops them here too — the day is excluded from
          // both sides of the ratio rather than scored, so putting anything
          // in the denominator for it would be a claim about a day the room
          // never asked about. See RoomParticipant.standDownDays.
          if (!habitExistedOn(habit, todayDate)) {
            return !anyGradable && !isStandDownToday;
          }
          final weekdays = mine.ruleFor(id, today)?.scheduledWeekdays ??
              habit.scheduledWeekdays;
          return weekdays.isEmpty || weekdays.contains(todayDate.weekday);
        }).toList();
        final doneCount = scheduledIds
            .where((id) => (todaySquares[id] ?? SquareState.none).isGreen)
            .length;
        // Display only, same wall as the full resync. Counted among the same
        // scheduledIds so the two paths cannot disagree about what was even
        // stood down.
        final restedToday = scheduledIds
            .where((id) =>
                (todaySquares[id] ?? SquareState.none) == SquareState.skipped)
            .length;
        final partialToday = scheduledIds
            .where((id) =>
                (todaySquares[id] ?? SquareState.none) == SquareState.partial)
            .length;
        final existingCounts = (snap.data()?['dailyDoneCount'] as Map?)?.map(
              (k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0),
            ) ??
            const <String, int>{};
        final existingPartial =
            (snap.data()?['dailyPartialCount'] as Map?)?.map(
                  (k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0),
                ) ??
                const <String, int>{};
        final existingRested =
            (snap.data()?['dailyRestedCount'] as Map?)?.map(
                  (k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0),
                ) ??
                const <String, int>{};
        final existingScheduled =
            (snap.data()?['dailyScheduledCount'] as Map?)?.map(
                  (k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0),
                ) ??
                const <String, int>{};
        final existingStandDown =
            (snap.data()?['standDownDays'] as List?)?.whereType<String>() ??
                const <String>[];
        final wasStandDown = existingStandDown.contains(today);
        // null means "fully scheduled, nothing excused" - the same sparse
        // convention syncLinkedHabitsProgress writes, so an absent key and
        // an explicit null both mean the same thing here.
        // countedHabitCount, not linkedIds.length, for the same reason the
        // full resync compares against it: linkedIds drops slots the leader
        // has withdrawn while scheduledCountFor's fallback does not, so
        // "equal to the total" here has to mean equal to the total the
        // FALLBACK will assume, or the key is omitted and the day silently
        // reverts to a larger denominator.
        final newScheduled = scheduledIds.length == mine.countedHabitCount
            ? null
            : scheduledIds.length;
        if ((existingCounts[today] ?? 0) == doneCount &&
            existingScheduled[today] == newScheduled &&
            (existingRested[today] ?? 0) == restedToday &&
            (existingPartial[today] ?? 0) == partialToday &&
            wasStandDown == isStandDownToday) {
          return; // Already correct - skip the write.
        }
        final updatedCounts = {...existingCounts};
        if (doneCount > 0) {
          updatedCounts[today] = doneCount;
        } else {
          updatedCounts.remove(today);
        }
        final updatedRested = {...existingRested};
        if (restedToday > 0) {
          updatedRested[today] = restedToday;
        } else {
          updatedRested.remove(today);
        }
        final updatedPartial = {...existingPartial};
        if (partialToday > 0) {
          updatedPartial[today] = partialToday;
        } else {
          updatedPartial.remove(today);
        }
        final updatedScheduled = {...existingScheduled};
        if (newScheduled != null) {
          updatedScheduled[today] = newScheduled;
        } else {
          updatedScheduled.remove(today);
        }
        // Add-or-remove, never add-only: resuming a habit part-way through the
        // day has to take today's mark back off, or the day would stay excused
        // for a member who is running again. Sorted for the same reason
        // quotaOkWeeks is — a stable array makes a real change readable in the
        // doc.
        final updatedStandDown = {...existingStandDown};
        if (isStandDownToday) {
          updatedStandDown.add(today);
        } else {
          updatedStandDown.remove(today);
        }
        final storedStandDown = updatedStandDown.toList()..sort();
        // Deliberately does NOT touch quotaOkWeeks. This path only runs for
        // rooms with no weekly-quota habit, so today's break status is just
        // "was anything due today left undone" - but today is exempt anyway
        // (currentStreak gives an unfinished today grace while the room is
        // live), and the next full resync settles it properly. Writing a
        // break for a day still in progress would flicker the streak to 0 on
        // the first tap of the morning.
        // Same allDoneToday/allDoneDate mirror as syncLinkedHabitsProgress's
        // doc comment describes, computed from this call's own (simpler,
        // no weekly-quota-credit distinction) done/scheduled numbers rather
        // than re-deriving anything - since this is the fast per-tap path,
        // whatever it decides "today" means is exactly what should trigger
        // the room-finish push, and the next full syncLinkedHabitsProgress
        // (room-open) reconciles it properly either way.
        final newAllDoneToday = !isStandDownToday &&
            (scheduledIds.isEmpty || doneCount >= scheduledIds.length);
        // Same date-aware edge check as syncLinkedHabitsProgress - see that
        // method's doc comment for why allDoneDate has to be checked
        // alongside the bool, not just the bool alone.
        final wasAlreadyNotifiedToday = snap.data()?['allDoneToday'] == true &&
            snap.data()?['allDoneDate'] == today;
        // Same "only announce a thing that actually happened" gate as the
        // full resync above - a day where every linked habit was excused is
        // finished, but it is not something to tell the room about.
        shouldNotify =
            newAllDoneToday && doneCount > 0 && !wasAlreadyNotifiedToday;
        // txn.update, NOT txn.set(merge: true), for the same reason the full
        // resync's write is an update(): the remove-today branches above are
        // real deletions, and a merge-set deep-merges map fields so a removed
        // key would silently survive — un-ticking today's square would then
        // leave the room's old credit in place forever. The doc exists
        // (snap.exists checked at the top of this transaction).
        txn.update(participantRef, {
          'dailyDoneCount': updatedCounts,
          'dailyScheduledCount': updatedScheduled,
          'dailyRestedCount': updatedRested,
          'dailyPartialCount': updatedPartial,
          'standDownDays': storedStandDown,
          'lastUpdated': Timestamp.now(),
          // This path graded today too, so it moves the watching-watermark
          // exactly like the full resync does - otherwise a person whose only
          // sync all day was a Grid tap would look unobserved tomorrow and
          // have today re-derived instead of trusted. See
          // RoomParticipant.lastSyncedDay.
          'lastSyncedDay': today,
          'allDoneToday': newAllDoneToday,
          'allDoneDate': today,
        });
      });
      if (shouldNotify) unawaited(_notifyRoomFinish(room.code));
    }
  }

  /// Best-effort trigger for the room-finish push (see functions/index.js's
  /// notifyRoomFinish callable) - called right after this device's own
  /// write flips allDoneToday false/missing -> true for [roomCode], from
  /// both syncLinkedHabitsProgress and syncTodayForHabit above. Never
  /// awaited by either caller and never allowed to throw outward: a push
  /// that fails to fire (offline, cold-started function, transient error)
  /// costs nothing more than a missed nudge to teammates, not worth
  /// surfacing as an error to the person who just finished their habits.
  /// The function itself re-verifies allDoneToday/allDoneDate server-side
  /// before sending anything - this call is a trigger, not a claim it
  /// blindly trusts.
  Future<void> _notifyRoomFinish(String roomCode) async {
    try {
      await FirebaseFunctions.instance
          .httpsCallable('notifyRoomFinish')
          .call({'roomCode': roomCode});
    } catch (_) {
      // Best-effort - see doc comment above.
    }
  }
}

final roomsControllerProvider =
    Provider<RoomsController>((ref) => RoomsController(ref));

/// Rooms this account belongs to that have finished, and whose ending this
/// device hasn't acknowledged yet — the input to the "your challenge
/// finished" popup (see RoomFinaleAnnouncer in main.dart).
///
/// Everything here is recomputed from live data rather than remembered, and
/// that's the whole design. A room the leader deleted has already dropped out
/// of [myRoomCodesProvider] (or resolves to a null doc), so it can't announce
/// anything. A room that got extended is no longer [RoomModel.isEnded], so it
/// can't either. A scheduled notification could have made neither of those
/// promises — it would have fired on the date regardless, about a room that
/// might no longer exist.
///
/// Empty while the underlying streams are still warming up, which is exactly
/// right: nothing should pop up before we actually know the state of a room.
final unseenFinishedRoomsProvider = Provider<List<RoomModel>>((ref) {
  final uid = ref.watch(authStateProvider).asData?.value?.uid;
  if (uid == null) return const [];
  return unseenFinishedRooms(
    myCodes: ref.watch(myRoomCodesProvider).valueOrNull ?? const <String>[],
    seenCodes: ref.watch(roomFinaleSeenProvider),
    roomFor: (code) => ref.watch(roomProvider(code)).valueOrNull,
  );
});

/// The selection itself, as a plain function - same unit-testability
/// reasoning as [weeklyQuotaScheduledDays]/[roomRuleAt]/[nextLeaderAfter]:
/// every "should this announce?" case can then be checked with hand-built
/// arguments and no Firestore, no auth and no widgets involved.
///
/// [roomFor] returns null for a code whose room document isn't there (or
/// hasn't loaded), which is precisely how a deleted room ends up silent.
List<RoomModel> unseenFinishedRooms({
  required List<String> myCodes,
  required Set<String> seenCodes,
  required RoomModel? Function(String code) roomFor,
}) {
  final out = <RoomModel>[];
  for (final code in myCodes) {
    if (seenCodes.contains(code)) continue;
    final room = roomFor(code);
    // Not there (deleted, or still loading) -> nothing to announce.
    // Still running (never ended, or the leader extended it) -> likewise.
    if (room == null || !room.isEnded) continue;
    out.add(room);
  }
  return out;
}
