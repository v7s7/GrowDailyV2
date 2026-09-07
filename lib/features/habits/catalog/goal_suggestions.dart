import '../models/habit_model.dart';

/// A single "smart suggestion": a pre-written habit name paired with the
/// goal type and category it belongs under. Read by the Add Habit sheet's
/// suggestion chips, which appear only once a category is picked and show
/// only that category's entries for the chosen side (build or quit).
///
/// Every category the sheet offers has four suggestions on each side. That
/// is a rule, pinned by test/features/habits/goal_suggestions_test.dart,
/// because the sheet used to fall back to "the first six of this type" when
/// a category had none, and a person who had just tapped «التعلّم» was
/// shown chips about prayer and sugar (Aziz, 2026-09-08: "make the
/// suggestions related").
///
/// Wording: short noun phrases, no verb addressed to the person, so nothing
/// here has a gender. Digits stay Latin, as everywhere else in the app.
class GoalSuggestion {
  final GoalType type;
  final HabitCategory category;
  final String en;
  final String ar;
  const GoalSuggestion(this.type, this.category, this.en, this.ar);
  String name(bool isAr) => isAr ? ar : en;
}

const goalSuggestions = <GoalSuggestion>[
  // ── الإيمان ────────────────────────────────────────────────────────
  GoalSuggestion(GoalType.build, HabitCategory.faith, 'Read Quran', 'قراءة القرآن'),
  GoalSuggestion(GoalType.build, HabitCategory.faith, 'Morning athkar', 'أذكار الصباح'),
  GoalSuggestion(GoalType.build, HabitCategory.faith, 'Evening athkar', 'أذكار المساء'),
  GoalSuggestion(GoalType.build, HabitCategory.faith, 'Fast Monday/Thursday', 'صيام الاثنين/الخميس'),
  GoalSuggestion(GoalType.quit, HabitCategory.faith, 'No delaying prayer', 'بدون تأخير الصلاة'),
  GoalSuggestion(GoalType.quit, HabitCategory.faith, 'No missed Fajr', 'بدون فوات الفجر'),
  GoalSuggestion(GoalType.quit, HabitCategory.faith, 'No backbiting', 'بدون غيبة'),
  GoalSuggestion(GoalType.quit, HabitCategory.faith, 'Less phone before Quran', 'تقليل الجوال قبل القرآن'),

  // ── الصحة ──────────────────────────────────────────────────────────
  GoalSuggestion(GoalType.build, HabitCategory.health, 'Walk 10 minutes', 'المشي 10 دقائق'),
  GoalSuggestion(GoalType.build, HabitCategory.health, 'Drink water', 'شرب الماء'),
  GoalSuggestion(GoalType.build, HabitCategory.health, 'Stretch', 'تمارين إطالة'),
  GoalSuggestion(GoalType.build, HabitCategory.health, 'Gym session', 'جلسة رياضة'),
  GoalSuggestion(GoalType.quit, HabitCategory.health, 'No sugar', 'بدون سكر'),
  GoalSuggestion(GoalType.quit, HabitCategory.health, 'No junk food', 'بدون أكل سريع'),
  GoalSuggestion(GoalType.quit, HabitCategory.health, 'Reduce caffeine', 'تقليل الكافيين'),
  GoalSuggestion(GoalType.quit, HabitCategory.health, 'No late snacks', 'بدون وجبات ليلية'),

  // ── التعلّم ────────────────────────────────────────────────────────
  GoalSuggestion(GoalType.build, HabitCategory.learning, 'Read 10 pages', 'قراءة 10 صفحات'),
  GoalSuggestion(GoalType.build, HabitCategory.learning, 'Study 25 minutes', 'دراسة 25 دقيقة'),
  GoalSuggestion(GoalType.build, HabitCategory.learning, 'Review notes', 'مراجعة الملاحظات'),
  GoalSuggestion(GoalType.build, HabitCategory.learning, 'Practice a language', 'تدريب لغة'),
  GoalSuggestion(GoalType.quit, HabitCategory.learning, 'No scrolling while studying', 'بدون تصفح أثناء الدراسة'),
  GoalSuggestion(GoalType.quit, HabitCategory.learning, 'No postponing revision', 'بدون تأجيل المراجعة'),
  GoalSuggestion(GoalType.quit, HabitCategory.learning, 'No all-nighters before exams', 'بدون سهر قبل الاختبار'),
  GoalSuggestion(GoalType.quit, HabitCategory.learning, 'No distractions', 'بدون تشتيت'),

  // ── التركيز ────────────────────────────────────────────────────────
  GoalSuggestion(GoalType.build, HabitCategory.focus, 'Deep work 25 minutes', 'عمل عميق 25 دقيقة'),
  GoalSuggestion(GoalType.build, HabitCategory.focus, "Plan today's top 3", 'تحديد أهم 3 مهام لليوم'),
  GoalSuggestion(GoalType.build, HabitCategory.focus, 'One phone-free hour', 'ساعة بدون جوال'),
  GoalSuggestion(GoalType.build, HabitCategory.focus, 'One task at a time', 'مهمة واحدة كل مرة'),
  GoalSuggestion(GoalType.quit, HabitCategory.focus, 'No phone after 10 PM', 'بدون جوال بعد 10 مساءً'),
  GoalSuggestion(GoalType.quit, HabitCategory.focus, 'Reduce scrolling', 'تقليل التصفح'),
  GoalSuggestion(GoalType.quit, HabitCategory.focus, 'No gaming before study', 'بدون ألعاب قبل الدراسة'),
  GoalSuggestion(GoalType.quit, HabitCategory.focus, 'No social media in bed', 'بدون سوشال في السرير'),

  // ── النوم ──────────────────────────────────────────────────────────
  GoalSuggestion(GoalType.build, HabitCategory.sleep, 'Sleep by 11 PM', 'النوم قبل 11 مساءً'),
  GoalSuggestion(GoalType.build, HabitCategory.sleep, 'Wake up early', 'الاستيقاظ مبكرًا'),
  GoalSuggestion(GoalType.build, HabitCategory.sleep, 'Consistent bedtime', 'موعد نوم ثابت'),
  GoalSuggestion(GoalType.build, HabitCategory.sleep, 'Wind down before bed', 'استرخاء قبل النوم'),
  GoalSuggestion(GoalType.quit, HabitCategory.sleep, 'No phone before bed', 'بدون جوال قبل النوم'),
  GoalSuggestion(GoalType.quit, HabitCategory.sleep, 'No late naps', 'بدون قيلولة متأخرة'),
  GoalSuggestion(GoalType.quit, HabitCategory.sleep, 'No evening caffeine', 'بدون كافيين مساءً'),
  GoalSuggestion(GoalType.quit, HabitCategory.sleep, 'No screens in the bedroom', 'بدون شاشات في غرفة النوم'),

  // ── المال ──────────────────────────────────────────────────────────
  GoalSuggestion(GoalType.build, HabitCategory.money, 'Track spending', 'تتبّع المصروفات'),
  GoalSuggestion(GoalType.build, HabitCategory.money, 'Save 1 BHD', 'ادّخار 1 د.ب'),
  GoalSuggestion(GoalType.build, HabitCategory.money, 'Review budget', 'مراجعة الميزانية'),
  GoalSuggestion(GoalType.build, HabitCategory.money, 'Compare prices', 'مقارنة الأسعار'),
  GoalSuggestion(GoalType.quit, HabitCategory.money, 'No impulse buying', 'بدون شراء اندفاعي'),
  GoalSuggestion(GoalType.quit, HabitCategory.money, 'Reduce delivery orders', 'تقليل طلبات التوصيل'),
  GoalSuggestion(GoalType.quit, HabitCategory.money, 'No unnecessary shopping', 'بدون تسوق غير ضروري'),
  GoalSuggestion(GoalType.quit, HabitCategory.money, 'No coffee from outside', 'بدون قهوة من برّا'),

  // ── العقل ──────────────────────────────────────────────────────────
  GoalSuggestion(GoalType.build, HabitCategory.mind, 'Meditate 5 minutes', 'تأمل 5 دقائق'),
  GoalSuggestion(GoalType.build, HabitCategory.mind, 'Gratitude journal', 'يوميات الامتنان'),
  GoalSuggestion(GoalType.build, HabitCategory.mind, 'Breathing exercise', 'تمرين تنفس'),
  GoalSuggestion(GoalType.build, HabitCategory.mind, 'Positive affirmations', 'عبارات إيجابية'),
  GoalSuggestion(GoalType.quit, HabitCategory.mind, 'No complaining', 'بدون تذمّر'),
  GoalSuggestion(GoalType.quit, HabitCategory.mind, 'No comparisons', 'بدون مقارنات'),
  GoalSuggestion(GoalType.quit, HabitCategory.mind, 'No overthinking before bed', 'بدون تفكير زائد قبل النوم'),
  GoalSuggestion(GoalType.quit, HabitCategory.mind, 'No news in the morning', 'بدون أخبار في الصباح'),

  // ── العلاقات ───────────────────────────────────────────────────────
  GoalSuggestion(GoalType.build, HabitCategory.social, 'Call family', 'الاتصال بالعائلة'),
  GoalSuggestion(GoalType.build, HabitCategory.social, 'Check on a friend', 'الاطمئنان على صديق'),
  GoalSuggestion(GoalType.build, HabitCategory.social, 'Family dinner', 'عشاء عائلي'),
  GoalSuggestion(GoalType.build, HabitCategory.social, 'Visit a relative', 'زيارة قريب'),
  GoalSuggestion(GoalType.quit, HabitCategory.social, 'No phone at the table', 'بدون جوال على السفرة'),
  GoalSuggestion(GoalType.quit, HabitCategory.social, 'No arguing in comments', 'بدون جدال في التعليقات'),
  GoalSuggestion(GoalType.quit, HabitCategory.social, 'Less time in group chats', 'تقليل وقت القروبات'),
  GoalSuggestion(GoalType.quit, HabitCategory.social, 'No interrupting', 'بدون مقاطعة الآخرين'),

  // ── مخصص ───────────────────────────────────────────────────────────
  GoalSuggestion(GoalType.build, HabitCategory.custom, 'Make the bed', 'ترتيب السرير'),
  GoalSuggestion(GoalType.build, HabitCategory.custom, 'Tidy for 10 minutes', 'ترتيب 10 دقائق'),
  GoalSuggestion(GoalType.build, HabitCategory.custom, 'Plan tomorrow', 'تخطيط يوم الغد'),
  GoalSuggestion(GoalType.build, HabitCategory.custom, 'Water the plants', 'سقي النباتات'),
  GoalSuggestion(GoalType.quit, HabitCategory.custom, 'No snoozing the alarm', 'بدون تأجيل المنبّه'),
  GoalSuggestion(GoalType.quit, HabitCategory.custom, 'No dishes left overnight', 'بدون صحون لليوم الثاني'),
  GoalSuggestion(GoalType.quit, HabitCategory.custom, 'No arriving late', 'بدون تأخير على المواعيد'),
  GoalSuggestion(GoalType.quit, HabitCategory.custom, 'No postponing the first task', 'بدون تأجيل أول مهمة'),
];

/// The suggestions for one side of one category, in list order. Empty is a
/// possible answer only for a category the sheet does not offer; for the
/// nine it does, the test above guarantees four.
List<GoalSuggestion> suggestionsFor(GoalType type, HabitCategory category) =>
    goalSuggestions
        .where((s) => s.type == type && s.category == category)
        .toList();
