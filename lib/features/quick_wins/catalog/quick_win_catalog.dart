import '../../habits/models/habit_model.dart';
import '../models/quick_win.dart';

// Reward constants kept flat and small on purpose — Quick Wins sit below
// habits (15-50 XP) and focus sessions (30-100 XP) in the app's reward
// scale, so completing one always feels like a light bonus, never a
// replacement for the real habit/streak loop.
const int _dailyXp = 12;
const int _weeklyXp = 50;
const int _weeklyGold = 15;

abstract final class QuickWinCatalog {
  static const List<QuickWin> daily = [
    QuickWin(
      id: 'daily_quran_page',
      titleEn: 'Read one page of Quran',
      titleAr: 'اقرأ صفحة واحدة من القرآن',
      category: HabitCategory.quran,
      cadence: QuickWinCadence.daily,
      xpReward: _dailyXp,
      goldReward: 0,
    ),
    QuickWin(
      id: 'daily_reflect_ayah',
      titleEn: 'Reflect on one verse you read',
      titleAr: 'تدبّر آية واحدة قرأتها',
      category: HabitCategory.quran,
      cadence: QuickWinCadence.daily,
      xpReward: _dailyXp,
      goldReward: 0,
    ),
    QuickWin(
      id: 'daily_two_rakahs',
      titleEn: "Pray two extra rak'ahs",
      titleAr: 'صلِّ ركعتين نافلة',
      category: HabitCategory.athkar,
      cadence: QuickWinCadence.daily,
      xpReward: _dailyXp,
      goldReward: 0,
    ),
    QuickWin(
      id: 'daily_gratitude_three',
      titleEn: 'Name 3 things you\'re grateful for today',
      titleAr: 'اذكر ثلاثة أشياء تشكر الله عليها اليوم',
      category: HabitCategory.athkar,
      cadence: QuickWinCadence.daily,
      xpReward: _dailyXp,
      goldReward: 0,
    ),
    QuickWin(
      id: 'daily_walk_10',
      titleEn: 'Walk for 10 minutes',
      titleAr: 'امشِ لمدة 10 دقائق',
      category: HabitCategory.fitness,
      cadence: QuickWinCadence.daily,
      xpReward: _dailyXp,
      goldReward: 0,
    ),
    QuickWin(
      id: 'daily_stretch_5',
      titleEn: 'Stretch for 5 minutes',
      titleAr: 'مارس تمارين الإطالة لمدة 5 دقائق',
      category: HabitCategory.fitness,
      cadence: QuickWinCadence.daily,
      xpReward: _dailyXp,
      goldReward: 0,
    ),
    QuickWin(
      id: 'daily_intend_fast',
      titleEn: 'Set an intention to fast this Mon or Thu',
      titleAr: 'انوِ صيام الاثنين أو الخميس القادم',
      category: HabitCategory.fasting,
      cadence: QuickWinCadence.daily,
      xpReward: _dailyXp,
      goldReward: 0,
    ),
    QuickWin(
      id: 'daily_sadaqah_smile',
      titleEn: 'Give in charity today, even a smile',
      titleAr: 'تصدّق اليوم، ولو بابتسامة',
      category: HabitCategory.sadaqah,
      cadence: QuickWinCadence.daily,
      xpReward: _dailyXp,
      goldReward: 0,
    ),
    QuickWin(
      id: 'daily_better_sleep',
      titleEn: 'Sleep 30 minutes earlier tonight',
      titleAr: 'نم مبكرًا بثلاثين دقيقة الليلة',
      category: HabitCategory.sleep,
      cadence: QuickWinCadence.daily,
      xpReward: _dailyXp,
      goldReward: 0,
    ),
    QuickWin(
      id: 'daily_clean_desk',
      titleEn: 'Clean your desk for 5 minutes',
      titleAr: 'رتّب مكتبك لمدة 5 دقائق',
      category: HabitCategory.custom,
      cadence: QuickWinCadence.daily,
      xpReward: _dailyXp,
      goldReward: 0,
    ),
    QuickWin(
      id: 'daily_kind_message',
      titleEn: 'Send a kind message to someone',
      titleAr: 'أرسل رسالة لطيفة لشخص ما',
      category: HabitCategory.custom,
      cadence: QuickWinCadence.daily,
      xpReward: _dailyXp,
      goldReward: 0,
    ),
    QuickWin(
      id: 'daily_plan_tomorrow',
      titleEn: 'Plan tomorrow in one sentence',
      titleAr: 'خطّط ليوم الغد بجملة واحدة',
      category: HabitCategory.custom,
      cadence: QuickWinCadence.daily,
      xpReward: _dailyXp,
      goldReward: 0,
    ),
    QuickWin(
      id: 'daily_water_before_coffee',
      titleEn: 'Drink water before your coffee',
      titleAr: 'اشرب الماء قبل القهوة',
      category: HabitCategory.custom,
      cadence: QuickWinCadence.daily,
      xpReward: _dailyXp,
      goldReward: 0,
    ),
  ];

  static const List<QuickWin> weekly = [
    QuickWin(
      id: 'weekly_quran_5_days',
      titleEn: 'Read Quran 5 days this week',
      titleAr: 'اقرأ القرآن 5 أيام هذا الأسبوع',
      category: HabitCategory.quran,
      cadence: QuickWinCadence.weekly,
      xpReward: _weeklyXp,
      goldReward: _weeklyGold,
      autoTrackTarget: 5,
    ),
    QuickWin(
      id: 'weekly_athkar_4_days',
      titleEn: 'Do your athkar 4 days this week',
      titleAr: 'أدِّ أذكارك 4 أيام هذا الأسبوع',
      category: HabitCategory.athkar,
      cadence: QuickWinCadence.weekly,
      xpReward: _weeklyXp,
      goldReward: _weeklyGold,
      autoTrackTarget: 4,
    ),
    QuickWin(
      id: 'weekly_exercise_2_days',
      titleEn: 'Exercise twice this week',
      titleAr: 'مارس الرياضة مرتين هذا الأسبوع',
      category: HabitCategory.fitness,
      cadence: QuickWinCadence.weekly,
      xpReward: _weeklyXp,
      goldReward: _weeklyGold,
      autoTrackTarget: 2,
    ),
    QuickWin(
      id: 'weekly_fast_2_days',
      titleEn: 'Fast Monday & Thursday this week',
      titleAr: 'صم الاثنين والخميس هذا الأسبوع',
      category: HabitCategory.fasting,
      cadence: QuickWinCadence.weekly,
      xpReward: _weeklyXp,
      goldReward: _weeklyGold,
      autoTrackTarget: 2,
    ),
    QuickWin(
      id: 'weekly_sadaqah_once',
      titleEn: 'Give sadaqah once this week',
      titleAr: 'تصدّق مرة واحدة هذا الأسبوع',
      category: HabitCategory.sadaqah,
      cadence: QuickWinCadence.weekly,
      xpReward: _weeklyXp,
      goldReward: _weeklyGold,
      autoTrackTarget: 1,
    ),
    QuickWin(
      id: 'weekly_plan_4_nights',
      titleEn: 'Plan tomorrow 4 nights this week',
      titleAr: 'خطّط ليوم الغد 4 ليالٍ هذا الأسبوع',
      category: HabitCategory.custom,
      cadence: QuickWinCadence.weekly,
      xpReward: _weeklyXp,
      goldReward: _weeklyGold,
      // `custom` is a catch-all bucket that also covers totally unrelated
      // habits (marriage check-ins, cold showers, ...), so "any active
      // custom-category habit" isn't a safe stand-in for "the user's
      // planning habit specifically" — manual mark-done instead of a
      // false-positive auto-track.
      autoTrackTarget: null,
    ),
    QuickWin(
      id: 'weekly_focus_sessions_3',
      titleEn: 'Complete 3 focus sessions this week',
      titleAr: 'أكمل 3 جلسات تركيز هذا الأسبوع',
      category: HabitCategory.custom,
      cadence: QuickWinCadence.weekly,
      xpReward: _weeklyXp,
      goldReward: _weeklyGold,
      // No existing weekly focus-session counter to track this against —
      // manual mark-done rather than building one just for this entry.
      autoTrackTarget: null,
    ),
  ];

  static QuickWin? findById(String id) {
    for (final w in daily) {
      if (w.id == id) return w;
    }
    for (final w in weekly) {
      if (w.id == id) return w;
    }
    return null;
  }
}
