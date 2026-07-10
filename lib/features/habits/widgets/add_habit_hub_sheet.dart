import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/game_constants.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../../shared/widgets/habit_limit_gate.dart';
import '../catalog/goal_suggestions.dart';
import '../catalog/islamic_habit_catalog.dart';
import '../models/habit_model.dart';
import '../notifiers/custom_habits_notifier.dart';
import 'add_habit_sheet.dart';
import 'plan_picker_sheet.dart';

enum HubTab { quick, plans, custom }

/// Single entry point for creating a habit. Replaces what used to be two
/// separate "+" affordances (the custom wizard and the plan-bundle picker)
/// with one sheet split into Quick Add / Plans / Custom tabs, so a new user
/// isn't asked to guess which button does what before they've seen either.
/// [initialTab] lets a specific CTA (e.g. "Browse Plans") land on the tab
/// it promised instead of always opening cold on Quick Add.
void showAddHabitHub(
  BuildContext context,
  WidgetRef ref, {
  HubTab initialTab = HubTab.quick,
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
  const AddHabitHub({super.key, this.initialTab = HubTab.quick});

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
    // Fixed body height (rather than a maxHeight cap) so the IndexedStack
    // below can give every tab's content a bounded height to lay out
    // against — Quick Add's Wrap of chips and Custom's step content both
    // rely on that the same way the standalone sheets already do via their
    // own ConstrainedBox(maxHeight:).
    final bodyHeight = screenHeight * 0.86 - 150 < 280
        ? 280.0
        : screenHeight * 0.86 - 150;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
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
                    label: s.quickAddTab,
                    selected: _tab == HubTab.quick,
                    onTap: () => setState(() => _tab = HubTab.quick),
                  ),
                  const SizedBox(width: 8),
                  _TabPill(
                    label: s.plansTab,
                    selected: _tab == HubTab.plans,
                    onTap: () => setState(() => _tab = HubTab.plans),
                  ),
                  const SizedBox(width: 8),
                  _TabPill(
                    label: s.customTab,
                    selected: _tab == HubTab.custom,
                    onTap: () => setState(() => _tab = HubTab.custom),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: bodyHeight,
              child: IndexedStack(
                index: _tab.index,
                children: const [
                  _QuickAddTab(),
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

// ─── Tab pill (shared by the hub's own tab row and the Quick Add Build/Quit
// toggle below) ────────────────────────────────────────────────────────────

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

// ─── Quick Add tab ──────────────────────────────────────────────────────────

class _QuickAddTab extends ConsumerStatefulWidget {
  const _QuickAddTab();

  @override
  ConsumerState<_QuickAddTab> createState() => _QuickAddTabState();
}

class _QuickAddTabState extends ConsumerState<_QuickAddTab> {
  GoalType _goalType = GoalType.build;

  void _toggle(GoalSuggestion suggestion, String label, String? existingId) {
    if (existingId != null) {
      HapticFeedback.selectionClick();
      ref.read(customHabitsProvider.notifier).remove(existingId);
      return;
    }
    if (!canAddHabits(ref)) {
      showHabitLimitGate(context, ref);
      return;
    }
    HapticFeedback.mediumImpact();
    ref.read(customHabitsProvider.notifier).add(
          name: label,
          category: suggestion.category,
          frequencyType: HabitFrequencyType.daily,
          frequencyTarget: 1,
          goalType: suggestion.type,
        );
  }

  /// Id of the already-added custom habit matching this suggestion, or
  /// null. Derived from the live provider (not local session state) so a
  /// habit quick-added, then the sheet closed and reopened, still shows as
  /// "Added" instead of letting a second tap create a duplicate.
  String? _idFor(List<IslamicHabitTemplate> custom, GoalSuggestion item, String label) {
    for (final h in custom) {
      if (h.name == label && h.category == item.category && h.goalType == item.type) {
        return h.id;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final isAr = s.isAr;
    final custom = ref.watch(customHabitsProvider);
    final items = goalSuggestions.where((g) => g.type == _goalType).toList();
    final byCategory = <HabitCategory, List<GoalSuggestion>>{};
    for (final item in items) {
      byCategory.putIfAbsent(item.category, () => []).add(item);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            s.quickAddSubtitle,
            style: TextStyle(fontSize: 13, color: gp.textSec),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _TabPill(
                label: s.buildToggle,
                selected: _goalType == GoalType.build,
                onTap: () => setState(() => _goalType = GoalType.build),
              ),
              const SizedBox(width: 8),
              _TabPill(
                label: s.quitToggle,
                selected: _goalType == GoalType.quit,
                onTap: () => setState(() => _goalType = GoalType.quit),
              ),
            ],
          ),
          const SizedBox(height: 18),
          for (final entry in byCategory.entries) ...[
            Text(
              entry.key.localizedName(isAr),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: gp.textTert,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: entry.value.map((item) {
                final label = item.name(isAr);
                final id = _idFor(custom, item, label);
                final xp = GameConstants.categoryXpRewards[item.category.name] ?? 10;
                return _QuickAddChip(
                  label: label,
                  xp: xp,
                  added: id != null,
                  onTap: () => _toggle(item, label, id),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}

class _QuickAddChip extends StatelessWidget {
  final String label;
  final int xp;
  final bool added;
  final VoidCallback onTap;

  const _QuickAddChip({
    required this.label,
    required this.xp,
    required this.added,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final color = added ? GameColors.success : GameColors.gold;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: added ? color.withOpacity(0.14) : gp.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: added ? color : gp.border.withOpacity(0.8),
            width: added ? 1.1 : 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (added) ...[
              Icon(Icons.check_rounded, size: 15, color: color),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: added ? FontWeight.w800 : FontWeight.w700,
                color: added ? color : gp.textPrimary,
                height: 1.1,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '+$xp',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: added ? color.withOpacity(0.8) : gp.textTert,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
