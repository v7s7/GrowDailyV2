import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../models/habit_model.dart';

/// Immutable template from the pre-saved Islamic catalog.
/// Call [toHabitModel] to equip it to a user's account.
class IslamicHabitTemplate {
  final String id;
  final String name;
  final String description;
  final String? cueAfter;
  final HabitCategory category;
  final HabitFrequencyType frequencyType;
  final int frequencyTarget;
  final bool hasTimer;
  final int? timerDurationSeconds;
  final int xpReward;
  final int goldReward;

  const IslamicHabitTemplate({
    required this.id,
    required this.name,
    required this.description,
    this.cueAfter,
    required this.category,
    required this.frequencyType,
    required this.frequencyTarget,
    required this.hasTimer,
    this.timerDurationSeconds,
    required this.xpReward,
    required this.goldReward,
  });

  HabitModel toHabitModel(String uid) => HabitModel(
        id: const Uuid().v4(),
        uid: uid,
        name: name,
        description: description,
        cueAfter: cueAfter,
        category: category,
        frequencyType: frequencyType,
        frequencyTarget: frequencyTarget,
        isPreset: true,
        catalogId: id,
        hasTimer: hasTimer,
        timerDurationSeconds: timerDurationSeconds,
        xpReward: xpReward,
        goldReward: goldReward,
        createdAt: DateTime.now(),
      );

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'description': description,
        if (cueAfter != null) 'cueAfter': cueAfter,
        'category': category.toJson(),
        'frequencyType': frequencyType.toJson(),
        'frequencyTarget': frequencyTarget,
        'hasTimer': hasTimer,
        if (timerDurationSeconds != null)
          'timerDurationSeconds': timerDurationSeconds,
        'xpReward': xpReward,
        'goldReward': goldReward,
      };

  factory IslamicHabitTemplate.fromMap(String id, Map<String, dynamic> d) =>
      IslamicHabitTemplate(
        id: id,
        name: d['name'] as String? ?? 'Custom Habit',
        description: d['description'] as String? ?? '',
        cueAfter: d['cueAfter'] as String?,
        category: HabitCategory.fromJson(d['category'] as String? ?? 'custom'),
        frequencyType: HabitFrequencyType.fromJson(
          d['frequencyType'] as String? ?? 'daily',
        ),
        frequencyTarget: d['frequencyTarget'] as int? ?? 1,
        hasTimer: d['hasTimer'] as bool? ?? false,
        timerDurationSeconds: d['timerDurationSeconds'] as int?,
        xpReward: d['xpReward'] as int? ?? 20,
        goldReward: d['goldReward'] as int? ?? 8,
      );

  factory IslamicHabitTemplate.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) =>
      IslamicHabitTemplate.fromMap(doc.id, doc.data()!);
}

abstract final class IslamicHabitCatalog {
  static const List<IslamicHabitTemplate> templates = [
    IslamicHabitTemplate(
      id: 'quran_daily_page',
      name: 'Quran Daily Page',
      description: 'Read at least one page of the Quran every day',
      cueAfter: 'Fajr',
      category: HabitCategory.quran,
      frequencyType: HabitFrequencyType.daily,
      frequencyTarget: 1,
      hasTimer: true,
      timerDurationSeconds: 600,
      xpReward: 30,
      goldReward: 10,
    ),
    IslamicHabitTemplate(
      id: 'quran_memorization',
      name: 'Quran Memorization',
      description: 'Memorize and review verses of the Quran',
      cueAfter: 'your quiet study block',
      category: HabitCategory.quran,
      frequencyType: HabitFrequencyType.daily,
      frequencyTarget: 1,
      hasTimer: true,
      timerDurationSeconds: 900,
      xpReward: 45,
      goldReward: 18,
    ),
    IslamicHabitTemplate(
      id: 'morning_athkar',
      name: 'Morning Athkar',
      description: 'Recite the morning remembrances after Fajr',
      cueAfter: 'Fajr',
      category: HabitCategory.athkar,
      frequencyType: HabitFrequencyType.daily,
      frequencyTarget: 1,
      hasTimer: false,
      xpReward: 15,
      goldReward: 5,
    ),
    IslamicHabitTemplate(
      id: 'evening_athkar',
      name: 'Evening Athkar',
      description: 'Recite the evening remembrances after Asr',
      cueAfter: 'Asr',
      category: HabitCategory.athkar,
      frequencyType: HabitFrequencyType.daily,
      frequencyTarget: 1,
      hasTimer: false,
      xpReward: 15,
      goldReward: 5,
    ),
    IslamicHabitTemplate(
      id: 'tahajjud',
      name: 'Tahajjud Prayer',
      description: 'Rise before Fajr for the voluntary night prayer',
      cueAfter: 'waking before Fajr',
      category: HabitCategory.athkar,
      frequencyType: HabitFrequencyType.weekly,
      frequencyTarget: 3,
      hasTimer: false,
      xpReward: 50,
      goldReward: 20,
    ),
    IslamicHabitTemplate(
      id: 'gym_consistency',
      name: 'Gym Consistency',
      description: 'Maintain fitness — your body is an amanah',
      category: HabitCategory.fitness,
      frequencyType: HabitFrequencyType.weekly,
      frequencyTarget: 3,
      hasTimer: false,
      xpReward: 20,
      goldReward: 8,
    ),
    IslamicHabitTemplate(
      id: 'sunnah_fasting',
      name: 'Monday & Thursday Fast',
      description: 'Follow the sunnah of fasting on Mondays and Thursdays',
      category: HabitCategory.fasting,
      frequencyType: HabitFrequencyType.weekly,
      frequencyTarget: 2,
      hasTimer: false,
      xpReward: 40,
      goldReward: 15,
    ),
    IslamicHabitTemplate(
      id: 'daily_sadaqah',
      name: 'Daily Sadaqah',
      description: 'Give in charity daily — even a smile counts',
      category: HabitCategory.sadaqah,
      frequencyType: HabitFrequencyType.daily,
      frequencyTarget: 1,
      hasTimer: false,
      xpReward: 25,
      goldReward: 10,
    ),
    IslamicHabitTemplate(
      id: 'sleep_schedule',
      name: 'Sleep Before Midnight',
      description: 'Protect your Fajr by sleeping before midnight',
      category: HabitCategory.sleep,
      frequencyType: HabitFrequencyType.daily,
      frequencyTarget: 1,
      hasTimer: false,
      xpReward: 15,
      goldReward: 5,
    ),
    // ── Marriage Preparation ─────────────────────────────────────
    IslamicHabitTemplate(
      id: 'marriage_dua',
      name: 'Dua for Your Spouse',
      description: 'Make a sincere dua for your spouse (or future spouse)',
      cueAfter: 'Isha',
      category: HabitCategory.custom,
      frequencyType: HabitFrequencyType.daily,
      frequencyTarget: 1,
      hasTimer: false,
      xpReward: 15,
      goldReward: 5,
    ),
    IslamicHabitTemplate(
      id: 'marriage_gratitude',
      name: 'Gratitude Note to Spouse',
      description: 'Write or say one thing you appreciate about them today',
      category: HabitCategory.custom,
      frequencyType: HabitFrequencyType.daily,
      frequencyTarget: 1,
      hasTimer: false,
      xpReward: 10,
      goldReward: 5,
    ),
    IslamicHabitTemplate(
      id: 'marriage_read',
      name: 'Read About Marriage',
      description: 'Study the rights and etiquette of marriage in Islam',
      category: HabitCategory.custom,
      frequencyType: HabitFrequencyType.daily,
      frequencyTarget: 1,
      hasTimer: true,
      timerDurationSeconds: 600,
      xpReward: 20,
      goldReward: 8,
    ),
    IslamicHabitTemplate(
      id: 'marriage_checkin',
      name: 'Weekly Marriage Check-in',
      description:
          'Sit together and talk honestly about how the week went',
      category: HabitCategory.custom,
      frequencyType: HabitFrequencyType.weekly,
      frequencyTarget: 1,
      hasTimer: false,
      xpReward: 30,
      goldReward: 10,
    ),
    // ── Productivity Starter Pack ─────────────────────────────────
    IslamicHabitTemplate(
      id: 'deep_work_block',
      name: 'Deep Work Block',
      description: 'One uninterrupted block of focused work, phone away',
      category: HabitCategory.custom,
      frequencyType: HabitFrequencyType.daily,
      frequencyTarget: 1,
      hasTimer: true,
      timerDurationSeconds: 1500,
      xpReward: 30,
      goldReward: 10,
    ),
    IslamicHabitTemplate(
      id: 'inbox_zero',
      name: 'Inbox Zero',
      description: 'Clear or triage every message in your inbox',
      category: HabitCategory.custom,
      frequencyType: HabitFrequencyType.daily,
      frequencyTarget: 1,
      hasTimer: false,
      xpReward: 15,
      goldReward: 5,
    ),
    IslamicHabitTemplate(
      id: 'daily_planning',
      name: 'Plan Tomorrow Tonight',
      description: 'Write tomorrow\'s top 3 priorities before you sleep',
      category: HabitCategory.custom,
      frequencyType: HabitFrequencyType.daily,
      frequencyTarget: 1,
      hasTimer: false,
      xpReward: 15,
      goldReward: 5,
    ),
    IslamicHabitTemplate(
      id: 'no_phone_morning',
      name: 'No Phone First Hour',
      description: 'No screens in the first hour after waking up',
      category: HabitCategory.custom,
      frequencyType: HabitFrequencyType.daily,
      frequencyTarget: 1,
      hasTimer: false,
      xpReward: 20,
      goldReward: 8,
    ),
    // ── 30-Day Discipline Challenge ────────────────────────────────
    IslamicHabitTemplate(
      id: 'cold_shower',
      name: 'Cold Shower',
      description: 'End your shower with at least 60 seconds of cold water',
      category: HabitCategory.custom,
      frequencyType: HabitFrequencyType.daily,
      frequencyTarget: 1,
      hasTimer: false,
      xpReward: 15,
      goldReward: 5,
    ),
    IslamicHabitTemplate(
      id: 'wake_early',
      name: 'Wake Before 6AM',
      description: 'Rise before 6AM and get straight out of bed',
      category: HabitCategory.custom,
      frequencyType: HabitFrequencyType.daily,
      frequencyTarget: 1,
      hasTimer: false,
      xpReward: 20,
      goldReward: 8,
    ),
    IslamicHabitTemplate(
      id: 'no_sugar',
      name: 'No Added Sugar',
      description: 'Go the whole day without any added sugar',
      category: HabitCategory.custom,
      frequencyType: HabitFrequencyType.daily,
      frequencyTarget: 1,
      hasTimer: false,
      xpReward: 20,
      goldReward: 8,
    ),
  ];

  static IslamicHabitTemplate? findById(String id) {
    try {
      return templates.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }

  static List<IslamicHabitTemplate> byCategory(HabitCategory category) =>
      templates.where((t) => t.category == category).toList();
}
