import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/game_theme.dart';
import '../models/habit_model.dart';
import '../notifiers/custom_habits_notifier.dart';

class AddHabitSheet extends ConsumerStatefulWidget {
  const AddHabitSheet({super.key});

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

  @override
  void initState() {
    super.initState();
    _nameCtrl.addListener(() {
      final has = _nameCtrl.text.trim().isNotEmpty;
      if (has != _hasName) setState(() => _hasName = has);
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
    HapticFeedback.mediumImpact();
    ref.read(customHabitsProvider.notifier).add(
          name: _nameCtrl.text.trim(),
          category: _category,
          cueAfter: _cueCtrl.text.trim(),
          frequencyType: _freqType,
          frequencyTarget: _freqTarget,
        );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
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
                'NEW HABIT',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: GameColors.gold,
                  letterSpacing: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 14),
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
                  hintText: 'What habit do you want to build?',
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
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _cueCtrl,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                style: TextStyle(fontSize: 14, color: gp.textPrimary),
                decoration: InputDecoration(
                  labelText: 'After what routine? (optional)',
                  hintText: 'Fajr, Maghrib, before sleep...',
                  prefixIcon: Icon(Icons.place_rounded, size: 18, color: gp.textSec),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Category
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text('CATEGORY',
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
                        setState(() => _category = cat);
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
              child: Text('FREQUENCY',
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
                    label: 'Daily',
                    active: _freqType == HabitFrequencyType.daily,
                    onTap: () => setState(() {
                      _freqType = HabitFrequencyType.daily;
                      _freqTarget = 1;
                    }),
                  ),
                  const SizedBox(width: 8),
                  _FreqBtn(
                    label: 'Weekly',
                    active: _freqType == HabitFrequencyType.weekly,
                    onTap: () => setState(() {
                      _freqType = HabitFrequencyType.weekly;
                      _freqTarget = 3;
                    }),
                  ),
                  if (_freqType == HabitFrequencyType.weekly) ...
                    [
                      const SizedBox(width: 16),
                      Text('Times:',
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
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: FilledButton(
                onPressed: _hasName ? _submit : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('ADD HABIT',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2)),
              ).animate(delay: 60.ms).fadeIn(duration: 250.ms),
            ),
          ],
        ),
      ).animate()
          .slideY(begin: 0.06, duration: 260.ms, curve: Curves.easeOutCubic)
          .fadeIn(duration: 200.ms),
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
