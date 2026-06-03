import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../models/habit_model.dart';

/// Immutable template from the pre-saved Islamic catalog.
/// Call [toHabitModel] to equip it to a user's account.
class IslamicHabitTemplate {
  final String id;
  final String name;
  final String description;
  final String iconEmoji;
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
    required this.iconEmoji,
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
        iconEmoji: iconEmoji,
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
        'iconEmoji': iconEmoji,
        'category': category.toJson(),
        'frequencyType': frequencyType.toJson(),
        'frequencyTarget': frequencyTarget,
        'hasTimer': hasTimer,
        if (timerDurationSeconds != null)
          'timerDurationSeconds': timerDurationSeconds,
        'xpReward': xpReward,
        'goldReward': goldReward,
      };

  factory IslamicHabitTemplate.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data()!;
    return IslamicHabitTemplate(
      id: doc.id,
      name: d['name'] as String,
      description: d['description'] as String? ?? '',
      iconEmoji: d['iconEmoji'] as String? ?? '',
      category:
          HabitCategory.fromJson(d['category'] as String? ?? 'custom'),
      frequencyType: HabitFrequencyType.fromJson(
        d['frequencyType'] as String? ?? 'daily',
      ),
      frequencyTarget: d['frequencyTarget'] as int? ?? 1,
      hasTimer: d['hasTimer'] as bool? ?? false,
      timerDurationSeconds: d['timerDurationSeconds'] as int?,
      xpReward: d['xpReward'] as int? ?? 20,
      goldReward: d['goldReward'] as int? ?? 8,
    );
  }
}

abstract final class IslamicHabitCatalog {
  static const List<IslamicHabitTemplate> templates = [
    IslamicHabitTemplate(
      id: 'quran_daily_page',
      name: 'Quran Daily Page',
      description: 'Read at least one page of the Quran every day',
      iconEmoji: '',
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
      iconEmoji: '',
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
      iconEmoji: '',
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
      iconEmoji: '',
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
      iconEmoji: '',
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
      iconEmoji: '',
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
      iconEmoji: '',
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
      iconEmoji: '',
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
      iconEmoji: '',
      category: HabitCategory.sleep,
      frequencyType: HabitFrequencyType.daily,
      frequencyTarget: 1,
      hasTimer: false,
      xpReward: 15,
      goldReward: 5,
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
