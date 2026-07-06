import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/intention_phrase.dart';

// ─── Locale provider ──────────────────────────────────────────────────────────

final localeProvider = StateNotifierProvider<_LocaleNotifier, Locale>(
  (_) => _LocaleNotifier(),
);

class _LocaleNotifier extends StateNotifier<Locale> {
  _LocaleNotifier() : super(const Locale('en'));

  void toggle() => state = state.languageCode == 'en'
      ? const Locale('ar')
      : const Locale('en');

  void set(Locale locale) => state = locale;
}

// ─── Strings ──────────────────────────────────────────────────────────────────

class S {
  final Locale locale;
  const S(this.locale);

  static S of(BuildContext context) {
    return S(Localizations.localeOf(context));
  }

  bool get isAr => locale.languageCode == 'ar';

  // ── App ──────────────────────────────────────────────────────────────────
  String get appTitle => isAr ? 'GrowDaily' : 'GrowDaily';
  String get tagline =>
      isAr ? 'لوّن حياتك، مربّعًا كل يوم.' : 'Color your life, one square at a time.';

  // ── Auth ─────────────────────────────────────────────────────────────────
  String get signIn => isAr ? 'تسجيل الدخول' : 'Sign In';
  String get createAccount => isAr ? 'إنشاء حساب' : 'Create Account';
  String get signInAction => isAr ? 'دخول' : 'SIGN IN';
  String get createAccountAction => isAr ? 'إنشاء الحساب' : 'CREATE ACCOUNT';
  String get email => isAr ? 'البريد الإلكتروني' : 'Email';
  String get password => isAr ? 'كلمة المرور' : 'Password';
  String get confirmPassword => isAr ? 'تأكيد كلمة المرور' : 'Confirm Password';
  String get tryAsGuest => isAr ? 'جرّب 3 عادات كضيف' : 'TRY 3 HABITS AS GUEST';
  String get guestDescription =>
      isAr ? 'لا حاجة لحساب. ابدأ أولى انتصاراتك الآن.' : 'No account needed. Complete your first Quran, athkar, or focus win now.';
  String get guestLimitTitle => isAr ? 'وصلت لحد التجربة' : "You've hit the guest limit";
  String get guestLimitBody => isAr
      ? 'التجربة كضيف تسمح بـ 3 عادات. أنشئ حسابًا مجانيًا لإضافة عدد غير محدود ومزامنة تقدمك.'
      : 'Guest mode is capped at 3 habits. Create a free account to add unlimited habits and keep your progress synced.';
  String get guestLimitCta => isAr ? 'إنشاء حساب مجاني' : 'Create free account';
  String get guestLimitMaybeLater => isAr ? 'ربما لاحقاً' : 'Maybe later';

  // Auth errors
  String get errFillAll => isAr ? 'يرجى ملء جميع الحقول' : 'Please fill in all fields';
  String get errPasswordsMismatch => isAr ? 'كلمتا المرور غير متطابقتين' : 'Passwords do not match';
  String get errPasswordTooShort =>
      isAr ? 'كلمة المرور يجب أن تكون 6 أحرف على الأقل' : 'Password must be at least 6 characters';
  String get errInvalidCredential =>
      isAr ? 'البريد الإلكتروني أو كلمة المرور غير صحيحة' : 'Invalid email or password';
  String get errEmailInUse =>
      isAr ? 'يوجد حساب بهذا البريد الإلكتروني بالفعل' : 'An account with this email already exists';
  String get errInvalidEmail => isAr ? 'بريد إلكتروني غير صالح' : 'Invalid email address';
  String get errWeakPassword =>
      isAr ? 'كلمة المرور ضعيفة (6 أحرف على الأقل)' : 'Password is too weak (min 6 characters)';
  String get errNetwork =>
      isAr ? 'تحقق من اتصالك بالإنترنت' : 'Check your internet connection';
  String get errGeneric => isAr ? 'حدث خطأ. حاول مجدداً.' : 'Something went wrong. Try again.';

  // ── Dashboard ────────────────────────────────────────────────────────────
  String get todaysHabits => isAr ? 'عادات اليوم' : "TODAY'S HABITS";
  String get addHabit => isAr ? 'إضافة عادة' : 'ADD HABIT';
  String get signOut => isAr ? 'تسجيل الخروج' : 'Sign Out';
  String get level => isAr ? 'المستوى' : 'LEVEL';
  String get totalXp => isAr ? 'مجموع XP' : 'TOTAL XP';
  String get streak => isAr ? 'السلسلة' : 'STREAK';
  String get freeze => isAr ? 'تجميد' : 'FREEZE';
  String get gold => isAr ? 'ذهب' : 'GOLD';
  String get active => isAr ? 'نشطة' : 'active';
  String activeCount(int n) => isAr ? '$n نشطة' : '$n active';

  // Intention card
  String get todaysIntention => isAr ? 'نية اليوم' : "Today's intention";
  String get pickTinyWin => isAr ? 'اختر انتصاراً صغيراً' : 'Pick one tiny win';
  String get pickOneGoal =>
      isAr ? 'اختر هدفاً لدينك أو عملك أو صحتك.' : 'Choose one goal for your deen, work, or health.';

  // Snackbars / sheets
  String streakFreezeProtected(int remaining) => isAr
      ? 'تجميد السلسلة حماك. متبقّي $remaining.'
      : 'Streak Freeze protected you. $remaining left.';
  String get claimComeback => isAr ? 'استلم +50 XP عودة' : 'Claim +50 XP comeback';
  String welcomeBack(String name) => isAr ? 'مرحبًا بعودتك، $name' : 'Welcome back, $name';
  String get comebackNoErase => isAr
      ? 'اليوم الفائت لا يمحو تقدمك.'
      : "A missed day doesn't erase your progress.";
  String get comebackBonusHint =>
      isAr ? '+50 XP مكافأة عودة عند المتابعة' : '+50 XP comeback bonus when you continue';
  String restoreStreakOffer(int days) => isAr
      ? 'استخدم تجميد السلسلة لاستعادة سلسلتك ذات $days يوم بدلاً من البدء من جديد.'
      : "Use a streak freeze to restore your $days-day streak instead of starting over.";
  String restoreStreakCta(int left) =>
      isAr ? 'استعادة السلسلة ($left متبقّية)' : 'Restore streak ($left left)';
  String get freshStreakInstead => isAr ? 'ابدأ سلسلة جديدة بدلاً من ذلك' : 'Start a fresh streak instead';
  String get keepGrowing => isAr ? 'واصل النمو' : 'Keep growing';
  String get streakMilestoneLabel => isAr ? 'إنجاز السلسلة' : 'STREAK MILESTONE';
  String daysCount(int n) => isAr ? '$n يوم' : '$n Days';
  String nowWarrior(String title) => isAr ? 'أنت الآن $title.' : 'You are now a $title.';
  String get consistencyBuildsCharacter => isAr
      ? 'الاتساق يبني الشخصية — استمر بالحضور.'
      : 'Consistency builds character — keep showing up.';
  String milestoneBonusXp(int bonus) =>
      isAr ? '+$bonus XP مكافأة الإنجاز' : '+$bonus XP milestone bonus';
  String get achievementUnlocked => isAr ? 'إنجاز مفتوح!' : 'ACHIEVEMENT UNLOCKED';
  String get claimReward => isAr ? 'استلم المكافأة' : 'CLAIM REWARD';
  String get levelUpMsg => isAr ? 'ارتقاء مستوى' : 'LEVEL UP';

  // ── Profile ──────────────────────────────────────────────────────────────
  String get profile => isAr ? 'الملف الشخصي' : 'Profile';
  String get achievements => isAr ? 'الإنجازات' : 'ACHIEVEMENTS';
  String get settings => isAr ? 'الإعدادات' : 'SETTINGS';
  String get darkMode => isAr ? 'الوضع الداكن' : 'Dark Mode';
  String get language => isAr ? 'اللغة' : 'Language';
  String get languageAr => isAr ? 'العربية' : 'Arabic';
  String get languageEn => isAr ? 'English' : 'English';
  String get cumulativeXp => isAr ? 'مجموع XP' : 'cumulative XP';
  String xpToLevel(int n) => isAr ? '$n XP للمستوى ${n + 1}' : 'XP to Level $n';
  String xpProgress(int current, int total, int nextLevel) => isAr
      ? '$current / $total XP للمستوى $nextLevel'
      : '$current / $total XP to Level $nextLevel';
  String get best => isAr ? 'أفضل' : 'BEST';
  String get total => isAr ? 'المجموع' : 'TOTAL';

  // Progress report
  String get fourteenDayProgress => isAr ? 'تقدم 14 يوم' : '14-day progress';
  String get holdingStrong => isAr ? 'أسبوعك الأخير قوي.' : 'Your recent week is holding strong.';
  String get startAgain => isAr ? 'الانتصارات الصغيرة تُعتبر. ابدأ اليوم مجدداً.' : 'Tiny wins still count. Start again today.';
  String get loadingReport => isAr ? 'جارٍ تحميل تقرير الاتساق...' : 'Loading your consistency report...';
  String get activeDays => isAr ? 'الأيام النشطة' : 'ACTIVE DAYS';
  String get bestDay => isAr ? 'أفضل يوم' : 'BEST DAY';

  // Streak Freeze card
  String get streakFreeze => isAr ? 'تجميد السلسلة' : 'Streak Freeze';
  String streakFreezeStatus(int current, int max) => isAr
      ? '$current/$max جاهز · المستوى 5+ يُعيد الشحن أسبوعياً'
      : '$current/$max ready · Level 5+ refills weekly';

  // ── Plan Picker ──────────────────────────────────────────────────────────
  String get choosePlan => isAr ? 'اختر خطتك' : 'Choose Your Plan';
  String get choosePlanSubtitle => isAr
      ? 'حزمة عادات جاهزة بنقرة واحدة.'
      : 'Start with a ready-made habit bundle.';
  String get startPlan => isAr ? 'ابدأ الخطة' : 'Start Plan';
  String get deactivatePlan => isAr ? 'إيقاف الخطة' : 'Deactivate';
  String get browsePlans => isAr ? 'استعرض الخطط' : 'Browse Plans';
  String get dailyReminder => isAr ? 'تذكير يومي' : 'Daily Reminder';
  String get tapToSetReminder => isAr ? 'اضغط لتعيين وقت التذكير' : 'Tap to set reminder time';

  // ── Empty state ───────────────────────────────────────────────────────────
  String get noHabitsYet => isAr ? 'لا عادات بعد' : 'No habits yet';
  String get noHabitsDesc => isAr
      ? 'ابدأ بخطة جاهزة أو أنشئ عادتك الخاصة.'
      : 'Start with a ready plan or create your own habit.';
  String get allDoneTitle => isAr ? 'أحسنت!' : 'ALL DONE!';
  String get allDoneSubtitle => isAr
      ? 'كل عادات اليوم مكتملة. استمر!'
      : 'All habits complete for today. Keep it up!';
  String get removeHabit => isAr ? 'إزالة العادة' : 'Remove habit';
  String get editHabitAction => isAr ? 'تعديل العادة' : 'Edit habit';

  // ── Add Habit Sheet ──────────────────────────────────────────────────────
  String get newHabit => isAr ? 'عادة جديدة' : 'NEW HABIT';
  String get editHabit => isAr ? 'تعديل العادة' : 'EDIT HABIT';
  String get saveChanges => isAr ? 'احفظ التغييرات' : 'SAVE CHANGES';
  String get habitNameHint => isAr ? 'ما العادة التي تريد بناءها؟' : 'What habit do you want to build?';
  String get afterWhatRoutine => isAr ? 'بعد أي روتين؟ (اختياري)' : 'After what routine? (optional)';
  String get routineHint => isAr ? 'الفجر، المغرب، قبل النوم...' : 'Fajr, Maghrib, before sleep...';
  String get category => isAr ? 'الفئة' : 'CATEGORY';
  String get frequency => isAr ? 'التكرار' : 'FREQUENCY';
  String get daily => isAr ? 'يومياً' : 'Daily';
  String get weekly => isAr ? 'أسبوعياً' : 'Weekly';
  String get times => isAr ? 'مرات:' : 'Times:';
  String get createHabit => isAr ? 'أنشئ العادة' : 'CREATE TINY HABIT';
  String get smartStarters => isAr ? 'بدايات ذكية' : 'SMART STARTERS';
  // A cue like "Fajr" reads naturally as "After Fajr, I will X." — but a
  // cue that already carries its own preposition, like "Before sleep",
  // would read as "After Before sleep, I will X." if we always prepended
  // "After"/"بعد". Detect that case so the preview stays grammatical no
  // matter which routine anchor the user picks or types.
  String planPreview(String cue, String habit) {
    final trimmedCue = cue.trim();
    final selfContained = cueHasOwnPreposition(trimmedCue);
    if (isAr) {
      final clause = selfContained ? trimmedCue : 'بعد $trimmedCue';
      return '$clause، سأقوم بـ $habit.';
    }
    final clause = selfContained
        ? capitalizeFirst(trimmedCue)
        : 'After $trimmedCue';
    return '$clause, I will $habit.';
  }
  String get tinyHintDefault => isAr
      ? 'اجعلها صغيرة لدرجة أنك تستطيع فعلها حتى في أصعب يوم.'
      : 'Make it tiny enough that you can do it even on a hard day.';
  String get tinyHintQuran => isAr
      ? 'اجعلها صغيرة: ابدأ بـ 3 آيات أو صفحة بعد الصلاة.'
      : 'Make it tiny: start with 3 ayat or one page after a prayer.';
  String get tinyHintAthkar => isAr
      ? 'اجعلها صغيرة: ابدأ بمجموعة أذكار قصيرة بعد الصلاة.'
      : 'Make it tiny: begin with one short athkar set after prayer.';
  String get tinyHintFitness => isAr
      ? 'اجعلها صغيرة: 5-10 دقائق كافية في الأيام الصعبة.'
      : 'Make it tiny: 5–10 minutes is enough on low-energy days.';
  String get tinyHintSleep => isAr
      ? 'اجعلها صغيرة: ضع إشارة بسيطة قبل النوم.'
      : 'Make it tiny: set a simple wind-down cue before sleep.';

  // ── Focus ────────────────────────────────────────────────────────────────
  String get focus => isAr ? 'التركيز' : 'Focus';
  String get focusTitle => isAr ? 'وقت التركيز' : 'Focus Time';
  String get focusDailyTitle => isAr ? 'تركيز اليوم' : 'Daily Focus';
  String get focusTagline => isAr ? 'خطة واضحة. انتصار نظيف.' : 'One clear plan. One clean win.';
  String focusRitualProgress(int done) => isAr ? '$done/3 خطوة مكتملة' : '$done/3 ritual steps complete';
  String get focusMostImportantTask => isAr ? 'أهم مهمة' : 'Most important task';
  String get focusMitSubtitle => isAr ? 'اختر النتيجة التي تجعل يومك منتجاً.' : 'Pick the one outcome that makes today productive.';
  String get focusIfThenPlan => isAr ? 'خطة إذا / سأفعل' : 'IF / THEN PLAN';
  String get focusTopTaskHint => isAr ? 'مثال: أنهِ تدفق الإدخال' : 'Example: Finish the onboarding flow';
  String get focusTopTaskLabel => isAr ? 'أهم مهمة' : 'Top task';
  String get focusCuePrefix => isAr ? 'إذا ' : 'If ';
  String get focusCueHint => isAr ? 'الساعة 9 على مكتبي' : 'it is 9:00 at my desk';
  String get focusCueLabel => isAr ? 'الإشارة: متى وأين' : 'Cue: when and where';
  String get focusActionPrefix => isAr ? 'سأفعل ' : 'I will ';
  String get focusActionHint => isAr ? 'ابدأ سبرنت تركيز 25 دقيقة' : 'start a 25-minute focus sprint';
  String get focusActionLabel => isAr ? 'الفعل: الخطوة التالية الدقيقة' : 'Action: exact next move';
  String get focusSavePlan => isAr ? 'احفظ خطة اليوم' : "Save today's plan";
  String get focusPlanSaved => isAr ? 'تم حفظ خطة التركيز لليوم.' : 'Focus plan saved for today.';
  String get focusTimerTitle => isAr ? 'مؤقت التركيز' : 'Focus timer';
  String get focusTimerSubtitle => isAr ? 'ابقَ في التطبيق بدلاً من التنقل.' : 'Stay inside GrowDaily instead of switching apps.';
  String get focusPauseSprint => isAr ? 'إيقاف السبرنت' : 'Pause sprint';
  String get focusStartSprint => isAr ? 'ابدأ السبرنت' : 'Start sprint';
  String get focusResetTimer => isAr ? 'إعادة المؤقت' : 'Reset timer';
  String get focusReady => isAr ? 'جاهز' : 'READY';
  String get focusFocusing => isAr ? 'أركّز الآن' : 'FOCUSING';
  String get focusComplete => isAr ? 'مكتمل' : 'COMPLETE';
  String focusMinutesLabel(int m) => isAr ? '$m د' : '$m min';
  String focusXpOnCompletion(int xp) =>
      isAr ? '+$xp XP عند الإكمال' : '+$xp XP on completion';
  String get focusSessionCompleteTitle =>
      isAr ? 'اكتملت جلسة التركيز' : 'FOCUS SESSION COMPLETE';
  String get focusDeepWorkDone => isAr ? 'أنجزت عملاً عميقاً' : 'Deep Work Done';
  String focusStayedFocused(String label) => isAr
      ? 'ركّزت لمدة $label. الجلسات الصغيرة تبني عقلاً قويًا.'
      : 'You stayed focused for $label. Small sessions build a strong mind.';
  String get focusGreatWork => isAr ? 'عمل رائع' : 'GREAT WORK';
  String get focusRitualTitle => isAr ? 'طقوس اليوم النظيفة' : 'Clean daily ritual';
  String get focusRitualSubtitle => isAr ? 'صغيرة للتكرار، منظمة للعمل.' : 'Small enough to repeat, structured enough to work.';
  String get focusRitualPlanWin => isAr ? 'خطط للانتصار الواحد' : 'Plan the one win';
  String get focusRitualChooseTask => isAr ? 'اختر مهمتك الأهم' : 'Choose your top task';
  String get focusRitualRunSprint => isAr ? 'قم بسبرنت تركيز' : 'Run a focus sprint';
  String focusRitualSprintsLogged(int n) => isAr ? '$n سبرنت مسجل اليوم' : '$n sprint${n == 1 ? '' : 's'} logged today';
  String get focusRitualReview => isAr ? 'مراجعة وإغلاق الحلقة' : 'Review and close the loop';
  String get focusRitualReviewSubtitle => isAr ? 'سجّل ما نجح حتى يبدأ الغد أخف' : 'Mark what worked so tomorrow starts lighter';
  String get focusLogSprint => isAr ? 'سجّل سبرنت 25 دقيقة' : 'Log 25-min sprint';
  String get focusResetToday => isAr ? 'إعادة اليوم' : 'Reset today';
  String get focusWhyTitle => isAr ? 'لماذا هذا موجود' : 'Why this is here';
  String get focusWhySubtitle => isAr ? 'مستوحى من أنماط مثبتة دون فوضى.' : 'Inspired by proven patterns in top planners without adding clutter.';
  String get focusIfThenCueTitle => isAr ? 'إشارة إذا / سأفعل' : 'If / then cue';
  String get focusIfThenCueBody => isAr ? 'يحوّل الأهداف المبهمة إلى خطوة محددة بالمكان والوقت.' : 'Turns vague goals into a specific when-and-where action.';
  String get focusOneTaskTitle => isAr ? 'مهمة واحدة فقط' : 'One top task';
  String get focusOneTaskBody => isAr ? 'يتجنب التخطيط المفرط ويوضح الانتصار التالي.' : 'Avoids over-planning and makes the next win obvious.';
  String get focusSprintTitle => isAr ? 'سبرنت تركيز قصير' : 'Short focus sprint';
  String get focusSprintBody => isAr ? 'حلقة خفيفة كما تستخدمها تطبيقات الإنتاجية الكبرى.' : 'A light Pomodoro-style loop like leading productivity apps use.';

  // ── Habit card ───────────────────────────────────────────────────────────
  String get habitDaily => isAr ? 'يومياً' : 'Daily';
  String habitWeeklyTimes(int n) => isAr ? '${n}x / أسبوع' : '${n}x / week';
  String habitAfterCue(String cue) => isAr ? '  ·  بعد $cue' : '  ·  After $cue';
  String get habitDone => isAr ? 'تم' : 'DONE';
  String get habitComplete => isAr ? 'أتمم' : 'COMPLETE';

  // ── Goals Matrix ─────────────────────────────────────────────────────────
  String get goals => isAr ? 'الأهداف' : 'Goals';
  String get goalsMatrix => isAr ? 'مصفوفة الأهداف' : 'Goals Matrix';
  String get matrixSubtitle =>
      isAr ? 'رتّب أهدافك لتحافظ على وضوح الأولويات.'
           : 'Sort your goals so deen and priorities stay clear.';
  String get matrixUrgent => isAr ? 'عاجل' : 'URGENT';
  String get matrixNotUrgent => isAr ? 'غير عاجل' : 'NOT URGENT';
  String get matrixImportant => isAr ? 'مهم' : 'IMPORTANT';
  String get matrixNotImportant => isAr ? 'غير مهم' : 'NOT IMPORTANT';
  String get matrixTapToAdd => isAr ? 'اضغط + للإضافة' : 'Tap + to add';
  String get matrixAddTask => isAr ? 'أضف مهمة' : 'ADD TASK';
  String get matrixWhatToDo => isAr ? 'ما الذي يجب فعله؟' : 'What needs to be done?';
  String get matrixMoveToQuadrant => isAr ? 'انقل إلى ربع' : 'MOVE TO QUADRANT';

  // ── Navigation ───────────────────────────────────────────────────────────
  String get navDashboard => isAr ? 'الرئيسية' : 'Dashboard';
  String get navGrid => isAr ? 'الشبكة' : 'Grid';
  String get navFocus => isAr ? 'التركيز' : 'Focus';
  String get navGoals => isAr ? 'الأهداف' : 'Goals';
  String get navProfile => isAr ? 'ملفي' : 'Profile';

  // ── Victory Grid ─────────────────────────────────────────────────────────
  String get gridTitle => isAr ? 'شبكة الانتصارات' : 'Victory Grid';
  String get gridSlogan =>
      isAr ? 'لوّن حياتك، مربّعًا كل يوم.' : 'Color your life, one square at a time.';
  String get gridThisWeek => isAr ? 'هذا الأسبوع' : 'This week';
  String get gridGreenSquares => isAr ? 'مربّعات خضراء' : 'Green squares';
  String get gridPoints => isAr ? 'النقاط' : 'Points';
  String get gridComplete => isAr ? 'الإكمال' : 'Complete';
  String get gridWeekFilled => isAr ? 'اكتمل الأسبوع!' : 'Week filled!';
  String get gridPerfectDay =>
      isAr ? 'يوم مثالي — كل مربّعات اليوم خضراء!' : 'Perfect day — every square is green!';
  String gridGreensToday(int n) =>
      isAr ? 'كسبت $n مربّعًا أخضر اليوم' : 'You earned $n green squares today';
  String get gridTapHint => isAr
      ? 'اضغط لتلوين المربّع · اضغط مطولاً للمزيد من الألوان'
      : 'Tap to color · long-press for more colors';
  String get gridLegend => isAr ? 'الألوان' : 'Legend';
  String get gridEmptyTitle => isAr ? 'لا توجد عادات بعد' : 'No habits to track yet';
  String get gridEmptyDesc => isAr
      ? 'أضف عادات من الرئيسية لتبدأ بتلوين أسبوعك.'
      : 'Add a few habits from the Dashboard to start coloring your week.';
  String get gridGoToDashboard => isAr ? 'الذهاب للرئيسية' : 'Go to Dashboard';
  String get gridEditSquare => isAr ? 'حدّد المربّع' : 'Set this square';
  String get gridNoteLabel => isAr ? 'ماذا حدث اليوم؟' : 'What happened today?';
  String get gridNoteHint =>
      isAr ? 'اكتب انعكاسًا قصيرًا…' : 'Write a short reflection…';
  String get gridSave => isAr ? 'حفظ' : 'Save';
  String get gridFutureDay => isAr ? 'يوم قادم' : 'Future day';

  // ── Monthly Heatmap ──────────────────────────────────────────────────────
  String get heatmapTitle => isAr ? 'خريطة التقدّم' : 'Progress Heatmap';
  String get heatmapSubtitle => isAr
      ? 'كثافة الإنجاز عبر الأشهر — كل مربّع يومٌ، وكل درجة لون كثافة انتصاراتك.'
      : "Your completion density across months — every square is a day, every shade is how much you colored it.";
  String get heatmapTotalGreen => isAr ? 'مربّعات خضراء' : 'Green squares';
  String get heatmapActiveDays => isAr ? 'أيام نشطة' : 'Active days';
  String get heatmapBestDay => isAr ? 'أفضل يوم' : 'Best day';
  String get heatmapLess => isAr ? 'أقل' : 'Less';
  String get heatmapMore => isAr ? 'أكثر' : 'More';

  // ── Night Review ─────────────────────────────────────────────────────────
  String get nightReviewTitle => isAr ? 'مراجعة الليل' : 'Night Review';
  String get nightReviewPromptTitle =>
      isAr ? 'كيف كان يومك؟' : 'How was your day?';
  String get nightReviewPromptDesc => isAr
      ? 'مراجعة مسائية قصيرة قبل النوم — مزاجك، انعكاسك، وانتصارات اليوم.'
      : 'A short evening check-in before bed — your mood, a reflection, and today\'s wins.';
  String get nightReviewMoodQuestion =>
      isAr ? 'اختر مزاجك' : 'Select your mood';
  String get nightReviewReflectionLabel =>
      isAr ? 'ماذا حدث اليوم؟' : 'What happened today?';
  String get nightReviewReflectionHint =>
      isAr ? 'اكتب بضع كلمات عن يومك…' : 'Write a few words about your day…';
  String get nightReviewSummaryTitle =>
      isAr ? 'ملخّص اليوم' : "Today's summary";
  String get nightReviewXpEarned => isAr ? 'نقاط الخبرة' : 'XP earned';
  String get nightReviewGreenSquares =>
      isAr ? 'مربّعات خضراء' : 'Green squares';
  String get nightReviewStreak => isAr ? 'السلسلة' : 'Streak';
  String get nightReviewSave => isAr ? 'حفظ المراجعة' : 'Save review';
  String get nightReviewSaved => isAr ? 'تم حفظ مراجعتك الليلية' : 'Night review saved';
  String get nightReviewDoneBadge => isAr ? 'تمت المراجعة' : 'Reviewed';
  String get nightReviewEditedHint =>
      isAr ? 'يمكنك تعديل مراجعتك في أي وقت الليلة' : 'You can edit tonight\'s review anytime';

  // ── Premium ──────────────────────────────────────────────────────────────
  String get premiumTitle => isAr ? 'بريميوم' : 'GrowDaily Premium';
  String get premiumHeadline =>
      isAr ? 'املأ حياتك بالأخضر، بلا حدود' : 'Fill your life with green, without limits';
  String get premiumSubhead => isAr
      ? 'ادعم تطوير GrowDaily وافتح كل قوتها.'
      : 'Support GrowDaily\'s development and unlock its full power.';
  String get premiumBenefitHabitsTitle =>
      isAr ? 'عادات غير محدودة' : 'Unlimited habits';
  String get premiumBenefitHabitsDesc => isAr
      ? 'تتبّع كل جوانب حياتك على شبكة واحدة، بلا سقف.'
      : 'Track every corner of your life on one grid — no cap.';
  String get premiumBenefitHistoryTitle =>
      isAr ? 'إحصاءات متقدمة' : 'Advanced insights';
  String get premiumBenefitHistoryDesc => isAr
      ? 'سنوات من الخرائط الحرارية والاتجاهات بين مزاجك وعاداتك.'
      : 'Years of heatmaps and trends between your mood and your habits.';
  String get premiumBenefitFamilyTitle =>
      isAr ? 'شبكات العائلة (قريبًا)' : 'Family grids (coming soon)';
  String get premiumBenefitFamilyDesc => isAr
      ? 'أهداف مشتركة وتحديات مع من تحب — أولوية الوصول للمشتركين.'
      : 'Shared goals and challenges with the people you love — subscribers get first access.';
  String get premiumBenefitSupportTitle =>
      isAr ? 'ادعم صانعًا مستقلًا' : 'Support an independent maker';
  String get premiumBenefitSupportDesc => isAr
      ? 'لا إعلانات، لا بيع بيانات — اشتراكك هو ما يبقي التطبيق حيًا.'
      : 'No ads, no data selling — your subscription is what keeps the app alive.';
  String get premiumMonthly => isAr ? 'شهري' : 'MONTHLY';
  String get premiumYearly => isAr ? 'سنوي' : 'YEARLY';
  String get premiumPerMonth => isAr ? 'كل شهر' : 'per month';
  String get premiumPerYear => isAr ? 'كل سنة' : 'per year';
  String premiumSave(String pct) => isAr ? 'وفّر $pct' : 'SAVE $pct';
  String get premiumCta => isAr ? 'ابدأ بريميوم' : 'START PREMIUM';
  String get premiumRestore => isAr ? 'استعادة المشتريات' : 'Restore purchases';
  String get premiumComingSoon => isAr
      ? 'الاشتراكات تفتح مع الإطلاق — أنت على قائمة المؤسسين.'
      : 'Purchases open at launch — you\'re on the founders list.';
  String get premiumActive =>
      isAr ? 'بريميوم مفعّل — شكرًا لدعمك!' : 'Premium is active — thank you for your support!';
  String get premiumFinePrint => isAr
      ? 'إلغاء في أي وقت. الأسعار النهائية تُعرض في المتجر.'
      : 'Cancel anytime. Final prices are shown in the store.';
  String get habitLimitTitle =>
      isAr ? 'وصلت لحد الخطة المجانية' : 'You\'ve reached the free plan limit';
  String habitLimitBody(int limit) => isAr
      ? 'الخطة المجانية تشمل $limit عادات. افتح عادات غير محدودة مع بريميوم.'
      : 'The free plan includes $limit habits. Unlock unlimited habits with Premium.';

  // ── Streak nudge ─────────────────────────────────────────────────────────
  String streakAtRiskTitle(int days) => isAr
      ? 'سلسلة الـ$days يومًا على المحك'
      : 'Your $days-day streak is on the line';
  String get streakAtRiskBody => isAr
      ? 'مربّع أخضر واحد الليلة يبقيها حيّة.'
      : 'One green square tonight keeps it alive.';
}
