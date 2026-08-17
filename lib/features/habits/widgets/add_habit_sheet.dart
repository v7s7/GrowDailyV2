import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/game_constants.dart';
import '../../../core/extensions/datetime_ext.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/services/device_location_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/prayer_times_service.dart';
import '../../../core/theme/game_theme.dart';
import '../../../shared/widgets/category_icon.dart';
import '../../../shared/widgets/habit_limit_gate.dart';
import '../../../shared/widgets/victory_burst.dart';
import '../../settings/models/notification_settings.dart';
import '../../settings/notifiers/notification_settings_notifier.dart';
import '../../settings/widgets/city_search_sheet.dart';
import '../catalog/goal_suggestions.dart';
import '../catalog/habit_plans.dart' show activeCatalogProvider;
import '../catalog/islamic_habit_catalog.dart';
import '../notifiers/catalog_overrides_notifier.dart';
import '../models/habit_cue.dart';
import '../models/habit_model.dart';
import '../../dashboard/notifiers/dashboard_notifier.dart';
import '../../rooms/notifiers/rooms_notifier.dart';
import '../notifiers/custom_habits_notifier.dart';
import '../../../shared/widgets/choice_chip_grid.dart';
import 'habit_color_picker.dart';

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

  const AddHabitSheet({
    super.key,
    this.existing,
    this.embedded = false,
    this.onStepChanged,
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
  HabitFrequencyType _freqType = HabitFrequencyType.daily;
  int _freqTarget = 1;
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
  _TimingMode _timingMode = _TimingMode.time;
  // Once the user manually picks a mode, category/goal-type changes stop
  // silently overriding it — same pattern as [_didPickCategory] below.
  bool _timingModeTouched = false;
  String? _selectedPrayer;
  TimeOfDay? _pickedTime;
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

  // ── Reminder offset — signed minutes from the resolved time/prayer
  // moment to when the notification actually fires: negative = before,
  // 0 = on time, positive = after. Only meaningful for Time/Prayer modes
  // (Custom Text has no resolved moment to offset from) — see
  // _reminderOffsetSection.
  //
  // Ordered earliest → latest so the row reads like a timeline, with "On
  // time" (0) sitting naturally in the middle as the default.
  static const _offsetPresets = [-30, -15, 0, 15, 30];
  int _reminderOffset = 0;
  bool _customOffsetSelected = false;
  // Custom entry is split into a magnitude field + a before/after choice,
  // rather than asking anyone to type a minus sign.
  final _reminderOffsetCtrl = TextEditingController();
  bool _customOffsetIsAfter = false;

  // Where the confetti burst on submit fires from — see _submit().
  final GlobalKey _createButtonKey = GlobalKey();
  // Locates the smart-suggestions section so _revealSuggestions() can
  // scroll it into view — see that method.
  final GlobalKey _suggestionsKey = GlobalKey();

  bool get _isEditing => widget.existing != null;

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

  /// A safe, always-reasonable starting timing mode for a fresh habit —
  /// never a guess at the exact prayer/time itself, just which picker to
  /// open first. Faith habits open on Prayer, quit/reduce goals open on
  /// Custom Text (the "when is it hardest" question rarely has a clean
  /// prayer or clock-time answer), everything else opens on Time.
  _TimingMode _defaultModeFor(HabitCategory category, GoalType goalType) {
    if (goalType == GoalType.quit) return _TimingMode.text;
    if (category == HabitCategory.faith) return _TimingMode.prayer;
    return _TimingMode.time;
  }

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
      if (parsed.clockTime != null) {
        _timingMode = _TimingMode.time;
        _pickedTime = parsed.clockTime;
      } else if (parsed.isPrayer) {
        _timingMode = _TimingMode.prayer;
        _selectedPrayer = parsed.prayerKey;
      } else if (!parsed.isEmpty) {
        _timingMode = _TimingMode.text;
        _cueCtrl.text = storedCue;
      }
      _timingModeTouched = true;
      final storedOffset = existing.reminderOffsetMinutes;
      _reminderOffset = storedOffset;
      if (!_offsetPresets.contains(storedOffset)) {
        _customOffsetSelected = true;
        _customOffsetIsAfter = storedOffset > 0;
        // Magnitude only — direction is carried by the toggle beside it.
        _reminderOffsetCtrl.text = storedOffset.abs().toString();
      }
      _ignoreQuietHours = existing.ignoreQuietHours;
      _category = _canonicalCategory(existing.category);
      _freqType = existing.frequencyType;
      _freqTarget = existing.frequencyTarget;
      _selectedWeekdays = existing.scheduledWeekdays.toSet();
      _goalType = existing.goalType;
      _reductionType = existing.reductionType;
      _limitCtrl.text = existing.limitAmount?.toString() ?? '';
      _limitUnit = existing.limitUnit ?? LimitUnit.minutes;
      _customUnitCtrl.text = existing.customUnitLabel ?? '';
      _iconColorHex = existing.iconColorHex;
      _hasName = true;
      _didPickCategory = true;
    }
    _nameCtrl.addListener(() {
      final text = _nameCtrl.text.trim();
      final has = text.isNotEmpty;
      final inferred = _inferCategory(text);
      final categoryChanging = !_didPickCategory && inferred != _category;
      if (has != _hasName || categoryChanging) {
        setState(() {
          _hasName = has;
          if (!_didPickCategory) {
            _category = inferred;
            if (!_timingModeTouched) {
              _timingMode = _defaultModeFor(_category, _goalType);
            }
          }
        });
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
    _reminderOffsetCtrl.addListener(() {
      if (_customOffsetSelected) setState(() {});
    });
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
    _limitCtrl.dispose();
    _customUnitCtrl.dispose();
    _reminderOffsetCtrl.dispose();
    _focus.dispose();
    _cueFocus.dispose();
    super.dispose();
  }

  /// Resolves whichever timing mode is active right now into the single
  /// [HabitCue] that gets saved and previewed — the one place that turns
  /// "Time / Prayer / Custom text + before-after" into the actual value,
  /// so submit and the live preview can never disagree with each other.
  HabitCue _currentCue() => switch (_timingMode) {
        _TimingMode.time => _pickedTime == null
            ? HabitCue.empty
            : HabitCue.time(_pickedTime!.hour, _pickedTime!.minute),
        _TimingMode.prayer => _selectedPrayer == null
            ? HabitCue.empty
            : HabitCue.fromStoredValue(
                _cueWithRelation(HabitCue.preset(_selectedPrayer!).labelFor(context)),
              ),
        _TimingMode.text => HabitCue.fromStoredValue(_cueWithRelation(_cueCtrl.text)),
      };

  /// The lead time that actually gets saved — 0 (no override) for Custom
  /// Text mode regardless of whatever was previously picked, since a
  /// freeform cue has no resolved moment for a lead time to count back
  /// from (see NotificationService.scheduleSmartReminders). Custom-value
  /// entry is clamped to a sane 0–360 minute range so a stray typo can't
  /// push a reminder days away from the habit it's for.
  int get _effectiveReminderOffset {
    if (_timingMode == _TimingMode.text) return 0;
    if (!_customOffsetSelected) return _reminderOffset;
    // The field holds a magnitude; the before/after toggle supplies the
    // sign, so a stray "-" typed into a number field can't flip the
    // meaning out from under the toggle.
    final parsed = (int.tryParse(_reminderOffsetCtrl.text.trim()) ?? 0)
        .abs()
        .clamp(0, 360);
    return _customOffsetIsAfter ? parsed : -parsed;
  }

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

  void _submit() {
    if (!_hasName) return;
    final existing = widget.existing;
    if (existing == null && !canAddHabits(ref)) {
      Navigator.pop(context);
      showHabitLimitGate(context, ref);
      return;
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
    if (_timingMode != _TimingMode.text) {
      _ensureNotificationPermission();
    }
    final cue = _currentCue().toStorageValue();
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
    if (existing != null && IslamicHabitCatalog.findById(existing.id) != null) {
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
              frequencyType: _freqType == catalogDefault.frequencyType
                  ? null
                  : _freqType,
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
        frequencyType: _freqType,
        frequencyTarget: _freqTarget,
        scheduledWeekdays: _selectedWeekdays.toList()..sort(),
        goalType: _goalType,
        reductionType: _reductionType,
        limitAmount: _reductionType == ReductionType.limit ? limitAmount : null,
        limitUnit: _reductionType == ReductionType.limit ? _limitUnit : null,
        customUnitLabel: _reductionType == ReductionType.limit
            ? _customUnitCtrl.text.trim()
            : null,
        iconColorHex: _iconColorHex,
        clearIconColor: _iconColorHex == null,
        reminderOffsetMinutes: _effectiveReminderOffset,
        ignoreQuietHours: _ignoreQuietHours,
      );
    } else {
      created = notifier.add(
        name: _nameCtrl.text.trim(),
        category: _category,
        cueAfter: cue,
        frequencyType: _freqType,
        frequencyTarget: _freqTarget,
        scheduledWeekdays: _selectedWeekdays.toList()..sort(),
        goalType: _goalType,
        reductionType: _reductionType,
        limitAmount: _reductionType == ReductionType.limit ? limitAmount : null,
        limitUnit: _reductionType == ReductionType.limit ? _limitUnit : null,
        customUnitLabel: _reductionType == ReductionType.limit
            ? _customUnitCtrl.text.trim()
            : null,
        iconColorHex: _iconColorHex,
        reminderOffsetMinutes: _effectiveReminderOffset,
        ignoreQuietHours: _ignoreQuietHours,
      );
    }
    Navigator.pop(context, created);
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
    messenger.showSnackBar(
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
  Widget _content(BuildContext context, S s) {
    final gp = context.gp;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
          padding: EdgeInsets.fromLTRB(20, 10, 20, _isEditing ? 4 : 20),
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
                  onPressed: !_hasName
                      ? null
                      : _step == 0
                          ? () {
                              HapticFeedback.selectionClick();
                              FocusScope.of(context).unfocus();
                              _goToStep(1, forward: true);
                            }
                          : _submit,
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
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
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
          _goalTypeToggle(s)
              .animate()
              .fadeIn(duration: 240.ms)
              .slideY(begin: 0.06, curve: Curves.easeOutCubic),
          const SizedBox(height: 16),
          _nameAndCategorySection(s)
              .animate(delay: 60.ms)
              .fadeIn(duration: 240.ms)
              .slideY(begin: 0.06, curve: Curves.easeOutCubic),
          if (_goalType == GoalType.quit) ...[
            const SizedBox(height: 16),
            _quitStyleSection(s)
                .animate(delay: 100.ms)
                .fadeIn(duration: 240.ms)
                .slideY(begin: 0.06, curve: Curves.easeOutCubic),
          ],
        ],
      );

  Widget _goalTypeToggle(S s) => Row(
        children: [
          Expanded(
            child: _SmallPick(
              label: s.buildHabitTitle,
              selected: _goalType == GoalType.build,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _goalType = GoalType.build;
                  if (!_timingModeTouched) {
                    _timingMode = _defaultModeFor(_category, _goalType);
                  }
                });
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _SmallPick(
              label: s.quitHabitTitle,
              selected: _goalType == GoalType.quit,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _goalType = GoalType.quit;
                  if (!_timingModeTouched) {
                    _timingMode = _defaultModeFor(_category, _goalType);
                  }
                });
              },
            ),
          ),
        ],
      );

  Widget _nameAndCategorySection(S s) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _nameCtrl,
            focusNode: _focus,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: context.gp.textPrimary,
            ),
            textCapitalization: TextCapitalization.sentences,
            onSubmitted: (_) {
              if (_hasName) {
                HapticFeedback.selectionClick();
                FocusScope.of(context).unfocus();
                _goToStep(1, forward: true);
              }
            },
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
                      color: _iconColorHex != null
                          ? Color(0xFF000000 |
                              int.parse(_iconColorHex!, radix: 16))
                          : Colors.transparent,
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
          const SizedBox(height: 16),
          _SectionLabel(s.category),
          const SizedBox(height: 8),
          // Fixed 3-column grid (9 categories = an exact 3×3) instead of a
          // content-hugging Wrap — the old version sized every chip to its
          // own label ("Faith" vs "Learning" vs "Custom"), so rows never
          // lined up and the count-per-row wandered between 2 and 4. Each
          // cell is now the same width, so the grid reads as a grid.
          _ChipGrid(
            columns: 3,
            items: _broadCategories.map((cat) {
              final selected = _category == cat;
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
                    if (!_timingModeTouched) {
                      _timingMode = _defaultModeFor(_category, _goalType);
                    }
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
          // A shortcut to fill in the name field, so it's only useful
          // before there's a name — once one's typed or picked, showing
          // it below would just be duplicate noise. XP hinted right on the
          // chip since tapping one is a one-tap "start earning" shortcut.
          if (!_hasName)
            Column(
              key: _suggestionsKey,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                _SectionLabel(s.smartSuggestions),
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
              ],
            ),
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
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _limitCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: s.maxAmount),
                  ),
                ),
                const SizedBox(width: 10),
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
          _timingModeSection(s)
              .animate(delay: 40.ms)
              .fadeIn(duration: 240.ms)
              .slideY(begin: 0.06, curve: Curves.easeOutCubic),
          const SizedBox(height: 8),
          _timingOptionalNote(s)
              .animate(delay: 70.ms)
              .fadeIn(duration: 240.ms),
          const SizedBox(height: 18),
          _frequencySection(s)
              .animate(delay: 90.ms)
              .fadeIn(duration: 240.ms)
              .slideY(begin: 0.06, curve: Curves.easeOutCubic),
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
          ),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: GameMotion.standard,
            child: KeyedSubtree(
              key: ValueKey(_timingMode),
              child: switch (_timingMode) {
                _TimingMode.time => _timeModeContent(s),
                _TimingMode.prayer => _prayerModeContent(s),
                _TimingMode.text => _textModeContent(s),
              },
            ),
          ),
        ],
      );

  /// Sits under the time/prayer/text picker as a standing reminder that none
  /// of it is required — _submit() only ever requires a name, and an
  /// untouched picker already saves as HabitCue.empty (see _currentCue).
  /// That was already true before this note existed; the note just makes it
  /// visible instead of leaving people to guess whether they have to force
  /// a time onto a habit that doesn't really have one.
  Widget _timingOptionalNote(S s) {
    final gp = context.gp;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 13, color: gp.textTert),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              s.timingOptionalNote,
              style: TextStyle(fontSize: 11, color: gp.textTert, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }

  void _selectTimingMode(_TimingMode mode) {
    HapticFeedback.selectionClick();
    setState(() {
      _timingMode = mode;
      _timingModeTouched = true;
    });
  }

  Widget _timeModeContent(S s) {
    final gp = context.gp;
    final picked = _pickedTime;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _pickTime,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: gp.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: gp.border, width: 0.5),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.schedule_rounded,
                  size: 18,
                  color: picked == null ? gp.textTert : GameColors.gold,
                ),
                const SizedBox(width: 10),
                Text(
                  picked == null ? s.pickATime : HabitCue.time(picked.hour, picked.minute).labelForLocale(s.isAr),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: picked == null ? FontWeight.w600 : FontWeight.w800,
                    color: picked == null ? gp.textTert : gp.textPrimary,
                  ),
                ),
                const Spacer(),
                Icon(Icons.chevron_right_rounded, size: 18, color: gp.textTert),
              ],
            ),
          ),
        ),
        if (picked != null) _reminderOffsetSection(s),
      ],
    );
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
  Widget _reminderOffsetSection(S s) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 14),
          _SectionLabel(s.remindMeSection),
          const SizedBox(height: 8),
          _ChipGrid(
            columns: 3,
            items: [
              for (final preset in _offsetPresets)
                _PlainChoiceChip(
                  selected: !_customOffsetSelected && _reminderOffset == preset,
                  label: _offsetPresetLabel(s, preset),
                  onTap: () => _selectOffsetPreset(preset),
                ),
              _PlainChoiceChip(
                selected: _customOffsetSelected,
                label: s.leadCustomOption,
                onTap: _selectCustomOffset,
              ),
            ],
          ),
          if (_customOffsetSelected) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _reminderOffsetCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: s.leadCustomMinutesHint),
            ),
            const SizedBox(height: 8),
            // Direction as its own two-chip row rather than a typed minus
            // sign — and on its own line rather than beside the field,
            // which used to overflow once the label text got long.
            _ChipGrid(
              columns: 2,
              items: [
                _PlainChoiceChip(
                  selected: !_customOffsetIsAfter,
                  label: s.offsetBeforeLabel,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _customOffsetIsAfter = false);
                  },
                ),
                _PlainChoiceChip(
                  selected: _customOffsetIsAfter,
                  label: s.offsetAfterLabel,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _customOffsetIsAfter = true);
                  },
                ),
              ],
            ),
          ],
          _reminderTimePreview(s),
          _quietHoursWarning(s),
        ],
      );

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
    messenger.showSnackBar(
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
    ScaffoldMessenger.of(context).showSnackBar(
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

  /// Small "you'll be reminded at ..." line under the lead-time picker —
  /// [S.remindAtTimePreview] once [_reminderAnchorTime] resolves to
  /// something, [S.remindPreviewNeedsLocation] instead for Prayer mode with
  /// no saved location (nothing to calculate against yet, but still worth
  /// explaining why rather than just showing nothing), or nothing at all
  /// for Time mode before a time's been picked (the row this sits under
  /// isn't even shown yet in that case — see _timeModeContent/
  /// _prayerModeContent's `if (picked != null)`/`if (_selectedPrayer !=
  /// null)` guards around this whole section).
  Widget _reminderTimePreview(S s) {
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
    // Signed: added, never subtracted — the exact single operation
    // NotificationService.scheduleSmartReminders performs, which is what
    // keeps this preview honest.
    final reminderMoment = anchor.add(Duration(minutes: _effectiveReminderOffset));
    final locale = s.isAr ? 'ar' : 'en';
    final timeLabel = DateFormat('h:mm a', locale).format(reminderMoment);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: GameColors.gold.withOpacity(0.10),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: GameColors.gold.withOpacity(0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.notifications_active_rounded, size: 13, color: GameColors.gold),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  s.remindAtTimePreview(timeLabel),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: GameColors.gold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _offsetPresetLabel(S s, int minutes) => switch (minutes) {
        0 => s.leadAtTime,
        < 0 => s.offsetBeforeMinutes(minutes.abs()),
        _ => s.offsetAfterMinutes(minutes),
      };

  void _selectOffsetPreset(int minutes) {
    HapticFeedback.selectionClick();
    setState(() {
      _reminderOffset = minutes;
      _customOffsetSelected = false;
    });
  }

  void _selectCustomOffset() {
    HapticFeedback.selectionClick();
    setState(() => _customOffsetSelected = true);
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
    if (!settings.masterEnabled || !settings.habitRemindersEnabled) {
      return const SizedBox.shrink();
    }
    if (!settings.quietHoursEnabled) return const SizedBox.shrink();
    if (_timingMode == _TimingMode.prayer &&
        !settings.quietHoursAppliesToPrayer) {
      return const SizedBox.shrink();
    }
    final anchor = _reminderAnchorTime(settings);
    if (anchor == null) return const SizedBox.shrink();
    final moment = anchor.add(Duration(minutes: _effectiveReminderOffset));
    if (!NotificationService.isMinuteWithinQuietHours(
      moment.hour * 60 + moment.minute,
      settings.quietHoursStart,
      settings.quietHoursEnd,
    )) {
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
            Icon(Icons.bedtime_outlined, size: 14, color: GameColors.error),
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
                        color: GameColors.gold,
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionLabel(s.repeat),
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
                      _freqTarget = 1;
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
          // Weekly (flexible — any days) is the one mode where the target
          // isn't already implied by something else on screen: Daily is
          // always 1, and Specific Days' target *is* however many days
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

  String _summary(S s) {
    final freq = _selectedWeekdays.isNotEmpty || _freqType == HabitFrequencyType.weekly
        ? s.habitWeeklyTimes(_freqTarget)
        : s.daily;
    final cue = _currentCue();
    return cue.isEmpty ? freq : '$freq · ${cue.labelForLocale(s.isAr)}';
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
        ? Color(0xFF000000 | int.parse(_iconColorHex!, radix: 16))
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
                  child: CategoryIcon(category: _category, size: 17, color: color),
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
                    const SizedBox(height: 2),
                    Text(
                      _summary(s),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: gp.textSec),
                    ),
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

  Future<void> _pickTime() async {
    HapticFeedback.selectionClick();
    final picked = await showTimePicker(
      context: context,
      initialTime: _pickedTime ?? TimeOfDay.now(),
      helpText: S.of(context).pickATime,
      // Force 12-hour AM/PM regardless of the device's 24-hour system
      // setting, so the picker looks the same on every phone.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() => _pickedTime = picked);
  }

  void _applySuggestion(GoalSuggestion suggestion) {
    HapticFeedback.selectionClick();
    _nameCtrl.text = suggestion.name(S.of(context).isAr);
    setState(() {
      _category = suggestion.category;
      _didPickCategory = true;
      _hasName = true;
      if (!_timingModeTouched) {
        _timingMode = _defaultModeFor(_category, _goalType);
      }
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

  List<GoalSuggestion> _suggestions() {
    final list = goalSuggestions.where((s) => s.type == _goalType && s.category == _category).toList();
    if (list.isNotEmpty) return list;
    return goalSuggestions.where((s) => s.type == _goalType).take(6).toList();
  }

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
      final score = entry.value.where((k) => words.contains(k)).length;
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
