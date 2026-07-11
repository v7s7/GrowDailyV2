import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/game_constants.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../../shared/widgets/category_icon.dart';
import '../../../shared/widgets/habit_limit_gate.dart';
import '../../../shared/widgets/victory_burst.dart';
import '../catalog/goal_suggestions.dart';
import '../catalog/islamic_habit_catalog.dart';
import '../models/habit_cue.dart';
import '../models/habit_model.dart';
import '../notifiers/custom_habits_notifier.dart';

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

  // Where the confetti burst on submit fires from — see _submit().
  final GlobalKey _createButtonKey = GlobalKey();

  bool get _isEditing => widget.existing != null;

  int get _categoryXp => GameConstants.categoryXpRewards[_category.name] ?? 10;

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
      _category = _canonicalCategory(existing.category);
      _freqType = existing.frequencyType;
      _freqTarget = existing.frequencyTarget;
      _selectedWeekdays = existing.scheduledWeekdays.toSet();
      _goalType = existing.goalType;
      _reductionType = existing.reductionType;
      _limitCtrl.text = existing.limitAmount?.toString() ?? '';
      _limitUnit = existing.limitUnit ?? LimitUnit.minutes;
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _cueCtrl.dispose();
    _limitCtrl.dispose();
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
      );
    }
    Navigator.pop(context);
  }

  void _deleteExisting() {
    final existing = widget.existing;
    if (existing == null) return;
    HapticFeedback.mediumImpact();
    ref.read(customHabitsProvider.notifier).remove(existing.id);
    Navigator.pop(context);
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
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _isEditing ? s.editHabit : s.addGoalTitle,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: gp.textPrimary,
                  ),
                ),
              ),
              _ProgressDots(totalSteps: 2, step: _step),
            ],
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
            ),
          ),
          const SizedBox(height: 16),
          _SectionLabel(s.category),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _broadCategories.map((cat) {
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
                },
              );
            }).toList(),
          ),
          // A shortcut to fill in the name field, so it's only useful
          // before there's a name — once one's typed or picked, showing
          // it below would just be duplicate noise. XP hinted right on the
          // chip since tapping one is a one-tap "start earning" shortcut.
          if (!_hasName) ...[
            const SizedBox(height: 16),
            _SectionLabel(s.smartSuggestions),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _suggestions().map((item) {
                return _PlainActionChip(
                  label: item.name(s.isAr),
                  xp: GameConstants.categoryXpRewards[item.category.name] ?? 10,
                  onTap: () => _applySuggestion(item),
                );
              }).toList(),
            ),
          ],
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
    return InkWell(
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
        ],
      );

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
                      _freqTarget = 1;
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
                        _selectedWeekdays.add(DateTime.now().weekday);
                      }
                      _freqTarget = _selectedWeekdays.length;
                    });
                  },
                ),
              ),
            ],
          ),
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
    final color = _goalType == GoalType.build ? GameColors.gold : GameColors.xpBlue;
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

  List<GoalSuggestion> _suggestions() {
    final list = goalSuggestions.where((s) => s.type == _goalType && s.category == _category).toList();
    if (list.isNotEmpty) return list;
    return goalSuggestions.where((s) => s.type == _goalType).take(6).toList();
  }

  HabitCategory _inferCategory(String text) {
    final lower = text.toLowerCase();
    bool hasAny(List<String> words) => words.any(lower.contains);
    if (hasAny(['quran', 'قرآن', 'سورة', 'آية', 'ayah', 'surah', 'athkar', 'أذكار', 'ذكر', 'dhikr'])) return HabitCategory.faith;
    if (hasAny(['gym', 'رياضة', 'مشي', 'تمرين', 'walk', 'run', 'workout', 'water'])) return HabitCategory.health;
    if (hasAny(['study', 'دراسة', 'قراءة', 'لغة', 'read', 'language', 'english'])) return HabitCategory.learning;
    if (hasAny(['phone', 'scrolling', 'جوال', 'تصفح', 'تيك توك', 'tiktok', 'gaming'])) return HabitCategory.focus;
    if (hasAny(['sleep', 'نوم', 'سهر', 'bed'])) return HabitCategory.sleep;
    if (hasAny(['money', 'spending', 'صرف', 'مصروف', 'budget', 'save'])) return HabitCategory.money;
    return _didPickCategory ? _category : HabitCategory.custom;
  }

  HabitCategory _canonicalCategory(HabitCategory cat) => switch (cat) {
        HabitCategory.quran || HabitCategory.athkar || HabitCategory.fasting || HabitCategory.sadaqah => HabitCategory.faith,
        HabitCategory.fitness => HabitCategory.health,
        _ => cat,
      };
}

// ─── Progress dots ──────────────────────────────────────────────────────────

class _ProgressDots extends StatelessWidget {
  final int totalSteps;
  final int step;
  const _ProgressDots({required this.totalSteps, required this.step});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final dots = <Widget>[];
    for (var i = 0; i < totalSteps; i++) {
      if (i > 0) dots.add(const SizedBox(width: 6));
      final active = i == step;
      dots.add(AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        width: active ? 20 : 7,
        height: 7,
        decoration: BoxDecoration(
          color: active ? GameColors.gold : gp.border,
          borderRadius: BorderRadius.circular(4),
        ),
      ));
    }
    return Row(mainAxisSize: MainAxisSize.min, children: dots);
  }
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
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                icon!,
                const SizedBox(width: 7),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                  color: selected ? GameColors.gold : gp.textPrimary,
                  height: 1.1,
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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: gp.textPrimary,
                height: 1.1,
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
