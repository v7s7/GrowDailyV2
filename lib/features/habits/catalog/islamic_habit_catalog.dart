import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' show Color;
import 'package:uuid/uuid.dart';

import '../models/habit_model.dart';

/// Immutable template from the pre-saved Islamic catalog.
/// Call [toHabitModel] to equip it to a user's account.
class IslamicHabitTemplate {
  final String id;
  final String name;
  final String description;
  // Arabic counterparts for the built-in catalog's [name]/[description] —
  // null for every user-created custom habit (those come from whatever the
  // user actually typed, in whichever language, so there's nothing to
  // translate) and populated for every entry in [IslamicHabitCatalog.
  // templates]. Read through [localName]/[localDescription] rather than
  // these directly, so a missing translation always falls back to the
  // English text instead of showing a blank.
  final String? nameAr;
  final String? descriptionAr;
  final String? cueAfter;
  final HabitCategory category;
  final HabitFrequencyType frequencyType;
  final int frequencyTarget;
  final List<int> scheduledWeekdays;
  final GoalType goalType;
  final ReductionType reductionType;
  final int? limitAmount;
  final LimitUnit? limitUnit;
  // Free-text label for LimitUnit.custom (e.g. "cigarettes", "swipes") —
  // null/empty for every other unit, which already have a stock translated
  // label (see S.limitUnitLabel). Without this, "custom" had no way to say
  // what it actually meant: a limit of 5 with unit "custom" just rendered
  // the literal word "Custom" everywhere instead of the thing being limited.
  final String? customUnitLabel;
  final bool hasTimer;
  final int? timerDurationSeconds;
  final int xpReward;
  final int goldReward;
  // A user-picked override for this one habit's icon color — 6 hex digits,
  // no leading '#' (e.g. 'E4819A'), or null to keep using whatever color
  // the render site would otherwise fall back to (categoryVisual's
  // category color in Grid, the done/goal-type accent in HabitCard). Stored
  // as a plain hex string rather than an ARGB int specifically so this
  // never has to touch Color's own (Flutter-version-sensitive) component
  // accessors — every read site just does
  // `Color(0xFF000000 | int.parse(iconColorHex, radix: 16))`.
  final String? iconColorHex;
  // How many minutes *before* the resolved cue moment (the picked clock
  // time, or prayer time + the global after-prayer offset) the reminder
  // should actually fire — 0 means "right at that moment," matching every
  // habit's behavior before this field existed, so old data with no stored
  // value is completely unaffected. Meaningless (and never surfaced in the
  // UI) for a freeform-text cue, since that has no resolved moment to count
  // back from in the first place. See NotificationService.scheduleSmartReminders.
  final int reminderLeadMinutes;

  /// The day this habit came into the user's life — creation day for a
  /// custom habit, activation day for a catalog habit (stamped in by
  /// habitListProvider from ActiveCatalogNotifier.activatedAt). Null for
  /// the const catalog templates themselves and for anything created
  /// before this field existed — null means "no birth date known," which
  /// [isScheduledFor] treats as always-existed, exactly the old behavior,
  /// so legacy habits change nothing. What this fixes: every surface that
  /// asks "was this habit scheduled on day X" (Grid squares, the heatmap
  /// day sheet, insights, the weekly recap, quit auto-clean, room credit)
  /// used to answer yes for days BEFORE the habit even existed, painting
  /// yesterday as a miss for a habit created this morning.
  final DateTime? createdAt;

  /// The day this habit was archived (deleted from the active list /
  /// deactivated) — null while still active. Symmetric with [createdAt]:
  /// together they bound the exact window a habit was real for, so a
  /// history surface that looks back across many days (Heatmap, Insights)
  /// can keep counting every day inside that window instead of losing the
  /// habit's whole past the instant it's removed from today's list. See
  /// [isScheduledFor] and allHabitsEverProvider (custom_habits_notifier.
  /// dart) for how this actually gets used — [habitListProvider] itself
  /// stays "active right now" only and never surfaces an archived habit,
  /// so nothing about today's Grid, Add sheet, or streak check changes.
  final DateTime? archivedAt;

  const IslamicHabitTemplate({
    required this.id,
    required this.name,
    required this.description,
    this.nameAr,
    this.descriptionAr,
    this.cueAfter,
    required this.category,
    required this.frequencyType,
    required this.frequencyTarget,
    this.scheduledWeekdays = const [],
    this.goalType = GoalType.build,
    this.reductionType = ReductionType.avoid,
    this.limitAmount,
    this.limitUnit,
    this.customUnitLabel,
    required this.hasTimer,
    this.timerDurationSeconds,
    required this.xpReward,
    required this.goldReward,
    this.iconColorHex,
    this.reminderLeadMinutes = 0,
    this.createdAt,
    this.archivedAt,
  });

  /// This habit's own icon color, or null to fall back to the category/
  /// state-driven default the call site already computes. Defensive about
  /// a malformed stored value (shouldn't happen — the picker only ever
  /// saves a validated 6-digit hex — but a bad manual Firestore edit
  /// shouldn't crash a render) by falling back to null instead of throwing.
  Color? get customColor {
    final hex = iconColorHex;
    if (hex == null || hex.length != 6) return null;
    final parsed = int.tryParse(hex, radix: 16);
    return parsed == null ? null : Color(0xFF000000 | parsed);
  }

  HabitModel toHabitModel(String uid) => HabitModel(
        id: const Uuid().v4(),
        uid: uid,
        name: name,
        description: description,
        cueAfter: cueAfter,
        category: category,
        frequencyType: frequencyType,
        frequencyTarget: frequencyTarget,
        scheduledWeekdays: scheduledWeekdays,
        goalType: goalType,
        reductionType: reductionType,
        limitAmount: limitAmount,
        limitUnit: limitUnit,
        customUnitLabel: customUnitLabel,
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
        if (scheduledWeekdays.isNotEmpty) 'scheduledWeekdays': scheduledWeekdays,
        'goalType': goalType.toJson(),
        if (goalType == GoalType.quit) 'reductionType': reductionType.toJson(),
        if (goalType == GoalType.quit &&
            reductionType == ReductionType.limit &&
            limitAmount != null)
          'limitAmount': limitAmount,
        if (goalType == GoalType.quit &&
            reductionType == ReductionType.limit &&
            limitUnit != null)
          'limitUnit': limitUnit!.toJson(),
        if (goalType == GoalType.quit &&
            reductionType == ReductionType.limit &&
            limitUnit == LimitUnit.custom &&
            customUnitLabel != null &&
            customUnitLabel!.trim().isNotEmpty)
          'customUnitLabel': customUnitLabel!.trim(),
        'hasTimer': hasTimer,
        if (timerDurationSeconds != null)
          'timerDurationSeconds': timerDurationSeconds,
        'xpReward': xpReward,
        'goldReward': goldReward,
        if (iconColorHex != null) 'iconColorHex': iconColorHex,
        if (reminderLeadMinutes > 0) 'reminderLeadMinutes': reminderLeadMinutes,
        // ISO string, not a Timestamp, on purpose: this exact map also
        // goes into Hive for guests (see CustomHabitsNotifier._saveGuest),
        // and Hive can't serialize Firestore Timestamps.
        if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
        if (archivedAt != null) 'archivedAt': archivedAt!.toIso8601String(),
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
        scheduledWeekdays: (d['scheduledWeekdays'] as List?)
                ?.whereType<int>()
                .where((d) => d >= DateTime.monday && d <= DateTime.sunday)
                .toList() ??
            const [],
        goalType: GoalType.fromJson(d['goalType'] as String?),
        reductionType: ReductionType.fromJson(d['reductionType'] as String?),
        limitAmount: d['limitAmount'] as int?,
        limitUnit: d['limitUnit'] == null
            ? null
            : LimitUnit.fromJson(d['limitUnit'] as String?),
        customUnitLabel: d['customUnitLabel'] as String?,
        hasTimer: d['hasTimer'] as bool? ?? false,
        timerDurationSeconds: d['timerDurationSeconds'] as int?,
        xpReward: d['xpReward'] as int? ?? 20,
        goldReward: d['goldReward'] as int? ?? 8,
        iconColorHex: d['iconColorHex'] as String?,
        reminderLeadMinutes: d['reminderLeadMinutes'] as int? ?? 0,
        createdAt: DateTime.tryParse(d['createdAt'] as String? ?? ''),
        archivedAt: DateTime.tryParse(d['archivedAt'] as String? ?? ''),
      );

  /// Whether this habit exists-and-is-due on [day]: never before its
  /// birth date (see [createdAt] — a habit created this morning was not
  /// "missed" yesterday), never after it was archived (see [archivedAt] —
  /// the archive day itself still counts, only days strictly after it
  /// don't, so archiving a habit today can't retroactively excuse today's
  /// own "all habits done" streak check), and on scheduled weekdays only
  /// when a specific schedule is set. This is the single seam every
  /// surface reads, so both rules hold everywhere at once.
  bool isScheduledFor(DateTime day) {
    final born = createdAt;
    if (born != null &&
        day.isBefore(DateTime(born.year, born.month, born.day))) {
      return false;
    }
    final died = archivedAt;
    if (died != null &&
        day.isAfter(DateTime(died.year, died.month, died.day))) {
      return false;
    }
    return scheduledWeekdays.isEmpty || scheduledWeekdays.contains(day.weekday);
  }

  /// A full copy with [createdAt] swapped in — how habitListProvider
  /// stamps a const catalog template with its activation date without the
  /// template itself carrying per-user state.
  IslamicHabitTemplate withCreatedAt(DateTime? date) => IslamicHabitTemplate(
        id: id,
        name: name,
        description: description,
        nameAr: nameAr,
        descriptionAr: descriptionAr,
        cueAfter: cueAfter,
        category: category,
        frequencyType: frequencyType,
        frequencyTarget: frequencyTarget,
        scheduledWeekdays: scheduledWeekdays,
        goalType: goalType,
        reductionType: reductionType,
        limitAmount: limitAmount,
        limitUnit: limitUnit,
        customUnitLabel: customUnitLabel,
        hasTimer: hasTimer,
        timerDurationSeconds: timerDurationSeconds,
        xpReward: xpReward,
        goldReward: goldReward,
        iconColorHex: iconColorHex,
        reminderLeadMinutes: reminderLeadMinutes,
        createdAt: date,
      );

  /// A full copy with both [createdAt] and [archivedAt] swapped in — how
  /// allHabitsEverProvider (custom_habits_notifier.dart) stamps a const
  /// catalog template with the exact window a past activation covered.
  /// Kept separate from [withCreatedAt] rather than extending it, so every
  /// existing [withCreatedAt] call site (habitListProvider's "active right
  /// now" list) is guaranteed untouched by this addition.
  IslamicHabitTemplate withDates({DateTime? createdAt, DateTime? archivedAt}) =>
      IslamicHabitTemplate(
        id: id,
        name: name,
        description: description,
        nameAr: nameAr,
        descriptionAr: descriptionAr,
        cueAfter: cueAfter,
        category: category,
        frequencyType: frequencyType,
        frequencyTarget: frequencyTarget,
        scheduledWeekdays: scheduledWeekdays,
        goalType: goalType,
        reductionType: reductionType,
        limitAmount: limitAmount,
        limitUnit: limitUnit,
        customUnitLabel: customUnitLabel,
        hasTimer: hasTimer,
        timerDurationSeconds: timerDurationSeconds,
        xpReward: xpReward,
        goldReward: goldReward,
        iconColorHex: iconColorHex,
        reminderLeadMinutes: reminderLeadMinutes,
        createdAt: createdAt,
        archivedAt: archivedAt,
      );

  /// Locale-aware display name — mirrors [HabitPlan.localName]. Falls back
  /// to [name] whenever [nameAr] is missing or blank, which is exactly the
  /// case for every user-created custom habit (no Arabic counterpart to
  /// fall back *to* would mean silently showing nothing).
  String localName(bool isAr) =>
      isAr && nameAr != null && nameAr!.trim().isNotEmpty ? nameAr! : name;

  /// Locale-aware description — mirrors [HabitPlan.localDesc].
  String localDescription(bool isAr) => isAr &&
          descriptionAr != null &&
          descriptionAr!.trim().isNotEmpty
      ? descriptionAr!
      : description;

  /// Display text for [limitUnit] — the free-text [customUnitLabel] when
  /// the unit is [LimitUnit.custom] and one was actually typed in ("5
  /// cigarettes" instead of "5 Custom"), otherwise [fallback] (the caller's
  /// translated stock label, e.g. S.limitUnitLabel('cups') → "cups").
  String unitLabel(String fallback) =>
      limitUnit == LimitUnit.custom &&
              customUnitLabel != null &&
              customUnitLabel!.trim().isNotEmpty
          ? customUnitLabel!.trim()
          : fallback;

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
      nameAr: 'ورد القرآن اليومي',
      descriptionAr: 'اقرأ صفحة واحدة على الأقل من القرآن كل يوم',
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
      nameAr: 'حفظ القرآن',
      descriptionAr: 'احفظ وراجع آيات من القرآن الكريم',
      // 'your quiet study block' was pure freeform text — HabitCue only
      // localizes its ~12 recognized presets (see habit_cue.dart), so this
      // showed as literal English even in Arabic mode. 'work_block'
      // ("Work block" / "وقت العمل") is the closest recognized preset to
      // "a dedicated quiet slot," and gets full EN/AR display for free.
      cueAfter: 'work_block',
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
      nameAr: 'أذكار الصباح',
      descriptionAr: 'اقرأ أذكار الصباح بعد صلاة الفجر',
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
      nameAr: 'أذكار المساء',
      descriptionAr: 'اقرأ أذكار المساء بعد صلاة العصر',
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
      nameAr: 'صلاة التهجد',
      descriptionAr: 'قم قبل الفجر لأداء صلاة الليل التطوعية',
      // 'waking before Fajr' was freeform (see quran_memorization's note
      // above) — 'fajr' is a recognized HabitCue preset and reads just as
      // naturally for a habit that's anchored to right before that prayer.
      cueAfter: 'fajr',
      // Tahajjud's window CLOSES at Fajr — a reminder at Fajr itself is
      // already too late. 45 minutes before Fajr lands inside the last
      // third of the night (its sunnah time) with enough room to actually
      // pray. See NotificationService.scheduleSmartReminders' lead-time
      // handling.
      reminderLeadMinutes: 45,
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
      nameAr: 'الالتزام بالرياضة',
      descriptionAr: 'حافظ على لياقتك — جسمك أمانة',
      // Late afternoon is both the physiological strength/performance peak
      // and the Gulf's own pre-Maghrib gym hour — anchoring to Asr gives a
      // real prayer-timed reminder instead of none at all.
      cueAfter: 'asr',
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
      nameAr: 'صيام الاثنين والخميس',
      descriptionAr: 'اتبع سنة الصيام يومي الاثنين والخميس',
      // Pinned to the actual sunnah days — before this, the habit showed
      // up (and could be checked off) any day of the week, contradicting
      // its own name. Now Grid/Today only present it on Mon + Thu.
      scheduledWeekdays: [DateTime.monday, DateTime.thursday],
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
      nameAr: 'صدقة يومية',
      descriptionAr: 'تصدّق كل يوم — حتى الابتسامة صدقة',
      // Morning giving is the timing with actual textual basis — the two
      // angels' daily dua for the one who gives comes each morning (صحيح
      // البخاري ١٤٤٢) — and it front-loads the habit before the day fills up.
      cueAfter: 'fajr',
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
      nameAr: 'النوم قبل منتصف الليل',
      descriptionAr: 'احمِ صلاة فجرك بالنوم قبل منتصف الليل',
      // A fixed 10:30 PM wind-down reminder, not an Isha anchor — Isha
      // drifts seasonally (as early as ~7 PM in winter) while "before
      // midnight" doesn't, and sleep-hygiene guidance is a consistent
      // wind-down cue ~1 hour before the target bedtime.
      cueAfter: 'custom_time:22:30',
      category: HabitCategory.sleep,
      frequencyType: HabitFrequencyType.daily,
      frequencyTarget: 1,
      hasTimer: false,
      xpReward: 15,
      goldReward: 5,
    ),
    // ── Marriage Preparation (pre-marriage — see the plan's own comment
    //    in habit_plans.dart for the prophetic basis) ────────────────────
    IslamicHabitTemplate(
      id: 'marriage_dua',
      name: 'Dua for a Righteous Spouse',
      description: 'Ask Allah sincerely to grant you a righteous spouse',
      nameAr: 'دعاء الزوج الصالح',
      descriptionAr: 'ادعُ الله بصدق أن يرزقك شريك حياة صالح',
      cueAfter: 'Isha',
      category: HabitCategory.custom,
      frequencyType: HabitFrequencyType.daily,
      frequencyTarget: 1,
      hasTimer: false,
      xpReward: 15,
      goldReward: 5,
    ),
    IslamicHabitTemplate(
      id: 'marriage_savings',
      name: 'Save for Your Marriage',
      description:
          'Put something aside for the mahr and married life, however small',
      nameAr: 'وفّر لزواجك',
      descriptionAr: 'حط مبلغ جانبًا للمهر وبيت الزوجية، حتى لو شي بسيط',
      category: HabitCategory.money,
      frequencyType: HabitFrequencyType.weekly,
      frequencyTarget: 1,
      hasTimer: false,
      xpReward: 25,
      goldReward: 10,
    ),
    IslamicHabitTemplate(
      id: 'lower_gaze',
      name: 'Guard Your Gaze',
      description: 'Lower your gaze and protect your chastity today',
      nameAr: 'غض البصر',
      descriptionAr: 'غض بصرك وصُن نفسك اليوم',
      // A quit-style habit (avoid, all day) rather than a one-tap task —
      // success is the *absence* of something, so it gets the full quit
      // flow for free: the emerald "stayed on track" pill, the quiet slip
      // log, and the evening check-in (see scheduleQuitCheckIns).
      goalType: GoalType.quit,
      category: HabitCategory.faith,
      frequencyType: HabitFrequencyType.daily,
      frequencyTarget: 1,
      hasTimer: false,
      xpReward: 20,
      goldReward: 8,
    ),
    IslamicHabitTemplate(
      id: 'marriage_gratitude',
      name: 'Gratitude Note to Spouse',
      description: 'Write or say one thing you appreciate about them today',
      nameAr: 'رسالة امتنان لزوجك',
      descriptionAr: 'اكتب أو قل شيئًا واحدًا تقدّره فيهم اليوم',
      // Evening: the day has actually happened by then, so there's
      // something real to be grateful about (a morning cue would ask
      // for gratitude about a day that hasn't occurred yet).
      cueAfter: 'evening',
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
      nameAr: 'اقرأ عن الزواج',
      descriptionAr: 'تعرّف على حقوق وآداب الزواج في الإسلام',
      // Reading slots naturally into the pre-sleep wind-down (and pairs
      // with sleep_schedule's own 10:30 PM nudge to get off the phone).
      cueAfter: 'before_sleep',
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
      nameAr: 'لقاء أسبوعي مع زوجك',
      descriptionAr: 'اجلسا معًا وتحدثا بصراحة عن أسبوعكما',
      // Pinned to Friday — the Gulf weekend's family day, when both
      // people are actually home and unhurried. Before this it floated
      // across the whole week with no anchor at all.
      scheduledWeekdays: [DateTime.friday],
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
      nameAr: 'فترة تركيز عميق',
      descriptionAr: 'فترة عمل مركّزة بلا مقاطعات، والهاتف بعيدًا',
      cueAfter: 'work_block',
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
      nameAr: 'تفريغ صندوق الوارد',
      descriptionAr: 'راجع وأنهِ كل رسالة في بريدك الوارد',
      // End of the workday, not morning — triaging first thing invites
      // the inbox to set the day's agenda, the opposite of Deep Focus's
      // whole point.
      cueAfter: 'after_work_school',
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
      nameAr: 'خطط ليوم الغد الليلة',
      descriptionAr: 'اكتب أهم 3 أولويات لغدك قبل النوم',
      cueAfter: 'before_sleep',
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
      nameAr: 'بلا هاتف في أول ساعة',
      descriptionAr: 'بدون شاشات في أول ساعة بعد الاستيقاظ',
      cueAfter: 'morning',
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
      nameAr: 'دش بارد',
      descriptionAr: 'أنهِ استحمامك بـ 60 ثانية على الأقل من الماء البارد',
      cueAfter: 'morning',
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
      nameAr: 'استيقظ قبل الساعة 6 صباحًا',
      descriptionAr: 'انهض قبل الساعة 6 صباحًا واخرج من الفراش مباشرة',
      // A fixed 5:30 AM reminder — the one habit whose whole promise IS a
      // clock time, so it gets one, with a half hour of margin before 6.
      cueAfter: 'custom_time:05:30',
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
      nameAr: 'بدون سكر مضاف',
      descriptionAr: 'اقضِ يومك كاملاً بدون أي سكر مضاف',
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
