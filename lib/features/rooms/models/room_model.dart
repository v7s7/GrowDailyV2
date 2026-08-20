import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/extensions/datetime_ext.dart';
import '../../../core/utils/western_digits.dart';
import '../../habits/models/habit_model.dart';

enum RoomHabitMode {
  shared, // leader picks a plan (1+ habits) that gets cloned to every joiner
  own; // each participant links one of their own existing habits

  String toJson() => name;
  static RoomHabitMode fromJson(String? v) =>
      values.firstWhere((e) => e.name == v, orElse: () => shared);
}

enum RoomDuration {
  fixed, // has an end date, set once at creation
  open; // no end date - runs until people leave

  String toJson() => name;
  static RoomDuration fromJson(String? v) =>
      values.firstWhere((e) => e.name == v, orElse: () => open);
}

/// The leader's chosen "spirit" for a room, set once at creation (same
/// creation-only timing as [RoomHabitMode]/[RoomDuration] - no leader
/// affordance changes it after the fact). [competitive] is the room this
/// app always had: the individual leaderboard/podium/Room Race widgets
/// ranking participants against each other. [team] layers a shared goal on
/// top of that exact same leaderboard (see [RoomTeamProgress]) - reach it
/// *together* and every participant claims a one-time bonus (see
/// RoomsController.claimTeamBonus) - without hiding or replacing the
/// individual ranking, which keeps showing either way.
///
/// Defaults to [competitive] both here and in [fromJson] - every room
/// created before this field existed was, and still is, exactly that.
enum RoomCompeteMode {
  competitive,
  team;

  String toJson() => name;
  static RoomCompeteMode fromJson(String? v) =>
      values.firstWhere((e) => e.name == v, orElse: () => competitive);
}

/// A single habit in a [RoomHabitMode.shared] room's plan, snapshotted from
/// the leader's own habit at creation time (name/category/color/frequency)
/// so a joiner who's never met the leader can still render an icon and
/// color for it, and so [RoomsController.joinRoom] has everything it needs
/// to create a matching habit for anyone who doesn't already have one -
/// see room_model.dart's top-of-file doc and RoomsController.joinRoom.
///
/// Deliberately doesn't carry [scheduledWeekdays] - a joiner-created habit
/// always starts as "every day", kept simple. This is just about what a
/// *freshly created* clone starts with, though - once linked, a habit's
/// real schedule (whether it's this default "every day" or something the
/// joiner later restricts, e.g. Mon/Wed/Fri only) absolutely does matter to
/// the room's completion math, which excuses a day a linked habit wasn't
/// even scheduled for rather than counting it as missed - see
/// [RoomParticipant.dailyScheduledCount].
///
/// (See [RoomHabitTemplate] below, which this describes - the class itself
/// sits under [kDeclinedSlot] and [RoomHabitRule].)

/// Stand-in id stored at a shared-plan slot's position in
/// [RoomParticipant.linkedHabitIds] when this participant deliberately
/// skipped that slot rather than linking a habit to it (see
/// RoomsController.declineSharedHabit). The slot keeps its *position* -
/// linkedHabitIds stays index-for-index parallel with [RoomModel.
/// sharedHabits], which every read site in this feature relies on - while
/// counting for nothing: RoomsController.syncLinkedHabitsProgress leaves it
/// out of both the numerator and the denominator, so a skipped habit can
/// neither earn nor cost this person anything.
///
/// A literal sentinel rather than a parallel `declinedIndexes` array
/// specifically to preserve that positional parallelism: a separate array
/// would leave linkedHabitIds shorter than sharedHabits, which is the exact
/// condition the unresolved-plan banner and resolvePlanHabit's
/// "must be the next slot" guard both key off, so a skip would have looked
/// identical to "hasn't decided yet" forever. Real habit ids are uuids, so
/// this can never collide with one.
const String kDeclinedSlot = '__declined__';

/// One period during which a participant's linked habit was graded by a
/// particular cadence, inside one room - the room's own frozen copy of
/// "what this habit was worth back then," which is what stops editing a
/// habit today from silently re-grading months of finished history (see
/// [RoomParticipant.habitRules]).
class RoomHabitRule {
  /// Effective-day date key (YYYY-MM-DD) this rule starts applying from,
  /// inclusive, running until the next rule's [from] or forever. Stored as
  /// the plain key string rather than a Timestamp on purpose: every lookup
  /// compares it against another date key, and YYYY-MM-DD sorts
  /// chronologically as a plain string, so no parsing is needed to find the
  /// rule in force on a given day.
  final String from;
  final HabitFrequencyType frequencyType;
  final int frequencyTarget;
  final List<int> scheduledWeekdays;

  const RoomHabitRule({
    required this.from,
    required this.frequencyType,
    required this.frequencyTarget,
    this.scheduledWeekdays = const [],
  });

  /// Whether [other] grades days any differently than this rule does - the
  /// check behind the room's "your habit's settings no longer match what
  /// this room is scoring you on" warning. Compares only the three things
  /// that actually affect credit; a rename or a colour change is not a rule
  /// change.
  bool differsFrom({
    required HabitFrequencyType frequencyType,
    required int frequencyTarget,
    required List<int> scheduledWeekdays,
  }) {
    if (this.frequencyType != frequencyType) return true;
    if (this.frequencyTarget != frequencyTarget) return true;
    final a = [...this.scheduledWeekdays]..sort();
    final b = [...scheduledWeekdays]..sort();
    if (a.length != b.length) return true;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return true;
    }
    return false;
  }

  Map<String, dynamic> toFirestore() => {
        'from': from,
        'frequencyType': frequencyType.toJson(),
        'frequencyTarget': frequencyTarget,
        if (scheduledWeekdays.isNotEmpty)
          'scheduledWeekdays': scheduledWeekdays,
      };

  factory RoomHabitRule.fromMap(Map<String, dynamic> d) => RoomHabitRule(
        from: (d['from'] as String?) ?? '',
        frequencyType: HabitFrequencyType.fromJson(
          d['frequencyType'] as String? ?? 'daily',
        ),
        frequencyTarget: (d['frequencyTarget'] as num?)?.toInt() ?? 1,
        scheduledWeekdays: (d['scheduledWeekdays'] as List?)
                ?.whereType<num>()
                .map((n) => n.toInt())
                .where((n) => n >= DateTime.monday && n <= DateTime.sunday)
                .toList() ??
            const [],
      );
}

class RoomHabitTemplate {
  final String name;
  final HabitCategory category;
  final String? iconColorHex;
  final HabitFrequencyType frequencyType;
  final int frequencyTarget;

  /// When the room's leader withdrew this slot from the plan - null while
  /// it's still live. A soft delete, deliberately: actually removing the
  /// entry would shift every later slot's index down by one, and since
  /// [RoomParticipant.linkedHabitIds] is positionally parallel to this list
  /// and each participant may only write their OWN participant doc (see
  /// firestore.rules), the leader has no way to re-align everyone else's
  /// arrays to match. Stamping it instead keeps every index stable forever;
  /// syncLinkedHabitsProgress simply skips a removed slot (it counts for
  /// nothing, exactly like [kDeclinedSlot]), and the UI greys it out. Also
  /// makes the removal reversible, which a real delete would not be.
  final DateTime? removedAt;

  /// When this entry joined the plan - null for every entry the room was
  /// actually *created* with (every one of those is born together, so
  /// there's nothing to distinguish), set to the moment RoomsController.
  /// addSharedHabit ran for anything the leader adds to an already-existing
  /// room's plan later. Purely informational (a "New" badge, an "Added Jul
  /// 28" label) - see that field's own note in addSharedHabit's doc comment
  /// for why this deliberately does NOT gate syncLinkedHabitsProgress's
  /// day-by-day math: a slot added mid-room still uses each participant's
  /// own linked habit's *real* history once they resolve it, exactly the
  /// same as a member who joins the room late already gets credited for
  /// real activity going all the way back to room.startDate, not just from
  /// their own joinedAt. A newly-added slot follows that identical,
  /// already-shipped precedent rather than inventing a second, different
  /// rule just for itself.
  final DateTime? addedAt;

  const RoomHabitTemplate({
    required this.name,
    required this.category,
    this.iconColorHex,
    required this.frequencyType,
    required this.frequencyTarget,
    this.addedAt,
    this.removedAt,
  });

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'category': category.toJson(),
        if (iconColorHex != null) 'iconColorHex': iconColorHex,
        'frequencyType': frequencyType.toJson(),
        'frequencyTarget': frequencyTarget,
        if (addedAt != null) 'addedAt': Timestamp.fromDate(addedAt!),
        if (removedAt != null) 'removedAt': Timestamp.fromDate(removedAt!),
      };

  factory RoomHabitTemplate.fromMap(Map<String, dynamic> d) =>
      RoomHabitTemplate(
        name: (d['name'] as String?) ?? '',
        category: HabitCategory.fromJson(d['category'] as String? ?? 'custom'),
        iconColorHex: d['iconColorHex'] as String?,
        frequencyType: HabitFrequencyType.fromJson(
          d['frequencyType'] as String? ?? 'daily',
        ),
        frequencyTarget: d['frequencyTarget'] as int? ?? 1,
        addedAt: (d['addedAt'] as Timestamp?)?.toDate(),
        removedAt: (d['removedAt'] as Timestamp?)?.toDate(),
      );

  /// Whether the leader has withdrawn this slot - see [removedAt].
  bool get isRemoved => removedAt != null;
}

/// Stored at: rooms/{code}
///
/// A room is the multi-user challenge a leader creates and others join by
/// [code] (the document's own id - see [generateRoomCode]). Unlike every
/// other synced doc in the app (each scoped to `users/{uid}`, one writer per
/// field), a room is read by every member but this top-level doc itself only
/// changes on create - see [RoomParticipant] for the per-member data each
/// device owns and writes on its own.
class RoomModel {
  final String code;
  final String name;
  final String createdBy;
  final String createdByName;
  final DateTime createdAt;
  final RoomHabitMode habitMode;

  /// Only populated when [habitMode] is [RoomHabitMode.shared] - the plan
  /// (1 or more habits) every participant in this room commits to. Each
  /// participant links their own real habit to every entry here (matching
  /// an existing one where possible, otherwise creating a new one - see
  /// RoomsController.joinRoom) so completion is always driven by their real
  /// Grid, never a separate manual tracker. Ignored in 'own' mode, where
  /// each participant links one of their own habits directly instead.
  final List<RoomHabitTemplate> sharedHabits;
  final RoomDuration duration;

  /// Always midnight-aligned (effectiveDay) - see RoomsController.createRoom.
  final DateTime startDate;

  /// Null when [duration] is [RoomDuration.open] - the room never locks.
  /// Always midnight-aligned when set.
  final DateTime? endDate;

  /// Date-key ranges the room was NOT running — the dead time between a
  /// room ending and a leader extending it.
  ///
  /// Extending used to simply push endDate out from today, which silently
  /// swept every dead day into the denominator: a room that ended on the
  /// 14th and was extended on the 17th handed all three members three fresh
  /// misses for days the room did not exist. Everyone's percentage dropped
  /// the instant the leader tapped extend, which made extending feel like a
  /// punishment for the group.
  ///
  /// A paused day is excluded from BOTH sides — it is not elapsed and it is
  /// not missed. Nobody was asked for anything, so nobody owes anything.
  /// That is the only reading that leaves an extension score-neutral, which
  /// is what makes it safe to offer at all.
  ///
  /// Stored as `[{from, to}]` inclusive date keys, oldest first. Empty for
  /// every room that has never been extended, so this is additive: existing
  /// rooms score exactly as they did before.
  final List<({String from, String to})> pausedSpans;

  /// Whether [dateKey] falls inside any paused span.
  bool isPausedOn(String dateKey) => pausedSpans.any(
        (s) => dateKey.compareTo(s.from) >= 0 && dateKey.compareTo(s.to) <= 0,
      );

  /// Denormalized headcount so a "my rooms" list can show it without a
  /// second read per room - kept in sync by RoomsController.joinRoom/
  /// leaveRoom via FieldValue.increment.
  final int memberCount;

  /// Lifecycle: 'lobby' (created, members gathering, nothing counts yet)
  /// or 'active' (the leader hit Start). Missing on any room created
  /// before this field existed - those were born active, so the default
  /// keeps them exactly as they were. There's deliberately no 'ended'
  /// value: ending is derived from [endDate] (see [isEnded]) so a room
  /// can never claim to be over on a different day than its dates say.
  final String status;

  /// For a fixed-length room created in the lobby, the chosen length is
  /// held here until the leader starts it - [endDate] can't be computed
  /// at create time anymore, since nobody knows yet which day Start gets
  /// pressed. Null for open-ended rooms and for pre-lobby-era rooms
  /// (whose endDate was computed at create and is already set).
  final int? lengthDays;

  /// The leader's chosen "go live" moment, set while still [isLobby] (see
  /// RoomsController.scheduleStart) - a precise clock time, unlike
  /// [startDate]'s always-midnight day granularity, so every member can
  /// watch a real ticking countdown to it (see RoomDetailScreen's
  /// _LobbyCard) instead of just knowing "sometime tomorrow." Null until
  /// the leader picks a time, and cleared the moment the room actually
  /// starts (see RoomsController's shared _beginChallenge) - once
  /// [isLobby] is false this is meaningless leftover state, not something
  /// any getter here should still read.
  final DateTime? scheduledStartAt;

  /// See [RoomCompeteMode]'s doc comment. Set once at creation, never
  /// changed after - defaults to [RoomCompeteMode.competitive] so every
  /// room created before this field existed keeps behaving exactly as it
  /// always did.
  final RoomCompeteMode competeMode;

  const RoomModel({
    required this.code,
    required this.name,
    required this.createdBy,
    required this.createdByName,
    required this.createdAt,
    required this.habitMode,
    this.sharedHabits = const [],
    required this.duration,
    required this.startDate,
    this.endDate,
    this.pausedSpans = const [],
    this.memberCount = 1,
    this.status = 'active',
    this.lengthDays,
    this.scheduledStartAt,
    this.competeMode = RoomCompeteMode.competitive,
  });

  bool get isLobby => status == 'lobby';

  /// True the instant a leader-picked [scheduledStartAt] actually arrives -
  /// the signal every device watching this room's countdown uses to fire
  /// RoomsController.autoStartIfDue, whichever of them happens to have the
  /// screen open first. Always false before a time's been picked.
  bool get scheduledStartDue =>
      scheduledStartAt != null && !DateTime.now().isBefore(scheduledStartAt!);

  /// Started, but the first counted day hasn't arrived yet — the "starts
  /// tomorrow morning" window between the leader pressing Start and the
  /// next app-day beginning. Everyone sees the countdown; nothing counts.
  bool get isCountingDown =>
      !isLobby && DateTime.now().effectiveDay.isBefore(startDate);

  /// The challenge is actually running: started, first day reached.
  bool get hasStarted =>
      !isLobby && !DateTime.now().effectiveDay.isBefore(startDate);

  /// Running right now — the 2x reward window (see
  /// roomBoostedHabitsProvider) and the "progress counts" window.
  bool get isLive => hasStarted && !isEnded;

  bool get isEnded {
    final end = endDate;
    return end != null && DateTime.now().effectiveDay.isAfter(end);
  }

  /// The last day progress counts toward this room - today, unless the room
  /// already ended (a room that ended 3 days ago shouldn't keep crediting
  /// completions logged after the fact).
  /// Tolerant of anything that isn't the shape we wrote — a malformed entry
  /// is dropped rather than failing the whole room's load, same posture as
  /// _remindersFrom on MatrixTask.
  static List<({String from, String to})> _pausedFrom(Object? raw) {
    if (raw is! List) return const [];
    final out = <({String from, String to})>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final from = e['from'];
      final to = e['to'];
      if (from is String && to is String && from.compareTo(to) <= 0) {
        out.add((from: from, to: to));
      }
    }
    out.sort((a, b) => a.from.compareTo(b.from));
    return List.unmodifiable(out);
  }

  DateTime get lastCountedDay {
    final today = DateTime.now().effectiveDay;
    final end = endDate;
    if (end == null) return today;
    return today.isAfter(end) ? end : today;
  }

  /// Days left including today, for a fixed-length room that hasn't ended
  /// yet - 0 once it has, and always 0 for an open-ended room (there's
  /// nothing to count down). What RoomsHubScreen's status pill and
  /// RoomDetailScreen's header both show.
  int get daysRemaining {
    final end = endDate;
    if (end == null) return 0;
    final today = DateTime.now().effectiveDay;
    if (today.isAfter(end)) return 0;
    return end.difference(today).inDays + 1;
  }

  /// Whole days the room has run so far, counting both [startDate] and the
  /// current (or final) day - the denominator behind every participant's
  /// percent. Never less than 1, even the instant a room is created.
  int get daysElapsed {
    final last = lastCountedDay;
    if (last.isBefore(startDate)) return 1;
    final span = last.difference(startDate).inDays + 1;
    if (pausedSpans.isEmpty) return span;
    // Paused days are excluded here for the same reason
    // RoomParticipant.daysElapsedIn excludes them: the room wasn't running.
    // These two MUST agree — the team card divides a pause-aware numerator
    // (teamDaysCompleted, built from daysCompleted) by this, so leaving it
    // as the raw calendar span made the team percentage contradict every
    // row underneath it: 88% per member above 47% for the team.
    var paused = 0;
    for (var d = startDate;
        !d.isAfter(last);
        d = d.add(const Duration(days: 1))) {
      if (isPausedOn(d.toDateKey())) paused++;
    }
    final live = span - paused;
    return live < 1 ? 1 : live;
  }

  factory RoomModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data()!;
    return RoomModel(
      code: doc.id,
      name: (d['name'] as String?) ?? '',
      createdBy: (d['createdBy'] as String?) ?? '',
      createdByName: (d['createdByName'] as String?) ?? '',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      habitMode: RoomHabitMode.fromJson(d['habitMode'] as String?),
      sharedHabits: (d['sharedHabits'] as List?)
              ?.whereType<Map>()
              .map(
                (m) => RoomHabitTemplate.fromMap(Map<String, dynamic>.from(m)),
              )
              .toList() ??
          const [],
      duration: RoomDuration.fromJson(d['duration'] as String?),
      startDate: (d['startDate'] as Timestamp?)?.toDate() ??
          DateTime.now().effectiveDay,
      endDate: (d['endDate'] as Timestamp?)?.toDate(),
      pausedSpans: _pausedFrom(d['pausedSpans']),
      memberCount: (d['memberCount'] as int?) ?? 1,
      // Pre-lobby-era rooms have no status field and were born active.
      status: (d['status'] as String?) ?? 'active',
      lengthDays: d['lengthDays'] as int?,
      scheduledStartAt: (d['scheduledStartAt'] as Timestamp?)?.toDate(),
      competeMode: RoomCompeteMode.fromJson(d['competeMode'] as String?),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'createdBy': createdBy,
        'createdByName': createdByName,
        'createdAt': Timestamp.fromDate(createdAt),
        'habitMode': habitMode.toJson(),
        if (sharedHabits.isNotEmpty)
          'sharedHabits': sharedHabits.map((h) => h.toFirestore()).toList(),
        'duration': duration.toJson(),
        'startDate': Timestamp.fromDate(startDate),
        if (endDate != null) 'endDate': Timestamp.fromDate(endDate!),
        if (pausedSpans.isNotEmpty)
          'pausedSpans': [
            for (final s in pausedSpans) {'from': s.from, 'to': s.to},
          ],
        'memberCount': memberCount,
        'status': status,
        if (lengthDays != null) 'lengthDays': lengthDays,
        if (scheduledStartAt != null)
          'scheduledStartAt': Timestamp.fromDate(scheduledStartAt!),
        'competeMode': competeMode.toJson(),
      };
}

/// Stored at: rooms/{code}/participants/{uid}
///
/// One doc per member, written only by that member's own device - the same
/// single-writer-per-doc rule every other notifier in the app follows.
/// Every other participant only ever reads this, never writes it. The
/// character fields are a denormalized snapshot so the leaderboard can
/// render real avatars without a second lookup per row; refreshed whenever
/// progress syncs.
class RoomParticipant {
  final String uid;
  final String displayName;
  final String characterId;
  final String? accessoryId;

  /// This participant's own PrestigeTier.id (see prestige_tier.dart) at the
  /// moment of their last sync — a leaderboard-only, cosmetic mirror of the
  /// same title chip the Profile hero header already shows, same
  /// "displayName/characterId/accessoryId" denormalization pattern (see
  /// RoomsController._profileFields), not a separate source of truth. Null
  /// for a participant doc written before this field existed, or for a
  /// signed-in account still on level 1/"Seeker" before the leaderboard row
  /// bothers rendering a chip at all — see _LeaderboardRow's own gate for
  /// why level 1 is deliberately excluded, mirroring the Profile card's
  /// identical "nothing to show off yet" restraint.
  final String? prestigeTierId;
  final DateTime joinedAt;

  /// This participant's own real habit(s) this room is tracking - always
  /// exactly 1 in 'own' mode; one per entry in the room's [RoomModel.
  /// sharedHabits] plan in 'shared' mode. Every id here is a real habit in
  /// this account's own Grid (see RoomsController.joinRoom), never a
  /// separate room-only concept, so completing it in Grid is what moves
  /// this room's leaderboard.
  final List<String> linkedHabitIds;
  final List<String> linkedHabitNames;

  /// When true, other participants' leaderboard rows for this person hide
  /// which specific habit(s) they linked - progress (%, heatmap, day count)
  /// still shows either way, this only affects the habit-name chips. Purely
  /// a display flag toggled from this participant's own device; see
  /// RoomsController.toggleHideDetails.
  final bool hideDetails;

  /// Effective-day date keys (see DateTimeGameExt.toDateKey) mapped to how
  /// many of [linkedHabitIds] this participant completed *that specific
  /// day* - the single source of truth for progress, recomputed from the
  /// participant's real daily habit history (`users/{uid}/daily/{date}`,
  /// the same records Grid reads) by RoomsController.
  /// syncLinkedHabitsProgress. Each linked habit is detected and counted
  /// independently rather than requiring all of them - see [creditFor] for
  /// how a day's count turns into partial (e.g. 1 of 2 -> 50%) or full
  /// credit. A date missing from this map is the same as 0 done that day.
  final Map<String, int> dailyDoneCount;

  /// Effective-day date keys mapped to how many of [linkedHabitIds] were
  /// actually *scheduled* (applicable) that specific day - the correct
  /// denominator for [creditFor]/[isFullyDone], since a habit with its own
  /// specific weekday schedule (see IslamicHabitTemplate.isScheduledFor)
  /// isn't something the participant failed to do on a day it was never
  /// supposed to happen at all. Recomputed alongside [dailyDoneCount] by
  /// RoomsController.syncLinkedHabitsProgress/syncTodayForHabit.
  ///
  /// Sparse on purpose, same as [dailyDoneCount]: a date key is only
  /// written when at least one linked habit was excused that day (i.e. the
  /// true count is *less* than [linkedHabitIds.length]) - see
  /// [scheduledCountFor] for the fallback that makes an absent key mean
  /// "everything was scheduled as normal."
  final Map<String, int> dailyScheduledCount;

  /// How many linked habits this participant deliberately stood down
  /// (تخطّي / [SquareState.skipped]) on a given day.
  ///
  /// ── A DISPLAY FIELD, AND ONLY A DISPLAY FIELD ─────────────────────────
  /// Nothing that produces a number a leaderboard sorts, renders or pays out
  /// on may read this. Not [creditFor], not [isFullyDone], not
  /// [scheduledCountFor], not the streak. It exists so a rest can stop being
  /// DRAWN as a miss, which is a different claim from a rest being scored as
  /// one, and the two must not be conflated by a later change. There is a
  /// test that fails if this field ever reaches the scoring code.
  ///
  /// The reason for the wall: a room is ranked. Subtracting a rested habit
  /// from the denominator would let a member paint تخطّي on the habits they
  /// did not do and watch a half-done day settle at full credit, invisibly,
  /// which is a dial rather than a mercy. What the app owes someone who
  /// rested is that it not call them a failure in public; it does not owe
  /// them the points.
  ///
  /// Sparse and remove-when-zero, exactly like its two siblings.
  final Map<String, int> dailyRestedCount;

  /// How many linked habits were marked جزئي ([SquareState.partial]) on a
  /// given day.
  ///
  /// UNLIKE [dailyRestedCount], this one DOES score: [creditFor] counts each
  /// partial as half a habit. Half the work is worth half the credit, and it
  /// was worth nothing here while the personal reports had already given it
  /// 0.5, so the same square meant two different things depending on which
  /// screen you were looking at.
  ///
  /// It cannot be gamed, which is why it may score where a rest may not:
  /// marking جزئي is always strictly worse than marking مكتمل, so nobody can
  /// improve a standing by reaching for it. A rest, by contrast, would have
  /// shrunk the denominator, which is a dial.
  ///
  /// Deliberately NOT read by [isFullyDone]. A half-finished day is not a
  /// finished day, so it moves the percentage and the bar without keeping a
  /// streak alive or lighting the "all done" state.
  ///
  /// Sparse and remove-when-zero, exactly like its siblings.
  final Map<String, int> dailyPartialCount;

  /// The first day this participant's rest concessions may apply from.
  ///
  /// Stamped once, to the day the concession code first runs for them, and
  /// never moved backward. That single field is what guarantees NO STANDING
  /// IN ANY RUNNING ROOM MOVES when this ships: every day already behind them
  /// is outside the window, so every stored percentage comes out identical on
  /// the first launch after the update, and the allowance starts earning from
  /// that day forward.
  ///
  /// It is deliberately NOT derived from [wasObservedOn]. That reads "at or
  /// before lastSyncedDay", which every day becomes the moment a sync runs, so
  /// gating on it would refuse every concession the feature was built to
  /// grant and the whole thing would quietly never fire.
  final String? restAllowanceFrom;

  /// Week-start date keys (Saturday, matching startOfDisplayWeek - the same
  /// week the Grid screen draws) whose flexible weekly-quota habits all
  /// actually REACHED their target. The one thing that lets a rest day count
  /// toward a streak (see [currentStreak]).
  ///
  /// A week still in progress is deliberately NOT in here, even though it
  /// could still make it. An earlier version did include pending weeks, and
  /// the result was a streak equal to however many days old the current week
  /// was, for a habit with nothing done in it at all - credit handed out in
  /// advance. The grace an open week gets is the chance to become credited,
  /// not credit before the fact.
  ///
  /// Deliberately phrased as "which weeks were fine" rather than "which days
  /// broke". An earlier version stored the break days, and that failed in the
  /// worst possible direction: a participant whose device hadn't synced yet
  /// had no break days recorded, which read as "nothing ever broke" and
  /// awarded them a full streak while their progress showed 0%. Missing data
  /// must never look like success. Phrased this way, an absent week simply
  /// isn't excused, so an unsynced participant gets a streak of 0 - which is
  /// the honest answer for someone we know nothing about yet.
  ///
  /// One entry per week rather than per day, so this stays small even for a
  /// long-running room.
  final List<String> quotaOkWeeks;

  /// habitId -> the cadence periods this room grades that habit by, oldest
  /// first (see [RoomHabitRule]). This is the room's own frozen copy of each
  /// linked habit's rules, and the reason editing a habit can no longer
  /// rewrite finished history.
  ///
  /// The problem it solves: syncLinkedHabitsProgress recomputes the room's
  /// whole day range from scratch every time, reading each habit's *current*
  /// frequency. So changing تمرين from 4x to 7x per week silently re-graded
  /// every past week at the new target - a month of perfect weeks could drop
  /// to 43% and take the streak with it, and the reverse (7x down to 1x)
  /// retroactively invented progress nobody earned. Nothing warned about it.
  ///
  /// What it deliberately does NOT freeze: the daily habit history itself.
  /// Ticking a past day's square in the Grid still flows through to the room
  /// on the next resync, exactly as before - that's a real thing the person
  /// really did, and back-filling a forgotten day is a feature people expect
  /// from a habit tracker. Only the *grading rule* is pinned, so history can
  /// be corrected but not re-scored under rules that didn't apply at the
  /// time.
  ///
  /// Empty for a participant doc last written before this existed, which
  /// syncLinkedHabitsProgress self-heals by seeding one period stamped from
  /// the room's start date using the habit's current settings - the best
  /// available answer, since a rule nobody ever recorded can't be recovered.
  /// A new period is only ever appended by an explicit user action (see
  /// RoomsController.relockHabitRules), never automatically on edit, since
  /// automatically following the edit is precisely the behaviour this
  /// replaces.
  final Map<String, List<RoomHabitRule>> habitRules;
  final DateTime lastUpdated;

  /// Whether *this* participant has already claimed this room's one-time
  /// Team mode bonus (see RoomCompeteMode.team/RoomTeamProgress.
  /// teamIsPerfect/RoomsController.claimTeamBonus) - written only by this
  /// participant's own device, same single-writer rule as every other field
  /// here, so one member claiming never touches another's. Meaningless (and
  /// always false) for a [RoomCompeteMode.competitive] room, which has
  /// nothing to claim.
  final bool teamBonusClaimed;

  /// Whether this participant has claimed their end-of-room podium prize —
  /// the [RoomCompeteMode.competitive] counterpart to [teamBonusClaimed].
  ///
  /// Finishing a competitive room used to pay nothing at all: a podium
  /// graphic and no XP, no gold, no medal, for a race that could run 90
  /// days. Top three now earn a real prize, scaled by place, claimed once.
  /// Same single-writer rule and same claim-once transaction as the team
  /// bonus (see RoomsController.claimPodiumBonus).
  final bool podiumBonusClaimed;

  /// Whether every actually-scheduled linked habit was done for [allDoneDate]
  /// the last time this doc was written - a plain mirror of
  /// `isFullyDone(allDoneDate)` at write time, kept as its own field (rather
  /// than derived fresh) purely so the room-finish Cloud Function
  /// (functions/index.js) can diff before/after on a Firestore trigger
  /// without reimplementing [isFullyDone]'s weekly-quota-aware logic in
  /// JavaScript. Every write from RoomsController.syncLinkedHabitsProgress
  /// keeps this in lockstep with the real per-day counts above it, so a
  /// false->true transition here means exactly what it means client-side:
  /// this participant just finished today, for the very first time today.
  final bool allDoneToday;

  /// The effective-day date key [allDoneToday] was computed for - lets a
  /// stale reader (or the function, defensively) recognize a flag that's
  /// left over from a day this device hasn't resynced since, rather than
  /// trusting a bare bool with no date attached to it.
  final String? allDoneDate;

  /// This participant's own choice to silence the room-finish push
  /// notification for this specific room - toggled from the room's own app
  /// bar (see RoomsController.setRoomMuted), single-writer just like every
  /// other per-participant flag here. Never affects the in-app, in-the-
  /// moment reactions in room_reactions.dart - those only ever show while
  /// this person is already looking at the room, which isn't the kind of
  /// interruption muting push is for.
  final bool notificationsMuted;

  /// The last effective-day date key on which a sync actually ran for this
  /// participant — the "the room was watching through here" watermark, and
  /// the thing that makes [RoomsController.syncLinkedHabitsProgress]'s
  /// anti-backdating clamp honest.
  ///
  /// The clamp exists so back-filling a forgotten square can't earn room
  /// credit after the fact, and it enforces that by capping a past day at
  /// whatever the room had already recorded for it. That is only a fair test
  /// when the room actually *saw* that day. It didn't, for every day this
  /// device spent closed, offline, or with a sync that silently failed (the
  /// per-tap push is fire-and-forget, see syncRoomToday) — and for those days
  /// "what the room recorded" is 0 purely because nobody was looking, not
  /// because nothing was done. Capping against that turned a day genuinely
  /// completed on time into a permanent zero, with no way back: the Grid kept
  /// showing the square green while the room insisted it never happened.
  ///
  /// With this recorded, the clamp can ask the question it always meant to
  /// ask — "was the room watching on the day in question?" — and only cap the
  /// days it actually observed. Anything later than this watermark is taken
  /// from the real daily history instead, which is the honest answer for a
  /// day nobody was there to see.
  ///
  /// Null for a participant doc written before this field existed. That
  /// deliberately reads as "watching through nowhere", so the next sync
  /// re-credits their whole window from their real Grid squares once, healing
  /// exactly the days the old clamp had wrongly zeroed, and then stamps the
  /// watermark so normal anti-backdating resumes from that point on.
  final String? lastSyncedDay;

  const RoomParticipant({
    required this.uid,
    required this.displayName,
    required this.characterId,
    this.accessoryId,
    this.prestigeTierId,
    required this.joinedAt,
    this.linkedHabitIds = const [],
    this.linkedHabitNames = const [],
    this.hideDetails = false,
    this.dailyDoneCount = const {},
    this.dailyScheduledCount = const {},
    this.dailyRestedCount = const {},
    this.dailyPartialCount = const {},
    this.restAllowanceFrom,
    this.quotaOkWeeks = const [],
    this.habitRules = const {},
    required this.lastUpdated,
    this.teamBonusClaimed = false,
    this.podiumBonusClaimed = false,
    this.allDoneToday = false,
    this.allDoneDate,
    this.notificationsMuted = false,
    this.lastSyncedDay,
  });

  /// Whether the room was already watching on [dateKey] — i.e. a sync ran on
  /// or after that day, so whatever it recorded for that day is a real
  /// observation rather than an absence of one. See [lastSyncedDay].
  bool wasObservedOn(String dateKey) {
    final through = lastSyncedDay;
    if (through == null) return false;
    return dateKey.compareTo(through) <= 0;
  }

  /// How many of [linkedHabitIds] actually counted toward [dateKey] - the
  /// real denominator for that day, not just linkedHabitIds.length. Falls
  /// back to linkedHabitIds.length when this day has no recorded value:
  /// either every linked habit really was scheduled that day (the sync
  /// only writes an entry when something was excused, to keep the doc
  /// small - see [dailyScheduledCount]'s doc comment), or this is a
  /// participant doc from before scheduling-awareness existed and simply
  /// hasn't resynced yet (same self-healing pattern as [dailyDoneCount]
  /// itself for a pre-existing field).
  /// [linkedHabitIds] minus any slot this participant skipped (see
  /// [kDeclinedSlot]) - the ids that actually count for or against them.
  /// Every "how many habits does this person have here" question should ask
  /// this rather than linkedHabitIds directly, which keeps skipped slots in
  /// place purely to hold their position in the shared plan.
  ///
  /// Allocates, so prefer [hasCountedHabits]/[countedHabitCount] for a plain
  /// emptiness or size check - those run inside per-day loops
  /// ([daysCompleted], [currentStreak]) where a throwaway list per day per
  /// participant adds up fast.
  List<String> get countedHabitIds =>
      linkedHabitIds.where((id) => id != kDeclinedSlot).toList();

  /// The counting ids that also survive [room]'s own plan edits - i.e. minus
  /// any slot whose shared-plan template the leader has withdrawn (see
  /// [RoomHabitTemplate.removedAt]). THE one place that decision lives:
  /// grading, the per-tap fast path, and the Grid's room-boost index all read
  /// this, so a skipped or withdrawn slot can never be counted by one of them
  /// and ignored by another. Identical to [countedHabitIds] for an
  /// 'own'-mode room, which has no shared templates to withdraw.
  List<String> countedHabitIdsIn(RoomModel room) {
    final shared = room.habitMode == RoomHabitMode.shared
        ? room.sharedHabits
        : const <RoomHabitTemplate>[];
    final out = <String>[];
    for (var i = 0; i < linkedHabitIds.length; i++) {
      if (linkedHabitIds[i] == kDeclinedSlot) continue;
      if (i < shared.length && shared[i].isRemoved) continue;
      out.add(linkedHabitIds[i]);
    }
    return out;
  }

  /// Whether anything counts here at all - the allocation-free counterpart to
  /// `countedHabitIds.isEmpty`.
  bool get hasCountedHabits {
    for (final id in linkedHabitIds) {
      if (id != kDeclinedSlot) return true;
    }
    return false;
  }

  /// How many slots count - the allocation-free counterpart to
  /// `countedHabitIds.length`.
  int get countedHabitCount {
    var n = 0;
    for (final id in linkedHabitIds) {
      if (id != kDeclinedSlot) n++;
    }
    return n;
  }

  /// The cadence rule this room grades [habitId] by on [dateKey] - the
  /// latest period that had already started by then (see [habitRules]).
  /// Falls back to the earliest recorded period for a day before any rule
  /// was stamped, and to null when this habit has no recorded rules at all,
  /// which syncLinkedHabitsProgress treats as "seed one from the habit's
  /// current settings."
  ///
  /// Date keys are YYYY-MM-DD, so a plain string comparison is already
  /// chronological - no parsing needed.
  RoomHabitRule? ruleFor(String habitId, String dateKey) {
    final rules = habitRules[habitId];
    if (rules == null || rules.isEmpty) return null;
    RoomHabitRule? best;
    RoomHabitRule? earliest;
    for (final r in rules) {
      if (earliest == null || r.from.compareTo(earliest.from) < 0) earliest = r;
      if (r.from.compareTo(dateKey) <= 0 &&
          (best == null || r.from.compareTo(best.from) > 0)) {
        best = r;
      }
    }
    return best ?? earliest;
  }

  /// Note the fallback can't know about a leader-withdrawn slot (that lives on
  /// the room, not here) - it doesn't need to, because the sync writes a real
  /// [dailyScheduledCount] entry whenever the true count differs from the
  /// plain total, and this fallback only ever applies to a day no sync has
  /// covered yet.
  int scheduledCountFor(String dateKey) =>
      dailyScheduledCount[dateKey] ?? countedHabitCount;

  /// How many habits were stood down on [dateKey]. Display only, see
  /// [dailyRestedCount].
  int restedCountFor(String dateKey) => dailyRestedCount[dateKey] ?? 0;

  /// How many habits were half done on [dateKey]. Scores, see
  /// [dailyPartialCount].
  int partialCountFor(String dateKey) => dailyPartialCount[dateKey] ?? 0;

  /// Whether [dateKey] should be DRAWN as a rest rather than a miss.
  ///
  /// Requires that nothing was done, so a mixed day (one habit done, one
  /// rested) still reads as the partial day it is rather than borrowing the
  /// calm of a full rest. Excludes a day that was structurally empty anyway
  /// ([isRestDay]), which already has its own treatment and is not a choice
  /// anybody made.
  bool isDeclaredRest(String dateKey) {
    if (!hasCountedHabits) return false;
    // A structurally empty day already has its own treatment and its own
    // full credit. Nothing was owed, which is the calendar's doing, not a
    // choice anybody made.
    if (isRestDay(dateKey)) return false;
    // Anything done at all makes this a partial day, and a partial day must
    // look like one.
    if ((dailyDoneCount[dateKey] ?? 0) != 0) return false;
    // EVERY scheduled habit, not merely one of them.
    //
    // Caught on device: with three linked habits, standing down a single one
    // and doing nothing else painted the whole day as a calm rest. That
    // overstates it. Two habits were plainly missed, and drawing the day as
    // a rest quietly forgives them in the one place other people are
    // looking. A rest is a day you decided not to train; a day you stood one
    // thing down and then let the rest slide is not that day.
    final scheduled = scheduledCountFor(dateKey);
    return scheduled > 0 && restedCountFor(dateKey) >= scheduled;
  }

  /// This participant's completion credit for [dateKey] - 0.0 to 1.0,
  /// proportional to how many of that day's actually-scheduled linked
  /// habits (see [scheduledCountFor]) were done (1 of 2 -> 0.5, 2 of 2 ->
  /// 1.0). A day where nothing was scheduled at all (every linked habit
  /// excused) is full credit, not zero - there was nothing to fall short
  /// of. 0 whenever nothing is linked yet, since there's nothing to divide
  /// by.
  ///
  /// Every linked habit is weighed the same here, including a flexible
  /// weekly-quota one ("4x a week, any days"): do it today and today is a
  /// whole done day, full colour, exactly like any other habit. The quota is
  /// NOT diluted across the week - a version of this briefly did that, and a
  /// day someone had genuinely completed showed as a fraction of a day, which
  /// is not what finishing a day looks like to the person who did it. The
  /// quota's real job is deciding whether a *week* keeps the streak alive,
  /// and that lives in [quotaOkWeeks]/[currentStreak], nowhere near this.
  double creditFor(String dateKey) {
    if (!hasCountedHabits) return 0;
    final scheduled = scheduledCountFor(dateKey);
    if (scheduled == 0) return 1.0;
    final done = dailyDoneCount[dateKey] ?? 0;
    // A جزئي habit is half a habit. The weight is 0.5 everywhere in this app
    // (SquareState.xpValue pays it 5 against complete's 10, the Grid's own
    // day ratio scores it 0.5, and the reports credit it 0.5), and Rooms was
    // the one surface still scoring it as nothing at all.
    //
    // Safe on a ranked surface because it is strictly dominated: marking
    // جزئي can only ever earn LESS than marking مكتمل, so it is never worth
    // reaching for. Compare dailyRestedCount, which must not score because
    // it would shrink the denominator instead of adding to the numerator.
    final credited = done + partialCountFor(dateKey) * 0.5;
    return (credited / scheduled).clamp(0.0, 1.0);
  }

  /// Whether [dateKey] asked nothing of this participant — a rest day a
  /// weekly quota entitled them to, or an off-day of a named-weekday habit.
  ///
  /// Scoring-wise such a day is finished, and [creditFor] rightly returns a
  /// full 1.0 for it. But it is NOT the same event as training, and anything
  /// that shows a day back to a person needs to tell the two apart: the
  /// leaderboard strip used to paint both in the same full emerald, so a
  /// 4x-a-week habit done exactly four times drew a solid week while the
  /// Grid — which only ever records what you actually did — showed four
  /// squares. Two screens, both correct, flatly contradicting each other.
  ///
  /// Deliberately separate from [creditFor] rather than folded into it:
  /// changing what an excused day scores would change the leaderboard, and
  /// the scoring was never the part that was wrong.
  bool isRestDay(String dateKey) =>
      hasCountedHabits && scheduledCountFor(dateKey) == 0;

  /// Whether *every actually-scheduled* linked habit was done on [dateKey]
  /// - the strict "full credit" case, used where a screen wants a plain
  /// done/not-done signal (e.g. the checkmark in Room Detail's "Your plan"
  /// card) rather than the underlying fraction. Trivially true on a day
  /// nothing was scheduled at all - see [creditFor]'s doc comment.
  ///
  /// Deliberately NOT what [currentStreak] asks - a rest day on a 4x-a-week
  /// habit is not a finished day, but it mustn't break a streak either. See
  /// [quotaOkWeeks].
  bool isFullyDone(String dateKey) {
    if (!hasCountedHabits) return false;
    final scheduled = scheduledCountFor(dateKey);
    if (scheduled == 0) return true;
    return (dailyDoneCount[dateKey] ?? 0) >= scheduled;
  }

  /// Whether this participant actually *did* something on [dateKey] — at
  /// least one linked habit genuinely completed, as opposed to a day that
  /// merely has nothing outstanding on it.
  ///
  /// [isFullyDone] deliberately answers true for a day where nothing was
  /// scheduled at all (a Mon/Wed habit's Tuesday, or a weekly quota's rest
  /// day once its target is met) — correct for "is anything owed today", and
  /// exactly what the plan card's checkmark wants. It is the wrong question
  /// for anything that announces a person to their teammates, though:
  /// "Aziz finished their habits today" on a day Aziz rested is a claim
  /// about a thing that didn't happen. Celebrations and pushes ask this
  /// instead.
  bool didCompleteAnythingOn(String dateKey) =>
      (dailyDoneCount[dateKey] ?? 0) > 0;

  /// Total credited days within [room]'s active window (start date through
  /// today, or the room's end date once it's passed) - a fractional sum,
  /// not a plain count: a day with 1 of 2 linked habits done contributes
  /// 0.5, not 0 or 1 (see [creditFor]). A date logged before the room
  /// started, or after it ended, never counts.
  /// The first day of [room] this participant is actually answerable for:
  /// the room's own start, or the day they joined, whichever is later.
  ///
  /// A late joiner used to be scored on the room's whole window. Join a
  /// 90-day room on day 80 and their real Grid history was credited all the
  /// way back to day 1 — someone who had never heard of the room could join
  /// on the final week and land straight at the top of a leaderboard other
  /// people had spent three months climbing. Scoring starts when they did.
  ///
  /// The denominator moves with it (see [daysElapsedIn]), so joining late is
  /// not a penalty either: they're measured on the days they were in the
  /// room, which is what "I joined this challenge" means to a person.
  DateTime countedStartIn(RoomModel room) {
    final joined = DateTime(joinedAt.year, joinedAt.month, joinedAt.day);
    return joined.isAfter(room.startDate) ? joined : room.startDate;
  }

  /// Days this participant has actually been in [room], counting both ends —
  /// the per-person counterpart to [RoomModel.daysElapsed], and the correct
  /// denominator for [progressRatio]. Never less than 1, even on the day
  /// someone joins.
  int daysElapsedIn(RoomModel room) {
    final start = countedStartIn(room);
    final last = room.lastCountedDay;
    if (last.isBefore(start)) return 1;
    final span = last.difference(start).inDays + 1;
    final conceded = concededDaysIn(room);
    // The early return is conditional on BOTH exemptions being empty now.
    // It used to check only pausedSpans, which would have skipped the rest
    // allowance entirely in the common case of a room that was never paused,
    // and the feature would have silently done nothing for almost everybody.
    if (room.pausedSpans.isEmpty && conceded.isEmpty) return span;
    // Paused days are not elapsed — the room wasn't running, so they were
    // never anyone's to keep. Counted by walking rather than by subtracting
    // span lengths, so a span that only partly overlaps this participant's
    // own window (a late joiner) is handled without special-casing.
    //
    // Conceded days leave the same way, and only ever days that scored zero
    // (see [concededDaysIn]), so this can lift a percentage but never invent
    // completion that did not happen.
    var excused = 0;
    for (var d = start; !d.isAfter(last); d = d.add(const Duration(days: 1))) {
      final key = d.toDateKey();
      if (room.isPausedOn(key) || conceded.contains(key)) excused++;
    }
    final live = span - excused;
    return live < 1 ? 1 : live;
  }

  /// How many rest days a week a room excuses. One.
  ///
  /// The smallest bound that makes the app's own position true without
  /// turning the leaderboard into a contest about who rests best. It caps the
  /// mercy ceiling at seven sixths: someone who genuinely does six of seven
  /// days reads 100% instead of 86%, and no arrangement of rests can beat
  /// "your best six of seven". Two a week would make it best five of seven,
  /// at which point resting starts to be the strategy.
  ///
  /// Fixed for every room on purpose. A per-room setting would mean the rule
  /// is not one rule, so the one sentence that explains it becomes "it
  /// depends which room you are in".
  static const int kRestConcessionsPerWeek = 1;

  /// Days excused by the weekly rest allowance, as dateKeys.
  ///
  /// A day qualifies only when EVERY scheduled habit was stood down and
  /// nothing at all was done ([isDeclaredRest], which by construction means
  /// [creditFor] is exactly 0). That single condition is what makes this safe
  /// on a ranked surface:
  ///
  ///  - A concession can never RAISE a day's credit. It can only remove a day
  ///    that already scored zero, which is arithmetically identical to
  ///    crediting that day at your own trailing rate. Somebody sitting at 0%
  ///    gains precisely nothing by resting.
  ///  - A MIXED day is untouched. Standing down the one habit you did not do
  ///    changes nothing, so there is no dial on a partial day.
  ///
  /// Earliest-first allocation within a week is therefore a display decision
  /// rather than a scoring one: every candidate day is worth zero, so which
  /// one the allowance lands on cannot change anybody's number.
  Set<String> concededDaysIn(RoomModel room) {
    final from = restAllowanceFrom;
    if (from == null) return const {};
    final out = <String>{};
    final usedPerWeek = <String, int>{};
    var day = countedStartIn(room);
    final last = room.lastCountedDay;
    while (!day.isAfter(last)) {
      final key = day.toDateKey();
      // Before the stamp, nothing is excused. This is the whole of the
      // no-standing-moves guarantee.
      if (key.compareTo(from) >= 0 &&
          !room.isPausedOn(key) &&
          isDeclaredRest(key)) {
        final week = day.startOfDisplayWeek.toDateKey();
        final used = usedPerWeek[week] ?? 0;
        if (used < kRestConcessionsPerWeek) {
          usedPerWeek[week] = used + 1;
          out.add(key);
        }
      }
      day = day.add(const Duration(days: 1));
    }
    return out;
  }

  double daysCompleted(RoomModel room) {
    var total = 0.0;
    var day = countedStartIn(room);
    final last = room.lastCountedDay;
    while (!day.isAfter(last)) {
      final key = day.toDateKey();
      // Skipped on both sides, matching daysElapsedIn — a paused day adds
      // nothing to the numerator and nothing to the denominator, so an
      // extension leaves every existing percentage exactly where it was.
      if (!room.isPausedOn(key)) total += creditFor(key);
      day = day.add(const Duration(days: 1));
    }
    return total;
  }

  /// 0.0-1.0 completion ratio for [room] - the number every leaderboard row
  /// sorts and renders by.
  double progressRatio(RoomModel room) {
    // Their own window, not the room's — see [countedStartIn].
    final elapsed = daysElapsedIn(room);
    if (elapsed <= 0) return 0;
    return (daysCompleted(room) / elapsed).clamp(0.0, 1.0);
  }

  /// Consecutive unbroken days counting backward from "now", for the
  /// leaderboard's streak badge. Never looks earlier than [RoomModel.
  /// startDate], and is always 0 before anything is linked.
  ///
  /// A day keeps a streak if it was genuinely finished, OR if it sits inside a
  /// week whose weekly quota was satisfied (see [quotaOkWeeks]) - that second
  /// clause IS the flexible-quota rule, and the only reason a rest day can
  /// count. For an ordinary daily habit only the first clause ever applies, so
  /// nothing changes for it.
  ///
  /// Both inputs fail safe: [isFullyDone] reads stored counts (absent = not
  /// done) and [quotaOkWeeks] is an explicit allow-list (absent = not
  /// excused). So a participant whose device hasn't synced scores 0, never a
  /// phantom streak.
  bool _keepsStreak(String dateKey, DateTime day) {
    if (isFullyDone(dateKey)) return true;
    return quotaOkWeeks.contains(day.startOfDisplayWeek.toDateKey());
  }

  /// Consecutive streak-keeping days counting backward from "now" (see
  /// [_keepsStreak]), for the leaderboard's streak badge. Never looks earlier
  /// than [RoomModel.startDate], and is always 0 before anything is linked.
  ///
  /// While the room is still running, an unfinished *today* doesn't zero this
  /// out - there's still time left, so this looks at whether yesterday keeps
  /// the streak alive instead of declaring it broken mid-day. Once the room
  /// has ended, its last countable day is final: if that day didn't hold, the
  /// streak the room ended on is 0, same as any habit streak that lapses.
  int currentStreak(RoomModel room) {
    if (!hasCountedHabits) return 0;
    var day = room.lastCountedDay;
    if (!room.isEnded && !_keepsStreak(day.toDateKey(), day)) {
      day = day.subtract(const Duration(days: 1));
    }
    var count = 0;
    // Floors at the day THEY joined, not the room's start — a streak can't
    // run back through days they weren't here for. See [countedStartIn].
    final floor = countedStartIn(room);
    while (!day.isBefore(floor) && _keepsStreak(day.toDateKey(), day)) {
      count++;
      day = day.subtract(const Duration(days: 1));
    }
    return count;
  }

  factory RoomParticipant.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data()!;
    return RoomParticipant(
      uid: doc.id,
      displayName: (d['displayName'] as String?) ?? '',
      // Empty, NOT a real character id, when the field is absent.
      //
      // This used to default to 'male_ghutra_blue' — which is male1, an
      // actual character somebody may have genuinely picked. A participant
      // doc written before this field existed, or by a partial write, was
      // therefore laundered into looking like a specific person's chosen
      // avatar, with nothing downstream able to tell the difference. Two
      // members could render identically, and a row could show a face that
      // wasn't theirs. Keeping "unknown" as unknown lets the leaderboard
      // draw a neutral placeholder instead — see CharacterCatalog.findById.
      characterId: (d['characterId'] as String?) ?? '',
      accessoryId: d['accessoryId'] as String?,
      prestigeTierId: d['prestigeTierId'] as String?,
      joinedAt: (d['joinedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      linkedHabitIds:
          (d['linkedHabitIds'] as List?)?.whereType<String>().toList() ??
              const [],
      linkedHabitNames:
          (d['linkedHabitNames'] as List?)?.whereType<String>().toList() ??
              const [],
      hideDetails: d['hideDetails'] as bool? ?? false,
      // A doc written before this field existed just has no per-day counts
      // yet - RoomsController.syncLinkedHabitsProgress (already run
      // automatically on every Room Detail open, see _syncIfNeeded) rebuilds
      // this from real Grid history within moments, same as any other
      // self-healing recompute in this app.
      dailyRestedCount: (d['dailyRestedCount'] as Map?)?.map(
            (k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0),
          ) ??
          const <String, int>{},
      dailyPartialCount: (d['dailyPartialCount'] as Map?)?.map(
            (k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0),
          ) ??
          const <String, int>{},
      restAllowanceFrom: d['restAllowanceFrom'] as String?,
      dailyDoneCount: (d['dailyDoneCount'] as Map?)?.map(
            (k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0),
          ) ??
          const {},
      // Same self-healing story as dailyDoneCount above - a doc from before
      // scheduling-awareness existed just has no entries yet, and
      // scheduledCountFor's fallback already treats that exactly like "every
      // linked habit was scheduled as normal" until the next resync.
      dailyScheduledCount: (d['dailyScheduledCount'] as Map?)?.map(
            (k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0),
          ) ??
          const {},
      // Absent for any doc written before this existed, which reads as "no
      // day ever broke a streak" - the next syncLinkedHabitsProgress pass
      // recomputes the real set. See quotaOkWeeks' own doc comment - absent
      // deliberately means "no week is excused", never "every week held".
      quotaOkWeeks:
          (d['quotaOkWeeks'] as List?)?.whereType<String>().toList() ??
              const [],
      habitRules: (d['habitRules'] as Map?)?.map(
            (k, v) => MapEntry(
              k.toString(),
              (v as List?)
                      ?.whereType<Map>()
                      .map(
                        (m) =>
                            RoomHabitRule.fromMap(Map<String, dynamic>.from(m)),
                      )
                      .where((r) => r.from.isNotEmpty)
                      .toList() ??
                  const <RoomHabitRule>[],
            ),
          ) ??
          const {},
      lastUpdated: (d['lastUpdated'] as Timestamp?)?.toDate() ?? DateTime.now(),
      teamBonusClaimed: d['teamBonusClaimed'] as bool? ?? false,
      podiumBonusClaimed: d['podiumBonusClaimed'] as bool? ?? false,
      // Both self-heal the same way as every other field added after this
      // model shipped: a doc from before this existed just reads as "not
      // done yet," and the next syncLinkedHabitsProgress pass (room-open,
      // habit-link, etc.) writes a real value.
      allDoneToday: d['allDoneToday'] as bool? ?? false,
      allDoneDate: d['allDoneDate'] as String?,
      notificationsMuted: d['notificationsMuted'] as bool? ?? false,
      // Absent for a doc written before the watermark existed, and null is
      // exactly the right reading of that: the room can't claim to have been
      // watching on any day it kept no record of watching. See
      // [lastSyncedDay] for why that makes the next sync re-credit real Grid
      // history once instead of trusting the old clamp's zeros.
      lastSyncedDay: d['lastSyncedDay'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'uid': uid,
        'displayName': displayName,
        // Omitted when unknown rather than writing an empty string back —
        // the next profile sync (_profileFields) fills in the real value.
        if (characterId.isNotEmpty) 'characterId': characterId,
        if (accessoryId != null) 'accessoryId': accessoryId,
        if (prestigeTierId != null) 'prestigeTierId': prestigeTierId,
        'joinedAt': Timestamp.fromDate(joinedAt),
        'linkedHabitIds': linkedHabitIds,
        'linkedHabitNames': linkedHabitNames,
        'hideDetails': hideDetails,
        'dailyDoneCount': dailyDoneCount,
        'dailyRestedCount': dailyRestedCount,
        'dailyPartialCount': dailyPartialCount,
        if (restAllowanceFrom != null) 'restAllowanceFrom': restAllowanceFrom,
        'dailyScheduledCount': dailyScheduledCount,
        'quotaOkWeeks': quotaOkWeeks,
        'habitRules': habitRules.map(
          (k, v) => MapEntry(k, v.map((r) => r.toFirestore()).toList()),
        ),
        'lastUpdated': Timestamp.fromDate(lastUpdated),
        'teamBonusClaimed': teamBonusClaimed,
        'podiumBonusClaimed': podiumBonusClaimed,
        'allDoneToday': allDoneToday,
        if (allDoneDate != null) 'allDoneDate': allDoneDate,
        'notificationsMuted': notificationsMuted,
        if (lastSyncedDay != null) 'lastSyncedDay': lastSyncedDay,
      };

  RoomParticipant copyWith({
    String? characterId,
    String? accessoryId,
    bool clearAccessory = false,
    String? prestigeTierId,
    List<String>? linkedHabitIds,
    List<String>? linkedHabitNames,
    bool? hideDetails,
    Map<String, int>? dailyDoneCount,
    Map<String, int>? dailyRestedCount,
    Map<String, int>? dailyPartialCount,
    String? restAllowanceFrom,
    Map<String, int>? dailyScheduledCount,
    List<String>? quotaOkWeeks,
    Map<String, List<RoomHabitRule>>? habitRules,
    DateTime? lastUpdated,
    bool? teamBonusClaimed,
    bool? podiumBonusClaimed,
    bool? allDoneToday,
    String? allDoneDate,
    bool? notificationsMuted,
    String? lastSyncedDay,
  }) =>
      RoomParticipant(
        uid: uid,
        displayName: displayName,
        characterId: characterId ?? this.characterId,
        accessoryId: clearAccessory ? null : (accessoryId ?? this.accessoryId),
        prestigeTierId: prestigeTierId ?? this.prestigeTierId,
        joinedAt: joinedAt,
        linkedHabitIds: linkedHabitIds ?? this.linkedHabitIds,
        linkedHabitNames: linkedHabitNames ?? this.linkedHabitNames,
        hideDetails: hideDetails ?? this.hideDetails,
        dailyDoneCount: dailyDoneCount ?? this.dailyDoneCount,
        dailyScheduledCount: dailyScheduledCount ?? this.dailyScheduledCount,
        dailyRestedCount: dailyRestedCount ?? this.dailyRestedCount,
        dailyPartialCount: dailyPartialCount ?? this.dailyPartialCount,
        restAllowanceFrom: restAllowanceFrom ?? this.restAllowanceFrom,
        quotaOkWeeks: quotaOkWeeks ?? this.quotaOkWeeks,
        habitRules: habitRules ?? this.habitRules,
        lastUpdated: lastUpdated ?? this.lastUpdated,
        teamBonusClaimed: teamBonusClaimed ?? this.teamBonusClaimed,
        podiumBonusClaimed: podiumBonusClaimed ?? this.podiumBonusClaimed,
        allDoneToday: allDoneToday ?? this.allDoneToday,
        allDoneDate: allDoneDate ?? this.allDoneDate,
        notificationsMuted: notificationsMuted ?? this.notificationsMuted,
        lastSyncedDay: lastSyncedDay ?? this.lastSyncedDay,
      );
}

/// Room-wide "everyone together" numbers — layered on top of the existing
/// per-participant leaderboard rather than replacing it. Nothing here needs
/// its own sync/storage: every input ([RoomParticipant.daysCompleted]/
/// [RoomParticipant.isFullyDone]) is already computed from data each
/// participant's own device already syncs for the leaderboard, so this is
/// pure aggregation over whatever [roomParticipantsProvider] already
/// streamed in. Kept as extension methods (not fields on RoomModel itself)
/// since a room doc alone doesn't carry its participants - both need the
/// same list the leaderboard sorts.
extension RoomTeamProgress on RoomModel {
  /// 0.0-1.0 - total credited days across every participant, out of the
  /// "everyone did every single day" ceiling (memberCount × daysElapsed).
  /// This is the number the team card's progress bar fills to: a room
  /// where everyone's been perfect reads 100%, same as any one person's own
  /// [RoomParticipant.progressRatio] would.
  double teamProgressRatio(List<RoomParticipant> participants) {
    if (participants.isEmpty) return 0;
    final maxPossible = participants.length * daysElapsed;
    if (maxPossible <= 0) return 0;
    final total =
        participants.fold<double>(0, (sum, p) => sum + p.daysCompleted(this));
    return (total / maxPossible).clamp(0.0, 1.0);
  }

  /// Raw "days completed together" — the numerator behind
  /// [teamProgressRatio], surfaced separately so the card can show real
  /// numbers ("14 of 20") alongside the percentage rather than just the
  /// bar. Rounded for display; the bar itself still fills from the exact
  /// fraction.
  int teamDaysCompleted(List<RoomParticipant> participants) => participants
      .fold<double>(0, (sum, p) => sum + p.daysCompleted(this))
      .round();

  int teamMaxPossibleDays(List<RoomParticipant> participants) =>
      participants.length * daysElapsed;

  /// True the moment *every* participant has fully credited today — the
  /// one binary "did the whole team show up" signal, distinct from the
  /// gradual [teamProgressRatio]. Requires at least one participant to have
  /// linked something; an empty room is never "complete."
  bool teamCompletedToday(List<RoomParticipant> participants) {
    if (participants.isEmpty) return false;
    final today = lastCountedDay.toDateKey();
    return participants.every((p) => p.isFullyDone(today));
  }

  /// True once the team has never missed a single credited day - every
  /// participant, every day, since [RoomModel.startDate]. The strict
  /// "everyone, every day" bar [RoomCompeteMode.team]'s bonus asks for
  /// (see RoomsController.claimTeamBonus), deliberately harder than
  /// [teamCompletedToday] (which only ever looks at today): one partial day
  /// anywhere in the room's history rules this out for good, same as any
  /// perfect streak would. Because [creditFor] only ever contributes exact
  /// 1.0s once every credited day is full, summing them never drifts below
  /// exactly 1.0 the way partial credit could - no epsilon needed.
  bool teamIsPerfect(List<RoomParticipant> participants) {
    if (participants.isEmpty) return false;
    return teamProgressRatio(participants) >= 1.0;
  }
}

/// A short, human-typeable room code - 6 characters from an alphabet that
/// drops visually-ambiguous characters (0/O, 1/I) so it's easy to read back
/// off a phone screen or relay over a call. Collision odds are astronomically
/// low (32^6 ≈ 1 billion combinations); RoomsController still checks before
/// writing (see its doc comment) - this is just the generator.
String generateRoomCode() {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final rand = Random();
  return List.generate(6, (_) => alphabet[rand.nextInt(alphabet.length)])
      .join();
}

/// Arabic-Indic digits (٠-٩) mapped to plain ASCII '0'-'9' - some devices
/// switch the numeric keypad to these when the system/app is in Arabic,
/// and [int.tryParse] only ever understands ASCII digits. Every character
/// that isn't one of these ten is passed through unchanged, so this is safe
/// to run on input that's already plain ASCII (the common case) as a no-op.
String _normalizeDigits(String input) => toWesternDigits(input);

/// Parses and bounds-checks a leader-typed custom room length in days - the
/// one function both CreateRoomSheet's and the Extend sheet's "Custom"
/// duration chip funnel their TextField through (see each sheet's own
/// duration section), so a day count means the same thing and is bounded
/// the same way no matter which of the two screens it was typed into.
///
/// Returns null for anything that isn't a whole, positive day count within
/// [minDays]..[maxDays] inclusive - empty/whitespace-only input, a decimal,
/// a unit suffix ("45 days"), zero, a negative number, or a number over the
/// cap - so every caller can treat "invalid" as one single case (disable
/// submit / show an inline error) instead of re-deriving its own notion of
/// what counts as a valid custom duration.
///
/// [maxDays] defaults to 365 (a full year) - generous enough for any real
/// challenge (the longest preset, 90, is well inside it) without letting a
/// stray extra digit (typing "3650" instead of "365") silently create a
/// decade-long room. [minDays] defaults to 1: a room lasting less than a
/// day isn't a fixed-length challenge, it's a same-day one, which is what
/// [RoomDuration.open] is already for.
int? parseCustomRoomDurationDays(
  String raw, {
  int minDays = 1,
  int maxDays = 365,
}) {
  final trimmed = _normalizeDigits(raw).trim();
  if (trimmed.isEmpty) return null;
  final parsed = int.tryParse(trimmed);
  if (parsed == null) return null;
  if (parsed < minDays || parsed > maxDays) return null;
  return parsed;
}
