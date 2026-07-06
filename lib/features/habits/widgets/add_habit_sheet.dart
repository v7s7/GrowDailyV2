import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../../shared/widgets/habit_limit_gate.dart';
import '../catalog/islamic_habit_catalog.dart';
import '../models/habit_model.dart';
import '../notifiers/custom_habits_notifier.dart';

class AddHabitSheet extends ConsumerStatefulWidget {
  final IslamicHabitTemplate? existing;
  const AddHabitSheet({super.key, this.existing});

  @override
  ConsumerState<AddHabitSheet> createState() => _AddHabitSheetState();
}

class _AddHabitSheetState extends ConsumerState<AddHabitSheet> {
  final _nameCtrl = TextEditingController();
  final _cueCtrl = TextEditingController();
  final _focus = FocusNode();
  HabitCategory _category = HabitCategory.custom;
  HabitFrequencyType _freqType = HabitFrequencyType.daily;
  int _freqTarget = 1;
  bool _hasName = false;
  bool _didPickCategory = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _nameCtrl.text = existing.name;
      _cueCtrl.text = existing.cueAfter ?? '';
      _category = existing.category;
      _freqType = existing.frequencyType;
      _freqTarget = existing.frequencyTarget;
      _hasName = true;
      _didPickCategory = true;
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
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _cueCtrl.dispose();
    _focus.dispose();
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
    if (existing != null) {
      ref.read(customHabitsProvider.notifier).update(
            id: existing.id,
            name: _nameCtrl.text.trim(),
            category: _category,
            cueAfter: _cueCtrl.text.trim(),
            frequencyType: _freqType,
            frequencyTarget: _freqTarget,
          );
    } else {
      ref.read(customHabitsProvider.notifier).add(
            name: _nameCtrl.text.trim(),
            category: _category,
            cueAfter: _cueCtrl.text.trim(),
            frequencyType: _freqType,
            frequencyTarget: _freqTarget,
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
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 12, 12 + bottom),
      child: Container(
        decoration: BoxDecoration(
          color: gp.surfaceHigh,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: gp.border, width: 0.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 4),
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                      color: gp.border,
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Text(
                _isEditing ? s.editHabit : s.newHabit,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: GameColors.gold,
                  letterSpacing: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 14),
            if (!_isEditing) ...[
              _SmartStarterRail(onPick: _applyStarter),
              const SizedBox(height: 16),
            ],
            // Name field
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _nameCtrl,
                focusNode: _focus,
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: (_) => _submit(),
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: gp.textPrimary,
                    height: 1.4),
                decoration: InputDecoration(
                  hintText: s.habitNameHint,
                  hintStyle: TextStyle(
                      fontSize: 16,
                      color: gp.textTert.withOpacity(0.8)),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            if (_hasName) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _TinyHint(text: _tinyHint(context)),
              ),
            ],
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _cueCtrl,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                style: TextStyle(fontSize: 14, color: gp.textPrimary),
                decoration: InputDecoration(
                  labelText: s.afterWhatRoutine,
                  hintText: s.routineHint,
                  prefixIcon:
                      Icon(Icons.schedule_rounded, size: 18, color: gp.textSec),
                ),
              ),
            ),
            const SizedBox(height: 10),
            _RoutineCueChips(
              selected: _cueCtrl.text.trim(),
              onPick: (cue) {
                HapticFeedback.selectionClick();
                setState(() => _cueCtrl.text = cue);
              },
            ),
            if (_hasName && _cueCtrl.text.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _PlanPreview(
                  cue: _cueCtrl.text.trim(),
                  habit: _nameCtrl.text.trim(),
                ),
              ),
            ],
            const SizedBox(height: 20),
            // Category
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(s.category,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: gp.textTert,
                      letterSpacing: 1.5)),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: HabitCategory.values.map((cat) {
                  final selected = _category == cat;
                  final icon = _iconFor(cat);
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _didPickCategory = true;
                          _category = cat;
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 0),
                        decoration: BoxDecoration(
                          color: selected
                              ? GameColors.gold.withOpacity(0.12)
                              : gp.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: selected
                                ? GameColors.gold.withOpacity(0.5)
                                : gp.border,
                            width: selected ? 1 : 0.5,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(icon,
                                size: 14,
                                color: selected
                                    ? GameColors.gold
                                    : gp.textSec),
                            const SizedBox(width: 6),
                            Text(
                              cat.displayName,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: selected
                                    ? GameColors.gold
                                    : gp.textSec,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 20),
            // Frequency
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(s.frequency,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: gp.textTert,
                      letterSpacing: 1.5)),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  _FreqBtn(
                    label: s.daily,
                    active: _freqType == HabitFrequencyType.daily,
                    onTap: () => setState(() {
                      _freqType = HabitFrequencyType.daily;
                      _freqTarget = 1;
                    }),
                  ),
                  const SizedBox(width: 8),
                  _FreqBtn(
                    label: s.weekly,
                    active: _freqType == HabitFrequencyType.weekly,
                    onTap: () => setState(() {
                      _freqType = HabitFrequencyType.weekly;
                      _freqTarget = 3;
                    }),
                  ),
                  if (_freqType == HabitFrequencyType.weekly) ...
                    [
                      const SizedBox(width: 16),
                      Text(s.times,
                          style: TextStyle(
                              fontSize: 13, color: gp.textSec)),
                      const SizedBox(width: 8),
                      _CountBtn(
                          icon: Icons.remove_rounded,
                          onTap: () {
                            if (_freqTarget > 1)
                              setState(() => _freqTarget--);
                          }),
                      const SizedBox(width: 8),
                      Text('$_freqTarget',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: gp.textPrimary)),
                      const SizedBox(width: 8),
                      _CountBtn(
                          icon: Icons.add_rounded,
                          onTap: () {
                            if (_freqTarget < 7)
                              setState(() => _freqTarget++);
                          }),
                    ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Submit
            Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, _isEditing ? 4 : 24),
              child: FilledButton(
                onPressed: _hasName ? _submit : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(_isEditing ? s.saveChanges : s.createHabit,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0)),
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
        ),
      ).animate()
          .slideY(begin: 0.06, duration: 260.ms, curve: Curves.easeOutCubic)
          .fadeIn(duration: 200.ms),
    );
  }

  String _tinyHint(BuildContext context) {
    final s = S.of(context);
    final name = _nameCtrl.text.trim().toLowerCase();
    if (name.contains('quran') || name.contains('ayat') || name.contains('page')) {
      return s.tinyHintQuran;
    }
    if (name.contains('athkar') || name.contains('dhikr')) {
      return s.tinyHintAthkar;
    }
    if (name.contains('walk') || name.contains('run') || name.contains('gym')) {
      return s.tinyHintFitness;
    }
    if (name.contains('sleep')) {
      return s.tinyHintSleep;
    }
    return s.tinyHintDefault;
  }

  void _applyStarter(_HabitStarter starter) {
    HapticFeedback.selectionClick();
    _nameCtrl.text = starter.name;
    _cueCtrl.text = starter.cueAfter;
    setState(() {
      _category = starter.category;
      _freqType = starter.frequencyType;
      _freqTarget = starter.frequencyTarget;
      _hasName = true;
      _didPickCategory = true;
    });
  }

  HabitCategory _inferCategory(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('quran') || lower.contains('ayah') ||
        lower.contains('ayat') || lower.contains('surah')) {
      return HabitCategory.quran;
    }
    if (lower.contains('athkar') || lower.contains('dhikr') ||
        lower.contains('dua') || lower.contains('prayer')) {
      return HabitCategory.athkar;
    }
    if (lower.contains('fast')) return HabitCategory.fasting;
    if (lower.contains('sadaqah') || lower.contains('charity') ||
        lower.contains('donate')) {
      return HabitCategory.sadaqah;
    }
    if (lower.contains('sleep') || lower.contains('bed')) {
      return HabitCategory.sleep;
    }
    if (lower.contains('walk') || lower.contains('run') ||
        lower.contains('gym') || lower.contains('workout')) {
      return HabitCategory.fitness;
    }
    return _didPickCategory ? _category : HabitCategory.custom;
  }

  IconData _iconFor(HabitCategory cat) => switch (cat) {
        HabitCategory.quran => Icons.menu_book_rounded,
        HabitCategory.athkar => Icons.self_improvement_rounded,
        HabitCategory.fitness => Icons.fitness_center_rounded,
        HabitCategory.fasting => Icons.nightlight_rounded,
        HabitCategory.sadaqah => Icons.favorite_rounded,
        HabitCategory.sleep => Icons.bedtime_rounded,
        HabitCategory.custom => Icons.star_rounded,
      };
}


class _HabitStarter {
  final String name;
  final String cueAfter;
  final HabitCategory category;
  final HabitFrequencyType frequencyType;
  final int frequencyTarget;

  const _HabitStarter({
    required this.name,
    required this.cueAfter,
    required this.category,
    this.frequencyType = HabitFrequencyType.daily,
    this.frequencyTarget = 1,
  });
}

const _starters = [
  _HabitStarter(
    name: 'Read 3 ayat',
    cueAfter: 'Fajr',
    category: HabitCategory.quran,
  ),
  _HabitStarter(
    name: 'Morning Athkar',
    cueAfter: 'Fajr',
    category: HabitCategory.athkar,
  ),
  _HabitStarter(
    name: 'Give small sadaqah',
    cueAfter: 'Jumuah',
    category: HabitCategory.sadaqah,
    frequencyType: HabitFrequencyType.weekly,
    frequencyTarget: 1,
  ),
  _HabitStarter(
    name: 'Walk 10 minutes',
    cueAfter: 'Asr',
    category: HabitCategory.fitness,
  ),
  _HabitStarter(
    name: 'Sleep before 11',
    cueAfter: 'Isha',
    category: HabitCategory.sleep,
  ),
];

class _SmartStarterRail extends StatelessWidget {
  final ValueChanged<_HabitStarter> onPick;
  const _SmartStarterRail({required this.onPick});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            S.of(context).smartStarters,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: gp.textTert,
              letterSpacing: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 36,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            scrollDirection: Axis.horizontal,
            itemBuilder: (context, index) {
              final starter = _starters[index];
              return ActionChip(
                onPressed: () => onPick(starter),
                avatar: Icon(_iconFor(starter.category), size: 16),
                label: Text(starter.name),
              );
            },
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemCount: _starters.length,
          ),
        ),
      ],
    );
  }

  IconData _iconFor(HabitCategory cat) => switch (cat) {
        HabitCategory.quran => Icons.menu_book_rounded,
        HabitCategory.athkar => Icons.self_improvement_rounded,
        HabitCategory.fitness => Icons.fitness_center_rounded,
        HabitCategory.fasting => Icons.nightlight_rounded,
        HabitCategory.sadaqah => Icons.favorite_rounded,
        HabitCategory.sleep => Icons.bedtime_rounded,
        HabitCategory.custom => Icons.star_rounded,
      };
}

class _TinyHint extends StatelessWidget {
  final String text;
  const _TinyHint({required this.text});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: GameColors.success.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: GameColors.success.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome_rounded,
              size: 16, color: GameColors.success),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, color: gp.textSec, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoutineCueChips extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onPick;
  const _RoutineCueChips({required this.selected, required this.onPick});

  static const _cues = ['Fajr', 'Dhuhr', 'Asr', 'Maghrib', 'Isha', 'Before sleep'];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, index) {
          final cue = _cues[index];
          return ChoiceChip(
            selected: selected == cue,
            label: Text(cue),
            onSelected: (_) => onPick(cue),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemCount: _cues.length,
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
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: gp.textPrimary,
        ),
      ),
    );
  }
}

class _FreqBtn extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _FreqBtn(
      {required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? GameColors.gold.withOpacity(0.12)
              : gp.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active
                ? GameColors.gold.withOpacity(0.5)
                : gp.border,
            width: active ? 1 : 0.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight:
                active ? FontWeight.w700 : FontWeight.w500,
            color: active ? GameColors.gold : gp.textSec,
          ),
        ),
      ),
    );
  }
}

class _CountBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CountBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: gp.surface,
          shape: BoxShape.circle,
          border: Border.all(color: gp.border, width: 0.5),
        ),
        child: Icon(icon, size: 14, color: gp.textPrimary),
      ),
    );
  }
}
