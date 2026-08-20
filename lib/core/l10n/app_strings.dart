import 'dart:async' show unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/deep_links.dart';
import '../services/local_store_service.dart';
import '../utils/bidi_fraction.dart';
import '../utils/intention_phrase.dart';
import '../../features/grid/models/square_state.dart';

// ─── Locale provider ──────────────────────────────────────────────────────────

final localeProvider = StateNotifierProvider<_LocaleNotifier, Locale>(
  (_) => _LocaleNotifier(),
);

class _LocaleNotifier extends StateNotifier<Locale> {
  _LocaleNotifier([super.initial = const Locale('en')]);

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

  // Best-effort mirror to Firestore for signed-in accounts - the room-finish
  // push Cloud Function (functions/index.js) reads this to pick AR vs EN for
  // a notification it sends about *this* account to someone else's device,
  // since a server has no other way to know which language a given user
  // reads. Never blocks/guards the locale change itself on this succeeding -
  // a guest, or a momentary offline write failure, just means that one
  // account's push text falls back to the function's own default until the
  // next successful sync.
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid != null) {
    unawaited(
      FirebaseFirestore.instance.collection('users').doc(uid).set(
        {'locale': locale.languageCode},
        SetOptions(merge: true),
      ).catchError((_) {}),
    );
  }
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
  String get appTitle => isAr ? 'Grow Daily' : 'Grow Daily';
  String get tagline => isAr
      ? 'لوّن حياتك، مربّعًا كل يوم.'
      : 'Color your life, one square at a time.';

  // ── Auth ─────────────────────────────────────────────────────────────────
  String get signIn => isAr ? 'تسجيل الدخول' : 'Sign In';
  String get createAccount => isAr ? 'إنشاء حساب' : 'Create Account';
  String get signInAction => isAr ? 'دخول' : 'SIGN IN';
  String get createAccountAction => isAr ? 'إنشاء الحساب' : 'CREATE ACCOUNT';
  String get email => isAr ? 'البريد الإلكتروني' : 'Email';
  String get password => isAr ? 'كلمة المرور' : 'Password';
  String get confirmPassword => isAr ? 'تأكيد كلمة المرور' : 'Confirm Password';
  String get tryAsGuest => isAr ? 'جرّب 3 عادات كضيف' : 'TRY 3 HABITS AS GUEST';
  String get guestDescription => isAr
      ? 'لا حاجة لحساب. ابدأ أولى انتصاراتك الآن.'
      : 'No account needed. Complete your first Quran, athkar, or focus win now.';
  String get guestLimitTitle =>
      isAr ? 'وصلت لحد التجربة' : "You've hit the guest limit";
  // "keep your progress synced" was removed from this line deliberately:
  // there is NO guest-to-account migration today (every notifier
  // hard-branches on uid), so the account a guest creates starts empty and
  // this sheet was promising the opposite at the exact moment it mattered.
  // The fresh-start fact lives in [guestFreshStartWarning], shown alongside.
  // If a real migration ships in 1.1, restore the promise then.
  String get guestLimitBody => isAr
      ? 'التجربة كضيف تسمح بـ 3 عادات. أنشئ حسابًا مجانيًا لإضافة عدد غير محدود من العادات والمزامنة عبر أجهزتك.'
      : 'Guest mode is capped at 3 habits. A free account removes the cap and syncs across your devices.';
  String get guestFreshStartWarning => isAr
      ? 'الحساب الجديد يبدأ من الصفر: تقدمك كضيف يبقى على هذا الجهاز ولا ينتقل إلى الحساب.'
      : 'A new account starts fresh: your guest progress stays on this device and does not carry over.';
  String get guestLimitCta => isAr ? 'إنشاء حساب مجاني' : 'Create free account';
  String get guestLimitMaybeLater => isAr ? 'ربما لاحقاً' : 'Maybe later';

  /// The one fact a guest can't discover on their own until it's too late:
  /// their data lives only on this device, so deleting the app erases it for
  /// good and nobody can restore it (see PRIVACY_POLICY.md's Guest mode
  /// section, which now says the same thing). Stated at the moment it's
  /// actually relevant rather than only buried in a policy document.
  ///
  /// Deliberately phrased as a plain fact, not a scare or a sales line - it's
  /// information the person is entitled to before choosing, and it happens to
  /// also be the honest reason to make an account.
  String get guestDataWarning => isAr
      ? 'بياناتك كضيف محفوظة على هذا الجهاز فقط. حذف التطبيق يمحوها نهائيًا، ولا يمكننا استرجاعها لأنه لا توجد لدينا نسخة.'
      : 'Guest data is saved on this device only. Deleting the app erases it permanently, and we cannot restore it because we never hold a copy.';

  // Password reset
  String get authForgotPassword =>
      isAr ? 'نسيت كلمة المرور؟' : 'Forgot password?';
  /// Deliberately the same message whether or not the address has an
  /// account: answering differently would let anyone test which emails are
  /// registered (and Firebase's own email-enumeration protection reports
  /// success either way regardless).
  String get authResetSent => isAr
      ? 'إذا كان لهذا البريد حساب، وصلته رسالة لإعادة التعيين. تحقق من بريدك ومن الرسائل غير المرغوبة.'
      : 'If that address has an account, a reset link is on its way. Check your inbox and spam folder.';
  String get errEnterEmailForReset =>
      isAr ? 'اكتب بريدك الإلكتروني أولًا' : 'Type your email first';

  // Auth errors
  String get errFillAll =>
      isAr ? 'يرجى ملء جميع الحقول' : 'Please fill in all fields';
  String get errPasswordsMismatch =>
      isAr ? 'كلمتا المرور غير متطابقتين' : 'Passwords do not match';
  String get errPasswordTooShort => isAr
      ? 'كلمة المرور يجب أن تكون 6 أحرف على الأقل'
      : 'Password must be at least 6 characters';
  String get errInvalidCredential => isAr
      ? 'البريد الإلكتروني أو كلمة المرور غير صحيحة'
      : 'Invalid email or password';
  String get errEmailInUse => isAr
      ? 'يوجد حساب بهذا البريد الإلكتروني بالفعل'
      : 'An account with this email already exists';
  String get errInvalidEmail =>
      isAr ? 'بريد إلكتروني غير صالح' : 'Invalid email address';
  String get errWeakPassword => isAr
      ? 'كلمة المرور ضعيفة (6 أحرف على الأقل)'
      : 'Password is too weak (min 6 characters)';
  String get errNetwork =>
      isAr ? 'تحقق من اتصالك بالإنترنت' : 'Check your internet connection';
  String get errGeneric =>
      isAr ? 'حدث خطأ. حاول مجدداً.' : 'Something went wrong. Try again.';

  // ── Dashboard ────────────────────────────────────────────────────────────
  String get todaysHabits => isAr ? 'عادات اليوم' : "TODAY'S HABITS";
  String get addHabit => isAr ? 'إضافة عادة' : 'ADD HABIT';
  String get signOut => isAr ? 'تسجيل الخروج' : 'Sign Out';
  String get signOutConfirmTitle => isAr ? 'تسجيل الخروج؟' : 'Sign out?';
  String get signOutConfirmBody => isAr
      ? 'يمكنك تسجيل الدخول مرة أخرى في أي وقت.'
      : 'You can sign back in anytime.';
  String get signOutConfirmCancel => isAr ? 'إلغاء' : 'Cancel';
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
  String get pickOneGoal => isAr
      ? 'اختر هدفاً لدينك أو عملك أو صحتك.'
      : 'Choose one goal for your deen, work, or health.';

  // Snackbars / sheets
  String streakFreezeProtected(int remaining) => isAr
      ? 'تجميد السلسلة حماك. متبقّي $remaining.'
      : 'Streak Freeze protected you. $remaining left.';
  String get claimComeback =>
      isAr ? 'استلم +50 XP عودة' : 'Claim +50 XP comeback';
  String welcomeBack(String name) =>
      isAr ? 'مرحبًا بعودتك، $name' : 'Welcome back, $name';
  String get comebackNoErase => isAr
      ? 'اليوم الفائت لا يمحو تقدمك.'
      : "A missed day doesn't erase your progress.";
  String get comebackBonusHint => isAr
      ? '+50 XP مكافأة عودة عند المتابعة'
      : '+50 XP comeback bonus when you continue';
  String restoreStreakOffer(int days) => isAr
      ? 'استخدم تجميد السلسلة لاستعادة سلسلتك ذات $days يوم بدلاً من البدء من جديد.'
      : 'Use a streak freeze to restore your $days-day streak instead of starting over.';
  String restoreStreakCta(int left) =>
      isAr ? 'استعادة السلسلة ($left متبقّية)' : 'Restore streak ($left left)';
  String get freshStreakInstead =>
      isAr ? 'ابدأ سلسلة جديدة بدلاً من ذلك' : 'Start a fresh streak instead';
  String get keepGrowing => isAr ? 'واصل النمو' : 'Keep growing';
  String get streakMilestoneLabel =>
      isAr ? 'إنجاز السلسلة' : 'STREAK MILESTONE';

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
  String get achievementUnlocked =>
      isAr ? 'إنجاز مفتوح!' : 'ACHIEVEMENT UNLOCKED';
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

  // ── Achievements screen ──────────────────────────────────────────────────
  //
  // Chrome copy for the redesigned screen — the trophy-case header (which
  // replaced the decorative banner PNG) and the Next-up spotlight.
  //
  // Register: impersonal throughout, no second person. The achievement
  // *names* in AchievementCatalog carry the Khaleji voice; the labels
  // around them deliberately don't, so the screen states facts ("باقي 14")
  // rather than cheering at you every time you open it — the fastest way
  // for a gamified surface to start reading as insincere.
  String get achievementsMedalsEarned => isAr ? 'ميداليات' : 'Medals earned';

  /// Deliberately the colloquial form rather than 'التالي' — it's the one
  /// label on the screen that names a *moment* rather than a stat, and the
  /// Gulf phrasing carries that without addressing anyone.
  String get achievementsNextUp => isAr ? 'اللي جاي' : 'Next up';

  /// The gap left to an achievement's threshold — the single most useful
  /// number on the screen, and the one the old layout made you work out
  /// yourself by subtracting the two halves of a "12 / 30" fraction.
  String achievementsRemaining(int n) => isAr ? 'باقي $n' : '$n to go';

  String get achievementsAllDone =>
      isAr ? 'كل الميداليات مفتوحة' : 'Every medal earned';
  String get achievementsMastered => isAr ? 'مكتملة' : 'Mastered';
  String get achievementsEarned => isAr ? 'مفتوحة' : 'Earned';
  String get achievementsTapTierHint =>
      isAr ? 'اضغط أي ميدالية للتفاصيل' : 'Tap any medal for details';

  /// "Silver · The Climb" — the tier and its family, above the achievement
  /// name in the detail sheet. Same shape in both languages; the separator
  /// sits between two already-directional runs, so it needs no bidi help.
  String achievementsTierOf(String tier, String family) => '$tier · $family';
  String get profileSection => isAr ? 'الملف الشخصي' : 'PROFILE';
  String get achievementsRowTitle => isAr ? 'الإنجازات' : 'Achievements';
  String get progressStreakTitle =>
      isAr ? 'التقدم والسلسلة' : 'Progress & Streak';
  // Merged Profile row + screen title replacing the old separate
  // Achievements / Habit Insights / Progress & Streak rows — see
  // ProgressHubScreen's doc comment.
  //
  // "Progress", not "Dashboard". There used to be two different screens
  // answering to that one word: this one (ProgressHubScreen, what the label
  // is actually on) and a separate DashboardScreen — so the name told you
  // nothing about which you'd get, in the product or in the code. That other
  // screen is gone, and this says what it holds.
  String get progressTitle => isAr ? 'التقدّم' : 'Progress';
  String get dashboardViewFullInsights =>
      isAr ? 'عرض الرؤى كاملة' : 'View full Insights';
  String get dashboardViewFullJournal =>
      isAr ? 'عرض كل الملاحظات' : 'View all Habit Notes';
  // Home for the evening/weekly nudges relocated off the Grid screen (see
  // ProfileScreen's _DashboardSection) — streak-at-risk, night-review
  // prompt, and the Friday recap card all now live under this header.
  String get profileDashboardSection => isAr ? 'نظرة عامة' : 'OVERVIEW';
  String get settings => isAr ? 'الإعدادات' : 'SETTINGS';

  /// Title case, unlike [settings] — that one is an all-caps section label
  /// inside a list; this is a screen's own app-bar title.
  String get settingsScreenTitle => isAr ? 'الإعدادات' : 'Settings';
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
  String previewingTheme(String name) => isAr
      ? 'معاينة: $name — مرر للتصفح'
      : 'Previewing: $name — swipe to look around';
  String get language => isAr ? 'اللغة' : 'Language';
  String get languageAr => isAr ? 'العربية' : 'Arabic';
  String get languageEn => isAr ? 'English' : 'English';
  String get cumulativeXp => isAr ? 'مجموع XP' : 'cumulative XP';
  String xpToLevel(int n) => isAr ? '$n XP للمستوى ${n + 1}' : 'XP to Level $n';

  /// The fraction goes through [progressFraction] so its two numbers keep the
  /// order they were written in Arabic — see that function's doc comment. A
  /// bare "$current / $total" inside an RTL sentence renders as "100 / 0".
  String xpProgress(int current, int total, int nextLevel) => isAr
      ? '${progressFraction(current, total)} XP للمستوى $nextLevel'
      : '${progressFraction(current, total)} XP to Level $nextLevel';
  String get best => isAr ? 'أفضل' : 'BEST';
  String get total => isAr ? 'المجموع' : 'TOTAL';

  // ── Stat-cell info popups (ProfileScreen's _StatsRow) ───────────────────
  // One small sheet per stat cell, explaining exactly what that number
  // means and how it's earned - tapping streak/best/total/gold/XP opens
  // this instead of leaving five bare numbers for the user to guess at.
  // See stat_info_sheet.dart's showStatInfoSheet, the one sheet all five
  // reuse.
  String get statInfoStreakTitle => isAr ? 'السلسلة' : 'Streak';
  String get statInfoStreakDesc => isAr
      ? 'عدد الأيام المتتالية التي أنجزت فيها كل عاداتك لهذا اليوم. تفويت يوم كامل يُصفّرها - إلا إذا حماك تجميد السلسلة.'
      : "Consecutive days you've completed every habit on your board. Miss a full day and it resets — unless a streak freeze covers you.";
  String get statInfoBestTitle => isAr ? 'أفضل سلسلة' : 'Best Streak';
  String get statInfoBestDesc => isAr
      ? 'أطول سلسلة حققتها على الإطلاق. بمجرد تجاوزها، يرتفع هذا الرقم ويبقى كما هو.'
      : 'Your longest streak ever. Beat it, and this number moves up and stays there for good.';
  // Arabic deliberately avoids 'الإنجازات' here - that's the exact word
  // this app's real Achievements/badges screen already uses (see
  // `achievements`/`achievementsRowTitle` above), and reusing it for this
  // unrelated "every habit tick, ever" tally reads as if this number and
  // the Achievements count are the same thing, when they're not (this one
  // is a raw completion tally; Achievements are discrete unlocked badges,
  // a much smaller number). 'الإتمام' (completion) keeps this stat's own
  // title unambiguous.
  String get statInfoTotalTitle =>
      isAr ? 'إجمالي مرات الإتمام' : 'Total Completions';
  String get statInfoTotalDesc => isAr
      ? 'كل عادة أنجزتها على الإطلاق، مجمّعة عبر رحلتك بأكملها - رقم لا يُصفَّر أبدًا.'
      : "Every habit you've ever checked off, added up across your whole journey — a tally that never resets.";
  String get statInfoGoldTitle => isAr ? 'الذهب' : 'Gold';
  String get statInfoGoldDesc => isAr
      ? 'تكسبه بإنجاز العادات والمهام. أنفقه في المتجر على أزياء وإكسسوارات لشخصيتك.'
      : 'Earned by completing habits and tasks. Spend it in the Shop on outfits and accessories for your character.';
  String get statInfoXpTitle => isAr ? 'مجموع الخبرة' : 'Total XP';
  String get statInfoXpDesc => isAr
      ? 'الخبرة التي تكسبها من كل عادة ومهمة تنجزها. هي ما يرفع مستوى شخصيتك بمرور الوقت.'
      : "Experience earned from every habit and task you complete. It's what levels your character up over time.";

  // Progress report
  String get fourteenDayProgress => isAr ? 'تقدم 14 يوم' : '14-day progress';
  // Impersonal, matching the achievements chrome — the app states what the
  // chart shows rather than addressing the reader. "أسبوعك الأخير قوي" and
  // "ابدأ اليوم مجدداً" made the same surface sound like a coach one screen
  // away from one that sounds like a scoreboard.
  String get holdingStrong =>
      isAr ? 'الأسبوع الأخير قوي' : 'The last week is holding strong';
  String get startAgain =>
      isAr ? 'الانتصارات الصغيرة تُعتبر' : 'Small wins still count';

  /// The third state of the 14-day card. Without it an empty fortnight fell
  /// through to [holdingStrong] — `0 >= 0` is technically "not declining" —
  /// so a chart with nothing on it congratulated you.
  String get noProgressYet =>
      isAr ? 'ما في بيانات كافية بعد' : 'Nothing tracked yet';

  String get loadingReport =>
      isAr ? 'جارٍ تحميل التقرير...' : 'Loading the report...';
  String get activeDays => isAr ? 'الأيام النشطة' : 'ACTIVE DAYS';
  String get bestDay => isAr ? 'أفضل يوم' : 'BEST DAY';

  // Progress report — per-day detail sheet (tapping a bar in the 14-day chart)
  String get progressToday => isAr ? 'اليوم' : 'Today';
  String get progressYesterday => isAr ? 'أمس' : 'Yesterday';

  /// Section header above the per-habit list in the 14-day chart's day
  /// sheet — what was actually done that day, plus any note left on a
  /// habit from Grid's long-press editor.
  String get progressDayBreakdown => isAr ? 'تفاصيل اليوم' : 'THAT DAY';

  String progressDayCompletions(int count) {
    if (count == 0) return isAr ? 'لا عادات مكتملة' : 'No habits completed';
    if (count == 1) return isAr ? 'عادة واحدة مكتملة' : '1 habit completed';
    return isAr ? '$count عادات مكتملة' : '$count habits completed';
  }

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

  /// Small caption shown above a plan's expanded habit checklist (see
  /// PlanPickerSheet's _HabitChip) - every habit starts checked, this is
  /// the only hint that tapping one unchecks it instead of this being a
  /// read-only preview of what Start adds.
  String get planPickHabitsHint => isAr
      ? 'كل العادات محددة تلقائيًا — اضغط على أي وحدة عشان تستبعدها'
      : 'Everything is checked by default — tap any habit to leave it out';

  /// Bottom-button label once at least one (but not all) of a plan's
  /// checklist habits is still checked (see _PlanCard's stagedCount) -
  /// tapping it commits exactly the checked set via
  /// ActiveCatalogNotifier.applyPlanSelection, adding whichever of those
  /// aren't already active and deactivating any unchecked one that
  /// happened to be. [n] is how many are checked right now, not how many
  /// are left to reach the full plan - unchecking habits lowers this
  /// count, it never means "the rest.".
  String addRemainingPlanHabits(int n) =>
      isAr ? 'أضف المحدد ($n)' : 'Add Selected ($n)';
  String get browsePlans => isAr ? 'استعرض الخطط' : 'Browse Plans';
  String get dailyReminder => isAr ? 'تذكير يومي' : 'Daily Reminder';
  String get tapToSetReminder =>
      isAr ? 'اضغط لتعيين وقت التذكير' : 'Tap to set reminder time';
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
  String get habitNameHint =>
      isAr ? 'ما العادة التي تريد بناءها؟' : 'What habit do you want to build?';
  String get afterWhatRoutine => isAr
      ? 'بعد أو قبل أي روتين؟ (اختياري)'
      : 'Before or after what routine? (optional)';
  String get routineHint => isAr
      ? 'الفجر، قبل العمل، بعد المغرب...'
      : 'Fajr, before work, after Maghrib...';
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
  String get whatImprove =>
      isAr ? 'ما الذي تريد تحسينه؟' : 'What do you want to improve?';
  String get buildHabitTitle => isAr ? 'أبني عادة' : 'Build a habit';
  String get buildHabitSubtitle => isAr
      ? 'أنشئ شيئًا تريد فعله أكثر.'
      : 'Create something you want to do more.';
  String get quitHabitTitle =>
      isAr ? 'أترك أو أقلل عادة' : 'Quit / reduce something';
  String get quitHabitSubtitle => isAr
      ? 'تحكّم في شيء تريد فعله أقل.'
      : 'Control something you want to do less.';
  String get whatHabitBuild =>
      isAr ? 'ما العادة التي تريد بناءها؟' : 'What habit do you want to build?';
  String get whatReduce =>
      isAr ? 'ما الذي تريد تقليله؟' : 'What do you want to reduce?';
  String get goalTitleHint => isAr
      ? 'اكتب هدفك أو اختر اقتراحًا'
      : 'Type your goal or pick a suggestion';
  String get smartSuggestions => isAr ? 'اقتراحات ذكية' : 'Smart suggestions';
  String get timingBuildTitle =>
      isAr ? 'متى وكيف ستتابع؟' : 'When and how often?';
  String get timingQuitTitle =>
      isAr ? 'ما الخطة الهادئة؟' : 'What is the calm plan?';
  String get whenQuestion => isAr ? 'متى؟' : 'When?';
  String get customTime => isAr ? 'وقت مخصص' : 'Custom time';
  String get customText => isAr ? 'نص مخصص' : 'Custom text';
  String get cuePrayerOption => isAr ? 'وقت الصلاة' : 'Prayer time';
  String get pickAPrayer => isAr ? 'اختر صلاة' : 'Pick a prayer';
  // ── Reminder lead time (Add Habit → When step) ─────────────────────
  // When the notification fires relative to the picked time/prayer —
  // separate from _CueRelation's "before/after [routine]" text above, which
  // only affects the habit's own display label, not scheduling.
  // Deliberately just "Remind me" (not "Remind me before"): the row this
  // labels now covers both directions, so naming one of them in the header
  // would contradict half its own options.
  String get remindMeSection => isAr ? 'ذكّرني' : 'Remind me';
  String get leadAtTime => isAr ? 'في الوقت' : 'On time';
  String get leadCustomOption => isAr ? 'مخصص' : 'Custom';
  String get leadCustomMinutesHint => isAr ? 'دقائق' : 'Minutes';

  // Signed offset chips (_reminderOffsetSection). Deliberately compact
  // ("30m before", not "30 minutes before"): these sit in a 3-column grid
  // whose cells are ~100dp on a small phone, and the live preview directly
  // underneath already spells out the resulting clock time in full — so
  // these only need to be scannable, not self-explanatory.
  //
  // Arabic leads with the preposition: "قبل ٣٠ د", never "٣٠ د قبل". The
  // trailing form these used to carry is English word order wearing Arabic
  // words — the same mistake formatOffsetVerbose (custom_offset_sheet.dart)
  // documents at length, shipping here unnoticed because the two were
  // written months apart. Matrix's chips build their labels through
  // formatOffsetCompact instead; these are Add Habit's, and the two grids
  // are supposed to be indistinguishable.
  String offsetBeforeMinutes(int n) => isAr ? 'قبل $n د' : '${n}m before';
  String offsetAfterMinutes(int n) => isAr ? 'بعد $n د' : '${n}m after';
  // Direction toggle beside the Custom minutes field.
  String get offsetBeforeLabel => isAr ? 'قبل' : 'Before';
  String get offsetAfterLabel => isAr ? 'بعد' : 'After';

  // Quiet-hours conflict warning (_quietHoursWarning in add_habit_sheet)
  // and its one-tap per-habit override. Replaces the old behavior where
  // such a reminder was cancelled silently and never explained.
  String get quietHoursConflictWarning => isAr
      ? 'هذا الوقت يقع ضمن ساعات الهدوء — لن يصلك التذكير.'
      : "This lands inside your quiet hours — it won't be delivered.";
  String get quietHoursOverrideOn => isAr
      ? 'سيصلك هذا التذكير رغم ساعات الهدوء.'
      : 'This reminder will be delivered anyway, despite quiet hours.';
  String get quietHoursAllowAnywayAction =>
      isAr ? 'اسمح به على أي حال' : 'Allow anyway';
  String get quietHoursRespectAction =>
      isAr ? 'احترم ساعات الهدوء' : 'Respect quiet hours';

  // Small live preview under the offset picker (_reminderOffsetSection in
  // add_habit_sheet.dart) — [time] is the already-localized clock string
  // (e.g. "1:00 PM"), computed from the picked clock time (or, for a prayer
  // cue, PrayerTimesService.calculateOfflineCorrected) plus the habit's own
  // signed offset. Nothing global is folded in anymore, which is what makes
  // this match the real scheduled fire time exactly.
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
  String get customTriggerOptional =>
      isAr ? 'وقت أو موقف مخصص (اختياري)' : 'Custom time or trigger (optional)';
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
    final clause =
        selfContained ? capitalizeFirst(trimmedCue) : 'After $trimmedCue';
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
  String get focusTagline =>
      isAr ? 'خطة واضحة. انتصار نظيف.' : 'One clear plan. One clean win.';
  String focusRitualProgress(int done) =>
      isAr ? '$done/3 خطوة مكتملة' : '$done/3 ritual steps complete';
  String get focusMostImportantTask =>
      isAr ? 'أهم مهمة' : 'Most important task';
  String get focusMitSubtitle => isAr
      ? 'اختر النتيجة التي تجعل يومك منتجاً.'
      : 'Pick the one outcome that makes today productive.';
  String get focusIfThenPlan => isAr ? 'خطة إذا / سأفعل' : 'IF / THEN PLAN';
  String get focusTopTaskHint =>
      isAr ? 'مثال: أنهِ تدفق الإدخال' : 'Example: Finish the onboarding flow';
  String get focusTopTaskLabel => isAr ? 'أهم مهمة' : 'Top task';
  String get focusCuePrefix => isAr ? 'إذا ' : 'If ';
  String get focusCueHint =>
      isAr ? 'الساعة 9 على مكتبي' : 'it is 9:00 at my desk';
  String get focusCueLabel =>
      isAr ? 'الإشارة: متى وأين' : 'Cue: when and where';
  String get focusActionPrefix => isAr ? 'سأفعل ' : 'I will ';
  String get focusActionHint =>
      isAr ? 'ابدأ سبرنت تركيز 25 دقيقة' : 'start a 25-minute focus sprint';
  String get focusActionLabel =>
      isAr ? 'الفعل: الخطوة التالية الدقيقة' : 'Action: exact next move';
  String get focusSavePlan => isAr ? 'احفظ خطة اليوم' : "Save today's plan";
  String get focusPlanSaved =>
      isAr ? 'تم حفظ خطة التركيز لليوم.' : 'Focus plan saved for today.';
  String get focusTimerTitle => isAr ? 'مؤقت التركيز' : 'Focus timer';
  String get focusTimerSubtitle => isAr
      ? 'ابقَ في التطبيق بدلاً من التنقل.'
      : 'Stay inside Grow Daily instead of switching apps.';
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
  String get focusDeepWorkDone =>
      isAr ? 'أنجزت عملاً عميقاً' : 'Deep Work Done';
  String focusStayedFocused(String label) => isAr
      ? 'ركّزت لمدة $label. الجلسات الصغيرة تبني عقلاً قويًا.'
      : 'You stayed focused for $label. Small sessions build a strong mind.';
  String get focusGreatWork => isAr ? 'عمل رائع' : 'GREAT WORK';
  String get focusRitualTitle =>
      isAr ? 'طقوس اليوم النظيفة' : 'Clean daily ritual';
  String get focusRitualSubtitle => isAr
      ? 'صغيرة للتكرار، منظمة للعمل.'
      : 'Small enough to repeat, structured enough to work.';
  String get focusRitualPlanWin =>
      isAr ? 'خطط للانتصار الواحد' : 'Plan the one win';
  String get focusRitualChooseTask =>
      isAr ? 'اختر مهمتك الأهم' : 'Choose your top task';
  String get focusRitualRunSprint =>
      isAr ? 'قم بسبرنت تركيز' : 'Run a focus sprint';
  String focusRitualSprintsLogged(int n) => isAr
      ? '$n سبرنت مسجل اليوم'
      : '$n sprint${n == 1 ? '' : 's'} logged today';
  String get focusRitualReview =>
      isAr ? 'مراجعة وإغلاق الحلقة' : 'Review and close the loop';
  String get focusRitualReviewSubtitle => isAr
      ? 'سجّل ما نجح حتى يبدأ الغد أخف'
      : 'Mark what worked so tomorrow starts lighter';
  String get focusLogSprint =>
      isAr ? 'سجّل سبرنت 25 دقيقة' : 'Log 25-min sprint';
  String get focusResetToday => isAr ? 'إعادة اليوم' : 'Reset today';
  String get focusWhyTitle => isAr ? 'لماذا هذا موجود' : 'Why this is here';
  String get focusWhySubtitle => isAr
      ? 'مستوحى من أنماط مثبتة دون فوضى.'
      : 'Inspired by proven patterns in top planners without adding clutter.';
  String get focusIfThenCueTitle =>
      isAr ? 'إشارة إذا / سأفعل' : 'If / then cue';
  String get focusIfThenCueBody => isAr
      ? 'يحوّل الأهداف المبهمة إلى خطوة محددة بالمكان والوقت.'
      : 'Turns vague goals into a specific when-and-where action.';
  String get focusOneTaskTitle => isAr ? 'مهمة واحدة فقط' : 'One top task';
  String get focusOneTaskBody => isAr
      ? 'يتجنب التخطيط المفرط ويوضح الانتصار التالي.'
      : 'Avoids over-planning and makes the next win obvious.';
  String get focusSprintTitle =>
      isAr ? 'سبرنت تركيز قصير' : 'Short focus sprint';
  String get focusSprintBody => isAr
      ? 'حلقة خفيفة كما تستخدمها تطبيقات الإنتاجية الكبرى.'
      : 'A light Pomodoro-style loop like leading productivity apps use.';

  // ── Habit card ───────────────────────────────────────────────────────────
  String get habitDaily => isAr ? 'يومياً' : 'Daily';
  String habitWeeklyTimes(int n) => isAr ? '${n}x / أسبوع' : '${n}x / week';
  String habitAfterCue(String cue) =>
      isAr ? '  ·  بعد $cue' : '  ·  After $cue';
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
  String get habitOverLimitToday =>
      isAr ? 'تجاوزت الحد اليوم' : 'OVER LIMIT TODAY';

  // ── Goals Matrix ─────────────────────────────────────────────────────────
  String get goals => isAr ? 'الأهداف' : 'Goals';
  String get goalsMatrix => isAr ? 'مصفوفة الأهداف' : 'Goals Matrix';
  String get matrixSubtitle => isAr
      ? 'رتّب أهدافك لتحافظ على وضوح الأولويات.'
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
  String get matrixTapToAdd =>
      isAr ? 'اضغط في أي مكان للإضافة' : 'Tap anywhere to add a goal';
  String get matrixAddAnother => isAr ? '+ أضف مهمة أخرى' : '+ Add another';
  String get matrixAddTask => isAr ? 'أضف مهمة' : 'ADD TASK';
  String get matrixWhatToDo =>
      isAr ? 'ما الذي يجب فعله؟' : 'What needs to be done?';
  String get matrixMoveToQuadrant => isAr ? 'انقل إلى ربع' : 'MOVE TO QUADRANT';

  /// Names for the three icon buttons on every task row (see
  /// _TileIconButton). They had no names at all: a screen-reader user heard
  /// "button, button, button", and a sighted new user had no way to learn
  /// that the handle moves a task between quadrants — the owner's words were
  /// "it's easy for me, but a new user will not know where to click". Used as
  /// both the Semantics label and the long-press tooltip.
  ///
  /// Sentence case, not the SHOUTING of [matrixMoveToQuadrant]: that one is a
  /// section header inside the move sheet, this is a control's own name.
  String get taskMoveAction => isAr ? 'نقل المهمة' : 'Move task';
  String get taskFavAction => isAr ? 'تمييز بنجمة' : 'Star task';
  String get taskUnfavAction => isAr ? 'إزالة النجمة' : 'Unstar task';
  String get taskDetailsAction => isAr ? 'التفاصيل' : 'Details';
  // Tooltips for the header's expand icon (QuadrantCard) and the close
  // button on the near-fullscreen view it opens (QuadrantExpandedScreen).
  String get matrixExpandQuadrant => isAr ? 'توسيع' : 'Expand';
  String get matrixCollapseQuadrant => isAr ? 'إغلاق' : 'Close';
  String get matrixDeleteTask => isAr ? 'حذف المهمة' : 'Delete task';
  String get matrixDeleteSelected => isAr ? 'حذف المحدد' : 'Delete selected';
  String matrixSelectedCount(int count) =>
      isAr ? '$count محدد' : '$count selected';
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
  String get matrixNoDescription => isAr ? 'لا يوجد وصف' : 'No description yet';
  // ReminderRow (reminder_picker.dart), shared by AddTaskSheet's "Add
  // details" section and TaskDetailSheet — matrixReminderLabel is the
  // unset-state placeholder (once set, the row shows the picked moment
  // itself instead, via formatReminderMoment, not a fixed string).
  String get matrixReminderLabel => isAr ? 'تعيين تذكير' : 'Set a reminder';
  String get matrixReminderPast => isAr
      ? 'اختر وقتًا في المستقبل'
      : 'Pick a time that hasn\'t already passed';
  // ReminderList's add row (reminder_picker.dart). Same label whether the
  // row is unlocked or showing the Premium lock — what changes is the icon
  // and colour, not the wording, so a free user reads what the feature
  // actually is before the upsell rather than being told "Premium" twice.
  String get matrixReminderAddAnother =>
      isAr ? 'إضافة تذكير آخر' : 'Add another reminder';
  // Screen-reader label for the × on a reminder row. Never rendered as
  // text — the button is icon-only, so without this a screen reader
  // announces nothing but the row's time twice over.
  String get matrixReminderRemove => isAr ? 'إزالة التذكير' : 'Remove reminder';
  // Why a dimmed offset chip didn't take. Distinct from
  // matrixReminderPast, which is about the anchor the user is picking; this
  // one is about a *derived* moment that has already gone by — "an hour
  // before" something twenty minutes away. Shown inline under the grid,
  // never as a SnackBar: this section lives inside a modal sheet, and the
  // ScaffoldMessenger is behind it.
  String get matrixReminderOffsetPast => isAr
      ? 'هذا التذكير مضى وقته بالفعل'
      : 'That reminder time has already passed';
  // ReminderPicker's offset section. "Extra" matters: the row above it is
  // already a reminder, so without that word the chips read as replacing
  // it rather than adding to it. The hint says outright that several can
  // be picked — every other chip grid in this app is single-choice, so a
  // multi-select one needs telling.
  String get matrixExtraRemindersSection =>
      isAr ? 'تذكيرات إضافية' : 'Extra reminders';
  String get matrixExtraRemindersHint => isAr
      ? 'اختر واحدًا أو أكثر — يمكنك إضافة أكثر من تذكير'
      : 'Pick one or more — you can add several';
  // The custom-offset sheet (custom_offset_sheet.dart), opened from the
  // "مخصص" cell of the offset grid. Lives in a sheet rather than inline so
  // the number, its unit, and the list of what's already added each get
  // room, without the grid growing a third control.
  String get customReminderTitle => isAr ? 'تذكير مخصص' : 'Custom reminder';
  String get customReminderValueHint => isAr ? 'الرقم' : 'Number';
  String get customReminderAdd => isAr ? 'إضافة' : 'Add';
  // Heading over the list of everything currently set, each row removable.
  String get customReminderAdded =>
      isAr ? 'التذكيرات المضافة' : 'Added reminders';
  String get customReminderEmpty =>
      isAr ? 'لم تضف أي تذكير بعد' : 'No extra reminders yet';
  String get customReminderAlreadyAdded =>
      isAr ? 'هذا التذكير مضاف بالفعل' : 'That reminder is already added';
  // Unit selector. Plural forms, since the selector names the unit rather
  // than counting anything — the counted forms are built separately (see
  // formatOffsetVerbose), where Arabic needs singular/dual/plural.
  String get unitMinutes => isAr ? 'دقائق' : 'Minutes';
  String get unitHours => isAr ? 'ساعات' : 'Hours';
  String get unitDays => isAr ? 'أيام' : 'Days';
  // Shown when a task already has its full stack of OS-schedulable
  // reminders (NotificationService.kMaxTaskReminderSlots) — a platform
  // ceiling that applies to Premium too, so this is deliberately worded as
  // a limit, not an upsell.
  String get matrixReminderMaxReached => isAr
      ? 'وصلت إلى الحد الأقصى من التذكيرات لهذه المهمة'
      : 'That\'s the most reminders one task can have';
  // The Premium gate for stacking reminders (reminder_limit_gate.dart).
  // Leads with what the feature does — staggered nudges before something
  // that matters — rather than with the cap it lifts.
  String get reminderGateTitle =>
      isAr ? 'تذكيرات متعددة' : 'Stack your reminders';
  String get reminderGateBody => isAr
      ? 'أضف أكثر من تذكير لنفس المهمة — نبّهك الساعة 3:00 و3:30 و4:00 قبل اجتماع الساعة 5. المجاني يتيح تذكيرًا واحدًا لكل مهمة.'
      : 'Add as many reminders to one task as you need — nudged at 3:00, 3:30 and 4:00 before a 5pm meeting. Free includes one reminder per task.';
  String get matrixDone => isAr ? 'تم' : 'Done';
  String get matrixUndo => isAr ? 'تراجع' : 'Undo';

  /// The same word, reused by Grid's habit-delete Undo. Kept as its own
  /// getter rather than borrowing matrixUndo so a future Matrix-specific
  /// rewording can't silently change what the Grid's button says.
  String get undo => isAr ? 'تراجع' : 'Undo';
  // Named, not generic - "'Buy groceries' deleted" tells you which task
  // just disappeared (useful right before the Undo action expires),
  // matching matrixTasksDeleted's own count below for the multi-select case.
  String matrixTaskDeleted(String taskTitle) =>
      isAr ? 'تم حذف "$taskTitle"' : '"$taskTitle" deleted';
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
  String get matrixEditQuadrantTitle => isAr ? 'تعديل الربع' : 'Edit quadrant';
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
  // Was 'مملوك', which is the word used for a possessed person. 'لديك'
  // is the ordinary register for "you have this".
  String get closetOwned => isAr ? 'لديك' : 'Owned';
  String get closetEquipped => isAr ? 'مرتدى' : 'Equipped';
  String get closetEquip => isAr ? 'ارتداء' : 'Equip';
  String get closetUnequip => isAr ? 'خلع' : 'Remove';
  String get closetBuy => isAr ? 'شراء' : 'Buy';
  String get closetBuyConfirmTitle =>
      isAr ? 'شراء هذه القطعة؟' : 'Buy this item?';
  String closetBuyConfirmBody(int cost) => isAr
      ? 'أنفق $cost ذهب لفتحها للأبد.'
      : 'Spend $cost gold to unlock this forever.';
  String get closetNotEnoughGold => isAr ? 'الذهب غير كافٍ' : 'Not enough gold';
  String get closetPurchaseFailed => isAr
      ? 'تعذّر إتمام الشراء — حاول مرة أخرى'
      : "Couldn't complete the purchase — try again";
  String get closetPurchased => isAr ? 'تم الفتح!' : 'Unlocked!';
  String get closetCancel => isAr ? 'إلغاء' : 'Cancel';

  // ── Closet: the three bands the grid is grouped into ──────────
  //
  // Grouping replaced a row of filter chips. The chips made the user
  // operate the screen to learn what they had; three titled bands answer
  // "what do I have / what can I get / what am I working toward" by
  // scrolling, with no taps at all. An empty band is not rendered.
  String get closetBandOwned => isAr ? 'لديك' : 'Yours';
  String get closetBandReach => isAr ? 'بمتناولك' : 'Within reach';
  String get closetBandGoal => isAr ? 'بالتقدّم' : 'Earned with progress';

  /// Why a character is locked at all: progress, never gold.
  String get closetCharacterEarned => isAr
      ? 'المظاهر تُكتسب، ما تُشترى.'
      : 'Looks are earned with progress, not gold.';

  /// Shown when someone taps a character they have not reached yet.
  /// Names what opens it rather than just refusing.
  String closetCharacterLocked(String requirement) =>
      isAr ? '$requirement يفتح هذا المظهر' : 'Unlocked at $requirement';

  String get closetNoAccessory => isAr ? 'بدون قطعة' : 'Nothing worn';

  /// Shown on a locked item's button. Deliberately states the rule rather
  /// than the shortfall: the point of a requirement is that no amount of
  /// gold substitutes for it.
  String get closetUnlockedByProgress =>
      isAr ? 'تُفتح بالتقدّم، لا بالذهب' : 'Unlocked by progress, not gold';

  String closetShortBy(int amount) =>
      isAr ? 'ينقصك $amount' : '$amount short';

  String closetBalanceIs(int gold) =>
      isAr ? 'رصيدك $gold ذهبًا' : 'You have $gold gold';

  String closetBalanceAfter(int gold) =>
      isAr ? 'يتبقى لك $gold ذهبًا' : '$gold left after this';

  String closetBalanceOf(int gold, int cost) =>
      isAr ? 'رصيدك $gold من $cost' : '$gold of $cost';

  /// "12 من 20", never "12 / 20". A slash is bidi-neutral, so in an RTL
  /// paragraph the two numbers around it swap and the label reads as its
  /// own inverse: 12 of 20 renders as "20 / 12". The word من is a strong
  /// RTL character and pins the order. Same pattern as streakFreezeStatus.
  String closetProgress(int have, int total) =>
      isAr ? '$have من $total' : '$have / $total';

  String closetPriceLater(int cost) =>
      isAr ? 'ثمنها بعد ذلك $cost ذهبًا' : 'Then it costs $cost gold';

  /// The payoff nobody is told about today: room leaderboards already
  /// render every member's equipped accessory.
  String get closetSeenByRooms =>
      isAr ? 'هكذا يراك أعضاء غرفك' : 'This is how your rooms see you';

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

  // GetStartedChecklistCard (Grid + Matrix, disappears once both are done —
  // see that widget's own doc comment for why this replaces leaning on the
  // spotlight/slide-tour alone to teach this). "Habit"/"Task" match navGrid/
  // navMatrix's own wording on purpose, not "Grid"/"Goal" — the checklist
  // is about the real-world thing being added, not the screen it lives on.
  String get getStartedTitle => isAr ? 'ابدأ الآن' : 'Get Started';

  /// "Step 2 of 4" on the Grid's guide card — a visible end so the guide
  /// reads as something you finish, not an open-ended chore list.
  ///
  /// The word "Step" is load-bearing and used to be missing: the card is
  /// called with `progress.done + 1`, so a brand-new user with nothing done
  /// saw a bare "1 of 4" sitting directly beside an *empty* checkbox. Read
  /// as a progress count — which is what a bare "N of M" beside a checkbox
  /// looks like — the card was claiming a step was finished when none was.
  /// "Step 1 of 4" says the same thing the number always meant.
  String guideStepCount(int step, int total) =>
      isAr ? 'الخطوة $step من $total' : 'Step $step of $total';

  String get getStartedAddHabit =>
      isAr ? 'أضف أول عادة لك' : 'Add your first habit';
  String get getStartedAddTask =>
      isAr ? 'أضف أول مهمة لك' : 'Add your first task';

  // Dismiss label on App Guide's coach-marks (CoachMarkOverlay). The four
  // habit/task spotlight strings that used to sit here went with the
  // first-run spotlight overlay itself — they duplicated the Get Started
  // checklist's own rows word for word.
  String get coachMarkSkip => isAr ? 'تخطّي' : 'Skip';

  // ── Victory Grid ─────────────────────────────────────────────────────────
  String get gridTitle => isAr ? 'شبكة الانتصارات' : 'Victory Grid';
  String get gridSlogan => isAr
      ? 'لوّن حياتك، مربّعًا كل يوم.'
      : 'Color your life, one square at a time.';
  String get gridThisWeek => isAr ? 'هذا الأسبوع' : 'This week';
  // "Green squares" used to be literal — every preset's completed square
  // was some shade of green. Some presets now use their own signature
  // color instead (see ThemePreset's class doc comment), so this and the
  // other grid/heatmap/night-review labels below stay color-neutral
  // rather than naming a color that isn't true for every theme.
  String get gridGreenSquares => isAr ? 'مربّعات ملوّنة' : 'Squares filled';

  /// [gridGreenSquares] agreed with its own number.
  ///
  /// The summary card prints a large count and this label beside it, and the
  /// label was a fixed plural — so a user who had coloured exactly one square
  /// read «1 مربّعات ملوّنة», plural agreement on the number one, on the app's
  /// main screen. Arabic counts do not work like English ones: 1 takes the
  /// singular, 2 the dual, 3–10 the plural, and 11+ the accusative singular.
  ///
  /// The 11+ form uses مربّعًا, which is the same word this file already uses
  /// in [gridEarnedToday] («كسبت $n مربّعًا اليوم») — so nothing here invents
  /// vocabulary, it only picks between forms of a word already chosen.
  /// English is unchanged: "Squares filled" reads correctly at every count.
  String gridGreenSquaresCount(int n) {
    if (!isAr) return gridGreenSquares;
    if (n == 1) return 'مربّع ملوّن';
    if (n == 2) return 'مربّعان ملوّنان';
    // 0 takes the same plural as 3–10. Without it, zero matched no branch and
    // fell through to the 11+ form below, so an untouched week — the first
    // thing a new user sees — read «0 مربّعًا ملوّنًا».
    if (n == 0 || (n >= 3 && n <= 10)) return 'مربّعات ملوّنة';
    return 'مربّعًا ملوّنًا';
  }

  /// The two small stats under the week's square count. Both are about
  /// TODAY while the big number above them is the whole week, which is
  /// what made them ambiguous - and "Points" named a currency this app
  /// does not have. It is XP: the profile header says «مجموع XP», the task
  /// reward float says «+20 XP», and the level bar is measured in it.
  /// Naming it here is cheaper than explaining it anywhere.
  String get gridPoints => isAr ? 'XP اليوم' : 'XP today';
  String get gridComplete => isAr ? 'إنجاز اليوم' : 'Today done';
  String get gridWeekFilled => isAr ? 'اكتمل الأسبوع!' : 'Week filled!';
  String get gridPerfectDay => isAr
      ? 'يوم مثالي — كل مربّعات اليوم ملوّنة!'
      : 'Perfect day — every square is filled!';
  String gridGreensToday(int n) =>
      isAr ? 'كسبت $n مربّعًا اليوم' : 'You earned $n squares today';
  String get gridTapHint => isAr
      ? 'اضغط لتلوين المربّع · اضغط مطولاً للمزيد من الألوان'
      : 'Tap to color · long-press for more colors';
  String get gridRewardHint => isAr
      ? 'اليوم فقط يمنحك نقاط الخبرة والذهب، ويزيد سلسلتك مرة واحدة يوميًا كحد أقصى.'
      : 'Only today earns XP, gold, and streak credit — once per day at most.';
  String get gridPastDayHint => isAr
      ? 'تعديل يوم سابق: يُحدّث سجلّك المرئي فقط، دون مكافآت.'
      : 'Editing a past day updates your visual record only — no rewards.';
  // Distinct from gridPastDayHint on purpose: shown for the real calendar
  // day during the 6-hour window right after midnight, which isn't a past
  // day at all (it just isn't the official rewarded day yet) — see
  // DateTimeGameExt.isRealToday/isToday's doc comments.
  String get gridNotYetActiveHint => isAr
      ? 'لم يصبح هذا اليوم رسميًا بعد: يمكنك تلوينه، لكن دون مكافآت حتى الساعة 6 صباحًا.'
      : "This day isn't official yet — you can color it in, but no rewards until 6 AM.";
  String get gridEmptyTitle =>
      isAr ? 'لا توجد عادات بعد' : 'No habits to track yet';
  // Points at the literal button just below it ("Browse Plans" / "استعرض
  // الخطط") rather than the old "Today" tab, which the bottom nav retired
  // when Grid became the app's home screen (see GameNavBar's doc comment) —
  // this used to send brand-new users looking for a tab that no longer
  // exists, on the very first real screen they land on.
  String get gridEmptyDesc => isAr
      ? 'اضغط "استعرض الخطط" تحت عشان تضيف أول عادة وتبدأ تلوّن أسبوعك.'
      : 'Tap Browse Plans below to add your first habit and start coloring your week.';
  String get gridEditSquare => isAr ? 'حدّد المربّع' : 'Set this square';

  /// What the CHOSEN square actually does, shown under the palette and
  /// changing as the choice changes.
  ///
  /// The six squares are the one part of this app that cannot be understood
  /// by looking at it. Three of them mean some version of "not done", and
  /// nothing on screen said how they differ, so the honest question a person
  /// arrives with, "what is the difference between تخطّي and فشل and just
  /// leaving it empty", had no answer anywhere in the product.
  ///
  /// These lines answer it in terms of CONSEQUENCE, not definition. Nobody
  /// needs to be told that تخطّي means skipped. What they need to know is
  /// that it will not be counted against them, and that فشل will.
  String squareStateEffect(SquareState state) => switch (state) {
        SquareState.complete =>
          isAr ? 'يُحتسب يومًا كاملًا.' : 'Counts as a full day.',
        SquareState.bonus => isAr
            ? 'أكثر من المطلوب، ويُحتسب يومًا كاملًا.'
            : 'More than asked, and counts as a full day.',
        SquareState.partial =>
          isAr ? 'يُحتسب نصف يوم.' : 'Counts as half a day.',
        SquareState.skipped => isAr
            ? 'راحة باختيارك. لا تُحسب عليك.'
            : 'A rest you chose. It is not counted against you.',
        SquareState.failed => isAr
            ? 'تُحسب عليك، وتُحفظ في ملاحظات العادات.'
            : 'Counted against you, and kept in Habit Notes.',
        SquareState.none => isAr
            ? 'لا شيء مسجّل. تُحسب عليك إذا كان اليوم مطلوبًا.'
            : 'Nothing recorded. Counted against you if the day was due.',
      };
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
  String get gridJournalSearchHint =>
      isAr ? 'ابحث في العادات أو الملاحظات' : 'Search habits or notes';
  // Shown instead of gridJournalEmpty when a search/filter is active but
  // matches nothing — distinguishes "nothing here yet" from "nothing
  // matches what you typed," since this month may well have real entries
  // that a narrow filter or search term is just hiding right now.
  String get gridJournalNoResults => isAr
      ? 'لا توجد نتائج مطابقة — جرّب بحثًا أو فلترًا مختلفًا'
      : 'No matches — try a different search or filter';
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
      ? 'كل مربّع يومٌ، وكلما ارتفع اللون فيه زاد ما أنجزته. اليوم الممتلئ يضيء.'
      : 'Your completion density across months — every square is a day, every shade is how much you colored it.';
  String get heatmapTotalGreen => isAr ? 'مربّعات ملوّنة' : 'Squares filled';
  String get heatmapActiveDays => isAr ? 'أيام نشطة' : 'Active days';
  String get heatmapBestDay => isAr ? 'أفضل يوم' : 'Best day';
  String get heatmapLess => isAr ? 'أقل' : 'Less';
  String get heatmapMore => isAr ? 'أكثر' : 'More';
  String get gridSectionBuild => isAr ? 'عادات البناء' : 'Build habits';
  String get gridSectionQuit => isAr ? 'الإقلاع والتقليل' : 'Quit & reduce';
  String gridFullRow(String name) => isAr
      ? 'صف كامل! أسبوع $name كله أخضر.'
      : 'Full row! A whole green week of $name.';
  String get perfectDayMsg => isAr
      ? 'يوم كامل! كل عاداتك خضرا اليوم.'
      : 'Perfect day! Every habit green today.';
  // ── Weekly recap (Friday card on the Grid) ────────────────────────────────
  String get weeklyRecapTitle => isAr ? 'حصاد الأسبوع' : 'Weekly recap';
  String get weeklyRecapThisWeek => isAr ? 'هالأسبوع' : 'This week';
  String get weeklyRecapLastWeek => isAr ? 'الأسبوع اللي طاف' : 'Last week';
  String weeklyRecapNeedsLove(String name) =>
      isAr ? 'يبيلها شوية اهتمام: $name' : 'Needs a little love: $name';
  String get weeklyRecapUp => isAr
      ? 'أقوى من الأسبوع اللي طاف. استمر.'
      : 'Stronger than last week. Keep it going.';
  String get weeklyRecapSame => isAr
      ? 'ثابت على مستواك، والثبات ذهب.'
      : 'Steady as last week. Consistency is gold.';
  String get weeklyRecapDown => isAr
      ? 'أسبوع أهدى من اللي قبله. الجاي لك.'
      : 'A quieter week. The next one is yours.';
  String get weeklyRecapFirst => isAr
      ? 'أول أسبوع مسجل لك. بداية حلوة.'
      : 'Your first recorded week. A sweet start.';
  String get weeklyRecapPerHabit =>
      isAr ? 'عاداتك هالأسبوع' : 'Your habits this week';
  String get weeklyRecapTrend => isAr ? 'آخر 4 أسابيع' : 'Last 4 weeks';
  String get weeklyRecapPremiumTeaser => isAr
      ? 'تفاصيل أعمق لكل عادة، مع Premium'
      : 'Deeper per-habit detail, with Premium';
  // ── Habit Insights (Premium) ──────────────────────────────────────────────
  String get insightsTitle => isAr ? 'رؤى العادات' : 'Habit Insights';
  String get insightsWindow => isAr ? 'آخر 8 أسابيع' : 'Last 8 weeks';

  /// Header over the per-habit completion-rate list, which had none — the
  /// bars appeared straight after the headline cards with nothing saying
  /// what "18 / 28" was counting.
  String get insightsPerHabitTitle =>
      isAr ? 'نسبة الإكمال لكل عادة' : 'Completion rate per habit';
  // Habit names are quoted ("$habit") to set them visually apart from the
  // surrounding sentence — easier to scan a list of these at a glance.
  //
  // Impersonal and unpunctuated, matching the achievements and progress
  // chrome. These render as a stack of six or seven cards, so they're
  // labels rather than prose: a full stop after three words reads as
  // machine translation in Arabic, and "أقوى أيامك"/"تفوتك" made the same
  // screen address the reader while the card above it stated a fact. The
  // *tips* in the detail sheet below stay second-person imperative on
  // purpose — those are advice, which is a different thing from a stat.
  String insightWeekdayMiss(String habit, String weekday) => isAr
      ? '"$habit" تنقطع أكثر يوم $weekday'
      : '"$habit" slips most on ${weekday}s';
  String insightStrongestDay(String weekday) =>
      isAr ? 'أقوى يوم: $weekday' : 'Strongest day: $weekday';
  String insightMostConsistent(String habit) =>
      isAr ? 'أثبت عادة: "$habit"' : 'Most consistent habit: "$habit"';
  String insightNeedsPush(String habit) =>
      isAr ? 'تحتاج دفعة: "$habit"' : 'Needs a push: "$habit"';
  String get insightsEmpty => isAr
      ? 'كمّل أسبوعين على الأقل وبتشوف أنماطك هني.'
      : 'Track a couple of weeks and your patterns will show up here.';
  String get insightsPremiumTitle =>
      isAr ? 'الرؤى ميزة Premium' : 'Insights is a Premium feature';
  String get insightsPremiumBody => isAr
      ? 'أنماطك الشخصية: أي عادة تفوتك، وأي يوم تضعف فيه، وأي وحدة أثبت. كلها من سجلك أنت.'
      : 'Your personal patterns: which habit slips, which day is weakest, which one holds strong. All from your own record.';
  // The free-tier teaser under the one real (unlocked) habit row — see
  // InsightsScreen's doc comment on why this replaced the old all-or-
  // nothing gate.
  String get insightsBreakdownTeaser => isAr
      ? 'شوف تفاصيل كل عاداتك، مع Premium'
      : 'See the full breakdown for every habit, with Premium';
  // ── Habit Insights detail sheet (tap any headline card) ────────────────────
  String insightDetailRate(int completed, int scheduled) =>
      isAr ? '$completed من $scheduled يوم' : '$completed of $scheduled days';
  String get insightDetailByDay =>
      isAr ? 'حسب أيام الأسبوع' : 'By day of the week';
  String get insightDetailCompare =>
      isAr ? 'بالمقارنة مع عاداتك الأخرى' : 'Compared to your other habits';
  String get insightTipMostConsistent => isAr
      ? 'عادتك الأقوى — كمّل عليها.'
      : 'Your strongest habit. Keep the streak going.';
  String get insightTipNeedsPush => isAr
      ? 'تركيز بسيط هنا ممكن يفرق كثير.'
      : 'A little extra focus here could make a real difference.';
  String insightTipWeekdayMiss(String weekday) => isAr
      ? 'جرّب تذكيرًا ليوم $weekday.'
      : 'Try setting a reminder for $weekday.';
  String get insightTipStrongestDay => isAr
      ? 'يوم ممتاز لتضيف عليه شيء جديد.'
      : 'A great day to build something new on top.';
  // The concrete date range behind "last 8 weeks" — shown once at the top
  // of the detail sheet since, several taps deep in a modal, "last 8
  // weeks" alone doesn't say *which* 8 weeks.
  String insightWindowWithDates(String start, String end) =>
      isAr ? 'آخر 8 أسابيع · $start – $end' : 'Last 8 weeks · $start – $end';
  // "Most consistent" / "needs a push" are inherently habit-vs-habit
  // claims, not day-vs-day ones — these compare the named habit against
  // the next-nearest one instead of forcing it through a weekday lens
  // that doesn't answer "why this habit."
  String insightPerfectRecord(int n) => isAr
      ? 'ما فوّتّ ولا يوم — $n من $n.'
      : 'You didn\'t miss a single day — $n for $n.';
  String insightMostConsistentCompare(String habit, int points) => isAr
      ? 'متقدم بـ$points نقطة عن أقرب عادة لك، "$habit".'
      : '$points points ahead of your next closest habit, "$habit".';
  String insightNeedsPushCompare(String habit, int points) => isAr
      ? 'أقل بـ$points نقطة من أثبت عاداتك، "$habit".'
      : '$points points behind your most consistent habit, "$habit".';
  String get insightOnlyHabitTracked => isAr
      ? 'عادتك الوحيدة اللي عندها بيانات كافية لين الحين.'
      : 'Your only habit with enough data to compare yet.';
  String get historyLockedCta => isAr ? 'افتح' : 'Unlock';
  // ── Rooms lifecycle (lobby, start, finale) ────────────────────────────────
  String get roomLobbyPill => isAr ? 'في الانتظار' : 'Lobby';
  String get roomStartsTomorrowPill => isAr ? 'يبدأ بكرة' : 'Starts tomorrow';
  String roomLobbyBanner(int count) => isAr
      ? 'الغرفة جاهزة و$count منضمين. القائد يحدد وقت البداية.'
      : 'The room is ready with $count in. The leader picks when it begins.';
  String get roomLobbyLeaderHint => isAr
      ? 'اختر وقت البداية تحت. الكل بيشوف نفس العد التنازلي، ويبدأ التحدي فور ما يوصل الصفر.'
      : 'Pick a start time below. Everyone sees the same countdown, and it kicks off the moment it hits zero.';
  // Leader-only: opens _ScheduleStartSheet for the first-ever pick — see
  // _EmptyLobbyCard.
  String get roomPickStartTimeAction =>
      isAr ? 'اختر وقت البداية' : 'Choose a start time';
  String get roomWaitingForLeaderSchedule => isAr
      ? 'بانتظار القائد يحدد وقت البداية'
      : 'Waiting for the leader to pick a start time';
  // _ScheduleStartSheet — quick chips + one custom escape hatch, same shape
  // as _ExtendRoomSheet's own length picker.
  String get roomScheduleTitle =>
      isAr ? 'متى يبدأ التحدي؟' : 'When should it start?';
  String get roomScheduleBody => isAr
      ? 'الكل بيشوف عد تنازلي حي لهذا الوقت. تقدر تغيّره وقتما تبي قبل ما يحين.'
      : 'Everyone sees a live countdown to this moment. Change it anytime before it fires.';
  String get roomScheduleQuick1Hour => isAr ? 'بعد ساعة' : 'In 1 hour';
  String get roomScheduleTomorrowMorning =>
      isAr ? 'بكرة الصبح' : 'Tomorrow morning';
  String get roomScheduleTomorrowEvening =>
      isAr ? 'بكرة المساء' : 'Tomorrow evening';
  String get roomScheduleCustomAction =>
      isAr ? 'اختر تاريخ ووقت مخصص' : 'Pick a custom date & time';
  String get roomScheduleNotFuture => isAr
      ? 'اختر وقتًا في المستقبل'
      : "Pick a time that hasn't already passed";
  // _ScheduledLobbyCard's live countdown — roomCountdownDaysLabel/
  // HoursLabel/MinLabel/SecLabel are fixed captions under each digit box
  // (like a digital timer's "HRS/MIN/SEC"), never pluralized against the
  // number above them.
  String get roomCountdownTitle => isAr ? 'يبدأ خلال' : 'Starts in';
  String roomCountdownAt(String when) => isAr ? 'يبدأ $when' : 'Starts $when';
  String get roomCountdownDaysLabel => isAr ? 'أيام' : 'Days';
  String get roomCountdownHoursLabel => isAr ? 'ساعات' : 'Hours';
  String get roomCountdownMinLabel => isAr ? 'دقائق' : 'Min';
  String get roomCountdownSecLabel => isAr ? 'ثواني' : 'Sec';
  String get roomChangeTimeAction => isAr ? 'غيّر الوقت' : 'Change time';
  // Leader-only override that skips the wait — see _confirmStartNow, which
  // reuses roomStartConfirmTitle/roomStartConfirmBody/roomStartAction
  // below for the actual confirm dialog.
  String get roomStartNowAction => isAr ? 'ابدأ الآن' : 'Start now';
  // RoomsHubScreen's list pill, once a lobby has a picked start time — see
  // formatCompactRemaining (rooms_notifier.dart) for the "2h 15m" part.
  String roomStartsInCompact(String compact) =>
      isAr ? 'يبدأ خلال $compact' : 'Starts in $compact';
  String get roomStartAction => isAr ? 'ابدأ التحدي' : 'Start the challenge';
  String get roomStartConfirmTitle =>
      isAr ? 'نبدأ التحدي؟' : 'Start the challenge?';
  String get roomStartConfirmBody => isAr
      ? 'أول يوم يبدأ الآن، للجميع، وما ينرجع عنها.'
      : 'Day one starts right now, for everyone, and this cannot be undone.';
  String get roomStartsTomorrowBanner => isAr
      ? 'التحدي يبدأ بكرة الصبح. جهز نفسك، وكل إنجاز له ضعف النقاط والذهب.'
      : 'The challenge starts tomorrow morning. Get ready, every completion pays double XP and gold.';
  String get roomEndedTitle => isAr ? 'انتهى التحدي' : 'Challenge complete';
  String get roomEndedBody => isAr
      ? 'ما قصرتوا. هذي النتيجة النهائية.'
      : 'Well done, all of you. Here is the final result.';
  String get notifLocationResolving =>
      isAr ? 'جاري التعرف على موقعك…' : 'Finding your location…';
  String get notifLocationSetGeneric =>
      isAr ? 'تم تحديد الموقع' : 'Location set';
  String get roomBoostHint => isAr
      ? 'عادات هذي الغرفة تدفع 2x نقاط وذهب وهي شغالة'
      : 'This room\'s habits pay 2x XP and gold while it runs';
  String get historyLockedBody => isAr
      ? 'الحساب المجاني يرجع 3 أشهر. Premium يفتح سجلك كامل، من أول يوم.'
      : 'Free goes back 3 months. Premium opens your whole history, from day one.';
  // ── History demo gate (shared: every locked-history surface) ─────────
  //
  // Wording note: the sheet SHOWS a fake perfect month stamped مثال, so
  // these strings never need to explain what history looks like — the
  // preview does that. They only name the thing and invite.
  String get demoGateExample => isAr ? 'مثال' : 'EXAMPLE';
  String get demoGateMonthTitle =>
      isAr ? 'شهر من سجلّك' : 'A month of your history';
  String get demoGatePerfectStamp => isAr ? 'شهر كامل' : 'PERFECT MONTH';
  String get demoGateCta =>
      isAr ? 'افتح سجلّك الكامل' : 'Unlock your full history';
  String get demoGateNotNow => isAr ? 'ليس الآن' : 'Not now';

  String get heatmapDayEmpty =>
      isAr ? 'ما في نشاط مسجل هاليوم' : 'Nothing recorded on this day';
  String get heatmapUpgradeTitle =>
      isAr ? 'افتح سجلّك الكامل' : 'Unlock your full history';
  String heatmapUpgradeBody(int freeMonths) => isAr
      ? 'الحساب المجاني يعرض آخر $freeMonths أشهر. Grow Daily Premium يفتح خريطتك كاملة، من أول يوم.'
      : 'Free shows your last $freeMonths months. Premium unlocks your whole map, from day one.';

  // ── Night Review ─────────────────────────────────────────────────────────
  String get nightReviewTitle => isAr ? 'مراجعة الليل' : 'Night Review';
  // Calendar of past mood/reflection check-ins — reused as both the
  // AppBar action's tooltip on NightReviewScreen and the destination
  // screen's own title, same pattern as heatmapTitle.
  String get nightReviewHistoryTitle =>
      isAr ? 'سجل المراجعات' : 'Review history';
  String get nightReviewHistoryEmpty =>
      isAr ? 'لا توجد مراجعات محفوظة هذا الشهر' : 'No reviews saved this month';
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
  String get nightReviewHabitsDoneLabel => isAr ? 'عادات اليوم' : 'Habits done';
  String get nightReviewTasksDoneLabel => isAr ? 'مهام منجزة' : 'Tasks done';
  String get nightReviewGreenSquares =>
      isAr ? 'مربّعات ملوّنة' : 'Squares filled';
  String get nightReviewStreak => isAr ? 'السلسلة' : 'Streak';
  String get nightReviewSave => isAr ? 'حفظ المراجعة' : 'Save review';
  String get nightReviewSaved =>
      isAr ? 'تم حفظ مراجعتك الليلية' : 'Night review saved';
  String get nightReviewDoneBadge => isAr ? 'تمت المراجعة' : 'Reviewed';
  String get nightReviewEditedHint => isAr
      ? 'يمكنك تعديل مراجعتك في أي وقت الليلة'
      : 'You can edit tonight\'s review anytime';

  // ── Premium ──────────────────────────────────────────────────────────────
  String get premiumTitle => isAr ? 'بريميوم' : 'Grow Daily Premium';
  String get premiumHeadline => isAr
      ? 'املأ حياتك بالألوان، بلا حدود'
      : 'Fill your life with color, without limits';
  String get premiumSubhead => isAr
      ? 'كل ما يقدّمه Grow Daily، بلا حدود.'
      : 'Everything Grow Daily has to offer, without the limits.';
  // This whole block was rewritten short and warm per user feedback that
  // the previous (accurate but spec-sheet-like) two-clause descriptions
  // read as "a lot of details." Every line below still maps to the exact
  // same real, currently-enforced gate as before — only the wording
  // changed, not the underlying claim.
  String get premiumBenefitHabitsTitle =>
      isAr ? 'عادات غير محدودة' : 'Unlimited habits';
  // Real gate: kFreeHabitLimit (10) in custom_habits_notifier.dart.
  String get premiumBenefitHabitsDesc => isAr
      ? 'ابنِ كل عادة تهمّك، بلا أي قيود.'
      : 'Build every habit you care about, with nothing holding you back.';
  String get premiumBenefitHistoryTitle =>
      isAr ? 'سجلّك الكامل' : 'Your full history';
  // Real gate: canBrowseHistoryMonth (premium_notifier.dart), kFreeHistoryMonths
  // (3), enforced identically on the Monthly Heatmap, Grid Journal, and Night
  // Review History screens. Dropped the old screen-by-screen list
  // (heatmap/journal/reflections) — accurate, but read like a feature spec.
  String get premiumBenefitHistoryDesc => isAr
      ? 'رحلتك كاملة منذ أول يوم، دائمًا بين يديك.'
      : 'Every day since you started, always within reach.';
  String get premiumBenefitInsightsTitle =>
      isAr ? 'الصورة الكاملة' : 'The complete picture';
  // Real gate: Insights (insights_screen.dart) shows free accounts only
  // their single strongest habit; Premium shows every habit. Weekly Recap
  // (weekly_recap_card.dart) adds a 4-week trend on top — still true, just
  // no longer spelled out here for length.
  String get premiumBenefitInsightsDesc => isAr
      ? 'صورة كاملة عن كل عادة تبنيها.'
      : 'A complete view of every habit you\'re building.';
  // Renamed from premiumBenefitThemes* — this bullet now covers appearance
  // broadly (themes today, character looks on the way) rather than just
  // themes, per user request to fold a premium-characters mention into
  // this bullet instead of giving it its own.
  String get premiumBenefitAppearanceTitle =>
      isAr ? 'لمستك الخاصة' : 'Make it yours';
  // Themes half is a real, live gate: ThemePresets.all (theme_preset.dart),
  // 9 of 11 presets premium-only, enforced in profile_screen.dart.
  //
  // The "character looks coming soon" clause this bullet used to carry —
  // added at the user's direction — was removed for the App Store
  // submission: character gating is not built (CharacterOption has no
  // isPremium field), and a paywall bullet selling an unbuilt feature is
  // exactly what Guideline 2.3.1 is aimed at, on the one screen a reviewer
  // reads line by line. Re-adding it after the feature ships is one line
  // here; re-submitting after a rejection is a review cycle.
  String get premiumBenefitAppearanceDesc => isAr
      ? '9 سمات حصرية لإعادة تصميم التطبيق بالكامل.'
      : '9 exclusive themes to restyle the whole app.';
  // Real gate: kFreeTaskReminders = 1 (premium_notifier.dart), enforced by
  // ReminderPicker.canStack via showReminderLimitGate. This was the Tasks
  // page's main cap and the paywall never mentioned it — a free user first
  // learned the feature existed by hitting its wall.
  String get premiumBenefitTaskRemindersTitle =>
      isAr ? 'تذكيرات متعددة للمهمة' : 'Stacked task reminders';
  String get premiumBenefitTaskRemindersDesc => isAr
      ? 'سلسلة تنبيهات للمهمة الواحدة — قبلها بيوم، بساعة، وعند موعدها.'
      : 'A ladder of nudges per task — a day out, an hour out, and on time.';
  String get premiumBenefitVoiceTitle => isAr ? 'ملاحظات صوتية' : 'Voice notes';
  // Real gate: hasVoiceNoteAccess (voice_note_gate.dart), flat premium-only
  // check, no free tier.
  String get premiumBenefitVoiceDesc => isAr
      ? 'سجّل تأملاتك بصوتك. لا حاجة للكتابة.'
      : 'Speak your reflections. No typing required.';
  String get premiumBenefitSupportTitle =>
      isAr ? 'ادعم صانعًا مستقلًا' : 'Support an independent maker';
  // No ad SDK exists anywhere in this codebase (verified by grep) —
  // GrowDaily has never shown ads to anyone, free or Premium.
  String get premiumBenefitSupportDesc => isAr
      ? 'بلا إعلانات، ولا بيع بيانات، إلى الأبد.'
      : 'No ads, no data selling, ever.';
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
  /// Shown under [premiumComingSoon] when the offering failed to load —
  /// which in App Review's sandbox is the COMMON case, not the rare one.
  /// Without it the screen was a dead end: no plans, no retry, and (before
  /// the same fix) no Restore either.
  String get premiumRetry => isAr ? 'إعادة المحاولة' : 'Try again';
  String get premiumComingSoon => isAr
      ? 'بريميوم غير متاح الآن — حاول مرة أخرى بعد قليل.'
      : 'Premium isn\'t available right now — please try again shortly.';
  String get premiumActive => isAr
      ? 'بريميوم مفعّل — شكرًا لدعمك!'
      : 'Premium is active — thank you for your support!';
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
  String get premiumPrivacyPolicy => isAr ? 'سياسة الخصوصية' : 'Privacy Policy';
  String get premiumLinkOpenError =>
      isAr ? 'تعذّر فتح الرابط.' : 'Couldn\'t open the link.';

  // ── Help & Support (help_support_screen.dart) ───────────────────────────
  // FAQ question/answer text itself lives in that file's own kFaqEntries
  // list (bilingual fields directly on each entry, same shape
  // IslamicHabitTemplate already uses for catalog content) rather than
  // here - these are just the screen's UI chrome, not its content.
  String get helpSupportRowTitle => isAr ? 'المساعدة والدعم' : 'Help & Support';
  String get helpFaqSectionTitle => isAr ? 'الأسئلة الشائعة' : 'FAQ';
  String get helpContactSectionTitle => isAr ? 'تواصل معنا' : 'Contact us';
  String get helpContactEmailLabel => isAr ? 'البريد الإلكتروني' : 'Email';
  String get helpContactWhatsAppLabel => isAr ? 'واتساب' : 'WhatsApp';
  String get helpContactInstagramLabel => isAr ? 'إنستغرام' : 'Instagram';
  String get helpGuidesSectionTitle => isAr ? 'شروحات الاستخدام' : 'Guides';
  String get habitLimitTitle =>
      isAr ? 'وصلت لحد الخطة المجانية' : 'You\'ve reached the free plan limit';
  String habitLimitBody(int limit) => isAr
      ? 'الخطة المجانية تشمل $limit عادات. افتح عادات غير محدودة مع بريميوم.'
      : 'The free plan includes $limit habits. Unlock unlimited habits with Premium.';

  // ── Voice note gate ──────────────────────────────────────────────────────
  String get voiceNoteGateTitle => isAr
      ? 'الملاحظات الصوتية ميزة بريميوم'
      : 'Voice notes are a Premium feature';
  String get voiceNoteGateBody => isAr
      ? 'سجّل ملاحظة صوتية سريعة لأي مهمة — متاحة مع بريميوم.'
      : 'Record a quick voice note on any task — available with Premium.';
  String get voiceNoteRecording => isAr ? 'جارٍ التسجيل…' : 'Recording…';
  String get voiceNoteTapToRecord => isAr ? 'اضغط للتسجيل' : 'Tap to record';
  String get voiceNoteTapToStop => isAr ? 'اضغط للإيقاف' : 'Tap to stop';
  String get voiceNoteMicPermissionDenied => isAr
      ? 'يحتاج التطبيق إذن الميكروفون لتسجيل الملاحظات الصوتية.'
      : 'Grow Daily needs microphone access to record voice notes.';
  String get voiceNoteAttached =>
      isAr ? 'ملاحظة صوتية مرفقة' : 'Voice note attached';
  String get voiceNotePlay => isAr ? 'تشغيل' : 'Play';
  String get voiceNotePause => isAr ? 'إيقاف مؤقت' : 'Pause';
  String get voiceNoteSkipBack => isAr ? 'رجوع 5 ثوانٍ' : 'Back 5 seconds';
  String get voiceNoteSkipForward =>
      isAr ? 'تقديم 5 ثوانٍ' : 'Forward 5 seconds';
  String voiceNoteSpeedLabel(String rate) =>
      isAr ? 'سرعة التشغيل، $rate' : 'Playback speed, $rate';
  // TaskDetailSheet's recordings-list section header — a task can hold
  // several named notes now (see VoiceNote), not just the one
  // voiceNoteAttached above used to describe.
  String get voiceNotesTitle => isAr ? 'الملاحظات الصوتية' : 'Voice Notes';
  // Placeholder shown for a recording nobody has named yet — "n" is that
  // note's 1-based position among this task's own recordings.
  String voiceNoteDefaultName(int n) => isAr ? 'تسجيل $n' : 'Recording $n';
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
      ? 'أنجز 80% من عادات اليوم على الأقل عشان تستمر.'
      : 'Finish 80% or more of today\'s habits to keep it going.';

  // ── First-run onboarding ─────────────────────────────────────────────────
  // Tone: benefit-first, short, warm — Khaleeji Arabic (not MSA), matching
  // the notification copy's voice. Four slides: Grid, Habits, Tasks, Rooms —
  // the Achievements slide was cut (it duplicated the gold/XP mention
  // already in the Habits slide), and the per-slide "where to tap" hint
  // chip was removed too, so this is now just title + body per slide.
  String get onboardingGridTitle => isAr
      ? 'لوّن حياتك، مربّع كل يوم'
      : 'Color your life, one square at a time';
  String get onboardingGridBody => isAr
      ? 'كل عادة تخلصها تلوّن مربّع في شبكتك. الأيام الخضرا تتجمع، وشهرك يمتلي شوي شوي.'
      : 'Every habit you finish colors a square. Green days add up. Watch your month fill in.';
  String get onboardingHabitsTitle =>
      isAr ? 'عادات صغيرة، فرق كبير' : 'Small habits, big difference';
  String get onboardingHabitsBody => isAr
      ? 'صلاة، قرآن، رياضة، أي شي يهمك. كل وحدة تخلصها تعطيك نقاط وذهب، وسلسلتك تكبر.'
      : 'Prayer, Quran, gym, anything that matters to you. Each one you finish earns XP and gold, and your streak grows.';
  String get onboardingTasksTitle =>
      isAr ? 'رتّب يومك بثواني' : 'Sort your day in seconds';
  String get onboardingTasksBody => isAr
      // Quadrant names match MatrixQuadrant.localLabel exactly (أولاً /
      // جدول / فوّض / احذف) so the slide teaches the same words the
      // Tasks screen actually shows.
      ? 'حط مهامك في أربع خانات: أولاً، جدول، فوّض، أو احذف. والمهم ما يضيع.'
      : 'Drop tasks into four boxes: Do First, Schedule, Delegate, or Eliminate. The important stuff never gets lost.';
  String get onboardingRoomsTitle =>
      isAr ? 'مع الربع أحلى' : 'Better with your people';
  String get onboardingRoomsBody => isAr
      // وناسة (not ونسة) — the real Gulf spelling, per the user.
      ? 'سوّ غرفة لأهلك وربعك، اربطوا عاداتكم، وتسابقوا على الصدارة. إنتاجية ووناسة.'
      : 'Make a room with family and friends, link your habits, and race up the leaderboard. Productive, together.';
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
  String get roomGenericError => isAr
      ? 'حدث خطأ ما. حاول مرة أخرى.'
      : 'Something went wrong. Please try again.';
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
  // Star toggle on each room's list tile — a personal, this-account-only
  // pin (see RoomsController.toggleStarRoom) that floats that room to the
  // top of this list (see sortStarredFirst), independent of what any other
  // member of the room sees.
  String get roomStarTooltip =>
      isAr ? 'تمييز هذه الغرفة بنجمة' : 'Star this room';
  String get roomUnstarTooltip =>
      isAr ? 'إلغاء تمييز هذه الغرفة' : 'Unstar this room';

  // Create Room sheet
  String get roomCreateTitle => isAr ? 'إنشاء غرفة' : 'Create a Room';
  String get roomNameLabel => isAr ? 'اسم الغرفة' : 'Room name';
  // No worked example here on purpose: "تحدي الفجر" reads like the name of a
  // habit, so people typed a habit into the room field. The field says what it
  // wants, and the tappable ideas below it do the suggesting.
  String get roomNameHint => isAr ? 'اسم تختاره أنت' : 'A name you pick';
  String get roomNameIdeas => isAr ? 'أفكار' : 'Ideas';

  /// Group names, not habit names — the distinction the old placeholder blurred.
  List<String> get roomNameSuggestions => isAr
      ? const [
          'العائلة',
          'الشلّة',
          'زملاء العمل',
          'رفاق النادي',
          'مجموعة الدراسة',
        ]
      : const [
          'Family',
          'The Squad',
          'Work Crew',
          'Gym Buddies',
          'Study Group',
        ];
  String get roomHabitModeLabel =>
      isAr ? 'كيف تعمل العادة؟' : 'How does the habit work?';
  String get roomHabitModeShared => isAr ? 'خطة القائد' : "Leader's plan";
  String get roomHabitModeSharedHint => isAr
      ? 'اختر من عاداتك — كل من ينضم يحصل عليها في شبكته أيضًا'
      : 'Pick from your own habits — everyone who joins gets them added to their Grid too';
  String get roomHabitModeOwn =>
      isAr ? 'عادة كل شخص الخاصة' : "Everyone's own habit";
  String get roomHabitModeOwnHint => isAr
      ? 'كل شخص يربط عادة واحدة أو أكثر من عاداته الخاصة'
      : 'Each person links one or more of their own habits';
  String get roomYourHabitLabel =>
      isAr ? 'عادتك لهذه الغرفة' : 'Your habit for this room';

  // Create Room - compete mode (RoomCompeteMode) - the leader's one-time
  // choice between the individual leaderboard this app always had and a
  // shared, collaborative goal layered on top of it (see RoomTeamProgress/
  // _TeamProgressCard's claim button).
  String get roomCompeteModeLabel => isAr ? 'روح الغرفة' : 'Room spirit';
  String get roomCompeteModeCompetitive => isAr ? 'تنافسية' : 'Competitive';
  String get roomCompeteModeCompetitiveHint =>
      isAr ? 'لوحة صدارة تقيس من الأفضل' : "A leaderboard ranks who's ahead";
  String get roomCompeteModeTeam => isAr ? 'فريق واحد' : 'Team';
  String get roomCompeteModeTeamHint => isAr
      ? 'اللوحة تبقى، ويضاف هدف مشترك: أنجزوا سويةً 100% وتحصل المجموعة كاملة على مكافأة'
      : 'Keeps the leaderboard, adds a shared goal: hit 100% together and the whole group earns a bonus';

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
  // The escape hatch beyond the 7/14/30/90 quick-picks - see
  // RoomModel.parseCustomRoomDurationDays for the 1-365 range this actually
  // enforces, and CreateRoomSheet/_ExtendRoomSheet for the two places this
  // trio of strings is shared between.
  String get roomDurationCustomOption => isAr ? 'مخصص' : 'Custom';
  String get roomDurationCustomHint => isAr ? 'عدد الأيام' : 'Number of days';
  String get roomDurationCustomRange => isAr ? '1 إلى 365 يومًا' : '1–365 days';
  String get roomDurationCustomInvalid =>
      isAr ? 'أدخل رقمًا بين 1 و365' : 'Enter a number between 1 and 365';
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

  /// The invite that actually travels — a WhatsApp message to someone who may
  /// or may not have the app.
  ///
  /// The link is now an https Universal Link (see roomJoinUrl), not the old
  /// `growdaily://join/CODE`. That change is the whole point: messengers only
  /// auto-linkify http/https, so the custom scheme arrived as untappable grey
  /// text, and it had no fallback at all — a recipient without the app got
  /// nothing, not even a clue what the link was for. The https link opens the
  /// app directly when it is installed and otherwise loads a page that
  /// explains the invite and offers the download.
  ///
  /// The code stays, on its own line, as the manual path: link previews get
  /// mangled, links get truncated by some clients, and someone may simply be
  /// reading this on a laptop. "أو" / "or" makes it explicitly the backup
  /// rather than a second instruction.
  String roomShareMessage(String name, String code) {
    final url = roomJoinUrl(code);
    return isAr
        ? 'انضم إلى تحدي "$name" في Grow Daily!\n\n$url\n\nأو استخدم الرمز: $code'
        : 'Join my "$name" challenge on Grow Daily!\n\n$url\n\nOr use the code: $code';
  }

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
  String get roomPreviewOwnMode =>
      isAr ? 'أحضر عادتك الخاصة' : 'Bring your own habit';
  String roomPreviewSharedHabit(String name) =>
      isAr ? 'الجميع يتابع: $name' : 'Everyone tracks: $name';

  /// Heads the per-habit breakdown on the join preview. Deliberately not a
  /// count ("2 habits"): the list right underneath already answers how many,
  /// and the question someone about to join is actually asking is *what* they
  /// are agreeing to — which is why each row now carries its cadence too.
  String get roomPreviewSharedHabitsLabel =>
      isAr ? 'الجميع يتابع' : 'Everyone tracks';
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

  /// "Show all 200 members" — the leaderboard's reveal for a room longer
  /// than the first slice it renders. Reuses [roomMemberCount]'s own Arabic
  /// plural rules rather than repeating them, so 2 reads عضوان here too.
  String roomShowAllMembers(int n) =>
      isAr ? 'عرض كل ${roomMemberCount(n)}' : 'Show all ${roomMemberCount(n)}';

  /// Shown in the Join preview for a room past [kRoomAutoMuteMemberLimit],
  /// so arriving to a silent bell is something the person was told about
  /// rather than something they have to work out.
  String get roomLargeRoomMutedNote => isAr
      ? 'غرفة كبيرة — الإشعارات تبدأ مغلقة. تقدر تشغّلها من داخل الغرفة.'
      : 'Big room — notifications start off. You can turn them on inside.';

  /// The "your challenge finished" popup shown on the next app open after a
  /// room ends — see RoomFinaleAnnouncer (main.dart) and
  /// unseenFinishedRoomsProvider.
  String roomFinaleDialogBody(String roomName) => isAr
      ? 'انتهى تحدي «$roomName». افتحه لتشوف المنصة والنتيجة النهائية.'
      : '"$roomName" has finished. Open it to see the podium and the final standings.';
  String get roomFinaleShow => isAr ? 'اعرض النتيجة' : 'See results';
  String get roomFinaleDismiss => isAr ? 'لاحقًا' : 'Not now';

  /// End-of-room podium prize (competitive rooms) — see
  /// RoomsController.podiumPrizeFor for the amounts.
  String roomClaimPrize(int xp, int gold) => isAr
      ? 'استلم جائزتك: $xp نقطة + $gold ذهب'
      : 'Claim your prize: $xp XP + $gold gold';
  String get roomPrizeClaimed =>
      isAr ? 'تم استلام جائزتك 🎉' : 'Prize claimed 🎉';

  // Room Detail / leaderboard screen
  String get roomOngoing => isAr ? 'مستمرة' : 'Ongoing';
  String get roomEnded => isAr ? 'انتهت' : 'Ended';
  String roomDaysLeft(int n) =>
      isAr ? '${daysCount(n)} متبقية' : '${daysCount(n)} left';
  // roomMyPlanTitle ("Your plan" / "خطتك") was removed with the card's title
  // row: a card that says "not done yet today" directly above your own habit
  // does not also need labelling. Kept out rather than left dangling so the
  // next person doesn't wonder where it renders.
  String get roomMarkedToday => isAr ? 'تم إنجاز اليوم' : 'Done for today';
  String get roomNotDoneToday => isAr ? 'لم يُنجز بعد اليوم' : 'Not yet today';

  /// "1/2 today" - shown instead of [roomMarkedToday]/[roomNotDoneToday]
  /// when some but not all of a multi-habit plan is done today (see
  /// RoomParticipant.isFullyDone) - the partial-credit middle state
  /// between the other two.
  String roomPartialToday(int done, int total) =>
      isAr ? '$done من $total اليوم' : '$done/$total today';

  /// One line per flexible weekly-quota habit on the plan card ("تمرين:
  /// 2/4 هذا الأسبوع"). The quota's week-level standing has no other home on
  /// this screen: the headline above only answers *today*, so a "4x a week"
  /// person had to keep the count in their head.
  String roomQuotaWeekProgress(String habit, int done, int target) => isAr
      ? '$habit: $done من $target هذا الأسبوع'
      : '$habit: $done of $target this week';

  /// Appended to [roomQuotaWeekProgress] on a day the quota genuinely owes
  /// (see DayDemand.owed): skipping today puts the week's target out of
  /// reach. This is the "last chance" nudge — the exact day the old grading
  /// bug used to greet with "Done for today" instead.
  String get roomQuotaNeededToday => isAr ? 'مطلوب اليوم' : 'needed today';

  /// Room header: when the challenge actually began — previously nowhere on
  /// the screen; the header only ever said how many days REMAIN, so "when
  /// did this start" took mental arithmetic against the room length.
  // Names the accented first cell of a participant's contribution strip.
  // Always shown; the date beside it only appears for a late joiner, whose
  // first day differs from the room's own start (already in the header).
  String get roomStripStart => isAr ? 'البداية' : 'Start';

  /// Toggle above the leaderboard that puts a per-week done-count over every
  /// column of every participant's strip. Off by default — the strip's job
  /// at rest is the shape of someone's month, and a number over each column
  /// is a second reading of the same data that only some people want.
  String get roomStripDetails => isAr ? 'تفاصيل الأسابيع' : 'Week detail';
  // The participant-calendar sheet the strip opens. The strip's own 9pt
  // cells can never be tapped (they fail every touch-target standard), so
  // this sheet is where a day is actually inspectable — hence the button
  // label naming what tapping the strip does, not what it shows.
  String get roomStripOpenCalendar => isAr ? 'عرض التقويم' : 'Open calendar';
  String roomCalendarTitle(String name) =>
      isAr ? 'تقويم $name' : "$name's calendar";
  String get roomCalendarDone => isAr ? 'أُنجز' : 'Done';
  String get roomCalendarMissed => isAr ? 'لم يُنجز' : 'Not done';
  String get roomCalendarPartial => isAr ? 'أُنجز جزئيًا' : 'Partly done';
  // A day the quota asked nothing of them — see RoomParticipant.isRestDay.
  // It scores as finished but draws empty, so the calendar has to say which
  // it is or an empty cell reads as a miss.
  String get roomCalendarRestDay => isAr ? 'يوم راحة' : 'Rest day';

  /// A day the member deliberately stood everything down (تخطّي), as opposed
  /// to [roomCalendarRestDay], which is a day nothing was owed on in the
  /// first place. Different facts, so different words: one is a choice, the
  /// other is the calendar.
  ///
  /// Said in the passive, not as "you rested", because this sheet is opened
  /// on OTHER participants as often as on yourself.
  String get roomCalendarStoodDown => isAr ? 'راحة مُعلَنة' : 'Rested';

  /// A day the whole ROOM was paused. Nobody was being graded, which is not
  /// the same as nobody doing anything, and the strip already draws it blank.
  String get roomCalendarPaused => isAr ? 'الغرفة متوقفة' : 'Room paused';
  // Shown when the selected day IS this participant's first counted day —
  // the one the strip rings. Worth its own note rather than just a status,
  // because it's the day that explains the shape of everything after it.
  String get roomCalendarFirstDayNote =>
      isAr ? 'أول يوم لك في هذه الغرفة' : 'Your first day in this room';
  String get roomCalendarFirstDayNoteOther =>
      isAr ? 'أول يوم في هذه الغرفة' : 'First day in this room';
  String roomStartedOn(String date) => isAr ? 'بدأت $date' : 'Started $date';
  String roomStartsOn(String date) => isAr ? 'تبدأ $date' : 'Starts $date';

  /// Notification Settings' system-permission banner — shown ONLY when the
  /// OS itself has this app's notifications switched off (see
  /// NotificationService.checkSystemPermission). Without it, every in-app
  /// toggle reads "on" while iOS silently drops every reminder, and even the
  /// test button fails with no explanation.
  String get notifSystemPermissionOff => isAr
      ? 'الإشعارات موقوفة من إعدادات النظام — لن يصلك أي تذكير حتى يتم تفعيلها.'
      : 'Notifications are turned off in system Settings — no reminder can reach you until they are allowed.';
  String get notifSystemPermissionOffAction =>
      isAr ? 'افتح إعدادات النظام' : 'Open system Settings';

  /// Shown in the room when a linked habit's live settings no longer match
  /// the cadence the room is scoring it by (see roomRuleMismatches and
  /// RoomParticipant.habitRules). Deliberately explains rather than alarms:
  /// the room holding its original rules is the CORRECT behaviour, since it
  /// stops an edit from rewriting finished days, so this reads as
  /// information plus an offer, not an error.
  String roomRuleChangedWarning(String habitNames) => isAr
      ? 'غيّرت إعدادات: $habitNames. هذه الغرفة ما زالت تحسب بالإعدادات الأصلية، حتى لا تتأثر أيامك السابقة.'
      : 'You changed the settings for $habitNames. This room still scores the original settings, so your finished days stay as you earned them.';
  String get roomRuleChangedAction => isAr
      ? 'استخدم إعداداتي الجديدة من اليوم'
      : 'Use my new settings from today';
  String get roomRuleChangedApplied => isAr
      ? 'تم. الأيام السابقة كما هي، والحساب الجديد يبدأ من اليوم.'
      : 'Done. Past days keep their score, the new settings start today.';

  /// The "no thanks" on a leader-added shared habit (see
  /// RoomsController.declineSharedHabit). A skipped slot counts for nothing
  /// either way, so this never costs the person anything.
  String get roomSkipSharedHabit => isAr ? 'تخطَّ هذه' : 'Skip this one';
  String get roomSkippedLabel => isAr ? 'متخطاة' : 'Skipped';
  String get roomSkippedHint => isAr
      ? 'هذه العادة لا تُحسب لك، لا لصالحك ولا ضدك. اضغط لإضافتها لاحقًا.'
      : 'This habit does not count for you either way. Tap to add it after all.';

  /// Leader-only removal of a shared habit (see
  /// RoomsController.removeSharedHabit).
  String get roomCancel => isAr ? 'إلغاء' : 'Cancel';
  String get roomRemoveSharedHabit =>
      isAr ? 'إزالة من الخطة' : 'Remove from plan';
  String roomRemoveSharedHabitConfirm(String habitName) => isAr
      ? 'إزالة "$habitName" من خطة الغرفة؟ ستتوقف عن الحساب للجميع، ولن تتأثر الأيام السابقة.'
      : 'Remove "$habitName" from the room plan? It stops counting for everyone, and no past day changes.';
  String get roomRemovedLabel => isAr ? 'مُزالة' : 'Removed';
  String roomPlanPartialCreditHint(int n) => isAr
      ? 'كل عادة تُنجزها تضيف جزءًا من التقدم — إكمال كل الـ $n يمنحك اليوم كاملًا'
      : 'Each one you finish adds partial credit — complete all $n for the full day';
  // Team Progress card (RoomTeamProgress) - the room-wide combined-goal
  // view alongside the individual leaderboard: "everyone together" numbers
  // rather than who's ranked where. daysCount(n) (already used by
  // roomDaysLeft above) covers the Arabic plural for the numbers here too.
  String get roomTeamProgressTitle => isAr ? 'تقدم الفريق' : 'Team progress';
  String roomTeamProgressDays(int completed, int possible) => isAr
      ? '${daysCount(completed)} من ${daysCount(possible)} سويةً'
      : '$completed of $possible days together';
  String get roomTeamAllDoneToday =>
      isAr ? 'الكل حضر اليوم' : "Everyone's shown up today";
  // Team bonus claim (RoomCompeteMode.team only) - see _TeamProgressCard's
  // three states: still chasing it, ready to claim, already claimed.
  String roomTeamBonusHint(int xp, int gold) => isAr
      ? 'أنجزوا 100% سويةً — كل يوم، كل شخص — ليحصل الجميع على +$xp خبرة و+$gold ذهب'
      : 'Hit 100% together — every day, every person — and everyone earns +$xp XP and +$gold gold';
  String get roomTeamBonusClaimAction =>
      isAr ? 'المطالبة بمكافأة الفريق' : 'Claim Team Bonus';
  String get roomTeamBonusClaimedLabel =>
      isAr ? 'تم استلام مكافأة الفريق' : 'Team bonus claimed';
  String get roomDetailsHidden => isAr ? 'مخفي عن الغرفة' : 'Hidden from room';
  String get roomDetailsVisible => isAr ? 'مرئي للغرفة' : 'Visible to room';
  // Editing a room's habit(s) after it's already been created - see
  // RoomsController.addSharedHabit ('shared' mode, leader-only, appears in
  // RoomDetailScreen's app-bar menu) and .addMyLinkedHabit ('own' mode, any
  // participant, appears right on _MyPlanCard) plus resolvePlanHabit (the
  // banner an already-joined guest sees once the leader's added something
  // new for them to link).
  String get roomAddHabitAction => isAr ? 'إضافة عادة' : 'Add a habit';
  String get roomAddHabitPickerTitle =>
      isAr ? 'إضافة عادة إلى الخطة' : 'Add a habit to the plan';
  String get roomAddHabitPickerHint => isAr
      ? 'كل من هم بالفعل في هذه الغرفة سيُطلب منهم ربط إحدى عاداتهم بها أيضًا.'
      : 'Everyone already in this room will be asked to link one of their own habits to it too.';
  String roomHabitAddedConfirmation(String habitName) => isAr
      ? 'تمت إضافة "$habitName" إلى الخطة'
      : 'Added "$habitName" to the plan';
  String get roomAddAnotherHabitAction =>
      isAr ? '+ إضافة عادة أخرى' : '+ Add another habit';
  String get roomAddAnotherHabitPickerTitle =>
      isAr ? 'إضافة عادة أخرى' : 'Add another habit';
  String get roomAddAnotherHabitPickerHint => isAr
      ? 'تابع عادة أخرى من عاداتك في هذه الغرفة.'
      : 'Track one more of your own habits in this room.';

  // ── Room-finish push (functions/index.js) ──────────────────────────────
  //
  // The one push category this app sends from a server rather than
  // scheduling locally - see NotificationSettings.roomActivityEnabled's
  // doc comment for the master toggle, and RoomParticipant.
  // notificationsMuted for this per-room override.
  String get roomMuteAction =>
      isAr ? 'كتم إشعارات هذه الغرفة' : 'Mute notifications for this room';
  String get roomUnmuteAction => isAr
      ? 'إلغاء كتم إشعارات هذه الغرفة'
      : 'Unmute notifications for this room';
  String get roomMutedConfirmation =>
      isAr ? 'تم كتم إشعارات هذه الغرفة' : 'Notifications muted for this room';
  String get roomUnmutedConfirmation => isAr
      ? 'تم إلغاء كتم إشعارات هذه الغرفة'
      : 'Notifications unmuted for this room';
  String get roomNoMoreHabitsToAdd => isAr
      ? 'كل عاداتك مرتبطة بهذه الغرفة بالفعل.'
      : 'All of your habits are already linked to this room.';

  /// The persistent "create instead of pick" row on pickOwnHabitSheet and
  /// CreateRoomSheet's _PlanHabitPicker - always shown, not just when the
  /// existing-habits list is empty, so there's never a dead end if none of
  /// your current habits fit what this room needs.
  String get roomCreateNewHabitAction =>
      isAr ? 'إنشاء عادة جديدة' : 'Create a new habit';

  /// Shown under [roomCreateNewHabitAction] only when picking/creating for
  /// a shared-mode room's plan (see pickOwnHabitSheet's isSharedTemplate
  /// param) - whatever gets created here is exactly what every other
  /// participant is later offered to link or clone, so this makes that
  /// plain before they name it.
  String get roomCreateNewHabitSharedNote => isAr
      ? 'سيصبح هذا هو العادة التي يمكن للجميع في الغرفة اتباعها أيضًا.'
      : 'This becomes the habit everyone in the room can follow too.';

  /// Non-blocking heads-up after creating a new habit through one of the
  /// room pickers, when its name closely matches one you already have (see
  /// suggestExistingMatch in rooms_notifier.dart, the same fuzzy-match
  /// helper the resolve-new-habits flow already uses to suggest a likely
  /// existing match) - a nudge, not a gate, so it never blocks the habit
  /// that was already created.
  String roomPossibleDuplicateWarning(String existingName) => isAr
      ? 'ملاحظة: لديك بالفعل عادة باسم "$existingName" مشابهة لهذه.'
      : 'Heads up: you already have a habit called "$existingName" that looks similar.';

  /// The banner _MyPlanCard shows a guest once the leader's added a new
  /// shared-plan slot they haven't resolved yet (see RoomsController.
  /// resolvePlanHabit) - [habitName] is the new plan entry's own name, same
  /// snapshot every other plan-preview string already shows.
  String roomNewHabitBannerTitle(String habitName) => isAr
      ? 'أضاف القائد عادة جديدة: $habitName'
      : 'Your leader added a new habit: $habitName';
  String get roomNewHabitBannerBody => isAr
      ? 'اربط إحدى عاداتك لتبقى نسبة إنجازك في هذه الغرفة دقيقة.'
      : 'Link one of your own habits so your progress here stays accurate.';
  String get roomNewHabitBannerAction => isAr ? 'ربط الآن' : 'Link now';
  String get roomResolveHabitsSheetTitle =>
      isAr ? 'عادة جديدة في الخطة' : 'New habit in the plan';
  // The local notification for this same event (RoomsHubScreen noticing an
  // unresolved plan slot) is NOT here - NotificationService.
  // showRoomHabitAdded fires with no BuildContext available (same as every
  // other notification body in that file, e.g. showTest), so its EN/AR
  // copy is hardcoded directly there instead of routed through S.
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
  /// deleted (see AddHabitSheet._deleteExisting/GridScreen._deleteSelected/
  /// DashboardScreen's Today swipe-delete) - the one moment this consequence
  /// is still easy to avoid, unlike after the fact when all that's left is
  /// roomLinkedHabitDeletedHint's warning.
  String get habitLinkedRoomWarningTitle =>
      isAr ? 'مرتبطة بغرفة مشتركة' : 'Linked to a shared room';

  /// [roomNames] is never empty (callers only show this dialog when at
  /// least one room is affected) - names, not just a count, so the person
  /// can recognize exactly which room(s) before confirming, and explicitly
  /// reassures that unlinking never means leaving: RoomsController.
  /// unlinkHabitEverywhere only ever strips this one habitId from
  /// linkedHabitIds, it never removes the participant doc or touches any
  /// other linked habit, so every other room this account is in - and every
  /// other habit still linked to *this* room - carries on exactly as
  /// before. See that method's own doc comment for the full guarantee.
  String habitLinkedRoomWarningBody(List<String> roomNames) {
    final quoted = roomNames.map((n) => isAr ? '"$n"' : '"$n"').toList();
    if (isAr) {
      final list = quoted.join('، ');
      return roomNames.length == 1
          ? 'هذه العادة جزء من تقدمك في غرفة $list. حذفها سيُلغي ربطها بتلك الغرفة فقط - ستبقى في الغرفة وتتابع بقية عاداتك المرتبطة بها فيها كما هي.'
          : 'هذه العادة جزء من تقدمك في غرف $list. حذفها سيُلغي ربطها بها جميعًا فقط - ستبقى في كل غرفة وتتابع بقية عاداتك المرتبطة بها فيها كما هي.';
    }
    final list = quoted.length == 1
        ? quoted.first
        : quoted.length == 2
            ? '${quoted[0]} and ${quoted[1]}'
            : '${quoted.sublist(0, quoted.length - 1).join(', ')}, and ${quoted.last}';
    return roomNames.length == 1
        ? "This habit counts toward your progress in $list. Deleting it will only unlink it from that room - you'll stay in the room and keep tracking anything else still linked there."
        : "This habit counts toward your progress in $list. Deleting it will only unlink it from those rooms - you'll stay in each room and keep tracking anything else still linked there.";
  }

  String get habitDeleteAnywayAction =>
      isAr ? 'حذف على أي حال' : 'Delete Anyway';
  String get habitDeleteLinkedRoomCancel => isAr ? 'إلغاء' : 'Cancel';

  /// The pause-side wording of [habitLinkedRoomWarningBody]. Pause does
  /// NOT unlink (see GridScreen._pauseHabit for why that was reverted), so
  /// this says the one thing that is actually true of a paused habit in a
  /// live room: the days it is away are days that room does not credit,
  /// and resuming puts it back. Nothing here is permanent, which is why
  /// the confirm button is a plain Pause rather than an "anyway".
  String habitPauseLinkedRoomBody(List<String> roomNames) {
    final quoted = roomNames.map((n) => '"$n"').toList();
    if (isAr) {
      final list = quoted.join('، ');
      return roomNames.length == 1
          ? 'هذه العادة محسوبة في غرفة $list. أيام إيقافها لن تُحتسب لك هناك، وترجع كما كانت عند الاستئناف. لن تخرج من الغرفة، وسجل العادة محفوظ بالكامل.'
          : 'هذه العادة محسوبة في غرف $list. أيام إيقافها لن تُحتسب لك فيها، وترجع كما كانت عند الاستئناف. لن تخرج من أي غرفة، وسجل العادة محفوظ بالكامل.';
    }
    final list = quoted.length == 1
        ? quoted.first
        : quoted.length == 2
            ? '${quoted[0]} and ${quoted[1]}'
            : '${quoted.sublist(0, quoted.length - 1).join(', ')}, and ${quoted.last}';
    return roomNames.length == 1
        ? "This habit counts toward $list. Days it is paused won't count for you there, and resuming puts it back the way it was. You stay in the room, and the habit's own record is kept in full."
        : "This habit counts toward $list. Days it is paused won't count for you in them, and resuming puts it back the way it was. You stay in every room, and the habit's own record is kept in full.";
  }

  String get habitPauseAnywayAction => isAr ? 'أوقف مؤقتًا' : 'Pause';

  /// Snackbar shown right after a habit is removed (see
  /// AddHabitSheet._deleteExisting/GridScreen._deleteSelected) — removal
  /// is now an archive under the hood (IslamicHabitTemplate.archivedAt),
  /// not a hard delete, so this is reassurance rather than a warning:
  /// nothing about the Heatmap or Insights actually goes blank.
  /// Kept short deliberately. This used to name both destinations — «سجلك
  /// السابق باقٍ في الإحصائيات وخريطة الحرارة» — which ran to two full lines
  /// of a floating snackbar sitting over the nav bar, and used «خريطة
  /// الحرارة» for a screen this app calls «خريطة التقدّم» everywhere else
  /// (see [heatmapTitle]), so it named a screen that does not exist by that
  // ── Pause / resume a habit ──────────────────────────────────────────
  //
  // "Pause", not "archive": what this does is stop a habit appearing
  // without touching a day of its history, and pause is the word that
  // carries no verdict. Deleting says "that was a mistake"; pausing says
  // "not now" — which for قيام الليل after Ramadan, or a study habit after
  // exams, is simply the truth. The DATA layer still calls it archive
  // (CustomHabitsNotifier.archive / archivedAt); only what people read
  // changed, because renaming stored fields buys nothing and risks a
  // migration.
  String get habitEdit => isAr ? 'تعديل' : 'Edit';
  String get habitActionsCancel => isAr ? 'إلغاء' : 'Cancel';
  String get habitPause => isAr ? 'إيقاف مؤقت' : 'Pause';
  String get habitPauseHint => isAr
      ? 'تختفي من لوحتك، وسجلها كامل محفوظ، وترجعها متى شئت.'
      : 'It leaves your board, keeps every day of its history, and comes back whenever you want.';
  String get habitResume => isAr ? 'استئناف' : 'Resume';
  String get habitResumeHint => isAr
      ? 'ترجع إلى لوحتك من اليوم، بكل سجلها السابق.'
      : 'Back on your board from today, with all of its past record.';
  String habitPausedConfirmation(String name) =>
      isAr ? 'تم إيقاف "$name" مؤقتًا' : '"$name" paused';
  String habitResumedConfirmation(String name) =>
      isAr ? 'رجعت "$name" إلى لوحتك' : '"$name" is back on your board';
  /// The paused section heading in the Add Habit sheet — where someone
  /// goes when they want a habit back, so resuming lives at the exact
  /// moment of intent rather than in a settings screen nobody visits.
  String get habitPausedSection => isAr ? 'موقوفة مؤقتًا' : 'Paused';
  String habitPausedDaysBadge(int n) =>
      isAr ? '$n يوم محفوظ' : '$n days saved';
  /// Collapsed-list control. Three paused habits fit before the section
  /// starts pushing the sheet's actual subject (adding a habit) off the
  /// screen, so the rest sit behind this one tap.
  String habitPausedShowAll(int n) =>
      isAr ? 'عرض الكل ($n)' : 'Show all ($n)';
  String get habitPausedShowLess => isAr ? 'عرض أقل' : 'Show less';
  /// Shown in the selection bar the moment multi-select is switched on
  /// from the header, before anything has been picked. "0 selected" next
  /// to a red Delete button describes the state accurately and still
  /// reads as broken; this says what to do instead.
  String get gridSelectPrompt =>
      isAr ? 'اختر العادات التي تريدها' : 'Tap the habits you want';

  // ── Delete forever ──────────────────────────────────────────────────
  String get habitDeleteForever => isAr ? 'حذف نهائي' : 'Delete forever';
  String habitDeleteForeverBody(String name) => isAr
      ? 'سيُحذف "$name" وسجله بالكامل، ولا يمكن التراجع. إذا كنت تريد إخفاءه فقط، استخدم الإيقاف المؤقت.'
      : 'This deletes "$name" and its whole history, and cannot be undone. If you only want it off your board, pause it instead.';
  String get habitDeleteForeverConfirm => isAr ? 'احذف نهائيًا' : 'Delete forever';
  String habitDeletedConfirmation(String name) =>
      isAr ? 'تم حذف "$name" نهائيًا' : '"$name" deleted';
  /// The long-press sheet's title.
  String get habitActionsTitle => isAr ? 'خيارات العادة' : 'Habit options';
  /// Header control that turns on multi-select, which long-press used to
  /// start before it became the actions menu.
  String get habitSelectMultiple => isAr ? 'تحديد' : 'Select';

  /// name. A confirmation only has to answer "did I just lose my history?" —
  /// "no" is the whole message, and Undo sits right beside it.
  String get habitArchivedConfirmation =>
      isAr ? 'تمت الإزالة. سجلك محفوظ.' : 'Removed. Your history is safe.';

  /// Plural counterpart for GridScreen's multi-select delete — [count] is
  /// always >= 2 at the one call site that uses this (the ==1 case uses
  /// [habitArchivedConfirmation] instead).
  ///
  /// Arabic agreement, same rules as [gridGreenSquaresCount]: 2 is the dual
  /// (عادتين, and the number itself is dropped because the dual form already
  /// says "two"), 3–10 takes the plural عادات, and 11+ takes the singular
  /// عادة after the numeral.
  String habitsArchivedConfirmation(int count) {
    if (!isAr) return 'Removed $count habits. Their history is safe.';
    if (count == 2) return 'تمت إزالة عادتين. سجلها محفوظ.';
    if (count <= 10) return 'تمت إزالة $count عادات. سجلها محفوظ.';
    return 'تمت إزالة $count عادة. سجلها محفوظ.';
  }

  /// "3/5 days" when [done] is whole, "2.5/5 days" when a multi-habit
  /// room's partial-credit days (see RoomParticipant.daysCompleted) leave
  /// it fractional - shows the exact number either way rather than
  /// rounding, since rounding here would quietly disagree with the %
  /// shown right next to it.
  String roomDayCount(double done, int total) {
    final doneStr = done == done.roundToDouble()
        ? done.toInt().toString()
        : done.toStringAsFixed(1);
    return isAr ? '$doneStr من $total' : '$doneStr/$total days';
  }

  String get roomYouLabel => isAr ? 'أنت' : 'You';
  String get roomLeaderLabel => isAr ? 'القائد' : 'Leader';
  String get roomLeaveAction => isAr ? 'مغادرة الغرفة' : 'Leave Room';
  String get roomLeaveConfirmTitle =>
      isAr ? 'مغادرة هذه الغرفة؟' : 'Leave this room?';
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
  String get roomDeleteConfirmTitle =>
      isAr ? 'حذف هذه الغرفة؟' : 'Delete this room?';
  String get roomDeleteConfirmBody => isAr
      ? 'سيؤدي هذا إلى إزالتها للجميع، ولا يمكن التراجع عن ذلك.'
      : "This removes it for everyone and can't be undone.";
  String get roomGoneMessage =>
      isAr ? 'هذه الغرفة لم تعد موجودة.' : 'This room no longer exists.';
  String get roomExtendAction => isAr ? 'تمديد الغرفة' : 'Extend Room';
  String get roomExtendTitle => isAr ? 'تمديد هذه الغرفة' : 'Extend this room';
  // Title of the resume-date step, shown only when extending a room that
  // already finished. Deliberately "resume" and never "restart": nothing is
  // reset — the history stays, the finish line moves, and the dead days in
  // between are excluded from everyone's score rather than counted as
  // misses.
  // Cadence badge under a leaderboard percentage — how demanding THIS
  // member's plan is. Two members in one room can be graded differently
  // (a 4x/week quota converts its untrained days into full credit, a daily
  // habit does not), which is most of why two people doing identical work
  // can show very different numbers. Naming the cadence is what makes that
  // gap explainable instead of arbitrary.
  String roomCadenceWeekly(int n) => isAr ? '$n× أسبوعياً' : '$n× a week';
  // The opt-in playful nudge. Worded as an invitation, never an accusation:
  // "still waiting on you" is banter, "you didn't" is a reprimand.
  String get notifRoomNudges => isAr ? 'تحفيز ودّي' : 'Friendly nudges';
  String get notifRoomNudgesDesc => isAr
      ? 'لما أحد يخلّص قبلك، يوصلك تنبيه خفيف يذكّرك. في الغرف الصغيرة فقط، ومرّة وحدة باليوم.'
      : 'When someone finishes before you, get a light teasing reminder. Small rooms only, once a day.';
  String get roomCadenceDaily => isAr ? 'يومي' : 'Daily';
  // Shown when a member's linked habits don't all share one cadence, so the
  // badge names the count rather than a single misleading number.
  String roomCadenceMixed(int n) => isAr ? '$n عادات' : '$n habits';
  String get roomExtendResumeTitle =>
      isAr ? 'متى نكمل؟' : 'When do we pick up?';
  String get roomExtendBody => isAr
      ? 'اختر مدة جديدة تبدأ من اليوم، أو اجعلها بلا نهاية.'
      : 'Pick a new duration starting today, or make it open-ended.';
  String get roomExtended => isAr ? 'تم تمديد الغرفة.' : 'Room extended.';

  /// _FinaleCard's leader control (room_detail_screen_countdown_finale.dart).
  /// Deliberately worded as continuing, never as a rematch: extendRoom moves
  /// only endDate and preserves startDate and everyone's existing progress,
  /// so "Run it again" / "سباق جديد" would promise a clean scoreboard the
  /// code does not deliver. [roomFinaleExtendHint] says the same thing in
  /// full underneath, because the button alone can't carry it.
  String get roomFinaleExtendAction => isAr ? 'كمّلوا أكثر' : 'Keep it going';
  String get roomFinaleExtendHint => isAr
      ? 'يكمل نفس التحدي بنفس النقاط — ما يبدأ من جديد.'
      : 'Continues the same challenge with everyone\'s current scores — it does not start over.';

  /// Shown to non-leaders on a finished room, so the one person who can act
  /// isn't the only one who understands why the room is still here.
  String get roomFinaleMemberHint => isAr
      ? 'يقدر قائد الغرفة يمددها إذا تبون تكملون.'
      : 'The room leader can extend this if you all want to keep going.';

  // ── Notification Settings ────────────────────────────────────────────
  // (see features/settings/screens/notification_settings_screen.dart and
  // features/settings/widgets/city_search_sheet.dart)

  String get notificationsTitle => isAr ? 'الإشعارات' : 'Notifications';

  String get notifMasterTitle =>
      isAr ? 'السماح بالإشعارات' : 'Allow Notifications';
  String get notifMasterDesc => isAr
      ? 'أوقفه لإيقاف كل إشعارات Grow Daily، التذكيرات والسلاسل والاحتفالات، كل شيء.'
      : 'Turn off to stop every notification Grow Daily sends, reminders, streaks, celebrations, all of it.';

  String get notifWhatSection =>
      isAr ? 'ما الذي تريد إشعاري به' : 'WHAT TO NOTIFY ME ABOUT';
  String get notifHabitReminders =>
      isAr ? 'تذكيرات العادات' : 'Habit reminders';
  String get notifHabitRemindersDesc => isAr
      ? 'تذكير لكل عادة في وقتها الخاص — يُتخطى تلقائيًا بعد إنجازها لهذا اليوم.'
      : "One reminder per habit, at its own cue — skipped automatically once you've done it for the day.";
  String get notifStreakRisk => isAr ? 'حماية السلسلة' : 'Streak protection';
  String get notifStreakRiskDesc => isAr
      ? 'تنبيه مسائي، فقط عندما تكون سلسلة حقيقية على وشك الضياع.'
      : 'An evening nudge, but only when a real streak is actually about to be lost.';
  String get notifCelebrations => isAr ? 'الاحتفالات' : 'Celebrations';
  String get notifCelebrationsDesc => isAr
      ? 'إشعارات إنجاز العادة، الترقية، وفتح الإنجازات.'
      : 'Habit completed, level up, and achievement-unlocked pings.';
  String get notifMatrixNudge =>
      isAr ? 'ذكر المهام العاجلة' : 'Mention urgent tasks';
  String get notifMatrixNudgeDesc => isAr
      ? 'يضيف مهامك العاجلة من "افعل أولاً" إلى تنبيه السلسلة — لا يُرسل كإشعار منفصل أبدًا.'
      : 'Adds your open Do First tasks to the streak nudge — never a separate notification of its own.';
  String get notifBundle =>
      isAr ? 'دمج التذكيرات المتقاربة' : 'Bundle close-together reminders';
  String get notifBundleDesc => isAr
      ? 'عندما تتقارب مواعيد عادتين أو أكثر، تصل كإشعار واحد بدلًا من عدة إشعارات.'
      : '2+ habits due around the same time arrive as one notification instead of several.';

  String get notifWeeklyDigest => isAr ? 'ملخص الأسبوع' : 'Weekly digest';
  String get notifWeeklyDigestDesc => isAr
      ? 'مساء الجمعة، رسالة قصيرة عن أيامك الملوّنة هذا الأسبوع وسلسلتك الحالية.'
      : 'A short Friday-evening note on the days you colored this week and your current streak.';

  String get notifRoomActivity => isAr ? 'نشاط الغرف' : 'Room activity';
  String get notifRoomActivityDesc => isAr
      ? 'يصلك إشعار عندما ينهي أحد زملائك في الغرفة عاداته اليوم.'
      : 'Get notified when a teammate in one of your rooms finishes their habits for the day.';

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
  // notifPrayerOffset / minutesAfterPrayer were removed alongside the
  // global prayer-offset stepper they labelled — reminder timing is now
  // picked per habit in Add Habit (see offsetBeforeMinutes/
  // offsetAfterMinutes) instead of once globally for every prayer habit.

  String get notifQuietHoursSection => isAr ? 'ساعات الهدوء' : 'QUIET HOURS';
  String get notifQuietHours => isAr ? 'ساعات الهدوء' : 'Quiet hours';
  String get notifQuietHoursDesc => isAr
      ? 'لا تُرسل أي تذكيرات خلال هذه الفترة.'
      : 'No reminders fire during this window.';
  String get notifQuietStart => isAr ? 'تبدأ' : 'Starts';
  String get notifQuietEnd => isAr ? 'تنتهي' : 'Ends';
  String get notifQuietAppliesToPrayer => isAr
      ? 'تطبيقها على تذكيرات الصلاة أيضًا'
      : 'Apply to prayer reminders too';
  String get notifQuietAppliesToPrayerDesc => isAr
      ? 'معطّلة افتراضيًا — الفجر عادة يقع ضمن فترة الهدوء الليلية، وهو التذكير الذي يريده معظم الناس رغم ذلك.'
      : "Off by default — Fajr usually falls inside a nighttime quiet window, and that's the one reminder most people still want.";

  String get notifTimingSection => isAr ? 'التوقيت' : 'TIMING';
  String get notifStreakRiskTime =>
      isAr ? 'وقت فحص السلسلة' : 'Streak check time';

  String get notifSendTest =>
      isAr ? 'إرسال إشعار تجريبي' : 'Send a test notification';
  String get notifTestSent => isAr
      ? 'تم الإرسال — تحقق من قائمة الإشعارات.'
      : 'Sent — check your notification shade.';

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
  String get citySearchHint =>
      isAr ? 'مثال: القاهرة، إسطنبول، جاكرتا' : 'e.g. Cairo, Istanbul, Jakarta';
  String get citySearchNoResults => isAr
      ? 'لا توجد نتائج — جرّب تهجئة مختلفة.'
      : 'No matches — try a different spelling.';
  String get citySearchPrompt =>
      isAr ? 'ابدأ بكتابة اسم مدينتك.' : "Start typing your city's name.";
  String get citySearchEnterManually => isAr
      ? 'لم تجد مدينتك؟ أدخل الإحداثيات يدويًا'
      : "Can't find your city? Enter coordinates manually";
  String get citySearchBackToSearch =>
      isAr ? 'العودة إلى البحث' : 'Back to search';
  String get locationLabelHint =>
      isAr ? 'تسمية (مثل «المنزل»)' : 'Label (e.g. "Home")';
  String get latitude => isAr ? 'خط العرض' : 'Latitude';
  String get longitude => isAr ? 'خط الطول' : 'Longitude';
  String get useTheseCoordinates =>
      isAr ? 'استخدام هذه الإحداثيات' : 'Use these coordinates';

  // ── Journey Page (MilestoneEvent timeline) ────────────────────────────

  String get journeyTitle => isAr ? 'رحلتي' : 'Journey';
  String get journeyEmptyTitle =>
      isAr ? 'رحلتك على وشك أن تبدأ' : 'Your journey is just getting started';
  String get journeyEmptyBody => isAr
      ? 'أكمل عاداتك واستمر في التقدم — كل إنجاز مهم سيظهر هنا.'
      : 'Keep completing habits and leveling up — every meaningful win will show up here.';
  String journeyMilestoneCount(int count) {
    if (count == 0) return isAr ? 'لا إنجازات بعد' : 'No milestones yet';
    if (count == 1) return isAr ? 'إنجاز واحد' : '1 milestone';
    return isAr ? '$count إنجازًا' : '$count milestones';
  }

  String journeyMemberSince(String monthYear, int days) => isAr
      ? 'عضو منذ $monthYear ($days يومًا)'
      : 'Member since $monthYear ($days days)';

  // ── Life Timeline (year-at-a-glance) ───────────────────────────────────

  String get lifeTimelineTitle => isAr ? 'خط الحياة الزمني' : 'Life Timeline';
  String get lifeTimelineSubtitle => isAr
      ? 'رحلتك كاملة، سنة بسنة — كل مربع يوم، وكل شارة إنجاز مررت به.'
      : 'Your whole journey, year by year — every square a day, every badge a milestone you passed.';
  String lifeTimelineYearTotal(int total) =>
      isAr ? '$total مربع أخضر' : '$total green squares';
  String get lifeTimelineOpenHeatmap =>
      isAr ? 'فتح خريطة النشاط الكاملة' : 'Open full Heatmap';
  String get lifeTimelineUpgradeBody => isAr
      ? 'النسخة المميزة تفتح كل سنة منذ إنشاء حسابك. النسخة المجانية تعرض هذه السنة فقط.'
      : 'Premium unlocks every year back to when your account began. Free shows this year only.';

  // ── Room moderation (App Review guideline 1.2) ─────────────────────────
  //
  // Rooms put one person's typed text (room name, display name, habit
  // names) in front of strangers who joined by code, which makes this
  // user-generated content. Guideline 1.2 asks for four things: filtering,
  // reporting, blocking, and a way to reach the operator. These strings
  // cover the middle two; TextModeration covers the first and the support
  // email covers the last.

  String get roomMemberActions => isAr ? 'خيارات العضو' : 'Member options';
  String get roomReportAction => isAr ? 'إبلاغ' : 'Report';
  String get roomBlockAction => isAr ? 'حظر' : 'Block';
  String get roomUnblockAction => isAr ? 'إلغاء الحظر' : 'Unblock';
  String roomReportTitle(String name) =>
      isAr ? 'الإبلاغ عن $name' : 'Report $name';
  String get roomReportSubtitle => isAr
      ? 'اختر السبب. البلاغ يوصلنا فقط، وما يُعلم الطرف الثاني.'
      : "Pick a reason. Reports come only to us, and the other person isn't told.";
  String get roomReportReasonName =>
      isAr ? 'اسم غير لائق' : 'Inappropriate name';
  String get roomReportReasonHarassment => isAr ? 'مضايقة' : 'Harassment';
  String get roomReportReasonSpam => isAr ? 'إزعاج أو سبام' : 'Spam';
  String get roomReportReasonOther => isAr ? 'سبب آخر' : 'Something else';
  String get roomReportNoteHint =>
      isAr ? 'تفاصيل إضافية (اختياري)' : 'Anything else to add? (optional)';
  String get roomReportSubmit => isAr ? 'إرسال البلاغ' : 'Send report';
  String get roomReportThanks => isAr
      ? 'وصلنا بلاغك. شكرًا لك.'
      : 'Report received. Thank you.';
  /// Offered right after a report, because someone who just reported a
  /// person almost always also wants to stop seeing them.
  String get roomReportAlsoBlock =>
      isAr ? 'احظر هذا العضو أيضًا' : 'Also block this member';
  String roomBlockedConfirm(String name) =>
      isAr ? 'تم حظر $name' : '$name is blocked';
  String roomUnblockedConfirm(String name) =>
      isAr ? 'تم إلغاء حظر $name' : '$name is unblocked';
  String get roomBlockExplain => isAr
      ? 'ما راح تشوف صفه في هذه الغرفة. ما راح يعرف، وتقدر تتراجع في أي وقت.'
      : "You won't see their row in this room. They aren't told, and you can undo it any time.";
  String roomBlockedHidden(int n) => isAr
      ? (n == 1 ? 'عضو محظور مخفي' : '$n أعضاء محظورين مخفيين')
      : (n == 1 ? '1 blocked member hidden' : '$n blocked members hidden');
  String get roomBlockedShow => isAr ? 'إظهار' : 'Show';

  /// Refusal shown when a name would be published to other people. Worded
  /// as a rule about the room rather than an accusation, since the most
  /// common trigger is someone testing what the field accepts.
  String get roomNameNotAllowed => isAr
      ? 'هذا الاسم ما ينفع هنا — غيره وحاول مرة ثانية.'
      : "That name can't be used here. Try a different one.";

  // ── Rooms Alive (live in-room reactions) ───────────────────────────────

  String roomReactionJoined(String name) =>
      isAr ? '$name انضم إلى الغرفة' : '$name just joined the room';
  String roomReactionFinished(String name) =>
      isAr ? '$name أنجز عادة اليوم!' : '$name just finished today!';

  // ── Monthly Story (shareable month-in-review) ──────────────────────────

  /// The first-completion reward float on a task row. ASCII digits and the
  /// Latin "XP" in both languages, matching every other stat in the app.
  String matrixRewardFloat(int xp, int gold) =>
      isAr ? '‎+$xp XP · +$gold ذهب' : '+$xp XP · +$gold gold';
  /// Shown in the add sheet after adding a task whose reminder anchors on a
  /// later day: under the default Today lens the new task is legitimately
  /// not visible, which read as the add having silently failed.
  String get matrixAddedForLater => isAr
      ? 'مجدولة ليوم لاحق — تظهر تحت «الكل»'
      : 'Scheduled for a later day — find it under "All"';

  String get monthlyStoryTitle => isAr ? 'قصة الشهر' : 'Monthly Story';
  String get monthlyStoryEmpty => isAr
      ? 'لا توجد بيانات لهذا الشهر بعد.'
      : "There's nothing recorded for this month yet.";
  String monthlyStoryHeadline(String month) =>
      isAr ? 'في $month، أنجزت:' : 'In $month, you completed:';
  String get monthlyStoryGreenSquares => isAr ? 'مربعًا أخضر' : 'green squares';
  String get monthlyStoryShareAction => isAr ? 'مشاركة قصتي' : 'Share My Story';
  String monthlyStoryShareText(
    String month,
    int greenSquares,
    int perfectDays,
    int levelUps,
    int achievements,
  ) =>
      isAr
          ? 'قصتي على Grow Daily، $month\n\nمربعات خضراء: $greenSquares\nأيام مثالية: $perfectDays\nترقيات مستوى: $levelUps\nإنجازات مفتوحة: $achievements\n\nأبني عادات أفضل، يومًا بعد يوم.'
          : 'My Grow Daily Story, $month\n\nGreen squares: $greenSquares\nPerfect days: $perfectDays\nLevel-ups: $levelUps\nAchievements unlocked: $achievements\n\nBuilding better habits, one day at a time.';

  // ── Year Record (per-habit yearly strips) ──────────────────────────────

  String get yearRecordTitle => isAr ? 'سجل السنة' : 'Year Record';
  String get yearRecordEmpty => isAr
      ? 'أضف عادة وابدأ التلوين — كل يوم تنجزه يظهر هنا.'
      : 'Add a habit and start coloring — every day you complete shows here.';
  /// ASCII digits in both languages, like every stat in the app.
  String yearRecordDaysCount(int n) => isAr ? '$n يوم' : '$n days';
  /// The quit-habit variant: a done day on a quit habit is a day RESISTED,
  /// and counting it as plain "days" undersells the win. التزام, not
  /// "نظيف" — commitment language, matching the app's no-shame register.
  String yearRecordCleanDaysCount(int n) =>
      isAr ? '$n يوم التزام' : '$n clean days';
  /// Collapsed section under the active habits. Archived habits keep their
  /// history, and this screen is the one place that history still shows
  /// after archiving — hidden by default so the past never crowds the
  /// present.
  String get yearRecordArchivedSection => isAr ? 'المؤرشفة' : 'Archived';

  // ── Month picker (shared: Monthly Story, any month-stepping screen) ────

  String get monthPickerTitle => isAr ? 'اختر الشهر' : 'Pick a month';
  String get weekPickerTitle => isAr ? 'اختر الأسبوع' : 'Pick a week';
  String get yearPickerTitle => isAr ? 'اختر السنة' : 'Pick a year';
  /// Screen-reader suffix on a month the free tier cannot open. The full
  /// explanation lives in [historyLockedBody], which the snackbar shows on
  /// tap; this only has to say that the cell is out of reach.
  String get monthPickerLocked => isAr ? 'مقفل' : 'Locked';

  /// Shown instead of the story when the dashboard failed to load, so a
  /// network failure can never be mistaken for "you did nothing this
  /// month" — which is what [monthlyStoryEmpty] would otherwise assert.
  String get monthlyStoryLoadFailed => isAr
      ? 'ما قدرنا نجيب بياناتك. تحقق من اتصالك وحاول مرة ثانية.'
      : "We couldn't load your data. Check your connection and try again.";

  // ── Level Prestige System ───────────────────────────────────────────────

  String get prestigeTitle => isAr ? 'مرتبة المستوى' : 'Level Prestige';
  String get prestigeSubtitle => isAr
      ? 'لقب يظهر بجانب اسمك، يُفتح تلقائيًا مع ارتقاء مستواك — بلا ذهب، وبلا اشتراك مميز.'
      : 'A title next to your name, unlocked automatically as you level up — no gold, no Premium.';
  String get prestigeAutoOption =>
      isAr ? 'تلقائي (الأعلى)' : 'Automatic (Highest)';
  String prestigeAutoOptionDesc(String currentTitle) =>
      isAr ? 'يعرض حاليًا: $currentTitle' : 'Currently showing: $currentTitle';
  String prestigeUnlockedAt(int level) =>
      isAr ? 'مفتوح منذ المستوى $level' : 'Unlocked at Level $level';
  String prestigeLockedUntil(int level) =>
      isAr ? 'يُفتح عند المستوى $level' : 'Unlocks at Level $level';

  // ── Category Breakdown (ProgressHubScreen) ─────────────────────────────

  String get categoryBreakdownTitle =>
      isAr ? 'توزيع الفئات' : 'Category Breakdown';

  // ── Reports hub (ProgressHubScreen's أسبوعي/شهري/سنوي tabs) ────────────
  //
  // The three segments replace what used to be two separate destinations
  // (Monthly Story, Year Record) plus this screen's own untabbed body. Kept
  // to one word each so all three fit the pill at any text scale, in both
  // languages.

  /// The reports destination's own title.
  ///
  /// Separate from [progressTitle] because they are separate screens again:
  /// the three period tabs answer "what did I do, and when", while التقدّم
  /// keeps the things that are not period-scoped at all (lifetime medals,
  /// lifetime category share, the newest notes). Stacking them in one
  /// scroll made the medals read like part of the month being viewed.
  String get reportsTitle => isAr ? 'التقارير' : 'Reports';

  String get reportsWeekly => isAr ? 'أسبوعي' : 'Weekly';
  String get reportsMonthly => isAr ? 'شهري' : 'Monthly';
  String get reportsYearly => isAr ? 'سنوي' : 'Yearly';

  /// The four numbers under every tab's grid.
  ///
  /// "نسبة الإنجاز" is measured against what the habits actually owed (see
  /// expectedCompletions), not against calendar days, so it stays honest
  /// for a habit scheduled twice a week.
  String get reportsRate => isAr ? 'نسبة الإنجاز' : 'Completion';
  String get reportsTotalDone => isAr ? 'المجموع' : 'Total done';

  /// Deliberately not "السلسلة": the app's real streak is an account-wide
  /// 80%-of-habits rule that survives rest days, and this is only the
  /// longest unbroken run INSIDE the period on screen. Two different
  /// numbers sharing one word would make the report look wrong.
  String get reportsLongestRun => isAr ? 'أطول تتابع' : 'Longest run';

  /// The ribbon on a habit card whose period was fully met.
  String get reportsPerfect => isAr ? 'كامل' : 'PERFECT';

  String get reportsHabitsSection => isAr ? 'عاداتك' : 'Your habits';

  /// Weekday rhythm block: the one thing on this screen nobody can work
  /// out for themselves by looking at a grid.
  String get reportsRhythmTitle => isAr ? 'إيقاع أيامك' : 'Your rhythm';
  /// Says WEEKDAY, not day, because "أفضل يوم" already appears three
  /// centimetres above it in the summary row meaning a specific date (18
  /// أغسطس). Two stats on one screen called the same thing, one answering
  /// with a date and one with a weekday, is the ambiguity this wording
  /// exists to remove.
  String reportsRhythmBest(String weekday) => isAr
      ? 'أفضل يوم في الأسبوع: $weekday'
      : 'Best weekday: $weekday';
  String reportsRhythmWorst(String weekday) => isAr
      ? 'أضعف يوم في الأسبوع: $weekday'
      : 'Weakest weekday: $weekday';

  /// Empty state per tab. Phrased about the PERIOD, never about the person:
  /// an empty August is a month with nothing in it yet, not a verdict.
  String get reportsEmptyWeek =>
      isAr ? 'ما فيه شيء مسجّل في هذا الأسبوع.' : 'Nothing recorded this week.';
  String get reportsEmptyMonth =>
      isAr ? 'ما فيه شيء مسجّل في هذا الشهر.' : 'Nothing recorded this month.';
  String get reportsEmptyYear =>
      isAr ? 'ما فيه شيء مسجّل في هذي السنة.' : 'Nothing recorded this year.';

  // ── One habit's own page ───────────────────────────────────────────────
  //
  // Four numbers, not eight. The obvious model for this screen puts Volume,
  // Total Volume, Daily Average and Overall Rate side by side, and a
  // "Daily Avg. 0.02" tells nobody anything at all. These are the questions
  // someone actually opens a habit to ask: how consistent am I lately, how
  // long have I kept it up, and how much have I done altogether.

  String get habitStatsThisPeriod => isAr ? 'هذا الشهر' : 'This month';
  String get habitStatsCurrentStreak => isAr ? 'السلسلة' : 'Streak';
  String get habitStatsBestStreak => isAr ? 'الأطول' : 'Best';

  /// The caption under the calendar, filled in when a day is tapped.
  ///
  /// A tap inside a sheet opening ANOTHER sheet is the kind of stacking that
  /// makes an app feel heavy, so a day answers in place instead: one line,
  /// naming the date and what was recorded on it.
  String habitStatsDayLine(String date, String state) => '$date · $state';

  /// Shown in that line before anything has been tapped, so the line is
  /// never an empty gap waiting to be understood.
  String get habitStatsDayHint => isAr
      ? 'اضغط أي يوم لتعرف ماذا سُجّل فيه.'
      : 'Tap any day to see what it recorded.';

  /// The day-detail sheet opened by tapping any cell in the weekly matrix.
  /// Passive on purpose. 'أنجزت' is read as either first person or a
  /// gendered second person depending on a vowel nobody types, so the same
  /// four letters address a man in one reading and speak for the reader in
  /// another. 'تم إنجاز' states what happened and belongs to nobody.
  String reportsDayDone(int n) => isAr ? 'تم إنجاز $n' : '$n done';
  String get reportsDayNothing =>
      isAr ? 'ما فيه إنجاز في هذا اليوم.' : 'Nothing done on this day.';
  String get reportsDayScheduled => isAr ? 'مطلوب' : 'Due';
  String get reportsDayNotDue => isAr ? 'غير مطلوب' : 'Not due';
}
