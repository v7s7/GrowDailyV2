import 'dart:async';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

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
import '../catalog/goal_suggestions.dart';
import '../catalog/habit_plans.dart' show activeCatalogProvider;
import '../catalog/islamic_habit_catalog.dart';
import '../notifiers/catalog_overrides_notifier.dart';
import '../models/habit_cue.dart';
import '../models/habit_reminder_stack.dart';
import '../models/habit_model.dart';
import '../../dashboard/notifiers/dashboard_notifier.dart';
import '../../premium/notifiers/premium_notifier.dart';
import '../../rooms/notifiers/rooms_notifier.dart';
import '../notifiers/custom_habits_notifier.dart';
import '../notifiers/newly_added_habit_provider.dart';
import '../../../shared/widgets/choice_chip_grid.dart';
import 'habit_color_picker.dart';
import 'habit_offset_sheet.dart';
import '../../matrix/widgets/custom_offset_sheet.dart' show formatOffsetVerbose;
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

  /// Fires with the form's step index whenever it changes (0 = What, 1 = When).
  ///
  /// [AddHabitHub] listens so it can hide the Plans / Add Goal switcher once
  /// the user has committed to Add Goal and moved on — past that point the
  /// choice is already made and the pills are just noise above the form.
  final ValueChanged<int>? onStepChanged;

  /// Fires when the first habit's "or pick a ready-made plan" link is
  /// tapped (see [_AddHabitSheetState._isFirstHabit]). [AddHabitHub] passes
  /// this so the link can switch the hub to its Plans tab; standalone there
  /// is no Plans tab, and the link is not drawn.
  final VoidCallback? onBrowsePlans;

  const AddHabitSheet({
    super.key,
    this.existing,
    this.embedded = false,
    this.onStepChanged,
    this.onBrowsePlans,
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
  final _customUnitCtrl = TextEditingController();
  final _focus = FocusNode();
  final _cueFocus = FocusNode();
  GoalType _goalType = GoalType.build;
  HabitCategory _category = HabitCategory.custom;

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
  _CueRelation _cueRelation = _CueRelation.after;
  ReductionType _reductionType = ReductionType.avoid;
  LimitUnit _limitUnit = LimitUnit.minutes;
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

  // ── Two-step flow: 0 = What (name/category), 1 = When (timing) ──────────
  int _step = 0;

  /// Every step change goes through here so [AddHabitSheet.onStepChanged]
  /// stays in sync — there are three places that move between steps.
  void _goToStep(int step, {required bool forward}) {
    if (_step == step) return;
    setState(() {
      _forward = forward;
      _step = step;
    });
    widget.onStepChanged?.call(step);
  }
  // Direction of the last step change, so the transition slides the right
  // way (forward = new content enters from the trailing edge, back = from
  // the leading edge) instead of always sliding one direction.
  bool _forward = true;

  // ── Timing (Step 2) ───────────────────────────────────────────────────

  /// Whether this habit is being given a moment at all — the switch above
  /// the time/prayer/text picker (see [_timingToggleRow]).
  ///
  /// Off for every new habit, and off is a real answer rather than an
  /// unanswered one: plenty of habits have no single checkable minute, and
  /// that shape used to be reachable only by leaving a pre-selected picker
  /// alone and believing the small print that said you could. Cadence is
  /// one question, having a moment is another, and they are asked
  /// separately now.
  bool _timingEnabled = false;

  /// Which kind of moment, once the switch is on. Null means the switch is
  /// on and nothing has been picked yet — deliberately the opening state,
  /// so the mode a habit ends up with is always one somebody chose rather
  /// than one the category guessed on their behalf.
  _TimingMode? _timingMode;
  String? _selectedPrayer;
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

  /// Notification or alarm, see IslamicHabitTemplate.alarm. Off until the
  /// person picks alarm AND the platform grants it; see [_setAlarm].
  bool _alarm = false;

  // ── Reminder offset — signed minutes from the resolved time/prayer
  // moment to when the notification actually fires: negative = before,
  // 0 = on time, positive = after. Only meaningful for Time/Prayer modes
  // (Custom Text has no resolved moment to offset from) — see
  // _reminderOffsetSection.
  //
  // Ordered earliest → latest so the row reads like a timeline, with "On
  // time" (0) sitting naturally in the middle as the default.
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
  // Locates the smart-suggestions section so _revealSuggestions() can
  // scroll it into view — see that method.
  final GlobalKey _suggestionsKey = GlobalKey();

  /// The Repeat chips, so a refused Create can scroll back to them.
  final GlobalKey _repeatSectionKey = GlobalKey();

  /// The timing section, so turning the switch on can scroll it into view.
  /// It opens directly above the preview card and the footer, which on a
  /// small phone is exactly where "below the fold" starts.
  final GlobalKey _timingSectionKey = GlobalKey();

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
      } else if (!parsed.isEmpty) {
        _timingMode = _TimingMode.text;
        _cueCtrl.text = storedCue;
      }
      // A habit that already carries a cue opens with the section open and
      // that cue showing; one saved without a moment opens closed, which is
      // exactly the state it was saved in. Editing is the only way the
      // switch is ever on to begin with.
      _timingEnabled = _timingMode != null;
      final storedOffset = existing.reminderOffsetMinutes;
      _reminderOffset = storedOffset;
      _extraOffsets = {...existing.extraReminderOffsets}..remove(storedOffset);
      _ignoreQuietHours = existing.ignoreQuietHours;
      _alarm = existing.alarm;
      _category = _canonicalCategory(existing.category);
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
      _timesPerDay = existing.frequencyType == HabitFrequencyType.daily
          ? (existing.frequencyTarget > storedTimes.length
                  ? existing.frequencyTarget
                  : storedTimes.length)
              .clamp(1, kMaxTimesPerDay)
          : 1;
      _selectedWeekdays = existing.scheduledWeekdays.toSet();
      _goalType = existing.goalType;
      _reductionType = existing.reductionType;
      _limitCtrl.text = existing.limitAmount?.toString() ?? '';
      _limitUnit = existing.limitUnit ?? LimitUnit.minutes;
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
    _cueCtrl.addListener(() {
      if (_hasName) setState(() {});
    });
    // Drives the live reminder-time preview (_reminderTimePreview) as a
    // custom lead-minutes value is typed — without this, only the preset
    // pills (_selectLeadPreset, which already calls setState) would ever
    // trigger a rebuild, and the preview would silently go stale the moment
    // "Custom" is picked.

    // Only the standalone "edit existing habit" sheet autofocuses the name
    // field on open. The embedded Add Goal tab (opened via the + button /
    // Add Habit Hub) is the very first screen of the creation flow — popping
    // the keyboard open before anything else on the sheet is even visible
    // was more disruptive than helpful, so it now waits for a deliberate tap
    // on the field instead.
    if (!widget.embedded) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
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
    final localized = existing.localName(S.of(context).isAr);
    if (_nameCtrl.text != localized) _nameCtrl.text = localized;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _cueCtrl.dispose();
    _stepGoalCtrl.dispose();
    _limitCtrl.dispose();
    _customUnitCtrl.dispose();
    _focus.dispose();
    _cueFocus.dispose();
    _offsetNoticeTimer?.cancel();
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
        _TimingMode.prayer => _selectedPrayer == null
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

  void _applyOffsetTap(
    ({HabitReminderStack stack, HabitOffsetTap outcome}) result,
  ) {
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
      Navigator.pop(context);
      showHabitLimitGate(context, ref);
      return;
    }
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
    final limitAmount = int.tryParse(_limitCtrl.text.trim());
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
                      _selectedWeekdays.toList()..sort(),
                      catalogDefault.scheduledWeekdays)
                  ? null
                  : (_selectedWeekdays.toList()..sort()),
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
        limitUnit: _isLimitHabit ? _limitUnit : null,
        customUnitLabel: _isLimitHabit
            ? _customUnitCtrl.text.trim()
            : null,
        iconColorHex: _iconColorHex,
        clearIconColor: _iconColorHex == null,
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
        limitUnit: _isLimitHabit ? _limitUnit : null,
        customUnitLabel: _isLimitHabit
            ? _customUnitCtrl.text.trim()
            : null,
        iconColorHex: _iconColorHex,
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

  /// Header + two-step form + footer nav, so [embedded] mode can drop
  /// straight into a host that already supplies the drag handle and outer
  /// card (see [AddHabitHub]). Step 1 (What) is name/category/goal-style —
  /// the minimum to know what's being created. Step 2 (When) is timing and
  /// frequency, with a live preview at the end. Editing always starts on
  /// Step 1 too, so the flow never branches into two different shapes.
  /// A set-a-limit quit habit needs its number: picking «ضع حدًا» and leaving
  /// the field blank used to save `reductionType: limit` with no amount, so
  /// every "within the limit" question had nothing to compare against.
  bool get _limitMissing =>
      _isLimitHabit && (int.tryParse(_limitCtrl.text.trim()) ?? 0) < 1;

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
  /// [_tryCreate] and [_limitErrorShown] / [_repeatErrorShown]. A form that
  /// points at a field before anybody has had a go at it is nagging, and a
  /// dead button with a note beside it says the same thing twice.
  bool get _canProceed => _hasName;

  /// Set the first time somebody presses the button with a limit habit whose
  /// number is missing, and the only thing that puts
  /// [S.limitAmountRequired] on screen. False again for a fresh sheet.
  bool _limitErrorShown = false;

  /// The cadence half of the same idea, for [S.repeatPickOne].
  bool _repeatErrorShown = false;

  /// Continue, with the step's own required answer checked at the moment of
  /// the press rather than in advance.
  ///
  /// Shared by the footer button and the name field's return key, so the
  /// keyboard cannot walk past a check the button enforces. Refusing here
  /// rather than in [_canProceed] is what keeps a limit habit from reaching
  /// step two with no number, which would be saved as no limit at all.
  void _tryContinue() {
    if (!_hasName) return;
    if (_limitMissing) {
      HapticFeedback.lightImpact();
      setState(() => _limitErrorShown = true);
      return;
    }
    HapticFeedback.selectionClick();
    FocusScope.of(context).unfocus();
    _goToStep(1, forward: true);
  }

  /// Create / Save changes, same contract as [_tryContinue].
  ///
  /// An unpicked cadence scrolls its own chips back into view before saying
  /// anything: the press happens at the bottom of the sheet and the chips
  /// can be above the fold by then, and an answer demanded from off screen
  /// is a dead end however politely it is worded.
  void _tryCreate() {
    if (!_hasName) return;
    if (_freqType == null) {
      HapticFeedback.lightImpact();
      setState(() => _repeatErrorShown = true);
      _revealRepeatSection();
      return;
    }
    _submit();
  }

  /// Scrolls the Repeat chips fully into view, the way
  /// [_revealTimingSection] does for the section below them.
  void _revealRepeatSection() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = _repeatSectionKey.currentContext;
      if (target == null) return;
      // Aligned to the top of the viewport (the default), not the bottom the
      // way _revealTimingSection does it: the chips are what has to be read
      // and answered now, so they go where the eye starts.
      Scrollable.ensureVisible(
        target,
        duration: GameMotion.slow,
        curve: Curves.easeOutCubic,
      );
    });
  }

  Widget _content(BuildContext context, S s) {
    final gp = context.gp;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Embedded, this form has no heading of its own. The host that
        // embeds it (AddHabitHub) already writes «إضافة عادة» directly
        // above, so «إضافة هدف» under it was the same word twice on two
        // lines, pushing the step's own question («متى وكيف ستتابع؟») a
        // heading further down for nothing.
        //
        // Standalone it is the only heading there is: three callers open
        // this sheet with no chrome of their own above it (the Grid's edit
        // sheet, the room habit picker, Create Room), so the condition is
        // about who is hosting the form, not about how many habits the
        // account has. It used to be the latter, which is why only a very
        // first habit escaped the duplicate.
        if (!widget.embedded)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
            child: Text(
              _isEditing ? s.editHabit : s.addGoalTitle,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: gp.textPrimary,
              ),
            ),
          ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
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
                key: ValueKey(_step),
                child: _step == 0 ? _stepWhat(s) : _stepWhen(s),
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            10,
            20,
            _isEditing ? 4 : 20 + MediaQuery.of(context).padding.bottom,
          ),
          child: Row(
            children: [
              if (_step == 1) ...[
                TextButton(
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    FocusScope.of(context).unfocus();
                    _goToStep(0, forward: false);
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
                  key: _step == 1 ? _createButtonKey : null,
                  onPressed: !_canProceed
                      ? null
                      : (_step == 0 ? _tryContinue : _tryCreate),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    _step == 0 ? s.continueAction : (_isEditing ? s.saveChanges : s.createGoal),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_isEditing)
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

  // ── Step 1: What ─────────────────────────────────────────────────────

  Widget _stepWhat(S s) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The kind of habit, as a two-way switch right above the box it
          // changes: the box's own question follows it («ما العادة التي
          // تريد بناءها؟» / «ما الذي تريد تقليله؟»). It was a quiet text link
          // under the whole form, and Aziz found nobody saw it there
          // (2026-09-08). With Build already selected it is a mode, not a
          // question: typing straight into the box works exactly as before.
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
          // The steps card lives inside the name section, directly under the
          // field that triggers it. See _nameAndCategorySection and
          // _revealStepCard for the measurement that moved it.
          _nameAndCategorySection(s)
              .animate(delay: 40.ms)
              .fadeIn(duration: 240.ms)
              .slideY(begin: 0.06, curve: Curves.easeOutCubic),
          if (_goalType == GoalType.quit && !_isPresetEdit) ...[
            const SizedBox(height: 16),
            _quitStyleSection(s)
                .animate(delay: 60.ms)
                .fadeIn(duration: 240.ms)
                .slideY(begin: 0.06, curve: Curves.easeOutCubic),
          ],
          const SizedBox(height: 8),
          _belowFormLinks(s)
              .animate(delay: 100.ms)
              .fadeIn(duration: 240.ms),
        ],
      );

  /// The one quiet link left under the form: the hub's Plans tab, while a
  /// first habit hides the hub's pills. The Build / Quit switch that used to
  /// be the first link here moved above the name box on 2026-09-08 (see
  /// [_goalTypeToggle]): as a link under everything, it went unseen.
  Widget _belowFormLinks(S s) {
    if (widget.onBrowsePlans == null) return const SizedBox.shrink();
    final gp = context.gp;
    // shrinkWrap, so the row is 36 tall on screen and in layout: the default
    // padded target makes it 48, and on a 730-point phone that alone pushed
    // it below the fold.
    final style = TextButton.styleFrom(
      foregroundColor: gp.textSec,
      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      minimumSize: const Size(0, 36),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 12),
    );
    return TextButton(
      style: style,
      onPressed: () {
        HapticFeedback.selectionClick();
        FocusScope.of(context).unfocus();
        widget.onBrowsePlans!();
      },
      child: Text(s.readyPlansLink),
    );
  }

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

  Widget _nameAndCategorySection(S s) => Column(
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
            onSubmitted: (_) => _tryContinue(),
            decoration: InputDecoration(
              hintText: _goalType == GoalType.build ? s.whatHabitBuild : s.whatReduce,
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
          // Right under the field whose text summoned it, above the
          // category grid, because the question it asks is about the name
          // that was just typed. It is also the only place in this step
          // that is still on screen with the keyboard open.
          if (_stepCardVisible) ...[
            const SizedBox(height: 12),
            _stepLinkCard(s)
                .animate()
                .fadeIn(duration: 260.ms)
                .slideY(begin: 0.08, curve: Curves.easeOutCubic)
                .scaleXY(begin: 0.97, curve: Curves.easeOutBack),
          ],
          const SizedBox(height: 16),
          _SectionLabel(s.category),
          // While nothing is picked and nothing typed, say why the space
          // under the grid is empty: the suggestions wait for a category.
          if (!_didPickCategory && !_hasName) ...[
            const SizedBox(height: 4),
            Text(
              s.categoryPickHint,
              style: TextStyle(fontSize: 12, color: context.gp.textTert),
            ),
          ],
          const SizedBox(height: 8),
          // Fixed 3-column grid (9 categories = an exact 3×3) instead of a
          // content-hugging Wrap — the old version sized every chip to its
          // own label ("Faith" vs "Learning" vs "Custom"), so rows never
          // lined up and the count-per-row wandered between 2 and 4. Each
          // cell is now the same width, so the grid reads as a grid.
          _ChipGrid(
            columns: 3,
            items: _broadCategories.map((cat) {
              // No chip lit until the person picks one or the typed name
              // says which (Aziz, 2026-09-08: unchosen by default). Before
              // this «مخصص» sat highlighted as if it had been chosen.
              final selected =
                  (_didPickCategory || _hasName) && _category == cat;
              return _PlainChoiceChip(
                selected: selected,
                label: cat.localizedName(s.isAr),
                icon: CategoryIcon(
                  category: cat,
                  size: 15,
                  color: selected ? GameColors.gold : context.gp.textSec,
                ),
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _didPickCategory = true;
                    _category = cat;
                  });
                  // Picking a category before typing anything means the
                  // suggestions below are about to become the most useful
                  // thing on screen (re-filtered to this category) — but
                  // they can easily sit below the fold, especially with
                  // the name field's keyboard still open eating half the
                  // sheet. See _revealSuggestions().
                  if (!_hasName) _revealSuggestions();
                },
              );
            }).toList(),
          ),
          // Below the categories, and only once one has been picked: the
          // suggestions are filtered by category, so before a pick they were
          // six «مخصص» chips nobody had asked for. Typing a name puts them
          // away as before. On a first habit they are labelled as the
          // quickest way in rather than as a shortcut (see _isFirstHabit).
          if (!_hasName && _didPickCategory && _suggestions().isNotEmpty)
            _suggestionsSection(s, lead: _isFirstHabit),
        ],
      );

  /// True when this account has no habits at all yet.
  ///
  /// The page reads the same for everyone (name box, categories,
  /// suggestions, the links; see [_stepWhat]), so this only sets what a
  /// first habit does differently: the suggestions are labelled as the
  /// quickest way in rather than as a shortcut, the hub hides its Plans /
  /// Add Goal pills and its "choose one" card and hands the form a Plans
  /// link instead (AddHabitHub's `_pillsHidden`). Dropping the form's own
  /// heading used to be on this list too; it is not a first-habit trimming
  /// any more, it is what every embedded host gets (see [_content]).
  ///
  /// A first habit used to open on a grid of suggestions and an "or write
  /// your own" label before the box, all under the hub's pills and their
  /// "choose one" card: three things to answer before the one thing to do,
  /// on a phone screen the keyboard then halves (reported from Android,
  /// 2026-09-08). That lead block is gone for good; the Build / Quit switch
  /// above the box stayed, as a mode rather than a question (Build is
  /// already selected, so typing straight into the box works). The order is
  /// the same for every habit now and only the trimmings above differ.
  bool get _isFirstHabit => ref.read(habitListProvider).isEmpty;

  Widget _suggestionsSection(S s, {bool lead = false}) => Column(
        key: _suggestionsKey,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          _SectionLabel(lead ? s.quickestStart : s.smartSuggestions),
          const SizedBox(height: 8),
          // 2 columns, not 3 — these labels are full phrases ("Fast
          // Monday/Thursday", "Less phone before Quran"), so 3 equal
          // columns would force ellipsis far more often than 2 does.
          _ChipGrid(
            columns: 2,
            items: _suggestions().map((item) {
              return _PlainActionChip(
                label: item.name(s.isAr),
                xp: GameConstants.categoryXpRewards[item.category.name] ?? 10,
                onTap: () => _applySuggestion(item),
              );
            }).toList(),
          ),
          const SizedBox(height: 4),
        ],
      );

  Widget _quitStyleSection(S s) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionLabel(s.goalStyle),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _SmallPick(
                  label: s.avoidCompletely,
                  selected: _reductionType == ReductionType.avoid,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _reductionType = ReductionType.avoid);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SmallPick(
                  label: s.setLimit,
                  selected: _reductionType == ReductionType.limit,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _reductionType = ReductionType.limit);
                  },
                ),
              ),
            ],
          ),
          if (_reductionType == ReductionType.limit) ...[
            const SizedBox(height: 12),
            // ── One line, and the same two columns as the picks above ─────
            //
            // The amount field carries a helperText for as long as the number
            // is missing, which is the state this row OPENS in — so it is
            // taller than the dropdown next to it nearly every time it is
            // seen. A Row centres its children by default, and that sank the
            // dropdown by half the helper's height (11.5pt, measured) against
            // a field whose box had not moved: two boxes, two different
            // lines. Aligning the tops puts the helper where it belongs,
            // under its own field, and leaves the boxes level.
            //
            // The gap is the picks' 8, not 10, so the seam between the two
            // columns runs straight down both rows.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    selectionWidthStyle: GameTextStyles.selectionWidthStyle,
                    controller: _limitCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: s.maxAmount,
                      // A limit habit without a number has nothing to be
                      // within; the form waits for one (see _canProceed).
                      helperText:
                          // Only after somebody has actually tried to move
                          // on with it empty. It used to be on screen from
                          // the moment the row opened, telling people off
                          // for not having typed yet.
                          _limitMissing && _limitErrorShown
                              ? s.limitAmountRequired
                              : null,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<LimitUnit>(
                    value: _limitUnit,
                    items: LimitUnit.values
                        .map((u) => DropdownMenuItem(value: u, child: Text(s.limitUnitLabel(u.name))))
                        .toList(),
                    onChanged: (v) => setState(() => _limitUnit = v ?? LimitUnit.minutes),
                  ),
                ),
              ],
            ),
            // Only LimitUnit.custom needs this — every other unit already
            // has a stock translated label (cups/minutes/times/money), so
            // asking again here would just be noise for those.
            if (_limitUnit == LimitUnit.custom) ...[
              const SizedBox(height: 10),
              TextField(
                selectionWidthStyle: GameTextStyles.selectionWidthStyle,
                controller: _customUnitCtrl,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: s.customUnitPrompt,
                  hintText: s.customUnitHint,
                ),
              ),
            ],
          ],
        ],
      );

  // ── Step 2: When ─────────────────────────────────────────────────────

  Widget _stepWhen(S s) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _goalType == GoalType.quit ? s.timingQuitTitle : s.timingBuildTitle,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: context.gp.textPrimary,
            ),
          ).animate().fadeIn(duration: 240.ms).slideY(begin: 0.06, curve: Curves.easeOutCubic),
          const SizedBox(height: 10),
          // ── Cadence FIRST, then the times ────────────────────────────────
          //
          // These two were the other way round, and that ordering is the whole
          // reason a habit counted twice a day could only ever be given one
          // time: the form asked WHEN before it asked HOW MANY TIMES, so there
          // was nowhere to put the second time — the screen did not yet know
          // there was one. The count is what decides the shape of everything
          // under it, so it has to be answered first.
          //
          // It also keeps the stepper reachable. With the pickers above it,
          // every extra occurrence pushed the plus button it came from further
          // down the sheet, and past a few taps out of the viewport entirely.
          _frequencySection(s)
              .animate(delay: 40.ms)
              .fadeIn(duration: 240.ms)
              .slideY(begin: 0.06, curve: Curves.easeOutCubic),
          // ── One question at a time, downward ────────────────────────────
          //
          // Whether the habit has a MOMENT is a separate question from how
          // often it repeats, and it is not asked until the first one is
          // answered: no switch, no chips, nothing. Cadence is what shapes
          // everything below it (a daily habit counted three times a day can
          // hold three clock times; a weekly one cannot hold any of that),
          // so offering the timing question first was offering it before the
          // form knew what it could offer.
          //
          // The whole block only ever appears, never disappears: nothing
          // sets the cadence back to null once it is picked, and an edit
          // always arrives with one, so no answer given here can be stranded
          // behind a section that went away.
          //
          // One AnimatedSize covers both reveals, this one and the picker's
          // own inside it, because it animates to whatever its subtree
          // measures rather than to a particular child.
          AnimatedSize(
            duration: GameMotion.standard,
            curve: Curves.easeOutCubic,
            // Grows downward from the chips above rather than around its own
            // middle, so each section opens under the control that opened it.
            alignment: Alignment.topCenter,
            child: _freqType == null
                ? const SizedBox.shrink()
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 14),
                      _timingToggleRow(s)
                          .animate(delay: 70.ms)
                          .fadeIn(duration: 240.ms)
                          .slideY(begin: 0.06, curve: Curves.easeOutCubic),
                      if (_timingEnabled)
                        Padding(
                          key: _timingSectionKey,
                          padding: const EdgeInsets.only(top: 14),
                          // Behind the switch row's own 70ms, not before it:
                          // on a habit that opens with the section already on
                          // (an edit with a cue), an unanimated picker painted
                          // at full opacity while the heading, the chips and
                          // the switch that governs it were still fading in.
                          // On the frame it was 100 percent, that switch was
                          // at 0.
                          //
                          // It sits on the child rather than on the
                          // AnimatedSize so it also runs when somebody opens
                          // the section by hand later, instead of popping in.
                          child: _timingModeSection(s)
                              .animate(delay: 100.ms)
                              .fadeIn(duration: 240.ms)
                              .slideY(begin: 0.06, curve: Curves.easeOutCubic),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 16),
          _goalPreviewCard(s)
              .animate(delay: 130.ms)
              .fadeIn(duration: 240.ms)
              .slideY(begin: 0.08, curve: Curves.easeOutCubic),
        ],
      );

  Widget _timingModeSection(S s) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _SmallPick(
                  label: s.customTime,
                  selected: _timingMode == _TimingMode.time,
                  onTap: () => _selectTimingMode(_TimingMode.time),
                ),
              ),
              // ── Prayer and free text are single-moment cues ──────────────
              //
              // Hidden, not disabled, once the habit is counted more than once
              // a day. A prayer is ONE moment — "five times a day" anchored to
              // prayers means five DIFFERENT prayers, which is a different
              // feature and not what this chip does — and free text has no
              // resolvable moment at all, so neither can express a second
              // occurrence. Offering a chip that silently collapses the count
              // back to one time is worse than not offering it: the person
              // sets two times, taps «وقت الصلاة», and one of them is gone
              // with nothing said.
              //
              // Disabled-but-visible was the other option and reads as a
              // paywall. There is nothing to unlock here — the choice simply
              // does not apply while the count is above one, and it comes
              // straight back when the count returns to one.
              if (!_isMultiTime) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: _SmallPick(
                    label: s.cuePrayerOption,
                    selected: _timingMode == _TimingMode.prayer,
                    onTap: () => _selectTimingMode(_TimingMode.prayer),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SmallPick(
                    label: s.customText,
                    selected: _timingMode == _TimingMode.text,
                    onTap: () => _selectTimingMode(_TimingMode.text),
                  ),
                ),
              ],
            ],
          ),
          // Nothing under the chips until one of them is picked. The
          // gap goes with it, so an opened section with no answer yet is
          // three chips and nothing else — which is the question.
          if (_timingMode != null) const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: GameMotion.standard,
            child: KeyedSubtree(
              key: ValueKey(_timingMode),
              child: switch (_timingMode) {
                null => const SizedBox.shrink(),
                _TimingMode.time => _timeModeContent(s),
                _TimingMode.prayer => _prayerModeContent(s),
                _TimingMode.text => _textModeContent(s),
              },
            ),
          ),
        ],
      );

  /// The switch that opens the time/prayer/text picker.
  ///
  /// Shaped like Notification Settings' rows (icon, label, Switch) rather
  /// than like the steps-link card above it: this is a plain yes or no about
  /// the section under it, not an offer that has to explain itself first.
  /// The whole row is the target, not just the switch.
  ///
  /// It replaced a line of small print saying the picker below could be
  /// skipped. A sentence asking someone not to use a control is a control
  /// that should not have been open, and off is now the resting state, so
  /// the sentence has nothing left to say.
  ///
  /// Not drawn at all until a cadence is picked (see [_stepWhen]): what this
  /// switch opens depends on the answer above it, so it waits for it.
  Widget _timingToggleRow(S s) {
    final gp = context.gp;
    final on = _timingEnabled;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _setTimingEnabled(!on),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Icon(
              on ? Icons.alarm_on_rounded : Icons.alarm_rounded,
              size: 19,
              color: on ? gp.goldInk : gp.textTert,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                // A quit habit is watching for a moment, not scheduling one
                // (its own reminder is the evening check-in, which this
                // switch has never governed), so it names the thing its
                // field below already names: a time or a situation.
                _goalType == GoalType.quit
                    ? s.timingToggleQuit
                    : s.timingToggle,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: on ? gp.textPrimary : gp.textSec,
                ),
              ),
            ),
            Switch(value: on, onChanged: _setTimingEnabled),
          ],
        ),
      ),
    );
  }

  /// Opens or closes the timing section.
  ///
  /// Turning it OFF clears the mode rather than remembering it, and takes
  /// with it everything that only means anything beside a cue: the alarm
  /// choice and the quiet-hours override. Both are written on save, so
  /// leaving either behind would store an answer about a reminder this
  /// habit is no longer getting — the same class of bug the steps-link
  /// switch already documents in [_setGoalType].
  ///
  /// What it does NOT clear is the picked times and the typed cue text.
  /// Those are the person's own input, they are only ever saved through a
  /// selected mode, and a switch flicked off and back on should ask for the
  /// choice again, not for the typing again.
  void _setTimingEnabled(bool on) {
    HapticFeedback.selectionClick();
    if (_cueFocus.hasFocus) _cueFocus.unfocus();
    setState(() {
      _timingEnabled = on;
      if (!on) {
        _timingMode = null;
        _openOffsetRow = -1;
        _alarm = false;
        _ignoreQuietHours = false;
      }
      // Counted more than once a day, the clock time is the ONLY mode the
      // row can offer (prayer and free text are single moments, see
      // _timingModeSection), so opening the section would show one unlit
      // full-width chip above empty space, which reads as a section that
      // failed to draw rather than as a choice. Picking the only option on
      // somebody's behalf takes nothing away from them: there is nothing
      // else to pick.
      if (on && _isMultiTime) _timingMode = _TimingMode.time;
    });
    if (on) _revealTimingSection();
  }

  /// Scrolls the freshly opened timing section fully into view. Same
  /// treatment [_revealStepCard] gives the steps card, and for the same
  /// reason: the section opens near the bottom of the sheet, so on a small
  /// phone the chips somebody just asked for can land under the footer.
  void _revealTimingSection() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = _timingSectionKey.currentContext;
      if (target == null) return;
      Scrollable.ensureVisible(
        target,
        alignment: 1.0,
        duration: GameMotion.slow,
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _selectTimingMode(_TimingMode mode) {
    HapticFeedback.selectionClick();
    setState(() => _timingMode = mode);
  }

  Widget _timeModeContent(S s) {
    final count = _effectiveTimeCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _timeRow(s, i, count),
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
    return Container(
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
                    padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
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
                        Flexible(
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
                    padding: const EdgeInsets.fromLTRB(4, 14, 12, 14),
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
                )
              else
                Padding(
                  padding: const EdgeInsets.only(left: 14, right: 14),
                  child: Icon(Icons.chevron_right_rounded,
                      size: 18, color: gp.textTert),
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

  Widget _prayerModeContent(S s) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _relationToggle(s),
          const SizedBox(height: 12),
          _SectionLabel(s.pickAPrayer),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final key in _prayerKeys) ...[
                if (key != _prayerKeys.first) const SizedBox(width: 6),
                Expanded(
                  child: _EqualPill(
                    selected: _selectedPrayer == key,
                    label: HabitCue.preset(key).labelFor(context),
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

  /// "Remind me [30 before · 15 before · On time · 15 after · 30 after ·
  /// Custom]" — sits under Time/Prayer mode once a concrete anchor is
  /// picked (see the two call sites above). Custom Text mode never shows
  /// this: a freeform cue has no resolved clock/prayer moment for an offset
  /// to mean anything against.
  ///
  /// A 3-column [_ChipGrid] in timeline order (earliest → latest), so all
  /// six choices are visible at once on any screen width — no horizontal
  /// scrolling to discover that "after" even exists, and no gesture fight
  /// with the vertically-scrolling sheet this sits inside. _ChipGrid's
  /// LayoutBuilder divides whatever width is available, so this lays out
  /// identically on a small phone and a tablet; it's the same grid the
  /// category/frequency pickers above already use, so it needs no new
  /// visual language.
  ///
  /// Picking "after Fajr" costs exactly as many taps as "before Fajr", and
  /// neither is behind a mode switch. Custom (a plain minutes field plus a
  /// two-chip direction choice, each on its own full-width row so nothing
  /// can overflow on a narrow device) is the escape hatch, mirroring the
  /// LimitUnit.custom pattern elsewhere in this file.
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
    final gate = canAddHabitReminder(
      current: offsets.length,
      isPremium: ref.watch(premiumAccessProvider),
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
          ),
          const SizedBox(height: 6),
        ],
        _addReminderRow(s, locked: gate.locked, full: !gate.allowed),
        _reminderLocationNotice(s),
        if (_offsetNotice != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 13, color: context.gp.textTert),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _offsetNotice!,
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
          ),
        if (_goalType == GoalType.build) _reminderStyleRow(s),
        _quietHoursWarning(s),
      ],
    );
  }

  /// A reminder the habit carries: its shift in words («قبل ١٥ دقيقة»),
  /// and where that lands today once the anchor resolves. Same box as a
  /// time row so the two lists read as one family. The close mark only
  /// shows once there is a second row to fall back on; the last reminder
  /// is edited, never removed, which is the rule HabitReminderStack keeps.
  Widget _reminderRow(
    S s,
    int offset, {
    required DateTime? anchor,
    required bool removable,
  }) {
    final gp = context.gp;
    final time = anchor == null
        ? null
        : DateFormat('h:mm a', s.isAr ? 'ar' : 'en')
            .format(anchor.add(Duration(minutes: offset)));
    return Container(
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: gp.border, width: 0.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _editReminder(offset),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 13, 6, 13),
                child: Row(
                  children: [
                    Icon(Icons.notifications_active_rounded,
                        size: 18, color: context.gp.goldInk),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        _offsetRowLabel(s, offset),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: gp.textPrimary,
                        ),
                      ),
                    ),
                    if (time != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        time,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: gp.textTert,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (removable)
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _toggleReminderOffset(offset),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 14, 12, 14),
                child:
                    Icon(Icons.close_rounded, size: 18, color: gp.textTert),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(left: 10, right: 12),
              child: Icon(Icons.chevron_right_rounded,
                  size: 18, color: gp.textTert),
            ),
        ],
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

  String _offsetRowLabel(S s, int offset) =>
      offset == 0 ? s.leadAtTime : formatOffsetVerbose(offset, s.isAr, s);

  /// What the offset sheet shifts from, as a clock time: the picked time,
  /// or today's prayer once a location is known. Null leaves the sheet
  /// without its "relative to" line and resolved preview.
  TimeOfDay? get _sheetAnchor {
    final anchor = _reminderAnchorTime(ref.read(notificationSettingsProvider));
    return anchor == null
        ? null
        : TimeOfDay(hour: anchor.hour, minute: anchor.minute);
  }

  /// A row tapped: the sheet opens on that reminder, and whatever comes
  /// back takes its place. The count never changes here, so no tier rule
  /// is asked; HabitReminderStack.replace keeps the roles straight.
  Future<void> _editReminder(int offset) async {
    final chosen = await showHabitOffsetSheet(
      context,
      current: offset,
      anchor: _sheetAnchor,
      presets: true,
    );
    if (chosen == null || !mounted || chosen == offset) return;
    HapticFeedback.selectionClick();
    setState(() {
      final next =
          HabitReminderStack(primary: _reminderOffset, extras: _extraOffsets)
              .replace(offset, chosen);
      _reminderOffset = next.primary;
      _extraOffsets = next.extras;
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
    );
    if (chosen == null || !mounted) return;
    _applyOffsetTap(stack.addTyped(chosen, isPremium: isPremium));
  }

  /// Notification or alarm: the one choice about HOW a reminder arrives,
  /// under the section that decides WHEN. Two cells, notification first
  /// because it is the default and the only thing the app did before alarms
  /// existed, and a one-line hint that says what the other cell buys. Drawn
  /// only where an alarm can exist at all (alarmChoiceAvailableProvider);
  /// everywhere else the sheet looks exactly as it did.
  Widget _reminderStyleRow(S s) {
    if (ref.watch(alarmChoiceAvailableProvider).value != true) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: ReminderStyleChoice(
        alarm: _alarm,
        accent: GameColors.gold,
        onChanged: _setAlarm,
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
      final loc = settings.location;
      if (prayer == null || loc == null) return null;
      // Offline-only and today-only on purpose — see
      // PrayerTimesService.calculateOfflineCorrected's doc comment for why
      // a live-API round trip isn't worth it for an in-form preview that
      // can recompute on every keystroke.
      final today = PrayerTimesService.calculateOfflineCorrected(
        latitude: loc.lat,
        longitude: loc.lng,
        date: DateTime.now(),
        madhab: settings.madhab,
        countryCode: settings.resolvedCountryCode,
      );
      return today.forKey(prayer);
    }
    return null;
  }

  /// Under the reminder rows in Prayer mode with no saved location: the
  /// rows cannot name a clock time yet, and this says why rather than
  /// leaving them bare. Briefly shows progress while
  /// _ensureLocationForPrayerCue is off asking for a real location.
  /// Nothing in any other state; the rows carry their own times.
  Widget _reminderLocationNotice(S s) {
    final gp = context.gp;
    final settings = ref.watch(notificationSettingsProvider);
    final anchor = _reminderAnchorTime(settings);
    if (anchor == null) {
      if (_timingMode != _TimingMode.prayer) return const SizedBox.shrink();
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
    if (!settings.masterEnabled || !settings.habitRemindersEnabled) {
      return const SizedBox.shrink();
    }
    if (!settings.quietHoursEnabled) return const SizedBox.shrink();
    if (_timingMode == _TimingMode.prayer &&
        !settings.quietHoursAppliesToPrayer) {
      return const SizedBox.shrink();
    }
    // Every time this habit carries, not just the first. The scheduler now
    // judges quiet hours per occurrence (a habit set for 00:00 and 12:00 keeps
    // its noon ping and loses only midnight), so a warning that looked at one
    // time would go quiet on exactly the schedule that needs it: the midnight
    // half of Aziz's protein case sits second in the list.
    final moments = _reminderAnchorTimes(settings)
        .map((a) => a.add(Duration(minutes: _effectiveReminderOffset)))
        .where((m) => NotificationService.isMinuteWithinQuietHours(
              m.hour * 60 + m.minute,
              settings.quietHoursStart,
              settings.quietHoursEnd,
            ))
        .toList();
    if (moments.isEmpty) return const SizedBox.shrink();

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
                      setState(() => _ignoreQuietHours = !_ignoreQuietHours);
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

  Widget _textModeContent(S s) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _relationToggle(s),
          const SizedBox(height: 10),
          TextField(
            selectionWidthStyle: GameTextStyles.selectionWidthStyle,
            controller: _cueCtrl,
            focusNode: _cueFocus,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: _goalType == GoalType.build ? s.afterWhatRoutine : s.customTriggerOptional,
              hintText: s.routineHint,
              prefixIcon: const Icon(Icons.notes_rounded, size: 18),
            ),
          ),
        ],
      );

  Widget _relationToggle(S s) => Row(
        children: [
          Expanded(
            child: _SmallPick(
              label: s.cueAfterOption,
              selected: _cueRelation == _CueRelation.after,
              onTap: () => _setCueRelation(_CueRelation.after),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _SmallPick(
              label: s.cueBeforeOption,
              selected: _cueRelation == _CueRelation.before,
              onTap: () => _setCueRelation(_CueRelation.before),
            ),
          ),
        ],
      );

  Widget _frequencySection(S s) => Column(
        key: _repeatSectionKey,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionLabel(s.repeat),
          // Only once Create has been pressed with nothing picked, and then
          // where the answer is owed rather than beside the button that
          // refused. Not before: three chips under a label that says
          // «التكرار» are already the question, and a line telling somebody
          // to answer a question they have not reached yet is nagging.
          if (_freqType == null && _repeatErrorShown) ...[
            const SizedBox(height: 3),
            Text(
              s.repeatPickOne,
              style: TextStyle(fontSize: 11, color: context.gp.textTert),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _SmallPick(
                  label: s.daily,
                  selected: _freqType == HabitFrequencyType.daily,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _freqType = HabitFrequencyType.daily;
                      // Not a flat 1 any more: for a daily habit this field
                      // IS the per-day count (effectiveDailyTarget), and the
                      // stepper below owns it. Coming from Weekly, whose
                      // target means times per WEEK, that number is
                      // meaningless here — so only a count this mode itself
                      // could have produced survives the switch.
                      _freqTarget = _dailyTargetInRange;
                      _selectedWeekdays.clear();
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SmallPick(
                  label: s.weekly,
                  selected: _freqType == HabitFrequencyType.weekly && _selectedWeekdays.isEmpty,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _freqType = HabitFrequencyType.weekly;
                      // Keeps an already-reasonable target (e.g. switching
                      // back from Specific Days) instead of always
                      // resetting to 1 — the dropdown below is what lets
                      // this go up to 6 for someone who wants "gym 4x a
                      // week" without picking which days.
                      _freqTarget = _weeklyTargetInRange;
                      _selectedWeekdays.clear();
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SmallPick(
                  label: s.specificDays,
                  selected: _selectedWeekdays.isNotEmpty,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _freqType = HabitFrequencyType.weekly;
                      if (_selectedWeekdays.isEmpty) {
                        _selectedWeekdays
                            .add(DateTime.now().effectiveDay.weekday);
                      }
                      _freqTarget = _selectedWeekdays.length;
                    });
                  },
                ),
              ),
            ],
          ),
          // Daily's own count — see _TimesPerDayRow. Always on screen while
          // Daily is selected (Option A), including at its resting 1, which
          // is how anyone finds out the setting exists at all.
          if (_freqType == HabitFrequencyType.daily &&
              _selectedWeekdays.isEmpty &&
              _goalType == GoalType.build) ...[
            const SizedBox(height: 12),
            _TimesPerDayRow(
              count: _dailyTargetInRange,
              onChanged: (v) => setState(() {
                _timesPerDay = v.clamp(1, kMaxTimesPerDay);
                // Mirrored immediately because _submit persists _freqTarget;
                // this mode is the one where the two genuinely are the
                // same number.
                _freqTarget = _timesPerDay;
                // Stepping up while a single-moment cue is selected has to
                // carry the mode with it, or the chips vanish and leave the
                // form sitting in a mode nothing on screen can reach or
                // change. Only ever onto the clock-time mode, and only ever
                // upward: stepping back down to 1 restores the chips and lets
                // the person pick a prayer again if that is what they wanted.
                // A section that was never opened has no mode to carry:
                // stepping the count up on a habit with no time at all
                // must not hand it one.
                if (_timesPerDay > 1 &&
                    _timingMode != null &&
                    _timingMode != _TimingMode.time) {
                  _timingMode = _TimingMode.time;
                }
              }),
            ),
          ],
          // Weekly (flexible — any days) is the one mode where the target
          // isn't already implied by something else on screen: Daily's is
          // the stepper above, and Specific Days' target *is* however many days
          // are picked below. So it's the only one that needs its own
          // control — how many times this week, days unspecified, e.g.
          // "gym 4x/week." Capped at 6, not 7: 7x/week is just Daily.
          if (_freqType == HabitFrequencyType.weekly && _selectedWeekdays.isEmpty) ...[
            const SizedBox(height: 10),
            DropdownButtonFormField<int>(
              value: _weeklyTargetInRange,
              decoration: InputDecoration(labelText: s.timesPerWeek),
              items: [
                for (var n = 1; n <= 6; n++)
                  DropdownMenuItem(value: n, child: Text(s.habitWeeklyTimes(n))),
              ],
              onChanged: (v) {
                if (v == null) return;
                HapticFeedback.selectionClick();
                setState(() => _freqTarget = v);
              },
            ),
          ],
          if (_selectedWeekdays.isNotEmpty) ...[
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
        ],
      );

  /// The preview card's second line, or null when there is nothing true to
  /// put on it yet.
  ///
  /// Null, not an empty string: an empty Text still takes its line box, and
  /// a blank row under the habit's name reads as a rendering fault. The
  /// card drops the line instead (see [_goalPreviewCard]).
  ///
  /// The unanswered cadence is the reason this can be null at all. Before
  /// the chips opened unlit, the else-branch below was always reachable and
  /// always true; now, printing «يومياً» here for a chip nobody has touched
  /// would be the form making the claim two lines above the button that
  /// commits it, which is the whole thing the unlit chips exist to stop.
  String? _summary(S s) {
    final freq = _freqType == null
        ? null
        : (_selectedWeekdays.isNotEmpty ||
                _freqType == HabitFrequencyType.weekly
            ? s.habitWeeklyTimes(_freqTarget)
            // A counted daily habit says how many, because "Daily" alone is
            // the one thing this preview would then be getting wrong.
            : (_dailyTargetInRange > 1
                // The whole phrase, not a numeral glued to a unit: Arabic
                // says "مرتين في اليوم" for two, where the number IS the
                // noun's form.
                ? '${s.daily} · ${s.timesPerDayPhrase(_dailyTargetInRange)}'
                : s.daily));
    final cue = _currentCue();
    final cueLabel = cue.isEmpty ? null : cue.labelForLocale(s.isAr);
    // Whatever HAS been answered, and only that: a cue with no cadence
    // still says the cue.
    if (freq == null) return cueLabel;
    return cueLabel == null ? freq : '$freq · $cueLabel';
  }

  /// A running "here's what you're about to create" confirmation — icon,
  /// name, frequency, and the XP it'll pay out, so the reward is visible
  /// before you commit, not just after. When there's a cue on a build goal,
  /// the full "After Fajr, I will Read Quran" implementation-intention
  /// sentence — the actual behavior-science reason the cue field exists —
  /// appears below it too.
  Widget _goalPreviewCard(S s) {
    final gp = context.gp;
    // A picked icon color takes over the whole preview card's accent (not
    // just the icon glyph) — this card is one small, single-color unit, so
    // splitting it into two different colors would look mismatched rather
    // than showing a clean "here's what you're about to create."
    final color = _iconColorHex != null
        ? (_iconColor ?? context.gp.textTert)
        : (_goalType == GoalType.build ? GameColors.gold : GameColors.iconXp);
    final cue = _currentCue();
    final cueText = cue.labelForLocale(s.isAr);
    final name = _nameCtrl.text.trim();
    final showPlanSentence = _goalType == GoalType.build && !cue.isEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  // Ink for the glyph only - the 8% wash and 22% border
                  // above keep the true colour, so the card still reads as
                  // one unit.
                  child: CategoryIcon(
                      category: _category, size: 17, color: gp.ink(color)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: gp.textPrimary),
                    ),
                    if (_summary(s) case final summary?) ...[
                      const SizedBox(height: 2),
                      Text(
                        summary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, color: gp.textSec),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
                ),
                child: Text(
                  '+$_categoryXp XP',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color),
                ),
              ),
            ],
          ),
          // The link, named on the last screen before the button that
          // creates it. Step 2 is a different screen from the card, so
          // without this the last mention of health was one Continue tap
          // ago and the OS permission sheet arrived out of nowhere.
          if (_stepCardVisible && _stepLinkEnabled) ...[
            const SizedBox(height: 10),
            Container(height: 0.5, color: color.withOpacity(0.18)),
            const SizedBox(height: 10),
            Row(
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
          ],
          if (showPlanSentence) ...[
            const SizedBox(height: 10),
            Container(height: 0.5, color: color.withOpacity(0.18)),
            const SizedBox(height: 10),
            Text(
              s.planPreview(cueText, name),
              style: TextStyle(
                fontSize: 12.5,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w600,
                color: gp.textSec,
                height: 1.3,
              ),
            ),
          ],
        ],
      ),
    );
  }

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

  void _setCueRelation(_CueRelation relation) {
    HapticFeedback.selectionClick();
    setState(() {
      _cueRelation = relation;
      // Only Custom Text mode has a live field to keep in sync — Prayer
      // mode applies the relation at read time (see _currentCue), since
      // there's no text of its own to rewrite.
      if (_timingMode == _TimingMode.text && _cueCtrl.text.trim().isNotEmpty) {
        _cueCtrl.text = _cueWithRelation(_cueCtrl.text);
      }
    });
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

  void _applySuggestion(GoalSuggestion suggestion) {
    HapticFeedback.selectionClick();
    _nameCtrl.text = suggestion.name(S.of(context).isAr);
    setState(() {
      _category = suggestion.category;
      _didPickCategory = true;
      _hasName = true;
    });
  }

  /// Scrolls the sheet so the (freshly re-filtered) suggestions section is
  /// fully visible, and drops the keyboard to reclaim the space it was
  /// using. Called right after picking a category with no name typed yet —
  /// the moment the suggestions are the most useful thing on screen, and
  /// the most likely to be sitting below the fold under an open keyboard.
  ///
  /// Deliberately uses Scrollable.ensureVisible instead of a fixed pixel
  /// offset: it measures the suggestions section's actual on-screen
  /// position at call time, so this lands correctly on a small phone or a
  /// tablet, portrait or landscape, keyboard up or down — a hardcoded
  /// offset would only ever be correct on whichever single device it was
  /// tuned against.
  void _revealSuggestions() {
    FocusScope.of(context).unfocus();
    // Waits a frame so this scrolls to where the suggestions section
    // actually lands *after* the setState above (new category => a
    // different, re-filtered chip grid => a possibly different height),
    // not to its stale pre-rebuild position.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = _suggestionsKey.currentContext;
      if (target == null) return;
      Scrollable.ensureVisible(
        target,
        alignment: 0.1,
        duration: GameMotion.slow,
        curve: Curves.easeOutCubic,
      );
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
  /// it come with it. Unlike [_revealSuggestions] this deliberately does
  /// not drop the keyboard: the person is mid-word in the name field, and
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

  /// The chips for the picked category on the current side, and nothing
  /// else. This used to fall back to "the first six of this type" when a
  /// category had none, so a person who had just tapped «التعلّم» was shown
  /// prayer and sugar (Aziz, 2026-09-08). Every offered category now has
  /// four on each side (goal_suggestions_test.dart), so the fallback is
  /// gone; an empty answer simply hides the section.
  List<GoalSuggestion> _suggestions() => suggestionsFor(_goalType, _category);

  /// Splits into whole words, after stripping common punctuation, rather
  /// than the plain substring match this replaced. Deliberately doesn't use
  /// regex `\b`/`\w` — those only recognize a-z/0-9 as "word" characters by
  /// default, so they'd silently fail to find word boundaries anywhere in
  /// Arabic text. Splitting on whitespace instead works identically for
  /// both scripts, since both separate words with spaces.
  Set<String> _wordsIn(String text) {
    final cleaned = text.toLowerCase().replaceAll(RegExp(r'[.,!?؟،:;]'), ' ');
    return cleaned.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toSet();
  }

  /// Guesses a starting category from what's typed so far — never meant to
  /// be perfect, just a reasonable default the user can always override
  /// with a manual chip tap (see [_didPickCategory], which also makes this
  /// function stop being consulted at all once that happens).
  ///
  /// Two fixes over the previous version: matching is now whole-word only
  /// (the old plain substring check matched "run" inside "runway" and
  /// "bed" inside "bedroom"), and every category is scored by how many of
  /// its keywords actually appear instead of returning on the first `if`
  /// that matches — a title mentioning two domains now picks whichever is
  /// the stronger signal rather than whichever category happened to be
  /// checked first. `mind` and `social` previously had no keywords at all
  /// and could never be auto-detected; both now do.
  HabitCategory _inferCategory(String text) {
    final words = _wordsIn(text);
    if (words.isEmpty) {
      return _didPickCategory ? _category : HabitCategory.custom;
    }
    const keywordsByCategory = <HabitCategory, List<String>>{
      HabitCategory.faith: [
        'quran', 'قرآن', 'سورة', 'آية', 'ayah', 'surah',
        'athkar', 'أذكار', 'ذكر', 'dhikr',
        'pray', 'prayer', 'praying', 'صلاة', 'صلي', 'دعاء', 'dua',
      ],
      HabitCategory.health: [
        'gym', 'رياضة', 'مشي', 'تمرين',
        'walk', 'walking', 'run', 'running', 'jog', 'jogging',
        'workout', 'workouts', 'water', 'exercise', 'stretch', 'stretching',
      ],
      HabitCategory.learning: [
        'study', 'studying', 'دراسة', 'قراءة', 'لغة',
        'read', 'reading', 'language', 'english', 'course', 'كورس',
        'كتاب', 'book',
      ],
      HabitCategory.focus: [
        'phone', 'scrolling', 'scroll', 'جوال', 'تصفح',
        'tiktok', 'gaming', 'game', 'games', 'youtube', 'يوتيوب',
      ],
      HabitCategory.sleep: [
        'sleep', 'sleeping', 'نوم', 'سهر', 'bed', 'bedtime', 'nap',
      ],
      HabitCategory.money: [
        'money', 'spending', 'spend', 'صرف', 'مصروف',
        'budget', 'save', 'saving', 'savings', 'مال', 'ميزانية',
      ],
      HabitCategory.mind: [
        'meditate', 'meditation', 'تأمل',
        'gratitude', 'امتنان', 'journal', 'journaling', 'يوميات',
        'breathing', 'تنفس', 'mindfulness', 'stress', 'توتر',
        'anxiety', 'قلق',
      ],
      HabitCategory.social: [
        'family', 'عائلة', 'friend', 'friends', 'أصدقاء',
        'call', 'اتصال', 'visit', 'زيارة', 'message', 'رسالة',
      ],
    };
    HabitCategory? best;
    var bestScore = 0;
    for (final entry in keywordsByCategory.entries) {
      var score = entry.value.where((k) => words.contains(k)).length;
      // The walking detector answers the same question about this name,
      // only far better than a word list can: it folds Arabic, strips the
      // definite article and forgives typos, so "المشي", "امشي شوي",
      // "walkk" and "10k steps" reach Health the way the exact keyword
      // "walking" already did. Before this they all landed on Custom,
      // which is how a habit the app was about to offer a step link for
      // could still be filed as uncategorised.
      //
      // Counted as one more health keyword rather than forced, so a name
      // that is mostly about something else ("read while walking") is
      // still decided by the rest of the words.
      if (entry.key == HabitCategory.health && looksLikeStepHabit(text)) {
        score += 1;
      }
      if (score > bestScore) {
        best = entry.key;
        bestScore = score;
      }
    }
    // "تيك توك" (TikTok) is the one keyword that's two tokens, not one, so
    // the word-set match above never sees it as a single unit — checked
    // separately, only as a fallback so a real single-keyword match
    // elsewhere still wins.
    if (best == null && text.toLowerCase().contains('تيك توك')) {
      best = HabitCategory.focus;
    }
    return best ?? (_didPickCategory ? _category : HabitCategory.custom);
  }

  HabitCategory _canonicalCategory(HabitCategory cat) => switch (cat) {
        HabitCategory.quran || HabitCategory.athkar || HabitCategory.fasting || HabitCategory.sadaqah => HabitCategory.faith,
        HabitCategory.fitness => HabitCategory.health,
        _ => cat,
      };
}
