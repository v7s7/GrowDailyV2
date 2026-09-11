import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/extensions/datetime_ext.dart';
import '../../../core/utils/western_digits.dart';
import '../../habits/models/habit_model.dart';
import '../../habits/models/weekly_quota_plan.dart';

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

  /// Days a member has to link a slot the leader added before it starts
  /// counting against them unlinked (see [slotAsksFromKey]). Aziz, 2026-09-09:
  /// "if all accept no need to wait", and none of them do wait, since a slot
  /// counts for a member from the day THEY link it (RoomHabitRule.from). This
  /// only ever governs the member who has not linked it yet: three days with
  /// a banner and a push before the room's plan is held against them.
  static const int kNewSlotGraceDays = 3;

  /// The share of the room's elapsed days a member must have been PRESENT
  /// for before they can hold a place (see RoomLeaderboard.holdsPlaceIn).
  /// Their score is still computed and shown; only the rank, the cup and the
  /// podium prize wait for tenure. The minimum-games-played rule every real
  /// league has, and the one this board was missing: a member who joined on
  /// the FINAL day and finished it read 100% and outranked 29 perfect days
  /// of 30, cup and 200 XP included (measured 2026-09-09). The team bonus
  /// already refused that exact move (teamIsPerfect's tenure clause); the
  /// competitive board and the podium never did.
  ///
  /// Half, so that on any day a member in for most of the room is placed and
  /// someone who joined in its second half has to finish it to hold a place.
  /// Never less than one day, so day one of a room places everyone.
  static const double kPlaceTenureFraction = 0.5;

  /// The most days tenure can ever demand. An open-ended room has no end, so
  /// half of it would grow without bound and somebody joining in its fourth
  /// month would wait two more before the board placed them. Two weeks is
  /// more than any sniper will sit out and less than any genuine joiner
  /// minds; a fixed room shorter than a month never reaches it.
  static const int kPlaceTenureCapDays = 14;

  /// The first day slot [i] was part of the plan at all - the room's own
  /// start for everything it was created with, the addition day for a slot
  /// the leader added later. Never before [startDate].
  String slotJoinedPlanKey(int i) {
    final startKey = startDate.toDateKey();
    if (i < 0 || i >= sharedHabits.length) return startKey;
    final added = sharedHabits[i].addedAt;
    if (added == null) return startKey;
    final key = DateTime(added.year, added.month, added.day).toDateKey();
    return key.compareTo(startKey) > 0 ? key : startKey;
  }

  /// The first day slot [i] is held against a member who has NOT linked it:
  /// [slotJoinedPlanKey] plus [kNewSlotGraceDays] for a late addition, the
  /// room's own start for an original slot (everyone linked those on joining
  /// or declined them on purpose, so there is nothing to wait for).
  String slotAsksFromKey(int i) {
    final startKey = startDate.toDateKey();
    if (i < 0 || i >= sharedHabits.length) return startKey;
    final added = sharedHabits[i].addedAt;
    if (added == null) return startKey;
    final asks = DateTime(added.year, added.month, added.day + kNewSlotGraceDays)
        .toDateKey();
    return asks.compareTo(startKey) > 0 ? asks : startKey;
  }

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

  bool get isEnded => isEndedAt(DateTime.now());

  /// [isEnded] against an explicit clock, like [lastCountedDayAt], so a
  /// surface that switches on the end (RoomLeaderboard.scoringRoster) can be
  /// tested at a chosen moment.
  bool isEndedAt(DateTime now) {
    final end = endDate;
    return end != null && now.effectiveDay.isAfter(end);
  }

  /// The last day progress counts toward this room - today, unless the room
  /// already ended (a room that ended 3 days ago shouldn't keep crediting
  /// completions logged after the fact).
  /// Tolerant of anything that isn't the shape we wrote — a malformed entry
  /// is dropped rather than failing the whole room's load, same posture as
  /// _remindersFrom on MatrixTask.
  static List<({String from, String to})> _pausedFrom(Object? raw) =>
      spansFrom(raw);

  /// The `[{from, to}]` date-key span shape [pausedSpans] and
  /// RoomParticipant.awaySpans share, parsed with the same tolerance.
  static List<({String from, String to})> spansFrom(Object? raw) {
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

  DateTime get lastCountedDay => lastCountedDayAt(DateTime.now());

  /// [lastCountedDay] against an explicit clock, so a rule that depends on
  /// both the room's end AND the hour (see
  /// [RoomParticipant.quotaWeekIsLost]) can be tested at a chosen moment
  /// rather than only at whatever time the suite happens to run.
  DateTime lastCountedDayAt(DateTime now) {
    final today = now.effectiveDay;
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
  /// RoomsController._profileFields), not a separate source of truth.
  ///
  /// Written unconditionally, at every tier including the base level-1
  /// "Seeker", and rendered at every tier too. (It was once written for
  /// everyone but DISPLAYED only above level 1, on the reasoning that a
  /// badge everyone starts with says nothing; in a room that reads as a
  /// broken row rather than as restraint. See _LeaderboardRow.)
  ///
  /// So null means exactly one thing now: a participant doc written before
  /// this field existed, which self-heals on that member's next sync.
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

  /// Date keys on which this member's whole commitment was STOOD DOWN — every
  /// counted habit paused, so there was nothing left for the room to grade.
  ///
  /// The per-member counterpart to [RoomModel.pausedSpans], and it exists for
  /// the same reason that field does: a day nobody was asked for anything is
  /// neither earned nor missed, and forcing it to be one of the two is wrong
  /// in whichever direction you pick.
  ///
  /// ── What this replaced ──────────────────────────────────────────────────
  /// Pausing every linked habit used to put each one back in the denominator
  /// as scheduled-and-never-done. The arithmetic was forward-only (days before
  /// the pause kept their grade), but the effect was not proportionate:
  /// measured on room A8GEL7, a member doing 4x a week faithfully and pausing
  /// on 2 Aug went from 93% to 13% with a streak of 26 down to 0, and their
  /// strip filled with red crosses for a month of days they had never been
  /// asked about. Standing a habit down was strictly worse than quietly doing
  /// nothing, which is the opposite of what pausing promises.
  ///
  /// ── Why it is not simply "no habits scheduled" ──────────────────────────
  /// Because that already means something else here. [scheduledCountFor] == 0
  /// is a REST day, and [creditFor] pays a rest day a full 1.0 while
  /// [isFullyDone] calls it finished. Dropping paused days through that route
  /// would score them as completed days — the exact "users will pause to fake
  /// a done day" hole. So this is a fourth day state, not a reuse of the third:
  /// [creditFor] returns 0 for it, [isFullyDone] and [isRestDay] are false, and
  /// [daysCompleted]/[daysElapsedIn] both skip it, so the ratio cannot move in
  /// either direction while the habit is away.
  ///
  /// Absent for every doc written before this existed, which reads as "nothing
  /// was ever stood down" — so no running room's stored percentage moves on the
  /// first launch after this ships. The next sync fills it in from real habit
  /// history, same self-healing recompute as [quotaOkWeeks].
  final List<String> standDownDays;

  /// Whether [dateKey] is one of this member's [standDownDays].
  ///
  /// A plain list scan, matching [quotaOkWeeks]. The list is bounded by the
  /// resync window ([kRoomSyncWindowDays]) plus whatever older stand-down days
  /// were already recorded, so it stays small enough that a set would buy
  /// nothing a const constructor can hold.
  bool isStoodDownOn(String dateKey) => standDownDays.contains(dateKey);

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

  /// Team-day milestones this account has already been paid for (7, 14,
  /// 30: see RoomTeamProgress.teamMilestones), written only by this account
  /// through RoomsController.claimTeamStreakBonus's claim-once transaction.
  /// A list rather than three flags so a fourth milestone is a data change,
  /// not a schema one.
  final List<int> teamStreakClaims;

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

  /// The instant the last FULL resync ran for this participant, stamped by
  /// RoomsController.syncLinkedHabitsProgress and nothing else. This is what
  /// [wasObservedOn] reads first: a day counts as observed only once a
  /// resync ran AFTER the day closed (kDayCutoffHour the next morning),
  /// because until then a completion can still legitimately arrive for it,
  /// paid in full by the Grid. [lastSyncedDay] alone could not say that: a
  /// sync at 09:00 stamps the same day as one at 23:00, and treating either
  /// as "observed" froze every grace-tail mark at the zero a midnight sync
  /// had seen (Aziz's own الوتر on 2026-09-06, traced 2026-09-07). Null for
  /// a doc written before this field existed; see [wasObservedOn] for the
  /// fallback.
  final DateTime? lastSyncedAt;

  /// Due counts inferred at read time for days this member's own phone has
  /// not regraded yet (see [closedQuotaWeekInference]).
  ///
  /// Never read from or written to Firestore: [RoomParticipant.fromFirestore]
  /// leaves it empty, and that is the only way syncLinkedHabitsProgress ever
  /// builds a participant, so nothing the sync compares or writes can see
  /// it. Filled only by [withClosedQuotaWeeksInferred], for the board, and
  /// dropped again by [asRecorded] for anything that pays.
  /// [scheduledCountFor] prefers it; [recordedScheduledCountFor] ignores it.
  final Map<String, int> inferredScheduledCount;

  /// When this member left the room - null while they are in it.
  ///
  /// A SOFT departure, deliberately, and it is the whole fix for the reset
  /// exploit. RoomsController.leaveRoom used to delete this document
  /// outright, and a rejoin then took the fresh-join path and stamped a new
  /// [joinedAt]: every bad day gone, measured from that moment, first place
  /// for a third of the work. Measured on 2026-09-09: 27% -> leave -> rejoin
  /// -> 100% and rank 1 over a day-one member at 80%. The doc comment that
  /// called losing your history "the cost of leaving" had it backwards on a
  /// ranked board, where bad history is exactly what a person wants to lose.
  ///
  /// The team bonus had already been given a tenure guard for this exact
  /// mechanic (see [RoomModel.teamIsPerfect]); the competitive board and the
  /// podium payout never were. Keeping the record is what gives them one:
  /// [joinedAt] stays the FIRST join, the finished and missed days stay, the
  /// frozen [habitRules] stay (a rejoin used to re-seed them from the habit's
  /// current settings, quietly undoing relockHabitRules' forward-only
  /// promise), and the days away become [awaySpans].
  ///
  /// Same shape as RoomHabitTemplate.removedAt for a withdrawn slot: stamp,
  /// do not delete, and let every reader skip it. A departed member is
  /// filtered out of the roster by roomParticipantsProvider and never drawn
  /// on the board; their document simply waits.
  final DateTime? leftAt;

  /// Stretches this member spent OUT of the room, as inclusive date keys,
  /// oldest first - written by RoomsController.joinRoom when someone who left
  /// comes back, from [leftAt] through the day before the rejoin.
  ///
  /// An away day scores ZERO on the room score ([roomCreditFor]), and stays
  /// in the denominator. Not excused like a stand-down: a pause is stepping
  /// back from a habit while still in the room, and the room asked nothing of
  /// you; leaving is withdrawing from the contest, and the contest went on
  /// without you. Excusing the away days would leave the exploit half open
  /// (leave for your bad stretch, return, watch it vanish). Zero closes it.
  final List<({String from, String to})> awaySpans;

  /// The day each currently DECLINED shared slot was declined, keyed by slot
  /// index (as a string, Firestore maps take string keys) - so the slot is
  /// held against the member only from then on, and the days before it,
  /// when it was linked and graded, stay exactly as they were played.
  ///
  /// Without a date, declining a slot today put its phantom on every past
  /// day and the resync stopped grading the habit that used to fill it: a
  /// member who unlinked one of three habits on day 20 dropped from 100% to
  /// 67% across the whole room for work already done - the same retroactive
  /// injustice the plan floor fixed for an added slot, from the other
  /// direction. Absent on a doc written before this existed, which reads as
  /// the old behaviour (declined from the slot's plan floor) for legacy
  /// declines only; every new decline carries its day.
  final Map<int, String> slotDeclinedFrom;

  /// Stretches a shared slot spent declined and was then resolved again,
  /// keyed by slot index, as inclusive date keys. A closed window stays a
  /// phantom forever: undoing a decline by linking a habit that happened to
  /// be paused or empty across the declined stretch cannot excuse it, which
  /// is the exploit the review measured (missed days simply vanishing).
  final Map<int, List<({String from, String to})>> slotDeclinedSpans;

  /// The habit that filled a shared slot before it was declined, keyed by
  /// slot index - what the resync keeps grading on the days before
  /// [slotDeclinedFrom], so those days keep the numerator they earned. One
  /// prior per slot; a second decline overwrites it, and the earlier
  /// stretch, always further back than the resync reaches, keeps its stored
  /// counts untouched.
  final Map<int, String> slotPriorHabitIds;

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
    this.standDownDays = const [],
    this.habitRules = const {},
    required this.lastUpdated,
    this.teamBonusClaimed = false,
    this.teamStreakClaims = const [],
    this.podiumBonusClaimed = false,
    this.allDoneToday = false,
    this.allDoneDate,
    this.notificationsMuted = false,
    this.lastSyncedDay,
    this.lastSyncedAt,
    this.inferredScheduledCount = const {},
    this.leftAt,
    this.awaySpans = const [],
    this.slotDeclinedFrom = const {},
    this.slotDeclinedSpans = const {},
    this.slotPriorHabitIds = const {},
  });

  /// Whether this member has left the room (see [leftAt]).
  bool get isDeparted => leftAt != null;

  /// Where a decline with no recorded date starts counting: the day this
  /// document was last written.
  ///
  /// An undated decline used to count from the beginning of time, and that
  /// was a real hole rather than a tidy default. [slotDeclinedFrom] is new,
  /// and its first three weeks of writes were silently discarded by a dotted
  /// field key inside a set(merge:) (see no_dotted_keys_in_set_test.dart), so
  /// NOT ONE participant document in production carries it. Every existing
  /// decline therefore took that branch and became a phantom across its
  /// room's whole history — including the weeks the slot was linked, graded
  /// and answered. On A8GEL7 that alone reversed the podium and put a 63.6%
  /// ceiling on a member who had answered 61% of the room, which is the exact
  /// complaint this whole scoring pass exists to fix.
  ///
  /// [lastUpdated] is the honest anchor: a decline present in the document
  /// was made at or before the last write, so this is the LATEST it can have
  /// happened, and charging no earlier than that never bills anyone for a day
  /// there is no record against. It stops sliding on the first sync, which
  /// stamps a real date (see RoomsController.syncLinkedHabitsProgress) — so
  /// this governs one launch per member and then never again.
  String get undatedDeclineFromKey =>
      DateTime(lastUpdated.year, lastUpdated.month, lastUpdated.day)
          .toDateKey();

  /// Whether shared slot [i] stood declined on [dateKey]: currently declined
  /// and on or after its [slotDeclinedFrom] (or [undatedDeclineFromKey] when
  /// no date was ever recorded), or inside one of its closed
  /// [slotDeclinedSpans].
  bool slotDeclinedOn(int i, String dateKey) {
    for (final s in slotDeclinedSpans[i] ?? const <({String from, String to})>[]) {
      if (dateKey.compareTo(s.from) >= 0 && dateKey.compareTo(s.to) <= 0) {
        return true;
      }
    }
    if (i < linkedHabitIds.length && linkedHabitIds[i] == kDeclinedSlot) {
      return dateKey.compareTo(slotDeclinedFrom[i] ?? undatedDeclineFromKey) >=
          0;
    }
    return false;
  }

  /// The habit that was graded in shared slot [i] on [dateKey], if any: the
  /// current one outside any declined window, the prior one on the days
  /// before the current decline. Null while declined or never resolved.
  String? habitInSlotOn(int i, String dateKey) {
    if (slotDeclinedOn(i, dateKey)) return null;
    if (i >= linkedHabitIds.length) return null;
    final current = linkedHabitIds[i];
    if (current != kDeclinedSlot) return current;
    // Declined now, but not yet on this day: the habit that filled it then.
    return slotPriorHabitIds[i];
  }

  /// Whether [dateKey] falls inside a stretch this member was out of the
  /// room - a past [awaySpans] entry, or the open stretch since [leftAt] if
  /// they are out right now.
  bool isAwayOn(String dateKey) {
    for (final s in awaySpans) {
      if (dateKey.compareTo(s.from) >= 0 && dateKey.compareTo(s.to) <= 0) {
        return true;
      }
    }
    final left = leftAt;
    if (left == null) return false;
    return dateKey.compareTo(
          DateTime(left.year, left.month, left.day).toDateKey(),
        ) >=
        0;
  }

  /// Whether the room was already watching on [dateKey] — i.e. a sync ran on
  /// or after that day, so whatever it recorded for that day is a real
  /// observation rather than an absence of one. See [lastSyncedDay].
  bool wasObservedOn(String dateKey) {
    final at = lastSyncedAt;
    if (at != null) {
      // Observed means graded after the day CLOSED. Under the overlapping-day
      // window a day is open, markable and paid, until kDayCutoffHour the
      // next morning, so a resync before that moment saw a day still in
      // progress and its record of it is not final.
      final day = DateTime.parse(dateKey);
      final closes = DateTime(day.year, day.month, day.day + 1, kDayCutoffHour);
      return !at.isBefore(closes);
    }
    // A doc that has only the day watermark, written before the instant was
    // recorded: the day it lands on counts as observed, as it always did
    // (see room_quota_rest_after_last_sync_test.dart for why a back-dated
    // square must not buy that day an excuse). The first full resync after
    // the update stamps the instant, and from then on the rule above is the
    // one that decides.
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

  /// Whether [habitId] had actually joined this room's plan by [dateKey].
  ///
  /// A slot added to a room that was already running is not something the
  /// member failed to do on the days before it existed. Grading it against
  /// them anyway is the bug this answers: adding a third habit to a room on
  /// day 9 re-divided all eight earlier days by 3 while their numerators
  /// could not move, and the adder's percentage fell more than twenty points
  /// for work they had already done. Traced on room ELQVF8, 2026-09-09.
  ///
  /// Read from [habitRules], which is already this room's own frozen,
  /// per-slot, date-windowed record of what it grades and from when. The
  /// MINIMUM `from` across the slot's periods, not [ruleFor]'s: ruleFor
  /// answers "which cadence applies" and deliberately falls back to the
  /// earliest period for a day before any rule started, which is the right
  /// answer to its question and the wrong one to this.
  ///
  /// FAILS OPEN. No recorded rule means this device has never stamped one,
  /// so there is nothing to say the slot was absent and the day grades
  /// exactly as it did before this existed. That is what keeps every stored
  /// percentage identical on the first launch after this ships: only a slot
  /// the room itself recorded as joining late can be excluded by it.
  bool slotOpenBy(String habitId, String dateKey) {
    final rules = habitRules[habitId];
    if (rules == null || rules.isEmpty) return true;
    var from = rules.first.from;
    for (final r in rules) {
      if (r.from.compareTo(from) < 0) from = r.from;
    }
    return from.compareTo(dateKey) <= 0;
  }

  /// [countedHabitCount] as it stood on [dateKey] - the slots that had
  /// actually joined the plan by then.
  ///
  /// The denominator [scheduledCountFor] falls back to. It must stay in step
  /// with what syncLinkedHabitsProgress computes for the same day, or the
  /// two disagree and a written key says one thing while an absent key reads
  /// another - the exact shape of the withdrawn-slot bug (see
  /// test/features/rooms/withdrawn_slot_credit_test.dart).
  int countedHabitCountOn(String dateKey) {
    var n = 0;
    var counted = 0;
    for (var i = 0; i < linkedHabitIds.length; i++) {
      // The habit that was actually in this slot THAT day: the prior one on
      // a day before the slot was declined, none inside a declined window
      // (see habitInSlotOn). A shared slot's history, not just its present.
      final id = habitInSlotOn(i, dateKey);
      if (id == null) continue;
      counted++;
      if (!slotOpenBy(id, dateKey)) continue;
      n++;
    }
    // NEVER zero while anything is linked. A zero denominator is full credit
    // in [creditFor] ("nothing was scheduled, so nothing was fallen short
    // of"), which is right for a day a schedule excused and catastrophic
    // here: a member who declined every original slot and took only a
    // late-added one would be paid 1.0 a day for every day before it joined,
    // retroactively, for nothing. That is a worse bug than the one this
    // whole change fixes, and it is on a ranked board.
    //
    // Falling back to the plain total keeps exactly today's answer for that
    // member: their day scores 0 and stays in the denominator, which is
    // honest - they were in the room and it did ask them for something. So
    // this method can only ever SHRINK a denominator that still has at least
    // one open slot in it, and can never create one that pays.
    if (n == 0) return counted;
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

  /// How many habits [dateKey] asked of this member: the inferred count for
  /// a closed quota week the member's phone has not regraded yet, when there
  /// is one (see [inferredScheduledCount]), otherwise what the document
  /// records ([recordedScheduledCountFor]). Every score and every drawn
  /// square reads this.
  int scheduledCountFor(String dateKey) =>
      inferredScheduledCount[dateKey] ?? recordedScheduledCountFor(dateKey);

  /// [scheduledCountFor] as the document itself records it, with nothing
  /// inferred on top. The anti-backdating clamp in syncLinkedHabitsProgress
  /// compares against THIS, and must: lowering the value it compares against
  /// is what released it when an admin write tried exactly that on
  /// 2026-09-11 (a back-painted observed day then asked for more than
  /// before, and was paid).
  ///
  /// Note the fallback can't know about a leader-withdrawn slot (that lives on
  /// the room, not here) - it doesn't need to, because the sync writes a real
  /// [dailyScheduledCount] entry whenever the true count differs from the
  /// plain total, and this fallback only ever applies to a day no sync has
  /// covered yet.
  ///
  /// ...which used to mean "and therefore you missed it", and that was wrong
  /// in the one case it mattered most. The sync only writes a day while the
  /// app is open, and the whole point of a weekly quota is that once you have
  /// hit your four, the rest of the week is yours. Those are exactly the days
  /// nobody opens the app. So a member who finished their week early stopped
  /// syncing, the remaining days kept no entry, this fallback called every one
  /// of them fully scheduled, and the strip crossed out days the quota had
  /// already bought them.
  ///
  /// Found on room A8GEL7: Perla's week of Sat 15 Aug had four greens (15, 17,
  /// 18, 19), her stored quotaOkWeeks contained 2026-08-15 confirming the
  /// quota was met, and her lastSyncedDay was 2026-08-19. The 20th and 21st
  /// carried no entry and drew as misses, while [_keepsStreak] - reading
  /// [quotaOkWeeks] instead of this map - forgave the very same two days. One
  /// participant document, two answers.
  ///
  /// So an unrecorded day now asks [quotaOkWeeks] before assuming the worst.
  /// That set is an explicit allow-list written only when a week genuinely
  /// reached its target, so it still fails safe: absent means not excused,
  /// never a phantom credit. Only a day with nothing done on it can be
  /// excused this way - a day that was actually trained must keep a real
  /// scheduled count so [creditFor] scores it and [isRestDay] doesn't label
  /// somebody's session a rest.
  ///
  /// An explicit stored entry always wins: the sync knows more than this
  /// inference does, including about withdrawn slots.
  ///
  /// [wasObservedOn] bounds it to days no sync ever reached, which is both
  /// the literal case this exists for and the thing that keeps it honest.
  /// quotaOkWeeks is graded from raw square history with no anti-backdating
  /// cap, so colouring in last week's squares today can make a week read as
  /// met. Without this bound that retroactive week would then excuse all its
  /// blank days and pay out on the ranked percentage: measured at +28.6
  /// points from back-painting two squares. Days a sync already watched keep
  /// their observed value instead, so back-dating still cannot buy credit
  /// here, exactly as setSquare's past-day branch refuses to pay XP for it.
  int recordedScheduledCountFor(String dateKey) {
    final stored = dailyScheduledCount[dateKey];
    if (stored != null) return stored;
    if (!wasObservedOn(dateKey) &&
        (dailyDoneCount[dateKey] ?? 0) == 0 &&
        (dailyPartialCount[dateKey] ?? 0) == 0 &&
        _everyCountedHabitIsWeeklyOn(dateKey) &&
        _weekQuotaWasMet(dateKey)) {
      return 0;
    }
    // The plan AS IT STOOD on this day, not as it stands now. A slot the
    // room recorded as joining later is not part of this day's denominator -
    // see [countedHabitCountOn]. Identical to [countedHabitCount] for every
    // room whose plan never changed, which is almost all of them.
    return countedHabitCountOn(dateKey);
  }

  /// Whether EVERY counted habit was on a weekly quota on [dateKey].
  ///
  /// This gate exists because [quotaOkWeeks] and [scheduledCountFor] have
  /// different scopes, and conflating them silently forgives real misses.
  /// The grader that writes quotaOkWeeks skips every non-weekly habit before
  /// deciding a week held (`if (rule.frequencyType != weekly) continue`), so
  /// the set attests to the quota habits and to nothing else. A plan of one
  /// daily habit plus one 4x-a-week habit can therefore bank a "met" week in
  /// which the daily habit was missed all seven days.
  ///
  /// Returning 0 there would zero the denominator for the WHOLE day, excusing
  /// the daily habit on the strength of an attestation that never looked at
  /// it. Measured on a mixed plan: 85.7% against a correct 57.1%, on a ranked
  /// leaderboard. So the inference only runs when there is no other kind of
  /// habit for it to speak over.
  ///
  /// [quotaWeekIsLost] and the room streak ([_keepsStreak]) ask this before
  /// trusting quotaOkWeeks too, so the strip, the lost-week cross-out and the
  /// flame always agree about which plans the set can speak for. The streak
  /// skipped it until 2026-09-11 (room ELQVF8, see
  /// room_streak_quota_scope_test.dart).
  ///
  /// Fails safe twice over. A missing rule means this device has not yet
  /// recorded what cadence that habit was on, and an unproven habit is
  /// treated as not-weekly, so the inference simply doesn't run and the old
  /// fallback stands. Same for a plan with no counted habits at all.
  bool _everyCountedHabitIsWeeklyOn(String dateKey) {
    var sawOne = false;
    for (final id in linkedHabitIds) {
      if (id == kDeclinedSlot) continue;
      sawOne = true;
      final rule = ruleFor(id, dateKey);
      if (rule == null || rule.frequencyType != HabitFrequencyType.weekly) {
        return false;
      }
    }
    return sawOne;
  }

  /// Whether [dateKey] falls in a week this participant's stored
  /// [quotaOkWeeks] marks as having reached its weekly target. Bucketed by
  /// [DateTimeGameExt.startOfDisplayWeek] (Saturday), the same rule
  /// [_keepsStreak] uses, so the two can never disagree about which seven
  /// days a week is. Empty for a purely daily-habit room, since the grader
  /// only ever records a week when it saw a weekly habit.
  bool _weekQuotaWasMet(String dateKey) {
    final day = DateTime.tryParse(dateKey);
    if (day == null) return false;
    return quotaOkWeeks.contains(day.startOfDisplayWeek.toDateKey());
  }

  /// Whether the quota week around [dateKey] can no longer reach its target,
  /// however the days it has left are spent.
  ///
  /// A 4x-a-week habit buys three blank days in a seven-day week. The fourth
  /// blank does not merely put the week behind, it ENDS it: three sessions
  /// is the most that can still be reached, and the week will grade as a
  /// miss no matter what happens on the remaining days. This is what tells
  /// the strip it may cross those days out now instead of waiting for
  /// Saturday to say something that was already true on Wednesday.
  ///
  /// Everything about it fails toward silence, because crossing out a day
  /// that could still have been saved is the one mistake that matters here:
  ///
  ///  * a week already banked in [quotaOkWeeks] is never lost;
  ///  * a plan with anything other than weekly habits on it is left alone,
  ///    exactly as [scheduledCountFor]'s own inference is, so a daily habit
  ///    is never graded by a quota's arithmetic;
  ///  * a habit whose rule this device has not recorded, or whose target is
  ///    not a real number, answers no;
  ///  * [dailyDoneCount] counts habits, not sessions of ONE habit, so on a
  ///    multi-habit plan it can only overstate what is already done, which
  ///    can only make a week look more reachable than it is.
  ///
  /// Days still to come count as available only while the room is still
  /// running on them: [lastCountedDay] is today for a live room, and a room
  /// that ends mid-week has nothing to offer after [endDate].
  ///
  /// YESTERDAY counts too while it is still inside the overlapping-day
  /// window. A day stays markable until [kDayCutoffHour] the next morning
  /// (DateTimeGameExt.isOpenDayAt), and a session marked in that tail is one
  /// the Grid pays and the room counts, so at 03:00 the week has one more day
  /// in hand than the calendar suggests. [now] is injectable for the same
  /// reason isOpenDayAt is: a rule with a boundary at 10 AM is otherwise only
  /// ever tested at whatever hour the suite happens to run.
  bool quotaWeekIsLost(String dateKey, RoomModel room, {DateTime? now}) {
    final clock = now ?? DateTime.now();
    final day = DateTime.tryParse(dateKey);
    if (day == null) return false;
    if (_weekQuotaWasMet(dateKey)) return false;
    if (!_everyCountedHabitIsWeeklyOn(dateKey)) return false;

    final weekStart = day.startOfDisplayWeek;
    final weekEnd = weekStart.add(const Duration(days: 6));
    final roomEnd = room.endDate;
    final today = room.lastCountedDayAt(clock);

    for (final id in linkedHabitIds) {
      if (id == kDeclinedSlot) continue;
      final rule = ruleFor(id, dateKey);
      if (rule == null ||
          rule.frequencyType != HabitFrequencyType.weekly ||
          rule.frequencyTarget < 1) {
        return false;
      }

      var reachable = 0;
      for (var d = weekStart; !d.isAfter(weekEnd); d = d.add(const Duration(days: 1))) {
        final key = d.toDateKey();
        // A day the room was not running, or the member's plan was stood
        // down on, was never theirs to spend and cannot be spent now.
        if (room.isPausedOn(key) || isStoodDownOn(key)) continue;
        if (d.isBefore(room.startDate)) continue;
        if (roomEnd != null && d.isAfter(roomEnd)) continue;
        // Three ways a day can still hold the session they need: it already
        // did, it has not happened yet, or it is the day that just ended and
        // is still inside the grace tail. Anything else is a blank day
        // already spent.
        //
        // `isAfter(today)`, not `!isBefore(today)`: today itself is covered
        // by isOpenDayAt, and on a room that has ENDED the last counted day
        // is in the past and long since spent — counting it would hand every
        // finished room one imaginary session.
        if ((dailyDoneCount[key] ?? 0) > 0 ||
            d.isAfter(today) ||
            d.isOpenDayAt(clock)) {
          reachable++;
        }
      }
      if (reachable < rule.frequencyTarget) return true;
    }
    return false;
  }

  /// How far back a member's own phone regrades a room: kRoomSyncWindowDays
  /// in rooms_notifier.dart. Mirrored because the model does not import the
  /// notifier; room_closed_quota_week_inference_test.dart pins the two
  /// together.
  static const int kSyncWindowDaysMirror = 45;

  /// The westernmost and easternmost clocks people keep, in hours from UTC.
  /// [closedQuotaWeekInference] reads every date it takes from an instant at
  /// one of these two, never on the device it happens to run on.
  static const int _kWestmostUtcOffsetHours = -12;
  static const int _kEastmostUtcOffsetHours = 14;

  /// The calendar day [instant] falls on for a clock [offsetHours] from UTC,
  /// as a local midnight like every other day this model builds. Read from
  /// the UTC value, so every device gets the same day whatever its own zone.
  static DateTime _dayAtUtcOffset(DateTime instant, int offsetHours) {
    final wall = instant.toUtc().add(Duration(hours: offsetHours));
    return DateTime(wall.year, wall.month, wall.day);
  }

  /// The Saturday that starts [day]'s week, counted in calendar days.
  /// startOfDisplayWeek subtracts a Duration, which a daylight saving change
  /// on this device can push into the day before.
  static DateTime _saturdayOn(DateTime day) => DateTime(
        day.year,
        day.month,
        day.day - (day.weekday - DateTime.saturday + 7) % 7,
      );

  /// Due counts for the days of weekly-quota weeks that have CLOSED since
  /// this member's last full sync graded them while they were still open,
  /// worked out from this document and [room] alone. A day is in the result
  /// only when its answer differs from [recordedScheduledCountFor].
  ///
  /// Why it exists. While a quota week is open the sync counts every present
  /// day as due (weeklyQuotaScheduledDays returns them all). Once the week
  /// closes short, the days weeklyQuotaDemand calls spare become rest days,
  /// but only the member's own phone writes that, and a member who stopped
  /// opening the app kept that week, and every week after it, fully due.
  /// Measured 2026-09-11: A8GEL7 Perla 37.8% for a record her own regrade
  /// scores 45.2%, YW68B9 m7md 26.3% for 31.3%.
  ///
  /// What it answers: what syncLinkedHabitsProgress would write for those
  /// days if the phone synced at [now] and the squares matched this record,
  /// on whatever clock that phone keeps (see "Which clock" below). The same
  /// window (kSyncWindowDaysMirror, rewound to Saturday), the same Saturday
  /// weeks, the same target clamped to the days present, and the same rest
  /// decision: weeklyQuotaDemand, translated to week positions exactly as
  /// weeklyQuotaScheduledDays does.
  ///
  /// It never reaches the anti-backdating clamp. The clamp compares against
  /// [recordedScheduledCountFor], and the sync grades a participant it
  /// parsed from the raw document, which has no inferred counts. Nor does it
  /// reach a payout: a team milestone is graded [asRecorded]
  /// (RoomTeamProgress.claimableTeamMilestone), and a room that has ended,
  /// where the podium settles, is left as recorded.
  ///
  /// A week is left exactly as recorded unless every one of these holds,
  /// because each is something the document cannot otherwise prove:
  ///  * the member is in the room and has synced, every linked habit has a
  ///    recorded rule, no declined slot carries a prior habit, and no linked
  ///    slot has been withdrawn (a declined slot is no habit at all, even
  ///    one the leader withdrew afterwards);
  ///  * the room has started, and has not ended on any clock. An ended room
  ///    is settled: RoomsController.claimPodiumBonus pays from its standings,
  ///    and no member's phone regrades it unasked (resyncAllMyRooms and
  ///    linkedRoomsFor both skip it);
  ///  * the week has closed by [now] on every clock and the last sync saw it
  ///    open on every clock: its lastSyncedDay is not after the week, and its
  ///    recorded instant falls on no later day than the week's last;
  ///  * the week is not banked in [quotaOkWeeks], touches no room pause and
  ///    no away day, and every habit's rule and slot are the same on all of
  ///    its days, starting on or before the first. The rule must also be
  ///    the same on any day in front of them that a phone can count first,
  ///    because a phone grades the whole week by the rule on its own first
  ///    counted day in it (see "Which clock");
  ///  * no day carries a partial or a rest mark, no stood-down day carries a
  ///    done, every other day records exactly what an open week records
  ///    (each weekly habit plus the regular habits due that weekday), and
  ///    each day has either nothing or everything done, so every weekly
  ///    habit's done days are known;
  ///  * those done days do not already meet the target.
  /// A day with anything done on it is never lowered.
  ///
  /// What it cannot see is squares. A square painted after its day closed,
  /// and held at zero by the clamp, still counts toward the target in the
  /// phone's regrade, which can move WHICH empty day is owed without moving
  /// the score: YW68B9 y.almehza101's phone keeps 22 August owed and rests
  /// the 26th, this rests the 22nd and keeps the 26th, four due days and the
  /// same percentage either way. Marks on days no sync observed leave this
  /// at or below the phone's answer. Late marks on days a sync DID observe
  /// can leave it above: squares painted there after the last sync that
  /// take a closed week past its target make the phone owe every green day
  /// (weeklyQuotaScheduledDays) while the clamp holds them at zero, and this
  /// cannot see them. Measured: a 4x week with 22 to 24 August done, a sync
  /// on Friday 28 August, then squares painted on the 25th and 26th, scores
  /// 3 of 4 here against 3 of 5 on the phone until that phone's sync lands.
  ///
  /// Nor can it see a habit paused after the last sync. The phone stops
  /// counting a paused habit where its stint ends (archivedAt) and stands
  /// those days down, but nothing on this document records the pause, so
  /// this treats them as present and can rest some of them. A 4x week with
  /// nothing done, paused after its fifth day, rests Saturday on the phone
  /// and Saturday to Monday here.
  ///
  /// Both are display only, and both are why nothing that pays may read
  /// this: payouts and ended rooms read the record ([asRecorded]).
  ///
  /// Which clock. Nothing in the document says what zone the member's phone
  /// keeps, and the viewer's own calendar can be a day ahead of it: a viewer
  /// at UTC+4 graded the week of 5 September closed at 2026-09-11T20:22Z,
  /// still Friday evening on the Bahrain phones in A8GEL7 and YW68B9. So
  /// every calendar date this takes from an INSTANT is read at the end of
  /// the inhabited clocks, UTC-12 or UTC+14, that makes it fire less, and
  /// the same on every device:
  ///  * today, and with it whether a week has closed: UTC-12, the latest
  ///    anywhere;
  ///  * whether the room has ended: today at UTC+14 against its end day at
  ///    UTC-12, the earliest anywhere;
  ///  * the room's first day and the member's join day: UTC+14, so no day
  ///    counts that some phone does not count;
  ///  * the first day a phone can take a week's rule from, those same two
  ///    dates: UTC-12, the earliest anywhere. A member who joined on a
  ///    Monday at 14:00 in Bahrain joined on Tuesday at UTC+14 and on Sunday
  ///    at UTC-12, and their phone grades that week by Monday's rule;
  ///  * the window's last day: UTC+14, so a week ages out as early as it
  ///    does anywhere;
  ///  * the last sync's day ([lastSyncedAt]): UTC+14, the latest day it can
  ///    have run on.
  /// Keys the member's phone wrote (lastSyncedDay, rule, pause, away and day
  /// keys) are already its own calendar and are read as written.
  ///
  /// A week these readings cut short at its start rests only days the phone
  /// rests too. weeklyQuotaDemand calls an empty day spare when the days
  /// from it to the week's end outnumber what is still needed: the days a
  /// phone counts in front of it leave the first as it is, and can only
  /// lower the second.
  ///
  /// Apart from those two blind spots and the one case after this list, the
  /// cost is time, never a wrong answer:
  ///  * a Bahrain member's closed week is corrected about 15 hours after it
  ///    closes on their phone (Saturday 12:00 UTC against Friday 21:00 UTC),
  ///    never before;
  ///  * a week whose last sync was stamped at 13:00 Bahrain time or later on
  ///    its own last day stays as recorded;
  ///  * a Bahrain room is left as recorded from 13:00 Bahrain time on the
  ///    day before its last day, and for good once it has ended, so its
  ///    finale and its podium read the record as they did before this
  ///    existed.
  /// The one case is daylight saving. A phone whose clock changes groups
  /// days in 24-hour steps (startOfGridWeek, and the day list the sync
  /// builds with day.add), which splits the week of each change in two,
  /// while this reads whole calendar weeks. For a member on such a phone it
  /// can rest a day that phone keeps due. The split is the phone grader's
  /// own bug, and no Gulf zone changes its clock.
  Map<String, int> closedQuotaWeekInference(RoomModel room, {DateTime? now}) {
    final clock = now ?? DateTime.now();
    final synced = lastSyncedDay;
    if (isDeparted || room.isLobby || synced == null) return const {};
    // See "Which clock" above.
    DateTime west(DateTime t) => _dayAtUtcOffset(t, _kWestmostUtcOffsetHours);
    DateTime east(DateTime t) => _dayAtUtcOffset(t, _kEastmostUtcOffsetHours);
    final today = west(clock);
    final todayEast = east(clock);
    final start = east(room.startDate);
    if (today.isBefore(start)) return const {};
    // Ended on some clock: settled, and left as recorded. Past this line
    // the room's end day falls on or after todayEast, and so after every
    // closed week, which is why nothing below asks about the end again.
    final endAt = room.endDate;
    if (endAt != null && todayEast.isAfter(west(endAt))) return const {};

    final shared = room.habitMode == RoomHabitMode.shared
        ? room.sharedHabits
        : const <RoomHabitTemplate>[];
    final slots = <(int, String)>[];
    for (var i = 0; i < linkedHabitIds.length; i++) {
      final id = linkedHabitIds[i];
      if (id == kDeclinedSlot) continue;
      if (i < shared.length && shared[i].isRemoved) return const {};
      final rules = habitRules[id];
      if (rules == null || rules.isEmpty) return const {};
      slots.add((i, id));
    }
    if (slots.isEmpty || slotPriorHabitIds.isNotEmpty) return const {};
    if (!slots.any(
      (s) => habitRules[s.$2]!
          .any((r) => r.frequencyType == HabitFrequencyType.weekly),
    )) {
      return const {};
    }

    // The phone's own window, rooms_notifier.dart syncLinkedHabitsProgress:
    // countedStartIn, then the last kSyncWindowDaysMirror days.
    final joined = east(joinedAt);
    var windowStart = joined.isAfter(start) ? joined : start;
    if (dailyDoneCount.isNotEmpty) {
      final aligned = _saturdayOn(
        DateTime(
          todayEast.year,
          todayEast.month,
          todayEast.day - (kSyncWindowDaysMirror - 1),
        ),
      );
      if (aligned.isAfter(windowStart)) windowStart = aligned;
    }
    // The earliest day any phone can count as this member's first: the
    // same two dates read at UTC-12. A phone grades a whole week by the rule
    // on its own first counted day in it, which in the week of the join or
    // of the room's start can fall before windowStart.
    final startWest = west(room.startDate);
    final joinedWest = west(joinedAt);
    final firstOnAnyPhone =
        joinedWest.isAfter(startWest) ? joinedWest : startWest;
    final syncedAt = lastSyncedAt;
    final syncedOn = syncedAt == null ? null : east(syncedAt);

    final out = <String, int>{};
    for (var week = _saturdayOn(windowStart);
        !week.isAfter(today);
        week = DateTime(week.year, week.month, week.day + 7)) {
      final weekEnd = DateTime(week.year, week.month, week.day + 6);
      // Closed now: isQuotaWeekClosed.
      if (!weekEnd.isBefore(today)) continue;
      // Open at the last sync. A sync after the week closed stamps a
      // lastSyncedDay past its end, or an instant some clock puts past it.
      if (weekEnd.toDateKey().compareTo(synced) < 0) continue;
      if (syncedOn != null && weekEnd.isBefore(syncedOn)) continue;
      if (quotaOkWeeks.contains(week.toDateKey())) continue;

      final first = week.isAfter(windowStart) ? week : windowStart;
      if (first.isAfter(weekEnd)) continue;
      final keys = <String>[
        for (var d = first;
            !d.isAfter(weekEnd);
            d = DateTime(d.year, d.month, d.day + 1))
          d.toDateKey(),
      ];
      // Every day a phone can take this week's rule from
      // (rooms_notifier.dart: roomRuleAt at days[dayIndices.first]): keys,
      // and any day in front of them some phone counts first. Never after
      // keys.first, since firstOnAnyPhone is never after windowStart.
      final ruleFirst = week.isAfter(firstOnAnyPhone) ? week : firstOnAnyPhone;
      final ruleKeys = <String>[
        for (var d = ruleFirst;
            !d.isAfter(weekEnd);
            d = DateTime(d.year, d.month, d.day + 1))
          d.toDateKey(),
      ];
      if (keys.any((k) => room.isPausedOn(k) || isAwayOn(k))) continue;

      var provable = true;
      final targets = <int>[];
      final regular = <RoomHabitRule>[];
      for (final (slot, id) in slots) {
        final rules = habitRules[id]!;
        final rule = ruleFor(id, keys.first)!;
        var floor = rules.first.from;
        for (final r in rules) {
          if (r.from.compareTo(floor) < 0) floor = r.from;
        }
        if (floor.compareTo(keys.first) > 0 ||
            ruleKeys.any((k) => !identical(ruleFor(id, k), rule)) ||
            keys.any((k) => habitInSlotOn(slot, k) != id)) {
          provable = false;
          break;
        }
        if (rule.frequencyType == HabitFrequencyType.weekly) {
          if (rule.frequencyTarget < 1) {
            provable = false;
            break;
          }
          targets.add(rule.frequencyTarget);
        } else {
          regular.add(rule);
        }
      }
      if (!provable || targets.isEmpty) continue;

      final present = <String>[];
      final recorded = <String, int>{};
      final allDone = <String>{};
      for (final k in keys) {
        final done = dailyDoneCount[k] ?? 0;
        if ((dailyPartialCount[k] ?? 0) > 0 || (dailyRestedCount[k] ?? 0) > 0) {
          provable = false;
          break;
        }
        if (isStoodDownOn(k)) {
          if (done > 0) {
            provable = false;
            break;
          }
          continue;
        }
        final count = recordedScheduledCountFor(k);
        final weekday = DateTime.parse(k).weekday;
        final openWeekCount = targets.length +
            regular
                .where(
                  (r) =>
                      r.scheduledWeekdays.isEmpty ||
                      r.scheduledWeekdays.contains(weekday),
                )
                .length;
        if (count != openWeekCount) {
          provable = false;
          break;
        }
        if (done == count) {
          allDone.add(k);
        } else if (done != 0) {
          provable = false;
          break;
        }
        present.add(k);
        recorded[k] = count;
      }
      if (!provable || present.isEmpty) continue;

      final rest = <String, int>{};
      for (final target in targets) {
        final effective = target.clamp(1, present.length);
        if (allDone.length >= effective) {
          provable = false;
          break;
        }
        final demand = weeklyQuotaDemand(
          dayCount: present.length,
          doneDays: {
            for (var i = 0; i < present.length; i++)
              if (allDone.contains(present[i])) i,
          },
          target: effective,
        );
        for (var i = 0; i < present.length; i++) {
          if (demand[i].isRest) {
            rest[present[i]] = (rest[present[i]] ?? 0) + 1;
          }
        }
      }
      if (!provable) continue;
      for (final e in rest.entries) {
        // Guaranteed by the gates above; stated so it cannot quietly stop
        // being true.
        if ((dailyDoneCount[e.key] ?? 0) != 0) return const {};
        out[e.key] = recorded[e.key]! - e.value;
      }
    }
    return out;
  }

  /// This member with [closedQuotaWeekInference] applied to every read built
  /// on [scheduledCountFor]. For the board only: gradedRoomParticipantsProvider
  /// calls it, nothing that writes a participant document may read the
  /// result, and nothing that pays may either (see [asRecorded]).
  RoomParticipant withClosedQuotaWeeksInferred(
    RoomModel room, {
    DateTime? now,
  }) {
    final inferred = closedQuotaWeekInference(room, now: now);
    return inferred.isEmpty ? this : copyWith(inferredScheduledCount: inferred);
  }

  /// This member as the document records it: [inferredScheduledCount]
  /// dropped, so every read built on [scheduledCountFor] answers
  /// [recordedScheduledCountFor] again. What anything that pays grades,
  /// whichever roster it was handed: an inferred week can pick a different
  /// rest day from the member's own phone (see [closedQuotaWeekInference]).
  RoomParticipant get asRecorded => inferredScheduledCount.isEmpty
      ? this
      : copyWith(inferredScheduledCount: const {});

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
    // Pausing a habit and marking تخطّي on it are different acts with
    // different records; a stood-down day has no squares to have been rested.
    if (isStoodDownOn(dateKey)) return false;
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
    // A stood-down day is worth NOTHING, and that is deliberate rather than
    // incidental. It is skipped on both sides by [daysCompleted] and
    // [daysElapsedIn], so the number it returns cannot reach the percentage —
    // but it can reach every screen that asks a day "how did this go", and the
    // one answer that must never come back is "finished". Falling through to
    // the line below would give exactly that: a paused day writes no scheduled
    // count, an absent count is a rest, and a rest pays 1.0. See standDownDays.
    if (isStoodDownOn(dateKey)) return 0;
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
      hasCountedHabits &&
      // A day the whole plan was paused is not a rest day the schedule
      // granted — see standDownDays for why the two must not collapse.
      !isStoodDownOn(dateKey) &&
      scheduledCountFor(dateKey) == 0;

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
    // Nothing was asked, so nothing was finished. This is the guard that stops
    // a pause reading as a completed day anywhere a screen wants a plain
    // done/not-done signal — including the room streak, which asks this.
    if (isStoodDownOn(dateKey)) return false;
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
  /// the per-person counterpart to [RoomModel.daysElapsed]. Never less than
  /// 1, even on the day someone joins.
  ///
  /// The ratios below deliberately do NOT use this: they want [_liveDaysIn]'s
  /// unclamped count, because zero days asked and one day asked are different
  /// facts and this method cannot tell them apart.
  int daysElapsedIn(RoomModel room) {
    final live = _liveDaysIn(room).live;
    return live < 1 ? 1 : live;
  }

  /// The real denominator: how many days in this participant's window
  /// anything was actually asked of them, unclamped, plus whether the reason
  /// nothing was is the SCHEDULE's own doing.
  ///
  /// Zero live days is a real answer, not an error, and [progressRatio] reads
  /// it through `allRest`: a window the plan never asked a single thing of is
  /// nothing fallen short of, while a window excused by a pause or a
  /// stand-down keeps the zero it has always had.
  ({int live, bool allRest}) _liveDaysIn(RoomModel room) {
    final start = countedStartIn(room);
    final last = room.lastCountedDay;
    if (last.isBefore(start)) return (live: 1, allRest: false);
    final span = last.difference(start).inDays + 1;
    final conceded = concededDaysIn(room);
    // No early return. There used to be one when the three stored exemptions
    // were all empty, but a rest day the SCHEDULE grants leaves the
    // denominator too now (see [isRestDay] below), and nothing is stored for
    // those - a 4x-a-week habit has them every week without a single paused
    // span or stand-down day to hint at it. Walking is what the numerator
    // already does, so the two agree by construction.
    // Paused days are not elapsed — the room wasn't running, so they were
    // never anyone's to keep. Counted by walking rather than by subtracting
    // span lengths, so a span that only partly overlaps this participant's
    // own window (a late joiner) is handled without special-casing.
    //
    // Conceded days leave the same way, and only ever days that scored zero
    // (see [concededDaysIn]), so this can lift a percentage but never invent
    // completion that did not happen.
    //
    // Stand-down days leave for the same reason as a room pause: the member
    // had no counted habit running, so the room asked them for nothing. They
    // are worth 0 in [daysCompleted] and 0 here, so a paused stretch holds a
    // percentage exactly where it was rather than either paying it out or
    // burning it down. See standDownDays.
    // ── A day the plan never asked for leaves BOTH sides ─────────────────
    //
    // It used to leave only the numerator's side, by being paid FULL credit
    // in [creditFor] ("nothing was scheduled, so nothing was fallen short
    // of") while still counting in this denominator. On a 7-day week that
    // handed a 4x-a-week habit three free successes every single week,
    // whatever actually happened: measured with the real grader, a week in
    // which NOTHING was done still scored 3/7 = 43%, and 1 of 4 scored 57%.
    //
    // Aziz, three times, looking at his own room: "why they are not getting
    // failure, they are missing the days not only rest days". He is right.
    // A day nobody was asked about is not a day anybody succeeded at, and
    // paying it like one is what stopped a missed week from reading as one.
    //
    // Excused instead, exactly as a paused day and a stand-down day already
    // are. A week's score becomes what fraction of its target was actually
    // done: 4 of 4 is still 100%, 1 of 4 is 25%, 0 of 4 is 0%. A completed
    // commitment is unchanged - which is the whole point, and the reason
    // this is safe for everyone keeping their promise.
    //
    // The Grid keeps painting these days calm (see isCoveredDay): a rest day
    // should still not LOOK like a miss. It simply stops counting as a win.
    var excused = 0;
    var rested = 0;
    for (var d = start; !d.isAfter(last); d = d.add(const Duration(days: 1))) {
      final key = d.toDateKey();
      final resting = isRestDay(key);
      if (resting) rested++;
      if (room.isPausedOn(key) ||
          conceded.contains(key) ||
          isStoodDownOn(key) ||
          resting) {
        excused++;
      }
    }
    return (live: span - excused, allRest: rested == span);
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
      // isDeclaredRest is already false on a stand-down day, so this is belt
      // and braces — but it states the rule the allowance depends on: an
      // allowance may only ever be spent on a day that would otherwise have
      // scored zero, and a stood-down day scores nothing at all.
      if (key.compareTo(from) >= 0 &&
          !room.isPausedOn(key) &&
          !isStoodDownOn(key) &&
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
      // A member's own stand-down days leave by the same door, and so does a
      // day the schedule never asked for (see daysElapsedIn's isRestDay note:
      // a free day used to be paid a full 1.0 here, which is what let a week
      // of nothing score 43%).
      if (!room.isPausedOn(key) && !isStoodDownOn(key) && !isRestDay(key)) {
        total += creditFor(key);
      }
      day = day.add(const Duration(days: 1));
    }
    return total;
  }

  /// 0.0-1.0 completion ratio for [room] - the number every leaderboard row
  /// sorts and renders by.
  double progressRatio(RoomModel room) {
    // Their own window, not the room's — see [countedStartIn].
    final window = _liveDaysIn(room);
    if (window.live <= 0) {
      // Every day they have been here was excused, so there is no fraction
      // to take. Which answer that deserves depends on WHY.
      //
      // The schedule's own doing (allRest): nothing was ever asked, so
      // nothing was fallen short of — the day-one member whose only habit is
      // Friday's, joining on a Tuesday. 1.0, exactly as before rest days
      // started leaving the denominator, so this narrow case is unchanged by
      // that fix. Tenure still keeps them off the podium (see holdsPlaceIn).
      //
      // A pause or a stand-down: unchanged too, and that has always been 0.
      // Someone who parked every habit on day one has not completed a room.
      return window.allRest ? 1.0 : 0.0;
    }
    return (daysCompleted(room) / window.live).clamp(0.0, 1.0);
  }

  // ── The room score ────────────────────────────────────────────────────
  //
  // Two numbers, on purpose.
  //
  // [progressRatio] is YOUR number: done over the habits you actually linked,
  // over your own days. It never lies about your effort and nothing another
  // member does can move it. It is what the strip, your sheet and your own
  // header speak in.
  //
  // [roomProgressRatio] is the ROOM SCORE: every day graded against the
  // room's plan as it stood that day, whether or not you linked all of it. It
  // is what the board ranks by, because it is the only number that means the
  // same thing for every row. A percentage of your own plan is only
  // comparable with somebody else's when the plans are the same size, and a
  // room's plans are not: a slot declined, a slot not yet linked, a slot a
  // free account could not create a habit for, a member who joined late.
  // Ranking [progressRatio] let two of three habits done every day tie
  // three of three, silently, which is the dial this whole file refuses
  // everywhere else (see dailyRestedCount).
  //
  // For every room where everyone linked every slot and nobody left, the
  // two are identical, so nothing moves on the first launch after this
  // ships except in rooms where the board was already wrong.

  /// Slots in [room]'s plan that were asked of this member on [dateKey] and
  /// that they have not linked - never resolved, or declined (see
  /// [kDeclinedSlot]). Each one counts as not done on the room score. Always
  /// 0 for an 'own'-mode room, which has no shared plan to fall short of.
  ///
  /// A slot the leader added later is only held against an unlinked member
  /// from [RoomModel.slotAsksFromKey], the addition plus a grace, so someone
  /// who has not opened the app since it appeared has a few days before the
  /// plan is counted against them. A member who DID link it is scored from
  /// the day they did, through their own RoomHabitRule, so an engaged room
  /// never waits (see RoomModel.kNewSlotGraceDays).
  int phantomSlotsOn(RoomModel room, String dateKey) {
    if (room.habitMode != RoomHabitMode.shared) return 0;
    final shared = room.sharedHabits;
    var n = 0;
    for (var i = 0; i < shared.length; i++) {
      if (shared[i].isRemoved) continue;
      if (!_slotIsPhantomOn(room, i, dateKey)) continue;
      n++;
    }
    return n;
  }

  /// Whether shared slot [i] was asked of this member on [dateKey] and had
  /// no habit in it: never resolved, or declined THAT day (see
  /// [slotDeclinedOn] - a decline counts from the day it was made, and a
  /// closed declined window stays a phantom however the slot was filled
  /// afterwards). Never before the day the room holds the slot against an
  /// unlinked member ([RoomModel.slotAsksFromKey]).
  bool _slotIsPhantomOn(RoomModel room, int i, String dateKey) {
    if (room.slotAsksFromKey(i).compareTo(dateKey) > 0) return false;
    if (i >= linkedHabitIds.length) return true; // never resolved
    final habit = habitInSlotOn(i, dateKey);
    if (habit == null) {
      // Declined, undated, and no record of what was in the slot before -
      // on a day before the decline could even have been made (see
      // [undatedDeclineFromKey]). We do not know whether they carried this
      // slot then or never took it, so the slot leaves BOTH sides: not a
      // phantom here, and not in [ownPlanWeightOn] either, since
      // habitInSlotOn is null for it. The day is graded on what they
      // demonstrably did have.
      //
      // Charging it instead is what made every pre-existing decline a
      // phantom across its room's whole history. Crediting it instead would
      // pay for a slot nobody can show was ever carried. Neither is a
      // record, so neither is charged.
      final undated = linkedHabitIds[i] == kDeclinedSlot &&
          slotDeclinedFrom[i] == null &&
          slotPriorHabitIds[i] == null;
      if (undated && dateKey.compareTo(undatedDeclineFromKey) < 0) return false;
      return true;
    }
    // Linked, but not yet on this day: a habit's room rule starts on the day
    // it was linked (the sync seeds it from that day and never earlier), and
    // before that the slot was as empty for this member as for anyone who
    // had not linked it. Without this, linking a habit late made the days
    // before the link disappear from the denominator - and with a sparse
    // cadence, excused them outright. Fails open for a doc with no rule
    // recorded, exactly like slotOpenBy.
    return !slotOpenBy(habit, dateKey);
  }

  /// This member's credit for [dateKey] on the room score: [creditFor], with
  /// every unlinked slot the room asked for that day counted as not done, and
  /// zero for any day they were out of the room ([awaySpans]).
  ///
  /// Byte-for-byte [creditFor] whenever nothing is missing, which is what
  /// keeps every unaffected room's number exactly where it was.
  /// What the unlinked slots the room asked for on [dateKey] weigh in the
  /// denominator - [phantomSlotsOn], with each slot weighed by its template's
  /// cadence. A daily slot is a whole habit every day. A weekly slot is only
  /// ever asked for [frequencyTarget] days of seven, so charging it in full
  /// every day would hold an unlinked "once a week" against someone seven
  /// times harder than the member who linked it and gets rest days; it
  /// weighs target/7 instead, the same average the linked member is graded
  /// at across a week.
  double phantomWeightOn(RoomModel room, String dateKey) {
    if (room.habitMode != RoomHabitMode.shared) return 0;
    final shared = room.sharedHabits;
    var weight = 0.0;
    for (var i = 0; i < shared.length; i++) {
      final slot = shared[i];
      if (slot.isRemoved) continue;
      if (!_slotIsPhantomOn(room, i, dateKey)) continue;
      weight += _slotWeight(slot);
    }
    return weight;
  }

  /// What ONE slot of the room's plan weighs on any given day. The single
  /// definition both sides of the room score use — [phantomWeightOn] for the
  /// slots this member is missing, [ownPlanWeightOn] for the ones they carry.
  ///
  /// Deliberately one function rather than two matching expressions. They
  /// were two, and the second one did not exist: the phantom side discounted
  /// a weekly slot to target/7 while the member's own side was taken from
  /// the day's raw scheduled count, so the same cadence weighed differently
  /// depending on which side of the plan it fell on. Two members carrying
  /// exactly half their room's plan and performing identically scored 50%
  /// and 40.7%, for no reason but whether the slots were daily or weekly.
  static double _slotWeight(RoomHabitTemplate slot) =>
      slot.frequencyType == HabitFrequencyType.weekly
          ? (slot.frequencyTarget / 7).clamp(0.0, 1.0)
          : 1.0;

  /// What the slots this member DOES carry weigh on [dateKey] — the mirror
  /// of [phantomWeightOn], over the slots with one of their habits in them.
  ///
  /// This is a property of the PLAN, not of the day: a slot they carry
  /// weighs the same on a day its habit happens not to be due as on a day it
  /// is. That is the whole point. Their performance on the day is [creditFor]
  /// (which already pays a day nothing was due a full 1.0); this only says
  /// how much of the room's plan that performance speaks for.
  double ownPlanWeightOn(RoomModel room, String dateKey) {
    if (room.habitMode != RoomHabitMode.shared) return 0;
    final shared = room.sharedHabits;
    var weight = 0.0;
    for (var i = 0; i < shared.length; i++) {
      if (shared[i].isRemoved) continue;
      final habit = habitInSlotOn(i, dateKey);
      // Empty for them that day, or linked but not yet running — the same
      // two tests _slotIsPhantomOn uses to call a slot missing.
      if (habit == null || !slotOpenBy(habit, dateKey)) continue;
      weight += _slotWeight(shared[i]);
    }
    return weight;
  }

  double roomCreditFor(RoomModel room, String dateKey) {
    if (isAwayOn(dateKey)) return 0;
    // Stood down leaves both sides, same as daysCompleted/daysElapsedIn.
    if (isStoodDownOn(dateKey)) return 0;
    final phantoms = phantomWeightOn(room, dateKey);
    if (phantoms == 0) return creditFor(dateKey);
    final mine = ownPlanWeightOn(room, dateKey);
    // None of the plan is theirs today, so none of the day is either.
    if (mine <= 0) return 0;
    // Their own day, scaled by the share of the plan it speaks for.
    //
    // This used to re-derive the numerator from raw counts —
    // `(done + partial * 0.5) / (scheduledCountFor + phantoms)` — and that
    // was the bug. An excused habit leaves scheduledCountFor, so it left the
    // numerator AND the denominator while the phantom stayed put, and a day
    // where EVERY own habit was excused divided 0 by the phantom's weight:
    // exactly 0.0, indistinguishable from doing nothing at all. On a
    // 4x-a-week habit that is three days in seven, and it cost the member on
    // Aziz's own room 13 points — 31.0% for a room he was answering 69% of.
    // creditFor pays that day 1.0 and says why ("there was nothing to fall
    // short of"); the room score's only business is scaling it.
    //
    // Byte-for-byte identical to the old arithmetic wherever every linked
    // habit was scheduled and every slot is daily, which is most rooms.
    return (creditFor(dateKey) * mine / (mine + phantoms)).clamp(0.0, 1.0);
  }

  /// [daysCompleted] on the room score.
  double roomDaysCompleted(RoomModel room) {
    var total = 0.0;
    var day = countedStartIn(room);
    final last = room.lastCountedDay;
    while (!day.isAfter(last)) {
      final key = day.toDateKey();
      // An away day contributes its zero whether or not it was also stood
      // down, or a rest day; see [roomDaysElapsedIn] for the other half of
      // that rule. A rest day the plan never asked for leaves both sides
      // (daysElapsedIn's isRestDay note) - but only when nothing else asked
      // that day either, which is what phantomWeightOn answers: an unlinked
      // slot still wants something, so the day is not free.
      final free = isRestDay(key) && phantomWeightOn(room, key) == 0;
      if (!room.isPausedOn(key) &&
          (isAwayOn(key) || (!isStoodDownOn(key) && !free))) {
        total += roomCreditFor(room, key);
      }
      day = day.add(const Duration(days: 1));
    }
    return total;
  }

  /// [daysElapsedIn], plus every away day that it excused.
  ///
  /// daysElapsedIn leaves stood-down and conceded days out of the
  /// denominator, which is right for a score and would leave the reset half
  /// open here: pause every habit, leave, come back, and the away stretch is
  /// excused instead of scored zero. On the room score an away day is in the
  /// denominator no matter what else was true of it. A day the whole ROOM
  /// was paused is still nobody's day.
  int roomDaysElapsedIn(RoomModel room) {
    var elapsed = _liveDaysIn(room).live;
    final conceded = concededDaysIn(room);
    var day = countedStartIn(room);
    final last = room.lastCountedDay;
    while (!day.isAfter(last)) {
      final key = day.toDateKey();
      if (room.isPausedOn(key)) {
        day = day.add(const Duration(days: 1));
        continue;
      }
      // An away day is in the denominator whatever else was true of it.
      if (isAwayOn(key) &&
          (isStoodDownOn(key) ||
              conceded.contains(key) ||
              isRestDay(key))) {
        elapsed++;
      } else if (!isAwayOn(key) &&
          isRestDay(key) &&
          phantomWeightOn(room, key) != 0) {
        // daysElapsedIn excused this day because this member's own linked
        // habits asked nothing of it. The ROOM still did: a slot they never
        // linked wants something every day it is open, so the day is theirs
        // to answer for and belongs back in the denominator. Without this,
        // an unlinked slot could be dodged simply by resting.
        elapsed++;
      }
      day = day.add(const Duration(days: 1));
    }
    return elapsed;
  }

  /// 0.0-1.0 - the number the board ranks by. See the section comment above.
  double roomProgressRatio(RoomModel room) {
    final elapsed = roomDaysElapsedIn(room);
    // Same reading as [progressRatio]: an all-rest window asked nothing, a
    // paused or stood-down one keeps its zero. In a shared room this is
    // rarely reached at all, because an unlinked slot's phantom puts those
    // days straight back into the denominator above.
    if (elapsed <= 0) return _liveDaysIn(room).allRest ? 1.0 : 0.0;
    return (roomDaysCompleted(room) / elapsed).clamp(0.0, 1.0);
  }

  /// How much of [room]'s plan this member carries TODAY: linked, live slots
  /// over the plan's live slots. What the board prints beside the score so a
  /// smaller plan is visible rather than a silent advantage. Null for an
  /// 'own'-mode room, where there is no shared plan to be a fraction of.
  ({int linked, int total})? planCoverageIn(RoomModel room) {
    if (room.habitMode != RoomHabitMode.shared) return null;
    final shared = room.sharedHabits;
    var linked = 0;
    var total = 0;
    for (var i = 0; i < shared.length; i++) {
      if (shared[i].isRemoved) continue;
      total++;
      if (i < linkedHabitIds.length && linkedHabitIds[i] != kDeclinedSlot) {
        linked++;
      }
    }
    return (linked: linked, total: total);
  }

  /// Consecutive unbroken days counting backward from "now", for the
  /// leaderboard's streak badge. Never looks earlier than [RoomModel.
  /// startDate], and is always 0 before anything is linked.
  ///
  /// A day keeps a streak if it was genuinely finished, OR if it sits inside a
  /// week whose weekly quota was satisfied (see [quotaOkWeeks]) on a plan made
  /// only of weekly habits. That second clause IS the flexible-quota rule.
  ///
  /// The plan check is the one [scheduledCountFor] and [quotaWeekIsLost] make,
  /// for the same reason: quotaOkWeeks attests to the weekly habits and to
  /// nothing else (the grader skips every non-weekly habit before deciding a
  /// week held), so it cannot speak for a daily habit sharing the plan.
  /// Without it, room ELQVF8 on 2026-09-11 showed Hoor a 7-day streak at 02:30
  /// with both daily habits still owed, and would have kept showing 7 once
  /// the day ended blank. A weekly habit's own rest days on a mixed plan still
  /// keep the streak through the first clause: the sync stores the daily
  /// habits' count on those days, so isFullyDone answers them.
  ///
  /// Both inputs fail safe: [isFullyDone] reads stored counts (absent = not
  /// done) and [quotaOkWeeks] is an explicit allow-list (absent = not
  /// excused). So a participant whose device hasn't synced scores 0, never a
  /// phantom streak.
  bool _keepsStreak(String dateKey, DateTime day) {
    if (isFullyDone(dateKey)) return true;
    return quotaOkWeeks.contains(day.startOfDisplayWeek.toDateKey()) &&
        _everyCountedHabitIsWeeklyOn(dateKey);
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
  ///
  /// [now] is injectable for the same reason [RoomModel.lastCountedDayAt] is:
  /// a live room's streak turns on which day is today, and a test pinned to
  /// real dates cannot otherwise reach the unfinished-today branch. Both
  /// callers pass nothing.
  int currentStreak(RoomModel room, {DateTime? now}) {
    if (!hasCountedHabits) return 0;
    final clock = now ?? DateTime.now();
    var day = room.lastCountedDayAt(clock);
    // RoomModel.isEnded, read at the same clock.
    final end = room.endDate;
    final roomEnded = end != null && clock.effectiveDay.isAfter(end);
    if (!roomEnded &&
        !isStoodDownOn(day.toDateKey()) &&
        !_keepsStreak(day.toDateKey(), day)) {
      day = day.subtract(const Duration(days: 1));
    }
    var count = 0;
    // Floors at the day THEY joined, not the room's start — a streak can't
    // run back through days they weren't here for. See [countedStartIn].
    final floor = countedStartIn(room);
    while (!day.isBefore(floor)) {
      final key = day.toDateKey();
      // A stood-down day is TRANSPARENT here: it does not extend the streak
      // and it does not end it, so the walk passes straight through the gap.
      //
      // Held rather than reset, and held rather than grown, is the only
      // reading consistent with the rest of [standDownDays]: the day is
      // excluded from both sides of the percentage, and a streak is the same
      // question asked consecutively. Resetting would put the whole penalty
      // the stand-down rule exists to remove back on the one number people
      // actually look at; counting it would pay a streak for days nobody
      // trained. Note the gap is visible either way — the leaderboard row
      // carries a pause badge for as long as it lasts.
      if (isStoodDownOn(key)) {
        day = day.subtract(const Duration(days: 1));
        continue;
      }
      if (!_keepsStreak(key, day)) break;
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
      // Absent means "nothing was ever stood down", never "everything was" —
      // the same fail-safe direction as quotaOkWeeks. See standDownDays.
      standDownDays:
          (d['standDownDays'] as List?)?.whereType<String>().toList() ??
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
      teamStreakClaims: [
        for (final v in d['teamStreakClaims'] as List? ?? const [])
          if (v is num) v.toInt(),
      ],
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
      lastSyncedAt: (d['lastSyncedAt'] as Timestamp?)?.toDate(),
      // Absent on every doc written before departures were kept, which
      // reads as "in the room, never left" - exactly what was true of every
      // doc that existed then, since leaving used to delete it.
      leftAt: (d['leftAt'] as Timestamp?)?.toDate(),
      awaySpans: RoomModel.spansFrom(d['awaySpans']),
      slotDeclinedFrom: _slotKeyedStrings(d['slotDeclinedFrom']),
      slotDeclinedSpans: {
        for (final e in ((d['slotDeclinedSpans'] as Map?) ?? const {}).entries)
          if (int.tryParse(e.key.toString()) case final int i)
            i: RoomModel.spansFrom(e.value),
      },
      slotPriorHabitIds: _slotKeyedStrings(d['slotPriorHabitIds']),
    );
  }

  /// `{ "2": "..." }` -> `{2: "..."}`, dropping anything that is not a slot
  /// index with a string under it.
  static Map<int, String> _slotKeyedStrings(Object? raw) => {
        if (raw is Map)
          for (final e in raw.entries)
            if (int.tryParse(e.key.toString()) case final int i)
              if (e.value is String && (e.value as String).isNotEmpty)
                i: e.value as String,
      };

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
        'standDownDays': standDownDays,
        'habitRules': habitRules.map(
          (k, v) => MapEntry(k, v.map((r) => r.toFirestore()).toList()),
        ),
        'lastUpdated': Timestamp.fromDate(lastUpdated),
        'teamBonusClaimed': teamBonusClaimed,
        // teamStreakClaims is deliberately NOT here. The only writer is the
        // arrayUnion inside RoomsController.claimTeamStreakBonus, so no
        // whole-document set or merge built from a stale snapshot can ever
        // carry an older list back over a claim that just landed. Absent
        // reads as empty, which is what a fresh participant is anyway.
        'podiumBonusClaimed': podiumBonusClaimed,
        'allDoneToday': allDoneToday,
        if (allDoneDate != null) 'allDoneDate': allDoneDate,
        'notificationsMuted': notificationsMuted,
        if (lastSyncedDay != null) 'lastSyncedDay': lastSyncedDay,
        if (lastSyncedAt != null)
          'lastSyncedAt': Timestamp.fromDate(lastSyncedAt!),
        if (leftAt != null) 'leftAt': Timestamp.fromDate(leftAt!),
        if (awaySpans.isNotEmpty)
          'awaySpans': [
            for (final s in awaySpans) {'from': s.from, 'to': s.to},
          ],
        if (slotDeclinedFrom.isNotEmpty)
          'slotDeclinedFrom': {
            for (final e in slotDeclinedFrom.entries) '${e.key}': e.value,
          },
        if (slotDeclinedSpans.isNotEmpty)
          'slotDeclinedSpans': {
            for (final e in slotDeclinedSpans.entries)
              '${e.key}': [
                for (final s in e.value) {'from': s.from, 'to': s.to},
              ],
          },
        if (slotPriorHabitIds.isNotEmpty)
          'slotPriorHabitIds': {
            for (final e in slotPriorHabitIds.entries) '${e.key}': e.value,
          },
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
    List<String>? standDownDays,
    Map<String, List<RoomHabitRule>>? habitRules,
    DateTime? lastUpdated,
    bool? teamBonusClaimed,
    List<int>? teamStreakClaims,
    bool? podiumBonusClaimed,
    bool? allDoneToday,
    String? allDoneDate,
    bool? notificationsMuted,
    String? lastSyncedDay,
    DateTime? lastSyncedAt,
    Map<String, int>? inferredScheduledCount,
    DateTime? leftAt,
    bool clearLeftAt = false,
    List<({String from, String to})>? awaySpans,
    Map<int, String>? slotDeclinedFrom,
    Map<int, List<({String from, String to})>>? slotDeclinedSpans,
    Map<int, String>? slotPriorHabitIds,
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
        standDownDays: standDownDays ?? this.standDownDays,
        habitRules: habitRules ?? this.habitRules,
        lastUpdated: lastUpdated ?? this.lastUpdated,
        teamBonusClaimed: teamBonusClaimed ?? this.teamBonusClaimed,
        teamStreakClaims: teamStreakClaims ?? this.teamStreakClaims,
        podiumBonusClaimed: podiumBonusClaimed ?? this.podiumBonusClaimed,
        allDoneToday: allDoneToday ?? this.allDoneToday,
        allDoneDate: allDoneDate ?? this.allDoneDate,
        notificationsMuted: notificationsMuted ?? this.notificationsMuted,
        lastSyncedDay: lastSyncedDay ?? this.lastSyncedDay,
        lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
        inferredScheduledCount:
            inferredScheduledCount ?? this.inferredScheduledCount,
        leftAt: clearLeftAt ? null : (leftAt ?? this.leftAt),
        awaySpans: awaySpans ?? this.awaySpans,
        slotDeclinedFrom: slotDeclinedFrom ?? this.slotDeclinedFrom,
        slotDeclinedSpans: slotDeclinedSpans ?? this.slotDeclinedSpans,
        slotPriorHabitIds: slotPriorHabitIds ?? this.slotPriorHabitIds,
      );
}

/// One member's place on a room's board: the participant, the number their
/// row shows, and whether anybody else is holding that same number.
///
/// [rank] is 1-based, and 0 means UNRANKED: a member the board has nothing
/// to say about yet, because their own percentage still reads 0%. See
/// [RoomLeaderboard.standings] for why that case is drawn as a dash rather
/// than as a position.
///
/// [shared] is what a tie is CALLED rather than just drawn as. First place
/// is the one place the board shows as a picture instead of a number, so a
/// shared first is two identical cups and a missing 2, with nothing saying
/// why. It is what the cup announces to a screen reader (see
/// S.roomPlaceFirstTied). Always false for an unranked member: nobody
/// shares a place that nobody has.
typedef RoomStanding = ({RoomParticipant participant, int rank, bool shared});

/// The one place a room decides who is ahead of whom, and by which number.
///
/// This used to be three separate derivations that each turned a list
/// POSITION into a rank: the leaderboard's `indexOf + 1`, the finale
/// podium's hard-coded 2/1/3 slots, and the prize section's `indexWhere +
/// 1`. All three read the same ordered list, so all three agreed only by
/// coincidence, and none of them could express the one thing a board most
/// needs to say: that two people are level.
extension RoomLeaderboard on RoomModel {
  /// [participants] ordered best first, each carrying the place its row
  /// should show.
  ///
  /// Places are COMPETITION places: members who are level share a place,
  /// and the next distinct score takes the place its position already gave
  /// it. Two people level at the top read 1, 1, 3, never 1, 1, 2. That is
  /// the whole point of this function: a shared first place is what puts
  /// the cup on both rows instead of handing one of them a silver 2 on the
  /// strength of an alphabetically smaller uid.
  ///
  /// LEVEL MEANS "THE SAME NUMBER ON SCREEN", and that is a deliberate
  /// choice rather than a shortcut. Every ranked surface prints
  /// `(progressRatio * 100).round()`, and each member divides by their own
  /// elapsed window ([RoomParticipant.daysElapsedIn]), so two people whose
  /// rows both read 86% are routinely 19/22 and 6/7: equal to the eye,
  /// unequal in the fourth decimal. Ranking on the raw double would have
  /// left exactly the reported bug in place, one cup between two rows
  /// showing the same percentage. The percentage is the number the board
  /// makes its promise with, so it is the number the places are grouped
  /// by. The raw ratio still breaks the order INSIDE a group, so the
  /// stronger of two equal-reading members is still drawn first.
  ///
  /// 0% IS NOT A PLACE. A member whose percentage still reads 0 is
  /// unranked (rank 0), whether that is the whole room on day one or one
  /// member who has not started. Without this, the shared-place rule turns
  /// the two most-viewed states of a room, the lobby and day one, into a
  /// column of identical trophies for work nobody has done yet. It also
  /// closes a payout that should never have existed: an ended room where
  /// nobody did anything has no rank 1, so
  /// [RoomsController.podiumPrizeFor] has nothing to pay.
  ///
  /// The uid tie-break is kept from the sort this replaces. List.sort is
  /// unstable above 32 elements and level members are the common case, so
  /// without a stable last key the rows, and any number derived from their
  /// order, visibly reshuffle on every participants-stream rebuild with
  /// nobody's score having changed.
  /// The share of the room's elapsed days a member must have been counted
  /// for before they can hold a PLACE. Their score is still computed and
  /// shown; only the rank, the cup and the podium prize wait for tenure.
  ///
  /// The minimum-games-played rule every real league has, and the one this
  /// board was missing. A member is measured only from the day they joined
  /// (countedStartIn, correctly, so a late joiner is not swamped by days
  /// they were never in), which means a member who joins on the FINAL day
  /// and finishes that one day reads 100% - and outranked 29 perfect days of
  /// 30. Measured on 2026-09-09: the one-day sniper took the cup and 200 XP
  /// from a 97% member. The team bonus already refuses this exact move
  /// ([teamIsPerfect]'s tenure clause); the competitive board and the podium
  /// never did.
  ///
  /// The thresholds live on [RoomModel] itself ([RoomModel.kPlaceTenureFraction],
  /// [RoomModel.kPlaceTenureCapDays]); an extension's statics are only
  /// reachable through the extension's own name, which nothing else should
  /// have to know.
  ///
  /// Whether [p] has been in this room long enough to hold a place.
  ///
  /// Tenure is PRESENCE, the calendar days from their first counted day to
  /// the last one graded, not [RoomParticipant.daysElapsedIn]. That one
  /// excuses stood-down and conceded days from the denominator, which is
  /// right for a score and wrong here: a member who paused a habit for a
  /// week was in the room that week, and a pause is a stand-down, not a
  /// shorter membership. Away days count too: they sit in the denominator
  /// and score zero, a worse standing rather than a shorter one, so leaving
  /// and coming back cannot dodge this in either direction.
  bool holdsPlaceIn(RoomParticipant p) {
    var required = (daysElapsed * RoomModel.kPlaceTenureFraction).ceil();
    if (required > RoomModel.kPlaceTenureCapDays) {
      required = RoomModel.kPlaceTenureCapDays;
    }
    if (required < 1) required = 1;
    final start = p.countedStartIn(this);
    final last = lastCountedDay;
    final present = last.isBefore(start) ? 1 : last.difference(start).inDays + 1;
    return present >= required;
  }

  /// The roster a surface that scores [graded] may read: as handed while the
  /// room runs, and every member [RoomParticipant.asRecorded] once it has
  /// ended at [now] (this device's clock when omitted).
  ///
  /// gradedRoomParticipantsProvider infers closed quota weeks on top of the
  /// record, and an ended room's finale pays its podium from the places
  /// [standings] draws from this list: RoomsController.claimPodiumBonus
  /// re-checks the end, the flag, the member count and tenure, never the
  /// rank. The inference returns nothing for a room that has ended on any
  /// clock, but a list graded before the end is kept until a stream emits,
  /// so the switch is made again here, where the places are drawn.
  List<RoomParticipant> scoringRoster(
    List<RoomParticipant> graded, {
    DateTime? now,
  }) =>
      isEndedAt(now ?? DateTime.now())
          ? [for (final p in graded) p.asRecorded]
          : graded;

  List<RoomStanding> standings(List<RoomParticipant> participants) {
    // Scored once per member rather than once per comparison. progressRatio
    // walks every counted day of the room and a sort asks for it O(n log n)
    // times, but the real reason is agreement: the ordering and the "are
    // these two level" test read the same two numbers, so they cannot
    // disagree about who is level with whom.
    final percents = <String, int>{};
    final ratios = <String, double>{};
    for (final p in participants) {
      // The room score, not the member's own number: the one yardstick that
      // means the same thing on every row. See RoomParticipant.roomCreditFor.
      final ratio = p.roomProgressRatio(this);
      ratios[p.uid] = ratio;
      percents[p.uid] = (ratio * 100).round();
    }
    int percentOf(RoomParticipant p) => percents[p.uid] ?? 0;
    double ratioOf(RoomParticipant p) => ratios[p.uid] ?? 0;
    // 0% is not a place, and neither is a day (see [holdsPlaceIn]). Decided
    // once here so the sort and the numbering below cannot disagree.
    final eligible = <String, bool>{
      for (final p in participants)
        p.uid: percentOf(p) > 0 && holdsPlaceIn(p),
    };
    bool placedOf(RoomParticipant p) => eligible[p.uid] ?? false;

    final sorted = [...participants]..sort((a, b) {
      // Members who hold a place come first, whatever their number: a
      // one-day joiner reading 100% sits below the cup-holder at 97%, not
      // above them with no cup, which reads as a board that forgot to draw
      // one. 0% rows already sorted last for the same reason.
      final byPlaced = (placedOf(b) ? 1 : 0).compareTo(placedOf(a) ? 1 : 0);
      if (byPlaced != 0) return byPlaced;
      final byPercent = percentOf(b).compareTo(percentOf(a));
      if (byPercent != 0) return byPercent;
      final byRatio = ratioOf(b).compareTo(ratioOf(a));
      return byRatio != 0 ? byRatio : a.uid.compareTo(b.uid);
    });

    final placed = <({RoomParticipant participant, int rank})>[];
    var place = 0;
    var placedSoFar = 0;
    int? previous;
    for (final p in sorted) {
      if (!placedOf(p)) {
        placed.add((participant: p, rank: 0));
        continue;
      }
      final percent = percentOf(p);
      // Only a genuinely different percentage moves the number on, and it
      // moves it to the position AMONG THE PLACED, not to the next integer:
      // that is what makes the place after a two-way tie for first a 3. The
      // position is counted over placed members only, so an unplaced row
      // never consumes a number nobody was given.
      if (percent != previous) place = placedSoFar + 1;
      placedSoFar++;
      placed.add((participant: p, rank: place));
      previous = percent;
    }

    // Who is sharing. Counted over the finished list rather than tracked
    // inside the loop above, because a tie is only visible once the LAST
    // member of it has been seen: the first of two equals is level with
    // somebody who has not been reached yet.
    final held = <int, int>{};
    for (final m in placed) {
      held[m.rank] = (held[m.rank] ?? 0) + 1;
    }
    return [
      for (final m in placed)
        (
          participant: m.participant,
          rank: m.rank,
          shared: m.rank > 0 && (held[m.rank] ?? 0) > 1,
        ),
    ];
  }
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
  /// "everyone did every single day" ceiling. This is the number the team
  /// card's progress bar fills to: a room where everyone's been perfect
  /// reads 100%, same as any one person's own
  /// [RoomParticipant.progressRatio] would.
  ///
  /// The ceiling is the SUM OF EACH MEMBER'S OWN [RoomParticipant
  /// .daysElapsedIn], not `participants.length * daysElapsed`, and that
  /// distinction is the whole correctness of this number. Every excusing
  /// rule in this file lives inside `daysElapsedIn`: a room pause, a late
  /// join ([countedStartIn]), a conceded rest day, and a stand-down
  /// stretch. A flat `length * daysElapsed` ceiling knows about none of
  /// them, so it counted days no member was ever asked about.
  ///
  /// The stand-down case was the one that actually bit. Two members both
  /// reading a true 100% on their own rows, one of whom had paused their
  /// only habit, produced a team card of 74%. Worse, [teamIsPerfect] is an
  /// all-history `>= 1.0` check and gates the bonus button, so a single
  /// paused stretch made `RoomsController.claimTeamBonus` permanently
  /// unreachable for that room — it did not heal on resume, because the
  /// dead days stayed in the denominator forever. Pausing a habit is
  /// supposed to hold a percentage still, and it does on the member's own
  /// row; the team card was the one surface still punishing it.
  ///
  /// This is the same fix [RoomModel.daysElapsed] already documents for
  /// ROOM-level pauses ("88% per member above 47% for the team"), finally
  /// extended to the per-participant ones.
  double teamProgressRatio(List<RoomParticipant> participants) {
    if (participants.isEmpty) return 0;
    final maxPossible = teamMaxPossibleDays(participants);
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

  /// The denominator behind [teamProgressRatio] — each member's own
  /// elapsed days, summed, so the card's "14 of 20" agrees with its own
  /// percentage. See [teamProgressRatio] for why this is not
  /// `participants.length * daysElapsed`.
  int teamMaxPossibleDays(List<RoomParticipant> participants) =>
      participants.fold<int>(0, (sum, p) => sum + p.daysElapsedIn(this));

  /// True the moment *every* participant has fully credited today — the
  /// one binary "did the whole team show up" signal, distinct from the
  /// gradual [teamProgressRatio]. Requires at least one participant to have
  /// linked something; an empty room is never "complete."
  bool teamCompletedToday(List<RoomParticipant> participants) {
    if (participants.isEmpty) return false;
    final today = lastCountedDay.toDateKey();
    return participants.every((p) => p.isFullyDone(today));
  }

  /// True once the team has never missed a credited day: every participant
  /// individually perfect, and every participant present since
  /// [RoomModel.startDate]. The bar [RoomCompeteMode.team]'s bonus asks for
  /// (see RoomsController.claimTeamBonus), deliberately harder than
  /// [teamCompletedToday], which only ever looks at today.
  ///
  /// NOT `teamProgressRatio >= 1.0`, and the difference is a real payout.
  /// The ratio's ceiling is each member's own [RoomParticipant.daysElapsedIn]
  /// (see [teamProgressRatio] for why it must be), and that is exactly what
  /// a one-day-old member has: one day. Deriving the gate from the ratio
  /// therefore let somebody join an already-perfect room, finish a single
  /// day, and unlock 150 XP and 75 gold on the strength of other people's
  /// months — repeatably, because leaveRoom deletes the participant doc that
  /// holds `teamBonusClaimed` and rejoining re-stamps `joinedAt`. The flat
  /// ceiling this replaced happened to block that by swamping the joiner,
  /// and blocking it was the only thing it did right.
  ///
  /// Two separate requirements, because they fail for opposite reasons:
  ///
  ///  - **Perfect**, per member, through their own [progressRatio]. Summing
  ///    across members and clamping only the total let one member's
  ///    overshoot subsidise another's genuine miss (reachable: a conceded
  ///    rest day carrying a جزئي square leaves the denominator while its 0.5
  ///    stays in the numerator). Asking each member separately makes a
  ///    subsidy unrepresentable.
  ///  - **Tenure**, so a newcomer cannot inherit the room's history. This is
  ///    the guard [RoomsController.claimPodiumBonus] already carries in its
  ///    own form, and the one this gate was missing.
  ///
  /// A member who paused still passes: their stand-down days leave both
  /// sides of their own ratio, which is the whole point of standDownDays and
  /// the reason this stopped being `>= 1.0` on a flat ceiling. Likewise a
  /// member who spent their weekly rest allowance reads 1.0 — the app's
  /// stated position (see [kRestConcessionsPerWeek]) is that six honest days
  /// of seven IS a full week, and the team gate agrees with the row rather
  /// than holding a stricter private opinion.
  bool teamIsPerfect(List<RoomParticipant> participants) {
    if (participants.isEmpty) return false;
    return participants.every(
      (p) =>
          !p.countedStartIn(this).isAfter(startDate) &&
          p.progressRatio(this) >= 1.0,
    );
  }

  // ─── Team day ──────────────────────────────────────────────────────────
  //
  // The cooperative reading of a team room (RoomCompeteMode.team), built
  // 2026-09-06. The unit of success is the room's DAY, not a person's rank:
  // the team wins a day when every member who was asked something that day
  // finished it, and wins in a row are the team streak. The old rule above,
  // one bonus for every member perfect over the whole room, was reachable
  // in theory and never in practice; these are meant to be won every week.
  //
  // "Asked something that day" is the same door every other excuse in this
  // file uses: a member counts on a day only once they had joined
  // (countedStartIn), while the room is not paused, while they are not
  // stood down, and while they have something linked. A day nobody was
  // asked about is neither won nor lost and does not break a streak, so an
  // extension's pause or everyone pausing together leaves the streak where
  // it was, the same score-neutral promise RoomModel.daysElapsed makes.

  /// Whether [p] was asked for anything on [day] ([dateKey] is its key).
  bool memberCountsOn(RoomParticipant p, String dateKey, DateTime day) =>
      p.hasCountedHabits &&
      !p.countedStartIn(this).isAfter(day) &&
      !isPausedOn(dateKey) &&
      !p.isStoodDownOn(dateKey) &&
      // Out of the room that day (RoomParticipant.awaySpans / leftAt): not
      // on the team, so they neither win nor lose it the day. Without this a
      // rejoiner's away stretch turned every won team day in it into a lost
      // one, and the days before a departure are kept exactly as they were
      // played - the team's history is not rewritten by someone leaving.
      !p.isAwayOn(dateKey);

  /// The team's result for one day: true when everyone who counted that
  /// day finished, false when someone who counted did not, null when
  /// nobody counted at all (the day is skipped, not lost). A rest day a
  /// weekly quota granted reads as finished, exactly as it does on the
  /// member's own row.
  bool? teamDayResult(
    String dateKey,
    DateTime day,
    List<RoomParticipant> participants,
  ) {
    var counted = 0;
    for (final p in participants) {
      if (!memberCountsOn(p, dateKey, day)) continue;
      counted++;
      if (!p.isFullyDone(dateKey)) return false;
    }
    return counted == 0 ? null : true;
  }

  /// Days the team won and days that counted at all, [startDate] through
  /// [lastCountedDay]. The finale's "you won 24 of 30 days together".
  ({int won, int counted}) teamDays(List<RoomParticipant> participants) {
    var won = 0;
    var counted = 0;
    var day = startDate;
    final last = lastCountedDay;
    while (!day.isAfter(last)) {
      final r = teamDayResult(day.toDateKey(), day, participants);
      if (r != null) {
        counted++;
        if (r) won++;
      }
      day = day.add(const Duration(days: 1));
    }
    return (won: won, counted: counted);
  }

  /// Consecutive won days ending on [lastCountedDay]; skipped days do not
  /// break it. While the room is live, a today that is not yet won is a
  /// day in progress rather than a miss, so it is stepped over and the
  /// card keeps showing yesterday's streak until today closes without
  /// everyone. Once today IS won the number rises on the spot, which is
  /// the moment worth celebrating. On an ended room the last day is final
  /// and a miss there ends the streak like any other.
  int teamStreak(List<RoomParticipant> participants) {
    var streak = 0;
    var day = lastCountedDay;
    final inProgress = !isEnded;
    while (!day.isBefore(startDate)) {
      final r = teamDayResult(day.toDateKey(), day, participants);
      if (r == false && !(inProgress && day == lastCountedDay)) break;
      if (r == true) streak++;
      day = day.subtract(const Duration(days: 1));
    }
    return streak;
  }

  /// [teamStreak] as [member] has lived it: the current run of won days
  /// ending on [lastCountedDay], counting only days the member was asked
  /// about. What "days to go" on the milestone row counts down from, since
  /// a milestone is earned by a run WITH this member in it, and a newcomer
  /// two days into a team streak of six is two days in, not six.
  int teamStreakWith(
    RoomParticipant member,
    List<RoomParticipant> participants,
  ) {
    var streak = 0;
    var day = lastCountedDay;
    final inProgress = !isEnded;
    while (!day.isBefore(startDate)) {
      final key = day.toDateKey();
      final r = teamDayResult(key, day, participants);
      if (r == false && !(inProgress && day == lastCountedDay)) break;
      if (r == true && memberCountsOn(member, key, day)) streak++;
      day = day.subtract(const Duration(days: 1));
    }
    return streak;
  }

  /// The longest run of won days [member] was part of: the tenure guard
  /// for milestone claims, in the same spirit as [teamIsPerfect]'s. A
  /// newcomer inherits nothing from a streak that ran before they joined,
  /// and a member excused for a day (stood down) neither extends nor
  /// breaks their own run on it.
  int teamBestStreakWith(
    RoomParticipant member,
    List<RoomParticipant> participants,
  ) {
    var best = 0;
    var run = 0;
    var day = startDate;
    final last = lastCountedDay;
    while (!day.isAfter(last)) {
      final key = day.toDateKey();
      final r = teamDayResult(key, day, participants);
      if (r == false) {
        run = 0;
      } else if (r == true && memberCountsOn(member, key, day)) {
        run++;
        if (run > best) best = run;
      }
      day = day.add(const Duration(days: 1));
    }
    return best;
  }

  /// The team milestone [member] can claim now, or null: the first of
  /// [RoomTeamProgress.teamMilestones] not in their teamStreakClaims, once
  /// [teamBestStreakWith] over [history] has reached it. What the team
  /// card's Claim button pays on; RoomsController.claimTeamStreakBonus
  /// guards only the double payment.
  ///
  /// Graded on the record whichever roster it is handed: every member is
  /// read [RoomParticipant.asRecorded], without the closed quota weeks the
  /// board infers on top (RoomParticipant.closedQuotaWeekInference). A team
  /// day turns on WHICH day was a rest, and the inference can rest a
  /// different day from the member's own phone, so over the board's roster
  /// a run can reach a milestone that neither the record nor that phone
  /// ever reaches.
  int? claimableTeamMilestone(
    RoomParticipant member,
    List<RoomParticipant> history,
  ) {
    for (final m in RoomTeamProgress.teamMilestones) {
      if (member.teamStreakClaims.contains(m)) continue;
      final best = teamBestStreakWith(
        member.asRecorded,
        [for (final p in history) p.asRecorded],
      );
      return best >= m ? m : null;
    }
    return null;
  }

  /// The team card's milestone row for [member]: the milestone its Claim
  /// button pays ([claimableTeamMilestone]), otherwise the next one to
  /// reach, and the current run its days-to-go counts from. All three read
  /// the record, whichever rosters [participants] and [history] hold: the
  /// button pays, and the countdown counts toward the claim it promises.
  ({int? claimable, int? next, int current}) teamMilestoneRowFor(
    RoomParticipant member,
    List<RoomParticipant> participants,
    List<RoomParticipant> history,
  ) {
    final claimable = claimableTeamMilestone(member, history);
    int? next;
    if (claimable == null) {
      for (final m in RoomTeamProgress.teamMilestones) {
        if (member.teamStreakClaims.contains(m)) continue;
        next = m;
        break;
      }
    }
    return (
      claimable: claimable,
      next: next,
      current: teamStreakWith(
        member.asRecorded,
        [for (final p in participants) p.asRecorded],
      ),
    );
  }

  /// The longest run of won days the team ever had, member-agnostic: the
  /// finale's "longest run" pill.
  int teamBestStreak(List<RoomParticipant> participants) {
    var best = 0;
    var run = 0;
    var day = startDate;
    final last = lastCountedDay;
    while (!day.isAfter(last)) {
      final r = teamDayResult(day.toDateKey(), day, participants);
      if (r == false) {
        run = 0;
      } else if (r == true) {
        run++;
        if (run > best) best = run;
      }
      day = day.add(const Duration(days: 1));
    }
    return best;
  }

  /// The three team-streak milestones, and what each pays every member,
  /// once. Sized against the podium prizes (200/120/80 XP for a race):
  /// thirty days of everyone finishing is harder than winning a race, so
  /// it pays more than first place.
  static const List<int> teamMilestones = [7, 14, 30];

  static ({int xp, int gold}) teamMilestonePrize(int days) => switch (days) {
        7 => (xp: 60, gold: 30),
        14 => (xp: 120, gold: 60),
        30 => (xp: 250, gold: 125),
        _ => (xp: 0, gold: 0),
      };

  /// The next milestone above [streak], or null past the last one.
  static int? teamNextMilestone(int streak) {
    for (final m in teamMilestones) {
      if (streak < m) return m;
    }
    return null;
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
