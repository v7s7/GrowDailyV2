import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/extensions/datetime_ext.dart';
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
class RoomHabitTemplate {
  final String name;
  final HabitCategory category;
  final String? iconColorHex;
  final HabitFrequencyType frequencyType;
  final int frequencyTarget;

  const RoomHabitTemplate({
    required this.name,
    required this.category,
    this.iconColorHex,
    required this.frequencyType,
    required this.frequencyTarget,
  });

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'category': category.toJson(),
        if (iconColorHex != null) 'iconColorHex': iconColorHex,
        'frequencyType': frequencyType.toJson(),
        'frequencyTarget': frequencyTarget,
      };

  factory RoomHabitTemplate.fromMap(Map<String, dynamic> d) =>
      RoomHabitTemplate(
        name: (d['name'] as String?) ?? '',
        category: HabitCategory.fromJson(d['category'] as String? ?? 'custom'),
        iconColorHex: d['iconColorHex'] as String?,
        frequencyType:
            HabitFrequencyType.fromJson(d['frequencyType'] as String? ?? 'daily'),
        frequencyTarget: d['frequencyTarget'] as int? ?? 1,
      );
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

  /// Denormalized headcount so a "my rooms" list can show it without a
  /// second read per room - kept in sync by RoomsController.joinRoom/
  /// leaveRoom via FieldValue.increment.
  final int memberCount;

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
    this.memberCount = 1,
  });

  bool get isEnded {
    final end = endDate;
    return end != null && DateTime.now().effectiveDay.isAfter(end);
  }

  /// The last day progress counts toward this room - today, unless the room
  /// already ended (a room that ended 3 days ago shouldn't keep crediting
  /// completions logged after the fact).
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
    return last.difference(startDate).inDays + 1;
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
              .map((m) => RoomHabitTemplate.fromMap(Map<String, dynamic>.from(m)))
              .toList() ??
          const [],
      duration: RoomDuration.fromJson(d['duration'] as String?),
      startDate: (d['startDate'] as Timestamp?)?.toDate() ??
          DateTime.now().effectiveDay,
      endDate: (d['endDate'] as Timestamp?)?.toDate(),
      memberCount: (d['memberCount'] as int?) ?? 1,
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
        'memberCount': memberCount,
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
  final DateTime lastUpdated;

  const RoomParticipant({
    required this.uid,
    required this.displayName,
    required this.characterId,
    this.accessoryId,
    required this.joinedAt,
    this.linkedHabitIds = const [],
    this.linkedHabitNames = const [],
    this.hideDetails = false,
    this.dailyDoneCount = const {},
    this.dailyScheduledCount = const {},
    required this.lastUpdated,
  });

  /// How many of [linkedHabitIds] actually counted toward [dateKey] - the
  /// real denominator for that day, not just linkedHabitIds.length. Falls
  /// back to linkedHabitIds.length when this day has no recorded value:
  /// either every linked habit really was scheduled that day (the sync
  /// only writes an entry when something was excused, to keep the doc
  /// small - see [dailyScheduledCount]'s doc comment), or this is a
  /// participant doc from before scheduling-awareness existed and simply
  /// hasn't resynced yet (same self-healing pattern as [dailyDoneCount]
  /// itself for a pre-existing field).
  int scheduledCountFor(String dateKey) =>
      dailyScheduledCount[dateKey] ?? linkedHabitIds.length;

  /// This participant's completion credit for [dateKey] - 0.0 to 1.0,
  /// proportional to how many of that day's actually-scheduled linked
  /// habits (see [scheduledCountFor]) were done (1 of 2 -> 0.5, 2 of 2 ->
  /// 1.0). A day where nothing was scheduled at all (every linked habit
  /// excused) is full credit, not zero - there was nothing to fall short
  /// of. 0 whenever nothing is linked yet, since there's nothing to divide
  /// by.
  double creditFor(String dateKey) {
    if (linkedHabitIds.isEmpty) return 0;
    final scheduled = scheduledCountFor(dateKey);
    if (scheduled == 0) return 1.0;
    final done = dailyDoneCount[dateKey] ?? 0;
    return (done / scheduled).clamp(0.0, 1.0);
  }

  /// Whether *every actually-scheduled* linked habit was done on [dateKey]
  /// - the strict "full credit" case, used where a screen wants a plain
  /// done/not-done signal (e.g. the checkmark in Room Detail's "Your plan"
  /// card) rather than the underlying fraction. Trivially true on a day
  /// nothing was scheduled at all - see [creditFor]'s doc comment.
  bool isFullyDone(String dateKey) {
    if (linkedHabitIds.isEmpty) return false;
    final scheduled = scheduledCountFor(dateKey);
    if (scheduled == 0) return true;
    return (dailyDoneCount[dateKey] ?? 0) >= scheduled;
  }

  /// Total credited days within [room]'s active window (start date through
  /// today, or the room's end date once it's passed) - a fractional sum,
  /// not a plain count: a day with 1 of 2 linked habits done contributes
  /// 0.5, not 0 or 1 (see [creditFor]). A date logged before the room
  /// started, or after it ended, never counts.
  double daysCompleted(RoomModel room) {
    var total = 0.0;
    var day = room.startDate;
    final last = room.lastCountedDay;
    while (!day.isAfter(last)) {
      total += creditFor(day.toDateKey());
      day = day.add(const Duration(days: 1));
    }
    return total;
  }

  /// 0.0-1.0 completion ratio for [room] - the number every leaderboard row
  /// sorts and renders by.
  double progressRatio(RoomModel room) {
    final elapsed = room.daysElapsed;
    if (elapsed <= 0) return 0;
    return (daysCompleted(room) / elapsed).clamp(0.0, 1.0);
  }

  /// Consecutive fully-credited days (see [isFullyDone]) counting backward
  /// from "now," for the leaderboard's streak badge. Because [isFullyDone]
  /// already treats a day nothing was scheduled on as satisfied, a Mon/Wed-
  /// only habit's off-days don't interrupt this either - the streak only
  /// ever breaks on a real miss. Never looks earlier than [RoomModel.
  /// startDate], and is always 0 before anything is linked.
  ///
  /// While the room is still running, an unfinished *today* doesn't zero
  /// this out - there's still time left, so this looks at whether yesterday
  /// keeps the streak alive instead of declaring it broken mid-day. Once
  /// the room has ended, though, its last countable day (room.lastCountedDay,
  /// a fixed calendar date at that point) is final - if that day wasn't
  /// completed, the streak the room ended on is 0, same as any habit streak
  /// that lapses.
  int currentStreak(RoomModel room) {
    if (linkedHabitIds.isEmpty) return 0;
    var day = room.lastCountedDay;
    if (!room.isEnded && !isFullyDone(day.toDateKey())) {
      day = day.subtract(const Duration(days: 1));
    }
    var count = 0;
    while (!day.isBefore(room.startDate) && isFullyDone(day.toDateKey())) {
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
      characterId: (d['characterId'] as String?) ?? 'male_ghutra_blue',
      accessoryId: d['accessoryId'] as String?,
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
      lastUpdated: (d['lastUpdated'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'uid': uid,
        'displayName': displayName,
        'characterId': characterId,
        if (accessoryId != null) 'accessoryId': accessoryId,
        'joinedAt': Timestamp.fromDate(joinedAt),
        'linkedHabitIds': linkedHabitIds,
        'linkedHabitNames': linkedHabitNames,
        'hideDetails': hideDetails,
        'dailyDoneCount': dailyDoneCount,
        'dailyScheduledCount': dailyScheduledCount,
        'lastUpdated': Timestamp.fromDate(lastUpdated),
      };

  RoomParticipant copyWith({
    String? characterId,
    String? accessoryId,
    bool clearAccessory = false,
    List<String>? linkedHabitIds,
    List<String>? linkedHabitNames,
    bool? hideDetails,
    Map<String, int>? dailyDoneCount,
    Map<String, int>? dailyScheduledCount,
    DateTime? lastUpdated,
  }) =>
      RoomParticipant(
        uid: uid,
        displayName: displayName,
        characterId: characterId ?? this.characterId,
        accessoryId: clearAccessory ? null : (accessoryId ?? this.accessoryId),
        joinedAt: joinedAt,
        linkedHabitIds: linkedHabitIds ?? this.linkedHabitIds,
        linkedHabitNames: linkedHabitNames ?? this.linkedHabitNames,
        hideDetails: hideDetails ?? this.hideDetails,
        dailyDoneCount: dailyDoneCount ?? this.dailyDoneCount,
        dailyScheduledCount: dailyScheduledCount ?? this.dailyScheduledCount,
        lastUpdated: lastUpdated ?? this.lastUpdated,
      );
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
