'use strict';

/**
 * The built-in achievement text, transcribed once from
 * lib/features/achievements/models/achievement_model.dart's
 * AchievementCatalog. Static on purpose: unlike Wording's app-text catalog
 * (docs/wording/generator), there is no analyzer-driven rebuild here — 20
 * achievements and 5 families change rarely enough that keeping this file in
 * sync by hand, the one time a new one is added in code, is simpler and
 * safer than a second code-parsing pipeline for 25 records. The Quran
 * family («ورد القرآن») was removed from the app on 2026-09-22, and from here.
 *
 * If Dart's list ever moves ahead of this one (a new achievement added, a
 * built-in string edited), the admin page still runs correctly — a
 * catalog-unknown id just cannot be found here to show or edit, and every
 * app keeps reading its own built-in text regardless of what this file
 * says. Nothing here is ever the app's source of truth, only what the
 * ADMIN PAGE shows as the "built-in" text next to an edit field.
 */

const FAMILIES = [
  { id: 'streak', title: 'Unbroken', titleAr: 'بدون انقطاع' },
  { id: 'level', title: 'The Climb', titleAr: 'الصعود' },
  { id: 'completions', title: 'Steady', titleAr: 'الثبات' },
  { id: 'grid', title: 'The Grid', titleAr: 'الشبكة' },
  { id: 'endurance', title: 'The Long Haul', titleAr: 'النَفَس الطويل' },
];

const TIER_LABEL = { bronze: 'Bronze', silver: 'Silver', gold: 'Gold', platinum: 'Platinum' };

const ACHIEVEMENTS = [
  // Streak
  { id: 'streak_7', familyId: 'streak', tier: 'bronze', name: 'A Full Week', nameAr: 'أسبوع كامل', description: 'A 7-day streak', descriptionAr: 'سلسلة 7 أيام متواصلة' },
  { id: 'streak_30', familyId: 'streak', tier: 'silver', name: 'A Month Straight', nameAr: 'شهر ما انقطع', description: 'A 30-day streak', descriptionAr: 'سلسلة 30 يوم متواصلة' },
  { id: 'streak_100', familyId: 'streak', tier: 'gold', name: 'A Hundred Days', nameAr: 'مية يوم', description: 'A 100-day streak', descriptionAr: 'سلسلة 100 يوم متواصلة' },
  { id: 'streak_365', familyId: 'streak', tier: 'platinum', name: 'A Year, No Gaps', nameAr: 'سنة ما فاتها يوم', description: 'A 365-day streak', descriptionAr: 'سلسلة 365 يوم متواصلة' },
  // Level
  { id: 'level_10', familyId: 'level', tier: 'bronze', name: 'First Rung', nameAr: 'أول درجة', description: 'Reach level 10', descriptionAr: 'الوصول للمستوى 10' },
  { id: 'level_25', familyId: 'level', tier: 'silver', name: 'Halfway Up', nameAr: 'نص السلّم', description: 'Reach level 25', descriptionAr: 'الوصول للمستوى 25' },
  { id: 'level_50', familyId: 'level', tier: 'gold', name: 'Top of the Ladder', nameAr: 'فوق السلّم', description: 'Reach level 50', descriptionAr: 'الوصول للمستوى 50' },
  { id: 'level_100', familyId: 'level', tier: 'platinum', name: 'The Summit', nameAr: 'القمة', description: 'Reach level 100, the maximum', descriptionAr: 'الوصول لأعلى مستوى: 100' },
  // Consistency (total lifetime completions)
  { id: 'completions_50', familyId: 'completions', tier: 'bronze', name: 'Now a Habit', nameAr: 'صار عادة', description: 'Any habit, 50 times', descriptionAr: 'أي عادة، 50 مرة' },
  { id: 'completions_500', familyId: 'completions', tier: 'silver', name: 'Steady', nameAr: 'ثابت', description: 'Habits, 500 times', descriptionAr: 'العادات، 500 مرة' },
  { id: 'completions_2000', familyId: 'completions', tier: 'gold', name: 'Nothing Stops It', nameAr: 'ما يوقفه شي', description: 'Habits, 2,000 times', descriptionAr: 'العادات، 2000 مرة' },
  { id: 'completions_5000', familyId: 'completions', tier: 'platinum', name: 'Second Nature', nameAr: 'صار طبع', description: 'Habits, 5,000 times', descriptionAr: 'العادات، 5000 مرة' },
  // Quran Devotion
  // Victory Grid
  { id: 'green_1', familyId: 'grid', tier: 'bronze', name: 'First Square', nameAr: 'أول مربّع', description: 'The first colored square on the Grid', descriptionAr: 'أول مربّع ملوّن في الشبكة' },
  { id: 'green_100', familyId: 'grid', tier: 'silver', name: 'A Hundred Squares', nameAr: 'مية مربّع', description: '100 colored squares on the Grid', descriptionAr: '100 مربّع ملوّن في الشبكة' },
  { id: 'green_500', familyId: 'grid', tier: 'gold', name: 'Colored In', nameAr: 'شبكة ملوّنة', description: '500 colored squares on the Grid', descriptionAr: '500 مربّع ملوّن في الشبكة' },
  { id: 'green_2000', familyId: 'grid', tier: 'platinum', name: 'A Full Canvas', nameAr: 'لوحة كاملة', description: '2,000 colored squares on the Grid', descriptionAr: '2000 مربّع ملوّن في الشبكة' },
  // Endurance: the streak rungs past 100
  { id: 'endurance_150', familyId: 'endurance', tier: 'bronze', name: 'Past the Hundred', nameAr: 'عدّت المية', description: 'A 150-day streak', descriptionAr: 'سلسلة 150 يوم متواصلة' },
  { id: 'endurance_200', familyId: 'endurance', tier: 'silver', name: 'Two Hundred Down', nameAr: 'ميتين يوم', description: 'A 200-day streak', descriptionAr: 'سلسلة 200 يوم متواصلة' },
  { id: 'endurance_250', familyId: 'endurance', tier: 'gold', name: 'Still Not Stopping', nameAr: 'ما وقفت لي الحين', description: 'A 250-day streak', descriptionAr: 'سلسلة 250 يوم متواصلة' },
  { id: 'endurance_300', familyId: 'endurance', tier: 'platinum', name: 'Three Hundred Straight', nameAr: 'ثلاثمية يوم', description: 'A 300-day streak', descriptionAr: 'سلسلة 300 يوم متواصلة' },
];

const ACHIEVEMENTS_BY_ID = new Map(ACHIEVEMENTS.map((a) => [a.id, a]));
const FAMILIES_BY_ID = new Map(FAMILIES.map((f) => [f.id, f]));

module.exports = { FAMILIES, ACHIEVEMENTS, TIER_LABEL, ACHIEVEMENTS_BY_ID, FAMILIES_BY_ID };
