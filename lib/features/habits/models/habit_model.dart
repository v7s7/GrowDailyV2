import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

enum HabitFrequencyType {
  daily, // must complete every day
  weekly; // must complete [frequencyTarget] times per week

  String toJson() => name;
  static HabitFrequencyType fromJson(String v) =>
      values.firstWhere((e) => e.name == v, orElse: () => daily);
}

enum GoalType {
  build,
  quit;

  String toJson() => name;
  static GoalType fromJson(String? v) =>
      values.firstWhere((e) => e.name == v, orElse: () => build);
}

enum ReductionType {
  avoid,
  limit;

  String toJson() => name;
  static ReductionType fromJson(String? v) =>
      values.firstWhere((e) => e.name == v, orElse: () => avoid);
}

enum LimitUnit {
  minutes,
  times,
  cups,
  money,
  custom;

  String toJson() => name;
  static LimitUnit fromJson(String? v) =>
      values.firstWhere((e) => e.name == v, orElse: () => minutes);
}

enum HabitCategory {
  faith,
  health,
  learning,
  focus,
  sleep,
  money,
  mind,
  social,
  custom,
  quran,
  athkar,
  fitness,
  fasting,
  sadaqah;

  String toJson() => switch (this) {
        quran || athkar || fasting || sadaqah => 'faith',
        fitness => 'health',
        _ => name,
      };
  static HabitCategory fromJson(String v) =>
      values.firstWhere((e) => e.name == v, orElse: () => custom);

  /// Locale-aware category label (e.g. for the Add/Edit Habit category
  /// chips) — this was English-only before, which meant it showed as
  /// "Fasting"/"Fitness"/etc. even with the app set to Arabic.
  String localizedName(bool isAr) => isAr
      ? switch (this) {
          faith || quran || athkar || fasting || sadaqah => 'الإيمان',
          health || fitness => 'الصحة',
          learning => 'التعلّم',
          focus => 'التركيز',
          sleep => 'النوم',
          money => 'المال',
          mind => 'العقل',
          social => 'العلاقات',
          custom => 'مخصص',
        }
      : switch (this) {
          faith || quran || athkar || fasting || sadaqah => 'Faith',
          health || fitness => 'Health',
          learning => 'Learning',
          focus => 'Focus',
          sleep => 'Sleep',
          money => 'Money',
          mind => 'Mind',
          social => 'Social',
          custom => 'Custom',
        };

  IconData get icon => switch (this) {
        faith || quran || athkar || fasting || sadaqah => Icons.menu_book_rounded,
        health || fitness => Icons.fitness_center_rounded,
        learning => Icons.school_rounded,
        focus => Icons.center_focus_strong_rounded,
        sleep => Icons.bedtime_rounded,
        money => Icons.savings_rounded,
        mind => Icons.psychology_rounded,
        social => Icons.groups_rounded,
        custom => Icons.star_rounded,
      };

  /// Custom-drawn glyph asset for this category, or null to fall back to
  /// [icon] (Material icon). These are transparent-background PNGs meant to
  /// be tinted via `Image.asset(..., color: x, colorBlendMode: BlendMode.srcIn)`
  /// — see [CategoryIcon] — so they behave like a drop-in replacement for
  /// `Icon(category.icon, color: x)` wherever it's used.
  String? get iconAsset => switch (this) {
        faith || quran || athkar => 'assets/images/category_quran.png',
        health || fitness => 'assets/images/category_fitness.png',
        fasting || focus => 'assets/images/category_focus.png',
        sadaqah || money => 'assets/images/category_charity.png',
        sleep => 'assets/images/category_sleep.png',
        learning || mind || social || custom => null,
      };
}

/// Stored at: users/{uid}/habits/{habitId}
///
/// Supports both user-created habits and pre-set Islamic catalog habits.
/// [frequencyTarget] combined with [frequencyType] encodes any cadence:
///   - daily + 1  → every day
///   - weekly + 3 → 3 times per week
///   - weekly + 5 → 5 times per week
class HabitModel {
  final String id;
  final String uid;
  final String name;
  final String? description;
  final String? cueAfter;
  final HabitCategory category;
  final GoalType goalType;
  final ReductionType reductionType;
  final int? limitAmount;
  final LimitUnit? limitUnit;

  // ── Frequency ────────────────────────────────────────────────
  final HabitFrequencyType frequencyType;
  final int frequencyTarget; // completions required per period
  final List<int> scheduledWeekdays; // DateTime weekday values; empty = every day

  // ── Catalog ──────────────────────────────────────────────────
  final bool isPreset; // sourced from IslamicHabitCatalog
  final String? catalogId;

  // ── Timer (e.g. Quran page tracker) ──────────────────────────
  final bool hasTimer;
  final int? timerDurationSeconds;

  // ── Rewards ──────────────────────────────────────────────────
  final int xpReward; // XP per single completion
  final int goldReward;

  // ── Lifetime stats ───────────────────────────────────────────
  final int totalCompletions;
  final int currentStreak;
  final int longestStreak;

  final DateTime createdAt;
  final bool isArchived;

  const HabitModel({
    required this.id,
    required this.uid,
    required this.name,
    this.description,
    this.cueAfter,
    required this.category,
    this.goalType = GoalType.build,
    this.reductionType = ReductionType.avoid,
    this.limitAmount,
    this.limitUnit,
    required this.frequencyType,
    required this.frequencyTarget,
    this.scheduledWeekdays = const [],
    this.isPreset = false,
    this.catalogId,
    this.hasTimer = false,
    this.timerDurationSeconds,
    required this.xpReward,
    required this.goldReward,
    this.totalCompletions = 0,
    this.currentStreak = 0,
    this.longestStreak = 0,
    required this.createdAt,
    this.isArchived = false,
  });

  bool get isWeekly => frequencyType == HabitFrequencyType.weekly;
  bool get requiresTimer => hasTimer && timerDurationSeconds != null;

  factory HabitModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data()!;
    return HabitModel(
      id: doc.id,
      uid: d['uid'] as String,
      name: d['name'] as String,
      description: d['description'] as String?,
      cueAfter: d['cueAfter'] as String?,
      category: HabitCategory.fromJson(d['category'] as String? ?? 'custom'),
      goalType: GoalType.fromJson(d['goalType'] as String?),
      reductionType: ReductionType.fromJson(d['reductionType'] as String?),
      limitAmount: d['limitAmount'] as int?,
      limitUnit: d['limitUnit'] == null
          ? null
          : LimitUnit.fromJson(d['limitUnit'] as String?),
      frequencyType: HabitFrequencyType.fromJson(
        d['frequencyType'] as String? ?? 'daily',
      ),
      frequencyTarget: d['frequencyTarget'] as int? ?? 1,
      scheduledWeekdays: (d['scheduledWeekdays'] as List?)
              ?.whereType<int>()
              .where((d) => d >= DateTime.monday && d <= DateTime.sunday)
              .toList() ??
          const [],
      isPreset: d['isPreset'] as bool? ?? false,
      catalogId: d['catalogId'] as String?,
      hasTimer: d['hasTimer'] as bool? ?? false,
      timerDurationSeconds: d['timerDurationSeconds'] as int?,
      xpReward: d['xpReward'] as int? ?? 10,
      goldReward: d['goldReward'] as int? ?? 5,
      totalCompletions: d['totalCompletions'] as int? ?? 0,
      currentStreak: d['currentStreak'] as int? ?? 0,
      longestStreak: d['longestStreak'] as int? ?? 0,
      createdAt:
          (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isArchived: d['isArchived'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'uid': uid,
        'name': name,
        if (description != null) 'description': description,
        if (cueAfter != null) 'cueAfter': cueAfter,
        'category': category.toJson(),
        'goalType': goalType.toJson(),
        if (goalType == GoalType.quit) 'reductionType': reductionType.toJson(),
        if (goalType == GoalType.quit &&
            reductionType == ReductionType.limit &&
            limitAmount != null)
          'limitAmount': limitAmount,
        if (goalType == GoalType.quit &&
            reductionType == ReductionType.limit &&
            limitUnit != null)
          'limitUnit': limitUnit!.toJson(),
        'frequencyType': frequencyType.toJson(),
        'frequencyTarget': frequencyTarget,
        if (scheduledWeekdays.isNotEmpty) 'scheduledWeekdays': scheduledWeekdays,
        'isPreset': isPreset,
        if (catalogId != null) 'catalogId': catalogId,
        'hasTimer': hasTimer,
        if (timerDurationSeconds != null)
          'timerDurationSeconds': timerDurationSeconds,
        'xpReward': xpReward,
        'goldReward': goldReward,
        'totalCompletions': totalCompletions,
        'currentStreak': currentStreak,
        'longestStreak': longestStreak,
        'createdAt': Timestamp.fromDate(createdAt),
        'isArchived': isArchived,
      };

  HabitModel copyWith({
    String? name,
    String? description,
    String? cueAfter,
    HabitCategory? category,
    GoalType? goalType,
    ReductionType? reductionType,
    int? limitAmount,
    LimitUnit? limitUnit,
    HabitFrequencyType? frequencyType,
    int? frequencyTarget,
    List<int>? scheduledWeekdays,
    bool? hasTimer,
    int? timerDurationSeconds,
    int? xpReward,
    int? goldReward,
    int? totalCompletions,
    int? currentStreak,
    int? longestStreak,
    bool? isArchived,
  }) =>
      HabitModel(
        id: id,
        uid: uid,
        name: name ?? this.name,
        description: description ?? this.description,
        cueAfter: cueAfter ?? this.cueAfter,
        category: category ?? this.category,
        goalType: goalType ?? this.goalType,
        reductionType: reductionType ?? this.reductionType,
        limitAmount: limitAmount ?? this.limitAmount,
        limitUnit: limitUnit ?? this.limitUnit,
        frequencyType: frequencyType ?? this.frequencyType,
        frequencyTarget: frequencyTarget ?? this.frequencyTarget,
        scheduledWeekdays: scheduledWeekdays ?? this.scheduledWeekdays,
        isPreset: isPreset,
        catalogId: catalogId,
        hasTimer: hasTimer ?? this.hasTimer,
        timerDurationSeconds:
            timerDurationSeconds ?? this.timerDurationSeconds,
        xpReward: xpReward ?? this.xpReward,
        goldReward: goldReward ?? this.goldReward,
        totalCompletions: totalCompletions ?? this.totalCompletions,
        currentStreak: currentStreak ?? this.currentStreak,
        longestStreak: longestStreak ?? this.longestStreak,
        createdAt: createdAt,
        isArchived: isArchived ?? this.isArchived,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HabitModel &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'HabitModel($name, ${frequencyTarget}x/${frequencyType.name})';
}
