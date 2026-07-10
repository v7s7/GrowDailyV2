import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../../shared/widgets/category_icon.dart';
import '../../../shared/widgets/habit_limit_gate.dart';
import '../catalog/goal_suggestions.dart';
import '../catalog/islamic_habit_catalog.dart';
import '../models/habit_cue.dart';
import '../models/habit_model.dart';
import '../notifiers/custom_habits_notifier.dart';

enum _CueRelation { after, before }

class AddHabitSheet extends ConsumerStatefulWidget {
  final IslamicHabitTemplate? existing;

  /// When true, renders just the step content + footer — no drag handle,
  /// no rounded card, no background. Used inside [AddHabitHub]'s "Custom"
  /// tab, which already supplies that chrome once for all three tabs.
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
  int _step = 0;
  bool _hasName = false;
  bool _didPickCategory = false;
  bool _cueLabelResolved = false;

  bool get _isEditing => widget.existing != null;

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
      _step = 1;
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

  /// Header row + step content + footer buttons — everything except the
  /// drag handle and outer card, so [embedded] mode can drop straight into
  /// a host that already supplies those (see [AddHabitHub]).
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
                Text(
                  '${_step + 1}/3',
                  style: TextStyle(fontSize: 12, color: gp.textTert),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: _step == 0 && !_isEditing
                  ? _typeStep(s)
                  : _step == 1
                      ? _titleStep(s)
                      : _timingStep(s),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20, 10, 20, _isEditing ? 4 : 20),
            child: Row(
              children: [
                if (_step > (_isEditing ? 1 : 0)) ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() => _step--),
                      child: Text(s.back),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _canContinue ? _primaryAction : null,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      _step < 2
                          ? s.continueAction
                          : (_isEditing ? s.saveChanges : s.createGoal),
                    ),
                  ),
                ),
              ],
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

  bool get _canContinue => _step == 0 || _hasName;

  void _primaryAction() {
    HapticFeedback.selectionClick();
    if (_step < 2) {
      setState(() => _step++);
    } else {
      _submit();
    }
  }

  Widget _typeStep(S s) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _QuestionTitle(s.whatImprove),
          const SizedBox(height: 14),
          _GoalTypeCard(
            title: s.buildHabitTitle,
            subtitle: s.buildHabitSubtitle,
            icon: Icons.add_task_rounded,
            selected: _goalType == GoalType.build,
            onTap: () => setState(() => _goalType = GoalType.build),
          ),
          const SizedBox(height: 12),
          _GoalTypeCard(
            title: s.quitHabitTitle,
            subtitle: s.quitHabitSubtitle,
            icon: Icons.shield_rounded,
            selected: _goalType == GoalType.quit,
            onTap: () => setState(() => _goalType = GoalType.quit),
          ),
        ],
      );

  Widget _titleStep(S s) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _QuestionTitle(_goalType == GoalType.build ? s.whatHabitBuild : s.whatReduce),
          const SizedBox(height: 12),
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
              if (_hasName) setState(() => _step = 2);
            },
            decoration: InputDecoration(
              hintText: s.goalTitleHint,
              prefixIcon: const Icon(Icons.edit_note_rounded, size: 20),
            ),
          ),
          const SizedBox(height: 18),
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
                onTap: () => setState(() {
                  _didPickCategory = true;
                  _category = cat;
                }),
              );
            }).toList(),
          ),
          const SizedBox(height: 18),
          _SectionLabel(s.smartSuggestions),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _suggestions().map((item) {
              return _PlainActionChip(
                label: item.name(s.isAr),
                onTap: () => _applySuggestion(item),
              );
            }).toList(),
          ),
        ],
      );

  Widget _timingStep(S s) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _QuestionTitle(_goalType == GoalType.build ? s.timingBuildTitle : s.timingQuitTitle),
          const SizedBox(height: 14),
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
          if (_goalType == GoalType.build && _hasName && _cueCtrl.text.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            _PlanPreview(cue: _cueCtrl.text.trim(), habit: _nameCtrl.text.trim()),
          ],
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

  const _PlainActionChip({required this.label, required this.onTap});

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
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: gp.textPrimary,
            height: 1.1,
          ),
        ),
      ),
    );
  }
}

class _QuestionTitle extends StatelessWidget {
  final String text;
  const _QuestionTitle(this.text);
  @override
  Widget build(BuildContext context) => Text(text, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: context.gp.textPrimary, height: 1.2));
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.gp.textTert));
}

class _GoalTypeCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _GoalTypeCard({required this.title, required this.subtitle, required this.icon, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? GameColors.gold.withOpacity(0.12) : gp.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? GameColors.gold.withOpacity(0.6) : gp.border),
        ),
        child: Row(children: [
          Icon(icon, color: selected ? GameColors.gold : gp.textSec),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: gp.textPrimary)),
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(fontSize: 13, color: gp.textSec, height: 1.25)),
          ])),
          if (selected) Icon(Icons.check_circle_rounded, color: GameColors.gold),
        ]),
      ),
    );
  }
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

class _PlanPreview extends StatelessWidget {
  final String cue;
  final String habit;
  const _PlanPreview({required this.cue, required this.habit});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: GameColors.xpBlue.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: GameColors.xpBlue.withOpacity(0.18)),
      ),
      child: Text(
        S.of(context).planPreview(cue, habit),
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: gp.textPrimary),
      ),
    );
  }
}
