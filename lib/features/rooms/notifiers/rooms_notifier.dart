import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/datetime_ext.dart';
import '../../auth/notifiers/auth_notifier.dart';
import '../../character/notifiers/character_notifier.dart';
import '../../dashboard/notifiers/dashboard_notifier.dart';
import '../../grid/models/square_state.dart';
import '../../grid/notifiers/weekly_grid_notifier.dart';
import '../../habits/catalog/islamic_habit_catalog.dart';
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
      .map((snap) =>
          (snap.data()?['roomCodes'] as List?)?.whereType<String>().toList() ??
          const <String>[]);
});

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
    final participants =
        ref.watch(roomParticipantsProvider(code)).valueOrNull;
    if (participants == null) continue;
    final mine = participants.where((p) => p.uid == uid);
    if (mine.isEmpty) continue;
    for (final habitId in mine.first.linkedHabitIds) {
      (result[habitId] ??= []).add(room);
    }
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
  if (!day.isToday) return;
  final todayRow =
      ref.read(weeklyGridProvider).states[day.toDateKey()] ?? const {};
  ref.read(roomsControllerProvider).syncTodayForHabit(habitId, todayRow).ignore();
}

/// Set the instant a `growdaily://join/CODE` deep link arrives (see
/// main.dart's AppLinks wiring + [parseRoomJoinLink]), consumed exactly
/// once by _OnboardingOrGrid's listener - the first widget that's safe to
/// navigate from, since it only ever builds once the language/auth/
/// onboarding gates are already behind the user - to jump straight to
/// Rooms with the code pre-filled instead of the normal tap-through (open
/// app -> Profile -> Rooms -> Join -> type the code by hand).
final pendingJoinCodeProvider = StateProvider<String?>((ref) => null);

/// Parses a `growdaily://join/CODE` deep link into a room code, or null if
/// [uri] doesn't match that shape - so a malformed link, or a link some
/// other feature/OS handler hands this app for an unrelated reason, is
/// silently ignored instead of ever being force-fit into a room-code
/// lookup. The code is upper-cased here to match [previewRoom]'s own
/// normalization, so a link's code always resolves the same way typing it
/// by hand would. See main.dart's AppLinks wiring - the only caller.
String? parseRoomJoinLink(Uri uri) {
  if (uri.scheme.toLowerCase() != 'growdaily') return null;
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
  String habitId,
) {
  final idx = linkedHabitIds.indexOf(habitId);
  if (idx < 0) return (linkedHabitIds, linkedHabitNames);
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
    final displayName = savedName.isNotEmpty
        ? savedName
        : (email?.split('@').first ?? 'Warrior');
    final character = _ref.read(characterProvider);
    return {
      'displayName': displayName,
      'characterId': character.characterId,
      if (character.equippedAccessoryId != null)
        'accessoryId': character.equippedAccessoryId,
    };
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
          .map((h) => RoomHabitTemplate(
                name: h.name,
                category: h.category,
                iconColorHex: h.iconColorHex,
                frequencyType: h.frequencyType,
                frequencyTarget: h.frequencyTarget,
              ))
          .toList(),
      duration: duration,
      startDate: startDate,
      endDate: null,
      status: 'lobby',
      lengthDays: duration == RoomDuration.fixed ? lengthDays : null,
    );
    final participant = RoomParticipant(
      uid: uid,
      displayName: profile['displayName'] as String,
      characterId: profile['characterId'] as String,
      accessoryId: profile['accessoryId'] as String?,
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
    await _userRef(uid).set({
      'roomCodes': FieldValue.arrayUnion([code]),
    }, SetOptions(merge: true));
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
    if (room.habitMode == RoomHabitMode.shared && room.sharedHabits.isNotEmpty) {
      final myHabits = _ref.read(habitListProvider);
      final ids = <String>[];
      final names = <String>[];
      for (var i = 0; i < room.sharedHabits.length; i++) {
        final template = room.sharedHabits[i];
        final resolution = i < planResolutions.length ? planResolutions[i] : null;
        IslamicHabitTemplate? existingMatch;
        if (resolution != null) {
          final found = myHabits.where((h) => h.id == resolution);
          if (found.isNotEmpty) existingMatch = found.first;
        }
        if (existingMatch != null) {
          ids.add(existingMatch.id);
          names.add(existingMatch.name);
          continue;
        }
        // No existing habit chosen (or it vanished between preview and
        // submit) - create a fresh one from the plan's own snapshot.
        final created = _ref.read(customHabitsProvider.notifier).add(
              name: template.name,
              category: template.category,
              frequencyType: template.frequencyType,
              frequencyTarget: template.frequencyTarget,
              iconColorHex: template.iconColorHex,
            );
        ids.add(created.id);
        names.add(created.name);
      }
      resolvedIds = ids;
      resolvedNames = names;
    } else if (room.habitMode == RoomHabitMode.own && linkedHabitIds.isNotEmpty) {
      resolvedIds = linkedHabitIds;
      resolvedNames = linkedHabitNames;
    }

    if (existing.exists) {
      await participantRef.set({
        ...profile,
        if (resolvedIds.isNotEmpty) ...{
          'linkedHabitIds': resolvedIds,
          'linkedHabitNames': resolvedNames,
        },
      }, SetOptions(merge: true));
      await syncLinkedHabitsProgress(room);
      return true;
    }

    final participant = RoomParticipant(
      uid: uid,
      displayName: profile['displayName'] as String,
      characterId: profile['characterId'] as String,
      accessoryId: profile['accessoryId'] as String?,
      joinedAt: DateTime.now(),
      linkedHabitIds: resolvedIds,
      linkedHabitNames: resolvedNames,
      lastUpdated: DateTime.now(),
    );
    await participantRef.set(participant.toFirestore());
    await _rooms.doc(room.code).set({
      'memberCount': FieldValue.increment(1),
    }, SetOptions(merge: true));
    await _userRef(uid).set({
      'roomCodes': FieldValue.arrayUnion([room.code]),
    }, SetOptions(merge: true));
    if (resolvedIds.isNotEmpty) await syncLinkedHabitsProgress(room);
    return true;
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
      final roster = rosterSnap.docs.map(RoomParticipant.fromFirestore).toList();
      final successor = nextLeaderAfter(uid, roster);
      if (successor == null) {
        await deleteRoom(room);
        return;
      }
      await _rooms.doc(room.code).set({
        'createdBy': successor.uid,
        'createdByName': successor.displayName,
      }, SetOptions(merge: true));
    }

    await participantRef.delete();
    await _rooms.doc(room.code).set({
      'memberCount': FieldValue.increment(-1),
    }, SetOptions(merge: true)).catchError((_) {});
    await _userRef(uid).set({
      'roomCodes': FieldValue.arrayRemove([room.code]),
    }, SetOptions(merge: true));
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
    await _userRef(uid).set({
      'roomCodes': FieldValue.arrayRemove([code]),
    }, SetOptions(merge: true));
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
    await _userRef(uid).set({
      'roomCodes': FieldValue.arrayRemove([room.code]),
    }, SetOptions(merge: true));
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
    await _rooms.doc(room.code).set({
      'scheduledStartAt': Timestamp.fromDate(startAt),
    }, SetOptions(merge: true));
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
    await _rooms.doc(room.code).set({
      'status': 'active',
      'startDate': Timestamp.fromDate(start),
      'scheduledStartAt': FieldValue.delete(),
      if (room.duration == RoomDuration.fixed && days != null)
        'endDate': Timestamp.fromDate(start.add(Duration(days: days - 1))),
    }, SetOptions(merge: true));
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
  Future<void> extendRoom(RoomModel room, int? lengthDays) async {
    final uid = _uid;
    if (uid == null || uid != room.createdBy) return;
    if (lengthDays == null) {
      await _rooms.doc(room.code).set({
        'duration': RoomDuration.open.toJson(),
        'endDate': FieldValue.delete(),
      }, SetOptions(merge: true));
      return;
    }
    final today = DateTime.now().effectiveDay;
    final newEnd = today.add(Duration(days: lengthDays - 1));
    await _rooms.doc(room.code).set({
      'duration': RoomDuration.fixed.toJson(),
      'endDate': Timestamp.fromDate(newEnd),
    }, SetOptions(merge: true));
  }

  /// Shows or hides this participant's linked-habit name(s) from other
  /// members' leaderboard rows - progress (%, heatmap, day count) is always
  /// visible either way, this only toggles the habit-name chips. Purely a
  /// display flag on this participant's own doc.
  Future<void> toggleHideDetails(String code, bool hide) async {
    final uid = _uid;
    if (uid == null) return;
    await _rooms.doc(code).collection('participants').doc(uid).set({
      'hideDetails': hide,
    }, SetOptions(merge: true));
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
    final rooms = _ref.read(myLinkedRoomHabitsProvider)[habitId];
    if (rooms == null || rooms.isEmpty) return;
    final uid = _uid;
    if (uid == null) return;
    for (final room in rooms) {
      final participantRef =
          _rooms.doc(room.code).collection('participants').doc(uid);
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
      final (newIds, newNames) = removeLinkedHabit(ids, names, habitId);
      await participantRef.set({
        'linkedHabitIds': newIds,
        'linkedHabitNames': newNames,
        'lastUpdated': Timestamp.now(),
      }, SetOptions(merge: true));
    }
  }

  /// Recomputes this participant's per-day completion counts for [room]
  /// straight from their real daily habit history (`users/{uid}/daily/
  /// {date}`, the same records the Grid screen reads) across *all* of their
  /// currently-linked habits for this room - each linked habit is detected
  /// and counted independently (see RoomParticipant.dailyDoneCount's doc
  /// comment), so a day with only some of them green still earns partial
  /// credit instead of nothing. Also checks each linked habit's own
  /// schedule (IslamicHabitTemplate.isScheduledFor) for every day in
  /// range, so a habit that isn't scheduled that day - the exact same
  /// "blocked, nothing to do" state the habit's own Grid square shows -
  /// is excused from that day's count instead of silently counting as
  /// missed (see RoomParticipant.dailyScheduledCount). Always re-reads
  /// this participant's own current linkedHabitIds from Firestore first
  /// rather than trusting a stale in-memory list, so this can safely be
  /// called from anywhere (Room Detail on open, pull-to-refresh, or right
  /// after joining) without any caller needing to track which habits are
  /// linked itself - the lighter-weight [syncTodayForHabit] below is what
  /// actually fires on every Grid tap instead. A full recompute (not an
  /// incremental add) each time, since a day's square can also be *un*-set
  /// after the fact - this keeps the room's copy from ever silently
  /// drifting out of sync with the real thing.
  Future<void> syncLinkedHabitsProgress(RoomModel room) async {
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
    final habitIds = (participantSnap.data()?['linkedHabitIds'] as List?)
            ?.whereType<String>()
            .toList() ??
        const [];
    if (habitIds.isEmpty) return;

    // Looked up once, up front, so each day's scheduling check below is a
    // plain map lookup rather than a re-scan of the whole habit list.
    final myHabits = _ref.read(habitListProvider);
    final habitById = {for (final h in myHabits) h.id: h};

    final days = <DateTime>[];
    for (var day = room.startDate;
        !day.isAfter(room.lastCountedDay);
        day = day.add(const Duration(days: 1))) {
      days.add(day);
    }
    final userRef = _userRef(uid);
    final snaps = await Future.wait(
      days.map((d) => userRef.collection('daily').doc(d.toDateKey()).get()),
    );
    final dailyCounts = <String, int>{};
    final dailyScheduled = <String, int>{};
    for (var i = 0; i < snaps.length; i++) {
      final day = days[i];
      final dateKey = day.toDateKey();
      // A linked habit that wasn't even scheduled this day (e.g. a
      // Mon/Wed/Fri-only habit on a Tuesday) doesn't count against the
      // day at all - it was never something to do, not something
      // skipped. See RoomParticipant.dailyScheduledCount's doc comment.
      // A linked habit no longer found (deleted from Grid after being
      // linked) fails open - still counts as scheduled - so a stale link
      // can't quietly make every other day easier; that's the same
      // "explain, don't fix silently" edge case _MyPlanCard's
      // hasDeletedLink warning already covers.
      final scheduledIds = habitIds
          .where((id) => habitById[id]?.isScheduledFor(day) ?? true)
          .toList();
      if (scheduledIds.length != habitIds.length) {
        dailyScheduled[dateKey] = scheduledIds.length;
      }
      final raw = snaps[i].data()?['squareStates'];
      if (raw is! Map) continue;
      final doneCount = scheduledIds
          .where((id) => SquareState.fromJson(raw[id]?.toString()).isGreen)
          .length;
      if (doneCount > 0) dailyCounts[dateKey] = doneCount;
    }

    final names = <String>[];
    for (final id in habitIds) {
      final match = habitById[id];
      if (match == null) continue;
      names.add(match.name);
    }

    await participantRef.set({
      ..._profileFields(),
      if (names.length == habitIds.length) 'linkedHabitNames': names,
      'dailyDoneCount': dailyCounts,
      'dailyScheduledCount': dailyScheduled,
      'lastUpdated': Timestamp.now(),
    }, SetOptions(merge: true));
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
    final todayDate = DateTime.now().effectiveDay;
    final today = todayDate.toDateKey();
    final habitById = {for (final h in _ref.read(habitListProvider)) h.id: h};

    for (final room in rooms) {
      // Same guard as syncLinkedHabitsProgress: lobby/countdown days never
      // count.
      if (!room.hasStarted) continue;
      final participantRef =
          _rooms.doc(room.code).collection('participants').doc(uid);
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
        final linkedIds = (snap.data()?['linkedHabitIds'] as List?)
                ?.whereType<String>()
                .toList() ??
            const [];
        if (linkedIds.isEmpty) return;
        // Same "excuse today's unscheduled habits" logic as
        // syncLinkedHabitsProgress - see that method's doc comment.
        final scheduledIds = linkedIds
            .where((id) => habitById[id]?.isScheduledFor(todayDate) ?? true)
            .toList();
        final doneCount = scheduledIds
            .where((id) => (todaySquares[id] ?? SquareState.none).isGreen)
            .length;
        final existingCounts = (snap.data()?['dailyDoneCount'] as Map?)?.map(
              (k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0),
            ) ??
            const <String, int>{};
        final existingScheduled =
            (snap.data()?['dailyScheduledCount'] as Map?)?.map(
                  (k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0),
                ) ??
                const <String, int>{};
        // null means "fully scheduled, nothing excused" - the same sparse
        // convention syncLinkedHabitsProgress writes, so an absent key and
        // an explicit null both mean the same thing here.
        final newScheduled = scheduledIds.length == linkedIds.length
            ? null
            : scheduledIds.length;
        if ((existingCounts[today] ?? 0) == doneCount &&
            existingScheduled[today] == newScheduled) {
          return; // Already correct - skip the write.
        }
        final updatedCounts = {...existingCounts};
        if (doneCount > 0) {
          updatedCounts[today] = doneCount;
        } else {
          updatedCounts.remove(today);
        }
        final updatedScheduled = {...existingScheduled};
        if (newScheduled != null) {
          updatedScheduled[today] = newScheduled;
        } else {
          updatedScheduled.remove(today);
        }
        txn.set(participantRef, {
          'dailyDoneCount': updatedCounts,
          'dailyScheduledCount': updatedScheduled,
          'lastUpdated': Timestamp.now(),
        }, SetOptions(merge: true));
      });
    }
  }
}

final roomsControllerProvider =
    Provider<RoomsController>((ref) => RoomsController(ref));
