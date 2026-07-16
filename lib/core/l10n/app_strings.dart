import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/local_store_service.dart';
import '../utils/intention_phrase.dart';

// ─── Locale provider ──────────────────────────────────────────────────────────

final localeProvider = StateNotifierProvider<_LocaleNotifier, Locale>(
  (_) => _LocaleNotifier(),
);

class _LocaleNotifier extends StateNotifier<Locale> {
  _LocaleNotifier([Locale initial = const Locale('en')]) : super(initial);

  void set(Locale locale) => state = locale;
}

const _kLocaleKey = 'selected_locale_v1';

/// Whether this device has completed the first-launch language picker at
/// least once. Seeded from Hive at boot (see main.dart) — a fresh install
/// has no persisted locale key yet, so this starts `false` and the picker
/// gate shows; once a language is chosen it's `true` forever after on this
/// device, so the picker never shows again.
final languageChosenProvider = StateProvider<bool>((ref) => false);

/// Sets the active locale and persists it, marking the language picker as
/// completed. Use this instead of `localeProvider.notifier.set` directly
/// so the choice survives a cold start.
Future<void> setLocale(WidgetRef ref, Locale locale) async {
  ref.read(localeProvider.notifier).set(locale);
  ref.read(languageChosenProvider.notifier).state = true;
  final box = await LocalStoreService.settingsBox();
  await box.put(_kLocaleKey, locale.languageCode);
}

/// Reads the persisted locale, if any. Called once at boot (see main.dart)
/// to seed [localeProvider]/[languageChosenProvider] before the first frame.
Future<Locale?> loadPersistedLocale() async {
  final box = await LocalStoreService.settingsBox();
  final code = box.get(_kLocaleKey) as String?;
  return code == null ? null : Locale(code);
}

/// Provider overrides that seed locale state from [persisted] at boot,
/// mirroring the `guestModeProvider.overrideWith(...)` pattern in main.dart.
List<Override> localeProviderOverrides(Locale? persisted) => [
      if (persisted != null)
        localeProvider.overrideWith((ref) => _LocaleNotifier(persisted)),
      languageChosenProvider.overrideWith((ref) => persisted != null),
    ];

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
  String get deleteAccount => isAr ? 'حذف الحساب' : 'Delete Account';
  String get deleteAccountWarningTitle =>
      isAr ? 'حذف حسابك نهائيًا؟' : 'Permanently delete your account?';
  String get deleteAccountWarningBody => isAr
      ? 'سيؤدي هذا إلى حذف عاداتك، سلاسلك، إنجازاتك، وكل بياناتك نهائيًا. لا يمكن التراجع عن هذا الإجراء.'
      : "This permanently deletes your habits, streaks, achievements, and all your data. This can't be undone.";
  String get deleteAccountPasswordLabel =>
      isAr ? 'أدخل كلمة المرور للتأكيد' : 'Enter your password to confirm';
  String get deleteAccountConfirmCta =>
      isAr ? 'حذف حسابي نهائيًا' : 'Delete my account';
  String get deleteAccountWrongPassword =>
      isAr ? 'كلمة مرور غير صحيحة.' : "That password doesn't match.";
  String get deleteAccountSuccess =>
      isAr ? 'تم حذف الحساب.' : 'Your account has been deleted.';
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

  /// Arabic cardinal numbers agree with their counted noun differently by
  /// range (CLDR's Arabic plural rule: one/two/few(3-10)/many(11-99)/other)
  /// — "3 أيام" and "14 يومًا" are both correct, "3 يوم" or "14 أيام" read as
  /// mistakes to a native reader, so this can't just be "$n يوم" for every n.
  String daysCount(int n) {
    if (!isAr) return '$n Days';
    if (n == 0) return 'لا أيام';
    if (n == 1) return 'يوم واحد';
    if (n == 2) return 'يومان';
    final mod100 = n % 100;
    if (mod100 >= 3 && mod100 <= 10) return '$n أيام';
    if (mod100 >= 11 && mod100 <= 99) return '$n يومًا';
    return '$n يوم';
  }

  /// Flavor title for a streak milestone (e.g. "3-Day Starter"). Gulf/Khaleeji
  /// tone in Arabic — "النشامى" especially is a warm, distinctly Bahraini/Gulf
  /// word for the brave/steadfast, rather than a flat literal translation.
  String milestoneTitle(int milestone) {
    if (!isAr) {
      return switch (milestone) {
        3 => '3-Day Starter',
        7 => '7-Day Warrior',
        14 => '2-Week Champion',
        30 => 'Month Master',
        60 => '60-Day Devotee',
        100 => 'Century Legend',
        _ => 'Streak Milestone',
      };
    }
    return switch (milestone) {
      3 => 'بداية النشامى',
      7 => 'محارب الأسبوع',
      14 => 'بطل الأسبوعين',
      30 => 'سيد الشهر',
      60 => 'صاحب الهمّة',
      100 => 'أسطورة المئة',
      _ => 'إنجاز السلسلة',
    };
  }

  String nowWarrior(String title) =>
      isAr ? 'ما شاء الله! أنت الآن $title.' : 'You are now a $title.';
  String get consistencyBuildsCharacter => isAr
      ? 'الثبات يصنع الأبطال — كمّل المشوار.'
      : 'Consistency builds character — keep showing up.';
  // Arabic phrase leads, the "+N XP" token trails — reads more naturally in
  // an RTL sentence than opening with a Latin/number run.
  String milestoneBonusXp(int bonus) =>
      isAr ? 'مكافأة الإنجاز: +$bonus XP' : '+$bonus XP milestone bonus';
  String get achievementUnlocked => isAr ? 'إنجاز مفتوح!' : 'ACHIEVEMENT UNLOCKED';
  // Short inline tag on the completion toast when a surprise bonus rolled —
  // see GameConstants.surpriseBonusChance.
  String get bonusTag => isAr ? 'مكافأة مفاجئة' : 'Bonus';
  String get claimReward => isAr ? 'استلم المكافأة' : 'CLAIM REWARD';
  String get levelUpMsg => isAr ? 'ارتقاء مستوى' : 'LEVEL UP';

  // ── Profile ──────────────────────────────────────────────────────────────
  String get profile => isAr ? 'الملف الشخصي' : 'Profile';
  String get achievements => isAr ? 'الإنجازات' : 'ACHIEVEMENTS';
  String achievementsViewAll(int n) => isAr ? 'عرض الكل ($n)' : 'View all ($n)';
  String get achievementsShowLess => isAr ? 'عرض أقل' : 'Show less';
  String get profileSection => isAr ? 'الملف الشخصي' : 'PROFILE';
  String get achievementsRowTitle => isAr ? 'الإنجازات' : 'Achievements';
  String get progressStreakTitle =>
      isAr ? 'التقدم والسلسلة' : 'Progress & Streak';
  String get settings => isAr ? 'الإعدادات' : 'SETTINGS';
  String get darkMode => isAr ? 'الوضع الداكن' : 'Dark Mode';
  String get appearance => isAr ? 'المظهر' : 'Appearance';
  String get appearanceSheetTitle =>
      isAr ? 'اختر مظهر التطبيق' : 'Choose an app theme';
  String get appearancePremiumHint => isAr
      ? 'القوالب المميزة تتطلب Premium'
      : 'Premium templates require Premium';
  String get appFont => isAr ? 'الخط' : 'Font';
  String get appFontSheetTitle =>
      isAr ? 'اختر خط التطبيق' : 'Choose an app font';
  String get preview => isAr ? 'معاينة' : 'Preview';
  String previewingTheme(String name) =>
      isAr ? 'معاينة: $name — مرر للتصفح' : 'Previewing: $name — swipe to look around';
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

  // ── Add Habit Hub (Plan / Add Goal tabs) ────────────────────────────────────
  String get hubTitle => isAr ? 'إضافة عادة' : 'Add a Habit';
  String get plansTab => isAr ? 'خطط' : 'Plans';

  // ── Plan Picker ──────────────────────────────────────────────────────────
  String get choosePlan => isAr ? 'اختر خطتك' : 'Choose Your Plan';
  String get choosePlanSubtitle => isAr
      ? 'حزمة عادات جاهزة بنقرة واحدة.'
      : 'Start with a ready-made habit bundle.';
  String get startPlan => isAr ? 'ابدأ الخطة' : 'Start Plan';
  String get deactivatePlan => isAr ? 'إيقاف الخطة' : 'Deactivate';
  /// Small caption shown above a plan's expanded habit chips - the only
  /// hint that they're individually tappable (see PlanPickerSheet's
  /// _HabitChip), not just a read-only preview of what "Start Plan" adds.
  String get planPickHabitsHint => isAr
      ? 'اضغط على أي عادة لإضافتها أو إزالتها بمفردها'
      : 'Tap any habit to add or remove just that one';
  /// Bottom-button label when some but not all of a plan's habits are
  /// already active (see _PlanCard's isPartiallyActive) - tapping it still
  /// runs the same activatePlan union as [startPlan] always has (safe for
  /// already-active habits), just phrased for "finish the rest" instead of
  /// "start from zero" since some were already deliberately picked.
  String addRemainingPlanHabits(int n) =>
      isAr ? 'أضف الباقي ($n)' : 'Add Remaining ($n)';
  String get browsePlans => isAr ? 'استعرض الخطط' : 'Browse Plans';
  String get dailyReminder => isAr ? 'تذكير يومي' : 'Daily Reminder';
  String get tapToSetReminder => isAr ? 'اضغط لتعيين وقت التذكير' : 'Tap to set reminder time';
  String get reminderPermissionDenied => isAr
      ? 'تم حفظ الوقت، لكن الإشعارات معطّلة — فعّلها من إعدادات هاتفك ليعمل التذكير.'
      : 'Time saved, but notifications are off — enable them in your phone\'s settings for the reminder to fire.';

  // ── Empty state ───────────────────────────────────────────────────────────
  String get noHabitsYet => isAr ? 'لا عادات بعد' : 'No habits yet';
  String get noHabitsDesc => isAr
      ? 'أكمل عاداتك اليوم، لوّن شبكتك الأسبوعية، وحافظ على سلسلتك مستمرة.'
      : 'Complete habits today, fill your grid, and keep your streak alive.';
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
  String get afterWhatRoutine => isAr ? 'بعد أو قبل أي روتين؟ (اختياري)' : 'Before or after what routine? (optional)';
  String get routineHint => isAr ? 'الفجر، قبل العمل، بعد المغرب...' : 'Fajr, before work, after Maghrib...';
  String get cueAfterOption => isAr ? 'بعد' : 'After';
  String get cueBeforeOption => isAr ? 'قبل' : 'Before';
  String get pickATime => isAr ? 'اختر وقتًا' : 'Pick a time';
  String get category => isAr ? 'الفئة' : 'CATEGORY';
  String get frequency => isAr ? 'التكرار' : 'FREQUENCY';
  String get daily => isAr ? 'يومياً' : 'Daily';
  String get weekly => isAr ? 'أسبوعياً' : 'Weekly';
  String get times => isAr ? 'مرات:' : 'Times:';
  String get createHabit => isAr ? 'أنشئ العادة' : 'CREATE TINY HABIT';
  String get smartStarters => isAr ? 'بدايات ذكية' : 'SMART STARTERS';

  String get addGoalTitle => isAr ? 'إضافة هدف' : 'Add Goal';
  String get whatImprove => isAr ? 'ما الذي تريد تحسينه؟' : 'What do you want to improve?';
  String get buildHabitTitle => isAr ? 'أبني عادة' : 'Build a habit';
  String get buildHabitSubtitle => isAr ? 'أنشئ شيئًا تريد فعله أكثر.' : 'Create something you want to do more.';
  String get quitHabitTitle => isAr ? 'أترك أو أقلل عادة' : 'Quit / reduce something';
  String get quitHabitSubtitle => isAr ? 'تحكّم في شيء تريد فعله أقل.' : 'Control something you want to do less.';
  String get whatHabitBuild => isAr ? 'ما العادة التي تريد بناءها؟' : 'What habit do you want to build?';
  String get whatReduce => isAr ? 'ما الذي تريد تقليله؟' : 'What do you want to reduce?';
  String get goalTitleHint => isAr ? 'اكتب هدفك أو اختر اقتراحًا' : 'Type your goal or pick a suggestion';
  String get smartSuggestions => isAr ? 'اقتراحات ذكية' : 'Smart suggestions';
  String get timingBuildTitle => isAr ? 'متى وكيف ستتابع؟' : 'When and how often?';
  String get timingQuitTitle => isAr ? 'ما الخطة الهادئة؟' : 'What is the calm plan?';
  String get whenQuestion => isAr ? 'متى؟' : 'When?';
  String get customTime => isAr ? 'وقت مخصص' : 'Custom time';
  String get customText => isAr ? 'نص مخصص' : 'Custom text';
  String get cuePrayerOption => isAr ? 'وقت الصلاة' : 'Prayer time';
  String get pickAPrayer => isAr ? 'اختر صلاة' : 'Pick a prayer';
  // ── Reminder lead time (Add Habit → When step) ─────────────────────
  // How long before the picked time/prayer the actual notification fires —
  // separate from _CueRelation's "before/after [routine]" text above, which
  // only affects the habit's own display label, not scheduling.
  // "ذكّرني قبل" / "Remind me before" — was just "ذكّرني"/"Remind me" before;
  // the "before" half matters since this section is specifically about how
  // far ahead of the resolved time/prayer moment the reminder fires, not
  // just whether one exists at all.
  String get remindMeSection => isAr ? 'ذكّرني قبل' : 'Remind me before';
  String get leadAtTime => isAr ? 'في الوقت' : 'On time';
  String get lead15Min => isAr ? '15 د' : '15 min';
  String get lead30Min => isAr ? '30 د' : '30 min';
  String get lead1Hour => isAr ? 'ساعة' : '1 hour';
  String get leadCustomOption => isAr ? 'مخصص' : 'Custom';
  String get leadCustomMinutesHint => isAr ? 'كم دقيقة قبل؟' : 'Minutes before';
  // Small live preview under the lead-time picker (_reminderLeadSection in
  // add_habit_sheet.dart) — [time] is the already-localized clock string
  // (e.g. "1:00 PM"), computed from the picked clock time or (for a
  // prayer cue) PrayerTimesService.calculateOfflineCorrected plus
  // NotificationSettings.prayerOffsetMinutes, minus the chosen lead.
  String remindAtTimePreview(String time) =>
      isAr ? 'سيتم تذكيرك الساعة $time' : "You'll be reminded at $time";
  // Shown instead of remindAtTimePreview when Prayer mode is picked but no
  // location is saved yet — there's no prayer time to compute against, so
  // this points at where to fix that rather than showing nothing at all.
  String get remindPreviewNeedsLocation => isAr
      ? 'حدد موقعك في إعدادات الإشعارات لرؤية الوقت الدقيق'
      : 'Set your location in Notification Settings to see the exact time';
  // Timing (time/prayer/text) is already optional in the data — an
  // untouched picker just saves with no cue at all. This says so out loud,
  // for habits like "pray on time" that have no single checkable moment.
  String get timingOptionalNote => isAr
      ? 'ليست كل عادة تحتاج وقتًا محددًا — يمكنك تخطي هذا إن لم ينطبق'
      : "Not every habit needs a set time — skip this if it doesn't apply.";
  String get repeat => isAr ? 'التكرار' : 'Repeat';
  String get goalStyle => isAr ? 'أسلوب الهدف' : 'Goal style';
  String get customizeTiming => isAr ? 'تخصيص التوقيت' : 'Customize timing';
  String get avoidCompletely => isAr ? 'تجنّبه تمامًا' : 'Avoid completely';
  String get setLimit => isAr ? 'ضع حدًا' : 'Set a limit';
  String get maxAmount => isAr ? 'الحد الأقصى' : 'Max amount';
  // Free-text unit name shown only when LimitUnit.custom is picked, so
  // "5 custom" can actually say "5 cigarettes" — see
  // IslamicHabitTemplate.customUnitLabel.
  String get customUnitPrompt => isAr ? 'ماذا تحدّ؟' : 'What are you limiting?';
  String get customUnitHint => isAr ? 'مثال: سجائر' : 'e.g. cigarettes';
  String get whenHardest => isAr ? 'متى يكون أصعب؟' : 'When is it hardest?';
  String get customTriggerOptional => isAr ? 'وقت أو موقف مخصص (اختياري)' : 'Custom time or trigger (optional)';
  String get threeTimesWeek => isAr ? '3 مرات/أسبوع' : '3x/week';
  String get specificDays => isAr ? 'أيام محددة' : 'Specific days';
  // Label on the dropdown that appears once "Weekly" (flexible — any
  // days) is picked in _frequencySection — lets someone say "gym 4x a
  // week" without committing to which days, as opposed to Specific Days
  // where the day count *is* the target.
  String get timesPerWeek => isAr ? 'عدد المرات أسبوعيًا' : 'Times per week';
  String get createGoal => isAr ? 'أنشئ الهدف' : 'CREATE GOAL';
  String get continueAction => isAr ? 'متابعة' : 'CONTINUE';
  String get back => isAr ? 'رجوع' : 'Back';
  String limitUnitLabel(String key) => isAr
      ? switch (key) {
          'minutes' => 'دقائق',
          'times' => 'مرات',
          'cups' => 'أكواب',
          'money' => 'مال',
          _ => 'مخصص',
        }
      : switch (key) {
          'minutes' => 'minutes',
          'times' => 'times',
          'cups' => 'cups',
          'money' => 'money',
          _ => 'custom',
        };
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
  String get habitStayedOnTrack => isAr ? 'بقيت على المسار' : 'STAYED ON TRACK';
  String get habitWithinLimit => isAr ? 'ضمن الحد' : 'WITHIN LIMIT';
  // Quit-habit secondary action — deliberately a quieter, plain-text
  // control next to the primary affirm button (see HabitCard), not another
  // filled pill: logging a slip should never look as rewarding to tap as
  // staying clean does.
  String get habitLogSlip => isAr ? 'سجّل انتكاسة' : 'LOG A SLIP';
  String get habitLogOverLimit => isAr ? 'سجّل التجاوز' : 'LOG OVER LIMIT';
  String get habitSlippedToday => isAr ? 'انتكست اليوم' : 'SLIPPED TODAY';
  String get habitOverLimitToday => isAr ? 'تجاوزت الحد اليوم' : 'OVER LIMIT TODAY';

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
  // Default filter segment — today's fresh tasks plus anything finished
  // today (see MatrixScreen._MatrixFilter.today). Distinct from matrixAll,
  // which also includes tasks still open from before today.
  String get matrixToday => isAr ? 'اليوم' : 'Today';
  String get matrixFav => isAr ? 'مفضلة' : 'Fav';
  // Count-based label on the tap-to-filter chip for tasks left unfinished
  // from before today (see MatrixScreen._carriedOverOnly) — deliberately
  // not called "yesterday": a task could be several days old, not just one.
  String matrixCarriedOverCount(int n) =>
      isAr ? '$n مُرحّلة' : '$n carried over';
  String get matrixAll => isAr ? 'الكل' : 'All';
  String get matrixTapToAdd => isAr ? 'اضغط في أي مكان للإضافة' : 'Tap anywhere to add a goal';
  String get matrixAddAnother => isAr ? '+ أضف مهمة أخرى' : '+ Add another';
  String get matrixAddTask => isAr ? 'أضف مهمة' : 'ADD TASK';
  String get matrixWhatToDo => isAr ? 'ما الذي يجب فعله؟' : 'What needs to be done?';
  String get matrixMoveToQuadrant => isAr ? 'انقل إلى ربع' : 'MOVE TO QUADRANT';
  // Tooltips for the header's expand icon (QuadrantCard) and the close
  // button on the near-fullscreen view it opens (QuadrantExpandedScreen).
  String get matrixExpandQuadrant => isAr ? 'توسيع' : 'Expand';
  String get matrixCollapseQuadrant => isAr ? 'إغلاق' : 'Close';
  String get matrixDeleteTask => isAr ? 'حذف المهمة' : 'Delete task';
  String get matrixDeleteSelected => isAr ? 'حذف المحدد' : 'Delete selected';
  String matrixSelectedCount(int count) => isAr ? '$count محدد' : '$count selected';
  String get matrixCompletedTitle => isAr ? 'المكتملة' : 'Completed';
  String get matrixNoCompletedTasks =>
      isAr ? 'لا مهام مكتملة بعد' : 'No completed tasks yet';
  String get matrixNoCompletedTasksDesc => isAr
      ? 'المهام التي تُنجزها تظهر هنا.'
      : 'Tasks you finish will show up here.';
  String get matrixRestoreTask => isAr ? 'استعادة' : 'Restore';
  String get matrixAddMultipleHint => isAr
      ? 'اكتب مهمة واضغط أدخل، ثم أضف التالية'
      : 'Type a task and hit enter, then add the next one';
  String get matrixAddDetails => isAr ? 'أضف تفاصيل' : 'Add details';
  String get matrixHideDetails => isAr ? 'إخفاء التفاصيل' : 'Hide details';
  String get matrixDescriptionHint =>
      isAr ? 'أضف وصفًا (اختياري)' : 'Add a description (optional)';
  String get matrixTaskDetails => isAr ? 'تفاصيل المهمة' : 'Task details';
  String get matrixNoDescription =>
      isAr ? 'لا يوجد وصف' : 'No description yet';
  // ReminderRow (reminder_picker.dart), shared by AddTaskSheet's "Add
  // details" section and TaskDetailSheet — matrixReminderLabel is the
  // unset-state placeholder (once set, the row shows the picked moment
  // itself instead, via formatReminderMoment, not a fixed string).
  String get matrixReminderLabel => isAr ? 'تعيين تذكير' : 'Set a reminder';
  String get matrixReminderPast => isAr
      ? 'اختر وقتًا في المستقبل'
      : 'Pick a time that hasn\'t already passed';
  String get matrixDone => isAr ? 'تم' : 'Done';
  String get matrixUndo => isAr ? 'تراجع' : 'Undo';
  String get matrixTaskDeleted => isAr ? 'تم حذف المهمة' : 'Task deleted';
  String matrixTasksDeleted(int count) =>
      isAr ? 'تم حذف $count مهام' : '$count tasks deleted';
  String get matrixPickADay => isAr
      ? 'اضغط على يوم أعلاه لترى ما أنجزته'
      : 'Tap a day above to see what you finished';
  String get matrixNoTasksThisDay =>
      isAr ? 'لا مهام مُنجزة في هذا اليوم' : 'Nothing finished on this day';

  // Long-press a quadrant header (QuadrantCard / QuadrantExpandedScreen) to
  // rename it and/or give it its own color — saved to the account and
  // synced across every signed-in device (see MatrixNotifier.updateQuadrant).
  String get matrixEditQuadrantTitle =>
      isAr ? 'تعديل الربع' : 'Edit quadrant';
  String get matrixEditQuadrantBody => isAr
      ? 'أعد تسمية هذا الربع واختر له لونًا خاصًا. يُحفظ في حسابك ويظهر على كل أجهزتك.'
      : 'Rename this quadrant and give it its own color. Saved to your account and synced across your devices.';
  String get matrixEditQuadrantSave => isAr ? 'حفظ' : 'Save';
  String get matrixEditQuadrantCancel => isAr ? 'إلغاء' : 'Cancel';
  String get matrixQuadrantColorTitle => isAr ? 'لون الربع' : 'Quadrant color';
  String get matrixQuadrantColorHint =>
      isAr ? 'اختر أي لون لهذا الربع' : 'Pick any color for this quadrant';

  // ── Character Closet ────────────────────────────────────────────────────
  String get closetProfileRow => isAr ? 'خزانة الشخصية' : 'Character Closet';
  String get closetCustomize => isAr ? 'تخصيص' : 'Customize';
  String get closetTitle => isAr ? 'خزانة الشخصية' : 'Character Closet';
  String get closetSubtitle =>
      isAr ? 'خصص رفيقك بشخصية وإكسسوار' : 'Customize your companion';
  String get closetCharacterSection => isAr ? 'الشخصية' : 'CHARACTER';
  String get closetOwned => isAr ? 'مملوك' : 'Owned';
  String get closetEquipped => isAr ? 'مرتدى' : 'Equipped';
  String get closetEquip => isAr ? 'ارتداء' : 'Equip';
  String get closetUnequip => isAr ? 'خلع' : 'Remove';
  String get closetBuy => isAr ? 'شراء' : 'Buy';
  String get closetBuyConfirmTitle => isAr ? 'شراء هذه القطعة؟' : 'Buy this item?';
  String closetBuyConfirmBody(int cost) => isAr
      ? 'أنفق $cost ذهب لفتحها للأبد.'
      : 'Spend $cost gold to unlock this forever.';
  String get closetNotEnoughGold => isAr ? 'الذهب غير كافٍ' : 'Not enough gold';
  String get closetPurchaseFailed =>
      isAr ? 'تعذّر إتمام الشراء — حاول مرة أخرى' : "Couldn't complete the purchase — try again";
  String get closetPurchased => isAr ? 'تم الفتح!' : 'Unlocked!';
  String get closetCancel => isAr ? 'إلغاء' : 'Cancel';

  // ── Edit display name (Profile) ─────────────────────────────────────────
  String get profileEditNameTitle => isAr ? 'اسمك' : 'Your name';
  String get profileEditNameBody => isAr
      ? 'هكذا سيظهر اسمك في التطبيق.'
      : "This is how you'll see yourself in the app.";
  String get profileEditNameHint => isAr ? 'اكتب اسمك' : 'Enter your name';
  String get profileEditNameSave => isAr ? 'حفظ' : 'Save';
  String get profileEditNameCancel => isAr ? 'إلغاء' : 'Cancel';
  String get profileEditNameError =>
      isAr ? 'تعذّر الحفظ — حاول مرة أخرى' : "Couldn't save — try again";

  // ── Quick Wins ───────────────────────────────────────────────────────────
  String get quickWins => isAr ? 'مكاسب سريعة' : 'Quick Wins';
  String get quickWinToday => isAr ? 'اليوم' : 'TODAY';
  String get quickWinThisWeek => isAr ? 'هذا الأسبوع' : 'THIS WEEK';
  String get quickWinDone => isAr ? 'تم' : 'Done';
  String get quickWinSwap => isAr ? 'تبديل' : 'Swap';
  String get quickWinClaim => isAr ? 'استلام' : 'Claim';

  // ── Navigation ───────────────────────────────────────────────────────────
  String get navToday => isAr ? 'اليوم' : 'Today';
  String get navGrid => isAr ? 'العادات' : 'Habits';
  String get navMatrix => isAr ? 'المهام' : 'Tasks';
  String get navFocus => isAr ? 'التركيز' : 'Focus';
  String get navGoals => isAr ? 'الأهداف' : 'Goals';
  String get navProfile => isAr ? 'ملفي' : 'Profile';

  // ── Victory Grid ─────────────────────────────────────────────────────────
  String get gridTitle => isAr ? 'شبكة الانتصارات' : 'Victory Grid';
  String get gridSlogan =>
      isAr ? 'لوّن حياتك، مربّعًا كل يوم.' : 'Color your life, one square at a time.';
  String get gridThisWeek => isAr ? 'هذا الأسبوع' : 'This week';
  // "Green squares" used to be literal — every preset's completed square
  // was some shade of green. Some presets now use their own signature
  // color instead (see ThemePreset's class doc comment), so this and the
  // other grid/heatmap/night-review labels below stay color-neutral
  // rather than naming a color that isn't true for every theme.
  String get gridGreenSquares => isAr ? 'مربّعات ملوّنة' : 'Squares filled';
  String get gridPoints => isAr ? 'النقاط' : 'Points';
  String get gridComplete => isAr ? 'الإكمال' : 'Complete';
  String get gridWeekFilled => isAr ? 'اكتمل الأسبوع!' : 'Week filled!';
  String get gridPerfectDay =>
      isAr ? 'يوم مثالي — كل مربّعات اليوم ملوّنة!' : 'Perfect day — every square is filled!';
  String gridGreensToday(int n) =>
      isAr ? 'كسبت $n مربّعًا اليوم' : 'You earned $n squares today';
  String get gridTapHint => isAr
      ? 'اضغط لتلوين المربّع · اضغط مطولاً للمزيد من الألوان'
      : 'Tap to color · long-press for more colors';
  String get gridRewardHint => isAr
      ? 'اليوم فقط يمنحك نقاط الخبرة والذهب، ويزيد سلسلتك مرة واحدة يوميًا كحد أقصى.'
      : "Only today earns XP, gold, and streak credit — once per day at most.";
  String get gridPastDayHint => isAr
      ? 'تعديل يوم سابق: يُحدّث سجلّك المرئي فقط، دون مكافآت.'
      : 'Editing a past day updates your visual record only — no rewards.';
  // Distinct from gridPastDayHint on purpose: shown for the real calendar
  // day during the 3-hour window right after midnight, which isn't a past
  // day at all (it just isn't the official rewarded day yet) — see
  // DateTimeGameExt.isRealToday/isToday's doc comments.
  String get gridNotYetActiveHint => isAr
      ? 'لم يصبح هذا اليوم رسميًا بعد: يمكنك تلوينه، لكن دون مكافآت حتى الساعة ٣ فجرًا.'
      : "This day isn't official yet — you can color it in, but no rewards until 3 AM.";
  String get gridEmptyTitle => isAr ? 'لا توجد عادات بعد' : 'No habits to track yet';
  String get gridEmptyDesc => isAr
      ? 'أضف عادات من تبويب اليوم لتبدأ بتلوين أسبوعك.'
      : 'Add a few habits from Today to start coloring your week.';
  String get gridGoToDashboard => isAr ? 'الذهاب لليوم' : 'Go to Today';
  String get gridEditSquare => isAr ? 'حدّد المربّع' : 'Set this square';
  String get gridNoteLabel => isAr ? 'ماذا حدث اليوم؟' : 'What happened today?';
  String get gridNoteHint =>
      isAr ? 'اكتب انعكاسًا قصيرًا…' : 'Write a short reflection…';
  String get gridSave => isAr ? 'حفظ' : 'Save';
  String get gridFutureDay => isAr ? 'يوم قادم' : 'Future day';
  String get gridSquareDoneFromToday => isAr
      ? 'أُنجزت هذه المهمة اليوم من صفحة اليوم. اختر لونًا آخر لتصحيحها.'
      : 'Completed from Today. Pick a different color to correct it.';

  // Habit Notes journal — long-press's note field and Skipped/Failed/Bonus
  // states (see gridEditSquare/gridNoteLabel above) are captured live from
  // the square editor; this is the read-only "browse it all later" screen
  // (see grid_journal_notifier.dart), same relationship
  // nightReviewHistoryTitle has to Night Review's own live entry point.
  String get gridJournalTitle => isAr ? 'ملاحظات العادات' : 'Habit Notes';
  String get gridJournalEmpty => isAr
      ? 'لا توجد ملاحظات محفوظة هذا الشهر — اضغط مطوّلاً على أي مربّع لإضافة واحدة'
      : 'No notes saved this month — long-press any square to add one';
  String get gridJournalFilterAll => isAr ? 'الكل' : 'All';
  // Shown in place of a habit's real name when it's since been deleted —
  // the note itself is still worth keeping (see isJournalWorthy's doc
  // comment), it just can't be attributed to a still-existing habit
  // anymore. Same "explain, don't silently drop" spirit as
  // roomLinkedHabitDeletedHint for the equivalent Rooms situation.
  String get gridJournalDeletedHabit => isAr ? 'عادة محذوفة' : 'Deleted habit';

  // ── Monthly Heatmap ──────────────────────────────────────────────────────
  String get heatmapTitle => isAr ? 'خريطة التقدّم' : 'Progress Heatmap';
  String get heatmapSubtitle => isAr
      ? 'كثافة الإنجاز عبر الأشهر — كل مربّع يومٌ، وكل درجة لون كثافة انتصاراتك.'
      : "Your completion density across months — every square is a day, every shade is how much you colored it.";
  String get heatmapTotalGreen => isAr ? 'مربّعات ملوّنة' : 'Squares filled';
  String get heatmapActiveDays => isAr ? 'أيام نشطة' : 'Active days';
  String get heatmapBestDay => isAr ? 'أفضل يوم' : 'Best day';
  String get heatmapLess => isAr ? 'أقل' : 'Less';
  String get heatmapMore => isAr ? 'أكثر' : 'More';
  String get heatmapUpgradeTitle =>
      isAr ? 'افتح سجلّك الكامل' : 'Unlock your full history';
  String heatmapUpgradeBody(int freeWeeks) => isAr
      ? 'الحساب المجاني يعرض آخر ${freeWeeks ~/ 4} أشهر تقريبًا. GrowDaily Premium يفتح سنة كاملة من خريطة تقدّمك.'
      : "Free shows your last ~${freeWeeks ~/ 4} months. Premium unlocks a full rolling year of your heatmap.";

  // ── Night Review ─────────────────────────────────────────────────────────
  String get nightReviewTitle => isAr ? 'مراجعة الليل' : 'Night Review';
  // Calendar of past mood/reflection check-ins — reused as both the
  // AppBar action's tooltip on NightReviewScreen and the destination
  // screen's own title, same pattern as heatmapTitle.
  String get nightReviewHistoryTitle =>
      isAr ? 'سجل المراجعات' : 'Review history';
  String get nightReviewHistoryEmpty => isAr
      ? 'لا توجد مراجعات محفوظة هذا الشهر'
      : 'No reviews saved this month';
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
  String get nightReviewHabitsDoneLabel =>
      isAr ? 'عادات اليوم' : 'Habits done';
  String get nightReviewTasksDoneLabel =>
      isAr ? 'مهام منجزة' : 'Tasks done';
  String get nightReviewGreenSquares =>
      isAr ? 'مربّعات ملوّنة' : 'Squares filled';
  String get nightReviewStreak => isAr ? 'السلسلة' : 'Streak';
  String get nightReviewSave => isAr ? 'حفظ المراجعة' : 'Save review';
  String get nightReviewSaved => isAr ? 'تم حفظ مراجعتك الليلية' : 'Night review saved';
  String get nightReviewDoneBadge => isAr ? 'تمت المراجعة' : 'Reviewed';
  String get nightReviewEditedHint =>
      isAr ? 'يمكنك تعديل مراجعتك في أي وقت الليلة' : 'You can edit tonight\'s review anytime';

  // ── Premium ──────────────────────────────────────────────────────────────
  String get premiumTitle => isAr ? 'بريميوم' : 'GrowDaily Premium';
  String get premiumHeadline =>
      isAr ? 'املأ حياتك بالألوان، بلا حدود' : 'Fill your life with color, without limits';
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
  String get premiumLifetime => isAr ? 'مدى الحياة' : 'LIFETIME';
  String get premiumPerMonth => isAr ? 'كل شهر' : 'per month';
  String get premiumPerYear => isAr ? 'كل سنة' : 'per year';
  String get premiumOneTime => isAr ? 'دفعة واحدة' : 'one-time';
  String premiumSave(String pct) => isAr ? 'وفّر $pct' : 'SAVE $pct';
  String get premiumBestValueBadge => isAr ? 'الأفضل قيمة' : 'BEST VALUE';
  String get premiumCta => isAr ? 'ابدأ بريميوم' : 'START PREMIUM';
  String get premiumRestore => isAr ? 'استعادة المشتريات' : 'Restore purchases';
  String get premiumComingSoon => isAr
      ? 'بريميوم غير متاح الآن — حاول مرة أخرى بعد قليل.'
      : 'Premium isn\'t available right now — please try again shortly.';
  String get premiumActive =>
      isAr ? 'بريميوم مفعّل — شكرًا لدعمك!' : 'Premium is active — thank you for your support!';
  String get premiumManageSubscription =>
      isAr ? 'إدارة الاشتراك' : 'Manage subscription';
  String get premiumPurchaseError => isAr
      ? 'تعذّرت العملية. حاول مرة أخرى.'
      : 'Something went wrong. Please try again.';
  String get premiumRestoreSuccess =>
      isAr ? 'تم استعادة بريميوم!' : 'Premium restored!';
  String get premiumRestoreNothingFound => isAr
      ? 'لم يتم العثور على مشتريات سابقة لهذا الحساب.'
      : 'No previous purchase found for this store account.';
  String get premiumFinePrint => isAr
      ? 'إلغاء في أي وقت. الأسعار النهائية تُعرض في المتجر.'
      : 'Cancel anytime. Final prices are shown in the store.';
  String get premiumTermsOfUse => isAr ? 'شروط الاستخدام' : 'Terms of Use';
  String get premiumPrivacyPolicy =>
      isAr ? 'سياسة الخصوصية' : 'Privacy Policy';
  String get premiumLinkOpenError => isAr
      ? 'تعذّر فتح الرابط.'
      : 'Couldn\'t open the link.';
  String get habitLimitTitle =>
      isAr ? 'وصلت لحد الخطة المجانية' : 'You\'ve reached the free plan limit';
  String habitLimitBody(int limit) => isAr
      ? 'الخطة المجانية تشمل $limit عادات. افتح عادات غير محدودة مع بريميوم.'
      : 'The free plan includes $limit habits. Unlock unlimited habits with Premium.';

  // ── Voice note gate ──────────────────────────────────────────────────────
  String get voiceNoteGateTitle =>
      isAr ? 'الملاحظات الصوتية ميزة بريميوم' : 'Voice notes are a Premium feature';
  String get voiceNoteGateBody => isAr
      ? 'سجّل ملاحظة صوتية سريعة لأي مهمة — متاحة مع بريميوم.'
      : 'Record a quick voice note on any task — available with Premium.';
  String get voiceNoteRecording => isAr ? 'جارٍ التسجيل…' : 'Recording…';
  String get voiceNoteTapToRecord => isAr ? 'اضغط للتسجيل' : 'Tap to record';
  String get voiceNoteTapToStop => isAr ? 'اضغط للإيقاف' : 'Tap to stop';
  String get voiceNoteMicPermissionDenied => isAr
      ? 'يحتاج التطبيق إذن الميكروفون لتسجيل الملاحظات الصوتية.'
      : 'GrowDaily needs microphone access to record voice notes.';
  String get voiceNoteAttached => isAr ? 'ملاحظة صوتية مرفقة' : 'Voice note attached';
  String get voiceNotePlay => isAr ? 'تشغيل' : 'Play';
  String get voiceNotePause => isAr ? 'إيقاف مؤقت' : 'Pause';
  String get voiceNoteSkipBack => isAr ? 'رجوع 5 ثوانٍ' : 'Back 5 seconds';
  String get voiceNoteSkipForward => isAr ? 'تقديم 5 ثوانٍ' : 'Forward 5 seconds';
  String voiceNoteSpeedLabel(String rate) =>
      isAr ? 'سرعة التشغيل، $rate' : 'Playback speed, $rate';
  // TaskDetailSheet's recordings-list section header — a task can hold
  // several named notes now (see VoiceNote), not just the one
  // voiceNoteAttached above used to describe.
  String get voiceNotesTitle => isAr ? 'الملاحظات الصوتية' : 'Voice Notes';
  // Placeholder shown for a recording nobody has named yet — "n" is that
  // note's 1-based position among this task's own recordings.
  String voiceNoteDefaultName(int n) =>
      isAr ? 'تسجيل $n' : 'Recording $n';
  String get voiceNoteRenameTitle =>
      isAr ? 'سمِّ هذا التسجيل' : 'Name this recording';
  String get voiceNoteRenameHint => isAr ? 'مثال: الخطوة 1' : 'e.g. Step 1';
  String get voiceNoteRenameSave => isAr ? 'حفظ' : 'Save';
  // Semantic label only (not visible text) for the floating global
  // player's close button — see voice_note_player.dart.
  String get voiceNoteClosePlayer => isAr ? 'إغلاق المشغل' : 'Close player';

  // ── Streak nudge ─────────────────────────────────────────────────────────
  String streakAtRiskTitle(int days) => isAr
      ? 'سلسلة الـ$days يومًا على المحك'
      : 'Your $days-day streak is on the line';
  String get streakAtRiskBody => isAr
      ? 'مربّع ملوّن واحد الليلة يبقيها حيّة.'
      : 'One colored square tonight keeps it alive.';

  // ── First-run onboarding ─────────────────────────────────────────────────
  // Tone: benefit-first, short, warm — Khaleeji Arabic (not MSA), matching
  // the notification copy's voice. Each slide also carries a "where to tap"
  // hint so a brand-new user knows exactly which button/tab the slide is
  // talking about.
  String get onboardingGridTitle => isAr
      ? 'لوّن حياتك، مربّع كل يوم'
      : 'Color your life, one square at a time';
  String get onboardingGridBody => isAr
      ? 'كل عادة تخلصها تلوّن مربّع في شبكتك. الأيام الخضرا تتجمع، وشهرك يمتلي شوي شوي.'
      : 'Every habit you finish colors a square. Green days add up. Watch your month fill in.';
  String get onboardingGridHint => isAr
      ? 'اضغط مربّع اليوم في الشبكة عشان تلوّنه'
      : "Tap today's square on the Grid to color it";
  String get onboardingHabitsTitle =>
      isAr ? 'عادات صغيرة، فرق كبير' : 'Small habits, big difference';
  String get onboardingHabitsBody => isAr
      ? 'صلاة، قرآن، رياضة، أي شي يهمك. كل وحدة تخلصها تعطيك نقاط وذهب، وسلسلتك تكبر.'
      : 'Prayer, Quran, gym, anything that matters to you. Each one you finish earns XP and gold, and your streak grows.';
  String get onboardingHabitsHint => isAr
      ? 'اضغط زر ＋ وأضف أول عادة'
      : 'Tap the ＋ button to add your first habit';
  String get onboardingTasksTitle =>
      isAr ? 'رتّب يومك بثواني' : 'Sort your day in seconds';
  String get onboardingTasksBody => isAr
      // Quadrant names match MatrixQuadrant.localLabel exactly (أولاً /
      // جدول / فوّض / احذف) so the slide teaches the same words the
      // Tasks screen actually shows.
      ? 'حط مهامك في أربع خانات: أولاً، جدول، فوّض، أو احذف. والمهم ما يضيع.'
      : 'Drop tasks into four boxes: Do First, Schedule, Delegate, or Eliminate. The important stuff never gets lost.';
  String get onboardingTasksHint => isAr
      ? 'من تبويب المهام في الشريط تحت'
      : 'Find it in the Tasks tab below';
  String get onboardingAchievementsTitle =>
      isAr ? 'كل إنجاز له طعم' : 'Every win counts';
  String get onboardingAchievementsBody => isAr
      ? 'نقاط وذهب ومستويات وإنجازات تفتحها وحدة وحدة. ثباتك هني له قيمة.'
      : 'XP, gold, levels, and achievements to unlock one by one. Your consistency is worth something here.';
  String get onboardingAchievementsHint => isAr
      ? 'شوفها كلها من تبويب ملفي'
      : 'See them all in your Profile tab';
  String get onboardingRoomsTitle =>
      isAr ? 'مع الربع أحلى' : 'Better with your people';
  String get onboardingRoomsBody => isAr
      // وناسة (not ونسة) — the real Gulf spelling, per the user.
      ? 'سوّ غرفة لأهلك وربعك، اربطوا عاداتكم، وتسابقوا على الصدارة. إنتاجية ووناسة.'
      : 'Make a room with family and friends, link your habits, and race up the leaderboard. Productive, together.';
  String get onboardingRoomsHint => isAr
      ? 'من ملفي، افتح الغرف وابدأ التحدي'
      : 'Open Rooms from your Profile to start one';
  String get onboardingSkip => isAr ? 'تخطّي' : 'Skip';
  String get onboardingNext => isAr ? 'التالي' : 'Next';
  String get onboardingGetStarted => isAr ? 'يلا نبدأ' : 'Start coloring';

  // ── Habit icon color picker ──────────────────────────────────────────────
  // Triggered from the name/category step of AddHabitSheet — a full-
  // spectrum picker (drag + hex) for one habit's own icon color, instead of
  // the icon always inheriting its category's fixed color.
  String get habitIconColor => isAr ? 'لون الأيقونة' : 'Icon color';
  String get habitIconColorHint => isAr
      ? 'اختر أي لون لأيقونة هذه العادة'
      : 'Pick any color for this habit\'s icon';
  String get hexCode => isAr ? 'الرمز السداسي' : 'Hex code';
  String get useDefaultColor => isAr ? 'اللون الافتراضي' : 'Use default color';
  String get colorPickerDone => isAr ? 'تم' : 'Done';

  // ── Rooms (group challenges) ─────────────────────────────────────────────
  // A room is a multi-user challenge: a leader creates one (naming it,
  // choosing whether everyone shares one habit or brings their own, and how
  // long it runs), others join with a short code, and everyone sees a live
  // leaderboard of % days completed. Reached from Profile's Rooms row - see
  // lib/features/rooms/.
  String get roomsTitle => isAr ? 'الغرف' : 'Rooms';
  String get roomGenericError =>
      isAr ? 'حدث خطأ ما. حاول مرة أخرى.' : 'Something went wrong. Please try again.';
  String get roomsEmptyTitle => isAr ? 'لا توجد غرف بعد' : 'No rooms yet';
  String get roomsEmptyBody => isAr
      ? 'أنشئ غرفة أو انضم إلى واحدة برمز لبدء تحدٍ مع أصدقائك.'
      : 'Create a room or join one with a code to start a challenge with friends.';
  String get roomCreateAction => isAr ? 'إنشاء غرفة' : 'Create Room';
  String get roomJoinAction => isAr ? 'انضمام لغرفة' : 'Join Room';
  String get roomGuestGateTitle =>
      isAr ? 'سجّل الدخول لاستخدام الغرف' : 'Sign in to use Rooms';
  String get roomGuestGateBody => isAr
      ? 'الغرف تشارك لوحة صدارة حيّة مع الجميع فيها، لذلك تحتاج إلى حساب.'
      : 'Rooms share a live leaderboard with everyone in them, so they need an account.';
  String get roomGuestGateAction => isAr ? 'تسجيل الدخول' : 'Sign In';

  // Create Room sheet
  String get roomCreateTitle => isAr ? 'إنشاء غرفة' : 'Create a Room';
  String get roomNameLabel => isAr ? 'اسم الغرفة' : 'Room name';
  String get roomNameHint => isAr ? 'مثال: تحدي الفجر' : 'e.g. Fajr Challenge';
  String get roomHabitModeLabel => isAr ? 'كيف تعمل العادة؟' : 'How does the habit work?';
  String get roomHabitModeShared => isAr ? 'خطة القائد' : "Leader's plan";
  String get roomHabitModeSharedHint => isAr
      ? 'اختر من عاداتك — كل من ينضم يحصل عليها في شبكته أيضًا'
      : "Pick from your own habits — everyone who joins gets them added to their Grid too";
  String get roomHabitModeOwn => isAr ? 'عادة كل شخص الخاصة' : "Everyone's own habit";
  String get roomHabitModeOwnHint => isAr
      ? 'كل شخص يربط عادة واحدة أو أكثر من عاداته الخاصة'
      : 'Each person links one or more of their own habits';
  String get roomYourHabitLabel => isAr ? 'عادتك لهذه الغرفة' : 'Your habit for this room';

  // Create Room - own-mode picker (multi-select from the leader's own
  // habits, tracked directly - no plan/cloning, unlike shared mode below)
  String get roomOwnHabitsLabel =>
      isAr ? 'أي من عاداتك؟' : 'Which of your habits?';
  String get roomOwnHabitsHint => isAr
      ? 'اختر عادة واحدة أو أكثر لتتبعها في هذه الغرفة.'
      : 'Pick 1 or more of your own habits to track in this room.';

  // Create Room - plan builder (multi-select from the leader's own habits)
  String get roomPlanHabitsLabel =>
      isAr ? 'ما العادات التي تُكوّن الخطة؟' : 'Which habits make up the plan?';
  String get roomPlanHabitsHint => isAr
      ? 'اختر عادة واحدة أو أكثر من عاداتك — كل من ينضم سيحصل عليها في شبكته أيضًا.'
      : 'Pick 1 or more of your own habits — everyone who joins gets them added to their Grid too.';
  String roomPlanSelectedCount(int n) {
    if (!isAr) return n == 1 ? '1 habit selected' : '$n habits selected';
    if (n == 0) return 'لم يتم اختيار شيء';
    if (n == 1) return 'تم اختيار عادة واحدة';
    if (n == 2) return 'تم اختيار عادتين';
    final mod100 = n % 100;
    if (mod100 >= 3 && mod100 <= 10) return 'تم اختيار $n عادات';
    return 'تم اختيار $n عادة';
  }
  String get roomDurationLabel => isAr ? 'كم المدة؟' : 'How long?';
  String get roomDurationOpenEnded => isAr ? 'بدون تاريخ نهاية' : 'No end date';
  String get roomCreateSubmit => isAr ? 'إنشاء الغرفة' : 'Create Room';

  // Just-created "share the code" moment
  String get roomCreatedTitle => isAr ? 'تم إنشاء الغرفة!' : 'Room created!';
  String get roomShareCode => isAr
      ? 'شارك هذا الرمز مع أصدقائك لينضموا'
      : 'Share this code with friends to have them join';
  String get roomCodeCopied => isAr ? 'تم نسخ الرمز' : 'Code copied';
  String get roomCopyAction => isAr ? 'نسخ الرمز' : 'Copy Code';
  String get roomShareAction => isAr ? 'مشاركة' : 'Share';
  String get roomDoneAction => isAr ? 'تم' : 'Done';
  // Includes a growdaily://join/CODE deep link (see main.dart's AppLinks
  // wiring) alongside the human-readable code, so tapping it on a device
  // that already has GrowDaily installed jumps straight to a pre-filled
  // Join Room sheet instead of the recipient having to open the app and
  // type the code by hand - the code on its own line still works exactly
  // as before wherever the link isn't clickable.
  String roomShareMessage(String name, String code) => isAr
      ? 'انضم إلى تحدي "$name" في GrowDaily!\nرمز الغرفة: $code\ngrowdaily://join/$code'
      : 'Join my "$name" challenge on GrowDaily!\nRoom code: $code\ngrowdaily://join/$code';

  // Join Room sheet
  String get roomJoinTitle => isAr ? 'الانضمام إلى غرفة' : 'Join a Room';
  String get roomCodeLabel => isAr ? 'رمز الغرفة' : 'Room code';
  String get roomCodeHint => isAr ? 'مثال: FJR482' : 'e.g. FJR482';
  String get roomFindAction => isAr ? 'بحث' : 'Find';
  String get roomNotFound => isAr
      ? 'لا توجد غرفة بهذا الرمز. تحقق وحاول مرة أخرى.'
      : 'No room with that code. Double-check and try again.';
  String get roomAlreadyEndedJoin => isAr
      ? 'انتهت هذه الغرفة ولم تعد تقبل أعضاءً جدد.'
      : "This room has already ended and isn't accepting new members.";
  String get roomPreviewOwnMode => isAr ? 'أحضر عادتك الخاصة' : 'Bring your own habit';
  String roomPreviewSharedHabit(String name) =>
      isAr ? 'الجميع يتابع: $name' : 'Everyone tracks: $name';
  String get roomPickHabitLabel =>
      isAr ? 'أي عادة ستتابعها هنا؟' : 'Which habit will you track here?';
  String get roomPickHabitHint => isAr ? 'اختر عادة' : 'Choose a habit';
  String get roomPickHabitsLabel =>
      isAr ? 'أي عادات ستتابعها هنا؟' : 'Which habits will you track here?';
  String get roomNoHabitsYet => isAr
      ? 'ليس لديك أي عادات بعد — أضف واحدة أولاً.'
      : "You don't have any habits yet — add one first.";

  // Join Room - plan review step (link an existing habit or add a new one
  // per entry in the leader's plan; pre-filled by suggestExistingMatch,
  // always editable before actually joining)
  String get roomPlanReviewLabel =>
      isAr ? 'طابق مع عاداتك' : 'Match to your habits';
  String get roomPlanAddAsNew =>
      isAr ? 'إضافة كعادة جديدة' : 'Add as new habit';
  String roomPlanLinkExisting(String name) =>
      isAr ? 'ربط: $name' : 'Link: $name';
  String get roomJoinSubmit => isAr ? 'انضمام للغرفة' : 'Join Room';

  /// "N members" - own Arabic plural class from [daysCount]'s (different
  /// word, same 0/1/2/3-10/11-99/100+ shape the language always needs).
  String roomMemberCount(int n) {
    if (!isAr) return n == 1 ? '1 member' : '$n members';
    if (n == 0) return 'لا أعضاء';
    if (n == 1) return 'عضو واحد';
    if (n == 2) return 'عضوان';
    final mod100 = n % 100;
    if (mod100 >= 3 && mod100 <= 10) return '$n أعضاء';
    if (mod100 >= 11 && mod100 <= 99) return '$n عضوًا';
    return '$n عضو';
  }

  // Room Detail / leaderboard screen
  String get roomOngoing => isAr ? 'مستمرة' : 'Ongoing';
  String get roomEnded => isAr ? 'انتهت' : 'Ended';
  String roomDaysLeft(int n) =>
      isAr ? '${daysCount(n)} متبقية' : '${daysCount(n)} left';
  String get roomMyPlanTitle => isAr ? 'خطتك' : 'Your plan';
  String get roomMarkedToday => isAr ? 'تم إنجاز اليوم' : 'Done for today';
  String get roomNotDoneToday => isAr ? 'لم يُنجز بعد اليوم' : 'Not yet today';
  /// "1/2 today" - shown instead of [roomMarkedToday]/[roomNotDoneToday]
  /// when some but not all of a multi-habit plan is done today (see
  /// RoomParticipant.isFullyDone) - the partial-credit middle state
  /// between the other two.
  String roomPartialToday(int done, int total) =>
      isAr ? '$done من $total اليوم' : '$done/$total today';
  String roomPlanPartialCreditHint(int n) => isAr
      ? 'كل عادة تُنجزها تضيف جزءًا من التقدم — إكمال كل الـ $n يمنحك اليوم كاملًا'
      : 'Each one you finish adds partial credit — complete all $n for the full day';
  String get roomDetailsHidden => isAr ? 'مخفي عن الغرفة' : 'Hidden from room';
  String get roomDetailsVisible => isAr ? 'مرئي للغرفة' : 'Visible to room';
  // Kept around for any link that went stale before habit deletion started
  // unlinking automatically (see habitLinkedRoomWarningBody below) - going
  // forward this shouldn't normally trigger. Deliberately no longer
  // recommends leaving and rejoining as a clean fix: leaveRoom deletes the
  // whole participant doc, so rejoining relinks the habit but also wipes
  // every prior day of progress in this room - only worth it if starting
  // over here is genuinely fine.
  String get roomLinkedHabitDeletedHint => isAr
      ? 'إحدى العادات المرتبطة لم تعد موجودة في شبكتك. يمكن لمغادرة الغرفة وإعادة الانضمام إعادة ربطها، لكن ذلك يصفّر تقدمك في هذه الغرفة أيضًا — فافعل ذلك فقط إذا كنت لا تمانع البدء من جديد.'
      : "A linked habit no longer exists in your Grid. Leaving and rejoining relinks it, but also resets your progress in this room — only do that if you're fine starting over here.";
  /// Shown before a habit that's linked to one or more rooms actually gets
  /// deleted (see AddHabitSheet._deleteExisting/GridScreen._deleteSelected)
  /// - the one moment this consequence is still easy to avoid, unlike after
  /// the fact when all that's left is roomLinkedHabitDeletedHint's warning.
  String get habitLinkedRoomWarningTitle =>
      isAr ? 'مرتبطة بغرفة مشتركة' : 'Linked to a shared room';
  String habitLinkedRoomWarningBody(int roomCount) => isAr
      ? (roomCount == 1
          ? 'هذه العادة جزء من تقدمك في غرفة مشتركة. حذفها سيُلغي ربطها بتلك الغرفة فورًا.'
          : 'هذه العادة جزء من تقدمك في $roomCount غرف مشتركة. حذفها سيُلغي ربطها بها جميعًا فورًا.')
      : (roomCount == 1
          ? "This habit counts toward your progress in a shared room. Deleting it will unlink it from that room right away."
          : "This habit counts toward your progress in $roomCount shared rooms. Deleting it will unlink it from all of them right away.");
  String get habitDeleteAnywayAction => isAr ? 'حذف على أي حال' : 'Delete Anyway';
  String get habitDeleteLinkedRoomCancel => isAr ? 'إلغاء' : 'Cancel';
  /// "3/5 days" when [done] is whole, "2.5/5 days" when a multi-habit
  /// room's partial-credit days (see RoomParticipant.daysCompleted) leave
  /// it fractional - shows the exact number either way rather than
  /// rounding, since rounding here would quietly disagree with the %
  /// shown right next to it.
  String roomDayCount(double done, int total) {
    final doneStr =
        done == done.roundToDouble() ? done.toInt().toString() : done.toStringAsFixed(1);
    return isAr ? '$doneStr من $total' : '$doneStr/$total days';
  }
  String get roomYouLabel => isAr ? 'أنت' : 'You';
  String get roomLeaderLabel => isAr ? 'القائد' : 'Leader';
  String get roomLeaveAction => isAr ? 'مغادرة الغرفة' : 'Leave Room';
  String get roomLeaveConfirmTitle => isAr ? 'مغادرة هذه الغرفة؟' : 'Leave this room?';
  String get roomLeaveConfirmBody => isAr
      ? 'يمكنك الانضمام مرة أخرى لاحقًا برمز الغرفة.'
      : 'You can rejoin later with the room code.';
  // Shown instead of roomLeaveConfirmBody specifically when the leaving
  // member is the room's own leader (see RoomDetailScreen's _confirmLeave)
  // - covers both of RoomsController.leaveRoom's leader-specific outcomes
  // (hands off to the next member, or deletes the room if no one else is
  // left) without needing an extra read just to know which one applies
  // before the dialog even opens.
  String get roomLeaveConfirmBodyLeader => isAr
      ? 'بصفتك القائد، ستنتقل القيادة تلقائيًا إلى أقدم عضو آخر — أو سيتم حذف الغرفة إذا كنت العضو الوحيد فيها.'
      : "As the leader, leaving hands the room off to its next-longest member — or deletes the room if you're the only one left.";
  String get roomLeaveConfirmCancel => isAr ? 'إلغاء' : 'Cancel';
  String get roomDeleteAction => isAr ? 'حذف الغرفة' : 'Delete Room';
  String get roomDeleteConfirmTitle => isAr ? 'حذف هذه الغرفة؟' : 'Delete this room?';
  String get roomDeleteConfirmBody => isAr
      ? 'سيؤدي هذا إلى إزالتها للجميع، ولا يمكن التراجع عن ذلك.'
      : "This removes it for everyone and can't be undone.";
  String get roomGoneMessage =>
      isAr ? 'هذه الغرفة لم تعد موجودة.' : 'This room no longer exists.';
  String get roomExtendAction => isAr ? 'تمديد الغرفة' : 'Extend Room';
  String get roomExtendTitle => isAr ? 'تمديد هذه الغرفة' : 'Extend this room';
  String get roomExtendBody => isAr
      ? 'اختر مدة جديدة تبدأ من اليوم، أو اجعلها بلا نهاية.'
      : 'Pick a new duration starting today, or make it open-ended.';
  String get roomExtended => isAr ? 'تم تمديد الغرفة.' : 'Room extended.';

  // ── Notification Settings ────────────────────────────────────────────
  // (see features/settings/screens/notification_settings_screen.dart and
  // features/settings/widgets/city_search_sheet.dart)

  String get notificationsTitle => isAr ? 'الإشعارات' : 'Notifications';

  String get notifMasterTitle =>
      isAr ? 'السماح بالإشعارات' : 'Allow Notifications';
  String get notifMasterDesc => isAr
      ? 'أوقفه لإيقاف كل إشعارات GrowDaily — التذكيرات والسلاسل والاحتفالات، كل شيء.'
      : 'Turn off to stop every notification GrowDaily sends — reminders, streaks, celebrations, all of it.';

  String get notifWhatSection =>
      isAr ? 'ما الذي تريد إشعاري به' : 'WHAT TO NOTIFY ME ABOUT';
  String get notifHabitReminders => isAr ? 'تذكيرات العادات' : 'Habit reminders';
  String get notifHabitRemindersDesc => isAr
      ? 'تذكير لكل عادة في وقتها الخاص — يُتخطى تلقائيًا بعد إنجازها لهذا اليوم.'
      : "One reminder per habit, at its own cue — skipped automatically once you've done it for the day.";
  String get notifStreakRisk => isAr ? 'حماية السلسلة' : 'Streak protection';
  String get notifStreakRiskDesc => isAr
      ? 'تنبيه مسائي، فقط عندما تكون سلسلة حقيقية على وشك الضياع.'
      : "An evening nudge, but only when a real streak is actually about to be lost.";
  String get notifCelebrations => isAr ? 'الاحتفالات' : 'Celebrations';
  String get notifCelebrationsDesc => isAr
      ? 'إشعارات إنجاز العادة، الترقية، وفتح الإنجازات.'
      : 'Habit completed, level up, and achievement-unlocked pings.';
  String get notifMatrixNudge => isAr ? 'ذكر المهام العاجلة' : 'Mention urgent tasks';
  String get notifMatrixNudgeDesc => isAr
      ? 'يضيف مهامك العاجلة من "افعل أولاً" إلى تنبيه السلسلة — لا يُرسل كإشعار منفصل أبدًا.'
      : "Adds your open Do First tasks to the streak nudge — never a separate notification of its own.";
  String get notifBundle => isAr ? 'دمج التذكيرات المتقاربة' : 'Bundle close-together reminders';
  String get notifBundleDesc => isAr
      ? 'عندما تتقارب مواعيد عادتين أو أكثر، تصل كإشعار واحد بدلًا من عدة إشعارات.'
      : '2+ habits due around the same time arrive as one notification instead of several.';

  String get notifPrayerSection =>
      isAr ? 'تذكيرات مرتبطة بأوقات الصلاة' : 'PRAYER-TIME REMINDERS';
  String get notifLocationNotSet => isAr ? 'غير محدد' : 'Not set';
  String get notifLocationHint => isAr
      ? 'اضغط أعلاه لتحديد موقعك تلقائيًا وتفعيل التذكيرات المرتبطة بأوقات الصلاة.'
      : 'Tap above to auto-detect your location and turn on prayer-linked reminders.';
  // Always shown under the location row (set or not) — the long-press
  // escape hatch to manual city search only exists for travel/denied-GPS
  // cases, so it needs to stay discoverable even after a location is
  // already set. See NotificationSettingsScreen's doc comment.
  String get notifLocationManualHint => isAr
      ? 'اضغط مطولاً للبحث عن مدينة يدويًا بدلاً من ذلك'
      : 'Long-press to search for a city manually instead';
  String get notifDetectingLocation =>
      isAr ? 'جارٍ تحديد الموقع…' : 'Detecting…';
  String get notifLocationDetectFailed => isAr
      ? 'تعذّر تحديد موقعك — ابحث عن مدينتك بدلاً من ذلك.'
      : "Couldn't detect your location — search for your city instead.";
  String get notifCalcMethod => isAr ? 'طريقة الحساب' : 'Calculation method';
  String get notifPrayerOffset => isAr ? 'ذكّرني' : 'Remind me';

  /// "10 minutes after" / "At prayer time" for 0 — the offset applied after
  /// a prayer's own calculated time before a linked habit reminder fires.
  /// Own Arabic plural class, same 0/1/2/3-10/11+ shape as [roomMemberCount]
  /// and [daysCount].
  String minutesAfterPrayer(int n) {
    if (!isAr) {
      if (n == 0) return 'At prayer time';
      return n == 1 ? '1 minute after' : '$n minutes after';
    }
    if (n == 0) return 'عند وقت الصلاة';
    if (n == 1) return 'دقيقة واحدة بعد';
    if (n == 2) return 'دقيقتان بعد';
    final mod100 = n % 100;
    if (mod100 >= 3 && mod100 <= 10) return '$n دقائق بعد';
    return '$n دقيقة بعد';
  }

  String get notifQuietHoursSection => isAr ? 'ساعات الهدوء' : 'QUIET HOURS';
  String get notifQuietHours => isAr ? 'ساعات الهدوء' : 'Quiet hours';
  String get notifQuietHoursDesc =>
      isAr ? 'لا تُرسل أي تذكيرات خلال هذه الفترة.' : 'No reminders fire during this window.';
  String get notifQuietStart => isAr ? 'تبدأ' : 'Starts';
  String get notifQuietEnd => isAr ? 'تنتهي' : 'Ends';
  String get notifQuietAppliesToPrayer =>
      isAr ? 'تطبيقها على تذكيرات الصلاة أيضًا' : 'Apply to prayer reminders too';
  String get notifQuietAppliesToPrayerDesc => isAr
      ? 'معطّلة افتراضيًا — الفجر عادة يقع ضمن فترة الهدوء الليلية، وهو التذكير الذي يريده معظم الناس رغم ذلك.'
      : "Off by default — Fajr usually falls inside a nighttime quiet window, and that's the one reminder most people still want.";

  String get notifTimingSection => isAr ? 'التوقيت' : 'TIMING';
  String get notifStreakRiskTime => isAr ? 'وقت فحص السلسلة' : 'Streak check time';

  String get notifSendTest => isAr ? 'إرسال إشعار تجريبي' : 'Send a test notification';
  String get notifTestSent =>
      isAr ? 'تم الإرسال — تحقق من قائمة الإشعارات.' : 'Sent — check your notification shade.';

  // ── City search (prayer-time location) ───────────────────────────────

  String get prayerLocationTitle => isAr ? 'الموقع' : 'Location';
  // Accurate about the live API call (coordinates are sent to a
  // prayer-times service to calculate exact times) rather than claiming
  // "on-device" — see PrayerTimesService's doc comment for why that call
  // happens. Still reassuring and true: nothing is stored on GrowDaily's
  // own servers or shared for any other purpose.
  // Broadened from "a prayer-times service" (singular) once location
  // resolution started also using a separate country-lookup service to
  // pick the right calculation method (see CountryLookupService) — still
  // deliberately vendor-agnostic; the point of this note is the purpose
  // (accurate prayer times, nothing else), not naming every third party.
  String get prayerLocationPrivacyNote => isAr
      ? 'يُستخدم موقعك فقط لحساب أوقات الصلاة بدقة (عبر خدمات أوقات الصلاة وتحديد الموقع) — لا يُخزَّن ولا يُشارك لأي غرض آخر.'
      : 'Your location is used only to calculate accurate prayer times (via prayer-times and location-lookup services) — never stored or shared for anything else.';
  String get citySearchHint => isAr ? 'مثال: القاهرة، إسطنبول، جاكرتا' : 'e.g. Cairo, Istanbul, Jakarta';
  String get citySearchNoResults =>
      isAr ? 'لا توجد نتائج — جرّب تهجئة مختلفة.' : 'No matches — try a different spelling.';
  String get citySearchPrompt =>
      isAr ? 'ابدأ بكتابة اسم مدينتك.' : "Start typing your city's name.";
  String get citySearchEnterManually =>
      isAr ? 'لم تجد مدينتك؟ أدخل الإحداثيات يدويًا' : "Can't find your city? Enter coordinates manually";
  String get citySearchBackToSearch => isAr ? 'العودة إلى البحث' : 'Back to search';
  String get locationLabelHint => isAr ? 'تسمية (مثل «المنزل»)' : 'Label (e.g. "Home")';
  String get latitude => isAr ? 'خط العرض' : 'Latitude';
  String get longitude => isAr ? 'خط الطول' : 'Longitude';
  String get useTheseCoordinates => isAr ? 'استخدام هذه الإحداثيات' : 'Use these coordinates';
}
