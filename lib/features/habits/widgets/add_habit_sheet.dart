import 'dart:async';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../core/constants/game_constants.dart';
import '../../../core/extensions/datetime_ext.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/alarm_choice_provider.dart';
import '../../../core/services/alarm_service.dart';
import '../../../core/services/health_steps_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/prayer_times_service.dart';
import '../../../core/theme/game_theme.dart';
import '../../../core/utils/step_habit_detector.dart';
import '../../../core/utils/western_digits.dart';
import '../../../shared/widgets/category_icon.dart';
import '../../../shared/widgets/habit_limit_gate.dart';
import '../../../shared/widgets/reminder_limit_gate.dart';
import '../../../shared/widgets/victory_burst.dart';
import '../../settings/models/notification_settings.dart';
import '../../settings/notifiers/notification_settings_notifier.dart';
import '../../settings/widgets/city_search_sheet.dart';
import '../catalog/habit_ideas.dart';
import '../catalog/habit_plans.dart' show activeCatalogProvider;
import '../catalog/islamic_habit_catalog.dart';
import '../notifiers/catalog_overrides_notifier.dart';
import '../models/habit_cadence.dart';
import '../models/habit_cue.dart';
import '../models/habit_reminder_stack.dart';
import '../models/habit_category_guess.dart';
import '../models/habit_model.dart';
import '../models/own_category.dart';
import '../../dashboard/notifiers/dashboard_notifier.dart';
import '../../premium/notifiers/premium_notifier.dart';
import '../../mascot/sprout.dart';
import '../../rooms/notifiers/rooms_notifier.dart';
import '../notifiers/custom_habits_notifier.dart';
import '../notifiers/newly_added_habit_provider.dart';
import '../../../shared/widgets/choice_chip_grid.dart';
import 'habit_color_picker.dart';
import 'habit_offset_sheet.dart';
import 'reminder_kind_card.dart';
import 'habit_ideas_page.dart';
import 'own_category_sheet.dart';
import 'quiet_hours_conflict_dialog.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../../shared/widgets/overlay_notice.dart';
import '../../../shared/widgets/reminder_style_choice.dart';

part 'add_habit_sheet_small_widgets.dart';

enum _CueRelation { after, before }

/// The three ways to anchor a habit's timing. Kept as three clearly separate
/// modes (rather than one flat mixed list of chips) so "when" is always one
/// deliberate choice, not a scavenger hunt through prayers, dayparts, and a
/// time picker all jumbled together.
enum _TimingMode { time, prayer, text }

class AddHabitSheet extends ConsumerStatefulWidget {
  final IslamicHabitTemplate? existing;

  /// When true, renders just the form content + footer — no drag handle,
  /// no rounded card, no background. Used inside [AddHabitHub]'s "Add
  /// Goal" tab, which already supplies that chrome once for all tabs.
  /// Standalone (the default) keeps the full self-contained sheet used for
  /// editing an existing habit.
  final bool embedded;

  /// Fires with the form's step index whenever it changes (0 = the habit,
  /// 1 = how often, 2 = the reminder).
  ///
  /// [AddHabitHub] listens so it can hide the Plans / Add Goal switcher once
  /// the user has committed to Add Goal and moved on — past that point the
  /// choice is already made and the pills are just noise above the form.
  final ValueChanged<int>? onStepChanged;

  /// Fires when the ideas door's Plans card is tapped. [AddHabitHub] passes
  /// this so the card can switch the hub to its Plans tab; standalone there
  /// is no Plans tab, and the card is not drawn.
  final VoidCallback? onBrowsePlans;

  /// Fires with a plan's id when one is picked on the ideas page.
  /// [AddHabitHub] passes this so the plan opens on its Plans tab; without
  /// it [onBrowsePlans] is called, and with neither the ideas page shows no
  /// plans.
  final ValueChanged<String>? onOpenPlan;

  /// Fires with the Build / Quit choice whenever it changes, and once on
  /// mount. [AddHabitHub] listens so its own heading can follow: the switch
  /// is inside this form, but the title that names what is being made sits
  /// above it in the host, and it used to keep saying «إضافة عادة» through
  /// both steps of building a quit goal.
  final ValueChanged<GoalType>? onGoalTypeChanged;

  const AddHabitSheet({
    super.key,
    this.existing,
    this.embedded = false,
    this.onStepChanged,
    this.onBrowsePlans,
    this.onOpenPlan,
    this.onGoalTypeChanged,
  });

  @override
  ConsumerState<AddHabitSheet> createState() => _AddHabitSheetState();
}

class _AddHabitSheetState extends ConsumerState<AddHabitSheet> {
  static const _broadCategories = [
    HabitCategory.faith,
    HabitCategory.health,
    HabitCategory.learning,
    HabitCategory.focus,
    HabitCategory.sleep,
    HabitCategory.money,
    HabitCategory.mind,
    HabitCategory.social,
    HabitCategory.custom,
  ];

  static const _prayerKeys = ['fajr', 'dhuhr', 'asr', 'maghrib', 'isha'];

  final _nameCtrl = TextEditingController();
  final _cueCtrl = TextEditingController();
  final _limitCtrl = TextEditingController();
  /// The quit limit's unit box. Typed, not picked (canvas v8, Aziz
  /// 2026-09-30: "custom only no need for chips"); [_typedUnit] reads it back
  /// into a [LimitUnit] on save.
  final _customUnitCtrl = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  GoalType _goalType = GoalType.build;
  HabitCategory _category = HabitCategory.custom;

  /// A category of the person's own, picked or made in this sheet (see
  /// OwnCategory). Set only alongside [_category] custom; picking one of the
  /// app's categories clears it.
  OwnCategory? _ownCategory;

  /// Categories made in this sheet and not yet saved with a habit, so the
  /// row keeps offering one after a switch to another category.
  final List<OwnCategory> _madeHere = [];

  /// Daily / Weekly / Specific days, or null while nobody has picked one.
  ///
  /// It used to open on Daily, with the per-day stepper already under it. A
  /// pre-selected chip is an answer the form gave itself, and this one is
  /// not cosmetic: cadence decides which days the Grid asks about, what the
  /// streak counts, and which days a room scores. So the chips open unlit,
  /// everything under them stays away until one is tapped, and Create is
  /// held back until then (see [_canCreate]) rather than saving a default
  /// nobody chose.
  ///
  /// Deliberately nullable rather than a "was it touched" flag beside a
  /// still-Daily field: nothing in this file dereferences it (every read is
  /// an `==`), so null costs no null-checks in the widgets, and the two
  /// places that would write it to storage stop compiling until they are
  /// made to face the unanswered case. A flag next to a live default fails
  /// the other way, silently.
  HabitFrequencyType? _freqType;
  int _freqTarget = 1;

  /// The per-day count, kept apart from [_freqTarget] on purpose.
  ///
  /// One stored field, `frequencyTarget`, means two unrelated things: times
  /// per DAY while the habit is daily, times per WEEK while it is weekly (see
  /// IslamicHabitTemplate.effectiveDailyTarget). Editing both through the one
  /// variable is how "5 times a week" quietly becomes "5 times a day" on a
  /// single chip tap. So the stepper owns this, the weekly dropdown owns
  /// _freqTarget, and only _submit ever folds them together.
  int _timesPerDay = 1;
  Set<int> _selectedWeekdays = {};

  /// The «قبل | بعد» answer written into a custom text cue's own words
  /// («قبل العمل», see [_cueWithRelation]). Seeded from the stored cue and
  /// changed only by a tap on custom text's chips, the one mode that draws
  /// them. A reminder's side never writes it: that is [_reminderLean].
  _CueRelation _cueRelation = _CueRelation.after;
  ReductionType _reductionType = ReductionType.avoid;
  bool _hasName = false;
  bool _didPickCategory = false;
  bool _cueLabelResolved = false;
  // This habit's own icon color, or null to keep using whatever color the
  // render site falls back to on its own (category/done-state driven) — see
  // IslamicHabitTemplate.customColor's doc comment.
  String? _iconColorHex;

  // ── Steps link (walking habits) ────────────────────────────────────────
  // Whether the typed name currently reads as walking (see
  // step_habit_detector.dart) — controls the link card's visibility, so
  // the offer appears the moment "مشي" or "walkk" lands in the field and
  // disappears if the name stops being about walking.
  bool _nameLooksWalkish = false;
  // The toggle on that card. ON by default for a name the detector reads as
  // walking, and that default is the whole point of the card: it grants
  // nothing (the OS permission is still asked at Save, see
  // _confirmStepsAccess) and it is shown, switched on, right under the name
  // being typed. What it replaces was worse than a dark pattern in the
  // other direction: the card rendered below the fold, off, and somebody
  // who typed "walking" and pressed the primary button lost the feature
  // without ever knowing the app had offered it.
  //
  // An existing habit that is already linked keeps that, and one that is
  // not gets the same offer a new habit gets, because "unlinked" and "never
  // asked" are the same stored value. See [_stepLinkTouched].
  bool _stepLinkEnabled = false;
  // Whether the link state is somebody's own decision rather than this
  // sheet's default: the switch was tapped, or the habit arrived already
  // carrying an answer. Once true, typing in the name field stops moving
  // the switch.
  bool _stepLinkTouched = false;
  // Locates the steps card so [_revealStepCard] can scroll it fully into
  // view the moment it appears, which on a phone with the keyboard open is
  // the difference between seeing it and not.
  final GlobalKey _stepCardKey = GlobalKey();
  int _stepGoal = _defaultStepGoal;
  // Once the person picks a goal chip, a number parsed out of the name
  // stops overwriting their choice.
  bool _stepGoalTouched = false;
  /// Whether the goal is being typed rather than picked from the presets.
  ///
  /// The three presets answer for most people in one tap, and answered for
  /// nobody else at all: before this there was no way to ask for 7,500, and a
  /// goal that arrived from the name ("امشي ٨٠٠٠ خطوة") could be seen but
  /// never adjusted. Turning it on keeps whatever number is already chosen,
  /// so the field opens on the person's own goal rather than on a blank.
  bool _stepGoalCustom = false;
  final _stepGoalCtrl = TextEditingController();
  static const _defaultStepGoal = 6000;
  static const _stepGoalPresets = [3000, 6000, 10000];
  /// The range a daily step goal is allowed to be, matching
  /// [parseStepGoal]'s own sanity check so a typed goal and a goal read out
  /// of the name can never disagree about what counts as plausible.
  static const _stepGoalMin = 100;
  static const _stepGoalMax = 100000;

  // ── Three steps (canvas v8, built 2026-10-01) ───────────────────────────
  //
  // 0 «العادة»: the name, typed first. 1 «كم مرة»: one question in one row.
  // 2 «التذكير (اختياري)»: a clock time or a prayer, or nothing, and the
  // habit is added there. Users had found the old two-step form "too
  // complex": its second page grew after every tap, up to nine choices with
  // one of them required.
  int _step = 0;

  /// An edit opens on an overview of the three answers (canvas board
  /// "Edit a habit"), and each row opens its step. Saving happens there.
  bool _editOverview = false;

  /// Every step change goes through here so [AddHabitSheet.onStepChanged]
  /// stays in sync.
  void _goToStep(int step, {required bool forward}) {
    if (_step == step && !_editOverview) return;
    setState(() {
      _forward = forward;
      _step = step;
      _editOverview = false;
    });
    _toTop();
    _settleAfterStepChange();
    widget.onStepChanged?.call(step);
  }

  /// Back to the edit overview from one of its step pages.
  void _backToOverview() {
    setState(() {
      _forward = false;
      _editOverview = true;
    });
    _toTop();
    _settleAfterStepChange();
  }

  /// True while a new step is still sliding in, when the footer button
  /// ignores taps.
  ///
  /// That button keeps its place from one step to the next and changes what
  /// it does: «متابعة» on step 2 becomes «أضف العادة» on step 3, and «تم» on
  /// an edit's step page becomes «احفظ التغييرات». So the second tap of a
  /// double tap on «متابعة» landed on «أضف العادة» and saved the habit before
  /// its reminder step had ever been seen. A tap during the slide was never
  /// meant for the page that is still arriving.
  bool _stepSettling = false;
  Timer? _settleTimer;

  void _settleAfterStepChange() {
    _stepSettling = true;
    _settleTimer?.cancel();
    // The step switcher's own length (GameMotion.relaxed), and a little
    // over, so the page is in place before it takes a tap.
    _settleTimer = Timer(
      GameMotion.relaxed + const Duration(milliseconds: 80),
      () => _stepSettling = false,
    );
  }

  /// True while [_submit] runs. It can wait on the step-count permission
  /// (a platform call, every time for a walking habit) and on the
  /// quiet-hours question before it saves, and nothing stopped a second tap
  /// in that wait: it ran the whole submit again, saved a second copy of the
  /// habit (both passing the free habit limit, so an account could go one
  /// over), and its own Navigator.pop then closed whatever sat under the
  /// sheet. One submit at a time.
  bool _submitting = false;

  /// Each step opens at its top, not at the scroll offset the last one was
  /// left at.
  void _toTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  // Direction of the last step change, so the transition slides the right
  // way (forward = new content enters from the trailing edge, back = from
  // the leading edge) instead of always sliding one direction.
  bool _forward = true;

  /// Set once an idea from the ideas page has filled the form, so step 2
  /// says the answers are a suggestion to change, not a choice made.
  bool _fromIdea = false;

  /// Whether «تغيير» on the category line has opened the category row.
  bool _categoryRowOpen = false;

  // ── The reminder (step 3) ─────────────────────────────────────────────

  /// Which kind of moment, or null for none: the step's resting answer, so
  /// the mode a habit ends up with is always one somebody chose rather than
  /// one the category guessed on their behalf. Text is never offered any
  /// more; it only arrives with an edited habit that already has words.
  _TimingMode? _timingMode;
  String? _selectedPrayer;

  /// A prayer per time, for a habit counted several times a day (Aziz,
  /// 2026-10-01: "30 min before fajr, and 30 after fajr"): each row's prayer
  /// and signed shift, or null while that row has none.
  ///
  /// Index 0 is never read. The FIRST row is [_selectedPrayer] with
  /// [_reminderOffset], the one prayer a habit counted once a day has, so
  /// stepping 1 → 3 → 1 times a day keeps one first prayer rather than two
  /// answers to the same question. Grows but never shrinks, like
  /// [_pickedTimes]: rows past the count come back when it does.
  List<PrayerSlot?> _prayerRows = [null];
  /// One picked time per occurrence of a habit counted several times a day,
  /// index-aligned with the reminder slot each will own.
  ///
  /// Grows but never SHRINKS. Stepping the count from 4 down to 2 and back up
  /// must return the two times that were already set rather than two empty
  /// rows, which is the same expectation times_per_day_test already pins for
  /// the count itself. Reads always take `_effectiveTimeCount` from the front.
  List<TimeOfDay?> _pickedTimes = [null];

  /// The signed shift each occurrence's reminder fires at, index-aligned with
  /// [_pickedTimes]. Only ever read while the habit is multi-time: a
  /// single-time habit keeps using the one _reminderOffset it always has.
  List<int> _pickedOffsets = [0];

  /// Which row currently has its before/after chips open, or -1.
  ///
  /// One at a time. Six chips per row times four rows is a wall, and the
  /// person is only ever adjusting one occurrence at a moment.
  int _openOffsetRow = -1;

  /// The first picked time — what every single-time reader meant by
  /// `_pickedTime` before this became a list.
  TimeOfDay? get _pickedTime => _pickedTimes.isEmpty ? null : _pickedTimes.first;

  /// How many times this form is actually collecting.
  ///
  /// The stepper only governs Daily-with-no-specific-days (see
  /// _frequencySection); every other cadence hides it but does NOT change
  /// _timingMode, so without this clamp switching to Weekly would keep writing
  /// N times a habit has no way to express.
  /// Whether this habit is collecting more than one time a day — the state in
  /// which only the clock-time cue can express what is being asked for.
  bool get _isMultiTime => _effectiveTimeCount > 1;

  int get _effectiveTimeCount =>
      _freqType == HabitFrequencyType.daily && _selectedWeekdays.isEmpty
          ? _dailyTargetInRange
          : 1;

  /// The times actually filled in, in slot order — what gets saved.
  List<TimeOfDay> get _filledTimes => [
        for (var i = 0; i < _effectiveTimeCount && i < _pickedTimes.length; i++)
          if (_pickedTimes[i] case final TimeOfDay t) t,
      ];
  // Set while _ensureLocationForPrayerCue's GPS request is in flight — lets
  // _reminderTimePreview show "Finding your location…" instead of the
  // static "no location" line for that brief window, and guards against
  // firing a second detect if a prayer pill gets tapped again before the
  // first one resolves.
  bool _detectingLocation = false;

  /// Per-habit "Allow anyway" for a reminder that lands inside quiet hours
  /// — see _quietHoursWarning. False until someone is actually warned and
  /// chooses to keep it.
  bool _ignoreQuietHours = false;

  /// What quiet hours were silencing when this sheet opened, as minutes of
  /// the day: what an edit already knew about. Saving asks about quiet hours
  /// ([_askAboutQuietHours]) only for a moment not in here, so an edit that
  /// leaves the reminder alone does not ask again. Empty for a new habit.
  Set<int> _quietAtOpen = const {};

  /// Set once the line under the time («اسمح به على أي حال» / «احترم ساعات
  /// الهدوء») is tapped. That was the answer, and saving does not ask again.
  bool _quietHoursAnswered = false;

  /// Notification or alarm, see IslamicHabitTemplate.alarm. Off until the
  /// person picks alarm AND the platform grants it; see [_setAlarm].
  bool _alarm = false;

  // ── Reminder offset: signed minutes from the resolved time or prayer
  // moment to when the notification actually fires. Negative is before, 0 is
  // on time, positive is after. Only meaningful for Time and Prayer modes,
  // since Custom Text has no resolved moment to offset from.
  //
  // These presets are the per-occurrence chips a multi-time row opens (see
  // _timeRow), ordered earliest to latest so the grid reads like a timeline
  // with «في الوقت» in the middle. A single time and a prayer no longer use
  // them: their reminders are rows that open the offset sheet (see
  // _reminderOffsetSection), whose presets live in reminder_copy.dart.
  static const _offsetPresets = [-30, -15, 0, 15, 30];
  /// The habit-level shift, as SIGNED minutes. One number, one home.
  ///
  /// Custom entry used to live as a magnitude in a text controller plus a
  /// direction in a bool, recombined on every read — two pieces of state for
  /// one fact, able to disagree, with a typed "-" fighting the toggle for the
  /// sign. The custom sheet returns signed minutes, so this is now simply the
  /// value. Only ever read for a single-time habit: with several times the
  /// shifts live per occurrence inside the cue (see HabitCue.offsetsAreOwn).
  int _reminderOffset = 0;

  /// The shifts stacked ON TOP of [_reminderOffset] — the same set the
  /// Tasks sheet calls extra reminders, asked here about a habit's one
  /// anchor. Empty for every habit with a single reminder, which is the
  /// default and what the free tier keeps.
  ///
  /// [_reminderOffset] deliberately stays the primary and is never a member:
  /// it is what every stored habit, and notification slot 0, already mean by
  /// "the reminder" (see IslamicHabitTemplate.extraReminderOffsets). Removing
  /// the primary promotes the earliest of these into its place rather than
  /// renumbering the whole stack.
  Set<int> _extraOffsets = {};

  /// Every shift this habit would fire at, earliest first — the primary plus
  /// the stack. Never empty: a habit always has at least one reminder, which
  /// is what [_toggleReminderOffset] refuses to let anyone delete.
  List<int> get _allReminderOffsets =>
      ({_reminderOffset, ..._extraOffsets}.toList()..sort());

  /// The reminders as one stack, for the rules that read them together.
  HabitReminderStack get _reminderStack =>
      HabitReminderStack(primary: _reminderOffset, extras: _extraOffsets);

  /// The side a prayer habit's offset sheet leans to when the reminders
  /// cannot say: every one on time, or a Premium stack on both sides.
  /// [_followReminderSide] keeps it on the side the reminders were last on,
  /// or the side last chosen in the sheet, which is the one place a prayer
  /// reminder's side is chosen (see [_prayerModeContent]). «بعد» until then.
  ///
  /// Its own field, because [_cueRelation] is saved into a custom text cue.
  /// While the two were one, an edit in the offset sheet rewrote the typed
  /// cue unseen: «العمل» switched to a prayer, its reminder set to 15 before
  /// and switched back saved «قبل العمل» under a field reading «العمل», and
  /// «قبل العمل» with 15 after saved «العمل». A prayer habit whose reminders
  /// are all before also reopened with قبل lit in custom text. For the same
  /// reason a tap on custom text's chips does not write this: the «قبل» in
  /// «قبل العمل» is not the side of a prayer's reminder.
  _CueRelation _reminderLean = _CueRelation.after;

  /// The side the offset sheet opens on for a reminder with no side of its
  /// own (on time, or being added). In prayer mode that is the side the
  /// other reminders are on, so one added beside 15 before Fajr opens on
  /// «قبل». With no single side to follow (all on time, or a Premium stack
  /// on both sides) it is [_reminderLean], which on a habit that has had no
  /// side yet is «بعد»: one tap on 15 saves 15 after. A clock time keeps
  /// opening on «قبل».
  bool get _sheetLeanAfter =>
      _timingMode == _TimingMode.prayer &&
      switch (_reminderStack.side) {
        HabitReminderSide.after => true,
        HabitReminderSide.before => false,
        HabitReminderSide.none ||
        HabitReminderSide.both =>
          _reminderLean == _CueRelation.after,
      };

  /// The picked prayer's label («الفجر»), or null outside prayer mode. What
  /// the rows and the offset sheet name as the moment a shift is from.
  String? _prayerName(S s) =>
      _timingMode == _TimingMode.prayer && _selectedPrayer != null
          ? HabitCue.preset(_selectedPrayer!).labelForLocale(s.isAr)
          : null;

  /// Why the last chip tap did nothing, shown inline under the grid.
  ///
  /// Inline rather than a SnackBar for the same reason the Tasks picker gives:
  /// this form lives inside a showModalBottomSheet, and the ScaffoldMessenger
  /// is BEHIND that sheet, so a SnackBar posted from here is drawn underneath
  /// it and never seen.
  String? _offsetNotice;
  Timer? _offsetNoticeTimer;

  void _showOffsetNotice(String message) {
    setState(() => _offsetNotice = message);
    _offsetNoticeTimer?.cancel();
    // Roughly a SnackBar's dwell, then cleared, so the section doesn't keep a
    // permanent scolding line under it.
    _offsetNoticeTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _offsetNotice = null);
    });
  }

  // Where the confetti burst on submit fires from — see _submit().
  final GlobalKey _createButtonKey = GlobalKey();
  /// The Repeat chips, so a refused Create can scroll back to them.
  final GlobalKey _repeatSectionKey = GlobalKey();

  bool get _isEditing => widget.existing != null;

  /// Editing a catalog preset stores a [CatalogHabitOverride] rather than a
  /// habit document, so the save path below forks on this. The override now
  /// carries the steps link too (see CatalogHabitOverride.stepGoal), which is
  /// what lets a preset like المشي اليومي be linked at all.
  bool get _isPresetEdit {
    final existing = widget.existing;
    return existing != null && IslamicHabitCatalog.findById(existing.id) != null;
  }

  /// Whether the steps-link card is on screen: any build-type habit whose
  /// name reads as walking, OR one whose link is already on (so editing a
  /// linked habit always shows the way to turn it off, even if the person
  /// renamed it to something the detector misses).
  ///
  /// Presets are included. They used to be excluded because the override
  /// could not carry a link, which meant the one catalog habit the feature
  /// exists for — المشي اليومي — was the one habit that could not use it.
  bool get _stepCardVisible =>
      _goalType == GoalType.build &&
      (_nameLooksWalkish || _stepLinkEnabled);

  int get _categoryXp => GameConstants.categoryXpRewards[_category.name] ?? 10;

  /// [_freqTarget] clamped to the 1–6 range the Weekly-mode dropdown in
  /// [_frequencySection] offers (7 would just mean Daily, so it's not one
  /// of the choices — see that method). Guards the rare case _freqTarget
  /// is currently something else entirely when Weekly mode is (re-)picked
  /// — e.g. carried over from Specific Days with more than 6 days
  /// selected, or any other stale value — instead of the dropdown
  /// asserting because its value doesn't match any of its items.
  int get _weeklyTargetInRange =>
      _freqTarget < 1 ? 1 : (_freqTarget > 6 ? 6 : _freqTarget);

  /// [_timesPerDay] clamped to what the stepper can express — the per-day
  /// twin of [_weeklyTargetInRange]. Guards a value restored from an older
  /// document written before the cap existed.
  int get _dailyTargetInRange => _timesPerDay.clamp(1, kMaxTimesPerDay);

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      // Seeded with the raw English `name` here and corrected to the
      // localized one in didChangeDependencies, which is the first point
      // S.of(context) is safe to read. Doing it in two steps rather than one
      // keeps every other field's initialisation where it already was.
      _nameCtrl.text = existing.name;
      final storedCue = existing.cueAfter ?? '';
      _cueRelation = _startsWithBefore(storedCue)
          ? _CueRelation.before
          : _CueRelation.after;
      final parsed = HabitCue.fromStoredValue(storedCue);
      final storedTimes = parsed.clockTimes;
      if (storedTimes.isNotEmpty) {
        _timingMode = _TimingMode.time;
        _pickedTimes = [...storedTimes];
        // A single-time cue never carries its own shift (offsetsAreOwn) —
        // its number lives in the habit-level field, including a multi-time
        // form saved with only one row filled (see _currentCue's collapse).
        // Seeding the row chip from clockOffsets alone showed «في الوقت»
        // for a shift the scheduler was honoring.
        _pickedOffsets = parsed.offsetsAreOwn
            ? [...parsed.clockOffsets]
            : [existing.reminderOffsetMinutes];
      } else if (parsed.isPrayer) {
        _timingMode = _TimingMode.prayer;
        _selectedPrayer = parsed.prayerKey;
      } else if (parsed.prayerSlots case [final first, ...final rest]) {
        // A prayer per time: the first row is the habit's one prayer (see
        // _prayerRows), its shift set below once the habit-level one has
        // been read.
        _timingMode = _TimingMode.prayer;
        _selectedPrayer = first.prayer;
        _prayerRows = [null, ...rest];
      } else if (!parsed.isEmpty) {
        _timingMode = _TimingMode.text;
        _cueCtrl.text = storedCue;
      }
      _editOverview = true;
      final storedOffset = existing.reminderOffsetMinutes;
      _reminderOffset = storedOffset;
      _extraOffsets = {...existing.extraReminderOffsets}..remove(storedOffset);
      // A prayer per time keeps its first row's shift in the cue.
      if (parsed.prayerSlots case [final first, ...]) {
        _reminderOffset = first.offset;
        _extraOffsets = {};
      }
      // A prayer cue is stored as the bare key, so the side its offset sheet
      // leans to can only come from the reminders' signs: صلاة التهجد, 45
      // before Fajr, set back on time still opens its sheet on «قبل». All on
      // time, or a stack on both sides, keeps the default. The helper does
      // nothing outside prayer mode, and writes only [_reminderLean]: custom
      // text still reopens on the stored words.
      _followReminderSide();
      _ignoreQuietHours = existing.ignoreQuietHours;
      _alarm = existing.alarm;
      _category = _canonicalCategory(existing.category);
      _ownCategory = existing.ownCategory;
      _freqType = existing.frequencyType;
      _freqTarget = existing.frequencyTarget;
      // Only a daily habit's target is a per-day count; a weekly one's is
      // not, and seeding from it would show a made-up number in the stepper.
      // Two sources of N have to agree on an existing habit: the stored
      // frequencyTarget and however many times the cue actually carries. They
      // can legitimately differ — a habit edited from 3x to 2x keeps three
      // stored times until it is saved — and the larger one wins, so a
      // document holding three times never renders only two pickers and
      // silently drops the third on save.
      // A prayer per time counts its rows the same way.
      final storedCount = storedTimes.isNotEmpty
          ? storedTimes.length
          : parsed.prayerSlots.length;
      _timesPerDay = existing.frequencyType == HabitFrequencyType.daily
          ? (existing.frequencyTarget > storedCount
                  ? existing.frequencyTarget
                  : storedCount)
              .clamp(1, kMaxTimesPerDay)
          : 1;
      _selectedWeekdays = existing.scheduledWeekdays.toSet();
      _goalType = existing.goalType;
      _reductionType = existing.reductionType;
      _limitCtrl.text = existing.limitAmount?.toString() ?? '';
      _customUnitCtrl.text = existing.customUnitLabel ?? '';
      _iconColorHex = existing.iconColorHex;
      final storedStepGoal = existing.stepGoal;
      _stepLinkEnabled = storedStepGoal != null;
      if (storedStepGoal != null) {
        _stepGoal = storedStepGoal;
        _stepGoalTouched = true;
        // A goal of their own opens on the field, already filled in. The
        // alternative was showing it as a fourth number beside the presets,
        // which read as a fourth suggestion rather than as their own answer.
        _stepGoalCustom = !_stepGoalPresets.contains(storedStepGoal);
      }
      // A preset that ships its own suggested goal opens on that number
      // instead of the generic default: المشي اليومي is a 10,000-step habit,
      // and offering 6,000 for it would be the app forgetting what it just
      // recommended. Only when nothing is linked yet — a real link always
      // outranks a suggestion.
      final suggested = existing.suggestedStepGoal;
      if (storedStepGoal == null && suggested != null) {
        _stepGoal = suggested;
        _stepGoalCustom = !_stepGoalPresets.contains(suggested);
      }
      _stepGoalCtrl.text = _stepGoal.toString();
      _nameLooksWalkish = looksLikeStepHabit(existing.name) ||
          looksLikeStepHabit(existing.nameAr ?? '');
      // Only a LIVE link counts as somebody's own answer. "Unlinked" cannot
      // be told apart from "never asked", and treating the two as the same
      // thing left المشي اليومي permanently un-offered: the walking preset
      // is switched on from the Grid or applied from a Plan, neither of
      // which opens this sheet, so it arrives here unlinked having never
      // shown the card once. The habit the whole feature exists for was the
      // one habit that never got the offer.
      //
      // The cost is that somebody who declines and later edits the habit for
      // an unrelated reason is offered again, since a decline is not stored.
      // That is one visible switch to flip back, against a preset that could
      // otherwise never be linked at all.
      _stepLinkTouched = storedStepGoal != null;
      if (_nameLooksWalkish) _stepLinkEnabled = true;
      _hasName = true;
      _didPickCategory = true;
      // Last, once every field the reminder is worked out from is set.
      _quietAtOpen = _silencedReminderMinutes(
        ref.read(notificationSettingsProvider),
      ).toSet();
    }
    // The Continue button reads the limit field (see _canProceed).
    _limitCtrl.addListener(() {
      if (mounted) setState(() {});
    });
    _nameCtrl.addListener(() {
      final text = _nameCtrl.text.trim();
      final has = text.isNotEmpty;
      final inferred = _inferCategory(text);
      final categoryChanging = !_didPickCategory && inferred != _category;
      final walkish = looksLikeStepHabit(text);
      // A goal typed right into the name ("٨٠٠٠ خطوة") pre-fills the card,
      // unless a chip was already deliberately picked.
      final namedGoal = walkish && !_stepGoalTouched
          ? (parseStepGoal(text) ?? _stepGoal)
          : _stepGoal;
      if (has != _hasName ||
          categoryChanging ||
          walkish != _nameLooksWalkish ||
          namedGoal != _stepGoal) {
        final appearing = walkish && !_nameLooksWalkish;
        setState(() {
          _hasName = has;
          _nameLooksWalkish = walkish;
          // The switch follows the name until somebody touches it: on when
          // the name reads as walking, off again when it stops (a half-typed
          // "walk" on the way to "wake up early" must not leave a live link
          // behind on a habit that has nothing to do with steps).
          if (!_stepLinkTouched) _stepLinkEnabled = walkish;
          if (namedGoal != _stepGoal) {
            // Read out of the name, so the person never typed it here: keep
            // the field in step with it, and open the field when the number
            // they wrote is not one of the presets.
            _stepGoalCtrl.text = namedGoal.toString();
            _stepGoalCustom = !_stepGoalPresets.contains(namedGoal);
          }
          _stepGoal = namedGoal;
          // The category no longer carries a timing mode with it. It used
          // to open the Prayer picker for anything that read as faith, which
          // is a good guess and still the wrong place to make it: the guess
          // arrived pre-selected, so a habit could be saved with a prayer cue
          // nobody ever chose.
          if (!_didPickCategory) _category = inferred;
        });
        // The card is being added to the tree by this very setState, so the
        // scroll has to wait for it to exist. Only on the frame it appears:
        // scrolling on every keystroke afterwards would fight the person
        // still typing.
        if (appearing) _revealStepCard();
      }
    });
    // Only a standalone NEW habit (a room's habit picker, Create Room)
    // autofocuses the name field: the page is type-first and there is
    // nothing else on it to read first. An edit opens on its overview with
    // the keyboard down, and the embedded Add Goal tab (the + button / Add
    // Habit Hub) waits for a deliberate tap, since popping the keyboard open
    // before the sheet is even visible was more disruptive than helpful.
    if (!widget.embedded && !_isEditing) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
    }
    // Tell the host what kind of goal this opens on. Only an edited habit
    // can open on anything but Build, but the host's heading has to be right
    // on the first frame, not only after the switch is touched.
    if (widget.onGoalTypeChanged != null) {
      final type = _goalType;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => widget.onGoalTypeChanged?.call(type));
    }
  }

  /// Whether the name field has been switched from the catalog's raw English
  /// `name` to the locale-appropriate one. Once only: after this, the text in
  /// the box is whatever the user has typed and must never be overwritten.
  bool _localNameResolved = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_localNameResolved) return;
    _localNameResolved = true;
    final existing = widget.existing;
    if (existing == null) return;
    // Editing a habit that came from a Plan showed its ENGLISH name to an
    // Arabic user, because initState seeds from `existing.name` and that
    // field is the English one — `localName(isAr)` is the display name every
    // other surface uses (see IslamicHabitTemplate.localName).
    //
    // It was not merely cosmetic. _submit compares the typed text against
    // `catalogDefault.localName(isAr)` to decide whether the name is a real
    // override or just the untouched default. With the box pre-filled in
    // English and the comparison made in Arabic, the two could never match,
    // so simply opening a preset in Arabic and pressing Save silently wrote
    // the English name in as a permanent per-user override — renaming the
    // person's habit to a language they did not choose. Seeding the same
    // string the comparison uses makes "I changed nothing" compare equal and
    // store nothing.
    final s = S.of(context);
    final localized = existing.localName(s.isAr);
    if (_nameCtrl.text != localized) _nameCtrl.text = localized;
    // The unit box is typed now, so a stock unit is shown as its word
    // («أكواب») for [_typedUnit] to read back as the same unit.
    if (existing.limitUnit case final LimitUnit unit
        when unit != LimitUnit.custom) {
      _customUnitCtrl.text = s.limitUnitLabel(unit.name);
    }
  }

  /// The quit limit's unit, read back from the typed box: a stock unit when
  /// the word is one of theirs in either language («أكواب», "cups», a
  /// singular «كوب» too), otherwise the person's own word as a custom unit.
  /// An empty box is «مرات», the box's own placeholder.
  (LimitUnit, String?) _typedUnit() {
    final typed = _customUnitCtrl.text.trim();
    if (typed.isEmpty) return (LimitUnit.times, null);
    final word = typed.toLowerCase();
    const stock = <LimitUnit, List<String>>{
      LimitUnit.minutes: ['دقائق', 'دقيقة', 'دقايق', 'minutes', 'minute', 'mins', 'min'],
      LimitUnit.times: ['مرات', 'مرة', 'times', 'time'],
      LimitUnit.cups: ['أكواب', 'اكواب', 'كوب', 'cups', 'cup'],
      LimitUnit.money: ['مال', 'money'],
    };
    for (final entry in stock.entries) {
      if (entry.value.contains(word)) return (entry.key, null);
    }
    return (LimitUnit.custom, typed);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _cueCtrl.dispose();
    _stepGoalCtrl.dispose();
    _limitCtrl.dispose();
    _customUnitCtrl.dispose();
    _focus.dispose();
    _scroll.dispose();
    _offsetNoticeTimer?.cancel();
    _settleTimer?.cancel();
    super.dispose();
  }

  /// The multi-time form's FILLED rows, each with its own signed shift —
  /// the single source both [_currentCue] and [_effectiveReminderOffset]
  /// read, so the two can never disagree about how many rows count or
  /// which shift belongs to which time.
  List<(TimeOfDay, int)> get _multiTimeEntries => [
        for (var i = 0; i < _effectiveTimeCount; i++)
          if (i < _pickedTimes.length && _pickedTimes[i] != null)
            (
              _pickedTimes[i]!,
              i < _pickedOffsets.length ? _pickedOffsets[i] : 0,
            ),
      ];

  /// Row [i] of a prayer per time, see [_prayerRows].
  PrayerSlot? _prayerRow(int i) {
    if (i == 0) {
      final prayer = _selectedPrayer;
      return prayer == null ? null : (prayer: prayer, offset: _reminderOffset);
    }
    return i < _prayerRows.length ? _prayerRows[i] : null;
  }

  /// Sets row [i], or takes its reminder off with null. Inside the caller's
  /// setState.
  void _setPrayerRow(int i, PrayerSlot? row) {
    if (i == 0) {
      _selectedPrayer = row?.prayer;
      _reminderOffset = row?.offset ?? 0;
      return;
    }
    while (_prayerRows.length <= i) {
      _prayerRows.add(null);
    }
    _prayerRows[i] = row;
  }

  /// Whether step 3 is asking for a prayer per time.
  bool get _isMultiPrayer =>
      _timingMode == _TimingMode.prayer && _isMultiTime;

  /// The prayer-per-time rows that are set, in row order, each once: two
  /// rows on the same prayer and side are one reminder (the later row says
  /// so), the same rule a clock time on one minute keeps.
  List<PrayerSlot> get _multiPrayerEntries => {
        for (var i = 0; i < _effectiveTimeCount; i++)
          if (_prayerRow(i) case final row?) row,
      }.toList();

  /// Resolves whichever timing mode is active right now into the single
  /// [HabitCue] that gets saved and previewed — the one place that turns
  /// "Time / Prayer / Custom text + before-after" into the actual value,
  /// so submit and the live preview can never disagree with each other.
  HabitCue _currentCue() => switch (_timingMode) {
        // The switch is off, or on with no mode picked yet. Either way there
        // is no moment to save, which is what an untouched picker has always
        // resolved to — the difference is that it is now something somebody
        // said rather than something they failed to say.
        null => HabitCue.empty,
        // An unfilled row is skipped rather than blocking. An empty cue is
        // never what stops a save: _submit's only two bars are a name and a
        // picked cadence, and the switch above this picker rests OFF, so
        // "no moment" is the ordinary answer rather than an omission. All
        // rows empty gives HabitCue.empty, exactly as before.
        // HabitCue.times sorts, dedupes and clamps, so this is the only place
        // the form has to think about order.
        // Multi-time carries its shifts inside the cue, beside the times they
        // belong to; single-time keeps the habit-level field untouched.
        // A multi-time form with exactly ONE row filled collapses to the
        // plain single-time shape (no offset suffix in the cue) and hands
        // its row's shift to the habit-level field instead — see
        // _effectiveReminderOffset. A one-time cue has offsetsAreOwn false,
        // so the scheduler reads the habit-level field for it; storing the
        // shift only inside the cue silently dropped it (the reminder fired
        // on the dot) while re-opening the sheet kept showing the chip the
        // schedule was not honoring.
        _TimingMode.time => _isMultiTime
            ? (_multiTimeEntries.length == 1
                ? HabitCue.times([_multiTimeEntries.single.$1])
                : HabitCue.timesWithOffsets(_multiTimeEntries))
            : HabitCue.times(_filledTimes),
        // The preset KEY, kept intact — never a localized label round-tripped
        // through text.
        //
        // This used to build the cue from labelFor(context), prepend «قبل» /
        // "Before" for the before-relation, and hand the result back to
        // fromStoredValue. Nothing could parse that: "قبل الفجر" is not a
        // preset key, so the cue collapsed to freeform text and
        // scheduleSmartReminders — which can only resolve a real prayer
        // moment — scheduled NOTHING, while the sheet went on showing a
        // confident "you'll be reminded at HH:MM" pill. The habit was saved
        // with a reminder the app had already decided not to set.
        //
        // Before/after for a prayer rides on reminderOffsetMinutes (the lead
        // time), which is the mechanism built for exactly this and is
        // resolved against the prayer's real clock time. Only the freeform
        // Custom-text mode needs the relation baked into the string, because
        // there is no resolvable moment to offset from.
        //
        // A prayer per time carries every row's prayer and shift inside the
        // cue. With ONE row set it collapses to the bare key, the shift going
        // to the habit-level field (see _effectiveReminderOffset), which is
        // the shape a habit with one prayer has always been saved in, and the
        // one every reader of a prayer habit already understands.
        _TimingMode.prayer => _isMultiTime
            ? switch (_multiPrayerEntries) {
                [] => HabitCue.empty,
                [final one] => HabitCue.preset(one.prayer),
                final rows => HabitCue.prayerSlots(rows),
              }
            : _selectedPrayer == null
                ? HabitCue.empty
                : HabitCue.preset(_selectedPrayer!),
        _TimingMode.text => HabitCue.fromStoredValue(_cueWithRelation(_cueCtrl.text)),
      };

  /// The lead time that actually gets saved — 0 (no override) for Custom
  /// Text mode regardless of whatever was previously picked, since a
  /// freeform cue has no resolved moment for a lead time to count back
  /// from (see NotificationService.scheduleSmartReminders). Custom-value
  /// entry is clamped to a sane 0–360 minute range so a stray typo can't
  /// push a reminder days away from the habit it's for.
  int get _effectiveReminderOffset {
    // No moment, nothing to shift from. Reached whenever the switch is off,
    // including on an edit that turned it off: the number has to be written
    // back as 0 rather than left at whatever the habit used to carry, or a
    // reminder outlives the cue it belonged to.
    if (_timingMode == null) return 0;
    if (_timingMode == _TimingMode.text) return 0;
    // A multi-time habit answers per occurrence, from inside its cue. Writing
    // the habit-level field as well would leave two numbers describing the
    // same shift, and the next reader would have to guess whether they stack.
    //
    // Except when only ONE row is filled: _currentCue collapses that to the
    // plain single-time shape (whose cue never carries offsets), so the
    // row's shift lives here — the one home a single-time habit has always
    // used.
    if (_timingMode == _TimingMode.time && _isMultiTime) {
      final entries = _multiTimeEntries;
      return entries.length == 1 ? entries.single.$2 : 0;
    }
    // A prayer per time, the same way: its shifts live in the cue, except
    // the lone row's, which _currentCue saves as the bare prayer.
    if (_isMultiPrayer) {
      final entries = _multiPrayerEntries;
      return entries.length == 1 ? entries.single.offset : 0;
    }
    // One number, one home. The custom value used to live as a magnitude in a
    // text controller plus a direction in a bool, re-derived here on every
    // read — so the field and the toggle could disagree, and a stray "-"
    // typed into the field fought the toggle for the sign. The sheet returns
    // signed minutes and they are stored as signed minutes.
    return _reminderOffset;
  }

  /// The stack that actually gets saved, beside [_effectiveReminderOffset].
  ///
  /// Empty in exactly the cases the section that edits it is not shown, so
  /// what is stored and what was on screen can never disagree:
  ///
  ///  * Custom-text mode, which has no resolved moment to shift from at all.
  ///  * A multi-time habit, which already gets one reminder per occurrence
  ///    with its own shift stored beside its time in the cue. Stacking on top
  ///    of that would multiply the two lists together — see
  ///    IslamicHabitTemplate.extraReminderOffsets.
  ///
  /// Dropping them rather than keeping them hidden is deliberate: a habit
  /// stepped up to 3x/day would otherwise go on firing a stack nothing in the
  /// form admits to, and stepping back down would resurrect it.
  List<int> get _effectiveExtraOffsets {
    if (_timingMode == null) return const [];
    if (_timingMode == _TimingMode.text) return const [];
    if (_timingMode == _TimingMode.time && _isMultiTime) return const [];
    if (_isMultiPrayer) return const [];
    final primary = _effectiveReminderOffset;
    return _extraOffsets.where((o) => o != primary).toList()..sort();
  }

  /// Applies one chip tap and says out loud what it did.
  ///
  /// The rule itself lives in HabitReminderStack.toggle, which is pure and
  /// tested on its own — what is left here is only the part that needs a
  /// screen: a notice, or the paywall.
  void _toggleReminderOffset(int signed) => _applyOffsetTap(
        HabitReminderStack(primary: _reminderOffset, extras: _extraOffsets)
            .toggle(signed, isPremium: ref.read(premiumAccessProvider)),
      );

  /// [chosen] is the value the offset sheet returned when the tap came from
  /// «أضف تذكير», and 0 for a × (see [_followReminderSide]).
  void _applyOffsetTap(
    ({HabitReminderStack stack, HabitOffsetTap outcome}) result, {
    int chosen = 0,
  }) {
    final s = S.of(context);
    switch (result.outcome) {
      case HabitOffsetTap.refusedLast:
        HapticFeedback.lightImpact();
        _showOffsetNotice(s.habitReminderKeepOne);
      case HabitOffsetTap.refusedFull:
        HapticFeedback.lightImpact();
        _showOffsetNotice(s.habitReminderMaxReached);
      case HabitOffsetTap.locked:
        showReminderLimitGate(context, ref, forHabit: true);
      case HabitOffsetTap.removed:
      case HabitOffsetTap.replaced:
      case HabitOffsetTap.added:
        HapticFeedback.selectionClick();
        setState(() {
          _reminderOffset = result.stack.primary;
          _extraOffsets = result.stack.extras;
          _followReminderSide(chosen: chosen);
        });
    }
  }

  /// Offset stacks compare as sets, same reasoning as [_sameWeekdays]: both
  /// sides are stored sorted, so this only ever differs from `==` for a
  /// legacy value, and answering "changed" for a reordering would write an
  /// override that says nothing.
  static bool _sameOffsets(List<int> a, List<int> b) =>
      _sameWeekdays(a, b);

  /// Weekday lists compare as sets — order is meaningless here and a
  /// re-sorted copy of the same days is not a change worth storing.
  static bool _sameWeekdays(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    final x = [...a]..sort();
    final y = [...b]..sort();
    for (var i = 0; i < x.length; i++) {
      if (x[i] != y[i]) return false;
    }
    return true;
  }

  Future<void> _submit() async {
    if (_submitting) return;
    _submitting = true;
    try {
      await _submitOnce();
    } finally {
      _submitting = false;
    }
  }

  Future<void> _submitOnce() async {
    if (!_hasName) return;
    // Read once into a local so the three writes below take a non-nullable
    // value: there is no "no cadence" to store (IslamicHabitTemplate's
    // frequencyType is not nullable, and effectiveDailyTarget reads it
    // unconditionally), and resolving the unanswered case to a quiet Daily
    // here would put back exactly the default this change removed. The
    // button is already held back for this (see [_canCreate]), so this is
    // the belt to that braces.
    final freqType = _freqType;
    if (freqType == null) return;
    final existing = widget.existing;
    if (existing == null && !canAddHabits(ref)) {
      // Habits that have not reached this phone are not a limit: the sheet,
      // and everything typed in it, stays for the retry the notice asks for.
      if (habitCountIsKnown(ref)) Navigator.pop(context);
      showHabitLimitGate(context, ref);
      return;
    }
    // A reminder inside quiet hours is asked about first, before anything
    // irreversible too: the answer can change what is saved (this habit let
    // through), and closing the question keeps the form open to change the
    // time.
    if (!await _askAboutQuietHours()) return;
    // The steps link is resolved BEFORE anything irreversible (haptic,
    // confetti, the save itself): it can show a real OS permission sheet,
    // and the answer decides whether the habit is saved linked or not.
    // Everything past this await is the same synchronous submit as always.
    int? stepGoal;
    if (_stepCardVisible && _stepLinkEnabled) {
      stepGoal = await _confirmStepsAccess();
      if (!mounted) return;
    }
    HapticFeedback.mediumImpact();
    // Celebrate starting something new — editing an existing goal is more
    // of an administrative tweak than a win, so this is reserved for
    // first-time creation only, fired from right where the tap landed.
    // A bigger burst than a routine habit completion: creating a goal only
    // happens once per habit, so it earns the extra flourish.
    if (existing == null) {
      final box =
          _createButtonKey.currentContext?.findRenderObject() as RenderBox?;
      if (box != null && box.attached) {
        showVictoryBurst(
          context,
          box.localToGlobal(box.size.center(Offset.zero)),
          particleCount: 24,
          spread: 92,
        );
      }
    }
    // This habit will actually be scheduled for a notification, so make
    // sure we're allowed to send one. Previously nothing in this sheet ever
    // asked: someone could pick "before Dhuhr", have their location
    // auto-detected, and still silently receive nothing forever because the
    // OS prompt had never been shown (iOS init deliberately doesn't
    // auto-request — see NotificationService.init). Fire-and-forget with a
    // warning on denial, the same request-then-warn contract
    // AddTaskSheet/TaskDetailSheet already use: scheduling still proceeds
    // either way, so a denial degrades to "saved but silent" rather than
    // blocking the habit from being created at all.
    // A quit habit's only notification is the evening check-in, which the
    // text mode above never asked permission for: on iOS it silently never
    // arrived (2026-09-08). Quit habits ask on save regardless of mode.
    // Nothing is scheduled for a habit with no moment, so nothing is asked
    // for either. With the switch off by default that is now the common
    // case, and a permission sheet arriving on the way out of a form that
    // set no reminder is exactly the prompt people learn to dismiss without
    // reading — including the ones who later do want a reminder.
    final currentCue = _currentCue();
    if (_goalType == GoalType.quit ||
        (_timingMode != null &&
            _timingMode != _TimingMode.text &&
            !currentCue.isEmpty)) {
      _ensureNotificationPermission();
    }
    final cue = currentCue.toStorageValue();
    final limitAmount = int.tryParse(toWesternDigits(_limitCtrl.text.trim()));
    final (limitUnit, customUnitLabel) = _typedUnit();
    final notifier = ref.read(customHabitsProvider.notifier);
    // Only the create path hands anything back - callers that open this
    // sheet to build a brand-new habit from somewhere other than the
    // ordinary Add Habit flow (see RoomsController's habit-picker sheets)
    // need the real created habit, id included, to link right away rather
    // than making the user go find it in a list afterward. The edit path
    // pops null, same as this always used to pop nothing - every existing
    // caller that ignores the result is unaffected either way.
    IslamicHabitTemplate? created;
    if (existing != null && _isPresetEdit) {
      // ── Editing a PRESET ────────────────────────────────────────────────
      // Catalog habits are const templates shared by every user, so there is
      // no per-user document to rewrite. Their changes are stored as an
      // override keyed by the catalog id and merged back in
      // habitListProvider - which is what makes this safe: the habit's id is
      // untouched, so its Grid squares, streak, completion counts and room
      // links all keep pointing at the same habit.
      //
      // Only the fields that make sense for a preset are carried. Category,
      // goal type and the quit-habit limit are part of what the preset IS -
      // they stay the catalog's, and the sheet hides them for presets.
      final catalogDefault = IslamicHabitCatalog.findById(existing.id)!;
      final editedName = _nameCtrl.text.trim();
      final pickedWeekdays = _selectedWeekdays.toList()..sort();
      // A schedule change starts today and leaves every earlier day on the
      // schedule it had, exactly as CustomHabitsNotifier.update records it
      // for a habit of their own. Measured against the preset as this person
      // has it at the moment of saving (their override already applied), not
      // as it was when the sheet opened.
      final live = ref.read(habitListProvider).firstWhere(
            (h) => h.id == existing.id,
            orElse: () => existing,
          );
      final pastCadences = pastCadencesAfterChange(
        past: live.pastCadences,
        current: live.cadence,
        next: HabitCadence(
          frequencyType: freqType,
          frequencyTarget: _freqTarget,
          scheduledWeekdays: pickedWeekdays,
        ),
        bornOn: live.createdAt,
        today: DateTime.now().effectiveDay,
      );
      ref.read(catalogOverridesProvider.notifier).setOverride(
            existing.id,
            CatalogHabitOverride(
              // Each field stored only when it actually differs from the
              // catalog, so a habit edited back to its defaults stops being
              // an override at all and starts tracking the preset again.
              name: editedName == catalogDefault.localName(S.of(context).isAr)
                  ? null
                  : editedName,
              cueAfter: cue == catalogDefault.cueAfter ? null : cue,
              frequencyType: freqType == catalogDefault.frequencyType
                  ? null
                  : freqType,
              frequencyTarget: _freqTarget == catalogDefault.frequencyTarget
                  ? null
                  : _freqTarget,
              scheduledWeekdays: _sameWeekdays(
                      pickedWeekdays, catalogDefault.scheduledWeekdays)
                  ? null
                  : pickedWeekdays,
              reminderOffsetMinutes: _effectiveReminderOffset ==
                      catalogDefault.reminderOffsetMinutes
                  ? null
                  : _effectiveReminderOffset,
              // Written whenever it differs from the preset's own, EMPTY
              // included: clearing a stack off a catalog habit has to
              // survive a reload, and null here would hand the catalog's
              // default straight back (see the override field's doc).
              extraReminderOffsets: _sameOffsets(_effectiveExtraOffsets,
                      catalogDefault.extraReminderOffsets)
                  ? null
                  : _effectiveExtraOffsets,
              // The link, resolved above through the same permission prompt
              // a custom habit gets. Null both when nobody linked it and
              // when somebody turned it off, which is the same thing: the
              // catalog never ships a live link, so there is no preset value
              // here for null to be confused with.
              stepGoal: stepGoal,
              alarm: _alarm == catalogDefault.alarm ? null : _alarm,
              ignoreQuietHours:
                  _ignoreQuietHours == catalogDefault.ignoreQuietHours
                      ? null
                      : _ignoreQuietHours,
              iconColorHex: _iconColorHex == catalogDefault.iconColorHex
                  ? null
                  : _iconColorHex,
              // Never "equal to the catalog": a preset has no history of its
              // own, so this is always kept, and it keeps the entry alive
              // after an edit back to the catalog's schedule.
              pastCadences: pastCadences,
            ),
          );
    } else if (existing != null) {
      notifier.update(
        id: existing.id,
        name: _nameCtrl.text.trim(),
        category: _category,
        cueAfter: cue,
        frequencyType: freqType,
        frequencyTarget: _freqTarget,
        scheduledWeekdays: _selectedWeekdays.toList()..sort(),
        goalType: _goalType,
        reductionType: _reductionType,
        limitAmount: _isLimitHabit ? limitAmount : null,
        limitUnit: _isLimitHabit ? limitUnit : null,
        customUnitLabel: _isLimitHabit ? customUnitLabel : null,
        iconColorHex: _iconColorHex,
        clearIconColor: _iconColorHex == null,
        ownCategory: _ownCategory,
        clearOwnCategory: _ownCategory == null,
        reminderOffsetMinutes: _effectiveReminderOffset,
        extraReminderOffsets: _effectiveExtraOffsets,
        ignoreQuietHours: _ignoreQuietHours,
        alarm: _alarm,
        stepGoal: stepGoal,
        clearStepGoal: stepGoal == null,
      );
    } else {
      created = notifier.add(
        name: _nameCtrl.text.trim(),
        category: _category,
        cueAfter: cue,
        frequencyType: freqType,
        frequencyTarget: _freqTarget,
        scheduledWeekdays: _selectedWeekdays.toList()..sort(),
        goalType: _goalType,
        reductionType: _reductionType,
        limitAmount: _isLimitHabit ? limitAmount : null,
        limitUnit: _isLimitHabit ? limitUnit : null,
        customUnitLabel: _isLimitHabit ? customUnitLabel : null,
        iconColorHex: _iconColorHex,
        ownCategory: _ownCategory,
        reminderOffsetMinutes: _effectiveReminderOffset,
        extraReminderOffsets: _effectiveExtraOffsets,
        ignoreQuietHours: _ignoreQuietHours,
        alarm: _alarm,
        stepGoal: stepGoal,
      );
      // Hand the Grid the new id so the board can scroll the row into view
      // and glow it once — creation appends below the fold, and without
      // this the sheet closed onto a board that looked exactly as it did
      // before. See newlyAddedHabitIdProvider.
      ref.read(newlyAddedHabitIdProvider.notifier).state = created.id;
    }
    Navigator.pop(context, created);
  }

  /// The Save-time half of the steps link: makes sure the platform can and
  /// may hand over the step count, and returns the goal to store — or null
  /// to save the habit unlinked, after telling the person why in an overlay
  /// notice. Same "the habit still saves either way" contract as
  /// _ensureNotificationPermission, just resolved before the write instead
  /// of after, because linked-ness is part of what gets written.
  Future<int?> _confirmStepsAccess() async {
    final s = S.of(context);
    // showOverlayNotice, not a SnackBar. Both of these are posted while the
    // sheet is still open, and a SnackBar goes to the Scaffold BEHIND it,
    // at the bottom of the screen, which is precisely the part of the
    // screen a bottom sheet is covering. What was left of the four seconds
    // once the sheet finished dismissing was the only chance anybody had of
    // reading why their link was off, with a confetti burst going off over
    // it. See overlay_notice.dart, which exists for this class of bug: it
    // is top-anchored and inserted into the ROOT overlay, so it is above
    // the sheet, and it outlives it.
    if (!await HealthStepsService.instance.isSupported()) {
      if (!mounted) return null;
      showOverlayNotice(context, s.stepLinkUnsupported,
          icon: Icons.directions_walk_rounded);
      return null;
    }
    if (!await HealthStepsService.instance.requestPermission()) {
      if (!mounted) return null;
      showOverlayNotice(context, s.stepLinkDenied,
          icon: Icons.directions_walk_rounded);
      return null;
    }
    return _stepGoal;
  }

  /// Checks whether [existing] is still counted toward any open room before
  /// actually deleting it - if so, this is the one moment that's still easy
  /// to warn about (see S.habitLinkedRoomWarningBody's doc comment), so a
  /// confirm dialog names what's at stake before anything happens. Either
  /// way, a linked habit gets unlinked from every room it's in as part of
  /// the same delete (see RoomsController.unlinkHabitEverywhere) so no
  /// room is ever left pointing at a habit that no longer exists.
  Future<void> _deleteExisting() async {
    final existing = widget.existing;
    if (existing == null) return;
    final linkedRooms =
        ref.read(myLinkedRoomHabitsProvider)[existing.id] ?? const [];
    if (linkedRooms.isNotEmpty) {
      final s = S.of(context);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(s.habitLinkedRoomWarningTitle),
          content: Text(s.habitLinkedRoomWarningBody(
              linkedRooms.map((r) => r.name).toList())),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(s.habitDeleteLinkedRoomCancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: GameColors.error),
              child: Text(s.habitDeleteAnywayAction),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    HapticFeedback.mediumImpact();
    // Captured before the pop below closes this sheet's own context — the
    // messenger lives on the ancestor Scaffold (Grid), so it's still good
    // for showing the confirmation after this sheet is gone.
    final messenger = ScaffoldMessenger.of(context);
    final confirmationText = S.of(context).habitArchivedConfirmation;
    ref.read(roomsControllerProvider).unlinkHabitEverywhere(existing.id).ignore();
    // archive(), not a hard delete — see CustomHabitsNotifier.archive's
    // doc comment. Leaves this sheet/the Grid/today's streak exactly as
    // fast as the old remove() did; only the Firestore doc's fate changed.
    // everCompleted: a never-touched, same-day habit gets fully erased
    // instead (see that parameter's own doc comment) — this is the
    // "delete a habit" entry point most likely to be someone undoing a
    // just-added mistake, so it's worth getting right here specifically.
    // isLoading counts as "has history": habitTotalCompletions is empty while
    // the dashboard is still loading, so reading it mid-load would classify a
    // habit with months of history as never-completed and hard-delete it
    // instead of archiving. Erring toward archive is free — the habit is gone
    // from the Grid either way, only the Firestore doc's fate differs, and an
    // archived doc can still be restored by Undo.
    final dash = ref.read(dashboardProvider);
    final everCompleted = dash.isLoading ||
        (dash.habitTotalCompletions[existing.id] ?? 0) > 0;
    // Preset habits live in ActiveCatalogNotifier, custom ones in
    // CustomHabitsNotifier, and archive() early-returns on an id it doesn't
    // own. This branch used to be missing here: "Remove habit" called
    // archive() unconditionally, which silently no-opped for every preset —
    // so tapping it on a preset unlinked the habit from every room (the line
    // above is not reversible) and then left the habit sitting on the Grid
    // exactly where it was. The user saw a delete that did nothing, and lost
    // their room links for it. Same branch GridScreen._deleteSelected already
    // uses; keyed on findById rather than on custom-habit membership, since
    // an already-archived custom habit isn't in that list either.
    if (IslamicHabitCatalog.findById(existing.id) == null) {
      ref
          .read(customHabitsProvider.notifier)
          .archive(existing.id, everCompleted: everCompleted);
    } else {
      ref
          .read(activeCatalogProvider.notifier)
          .toggle(existing.id, everCompleted: everCompleted);
    }
    if (mounted) Navigator.pop(context);
    messenger.showOne(
      SnackBar(
        content: Text(confirmationText),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    if (!_cueLabelResolved) {
      _cueLabelResolved = true;
      if (_cueCtrl.text.isNotEmpty) {
        _cueCtrl.text = HabitCue.fromStoredValue(_cueCtrl.text).labelFor(context);
      }
    }

    final content = _content(context, s);
    if (widget.embedded) return content;

    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;
    // Resting size (no keyboard) stays ~92% of the screen, same as before.
    // Once the keyboard opens, cap it to whatever room is left above it
    // instead, so the sheet never ends up pushed off the top of the screen
    // or hiding the focused field behind the keyboard.
    final rawMaxHeight = bottom > 0 ? screenHeight - bottom - 24 : screenHeight * 0.92;
    final maxHeight = rawMaxHeight < 200.0 ? 200.0 : rawMaxHeight;
    const keyboardAnim = Duration(milliseconds: 220);
    const keyboardCurve = Curves.easeOutCubic;
    return AnimatedPadding(
      duration: keyboardAnim,
      curve: keyboardCurve,
      padding: EdgeInsets.only(bottom: bottom),
      child: AnimatedContainer(
        duration: keyboardAnim,
        curve: keyboardCurve,
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Container(
          decoration: BoxDecoration(
            color: gp.surfaceHigh,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: gp.border, width: 0.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 4),
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: gp.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              // Flexible, not a bare child. Without it this Column hands
              // `content` an unbounded height, so the Flexible(
              // SingleChildScrollView) *inside* _content has nothing to shrink
              // against: the scroll view takes its full intrinsic height, the
              // Column grows past the maxHeight constraint above, and the
              // bottom overflows. It only showed while EDITING, because that
              // is the one case that adds the "Remove habit" button under the
              // footer — the extra ~48pt that tipped it over. The visible
              // result was Flutter's overflow stripe across the footer with
              // Remove clipped underneath it, which is what "editing a plan
              // habit gets stuck" looked like: the buttons were there, just
              // painted outside the sheet.
              Flexible(child: content),
            ],
          ),
        ),
      ).animate().slideY(begin: 0.06, duration: 260.ms, curve: Curves.easeOutCubic).fadeIn(duration: 200.ms),
    );
  }

  /// A set-a-limit quit habit needs its number: picking «أحدّه» and leaving
  /// the field blank used to save `reductionType: limit` with no amount, so
  /// every "within the limit" question had nothing to compare against.
  bool get _limitMissing =>
      _isLimitHabit &&
      (int.tryParse(toWesternDigits(_limitCtrl.text.trim())) ?? 0) < 1;

  /// The limit trio (amount, unit, custom label) belongs to a QUIT habit
  /// with a limit. Guarding on the reduction type alone let a build habit
  /// that had briefly been a limit carry a limitAmount in memory.
  bool get _isLimitHabit =>
      _goalType == GoalType.quit && _reductionType == ReductionType.limit;

  /// The only thing that greys the primary button: a habit with no name is
  /// not a habit yet, and the box asking for one is the first thing on the
  /// step.
  ///
  /// The other two required answers (a limit habit's number, and the
  /// cadence) do NOT grey it. They are checked when it is pressed, and only
  /// then does the control that owes the answer say so: see [_tryContinue],
  /// [_tryContinueOften] and [_limitErrorShown] / [_repeatErrorShown]. A
  /// form that points at a field before anybody has had a go at it is
  /// nagging, and a dead button with a note beside it says the same thing
  /// twice.
  bool get _canProceed => _hasName;

  /// Set the first time somebody presses the button with a limit habit whose
  /// number is missing, and the only thing that puts
  /// [S.limitAmountRequired] on screen. False again for a fresh sheet.
  bool _limitErrorShown = false;

  /// The cadence half of the same idea, for [S.repeatPickOne].
  bool _repeatErrorShown = false;

  /// Step 1's «متابعة», with its own required answer (a limit habit's
  /// number) checked at the moment of the press rather than in advance.
  ///
  /// Shared by the footer button and the name field's return key, so the
  /// keyboard cannot walk past a check the button enforces.
  void _tryContinue() {
    if (!_stepWhatDone()) return;
    HapticFeedback.selectionClick();
    FocusScope.of(context).unfocus();
    _goToStep(1, forward: true);
  }

  /// Step 1's answers, checked: a name, and a limit habit's number. Says
  /// what is missing where it is owed.
  bool _stepWhatDone() {
    if (!_hasName) return false;
    if (_limitMissing) {
      HapticFeedback.lightImpact();
      setState(() => _limitErrorShown = true);
      return false;
    }
    return true;
  }

  /// Step 2's «متابعة». The one required answer on the step is how often,
  /// and nothing is lit until somebody picks it: cadence decides which days
  /// the Grid asks about, what the streak counts and which days a room
  /// scores, so the form never answers it for them.
  void _tryContinueOften() {
    if (!_stepOftenDone()) return;
    HapticFeedback.selectionClick();
    _goToStep(2, forward: true);
  }

  bool _stepOftenDone() {
    if (_freqType != null) return true;
    HapticFeedback.lightImpact();
    setState(() => _repeatErrorShown = true);
    _revealRepeatSection();
    return false;
  }

  /// «أضف العادة» on step 3, and «احفظ التغييرات» on the edit overview.
  /// The cadence is checked again here as the belt to [_tryContinueOften]'s
  /// braces: there is no "no cadence" to store.
  void _tryCreate() {
    if (!_hasName) return;
    if (_freqType == null) {
      HapticFeedback.lightImpact();
      setState(() => _repeatErrorShown = true);
      if (_isEditing) {
        _goToStep(1, forward: true);
      } else {
        _revealRepeatSection();
      }
      return;
    }
    _submit();
  }

  /// «تم» on an edited habit's step page: the step's own answer checked,
  /// then back to the overview, where saving happens.
  void _editStepDone() {
    final ok = switch (_step) {
      0 => _stepWhatDone(),
      1 => _stepOftenDone(),
      _ => true,
    };
    if (!ok) return;
    HapticFeedback.selectionClick();
    FocusScope.of(context).unfocus();
    _backToOverview();
  }

  /// Scrolls the how-often row fully into view.
  void _revealRepeatSection() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = _repeatSectionKey.currentContext;
      if (target == null) return;
      Scrollable.ensureVisible(
        target,
        duration: GameMotion.slow,
        curve: Curves.easeOutCubic,
      );
    });
  }

  /// Heading (standalone only), the step bar, the page, then the footer, so
  /// [embedded] mode can drop straight into a host that already supplies
  /// the drag handle and outer card (see [AddHabitHub]).
  Widget _content(BuildContext context, S s) {
    final gp = context.gp;
    final onOverview = _isEditing && _editOverview;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Embedded, this form has no heading of its own: the host that
        // embeds it (AddHabitHub) already writes «إضافة عادة» directly above.
        // Standalone it is the only heading there is: three callers open
        // this sheet with no chrome of their own above it (the Grid's edit
        // sheet, the room habit picker, Create Room).
        if (!widget.embedded)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
            child: Text(
              // Standalone, this is the only heading there is, so it has to
              // follow the switch too — see AddHabitHub's copy of this. One
              // noun, «عادة», where it used to say «هدف» on this sheet.
              _isEditing
                  ? s.editHabit
                  : (_goalType == GoalType.quit ? s.hubTitleQuit : s.hubTitle),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: gp.textPrimary,
              ),
            ),
          ),
        // Where you are, for a new habit. An edit is not a walk through the
        // steps: its overview names all three answers at once.
        if (!_isEditing) _stepBar(s),
        Flexible(
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: AnimatedSwitcher(
              duration: GameMotion.relaxed,
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                final offsetTween = Tween<Offset>(
                  begin: Offset(_forward ? 0.08 : -0.08, 0),
                  end: Offset.zero,
                );
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: animation.drive(offsetTween),
                    child: child,
                  ),
                );
              },
              layoutBuilder: (currentChild, previousChildren) => Stack(
                alignment: Alignment.topCenter,
                children: [
                  ...previousChildren,
                  if (currentChild != null) currentChild,
                ],
              ),
              child: KeyedSubtree(
                key: ValueKey(onOverview ? -1 : _step),
                child: onOverview
                    ? _editOverviewPage(s)
                    : switch (_step) {
                        0 => _stepWhat(s),
                        1 => _stepOften(s),
                        _ => _stepReminder(s),
                      },
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            10,
            20,
            onOverview ? 4 : 20 + MediaQuery.of(context).padding.bottom,
          ),
          child: _footer(s),
        ),
        if (onOverview)
          Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              0,
              20,
              20 + MediaQuery.of(context).padding.bottom,
            ),
            child: TextButton(
              onPressed: _deleteExisting,
              style: TextButton.styleFrom(
                minimumSize: const Size(double.infinity, 44),
                foregroundColor: GameColors.error,
              ),
              child: Text(s.removeHabit),
            ),
          ),
      ],
    );
  }

  /// The buttons under the page. A new habit: «متابعة» on step 1, «رجوع»
  /// and «متابعة» on step 2, «رجوع» and «أضف العادة» on step 3. An edit:
  /// «احفظ التغييرات» on the overview and «تم» on a step page.
  Widget _footer(S s) {
    final gp = context.gp;
    final String label;
    final VoidCallback onPressed;
    var showBack = false;
    if (_isEditing) {
      label = _editOverview ? s.saveChanges : s.habitEditStepDone;
      onPressed = _editOverview ? _tryCreate : _editStepDone;
    } else {
      switch (_step) {
        case 0:
          label = s.continueAction;
          onPressed = _tryContinue;
        case 1:
          label = s.continueAction;
          onPressed = _tryContinueOften;
          showBack = true;
        default:
          label = s.addHabitAction;
          onPressed = _tryCreate;
          showBack = true;
      }
    }
    final creates = _isEditing ? _editOverview : _step == 2;
    return Row(
      children: [
        if (showBack) ...[
          TextButton(
            onPressed: () {
              HapticFeedback.selectionClick();
              FocusScope.of(context).unfocus();
              _goToStep(_step - 1, forward: false);
            },
            style: TextButton.styleFrom(
              minimumSize: const Size(64, 50),
              foregroundColor: gp.textSec,
            ),
            child: Text(s.back),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: FilledButton(
            key: creates ? _createButtonKey : null,
            // See [_stepSettling]: a tap while the next step slides in is the
            // second tap of the one that moved it.
            onPressed: _canProceed
                ? () {
                    if (_stepSettling) return;
                    onPressed();
                  }
                : null,
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(label),
          ),
        ),
      ],
    );
  }

  /// Three bars with the step names under them: lit up to the step you are
  /// on, the current name in bold. A step already passed can be tapped to go
  /// back to it. All three are solid: the third was dashed to say it is
  /// optional, which its name «(اختياري)» already says (Aziz, 2026-10-01).
  Widget _stepBar(S s) {
    final gp = context.gp;
    final labels = [
      s.addHabitStepWhat,
      s.addHabitStepOften,
      s.addHabitStepReminder,
    ];
    Widget bar(int i) {
      final lit = i <= _step;
      return AnimatedContainer(
        duration: GameMotion.quick,
        height: 4,
        decoration: BoxDecoration(
          color: lit ? GameColors.gold : gp.border,
          borderRadius: BorderRadius.circular(2),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
      child: Row(
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: Semantics(
                button: i < _step,
                selected: i == _step,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: i < _step
                      ? () {
                          HapticFeedback.selectionClick();
                          FocusScope.of(context).unfocus();
                          _goToStep(i, forward: false);
                        }
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        bar(i),
                        const SizedBox(height: 6),
                        Text(
                          labels[i],
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight:
                                i == _step ? FontWeight.w800 : FontWeight.w600,
                            color: i == _step
                                ? context.gp.goldInk
                                : (i < _step ? gp.textSec : gp.textTert),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// What an edit opens on: the three answers as rows, each opening its
  /// step (canvas board "Edit a habit"). It used to open on the name box
  /// with the keyboard up and walk through both pages to save.
  Widget _editOverviewPage(S s) {
    final settings = ref.watch(notificationSettingsProvider);
    final cue = _currentCue();
    final anchor = _reminderAnchorTime(settings);
    String? reminderLine;
    if (!cue.isEmpty && _timingMode != _TimingMode.text) {
      final sentences = [
        for (final offset in _remindersForSummary())
          _offsetRowLabel(s, offset),
        // A prayer per time says each row, «قبل الفجر بـ30 دقيقة، بعد الفجر
        // بـ30 دقيقة»: the label above names each prayer only once.
        if (_isMultiPrayer)
          for (final row in _multiPrayerEntries)
            habitReminderSentence(
              row.offset,
              s,
              prayer: HabitCue.preset(row.prayer).labelForLocale(s.isAr),
            ),
      ];
      String? time;
      if (anchor != null && !_isMultiTime) {
        final at = anchor.add(Duration(minutes: _effectiveReminderOffset));
        time = HabitCue.time(at.hour, at.minute).labelForLocale(s.isAr);
      }
      reminderLine = [
        if (sentences.isNotEmpty) sentences.join(s.isAr ? '، ' : ', '),
        if (time != null) time,
      ].join(' · ');
      if (reminderLine.isEmpty) reminderLine = null;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _overviewRow(
          label: s.addHabitStepWhat,
          value: _nameCtrl.text.trim(),
          leading: _categoryBadge(),
          onTap: () => _goToStep(0, forward: true),
        ),
        const SizedBox(height: 8),
        _overviewRow(
          label: s.addHabitStepOften,
          value: _oftenSummary(s) ?? s.repeatPickOne,
          onTap: () => _goToStep(1, forward: true),
        ),
        const SizedBox(height: 8),
        _overviewRow(
          label: s.addHabitStepReminderShort,
          value: cue.isEmpty ? s.noReminder : cue.labelForLocale(s.isAr),
          detail: reminderLine,
          onTap: () => _goToStep(2, forward: true),
        ),
        if (_stepCardVisible && _stepLinkEnabled) ...[
          const SizedBox(height: 10),
          _stepLinkRecap(s),
        ],
      ],
    ).animate().fadeIn(duration: 240.ms).slideY(begin: 0.04, curve: Curves.easeOutCubic);
  }

  /// The reminders an overview or a summary names: a multi-time habit's are
  /// per occurrence and live with its times, so it names none.
  List<int> _remindersForSummary() {
    if (_timingMode == null || _timingMode == _TimingMode.text) return const [];
    if (_timingMode == _TimingMode.time && _isMultiTime) return const [];
    if (_isMultiPrayer) return const [];
    return [_effectiveReminderOffset, ..._effectiveExtraOffsets];
  }

  Widget _overviewRow({
    required String label,
    required String value,
    String? detail,
    Widget? leading,
    required VoidCallback onTap,
  }) {
    final gp = context.gp;
    final radius = BorderRadius.circular(14);
    return Material(
      type: MaterialType.transparency,
      child: Ink(
        decoration: BoxDecoration(
          color: gp.surface,
          borderRadius: radius,
          border: Border.all(color: gp.border, width: 0.5),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 14, 10, 14),
            child: Row(
              children: [
                SizedBox(
                  width: 64,
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: gp.textTert,
                    ),
                  ),
                ),
                if (leading != null) ...[
                  leading,
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        value,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: gp.textPrimary,
                          height: 1.3,
                        ),
                      ),
                      if (detail != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          detail,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: gp.textSec,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: context.gp.goldInk,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Step 1: the habit ────────────────────────────────────────────────

  /// Type-first: the Build / Quit switch, the name box and «متابعة». The
  /// category is picked from the name and shown as one line that can be
  /// changed; suggestions and Plans wait behind one optional door, so
  /// somebody who knows what they want never meets them (canvas v8, Aziz
  /// 2026-09-30: "user may feel he must click first before type").
  Widget _stepWhat(S s) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The kind of habit, as a two-way switch right above the box it
          // changes. It was a quiet text link under the whole form, and Aziz
          // found nobody saw it there (2026-09-08). With Build already
          // selected it is a mode, not a question: typing straight into the
          // box works.
          // Not for a catalog preset: its goal type and quit limit are part
          // of what the preset IS, and the override an edit stores cannot
          // change them (see _submit). Showing the switch there let an edit
          // of «غض البصر» appear to turn it into a build habit and do
          // nothing.
          if (!_isPresetEdit) ...[
            _goalTypeToggle(s)
                .animate()
                .fadeIn(duration: 240.ms)
                .slideY(begin: 0.06, curve: Curves.easeOutCubic),
            const SizedBox(height: 12),
          ],
          _nameSection(s)
              .animate(delay: 40.ms)
              .fadeIn(duration: 240.ms)
              .slideY(begin: 0.06, curve: Curves.easeOutCubic),
          // Right under the name: a limit typed in the old form sat under
          // nine categories and the ideas, below the keyboard.
          if (_goalType == GoalType.quit && !_isPresetEdit) ...[
            const SizedBox(height: 14),
            _quitStyleSection(s)
                .animate(delay: 60.ms)
                .fadeIn(duration: 240.ms)
                .slideY(begin: 0.06, curve: Curves.easeOutCubic),
          ],
          // The way to ideas and plans: one card that opens a page of its
          // own (the "Habit ideas page" canvas). An edit already has its
          // habit; ideas would only replace it.
          if (!_isEditing) ...[
            const SizedBox(height: 14),
            _ideasCard(s).animate(delay: 80.ms).fadeIn(duration: 240.ms),
          ],
        ],
      );

  /// The "this looks like a walking habit" card — the visible half of the
  /// steps link (step_habit_detector.dart is the detection half). Explains
  /// what linking does in one sentence, then a switch and, once on, the
  /// daily-goal chips. Turning it on here promises nothing yet: the real
  /// health permission is asked on Save (see _confirmStepsAccess), so
  /// backing out of the sheet never leaves a half-granted state behind.
  Widget _stepLinkCard(S s) {
    final gp = context.gp;
    // Always the same three, in the same order. A goal of the person's own
    // used to be injected here as a fourth number, which read as a fourth
    // suggestion from the app rather than as their own answer, and moved the
    // other three around depending on its size. It lives in the Custom field
    // below now, where it can also be changed.
    const goalChoices = _stepGoalPresets;
    final on = _stepLinkEnabled;
    return AnimatedContainer(
      key: _stepCardKey,
      duration: GameMotion.quick,
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        // The card carries the answer in its own weight: switched on it is
        // a filled, outlined panel, switched off it recedes to an offer.
        // Before this it looked identical either way, so the one state
        // worth noticing (a link about to be created) announced nothing.
        color: GameColors.success.withOpacity(on ? 0.12 : 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: GameColors.success.withOpacity(on ? 0.55 : 0.25),
          width: on ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // A filled disc rather than a bare glyph: at 18pt on a tinted
              // panel the old icon read as decoration on the border.
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: GameColors.success.withOpacity(on ? 0.22 : 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.directions_walk_rounded,
                    size: 18, color: GameColors.success),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  s.stepLinkTitle((!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS)),
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: gp.textPrimary,
                  ),
                ),
              ),
              Switch.adaptive(
                value: _stepLinkEnabled,
                activeColor: GameColors.success,
                onChanged: (v) {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _stepLinkEnabled = v;
                    // From here on the name field stops moving this switch:
                    // an answer given by hand outranks one inferred from
                    // spelling. See [_stepLinkTouched].
                    _stepLinkTouched = true;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            s.stepLinkBody((!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS)),
            style: TextStyle(fontSize: 11.5, color: gp.textSec, height: 1.4),
          ),
          if (_stepLinkEnabled) ...[
            const SizedBox(height: 8),
            // What happens next, in the one place somebody is still looking
            // at this decision. The switch grants nothing by itself, and an
            // OS permission sheet that arrives unannounced two taps later
            // gets dismissed by reflex. On iOS it is shown once, ever.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_open_rounded,
                    size: 13, color: GameColors.success),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    s.stepLinkAskNext(_isEditing),
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                      color: GameColors.success,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              s.stepLinkGoal(_stepGoal),
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: gp.textSec,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                for (final goal in goalChoices) ...[
                  Expanded(
                    child: _SmallPick(
                      label: '$goal',
                      selected: !_stepGoalCustom && _stepGoal == goal,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _stepGoal = goal;
                          _stepGoalTouched = true;
                          // Closes the field, and takes its number with it:
                          // a preset tapped last IS the answer, and leaving
                          // a stale typed number on screen underneath would
                          // make two different goals visible at once.
                          _stepGoalCustom = false;
                          _stepGoalCtrl.text = goal.toString();
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: _SmallPick(
                    label: s.stepGoalCustom,
                    selected: _stepGoalCustom,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() {
                        _stepGoalCustom = true;
                        _stepGoalTouched = true;
                        // Opens on the goal already chosen, not on a blank.
                        // The person is adjusting a number, not inventing
                        // one, and a cleared field would throw away the one
                        // piece of context they have.
                        _stepGoalCtrl.text = _stepGoal.toString();
                      });
                    },
                  ),
                ),
              ],
            ),
            if (_stepGoalCustom) ...[
              const SizedBox(height: 8),
              _stepGoalField(s),
            ],
          ],
        ],
      ),
    );
  }

  /// The typed goal, or null while what is in the field is not a goal the
  /// app can use (empty, or outside [_stepGoalMin]..[_stepGoalMax]).
  ///
  /// Deliberately not the same thing as [_stepGoal]: that one only ever
  /// holds a number the app WOULD save, so a half-typed "8" on the way to
  /// "8000" cannot momentarily become somebody's daily goal.
  int? get _typedStepGoal {
    final n = int.tryParse(toWesternDigits(_stepGoalCtrl.text.trim()));
    if (n == null || n < _stepGoalMin || n > _stepGoalMax) return null;
    return n;
  }

  /// The number field behind the Custom chip.
  ///
  /// Digits only and a number keyboard, because there is nothing else to
  /// type here, and the unit sits beside the field rather than inside it as
  /// a hint: a hint disappears the moment somebody starts typing, which is
  /// exactly when "am I entering steps or minutes?" is being asked.
  Widget _stepGoalField(S s) {
    final gp = context.gp;
    final invalid = _typedStepGoal == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 104,
              child: TextField(
                selectionWidthStyle: GameTextStyles.selectionWidthStyle,
                controller: _stepGoalCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  // Arabic-Indic digits allowed through, not stripped.
                  // digitsOnly is [0-9] only, so an Arabic keyboard typing
                  // ٨٠٠٠ would have produced an empty field with no
                  // explanation; toWesternDigits folds them on the way out.
                  FilteringTextInputFormatter.allow(
                    RegExp(r'[0-9\u0660-\u0669\u06F0-\u06F9]'),
                  ),
                  LengthLimitingTextInputFormatter(6),
                ],
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: gp.textPrimary,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                  filled: true,
                  fillColor: gp.surface,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(9),
                    borderSide: BorderSide(
                      color: invalid
                          ? GameColors.error.withOpacity(0.7)
                          : GameColors.success.withOpacity(0.45),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(9),
                    borderSide: BorderSide(
                      color: invalid ? GameColors.error : GameColors.success,
                      width: 1.5,
                    ),
                  ),
                ),
                onChanged: (_) => setState(() {
                  // Only a usable number is allowed to become the goal. An
                  // unusable one leaves the last good goal standing and says
                  // so below, so there is no way to save nothing by mistake.
                  final typed = _typedStepGoal;
                  if (typed != null) _stepGoal = typed;
                }),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                s.stepGoalFieldLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: gp.textSec,
                ),
              ),
            ),
          ],
        ),
        if (invalid) ...[
          const SizedBox(height: 5),
          Text(
            s.stepGoalOutOfRange(_stepGoalMin, _stepGoalMax),
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: context.gp.errorInk,
              height: 1.35,
            ),
          ),
        ],
      ],
    );
  }

  /// The Build / Quit change, from the switch above the box
  /// ([_goalTypeToggle]); kept apart from the widget so the rules below stay
  /// in one place if a second caller ever appears.
  void _setGoalType(GoalType type) {
    if (type == _goalType) return;
    HapticFeedback.selectionClick();
    widget.onGoalTypeChanged?.call(type);
    setState(() {
      _goalType = type;
      // A quit habit is kept or slipped once a day; there is no "three
      // times a day" to abstain. The stepper is hidden for quit habits (see
      // _frequencySection), so the count it owns goes back to one here.
      //
      // Only Daily can have run the count up, because the stepper is the
      // only thing that moves it and it renders under no other chip — so an
      // unpicked cadence has nothing to reset, and the null falls through
      // this guard correctly.
      if (type == GoalType.quit && _freqType == HabitFrequencyType.daily) {
        _timesPerDay = 1;
        _freqTarget = 1;
      }
      // The card is build-only (see _stepCardVisible), so leaving Build
      // takes it off screen. Leaving the switch on behind it meant
      // _submit's guard skipped the whole resolution and an edited habit
      // was written with clearStepGoal: true: the link went away with
      // nothing on screen having said so, and switching back to Build
      // showed a card claiming it was still on. The answer leaves with the
      // card.
      if (type == GoalType.quit && _stepLinkEnabled) {
        _stepLinkEnabled = false;
        _stepLinkTouched = true;
      }
    });
  }

  /// Build or Quit, as one joined switch above the name box. Not two
  /// _SmallPick pills: the hub's tabs sit right above in that shape, and two
  /// matching rows read as a four-way grid (see _SegmentedPair).
  Widget _goalTypeToggle(S s) => _SegmentedPair(
        firstLabel: s.goalTypeBuildOption,
        firstIcon: Icons.add_circle_outline_rounded,
        secondLabel: s.goalTypeQuitOption,
        secondIcon: Icons.do_not_disturb_on_outlined,
        firstSelected: _goalType == GoalType.build,
        onChanged: (first) =>
            _setGoalType(first ? GoalType.build : GoalType.quit),
      );

  Widget _nameSection(S s) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            selectionWidthStyle: GameTextStyles.selectionWidthStyle,
            controller: _nameCtrl,
            focusNode: _focus,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: context.gp.textPrimary,
            ),
            textCapitalization: TextCapitalization.sentences,
            onSubmitted: (_) => _isEditing ? _editStepDone() : _tryContinue(),
            decoration: InputDecoration(
              // An example rather than a question: the step bar above
              // already says «العادة».
              hintText: _goalType == GoalType.build
                  ? s.habitNameHintBuild
                  : s.habitNameHintQuit,
              prefixIcon: const Icon(Icons.edit_note_rounded, size: 20),
              // Right there while typing the name rather than a separate
              // section below — one tap opens the full picker (drag +
              // hex), no extra step needed for the common case of leaving
              // it on the category's own default color.
              suffixIcon: Padding(
                padding: const EdgeInsets.all(9),
                child: GestureDetector(
                  onTap: () async {
                    HapticFeedback.selectionClick();
                    final picked = await showHabitColorPicker(
                      context,
                      initialHex: _iconColorHex,
                    );
                    if (picked == null || !mounted) return;
                    setState(() {
                      _iconColorHex = picked.isEmpty ? null : picked;
                    });
                  },
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: _iconColor ?? Colors.transparent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _iconColorHex != null
                            ? context.gp.border
                            : context.gp.textTert,
                        width: 1.5,
                      ),
                    ),
                    child: _iconColorHex == null
                        ? Icon(Icons.palette_outlined,
                            size: 13, color: context.gp.textTert)
                        : null,
                  ),
                ),
              ),
            ),
          ),
          if (_hasName) _categoryLine(s),
          if (_hasName && _categoryRowOpen) ...[
            const SizedBox(height: 6),
            _categoryChipRow(s),
          ],
          // Right under the field whose text summoned it, because the
          // question it asks is about the name that was just typed. It is
          // also the only place in this step that is still on screen with
          // the keyboard open.
          if (_stepCardVisible) ...[
            const SizedBox(height: 12),
            _stepLinkCard(s)
                .animate()
                .fadeIn(duration: 260.ms)
                .slideY(begin: 0.08, curve: Curves.easeOutCubic)
                .scaleXY(begin: 0.97, curve: Curves.easeOutBack),
          ],
        ],
      );

  /// «الفئة: الإيمان · تغيير», under the box once there is a name: the
  /// category the name reads as, or the one picked. It used to be a 3x3
  /// grid every habit walked past. A catalog preset keeps its own, so it
  /// gets the line without «تغيير».
  Widget _categoryLine(S s) {
    final gp = context.gp;
    final style = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: gp.textTert,
    );
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 4, top: 4),
      child: Row(
        children: [
          Flexible(
            child: Text(
              s.habitCategoryLine(
                _ownCategory?.name ?? _category.localizedName(s.isAr),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          if (!_isPresetEdit) ...[
            Text(' · ', style: style),
            Semantics(
              button: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _categoryRowOpen = !_categoryRowOpen);
                },
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: Text(
                    s.habitCategoryChange,
                    style: style.copyWith(
                      fontWeight: FontWeight.w800,
                      color: context.gp.goldInk,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// The categories «تغيير» opens, as one row that scrolls sideways:
  /// «فئة جديدة» first, which makes one, then the person's own
  /// (OwnCategory), then the app's, the current one lit. Their own lead
  /// because a row that scrolls hides its far end, and a choice nobody sees
  /// is not one (Aziz found that of a link under the form, 2026-09-08).
  /// Ideas are not here: they have a page of their own ([_ideasCard]), and
  /// a category of one's own has none.
  Widget _categoryChipRow(S s) {
    final own = {...ref.watch(ownCategoriesProvider), ..._madeHere};
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const ClampingScrollPhysics(),
      child: Row(
        children: [
          _CategoryPill(
            category: HabitCategory.custom,
            iconData: Icons.add_rounded,
            label: s.ownCategoryNew,
            selected: false,
            action: true,
            onTap: () async {
              final made = await showOwnCategorySheet(context);
              if (made == null || !mounted) return;
              setState(() {
                if (!own.contains(made)) _madeHere.add(made);
                _pickOwnCategory(made);
                _categoryRowOpen = false;
              });
            },
          ),
          for (final mine in own) ...[
            const SizedBox(width: 6),
            _CategoryPill(
              category: HabitCategory.custom,
              iconData: mine.iconData,
              label: mine.name,
              selected: _ownCategory == mine,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _pickOwnCategory(mine);
                  _categoryRowOpen = false;
                });
              },
            ),
          ],
          for (final cat in _broadCategories) ...[
            const SizedBox(width: 6),
            _CategoryPill(
              category: cat,
              label: cat.localizedName(s.isAr),
              selected: _ownCategory == null && _category == cat,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _didPickCategory = true;
                  _category = cat;
                  _ownCategory = null;
                  _categoryRowOpen = false;
                });
              },
            ),
          ],
        ],
      ),
    );
  }

  /// A category of the person's own, picked: underneath it is «مخصص».
  void _pickOwnCategory(OwnCategory category) {
    _didPickCategory = true;
    _category = HabitCategory.custom;
    _ownCategory = category;
  }

  /// Whether the ideas page can offer ready-made plans: only inside the Add
  /// Habit hub, which is where the Plans tab lives.
  bool get _hasPlans =>
      widget.onOpenPlan != null || widget.onBrowsePlans != null;

  /// «أفكار وخطط جاهزة»: the one way to ideas and plans on step 1, a card
  /// with Doum holding his idea that opens the ideas page. It replaced an
  /// inline door Aziz found hard to read (2026-10-01: "I don't like the
  /// design"); the page is the "Habit ideas page" canvas he approved.
  Widget _ideasCard(S s) {
    final gp = context.gp;
    final plans = _hasPlans && _goalType == GoalType.build;
    final radius = BorderRadius.circular(18);
    return Material(
      type: MaterialType.transparency,
      child: Ink(
        decoration: BoxDecoration(
          color: GameColors.gold.withOpacity(0.10),
          borderRadius: radius,
          border: Border.all(color: GameColors.gold.withOpacity(0.35)),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: _openIdeas,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(10, 10, 12, 10),
            child: Row(
              children: [
                const Sprout(pose: SproutPose.idea, height: 52),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plans ? s.ideasEntryTitle : s.ideasEntryTitleNoPlans,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: gp.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        plans ? s.ideasEntryBody : s.ideasEntryBodyNoPlans,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: gp.textSec,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.chevron_right_rounded,
                    size: 22, color: gp.goldInk),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Opens the ideas page on the side the switch is on. A plan opens on the
  /// hub's Plans tab; an idea fills the form, then is added at once («+»,
  /// «أضفها لعاداتي») or shown on step 2 to change first («عدّلها قبل
  /// الإضافة»), so nothing is typed twice.
  Future<void> _openIdeas() async {
    FocusScope.of(context).unfocus();
    final isAr = S.of(context).isAr;
    // In the hub the page adds ideas itself, as many as the person likes
    // (Aziz, 2026-10-01). A room's picker links the one habit this sheet
    // returns, so there an idea still comes back to the form.
    final added = <String>{};
    final pick = await showHabitIdeasPage(
      context,
      goalType: _goalType,
      withPlans: _hasPlans,
      onAdd: _hasPlans ? _addIdeaNow : null,
      added: added,
      haveNames: {
        for (final h in ref.read(habitListProvider)) ...[
          h.name.trim().toLowerCase(),
          h.localName(isAr).trim().toLowerCase(),
        ],
      },
    );
    if (!mounted) return;
    // Ideas added and nothing typed here: the job is done, so the sheet
    // closes onto the board, where the last one added is lit (see
    // newlyAddedHabitIdProvider). A name typed before the ideas were opened
    // keeps the form open for it.
    if (pick == null && added.isNotEmpty && !_hasName) {
      Navigator.pop(context);
      return;
    }
    if (pick == null) return;
    switch (pick) {
      case PlanPicked(:final planId):
        if (widget.onOpenPlan case final open?) {
          open(planId);
        } else {
          widget.onBrowsePlans?.call();
        }
      case IdeaPicked(:final idea, :final addNow):
        _applyIdea(idea);
        if (addNow) {
          _tryCreate();
        } else {
          if (idea.reminderPrayer != null) _ensureLocationForPrayerCue();
          _goToStep(1, forward: true);
        }
    }
  }

  /// «أضفها لعاداتي» on the ideas page, in the hub: the idea saved as one
  /// of the person's habits as suggested, without leaving the page, so the
  /// next one can be picked. The free tier's habit limit is the one bar,
  /// and it says why. A reminder asks for notifications, and a prayer for
  /// the place its times are worked out from, the same two asks a save here
  /// makes.
  Future<bool> _addIdeaNow(HabitIdea idea) async {
    if (!canAddHabits(ref)) {
      showHabitLimitGate(context, ref);
      return false;
    }
    final s = S.of(context);
    final often = idea.often;
    final hour = idea.reminderHour;
    final cue = idea.reminderPrayer ??
        (hour == null
            ? null
            : HabitCue.time(hour, idea.reminderMinute ?? 0).toStorageValue());
    final created = ref.read(customHabitsProvider.notifier).add(
          name: idea.name(s.isAr),
          category: _canonicalCategory(idea.category),
          cueAfter: cue,
          frequencyType: often.type,
          frequencyTarget: often.isDaily ? idea.timesPerDay : often.target,
          scheduledWeekdays: [...often.weekdays],
          goalType: idea.type,
          reductionType: idea.limitAmount == null
              ? ReductionType.avoid
              : ReductionType.limit,
          limitAmount: idea.limitAmount,
          limitUnit: idea.limitUnit,
        );
    ref.read(newlyAddedHabitIdProvider.notifier).state = created.id;
    if (idea.type == GoalType.quit || cue != null) {
      _ensureNotificationPermission();
    }
    if (idea.reminderPrayer != null) _ensureLocationForPrayerCue();
    return true;
  }

  /// Fills the form from [idea]: its side, name and category, how often,
  /// a quit idea's limit, and its suggested reminder. Every answer stays
  /// the person's to change on the steps that follow.
  void _applyIdea(HabitIdea idea) {
    final s = S.of(context);
    if (idea.type != _goalType) _setGoalType(idea.type);
    // Picked, so the name below does not move the category.
    _didPickCategory = true;
    _category = _canonicalCategory(idea.category);
    _ownCategory = null;
    _nameCtrl.text = idea.name(s.isAr);
    setState(() {
      _hasName = true;
      _categoryRowOpen = false;
      final often = idea.often;
      _freqType = often.type;
      _selectedWeekdays = {...often.weekdays};
      if (often.isDaily) {
        _timesPerDay = idea.timesPerDay;
        _freqTarget = idea.timesPerDay;
      } else {
        _freqTarget = often.target;
      }
      if (idea.type == GoalType.quit) {
        _reductionType = idea.limitAmount == null
            ? ReductionType.avoid
            : ReductionType.limit;
        _limitCtrl.text = idea.limitAmount?.toString() ?? '';
        _customUnitCtrl.text = idea.limitUnit == null
            ? ''
            : s.limitUnitLabel(idea.limitUnit!.name);
      }
      _openOffsetRow = -1;
      _reminderOffset = 0;
      _extraOffsets = {};
      _prayerRows = [null];
      // A prayer idea counted several times a day starts its first row on
      // that prayer; the rows after it are left to the person.
      if (idea.reminderPrayer != null) {
        _timingMode = _TimingMode.prayer;
        _selectedPrayer = idea.reminderPrayer;
      } else if (idea.reminderHour != null) {
        _timingMode = _TimingMode.time;
        _pickedTimes = [
          TimeOfDay(hour: idea.reminderHour!, minute: idea.reminderMinute ?? 0),
        ];
        _pickedOffsets = [0];
      } else {
        _timingMode = null;
      }
      _fromIdea = true;
    });
  }

  /// A quit habit's question, right under its name: quit fully, or limit
  /// it, and the limit typed as a number and a unit (canvas v8, Aziz
  /// 2026-09-30: "custom only no need for chips, user set what he wants").
  Widget _quitStyleSection(S s) {
    final gp = context.gp;
    final limit = _reductionType == ReductionType.limit;
    final error = _limitMissing && _limitErrorShown;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: gp.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            s.quitStyleQuestion,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: gp.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          _SegmentedRow(
            labels: [s.quitFullyOption, s.quitLimitOption],
            selected: limit ? 1 : 0,
            onChanged: (i) {
              HapticFeedback.selectionClick();
              setState(() => _reductionType =
                  i == 1 ? ReductionType.limit : ReductionType.avoid);
            },
          ),
          if (limit) ...[
            const SizedBox(height: 12),
            // [amount] [unit] «في اليوم», one line, the boxes level.
            Row(
              children: [
                SizedBox(
                  width: 76,
                  child: TextField(
                    selectionWidthStyle: GameTextStyles.selectionWidthStyle,
                    controller: _limitCtrl,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    // Arabic-Indic digits let through (٢), folded on save.
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'[0-9٠-٩۰-۹]'),
                      ),
                      LengthLimitingTextInputFormatter(5),
                    ],
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: gp.textPrimary,
                    ),
                    // No hint: «الحد الأقصى» does not fit a box sized for a
                    // number, and the line under the row says what to type.
                    decoration: InputDecoration(
                      isDense: true,
                      enabledBorder: error
                          ? OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: GameColors.error.withOpacity(0.7),
                              ),
                            )
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    selectionWidthStyle: GameTextStyles.selectionWidthStyle,
                    controller: _customUnitCtrl,
                    textCapitalization: TextCapitalization.sentences,
                    style: TextStyle(
                      // The amount box's size, so the two boxes are one height.
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: gp.textPrimary,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: s.limitUnitLabel(LimitUnit.times.name),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  s.limitPerDay,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: gp.textSec,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Only after somebody has actually tried to move on with the
            // number empty does the line under the boxes turn into the
            // refusal: before that it says what the unit box is for.
            Text(
              error ? s.limitAmountRequired : s.limitUnitHelp,
              style: TextStyle(
                fontSize: 11,
                height: 1.35,
                fontWeight: error ? FontWeight.w700 : FontWeight.w500,
                color: error ? context.gp.errorInk : gp.textTert,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Step 2: how often ────────────────────────────────────────────────

  Widget _stepOften(S s) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _summaryStrip(s, withXp: true)
              .animate()
              .fadeIn(duration: 240.ms)
              .slideY(begin: 0.06, curve: Curves.easeOutCubic),
          // Filled from an idea: say so, so the lit answer below reads as a
          // suggestion to change rather than a choice somebody made.
          if (_fromIdea && !_isEditing) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: GameColors.gold.withOpacity(0.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.auto_awesome_rounded,
                      size: 16, color: context.gp.goldInk),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s.ideasFromIdeaNote,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: context.gp.textSec,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          Text(
            _goalType == GoalType.quit
                ? s.howOftenQuestionQuit
                : s.howOftenQuestion,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: context.gp.textPrimary,
            ),
          ).animate(delay: 30.ms).fadeIn(duration: 240.ms),
          const SizedBox(height: 12),
          _oftenSection(s)
              .animate(delay: 60.ms)
              .fadeIn(duration: 240.ms)
              .slideY(begin: 0.06, curve: Curves.easeOutCubic),
        ],
      );

  /// Which of the three is lit, or null while nobody has picked one.
  int? get _oftenIndex {
    if (_freqType == null) return null;
    if (_selectedWeekdays.isNotEmpty) return 2;
    return _freqType == HabitFrequencyType.weekly ? 1 : 0;
  }

  /// One choice in one row, «كل يوم | مرات بالأسبوع | أيام معيّنة», and what
  /// that choice needs next in its own panel under it, so it never looks
  /// like a fourth option (Aziz, 2026-09-30: "make it not a list... user may
  /// think it's another option").
  Widget _oftenSection(S s) => Column(
        key: _repeatSectionKey,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SegmentedRow(
            labels: [s.oftenEveryDay, s.oftenTimesAWeek, s.oftenSetDays],
            selected: _oftenIndex,
            onChanged: _pickOften,
          ),
          // Only once «متابعة» has been pressed with nothing picked, and in
          // the error colour, where the answer is owed. It used to be a small
          // grey «اختر وحدة» beside a button that looked ready.
          if (_freqType == null && _repeatErrorShown) ...[
            const SizedBox(height: 8),
            Text(
              s.repeatPickOne,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: context.gp.errorInk,
              ),
            ),
          ],
          AnimatedSize(
            duration: GameMotion.standard,
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _oftenPanel(s) ?? const SizedBox(width: double.infinity),
          ),
        ],
      );

  void _pickOften(int index) {
    HapticFeedback.selectionClick();
    setState(() {
      switch (index) {
        case 0:
          _freqType = HabitFrequencyType.daily;
          // Not a flat 1: for a daily habit this field IS the per-day count
          // (effectiveDailyTarget), and the stepper owns it. Coming from a
          // number a week, that number is meaningless here, so only a count
          // this mode itself could have produced survives the switch.
          _freqTarget = _dailyTargetInRange;
          _selectedWeekdays.clear();
        case 1:
          _freqType = HabitFrequencyType.weekly;
          // Keeps an already-reasonable target (switching back from set
          // days, say) instead of always resetting to 1.
          _freqTarget = _weeklyTargetInRange;
          _selectedWeekdays.clear();
        default:
          _freqType = HabitFrequencyType.weekly;
          if (_selectedWeekdays.isEmpty) {
            _selectedWeekdays.add(DateTime.now().effectiveDay.weekday);
          }
          _freqTarget = _selectedWeekdays.length;
      }
    });
  }

  /// What the picked choice needs next, in its own box: times a day for a
  /// daily build habit, the 1 to 6 count for a number a week, the days for
  /// set days. Null when the choice needs nothing more (a daily quit habit,
  /// which is kept or slipped once a day) or nothing is picked.
  Widget? _oftenPanel(S s) {
    final gp = context.gp;
    Widget panel(Widget child) => Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: gp.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: gp.border, width: 0.5),
            ),
            child: child,
          ),
        );
    Widget question(String text) => Text(
          text,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w800,
            color: gp.textPrimary,
          ),
        );
    switch (_oftenIndex) {
      case 0 when _goalType == GoalType.build:
        // Daily's own count, see _TimesPerDayRow. On screen at its resting
        // 1 too, which is how anyone finds out the setting exists at all.
        return panel(_TimesPerDayRow(
          count: _dailyTargetInRange,
          onChanged: (v) => setState(() {
            _timesPerDay = v.clamp(1, kMaxTimesPerDay);
            // Mirrored immediately because _submit persists _freqTarget;
            // this mode is the one where the two are the same number.
            _freqTarget = _timesPerDay;
            // A prayer stays a prayer: with more times a day it becomes the
            // first of a prayer per time (see _prayerRows), and back at once
            // a day the first row is the prayer again. Words typed for the
            // moment are one moment, so several times move them onto the
            // clock, the mode that can hold several.
            if (_timesPerDay > 1 && _timingMode == _TimingMode.text) {
              _timingMode = _TimingMode.time;
            }
          }),
        ));
      case 1:
        // Capped at 6: seven a week is every day.
        return panel(Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            question(s.oftenWeekQuestion),
            const SizedBox(height: 10),
            Row(
              children: [
                for (var n = 1; n <= 6; n++) ...[
                  if (n > 1) const SizedBox(width: 6),
                  Expanded(
                    child: _EqualPill(
                      selected: _weeklyTargetInRange == n,
                      label: '$n',
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _freqTarget = n);
                      },
                    ),
                  ),
                ],
              ],
            ),
          ],
        ));
      case 2:
        return panel(Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            question(s.oftenDaysQuestion),
            const SizedBox(height: 10),
            Row(
              children: [
                for (final entry in _weekdays(context).asMap().entries) ...[
                  if (entry.key > 0) const SizedBox(width: 6),
                  Expanded(
                    child: _EqualPill(
                      selected: _selectedWeekdays.contains(entry.value.$1),
                      label: entry.value.$2,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() {
                          if (!_selectedWeekdays.remove(entry.value.$1)) {
                            _selectedWeekdays.add(entry.value.$1);
                          }
                          // Never no days: the last one stays lit.
                          if (_selectedWeekdays.isEmpty) {
                            _selectedWeekdays.add(entry.value.$1);
                          }
                          _freqType = HabitFrequencyType.weekly;
                          _freqTarget = _selectedWeekdays.length;
                        });
                      },
                    ),
                  ),
                ],
              ],
            ),
          ],
        ));
      default:
        return null;
    }
  }

  // ── Step 3: the reminder (optional) ──────────────────────────────────

  /// Starts clean: two choices, a clock time or a prayer, and nothing picked
  /// is a real answer («اختياري، تقدر تضيف العادة بدون تذكير.»). The
  /// prayers appear only after «مع وقت صلاة» (Aziz, 2026-09-30: prayers are
  /// "not the main"), then the reminder rows. Writing the moment in words
  /// is gone ("the custom text, maybe no need"); a habit that already has
  /// words keeps them (see [_writtenMomentCard]).
  Widget _stepReminder(S s) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _summaryStrip(s, withXp: false)
              .animate()
              .fadeIn(duration: 240.ms)
              .slideY(begin: 0.06, curve: Curves.easeOutCubic),
          // The link, named on the last screen before the button that
          // creates it, so the OS permission sheet does not arrive out of
          // nowhere two steps after the card.
          if (_stepCardVisible && _stepLinkEnabled) ...[
            const SizedBox(height: 8),
            _stepLinkRecap(s),
          ],
          const SizedBox(height: 18),
          Text(
            s.reminderQuestion,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: context.gp.textPrimary,
            ),
          ).animate(delay: 30.ms).fadeIn(duration: 240.ms),
          const SizedBox(height: 4),
          Text(
            s.reminderOptionalNote,
            style: TextStyle(fontSize: 12, color: context.gp.textTert),
          ).animate(delay: 30.ms).fadeIn(duration: 240.ms),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ReminderKindCard(
                  kind: ReminderKind.clock,
                  label: s.reminderAtClock,
                  selected: _timingMode == _TimingMode.time,
                  onTap: () => _pickReminderKind(_TimingMode.time),
                ),
              ),
              // Offered at any count: a habit counted several times a day
              // takes a prayer per time (Aziz, 2026-10-01), see
              // _multiPrayerContent.
              const SizedBox(width: 10),
              Expanded(
                child: ReminderKindCard(
                  kind: ReminderKind.prayer,
                  label: s.reminderWithPrayer,
                  selected: _timingMode == _TimingMode.prayer,
                  onTap: () => _pickReminderKind(_TimingMode.prayer),
                ),
              ),
            ],
          ).animate(delay: 60.ms).fadeIn(duration: 240.ms),
          AnimatedSize(
            duration: GameMotion.standard,
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: GameMotion.standard,
              child: KeyedSubtree(
                key: ValueKey(_timingMode),
                child: switch (_timingMode) {
                  null => const SizedBox(width: double.infinity),
                  _TimingMode.time => Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: _timeModeContent(s),
                    ),
                  _TimingMode.prayer => Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: _prayerModeContent(s),
                    ),
                  _TimingMode.text => Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: _writtenMomentCard(s),
                    ),
                },
              ),
            ),
          ),
        ],
      );

  /// A choice tapped. Tapped again it is taken back, and no reminder is the
  /// answer again; that also takes with it what only means anything beside
  /// a cue, the alarm choice and the quiet-hours override, since both are
  /// written on save. The picked times and the prayer are kept: they are
  /// only ever saved through a picked mode, and a choice taken back and
  /// made again should not ask for them again.
  ///
  /// A clock time with none picked yet opens the time picker straight away:
  /// the time is what was just asked for.
  void _pickReminderKind(_TimingMode mode) {
    HapticFeedback.selectionClick();
    if (_timingMode == mode) {
      setState(() {
        _timingMode = null;
        _openOffsetRow = -1;
        _alarm = false;
        _ignoreQuietHours = false;
      });
      return;
    }
    setState(() {
      _timingMode = mode;
      // The reminders carry over from a clock time, so the side the offset
      // sheet leans to comes with them (see _followReminderSide).
      _followReminderSide();
    });
    if (mode == _TimingMode.time && !_isMultiTime && _pickedTime == null) {
      _pickTime();
    }
    if (mode == _TimingMode.prayer && _selectedPrayer != null) {
      _ensureLocationForPrayerCue();
    }
  }

  /// A habit saved with its moment in words («بعد العمل»), kept as it is
  /// when the habit is edited (Aziz, 2026-10-01, "pick the simple option").
  /// The × takes it off; a clock time or a prayer picked above replaces it.
  Widget _writtenMomentCard(S s) {
    final gp = context.gp;
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 4, 10),
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: gp.border, width: 0.5),
      ),
      child: Row(
        children: [
          Icon(Icons.notes_rounded, size: 18, color: context.gp.goldInk),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.habitWrittenMoment,
                  style: TextStyle(fontSize: 11, color: gp.textTert),
                ),
                const SizedBox(height: 2),
                Text(
                  _cueCtrl.text.trim(),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: gp.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: s.habitReminderRemove,
            onPressed: () {
              HapticFeedback.selectionClick();
              setState(() {
                _timingMode = null;
                _alarm = false;
                _ignoreQuietHours = false;
              });
            },
            icon: Icon(Icons.close_rounded, size: 18, color: gp.textTert),
          ),
        ],
      ),
    );
  }

  Widget _timeModeContent(S s) {
    final count = _effectiveTimeCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          // What _timeRow's Ink and InkWell paint on, so a press shows.
          // Transparent: the row's own Ink still owns its look.
          Material(
            type: MaterialType.transparency,
            child: _timeRow(s, i, count),
          ),
        ],
        // The offset section below is for the SINGLE-time case only. With
        // several times it moves inside each row instead: a floating
        // «ذكّرني» block under a list of times says nothing about which time
        // it governs, and the honest answer (all of them) is not what someone
        // reading it assumes. Reported from a two-time habit where the block
        // sat under the second row and read as belonging to it.
        if (!_isMultiTime && _filledTimes.isNotEmpty) _reminderOffsetSection(s),
        // Several times a day keep their shift inside each row, but the
        // alarm choice is about the habit, not one of its times, so it
        // stays here, once, under the list.
        // A quit habit's reminder is a check-in and never rings as an alarm
        // (see NotificationService._scheduleOne), so it is not offered one.
        if (_isMultiTime &&
            _filledTimes.isNotEmpty &&
            _goalType == GoalType.build)
          if (_goalType == GoalType.build) _reminderStyleRow(s),
      ],
    );
  }

  /// One occurrence's time picker. Carries its 1-based position only when
  /// there is more than one, so the single-time case is visually unchanged.
  ///
  /// The position is a bare numeral rather than a phrase: it needs no
  /// translation, costs no new string, and reads identically in both scripts.
  Widget _timeRow(S s, int slot, int count) {
    final gp = context.gp;
    final picked = slot < _pickedTimes.length ? _pickedTimes[slot] : null;
    final offset = slot < _pickedOffsets.length ? _pickedOffsets[slot] : 0;
    final open = _openOffsetRow == slot;
    // ── Two rows on the same minute ─────────────────────────────────────
    //
    // The cue dedupes by minute (HabitCue.timesWithOffsets), so saving two
    // rows set to the same time keeps ONE of them and drops the other's shift
    // with it. Silently. And it is easy to reach by accident: every picker
    // opens on the current clock, so confirming twice without changing
    // anything produces exactly this.
    //
    // Flagged on the LATER row, never the earlier one — the first is the one
    // being kept, and colouring both would say "these are equally wrong" when
    // only one of them is about to disappear.
    final duplicate = picked != null &&
        [
          for (var i = 0; i < slot && i < _pickedTimes.length; i++)
            _pickedTimes[i],
        ].any((t) => t != null && t.hour == picked.hour && t.minute == picked.minute);
    // Two targets, two jobs, and each looks like what it does. The time text
    // opens the picker (the common action, one tap, exactly as it always was);
    // the shift chip beside it opens this occurrence's before/after choices.
    // Making the whole row one target and hiding "change the time" a level
    // down would tax the frequent action to make room for the rare one.
    // Ink, not a filled Container: InkWell paints its press highlight on the
    // nearest Material, and a Container's solid fill sat on top of that and
    // hid it. The transparent Material it paints on is wrapped round this row
    // in _timeModeContent.
    return Ink(
      width: double.infinity,
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: duplicate
              ? GameColors.error.withOpacity(0.55)
              : open
                  ? GameColors.gold.withOpacity(0.55)
                  : gp.border,
          width: (open || duplicate) ? 1 : 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _pickTime(slot),
                  child: Padding(
                    // With the chevron inside, the row ends in its own
                    // padding. Beside the shift chip it hands that edge on.
                    // Directional both ways: a left and right inset put the
                    // clock 6pt from the right edge in Arabic on a two-time
                    // row, against 14pt on a one-time row.
                    padding: count > 1 && picked != null
                        ? const EdgeInsetsDirectional.fromSTEB(14, 14, 6, 14)
                        : const EdgeInsetsDirectional.fromSTEB(14, 14, 14, 14),
                    child: Row(
                      children: [
                        Icon(
                          Icons.schedule_rounded,
                          size: 18,
                          color: picked == null ? gp.textTert : context.gp.goldInk,
                        ),
                        const SizedBox(width: 10),
                        if (count > 1) ...[
                          Text(
                            '${slot + 1}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: gp.textTert,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(
                            picked == null
                                ? s.pickATime
                                : HabitCue.time(picked.hour, picked.minute)
                                    .labelForLocale(s.isAr),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: picked == null
                                  ? FontWeight.w600
                                  : FontWeight.w800,
                              color: picked == null
                                  ? gp.textTert
                                  : gp.textPrimary,
                            ),
                          ),
                        ),
                        // Inside the tap area, not beside it: the chevron was
                        // the row's only tap cue and tapping it did nothing.
                        // Gold like «أضف تذكير», so it reads as the way in.
                        if (!(count > 1 && picked != null)) ...[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 20,
                            color: context.gp.goldInk,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              // Only once there is a time to shift, and only while the habit
              // is multi-time — with one time the section below the list is
              // still the right home for this.
              if (count > 1 && picked != null)
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _openOffsetRow = open ? -1 : slot);
                  },
                  child: Padding(
                    padding:
                        const EdgeInsetsDirectional.fromSTEB(4, 14, 12, 14),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _offsetPresetLabel(s, offset),
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: offset == 0
                                ? gp.textTert
                                : context.gp.goldInk,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          open
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                          size: 18,
                          color: gp.textTert,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          if (duplicate)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Row(
                children: [
                  Icon(Icons.error_outline_rounded,
                      size: 13, color: context.gp.errorInk),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      s.habitDuplicateTime,
                      style: TextStyle(
                        fontSize: 10.5,
                        height: 1.4,
                        color: context.gp.errorInk,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (open) ...[
            Divider(height: 1, thickness: 0.5, color: gp.divider),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ChipGrid(
                    columns: 3,
                    items: [
                      for (final preset in _offsetPresets)
                        _PlainChoiceChip(
                          selected: offset == preset,
                          label: _offsetPresetLabel(s, preset),
                          onTap: () => _setRowOffset(slot, preset),
                        ),
                      // Sixth cell, so the grid is two complete rows of three
                      // rather than five with a hole. Selected whenever the
                      // row's shift is not one of the presets, which is the
                      // only way a person can tell at a glance that the value
                      // above came from here.
                      _PlainChoiceChip(
                        selected: !_offsetPresets.contains(offset),
                        label: s.leadCustomOption,
                        onTap: () => _pickRowOffset(s, slot, picked, offset),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Says the resolved moment, not just the shift. "15 minutes
                  // before" is an instruction; "7:45" is the answer, and the
                  // answer is what someone checks.
                  Text(
                    s.remindAtTimePreview(_shiftedLabel(s, picked, offset)),
                    style: TextStyle(fontSize: 11, color: gp.textTert),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _setRowOffset(int slot, int minutes) {
    HapticFeedback.selectionClick();
    setState(() {
      while (_pickedOffsets.length <= slot) {
        _pickedOffsets.add(0);
      }
      _pickedOffsets[slot] = minutes;
    });
  }

  /// Opens the custom-shift sheet for ONE occurrence.
  ///
  /// The anchor goes in so the sheet can show where the reminder actually
  /// lands and name which occurrence is being adjusted — with four rows on
  /// screen, a sheet that said only «تذكير مخصص» would leave the person
  /// guessing which one they opened.
  Future<void> _pickRowOffset(
    S s,
    int slot,
    TimeOfDay? anchor,
    int current,
  ) async {
    final chosen = await showHabitOffsetSheet(
      context,
      current: current,
      anchor: anchor,
      // Opened on an occurrence that exists, so its button says «حفظ».
      editing: true,
    );
    // Null is a dismissal, 0 is a deliberate "on the dot" — a bare int could
    // not tell those apart, and backing out would silently clear the shift.
    if (chosen == null || !mounted) return;
    _setRowOffset(slot, chosen);
  }

  /// [picked] shifted by [offset], as a clock label. Wraps around midnight,
  /// which a 30-minute lead on a 00:15 reminder genuinely does.
  String _shiftedLabel(S s, TimeOfDay? picked, int offset) {
    if (picked == null) return '';
    final total = (picked.hour * 60 + picked.minute + offset) % (24 * 60);
    final m = total < 0 ? total + 24 * 60 : total;
    return HabitCue.time(m ~/ 60, m % 60).labelForLocale(s.isAr);
  }

  /// The prayers, then the picked prayer's reminder rows.
  ///
  /// No «قبل | بعد» pair above the prayers. One stood here, first saving
  /// nothing for a prayer habit and then (395968d) standing for the
  /// reminders' side, while the offset sheet every row opens asked the same
  /// question again, so Aziz had it taken off this step (2026-09-12). A
  /// prayer reminder's side is chosen in that sheet and read back on its
  /// row, «قبل الفجر بـ15 دقيقة».
  ///
  /// Each prayer carries today's time under its name once a place is known
  /// (canvas v8), so picking one is picking a time, not a word.
  Widget _prayerModeContent(S s) {
    if (_isMultiTime) return _multiPrayerContent(s);
    final settings = ref.watch(notificationSettingsProvider);
    final loc = settings.location;
    // Offline and today only, the same source the reminder rows' times use
    // (see _reminderAnchorTime).
    final today = loc == null
        ? null
        : PrayerTimesService.calculateOfflineCorrected(
            latitude: loc.lat,
            longitude: loc.lng,
            date: DateTime.now(),
            countryCode: settings.resolvedCountryCode,
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (final key in _prayerKeys) ...[
              if (key != _prayerKeys.first) const SizedBox(width: 6),
              Expanded(
                child: _EqualPill(
                  selected: _selectedPrayer == key,
                  label: HabitCue.preset(key).labelFor(context),
                  sublabel: switch (today?.forKey(key)) {
                    final at? =>
                      HabitCue.time(at.hour, at.minute).labelForLocale(s.isAr),
                    null => null,
                  },
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedPrayer = key);
                    _ensureLocationForPrayerCue();
                  },
                ),
              ),
            ],
          ],
        ),
        if (_selectedPrayer != null) _reminderOffsetSection(s),
      ],
    );
  }

  /// A prayer per time, for a habit counted several times a day (Aziz,
  /// 2026-10-01: "option 2, but user can set like 30 min before fajr, and 30
  /// after fajr, so it should be well designed to do that").
  ///
  /// One row per time, the shape the clock times have: its number, then the
  /// whole reminder in words, «قبل الفجر بـ30 دقيقة», and where that lands
  /// today. A row opens one sheet that asks the prayer and the side together
  /// (showPrayerSlotSheet), so a row is set in two taps: a prayer, an
  /// amount. Above the rows, one line says the thing nobody would guess,
  /// that one prayer can take two.
  ///
  /// A row left empty is no reminder for that time, never a block: the
  /// habit saves with the rows that are set, as a clock time left unpicked
  /// always has.
  Widget _multiPrayerContent(S s) {
    final gp = context.gp;
    final count = _effectiveTimeCount;
    final anySet = _multiPrayerEntries.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          s.prayerPerTimeNote,
          style: TextStyle(fontSize: 12, color: gp.textTert, height: 1.4),
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _prayerRowTile(s, i, count),
        ],
        _reminderLocationNotice(s),
        if (anySet && _goalType == GoalType.build) _reminderStyleRow(s),
        if (anySet) _quietHoursWarning(s),
      ],
    );
  }

  /// One time's row in [_multiPrayerContent], the whole box one tap target.
  /// A later row set to the same prayer and side as an earlier one is
  /// outlined and says it would be kept once, the way a clock row on the
  /// same minute does.
  Widget _prayerRowTile(S s, int i, int count) {
    final gp = context.gp;
    final row = _prayerRow(i);
    final settings = ref.watch(notificationSettingsProvider);
    final name = row == null
        ? null
        : HabitCue.preset(row.prayer).labelForLocale(s.isAr);
    final sentence = row == null
        ? s.pickAPrayer
        : habitReminderSentence(row.offset, s, prayer: name);
    final anchor = row == null ? null : _prayerToday(row.prayer, settings);
    final landsAt = anchor?.add(Duration(minutes: row!.offset));
    final time = landsAt == null
        ? null
        : HabitCue.time(landsAt.hour, landsAt.minute).labelForLocale(s.isAr);
    final duplicate = row != null &&
        [for (var j = 0; j < i; j++) _prayerRow(j)].contains(row);
    final radius = BorderRadius.circular(14);
    return Material(
      type: MaterialType.transparency,
      child: Ink(
        decoration: BoxDecoration(
          color: gp.surface,
          borderRadius: radius,
          border: Border.all(
            color: duplicate ? GameColors.error.withOpacity(0.55) : gp.border,
            width: duplicate ? 1 : 0.5,
          ),
        ),
        child: Semantics(
          container: true,
          button: true,
          label: [
            s.prayerSlotTitle(i + 1),
            if (time == null) sentence else s.habitReminderRowSemantics(sentence, time),
          ].join('، '),
          child: InkWell(
            borderRadius: radius,
            onTap: () => _editPrayerRow(i),
            child: ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(14, 13, 12, 13),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.mosque_outlined,
                          size: 18,
                          color: row == null ? gp.textTert : context.gp.goldInk,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: gp.textTert,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            sentence,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.3,
                              fontWeight:
                                  row == null ? FontWeight.w600 : FontWeight.w800,
                              color: row == null ? gp.textTert : gp.textPrimary,
                            ),
                          ),
                        ),
                        if (time != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            time,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: gp.textSec,
                            ),
                          ),
                        ],
                        const SizedBox(width: 4),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 20,
                          color: context.gp.goldInk,
                        ),
                      ],
                    ),
                    if (duplicate) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.error_outline_rounded,
                              size: 13, color: context.gp.errorInk),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              s.habitDuplicateTime,
                              style: TextStyle(
                                fontSize: 10.5,
                                height: 1.4,
                                color: context.gp.errorInk,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// A row tapped: the sheet opens on its prayer and side, or for an empty
  /// row on the one most people mean next. After a row set BEFORE a prayer
  /// that is the same prayer, after it: «30 before Fajr» then «30 after
  /// Fajr» is two taps. After any other, the next prayer of the day. The
  /// first row with nothing above it opens on Fajr. The side leans «بعد»,
  /// the side a prayer habit's sheet has always opened on.
  Future<void> _editPrayerRow(int i) async {
    final s = S.of(context);
    final settings = ref.read(notificationSettingsProvider);
    final row = _prayerRow(i);
    PrayerSlot? above;
    for (var j = i - 1; j >= 0 && above == null; j--) {
      above = _prayerRow(j);
    }
    final lean = switch (above) {
      null => _prayerKeys.first,
      (prayer: final p, offset: < 0) => p,
      (prayer: final p, offset: _) =>
        _prayerKeys[(_prayerKeys.indexOf(p) + 1) % _prayerKeys.length],
    };
    final picked = await showPrayerSlotSheet(
      context,
      title: s.prayerSlotTitle(i + 1),
      prayers: [
        for (final key in _prayerKeys)
          (
            key: key,
            label: HabitCue.preset(key).labelForLocale(s.isAr),
            at: switch (_prayerToday(key, settings)) {
              final at? => TimeOfDay(hour: at.hour, minute: at.minute),
              null => null,
            },
          ),
      ],
      prayer: row?.prayer ?? lean,
      current: row?.offset,
      clearable: row != null,
    );
    if (picked == null || !mounted) return;
    HapticFeedback.selectionClick();
    setState(() => _setPrayerRow(i, picked.slot));
    // The first prayer set is what the rows' times need a place for, asked
    // now rather than at save, the way a single prayer asks on its tap.
    if (picked.slot != null) _ensureLocationForPrayerCue();
  }

  /// «ذكّرني», under Time and Prayer mode once a concrete anchor is picked
  /// (see the two call sites above). Custom Text mode never shows this: a
  /// freeform cue has no resolved clock or prayer moment for an offset to
  /// mean anything against.
  ///
  /// One row per reminder, each naming its shift and the clock time it
  /// lands on today, then a row that adds another. Tapping a row opens the
  /// offset sheet with that reminder loaded; the add row opens it empty.
  /// The chip grid that used to sit here, first behind a link and then in
  /// the open, was the busiest thing on the step for a choice most people
  /// leave on «في الوقت»; a list is exactly as long as what was chosen
  /// (Aziz, 2026-09-06).
  ///
  /// Free keeps one row: its add row wears a lock and opens the premium
  /// gate, the same gate the chips used to send people to. A premium habit
  /// at its cap keeps the row too, dimmed, and says why on tap.
  Widget _reminderOffsetSection(S s) {
    final settings = ref.watch(notificationSettingsProvider);
    final anchor = _reminderAnchorTime(settings);
    final offsets = _allReminderOffsets;
    final isPremium = ref.watch(premiumAccessProvider);
    final gate = canAddHabitReminder(
      current: offsets.length,
      isPremium: isPremium,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 14),
        _SectionLabel(s.remindMeSection),
        const SizedBox(height: 8),
        for (final offset in offsets) ...[
          _reminderRow(
            s,
            offset,
            anchor: anchor,
            removable: offsets.length > 1,
            locked: !_reminderStack.canEdit(offset, isPremium: isPremium),
          ),
          const SizedBox(height: 6),
        ],
        _addReminderRow(s, locked: gate.locked, full: !gate.allowed),
        _reminderLocationNotice(s),
        if (_offsetNotice != null) _offsetNoticeLine(_offsetNotice!),
        if (_goalType == GoalType.build) _reminderStyleRow(s),
        _quietHoursWarning(s),
      ],
    );
  }

  /// [_offsetNotice] as a line under the reminder list, for a tap there
  /// that was refused.
  Widget _offsetNoticeLine(String message) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded,
                size: 13, color: context.gp.textTert),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: context.gp.textTert,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      );

  /// A reminder the habit carries, written as the whole reminder: with a
  /// prayer «قبل الفجر بـ15 دقيقة» (see habitReminderSentence), with a clock
  /// time its shift in words, «قبل 15 دقيقة». Then where that lands today
  /// once the anchor resolves, at the far end beside the chevron. Same box
  /// as a time row so the two lists read as one family.
  ///
  /// The whole box is one tap target, chevron included. The chevron used to
  /// sit outside the InkWell, so the row's only tap cue did nothing when it
  /// was tapped, and a solid Container fill hid the press highlight. The fill
  /// is Ink on a transparent Material now, so a press shows.
  ///
  /// The close mark only shows once there is a second row to fall back on;
  /// the last reminder is edited, never removed, which is the rule
  /// HabitReminderStack keeps. It sits after a thin divider in its own tap
  /// area, and the row keeps its chevron beside it.
  ///
  /// [locked]: an extra kept from a Premium that has ended. The chevron
  /// becomes the add row's lock, so the rows that open the gate are told
  /// apart before the tap, and the × beside it still takes it off.
  Widget _reminderRow(
    S s,
    int offset, {
    required DateTime? anchor,
    required bool removable,
    bool locked = false,
  }) {
    final gp = context.gp;
    final landsAt = anchor?.add(Duration(minutes: offset));
    // Built the way the offset sheet builds its times, from plain integers.
    // DateFormat('h:mm a', 'ar') picks up flutter_localizations' Arabic digit
    // data, which drew ٤:٠٣ on this row while the sheet drew 4:03.
    final time = landsAt == null
        ? null
        : HabitCue.time(landsAt.hour, landsAt.minute).labelForLocale(s.isAr);
    final sentence = _offsetRowLabel(s, offset);
    final radius = BorderRadius.circular(14);
    return Material(
      type: MaterialType.transparency,
      child: Ink(
        decoration: BoxDecoration(
          color: gp.surface,
          borderRadius: radius,
          border: Border.all(color: gp.border, width: 0.5),
        ),
        child: Row(
          children: [
            Expanded(
              // One button to a screen reader: the sentence, then the time.
              child: Semantics(
                container: true,
                button: true,
                label: time == null
                    ? sentence
                    : s.habitReminderRowSemantics(sentence, time),
                child: InkWell(
                  borderRadius: radius,
                  onTap: () => _editReminder(offset),
                  child: ExcludeSemantics(
                    child: Padding(
                      padding: EdgeInsetsDirectional.fromSTEB(
                        14,
                        13,
                        removable ? 8 : 12,
                        13,
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.notifications_active_rounded,
                              size: 18, color: context.gp.goldInk),
                          const SizedBox(width: 10),
                          Expanded(
                            // Two lines before any «…»: the amount comes
                            // last in Arabic, and one line cut it off.
                            child: Text(
                              sentence,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: gp.textPrimary,
                                height: 1.3,
                              ),
                            ),
                          ),
                          if (time != null) ...[
                            const SizedBox(width: 8),
                            Text(
                              time,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: gp.textSec,
                              ),
                            ),
                          ],
                          const SizedBox(width: 4),
                          Icon(
                            locked
                                ? Icons.lock_outline_rounded
                                : Icons.chevron_right_rounded,
                            size: locked ? 18 : 20,
                            color: context.gp.goldInk,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (removable) ...[
              Container(width: 0.5, height: 24, color: gp.divider),
              Semantics(
                container: true,
                button: true,
                label: s.habitReminderRemove,
                child: InkWell(
                  borderRadius: radius,
                  onTap: () => _toggleReminderOffset(offset),
                  child: ExcludeSemantics(
                    child: Padding(
                      // 12 + 18 + 14: a 44pt target, the minimum, beside a
                      // divider where a near miss opens the sheet instead.
                      padding:
                          const EdgeInsetsDirectional.fromSTEB(12, 14, 14, 14),
                      child: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: gp.textTert,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// The row that grows the list. Gold outline rather than a filled box so
  /// it reads as an action under the rows, not as one more of them.
  Widget _addReminderRow(S s, {required bool locked, required bool full}) =>
      Opacity(
        opacity: full && !locked ? 0.5 : 1,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _addReminder,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: GameColors.gold.withOpacity(0.35),
                width: 0.5,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  locked ? Icons.lock_outline_rounded : Icons.add_rounded,
                  size: 18,
                  color: context.gp.goldInk,
                ),
                const SizedBox(width: 10),
                Text(
                  s.habitAddReminderRow,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: context.gp.goldInk,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  /// The row's sentence: the prayer and the side in prayer mode («قبل الفجر
  /// بـ15 دقيقة»), the words it always had for a clock time. See
  /// habitReminderSentence.
  String _offsetRowLabel(S s, int offset) =>
      habitReminderSentence(offset, s, prayer: _prayerName(s));

  /// What the offset sheet shifts from, as a clock time: the picked time,
  /// or today's prayer once a location is known. Null leaves the sheet with
  /// no time in its "relative to" line and no resolved preview; a prayer is
  /// still named there (see [_prayerName]).
  TimeOfDay? get _sheetAnchor {
    final anchor = _reminderAnchorTime(ref.read(notificationSettingsProvider));
    return anchor == null
        ? null
        : TimeOfDay(hour: anchor.hour, minute: anchor.minute);
  }

  /// Keeps the side the offset sheet leans to in step with the reminders.
  /// Called after every change to them (edit, add, ×) and on entering prayer
  /// mode, inside the caller's setState.
  ///
  /// While the reminders sit on one side, [_reminderLean] is that side, so
  /// once they are all back on time the next sheet still opens where they
  /// were. Following only the value the sheet returns would miss a ×, which
  /// returns none: on «ذكر», 10 before and 30 after, × on the after row and
  /// then the one left set on time would open the next sheet on بعد with
  /// nothing chosen. A clock habit switched to a prayer would carry the same
  /// stale side in.
  ///
  /// On both sides the reminders cannot say which side is meant, so
  /// [chosen], the value the sheet just returned, picks the side the next
  /// sheet leans to. Prayer mode only, since a clock time's sheet always
  /// opens on «قبل». It never writes [_cueRelation]: a reminder's side is
  /// not the «قبل» in a typed cue's words.
  void _followReminderSide({int chosen = 0}) {
    if (_timingMode != _TimingMode.prayer) return;
    switch (_reminderStack.side) {
      case HabitReminderSide.before:
        _reminderLean = _CueRelation.before;
      case HabitReminderSide.after:
        _reminderLean = _CueRelation.after;
      case HabitReminderSide.both:
        if (chosen != 0) {
          _reminderLean = chosen > 0 ? _CueRelation.after : _CueRelation.before;
        }
      case HabitReminderSide.none:
        break;
    }
  }

  /// A row tapped: the sheet opens on that reminder, and whatever comes
  /// back takes its place. HabitReminderStack.replace keeps the roles
  /// straight. The one tier rule is which rows may move at all
  /// (HabitReminderStack.canEdit): an extra kept from a Premium that has
  /// ended opens the same gate the add row does, and its × still works.
  Future<void> _editReminder(int offset) async {
    if (!_reminderStack.canEdit(offset,
        isPremium: ref.read(premiumAccessProvider))) {
      showReminderLimitGate(context, ref, forHabit: true);
      return;
    }
    final s = S.of(context);
    final chosen = await showHabitOffsetSheet(
      context,
      current: offset,
      anchor: _sheetAnchor,
      presets: true,
      leanAfter: _sheetLeanAfter,
      editing: true,
      anchorName: _prayerName(s),
    );
    if (chosen == null || !mounted || chosen == offset) return;
    HapticFeedback.selectionClick();
    setState(() {
      final next =
          HabitReminderStack(primary: _reminderOffset, extras: _extraOffsets)
              .replace(offset, chosen);
      _reminderOffset = next.primary;
      _extraOffsets = next.extras;
      _followReminderSide(chosen: chosen);
    });
  }

  /// The add row tapped. The tier is checked BEFORE the sheet opens: a
  /// free account meets the gate at once rather than after choosing a
  /// value it cannot keep, and a premium habit at its cap hears why. What
  /// the sheet returns then goes through the same add rule a typed value
  /// always did, so a value already on the list is left as it is.
  Future<void> _addReminder() async {
    final s = S.of(context);
    final stack =
        HabitReminderStack(primary: _reminderOffset, extras: _extraOffsets);
    final isPremium = ref.read(premiumAccessProvider);
    final gate =
        canAddHabitReminder(current: stack.length, isPremium: isPremium);
    if (gate.locked) {
      showReminderLimitGate(context, ref, forHabit: true);
      return;
    }
    if (!gate.allowed) {
      HapticFeedback.lightImpact();
      _showOffsetNotice(s.habitReminderMaxReached);
      return;
    }
    final chosen = await showHabitOffsetSheet(
      context,
      current: null,
      anchor: _sheetAnchor,
      presets: true,
      leanAfter: _sheetLeanAfter,
      anchorName: _prayerName(s),
    );
    if (chosen == null || !mounted) return;
    _applyOffsetTap(
      stack.addTyped(chosen, isPremium: isPremium),
      chosen: chosen,
    );
  }

  /// Notification or alarm: the one choice about HOW a reminder arrives,
  /// under the section that decides WHEN. Two cells, notification first
  /// because it is the default and the only thing the app did before alarms
  /// existed, and a one-line hint that says what the other cell buys. Drawn
  /// wherever an alarm exists or an iOS update would bring it
  /// (alarmChoiceProvider); on an older iPhone the alarm cell is grey and
  /// says what it needs instead of switching. Where neither holds, such as
  /// the web, it is not drawn and the sheet looks exactly as it did.
  Widget _reminderStyleRow(S s) {
    final choice = ref.watch(alarmChoiceProvider).value ?? AlarmChoice.hidden;
    if (choice == AlarmChoice.hidden) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: ReminderStyleChoice(
        alarm: _alarm,
        accent: GameColors.gold,
        onChanged: _setAlarm,
        alarmChoice: choice,
      ),
    );
  }

  /// Alarm needs the system's permission the first time; a refusal keeps
  /// the choice on notification and says so where the person is looking,
  /// through the overlay rather than a SnackBar, which a sheet would hide.
  Future<void> _setAlarm(bool alarm) async {
    if (!alarm) {
      setState(() => _alarm = false);
      return;
    }
    final granted = await AlarmService.instance.requestPermission();
    if (!mounted) return;
    if (!granted) {
      showOverlayNotice(context, S.of(context).alarmPermissionDenied,
          icon: Icons.alarm_off_rounded);
      // Greys «منبّه» now rather than at the next return to the app.
      ref.invalidate(alarmChoiceProvider);
      return;
    }
    setState(() => _alarm = true);
  }

  /// Asks the OS for notification permission on the way out of [_submit],
  /// for any habit whose cue actually resolves to a scheduled time.
  ///
  /// Reuses the exact request-then-warn-on-false contract AddTaskSheet and
  /// TaskDetailSheet already follow, including the same
  /// [S.reminderPermissionDenied] copy, so all three reminder-setting
  /// surfaces behave identically. The ScaffoldMessenger is captured
  /// *before* the await because [_submit] pops this sheet immediately after
  /// calling this — by the time the prompt resolves, this widget's own
  /// context is gone, but the messenger above it is still very much alive.
  Future<void> _ensureNotificationPermission() async {
    final messenger = ScaffoldMessenger.of(context);
    final deniedMessage = S.of(context).reminderPermissionDenied;
    final granted = await NotificationService.instance.requestPermissions();
    if (granted) return;
    messenger.showOne(
      SnackBar(
        content: Text(deniedMessage),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// Fires the moment someone picks a prayer-linked cue with no location
  /// saved yet — asks for it right here via the real OS location prompt
  /// ([detectAndSaveLocation]) instead of just leaving the small "go set
  /// your location in Notification Settings" line under the lead-time
  /// picker as the only sign anything's needed, which someone could easily
  /// save the habit past without noticing, leaving that reminder silently
  /// never scheduled. A no-op if a location's already saved, or a request
  /// is already in flight.
  Future<void> _ensureLocationForPrayerCue() async {
    if (_detectingLocation) return;
    if (ref.read(notificationSettingsProvider).location != null) return;

    setState(() => _detectingLocation = true);
    final s = S.of(context);
    final outcome = await detectAndSaveLocation(
      ref,
      isAr: s.isAr,
      resolvingLabel: s.notifLocationResolving,
      genericLabel: s.notifLocationSetGeneric,
      isMounted: () => mounted,
    );
    if (!mounted) return;
    setState(() => _detectingLocation = false);
    if (outcome.isSuccess) return;

    // Denied, services off, or timed out — same "don't just dead-end"
    // fallback NotificationSettingsScreen's own location row uses: explain
    // why, then offer the manual city search immediately rather than
    // making them find their own way to Settings afterward.
    if (!mounted) return;
    ScaffoldMessenger.of(context).showOne(
      SnackBar(
        content: Text(s.notifLocationDetectFailed),
        duration: const Duration(seconds: 3),
      ),
    );
    final picked = await showCitySearchSheet(context);
    if (!mounted || picked == null) return;
    await ref
        .read(notificationSettingsProvider.notifier)
        .update((c) => c.copyWith(location: picked));
  }

  /// The resolved cue moment a reminder is offset *from* — a habit's own
  /// picked clock time as-is, or (for a prayer cue) today's calculated
  /// prayer moment, untouched. Nothing global is added on top of it
  /// anymore: [_reminderTimePreview] applies exactly one signed offset to
  /// this, the same single `.add(offset)` NotificationService
  /// .scheduleSmartReminders applies, which is what finally makes this
  /// preview and the real scheduled fire time agree to the minute (they
  /// used to differ by the old global prayer offset, which this preview
  /// never knew about). Returns null when there's nothing to compute yet:
  /// no time/prayer picked, or (prayer mode only) no location saved to
  /// calculate against.
  /// Every moment a reminder would be offset FROM — one per filled time in
  /// Time mode, one for a prayer, none for freeform text.
  List<DateTime> _reminderAnchorTimes(NotificationSettings settings) {
    if (_timingMode == _TimingMode.time) {
      final today = DateTime.now();
      return [
        for (final t in _filledTimes)
          DateTime(today.year, today.month, today.day, t.hour, t.minute),
      ];
    }
    final single = _reminderAnchorTime(settings);
    return single == null ? const [] : [single];
  }

  DateTime? _reminderAnchorTime(NotificationSettings settings) {
    if (_timingMode == _TimingMode.time) {
      final picked = _pickedTime;
      if (picked == null) return null;
      final today = DateTime.now();
      return DateTime(today.year, today.month, today.day, picked.hour, picked.minute);
    }
    if (_timingMode == _TimingMode.prayer) {
      final prayer = _selectedPrayer;
      return prayer == null ? null : _prayerToday(prayer, settings);
    }
    return null;
  }

  /// Today's time of [prayer] where the person is, or null with no place
  /// saved. Offline-only and today-only on purpose — see
  /// PrayerTimesService.calculateOfflineCorrected's doc comment for why a
  /// live-API round trip isn't worth it for an in-form preview that can
  /// recompute on every keystroke.
  DateTime? _prayerToday(String prayer, NotificationSettings settings) {
    final loc = settings.location;
    if (loc == null) return null;
    return PrayerTimesService.calculateOfflineCorrected(
      latitude: loc.lat,
      longitude: loc.lng,
      date: DateTime.now(),
      countryCode: settings.resolvedCountryCode,
    ).forKey(prayer);
  }

  /// Under the reminder rows in Prayer mode with no saved location: the
  /// rows cannot name a clock time yet, and this says why rather than
  /// leaving them bare. Briefly shows progress while
  /// _ensureLocationForPrayerCue is off asking for a real location.
  /// Nothing in any other state; the rows carry their own times.
  Widget _reminderLocationNotice(S s) {
    final gp = context.gp;
    final settings = ref.watch(notificationSettingsProvider);
    // A prayer with no place to work its time out from. Asked of the place
    // itself rather than of a resolved anchor: with a prayer per time the
    // first row can be empty while the others are set.
    if (_timingMode == _TimingMode.prayer && settings.location == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // _ensureLocationForPrayerCue (fired the moment a prayer pill
              // was tapped) is off asking for a real location right now —
              // this briefly replaces the "no location" line with visible
              // progress instead of leaving it looking unchanged while a
              // permission prompt/GPS fix is actually in flight.
              if (_detectingLocation) ...[
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.5, color: gp.textTert),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    s.notifLocationResolving,
                    style: TextStyle(fontSize: 11, color: gp.textTert, height: 1.3),
                  ),
                ),
              ] else ...[
                Icon(Icons.location_off_outlined, size: 13, color: gp.textTert),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    s.remindPreviewNeedsLocation,
                    style: TextStyle(fontSize: 11, color: gp.textTert, height: 1.3),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  String _offsetPresetLabel(S s, int minutes) => switch (minutes) {
        0 => s.leadAtTime,
        < 0 => s.offsetBeforeMinutes(minutes.abs()),
        _ => s.offsetAfterMinutes(minutes),
      };

  /// Every moment of the day this form would ring at, as minutes since
  /// midnight: each filled time with its own shift in a multi-time form,
  /// otherwise the one time (or today's prayer) with the main shift and
  /// every extra one. The scheduler judges quiet hours per ring, shift by
  /// shift, so a check that looked only at the main shift would miss «قبل
  /// الفجر بساعة» landing in the night beside an on-time reminder that
  /// does not.
  List<int> _reminderFireMinutes(NotificationSettings settings) {
    int wrap(int m) => (m % 1440 + 1440) % 1440;
    if (_isMultiPrayer) {
      return [
        for (final row in _multiPrayerEntries)
          if (_prayerToday(row.prayer, settings) case final at?)
            wrap(at.hour * 60 + at.minute + row.offset),
      ];
    }
    if (_timingMode == _TimingMode.time &&
        _isMultiTime &&
        _multiTimeEntries.length > 1) {
      return [
        for (final (time, shift) in _multiTimeEntries)
          wrap(time.hour * 60 + time.minute + shift),
      ];
    }
    final shifts = [_effectiveReminderOffset, ..._effectiveExtraOffsets];
    return [
      for (final anchor in _reminderAnchorTimes(settings))
        for (final shift in shifts)
          wrap(anchor.hour * 60 + anchor.minute + shift),
    ];
  }

  /// The moments quiet hours would silence, the per-habit «اسمح به على أي
  /// حال» aside: none when nothing is sent anyway (notifications or habit
  /// reminders off) or quiet hours are off, and none for a reminder the
  /// scheduler lets through them.
  List<int> _quietReminderMinutes(NotificationSettings settings) {
    if (!settings.masterEnabled || !settings.habitRemindersEnabled) {
      return const [];
    }
    if (!settings.quietHoursEnabled) return const [];
    // An alarm is the person asking to be woken, and the scheduler lets it
    // through quiet hours (see NotificationService's exemption), so telling
    // them it will be silenced would be untrue.
    if (_alarm) return const [];
    if (_timingMode == _TimingMode.prayer &&
        !settings.quietHoursAppliesToPrayer) {
      return const [];
    }
    // Every time this habit carries, not just the first. The scheduler now
    // judges quiet hours per occurrence (a habit set for 00:00 and 12:00 keeps
    // its noon ping and loses only midnight), so a warning that looked at one
    // time would go quiet on exactly the schedule that needs it: the midnight
    // half of Aziz's protein case sits second in the list.
    return [
      for (final m in _reminderFireMinutes(settings))
        if (NotificationService.isMinuteWithinQuietHours(
          m,
          settings.quietHoursStart,
          settings.quietHoursEnd,
        ))
          m,
    ];
  }

  /// What saving now would actually leave silent: [_quietReminderMinutes],
  /// or nothing for a habit let through quiet hours.
  List<int> _silencedReminderMinutes(NotificationSettings settings) =>
      _ignoreQuietHours ? const [] : _quietReminderMinutes(settings);

  /// The save-time question for a reminder that would ring inside quiet
  /// hours and so never arrive (showQuietHoursConflict). Only while quiet
  /// hours are on, and only about a moment this sheet has not already been
  /// through: a new habit, or an edit that moved a time into the window. An
  /// edit that leaves the reminder as it was, or a tap on the line under the
  /// time, is not asked again.
  ///
  /// True to go on saving: nothing to ask, or an answer given. False when
  /// the card was closed without one, and the form stays as it is.
  Future<bool> _askAboutQuietHours() async {
    if (_quietHoursAnswered) return true;
    final settings = ref.read(notificationSettingsProvider);
    final silenced = _silencedReminderMinutes(settings);
    if (silenced.every(_quietAtOpen.contains)) return true;
    final isAr = S.of(context).isAr;
    String clock(List<TimeOfDay> times) =>
        HabitCue.times(times).labelForLocale(isAr);
    final answer = await showQuietHoursConflict(
      context,
      times: clock([
        for (final m in silenced) TimeOfDay(hour: m ~/ 60, minute: m % 60),
      ]),
      start: clock([settings.quietHoursStart]),
      end: clock([settings.quietHoursEnd]),
    );
    if (!mounted || answer == null) return false;
    switch (answer) {
      case QuietHoursConflictAnswer.turnOff:
        // The switch flips at once (the notifier sets its state before it
        // writes), so the save below is not held up by the write.
        ref
            .read(notificationSettingsProvider.notifier)
            .update((c) => c.copyWith(quietHoursEnabled: false))
            .ignore();
      case QuietHoursConflictAnswer.allowThis:
        setState(() => _ignoreQuietHours = true);
      case QuietHoursConflictAnswer.keep:
        break;
    }
    return mounted;
  }

  /// Shown only when the reminder this form would actually schedule lands
  /// inside the user's quiet-hours window and nothing else already exempts
  /// it. Previously that reminder was cancelled outright by
  /// NotificationService with no warning anywhere — someone deliberately
  /// setting a 6am reminder just never heard from it again. This says so up
  /// front and offers the one-tap override ([_ignoreQuietHours]) right
  /// where the decision is being made.
  ///
  /// Prayer-linked cues are deliberately silent here: they're already
  /// exempt by default (see NotificationSettings.quietHoursAppliesToPrayer)
  /// precisely because Fajr routinely falls inside a normal night window,
  /// so warning about it would be noise on the app's most common case.
  Widget _quietHoursWarning(S s) {
    final settings = ref.watch(notificationSettingsProvider);
    if (_quietReminderMinutes(settings).isEmpty) {
      return const SizedBox.shrink();
    }

    final gp = context.gp;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: GameColors.error.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: GameColors.error.withOpacity(0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.bedtime_outlined, size: 14, color: context.gp.errorInk),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _ignoreQuietHours
                        ? s.quietHoursOverrideOn
                        : s.quietHoursConflictWarning,
                    style: TextStyle(
                        fontSize: 11, color: gp.textSec, height: 1.35),
                  ),
                  const SizedBox(height: 6),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() {
                        _ignoreQuietHours = !_ignoreQuietHours;
                        _quietHoursAnswered = true;
                      });
                    },
                    child: Text(
                      _ignoreQuietHours
                          ? s.quietHoursRespectAction
                          : s.quietHoursAllowAnywayAction,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: context.gp.goldInk,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// How often, in words, or null while nobody has picked it: printing
  /// «كل يوم» for a choice nobody made would be the form making the claim
  /// the unlit row exists to stop.
  String? _oftenSummary(S s) {
    if (_freqType == null) return null;
    if (_selectedWeekdays.isNotEmpty) {
      final sep = s.isAr ? '، ' : ', ';
      return [
        for (final (weekday, name) in _weekdays(context))
          if (_selectedWeekdays.contains(weekday)) name,
      ].join(sep);
    }
    if (_freqType == HabitFrequencyType.weekly) {
      return s.timesAWeekPhrase(_weeklyTargetInRange);
    }
    // A counted daily habit says how many: «كل يوم» alone would be the one
    // thing this line then got wrong. The whole phrase, since Arabic says
    // «مرتين في اليوم» for two.
    return _dailyTargetInRange > 1 && _goalType == GoalType.build
        ? '${s.oftenEveryDay} · ${s.timesPerDayPhrase(_dailyTargetInRange)}'
        : s.oftenEveryDay;
  }

  /// The accent the habit's own icon is drawn in: its picked colour, or the
  /// build or quit default.
  Color get _accent => _iconColorHex != null
      ? (_iconColor ?? context.gp.textTert)
      : (_goalType == GoalType.build ? GameColors.gold : GameColors.iconXp);

  /// The habit's category icon in a small tinted square.
  Widget _categoryBadge() {
    final color = _accent;
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: color.withOpacity(0.16),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Center(
        // Ink for the glyph only, so it reads on the 16% wash.
        child: CategoryIcon(
          category: _category,
          ownIcon: _ownCategory?.icon,
          size: 16,
          color: context.gp.ink(color),
        ),
      ),
    );
  }

  /// The strip at the top of steps 2 and 3: what has been picked so far,
  /// the name first, then how often and the reminder once answered. On
  /// step 2 it ends in the points the habit pays, so the reward is visible
  /// before anything is committed.
  Widget _summaryStrip(S s, {required bool withXp}) {
    final gp = context.gp;
    final cue = _currentCue();
    final parts = [
      if (_oftenSummary(s) case final often?) often,
      if (!cue.isEmpty) cue.labelForLocale(s.isAr),
    ];
    final color = _accent;
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(8, 8, 10, 8),
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: gp.border, width: 0.5),
      ),
      child: Row(
        children: [
          _categoryBadge(),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: _nameCtrl.text.trim(),
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: gp.textPrimary,
                    ),
                  ),
                  if (parts.isNotEmpty)
                    TextSpan(
                      text: ' · ${parts.join(' · ')}',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: gp.textSec,
                      ),
                    ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (withXp) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color.withOpacity(0.18),
                borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
              ),
              // Left to right whatever the page's direction: in Arabic the
              // plain string drew as «XP 20+».
              child: Text(
                '+$_categoryXp XP',
                textDirection: TextDirection.ltr,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: gp.ink(color),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// The steps link, said back in one line once it is on.
  Widget _stepLinkRecap(S s) => Padding(
        padding: const EdgeInsetsDirectional.only(start: 4),
        child: Row(
          children: [
            Icon(Icons.directions_walk_rounded,
                size: 15, color: GameColors.success),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                s.stepLinkRecap(_stepGoal),
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: GameColors.success,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      );

  /// The chosen icon colour, or null when the stored hex is unusable.
  ///
  /// int.parse THROWS on a malformed value, which red-screened the whole
  /// edit sheet for a habit whose stored hex had been written by an older
  /// build or hand-edited. The model layer already guards the identical
  /// parse (MatrixState.colorFor) and falls back rather than crashing; this
  /// does the same, because a wrong swatch is a far better outcome than an
  /// uneditable habit.
  Color? get _iconColor {
    final hex = _iconColorHex;
    if (hex == null) return null;
    final parsed = int.tryParse(hex, radix: 16);
    return parsed == null ? null : Color(0xFF000000 | parsed);
  }

  bool _startsWithBefore(String value) {
    final trimmed = value.trim().toLowerCase();
    return trimmed.startsWith('before ') || value.trim().startsWith('قبل ');
  }

  String _baseCue(String value) {
    final trimmed = value.trim();
    final lower = trimmed.toLowerCase();
    if (lower.startsWith('before ')) return trimmed.substring(7).trim();
    if (lower.startsWith('after ')) return trimmed.substring(6).trim();
    if (trimmed.startsWith('قبل ')) return trimmed.substring(4).trim();
    if (trimmed.startsWith('بعد ')) return trimmed.substring(4).trim();
    return trimmed;
  }

  String _cueWithRelation(String base) {
    final trimmed = _baseCue(base);
    if (trimmed.isEmpty || _cueRelation == _CueRelation.after) return trimmed;
    return S.of(context).isAr ? 'قبل $trimmed' : 'Before $trimmed';
  }

  List<(int, String)> _weekdays(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    final monday = DateTime(2024, 1, 1);
    return List.generate(7, (i) {
      final day = monday.add(Duration(days: i));
      return (day.weekday, DateFormat.E(locale).format(day));
    });
  }

  Future<void> _pickTime([int slot = 0]) async {
    HapticFeedback.selectionClick();
    final current = slot < _pickedTimes.length ? _pickedTimes[slot] : null;
    final picked = await showTimePicker(
      context: context,
      initialTime: current ?? TimeOfDay.now(),
      helpText: S.of(context).pickATime,
      // Force 12-hour AM/PM regardless of the device's 24-hour system
      // setting, so the picker looks the same on every phone.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      while (_pickedTimes.length <= slot) {
        _pickedTimes.add(null);
      }
      while (_pickedOffsets.length <= slot) {
        _pickedOffsets.add(0);
      }
      _pickedTimes[slot] = picked;
    });
  }

  /// Scrolls the steps card fully into view the frame it first appears.
  ///
  /// Measured on an iPhone 17 Pro before this existed: with the Arabic
  /// keyboard open, the sheet has about 210pt of usable height under the
  /// name field, and the card used to render after the whole 3x3 category
  /// grid. Somebody typing "walking" saw the name field, one row of
  /// category chips, and the Continue button. The card was on screen in
  /// the widget tree and off screen in every way that matters, which is
  /// exactly the report this was built from.
  ///
  /// [alignment] 1.0 puts the card's BOTTOM edge at the bottom of the
  /// viewport rather than its top, so the switch and the goal chips under
  /// it come with it. This deliberately does not drop the keyboard: the person is mid-word in the name field, and
  /// closing it under them to show a card they did not ask for would be
  /// its own kind of rude.
  void _revealStepCard() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = _stepCardKey.currentContext;
      if (target == null) return;
      Scrollable.ensureVisible(
        target,
        alignment: 1.0,
        duration: GameMotion.slow,
        curve: Curves.easeOutCubic,
      );
    });
  }

  /// A starting category from what's typed so far (guessHabitCategory),
  /// the user's own pick once a chip was tapped (see [_didPickCategory],
  /// which also stops this being consulted at all), or Custom.
  HabitCategory _inferCategory(String text) =>
      guessHabitCategory(text) ??
      (_didPickCategory ? _category : HabitCategory.custom);

  HabitCategory _canonicalCategory(HabitCategory cat) => switch (cat) {
        HabitCategory.quran || HabitCategory.athkar || HabitCategory.fasting || HabitCategory.sadaqah => HabitCategory.faith,
        HabitCategory.fitness => HabitCategory.health,
        _ => cat,
      };
}
