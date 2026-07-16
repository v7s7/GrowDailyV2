import '../models/habit_model.dart';

/// A single "smart suggestion" — a pre-written habit name paired with the
/// goal type/category it belongs under. Shared between the Custom wizard's
/// suggestion chips ([AddHabitSheet]) and the Quick Add tab ([AddHabitHub]),
/// so both surfaces stay in sync from one list instead of drifting apart.
class GoalSuggestion {
  final GoalType type;
  final HabitCategory category;
  final String en;
  final String ar;
  const GoalSuggestion(this.type, this.category, this.en, this.ar);
  String name(bool isAr) => isAr ? ar : en;
}

const goalSuggestions = <GoalSuggestion>[
  GoalSuggestion(GoalType.build, HabitCategory.faith, 'Read Quran', 'قراءة القرآن'),
  GoalSuggestion(GoalType.build, HabitCategory.faith, 'Morning athkar', 'أذكار الصباح'),
  GoalSuggestion(GoalType.build, HabitCategory.faith, 'Evening athkar', 'أذكار المساء'),
  GoalSuggestion(GoalType.build, HabitCategory.faith, 'Fast Monday/Thursday', 'صيام الاثنين/الخميس'),
  GoalSuggestion(GoalType.quit, HabitCategory.faith, 'Reduce missed prayers', 'تقليل فوات الصلاة'),
  GoalSuggestion(GoalType.quit, HabitCategory.faith, 'Avoid delaying prayer', 'عدم تأخير الصلاة'),
  GoalSuggestion(GoalType.quit, HabitCategory.faith, 'Less phone before Quran', 'تقليل الجوال قبل القرآن'),
  GoalSuggestion(GoalType.build, HabitCategory.health, 'Walk 10 minutes', 'المشي 10 دقائق'),
  GoalSuggestion(GoalType.build, HabitCategory.health, 'Drink water', 'شرب الماء'),
  GoalSuggestion(GoalType.build, HabitCategory.health, 'Stretch', 'تمارين إطالة'),
  GoalSuggestion(GoalType.build, HabitCategory.health, 'Gym session', 'جلسة رياضة'),
  GoalSuggestion(GoalType.quit, HabitCategory.health, 'No sugar', 'بدون سكر'),
  GoalSuggestion(GoalType.quit, HabitCategory.health, 'No junk food', 'بدون أكل سريع'),
  GoalSuggestion(GoalType.quit, HabitCategory.health, 'Reduce caffeine', 'تقليل الكافيين'),
  GoalSuggestion(GoalType.quit, HabitCategory.health, 'No late snacks', 'بدون وجبات ليلية'),
  GoalSuggestion(GoalType.build, HabitCategory.learning, 'Read 10 pages', 'قراءة 10 صفحات'),
  GoalSuggestion(GoalType.build, HabitCategory.learning, 'Study 25 minutes', 'دراسة 25 دقيقة'),
  GoalSuggestion(GoalType.build, HabitCategory.learning, 'Review notes', 'مراجعة الملاحظات'),
  GoalSuggestion(GoalType.build, HabitCategory.learning, 'Practice language', 'تدريب لغة'),
  GoalSuggestion(GoalType.quit, HabitCategory.focus, 'No phone after 10 PM', 'بدون جوال بعد 10 مساءً'),
  GoalSuggestion(GoalType.quit, HabitCategory.focus, 'Reduce scrolling', 'تقليل التصفح'),
  GoalSuggestion(GoalType.quit, HabitCategory.focus, 'No gaming before study', 'بدون ألعاب قبل الدراسة'),
  GoalSuggestion(GoalType.quit, HabitCategory.focus, 'No social media in bed', 'بدون تواصل في السرير'),
  GoalSuggestion(GoalType.build, HabitCategory.sleep, 'Sleep by 11 PM', 'النوم قبل 11 مساءً'),
  GoalSuggestion(GoalType.build, HabitCategory.sleep, 'Wake up early', 'الاستيقاظ مبكرًا'),
  GoalSuggestion(GoalType.build, HabitCategory.sleep, 'Consistent bedtime', 'موعد نوم ثابت'),
  GoalSuggestion(GoalType.quit, HabitCategory.sleep, 'No phone before bed', 'بدون جوال قبل النوم'),
  GoalSuggestion(GoalType.quit, HabitCategory.sleep, 'No late naps', 'بدون قيلولة متأخرة'),
  GoalSuggestion(GoalType.quit, HabitCategory.sleep, 'No evening caffeine', 'بدون كافيين مساءً'),
  GoalSuggestion(GoalType.build, HabitCategory.money, 'Track spending', 'تتبّع المصروفات'),
  GoalSuggestion(GoalType.build, HabitCategory.money, 'Save 1 BHD', 'ادّخار 1 د.ب'),
  GoalSuggestion(GoalType.build, HabitCategory.money, 'Review budget', 'مراجعة الميزانية'),
  GoalSuggestion(GoalType.quit, HabitCategory.money, 'No impulse buying', 'بدون شراء اندفاعي'),
  GoalSuggestion(GoalType.quit, HabitCategory.money, 'Reduce delivery orders', 'تقليل طلبات التوصيل'),
  GoalSuggestion(GoalType.quit, HabitCategory.money, 'No unnecessary shopping', 'بدون تسوق غير ضروري'),
  GoalSuggestion(GoalType.build, HabitCategory.mind, 'Meditate 5 minutes', 'تأمل 5 دقائق'),
  GoalSuggestion(GoalType.build, HabitCategory.mind, 'Gratitude journal', 'يوميات الامتنان'),
  GoalSuggestion(GoalType.build, HabitCategory.mind, 'Breathing exercise', 'تمرين تنفس'),
  GoalSuggestion(GoalType.build, HabitCategory.mind, 'Positive affirmations', 'عبارات إيجابية'),
  GoalSuggestion(GoalType.build, HabitCategory.social, 'Call family', 'الاتصال بالعائلة'),
  GoalSuggestion(GoalType.build, HabitCategory.social, 'Check on a friend', 'الاطمئنان على صديق'),
  GoalSuggestion(GoalType.build, HabitCategory.social, 'Family dinner', 'عشاء عائلي'),
  GoalSuggestion(GoalType.build, HabitCategory.social, 'Visit a relative', 'زيارة قريب'),
];
