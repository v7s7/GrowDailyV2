import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/game_constants.dart';
import '../../../core/extensions/datetime_ext.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/services/prayer_times_service.dart';
import '../../../core/theme/game_theme.dart';
import '../../../shared/widgets/category_icon.dart';
import '../../../shared/widgets/habit_limit_gate.dart';
import '../../../shared/widgets/victory_burst.dart';
import '../../settings/models/notification_settings.dart';
import '../../settings/notifiers/notification_settings_notifier.dart';
import '../catalog/goal_suggestions.dart';
import '../catalog/islamic_habit_catalog.dart';
import '../models/habit_cue.dart';
import '../models/habit_model.dart';
import '../../rooms/notifiers/rooms_notifier.dart';
import '../notifiers/custom_habits_notifier.dart';
import 'habit_color_picker.dart';

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

  const AddHabitSheet({super.key, this.existing, this.embedded = false});

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

  // ── Reminder lead time — how many minutes before the resolved time/
  // prayer moment the notification actually fires. Only meaningful for
  // Time/Prayer modes (Custom Text has no resolved moment to count back
  // from) — see _reminderLeadSection.
  static const _leadPresets = [0, 15, 30, 60];
  int _reminderLead = 0;
  bool _customLeadSelected = false;
  final _reminderLeadCtrl = TextEditingController();

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
      final storedLead = existing.reminderLeadMinutes;
      if (_leadPresets.contains(storedLead)) {
        _reminderLead = storedLead;
      } else {
        _reminderLead = storedLead;
        _customLeadSelected = true;
        _reminderLeadCtrl.text = storedLead.toString();
      }
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
    _reminderLeadCtrl.addListener(() {
      if (_customLeadSelected) setState(() {});
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

  @override
  void dispose() {
    _nameCtrl.dispose();
    _cueCtrl.dispose();
    _limitCtrl.dispose();
    _customUnitCtrl.dispose();
    _reminderLeadCtrl.dispose();
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
  int get _effectiveReminderLead {
    if (_timingMode == _TimingMode.text) return 0;
    if (!_customLeadSelected) return _reminderLead;
    final parsed = int.tryParse(_reminderLeadCtrl.text.trim()) ?? 0;
    return parsed.clamp(0, 360);
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
    final cue = _currentCue().toStorageValue();
    final limitAmount = int.tryParse(_limitCtrl.text.trim());
    final notifier = ref.read(customHabitsProvider.notifier);
    if (existing != null) {
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
        reminderLeadMinutes: _effectiveReminderLead,
      );
    } else {
      notifier.add(
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
        reminderLeadMinutes: _effectiveReminderLead,
      );
    }
    Navigator.pop(context);
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
          content: Text(s.habitLinkedRoomWarningBody(linkedRooms.length)),
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
    ref.read(customHabitsProvider.notifier).archive(existing.id);
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
              content,
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
              duration: const Duration(milliseconds: 260),
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
                    setState(() {
                      _forward = false;
                      _step = 0;
                    });
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
                              setState(() {
                                _forward = true;
                                _step = 1;
                              });
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
                setState(() {
                  _forward = true;
                  _step = 1;
                });
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
            duration: const Duration(milliseconds: 200),
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
        if (picked != null) _reminderLeadSection(s),
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
                    },
                  ),
                ),
              ],
            ],
          ),
          if (_selectedPrayer != null) _reminderLeadSection(s),
        ],
      );

  /// "Remind me [on time / 15 min / 30 min / 1 hour / custom] before" —
  /// sits under Time/Prayer mode once a concrete anchor is picked (see the
  /// two call sites above). Custom Text mode never shows this: a freeform
  /// cue has no resolved clock/prayer moment for a lead time to mean
  /// anything against. Mirrors the LimitUnit.custom pattern elsewhere in
  /// this file — a row of quick options, plus a numeric field that only
  /// appears once "Custom" itself is selected.
  Widget _reminderLeadSection(S s) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 14),
          _SectionLabel(s.remindMeSection),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final preset in _leadPresets) ...[
                if (preset != _leadPresets.first) const SizedBox(width: 6),
                Expanded(
                  child: _EqualPill(
                    selected: !_customLeadSelected && _reminderLead == preset,
                    label: _leadPresetLabel(s, preset),
                    onTap: () => _selectLeadPreset(preset),
                  ),
                ),
              ],
              const SizedBox(width: 6),
              Expanded(
                child: _EqualPill(
                  selected: _customLeadSelected,
                  label: s.leadCustomOption,
                  onTap: _selectCustomLead,
                ),
              ),
            ],
          ),
          if (_customLeadSelected) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _reminderLeadCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: s.leadCustomMinutesHint),
            ),
          ],
          _reminderTimePreview(s),
        ],
      );

  /// The already-resolved moment a reminder counts *back from* — a habit's
  /// own picked clock time as-is, or (for a prayer cue) today's prayer
  /// moment plus [NotificationSettings.prayerOffsetMinutes], mirroring
  /// NotificationService.scheduleSmartReminders' own
  /// `candidate.add(offset).subtract(lead)` sequence exactly so this
  /// preview and the real scheduled fire time never disagree about what
  /// they're counting back from — only [_reminderTimePreview] then
  /// subtracts the lead itself, same as that method does. Returns null
  /// when there's nothing to compute yet: no time/prayer picked, or (prayer
  /// mode only) no location saved to calculate against.
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
      final raw = today.forKey(prayer);
      if (raw == null) return null;
      return raw.add(Duration(minutes: settings.prayerOffsetMinutes));
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
              Icon(Icons.location_off_outlined, size: 13, color: gp.textTert),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  s.remindPreviewNeedsLocation,
                  style: TextStyle(fontSize: 11, color: gp.textTert, height: 1.3),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final reminderMoment = anchor.subtract(Duration(minutes: _effectiveReminderLead));
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

  String _leadPresetLabel(S s, int minutes) => switch (minutes) {
        0 => s.leadAtTime,
        15 => s.lead15Min,
        30 => s.lead30Min,
        60 => s.lead1Hour,
        _ => '$minutes',
      };

  void _selectLeadPreset(int minutes) {
    HapticFeedback.selectionClick();
    setState(() {
      _reminderLead = minutes;
      _customLeadSelected = false;
    });
  }

  void _selectCustomLead() {
    HapticFeedback.selectionClick();
    setState(() => _customLeadSelected = true);
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
                  borderRadius: BorderRadius.circular(100),
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
        duration: const Duration(milliseconds: 320),
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

// ─── Equal-width pill (fixed 1/n row share, centered, shrink-to-fit text) ──
// Used wherever a fixed-size set of options (5 prayers, 7 weekdays) should
// always fill exactly one row at uniform width, rather than wrap unevenly.

class _EqualPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _EqualPill({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: TweenAnimationBuilder<double>(
        key: ValueKey(selected),
        tween: Tween(begin: selected ? 0.9 : 1.0, end: 1.0),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutBack,
        builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? GameColors.gold.withOpacity(0.12) : gp.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? GameColors.gold.withOpacity(0.5) : gp.border),
          ),
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected ? GameColors.gold : gp.textSec,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Fixed-column chip grid ─────────────────────────────────────────────
// Every cell gets the exact same width (available width ÷ columns, minus
// gaps), so a row of chips lines up like a grid regardless of how long
// each individual label is — the plain Wrap this replaced sized each chip
// to its own text, which produced a different chip count on every row and
// a lot of dead space next to short labels.
class _ChipGrid extends StatelessWidget {
  final int columns;
  final List<Widget> items;
  static const double _spacing = 8;
  const _ChipGrid({
    required this.columns,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cellWidth =
            (constraints.maxWidth - _spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: _spacing,
          runSpacing: _spacing,
          children: [
            for (final item in items) SizedBox(width: cellWidth, child: item),
          ],
        );
      },
    );
  }
}

class _PlainChoiceChip extends StatelessWidget {
  final bool selected;
  final String label;
  final Widget? icon;
  final VoidCallback onTap;

  const _PlainChoiceChip({
    required this.selected,
    required this.label,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: TweenAnimationBuilder<double>(
        key: ValueKey(selected),
        tween: Tween(begin: selected ? 0.88 : 1.0, end: 1.0),
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutBack,
        builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? GameColors.gold.withOpacity(0.14) : gp.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? GameColors.gold : gp.border.withOpacity(0.8),
              width: selected ? 1.1 : 0.8,
            ),
          ),
          // Centered, not left-hugged — now that _ChipGrid gives every chip
          // the same fixed width, a short label like "Faith" would
          // otherwise sit at the left edge with empty space on the right.
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                icon!,
                const SizedBox(width: 7),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                    color: selected ? GameColors.gold : gp.textPrimary,
                    height: 1.1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlainActionChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  // Set on suggestion chips only — a small reward preview to make tapping
  // one feel like claiming a shortcut, not just filling in a text field.
  // Left null for plain action chips that aren't tied to any specific
  // reward.
  final int? xp;

  const _PlainActionChip({required this.label, required this.onTap, this.xp});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: gp.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: gp.border.withOpacity(0.9), width: 0.8),
        ),
        // Centered, and the label is the one that gives way (ellipsis) if
        // the fixed cell is too narrow for it — the XP badge stays fixed
        // size and always fully visible, same reasoning as
        // _PlainChoiceChip's centering above.
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: gp.textPrimary,
                  height: 1.1,
                ),
              ),
            ),
            if (xp != null) ...[
              const SizedBox(width: 6),
              Text(
                '+$xp',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: GameColors.gold,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.gp.textTert));
}

class _SmallPick extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SmallPick({required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: TweenAnimationBuilder<double>(
        key: ValueKey(selected),
        tween: Tween(begin: selected ? 0.9 : 1.0, end: 1.0),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutBack,
        builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? GameColors.gold.withOpacity(0.12) : gp.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? GameColors.gold.withOpacity(0.5) : gp.border),
          ),
          alignment: Alignment.center,
          child: Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: selected ? FontWeight.w800 : FontWeight.w600, color: selected ? GameColors.gold : gp.textSec)),
        ),
      ),
    );
  }
}
