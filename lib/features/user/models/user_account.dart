import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/game_constants.dart';
import '../../../core/utils/xp_calculator.dart';

/// Stored at: users/{uid}
/// Mirrors the authenticated Firebase user; never stores credentials.
class UserAccount {
  final String uid;
  final String displayName;
  final String? avatarUrl;

  // ── Progression ─────────────────────────────────────────────
  final int level;
  final int cumulativeXp; // total XP earned lifetime
  final int currentLevelXp; // XP within the current level
  final int gold;

  // ── Streaks ──────────────────────────────────────────────────
  final int currentStreak; // consecutive active days
  final int longestStreak;
  final DateTime? lastActiveDate;

  // ── Unlocks ──────────────────────────────────────────────────
  final List<String> unlockedAchievements; // achievement IDs
  final List<String> equippedHabitIds; // habits shown on dashboard

  final DateTime createdAt;

  const UserAccount({
    required this.uid,
    required this.displayName,
    this.avatarUrl,
    required this.level,
    required this.cumulativeXp,
    required this.currentLevelXp,
    required this.gold,
    required this.currentStreak,
    required this.longestStreak,
    this.lastActiveDate,
    required this.unlockedAchievements,
    required this.equippedHabitIds,
    required this.createdAt,
  });

  // ── Computed ─────────────────────────────────────────────────

  int get xpToNextLevel => XpCalculator.xpToNextLevel(level);

  double get levelProgress =>
      XpCalculator.levelProgressRatio(currentLevelXp, level);

  bool get isMaxLevel => level >= GameConstants.maxLevel;

  // ── Constructors ─────────────────────────────────────────────

  factory UserAccount.initial(String uid, String displayName) => UserAccount(
        uid: uid,
        displayName: displayName,
        level: 1,
        cumulativeXp: 0,
        currentLevelXp: 0,
        gold: 0,
        currentStreak: 0,
        longestStreak: 0,
        unlockedAchievements: const [],
        equippedHabitIds: const [],
        createdAt: DateTime.now(),
      );

  factory UserAccount.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data()!;
    return UserAccount(
      uid: doc.id,
      displayName: d['displayName'] as String? ?? '',
      avatarUrl: d['avatarUrl'] as String?,
      level: d['level'] as int? ?? 1,
      cumulativeXp: d['cumulativeXp'] as int? ?? 0,
      currentLevelXp: d['currentLevelXp'] as int? ?? 0,
      gold: d['gold'] as int? ?? 0,
      currentStreak: d['currentStreak'] as int? ?? 0,
      longestStreak: d['longestStreak'] as int? ?? 0,
      lastActiveDate:
          (d['lastActiveDate'] as Timestamp?)?.toDate(),
      unlockedAchievements:
          List<String>.from(d['unlockedAchievements'] as List? ?? []),
      equippedHabitIds:
          List<String>.from(d['equippedHabitIds'] as List? ?? []),
      createdAt:
          (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'displayName': displayName,
        if (avatarUrl != null) 'avatarUrl': avatarUrl,
        'level': level,
        'cumulativeXp': cumulativeXp,
        'currentLevelXp': currentLevelXp,
        'gold': gold,
        'currentStreak': currentStreak,
        'longestStreak': longestStreak,
        if (lastActiveDate != null)
          'lastActiveDate': Timestamp.fromDate(lastActiveDate!),
        'unlockedAchievements': unlockedAchievements,
        'equippedHabitIds': equippedHabitIds,
        'createdAt': Timestamp.fromDate(createdAt),
      };

  UserAccount copyWith({
    String? displayName,
    String? avatarUrl,
    int? level,
    int? cumulativeXp,
    int? currentLevelXp,
    int? gold,
    int? currentStreak,
    int? longestStreak,
    DateTime? lastActiveDate,
    List<String>? unlockedAchievements,
    List<String>? equippedHabitIds,
  }) =>
      UserAccount(
        uid: uid,
        displayName: displayName ?? this.displayName,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        level: level ?? this.level,
        cumulativeXp: cumulativeXp ?? this.cumulativeXp,
        currentLevelXp: currentLevelXp ?? this.currentLevelXp,
        gold: gold ?? this.gold,
        currentStreak: currentStreak ?? this.currentStreak,
        longestStreak: longestStreak ?? this.longestStreak,
        lastActiveDate: lastActiveDate ?? this.lastActiveDate,
        unlockedAchievements:
            unlockedAchievements ?? this.unlockedAchievements,
        equippedHabitIds: equippedHabitIds ?? this.equippedHabitIds,
        createdAt: createdAt,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserAccount &&
          runtimeType == other.runtimeType &&
          uid == other.uid &&
          level == other.level &&
          cumulativeXp == other.cumulativeXp;

  @override
  int get hashCode => uid.hashCode ^ level.hashCode ^ cumulativeXp.hashCode;

  @override
  String toString() =>
      'UserAccount(uid: $uid, level: $level, xp: $cumulativeXp, streak: $currentStreak)';
}
