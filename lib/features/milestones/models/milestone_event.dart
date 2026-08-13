import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/game_theme.dart';
import '../../achievements/models/achievement_model.dart';

/// What kind of meaningful moment a [MilestoneEvent] records — deliberately
/// coarse (see [MilestoneEvent]'s own doc comment) so this enum only ever
/// grows with things a human would want to see months later, never with a
/// per-completion or per-tap event.
enum MilestoneType {
  /// Synthetic only — built client-side from [UserAccountModel.createdAt]
  /// wherever a timeline needs a "day one" anchor (see JourneyPage). Never
  /// actually written to `users/{uid}/milestones`: account creation has no
  /// other event competing for that moment, so there's nothing this would
  /// add over just reading createdAt directly at render time.
  joined,
  levelUp,
  streakMilestone,
  perfectDay,
  perfectWeek,
  achievementUnlocked,

  /// A linked Room's shared goal was completed by every participant — see
  /// RoomsController (Rooms Alive Phase 1). Not yet wired (Phase 2 backend
  /// work is architecture-only for now), but modeled here already so the
  /// eventual write site only has to add one call, not design the schema.
  roomChallengeComplete;

  String toJson() => name;
  static MilestoneType fromJson(String? v) => values.firstWhere(
        (e) => e.name == v,
        orElse: () => levelUp,
      );

  IconData get icon => switch (this) {
        joined => Icons.flag_rounded,
        levelUp => Icons.bolt_rounded,
        streakMilestone => Icons.local_fire_department_rounded,
        perfectDay => Icons.star_rounded,
        perfectWeek => Icons.auto_awesome_rounded,
        achievementUnlocked => Icons.emoji_events_rounded,
        roomChallengeComplete => Icons.groups_rounded,
      };

  /// Per-type accent color — what [JourneyPage]'s row icons, the Life
  /// Timeline's per-year tally chips, and anywhere else a [MilestoneType]
  /// needs a color all read from. Originally written separately in each of
  /// those two screens as an identical private `_color` switch; pulled up
  /// here once the duplication was spotted, same reasoning as [icon] and
  /// [localizedName] already living on the enum rather than on whichever
  /// widget happens to render first.
  Color get color => switch (this) {
        joined => GameColors.emerald,
        levelUp => GameColors.gold,
        streakMilestone => GameColors.iconStreak,
        perfectDay => GameColors.success,
        perfectWeek => GameColors.iconXp,
        achievementUnlocked => GameColors.gold,
        roomChallengeComplete => GameColors.iconXp,
      };

  /// Generic per-type label — [milestoneHeadline] below builds the richer,
  /// data-filled sentence actually shown in the UI (e.g. "Reached Level
  /// 12" rather than just "Level Up"); this is the fallback for anywhere
  /// only the category itself matters (e.g. a Legacy Shelf tally row).
  String localizedName(bool isAr) => isAr
      ? switch (this) {
          joined => 'انضممت',
          levelUp => 'ارتقاء مستوى',
          streakMilestone => 'إنجاز سلسلة',
          perfectDay => 'يوم مثالي',
          perfectWeek => 'أسبوع مثالي',
          achievementUnlocked => 'إنجاز مفتوح',
          roomChallengeComplete => 'تحدي غرفة مكتمل',
        }
      : switch (this) {
          joined => 'Joined Grow Daily',
          levelUp => 'Level Up',
          streakMilestone => 'Streak Milestone',
          perfectDay => 'Perfect Day',
          perfectWeek => 'Perfect Week',
          achievementUnlocked => 'Achievement Unlocked',
          roomChallengeComplete => 'Room Challenge Complete',
        };
}

/// One meaningful, dated moment in a user's GrowDaily history — the single
/// source of truth [JourneyPage] renders directly, [MonthlyStoryScreen]
/// counts against a date range, and the Legacy Shelf tallies by [type].
/// Stored at `users/{uid}/milestones/{id}`, written once at the moment it's
/// detected, never edited afterward — an append-only log, not a mutable
/// rollup like [DashboardState]'s running totals (streak/level/gold/...),
/// which stay exactly as they are today; this only ever adds a dated
/// breadcrumb alongside them.
///
/// Deliberately coarse-grained: every write site (see
/// DashboardNotifierCompleteHabit.completeHabit's milestone-log section,
/// the one real writer today) only logs something worth seeing again
/// months later — a level-up, a streak threshold, a perfect day/week, an
/// achievement unlock — never a plain habit completion. A very active user
/// still only produces a handful of these a week, not one per tap.
///
/// No-ops for guests: everything in this file assumes a signed-in [uid],
/// same account-required boundary Rooms already draws (see
/// RoomsHubScreen's guest gate) — a log tied to `users/{uid}` has nowhere
/// to live for an account that doesn't exist yet. A guest's running totals
/// (streak, totalCompletions, etc.) still work everywhere they already
/// did; only this dated log, and anything built only from it, is
/// unavailable until they sign in.
class MilestoneEvent {
  final String id;
  final MilestoneType type;
  final DateTime occurredAt;

  /// Small, type-specific extra context — e.g. `{'level': 12}` for
  /// [MilestoneType.levelUp], `{'days': 30}` for a streak milestone,
  /// `{'achievementId': 'streak_100', ...}` for an unlock. A loose map
  /// rather than one subclass per type: the handful of readers (Journey
  /// Page, Monthly Story, Legacy Shelf) only ever need the couple of typed
  /// getters below on top of this, not real polymorphism, and a loose map
  /// means a new [MilestoneType] never needs a schema migration. Read
  /// through [level]/[streakDays]/[achievementId] rather than indexing
  /// this directly, and through [milestoneHeadline] for the full sentence.
  final Map<String, dynamic> data;

  const MilestoneEvent({
    required this.id,
    required this.type,
    required this.occurredAt,
    this.data = const {},
  });

  int? get level => data['level'] as int?;
  int? get streakDays => data['days'] as int?;
  int? get weekNumber => data['weekNumber'] as int?;
  String? get achievementId => data['achievementId'] as String?;
  String? get achievementTier => data['tier'] as String?;
  String? get roomName => data['roomName'] as String?;

  factory MilestoneEvent.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? const <String, dynamic>{};
    return MilestoneEvent(
      id: doc.id,
      type: MilestoneType.fromJson(d['type'] as String?),
      occurredAt: (d['occurredAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      data: Map<String, dynamic>.from(d['data'] as Map? ?? const {}),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'type': type.toJson(),
        'occurredAt': Timestamp.fromDate(occurredAt),
        'data': data,
      };
}

/// The full, data-filled sentence for one event — what [JourneyPage] and
/// [MonthlyStoryScreen] actually print per row, so this formatting lives in
/// exactly one place instead of being re-derived by every screen that lists
/// milestones. Falls back to [MilestoneType.localizedName] for anything
/// missing its expected data key (defensive against a future type added
/// here without its own case yet).
String milestoneHeadline(MilestoneEvent e, bool isAr) {
  switch (e.type) {
    case MilestoneType.joined:
      return isAr ? 'بدأت رحلتك مع Grow Daily' : 'Started your Grow Daily journey';
    case MilestoneType.levelUp:
      final lvl = e.level;
      if (lvl == null) return e.type.localizedName(isAr);
      return isAr ? 'وصلت للمستوى $lvl' : 'Reached Level $lvl';
    case MilestoneType.streakMilestone:
      final days = e.streakDays;
      if (days == null) return e.type.localizedName(isAr);
      return isAr ? 'سلسلة $days يومًا' : '$days-day streak';
    case MilestoneType.perfectDay:
      return isAr ? 'يوم مثالي، أنجزت كل عاداتك' : 'Perfect day, every habit done';
    case MilestoneType.perfectWeek:
      return isAr ? 'أسبوع مثالي بالكامل' : 'A full perfect week';
    case MilestoneType.achievementUnlocked:
      // e.achievementId is stored on every real write (see
      // DashboardNotifierCompleteHabit.completeHabit's milestone-log
      // section) - looking the real achievement up by it means this reads
      // "Unlocked: Century Champion" instead of a generic sentence that's
      // identical for every single unlock a person ever earns. Falls back
      // to the generic line only for a doc missing achievementId (an old
      // write from before this field existed) or one whose id no longer
      // matches anything in the catalog (a retired/renamed achievement).
      final achievement = AchievementCatalog.findById(e.achievementId ?? '');
      if (achievement == null) return e.type.localizedName(isAr);
      return isAr
          ? 'فتحت إنجاز "${achievement.localName(true)}"'
          : 'Unlocked "${achievement.localName(false)}"';
    case MilestoneType.roomChallengeComplete:
      final name = e.roomName;
      return isAr
          ? (name == null ? 'أكملت تحدي غرفة' : 'أكملت تحدي "$name"')
          : (name == null
              ? 'Completed a room challenge'
              : 'Completed "$name" challenge');
  }
}
