import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/local_store_service.dart';
import '../../auth/notifiers/auth_notifier.dart';
import 'islamic_habit_catalog.dart';

// ─── Plan definitions ─────────────────────────────────────────────────────────

class HabitPlan {
  final String id;
  final String nameEn;
  final String nameAr;
  final String descEn;
  final String descAr;
  final Color color;
  final String emoji;
  final List<String> catalogIds;

  const HabitPlan({
    required this.id,
    required this.nameEn,
    required this.nameAr,
    required this.descEn,
    required this.descAr,
    required this.color,
    required this.emoji,
    required this.catalogIds,
  });

  String localName(bool isAr) => isAr ? nameAr : nameEn;
  String localDesc(bool isAr) => isAr ? descAr : descEn;

  List<IslamicHabitTemplate> get habits =>
      IslamicHabitCatalog.templates.where((t) => catalogIds.contains(t.id)).toList();

  int get totalDailyXp =>
      habits.fold(0, (sum, t) => sum + t.xpReward);
}

const habitPlans = <HabitPlan>[
  HabitPlan(
    id: 'morning_warrior',
    nameEn: 'Morning Warrior',
    nameAr: 'محارب الفجر',
    descEn: 'Quran + morning athkar at dawn. The best start.',
    descAr: 'قرآن وأذكار الصباح عند الفجر. أفضل بداية.',
    color: Color(0xFF4A9EFF),
    emoji: '🌅',
    catalogIds: ['morning_athkar', 'quran_daily_page', 'sleep_schedule'],
  ),
  HabitPlan(
    id: 'deen_core',
    nameEn: 'Deen Core',
    nameAr: 'أساس الدين',
    descEn: 'Morning & evening athkar, daily Quran, sunnah fasting.',
    descAr: 'أذكار الصباح والمساء، قرآن يومي، صيام السنة.',
    color: Color(0xFF34C759),
    emoji: '☪',
    catalogIds: ['morning_athkar', 'evening_athkar', 'quran_daily_page', 'sunnah_fasting'],
  ),
  HabitPlan(
    id: 'body_soul',
    nameEn: 'Body & Soul',
    nameAr: 'الجسد والروح',
    descEn: 'Fitness, charity, and sleep — your body is an amanah.',
    descAr: 'رياضة، صدقة، ونوم — جسمك أمانة.',
    color: Color(0xFFFF6B35),
    emoji: '💪',
    catalogIds: ['gym_consistency', 'sleep_schedule', 'daily_sadaqah'],
  ),
  HabitPlan(
    id: 'full_growth',
    nameEn: 'Full Growth',
    nameAr: 'النمو الكامل',
    descEn: 'All essentials for a complete, balanced Islamic life.',
    descAr: 'كل الأساسيات لحياة إسلامية متوازنة.',
    color: Color(0xFFBF5AF2),
    emoji: '⭐',
    catalogIds: [
      'morning_athkar', 'evening_athkar', 'quran_daily_page',
      'sunnah_fasting', 'daily_sadaqah', 'gym_consistency', 'sleep_schedule',
    ],
  ),
];

// ─── Active catalog provider ──────────────────────────────────────────────────

const _kActiveKey = 'active_catalog_ids_v1';
const _kReminderKey = 'daily_reminder_time_v1';

class ActiveCatalogNotifier extends StateNotifier<Set<String>> {
  ActiveCatalogNotifier() : super(const {}) {
    _load();
  }

  Future<void> _load() async {
    final box = await LocalStoreService.settingsBox();
    final raw = box.get(_kActiveKey);
    if (raw is List && mounted) {
      state = Set<String>.from(raw.whereType<String>());
    }
  }

  Future<void> _save() async {
    final box = await LocalStoreService.settingsBox();
    await box.put(_kActiveKey, state.toList());
  }

  void toggle(String catalogId) {
    if (state.contains(catalogId)) {
      state = Set.of(state)..remove(catalogId);
    } else {
      state = {...state, catalogId};
    }
    _save();
  }

  void activatePlan(HabitPlan plan) {
    state = {...state, ...plan.catalogIds};
    _save();
  }

  void deactivatePlan(HabitPlan plan) {
    state = state.difference(plan.catalogIds.toSet());
    _save();
  }

  bool planIsActive(HabitPlan plan) =>
      plan.catalogIds.every(state.contains);
}

final activeCatalogProvider =
    StateNotifierProvider<ActiveCatalogNotifier, Set<String>>(
  (_) => ActiveCatalogNotifier(),
);

// ─── Daily reminder time provider ─────────────────────────────────────────────

class ReminderTimeNotifier extends StateNotifier<TimeOfDay?> {
  ReminderTimeNotifier() : super(null) {
    _load();
  }

  Future<void> _load() async {
    final box = await LocalStoreService.settingsBox();
    final raw = box.get(_kReminderKey) as String?;
    if (raw != null && mounted) {
      final parts = raw.split(':');
      if (parts.length == 2) {
        state = TimeOfDay(
          hour: int.tryParse(parts[0]) ?? 20,
          minute: int.tryParse(parts[1]) ?? 0,
        );
      }
    }
  }

  Future<void> set(TimeOfDay time) async {
    state = time;
    final box = await LocalStoreService.settingsBox();
    await box.put(_kReminderKey, '${time.hour}:${time.minute}');
  }

  Future<void> clear() async {
    state = null;
    final box = await LocalStoreService.settingsBox();
    await box.delete(_kReminderKey);
  }
}

final reminderTimeProvider =
    StateNotifierProvider<ReminderTimeNotifier, TimeOfDay?>(
  (_) => ReminderTimeNotifier(),
);
