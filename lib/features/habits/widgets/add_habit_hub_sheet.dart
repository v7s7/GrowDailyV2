import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../../shared/widgets/habit_limit_gate.dart';
import '../notifiers/custom_habits_notifier.dart';
import 'add_habit_sheet.dart';
import 'plan_picker_sheet.dart';

enum HubTab { plans, addGoal }

/// Single entry point for creating a habit: one sheet split into Plan /
/// Add Goal tabs, so a new user isn't asked to guess which button does
/// what before they've seen either. [initialTab] lets a specific CTA (e.g.
/// "Browse Plans") land on the tab it promised instead of always opening
/// cold on Add Goal.
void showAddHabitHub(
  BuildContext context,
  WidgetRef ref, {
  HubTab initialTab = HubTab.addGoal,
}) {
  if (!canAddHabits(ref)) {
    showHabitLimitGate(context, ref);
    return;
  }
  HapticFeedback.lightImpact();
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    useSafeArea: true,
    builder: (_) => AddHabitHub(initialTab: initialTab),
  );
}

class AddHabitHub extends StatefulWidget {
  final HubTab initialTab;
  const AddHabitHub({super.key, this.initialTab = HubTab.addGoal});

  @override
  State<AddHabitHub> createState() => _AddHabitHubState();
}

class _AddHabitHubState extends State<AddHabitHub> {
  late HubTab _tab = widget.initialTab;

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;
    // Chrome above the tab body: drag handle + title row + tab row + spacing.
    const chromeHeight = 150.0;
    const minBodyHeight = 220.0;
    // Resting size (no keyboard) stays ~86% of the screen, same as before.
    // Once the keyboard opens, shrink to whatever room is left above it
    // instead, so the sheet — and the focused field inside it — never end
    // up pushed off the top of the screen or hidden behind the keyboard.
    final availableHeight = bottom > 0
        ? screenHeight - bottom - chromeHeight - 16
        : screenHeight * 0.86 - chromeHeight;
    final bodyHeight = availableHeight < minBodyHeight ? minBodyHeight : availableHeight;
    const keyboardAnim = Duration(milliseconds: 220);
    const keyboardCurve = Curves.easeOutCubic;

    return AnimatedPadding(
      duration: keyboardAnim,
      curve: keyboardCurve,
      padding: EdgeInsets.only(bottom: bottom),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      s.hubTitle,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: gp.textPrimary,
                      ),
                    ),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => Navigator.pop(context),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(Icons.close_rounded, size: 20, color: gp.textSec),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  _TabPill(
                    label: s.plansTab,
                    selected: _tab == HubTab.plans,
                    onTap: () => setState(() => _tab = HubTab.plans),
                  ),
                  const SizedBox(width: 8),
                  _TabPill(
                    label: s.addGoalTitle,
                    selected: _tab == HubTab.addGoal,
                    onTap: () => setState(() => _tab = HubTab.addGoal),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            AnimatedContainer(
              duration: keyboardAnim,
              curve: keyboardCurve,
              height: bodyHeight,
              child: IndexedStack(
                index: _tab.index,
                children: const [
                  PlanPickerSheet(embedded: true),
                  AddHabitSheet(embedded: true),
                ],
              ),
            ),
          ],
        ),
      ).animate().slideY(begin: 0.06, duration: 260.ms, curve: Curves.easeOutCubic).fadeIn(duration: 200.ms),
    );
  }
}

// ─── Tab pill ───────────────────────────────────────────────────────────────

class _TabPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TabPill({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? GameColors.gold.withOpacity(0.14) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? GameColors.gold : gp.border,
              width: selected ? 1.1 : 0.8,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              color: selected ? GameColors.gold : gp.textSec,
            ),
          ),
        ),
      ),
    );
  }
}
