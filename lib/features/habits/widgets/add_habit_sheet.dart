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
  // Frequency/cue/limit start collapsed behind "Customize timing" for a new
  // goal — a name and category are enough to save, nothing else has to be
  // decided first. Editing starts expanded instead, since there's already
  // something specific worth reviewing.
  bool _customizeExpanded = false;
  // Where the confetti burst on submit fires from — see _submit().
  final GlobalKey _createButtonKey = GlobalKey();

  bool get _isEditing => widget.existing != null;

  int get _categoryXp => GameConstants.categoryXpRewards[_category.name] ?? 10;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _nameCtrl.text = existing.name;
      _cueCtrl.text = existing.cueAfter ?? '';
      _cueRelation = _startsWithBefore(_cueCtrl.text)
          ? _CueRelation.before
          : _CueRelation.after;
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
      _customizeExpanded = true;
    }
    _nameCtrl.addListener(() {
      final text = _nameCtrl.text.trim();
      final has = text.isNotEmpty;
      final inferred = _inferCategory(text);
      if (has != _hasName || (!_didPickCategory && inferred != _category)) {
        setState(() {
          _hasName = has;
          if (!_didPickCategory) _category = inferred;
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
    if (existing == null) {
      final box =
          _createButtonKey.currentContext?.findRenderObject() as RenderBox?;
      if (box != null && box.attached) {
        showVictoryBurst(context, box.localToGlobal(box.size.center(Offset.zero)));
      }
    }
    final cue = HabitCue.fromStoredValue(_cueWithRelation(_cueCtrl.text)).toStorageValue();
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
    final maxHeight = MediaQuery.of(context).size.height * 0.92;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: bottom),
      child: ConstrainedBox(
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

  bool get _canSubmit => _hasName;

  /// Header + form + footer button — everything except the drag handle and
  /// outer card, so [embedded] mode can drop straight into a host that
  /// already supplies those (see [AddHabitHub]). One screen, not a wizard:
  /// name and category are all that's required to save; frequency, cue,
  /// and (quit-only) limit live inside [_customizeSection], collapsed by
  /// default so deciding all of it up front is optional, not mandatory.
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _goalTypeToggle(s)
                    .animate()
                    .fadeIn(duration: 280.ms)
                    .slideY(begin: 0.06, curve: Curves.easeOutCubic),
                const SizedBox(height: 16),
                _nameAndCategorySection(s)
                    .animate(delay: 60.ms)
                    .fadeIn(duration: 280.ms)
                    .slideY(begin: 0.06, curve: Curves.easeOutCubic),
                const SizedBox(height: 16),
                _customizeSection(s)
                    .animate(delay: 120.ms)
                    .fadeIn(duration: 280.ms)
                    .slideY(begin: 0.06, curve: Curves.easeOutCubic),
                // Only once there's a name to actually preview — pops in
                // fresh the moment typing crosses that line.
                if (_hasName) ...[
                  const SizedBox(height: 16),
                  _goalPreviewCard(s)
                      .animate()
                      .fadeIn(duration: 220.ms)
                      .slideY(begin: 0.08, curve: Curves.easeOutCubic),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(20, 10, 20, _isEditing ? 4 : 20),
          child: FilledButton(
            key: _createButtonKey,
            onPressed: _canSubmit ? _submit : null,
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(_isEditing ? s.saveChanges : s.createGoal),
          ).animate(delay: 60.ms).fadeIn(duration: 250.ms),
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

  Widget _goalTypeToggle(S s) => Row(
        children: [
          Expanded(
            child: _SmallPick(
              label: s.buildHabitTitle,
              selected: _goalType == GoalType.build,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _goalType = GoalType.build);
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
                setState(() => _goalType = GoalType.quit);
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
              if (_hasName) _submit();
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

  /// Frequency, cue, and (quit-only) limit, tucked behind one tap. Shows a
  /// one-line summary of the current settings while collapsed, so what
  /// you'd get by just saving now is never a mystery.
  Widget _customizeSection(S s) {
    final gp = context.gp;
    return Container(
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: gp.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _customizeExpanded = !_customizeExpanded);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.tune_rounded, size: 17, color: gp.textSec),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.customizeTiming,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: gp.textPrimary,
                          ),
                        ),
                        if (!_customizeExpanded) ...[
                          const SizedBox(height: 1),
                          Text(
                            _summary(s),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11.5, color: gp.textTert),
                          ),
                        ],
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: _customizeExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.expand_more_rounded, size: 20, color: gp.textTert),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _customizeExpanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    child: _timingFields(s),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  String _summary(S s) {
    final freq = _selectedWeekdays.isNotEmpty || _freqType == HabitFrequencyType.weekly
        ? s.habitWeeklyTimes(_freqTarget)
        : s.daily;
    final cue = _cueCtrl.text.trim();
    return cue.isEmpty ? freq : '$freq · $cue';
  }

  /// A running "here's what you're about to create" confirmation — icon,
  /// name, frequency, and the XP it'll pay out, so the reward is visible
  /// before you commit, not just after. When there's a cue on a build goal,
  /// the full "After Fajr, I will Read Quran" implementation-intention
  /// sentence — the actual behavior-science reason the cue field exists —
  /// appears below it too, exactly as it used to on its own card.
  Widget _goalPreviewCard(S s) {
    final gp = context.gp;
    final color = _goalType == GoalType.build ? GameColors.gold : GameColors.xpBlue;
    final cueText = _cueCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    final showPlanSentence = _goalType == GoalType.build && cueText.isNotEmpty;
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

  Widget _timingFields(S s) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_goalType == GoalType.quit) ...[
            _SectionLabel(s.goalStyle),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _SmallPick(label: s.avoidCompletely, selected: _reductionType == ReductionType.avoid, onTap: () => setState(() => _reductionType = ReductionType.avoid))),
                const SizedBox(width: 8),
                Expanded(child: _SmallPick(label: s.setLimit, selected: _reductionType == ReductionType.limit, onTap: () => setState(() => _reductionType = ReductionType.limit))),
              ],
            ),
            if (_reductionType == ReductionType.limit) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: TextField(controller: _limitCtrl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: s.maxAmount))),
                  const SizedBox(width: 10),
                  Expanded(child: DropdownButtonFormField<LimitUnit>(value: _limitUnit, items: LimitUnit.values.map((u) => DropdownMenuItem(value: u, child: Text(s.limitUnitLabel(u.name)))).toList(), onChanged: (v) => setState(() => _limitUnit = v ?? LimitUnit.minutes))),
                ],
              ),
            ],
            const SizedBox(height: 18),
            _SectionLabel(s.whenHardest),
          ] else
            _SectionLabel(s.whenQuestion),
          const SizedBox(height: 8),
          Row(
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
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final cue in _cueSuggestions())
                _PlainChoiceChip(
                  selected: _baseCue(_cueCtrl.text) == cue.labelFor(context),
                  label: cue.labelFor(context),
                  onTap: () => _applyCue(cue.labelFor(context)),
                ),
              _PlainActionChip(label: s.customTime, onTap: _pickCustomTime),
              _PlainActionChip(
                label: s.customText,
                onTap: () {
                  HapticFeedback.selectionClick();
                  _cueFocus.requestFocus();
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _cueCtrl,
            focusNode: _cueFocus,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: _goalType == GoalType.build ? s.afterWhatRoutine : s.customTriggerOptional,
              hintText: s.routineHint,
              prefixIcon: const Icon(Icons.schedule_rounded, size: 18),
            ),
          ),
          const SizedBox(height: 18),
          _SectionLabel(s.repeat),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _SmallPick(
                  label: s.daily,
                  selected: _freqType == HabitFrequencyType.daily,
                  onTap: () => setState(() {
                    _freqType = HabitFrequencyType.daily;
                    _freqTarget = 1;
                    _selectedWeekdays.clear();
                  }),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SmallPick(
                  label: s.weekly,
                  selected: _freqType == HabitFrequencyType.weekly && _selectedWeekdays.isEmpty,
                  onTap: () => setState(() {
                    _freqType = HabitFrequencyType.weekly;
                    _freqTarget = 3;
                    _selectedWeekdays.clear();
                  }),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SmallPick(
                  label: s.specificDays,
                  selected: _selectedWeekdays.isNotEmpty,
                  onTap: () => setState(() {
                    _freqType = HabitFrequencyType.weekly;
                    if (_selectedWeekdays.isEmpty) {
                      _selectedWeekdays.add(DateTime.now().weekday);
                    }
                    _freqTarget = _selectedWeekdays.length;
                  }),
                ),
              ),
            ],
          ),
          if (_selectedWeekdays.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final day in _weekdays(context))
                  _PlainChoiceChip(
                    selected: _selectedWeekdays.contains(day.$1),
                    label: day.$2,
                    onTap: () => setState(() {
                      if (!_selectedWeekdays.remove(day.$1)) {
                        _selectedWeekdays.add(day.$1);
                      }
                      if (_selectedWeekdays.isEmpty) {
                        _selectedWeekdays.add(day.$1);
                      }
                      _freqType = HabitFrequencyType.weekly;
                      _freqTarget = _selectedWeekdays.length;
                    }),
                  ),
              ],
            ),
          ],
        ],
      );

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

  void _applyCue(String label) {
    HapticFeedback.selectionClick();
    setState(() => _cueCtrl.text = _cueWithRelation(label));
  }

  void _setCueRelation(_CueRelation relation) {
    HapticFeedback.selectionClick();
    setState(() {
      _cueRelation = relation;
      if (_cueCtrl.text.trim().isNotEmpty) {
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

  Future<void> _pickCustomTime() async {
    HapticFeedback.selectionClick();
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      helpText: S.of(context).pickATime,
    );
    if (picked == null) return;
    setState(() {
      _cueCtrl.text = _cueWithRelation(
        HabitCue.time(picked.hour, picked.minute).labelFor(context),
      );
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

  List<HabitCue> _cueSuggestions() {
    if (_goalType == GoalType.quit) {
      return [
        HabitCue.preset('morning'),
        HabitCue.preset('afternoon'),
        HabitCue.preset('evening'),
        HabitCue.preset('before_sleep'),
      ];
    }
    return switch (_category) {
      HabitCategory.faith => [HabitCue.preset('fajr'), HabitCue.preset('maghrib'), HabitCue.preset('before_sleep')],
      HabitCategory.health => [HabitCue.preset('morning'), HabitCue.preset('after_work_school'), HabitCue.preset('evening')],
      HabitCategory.learning => [HabitCue.preset('morning'), HabitCue.preset('after_school_work'), HabitCue.preset('evening')],
      HabitCategory.sleep => [HabitCue.preset('before_sleep'), HabitCue.time(22, 0), HabitCue.time(23, 0)],
      HabitCategory.focus => [HabitCue.preset('morning'), HabitCue.preset('work_block'), HabitCue.preset('evening')],
      _ => [HabitCue.preset('morning'), HabitCue.preset('evening'), HabitCue.preset('before_sleep')],
    };
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
    );
  }
}

class _PlainActionChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  // Set on suggestion chips only — a small reward preview to make tapping
  // one feel like claiming a shortcut, not just filling in a text field.
  // Left null for plain action chips (custom time/text) that aren't tied
  // to any specific reward.
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
    );
  }
}

