import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../../shared/widgets/habit_limit_gate.dart';
import '../catalog/habit_plans.dart';
import '../catalog/islamic_habit_catalog.dart';
import '../notifiers/custom_habits_notifier.dart';

class PlanPickerSheet extends ConsumerStatefulWidget {
  const PlanPickerSheet({super.key});

  @override
  ConsumerState<PlanPickerSheet> createState() => _PlanPickerSheetState();
}

class _PlanPickerSheetState extends ConsumerState<PlanPickerSheet> {
  String? _expandedPlanId;

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final isAr = s.isAr;
    final activeIds = ref.watch(activeCatalogProvider);
    final reminderTime = ref.watch(reminderTimeProvider);

    return Container(
      decoration: BoxDecoration(
        color: gp.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 8),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: gp.border,
                borderRadius: BorderRadius.circular(100),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: GameColors.gold.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.auto_awesome_rounded,
                      color: GameColors.gold, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.choosePlan,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: gp.textPrimary,
                          letterSpacing: -0.3,
                        ),
                      ),
                      Text(
                        s.choosePlanSubtitle,
                        style: TextStyle(fontSize: 12, color: gp.textSec),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.05),

          const SizedBox(height: 16),

          // Plan cards
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.55,
            ),
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shrinkWrap: true,
              itemCount: habitPlans.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final plan = habitPlans[i];
                final isActive = plan.catalogIds.every(activeIds.contains);
                final isExpanded = _expandedPlanId == plan.id;
                return _PlanCard(
                  plan: plan,
                  isActive: isActive,
                  isExpanded: isExpanded,
                  isAr: isAr,
                  activeIds: activeIds,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _expandedPlanId = isExpanded ? null : plan.id;
                    });
                  },
                  onActivate: () {
                    if (isActive) {
                      HapticFeedback.mediumImpact();
                      ref.read(activeCatalogProvider.notifier).deactivatePlan(plan);
                      return;
                    }
                    final newCount =
                        plan.catalogIds.where((id) => !activeIds.contains(id)).length;
                    if (!canAddHabits(ref, additionalCount: newCount)) {
                      showHabitLimitGate(context, ref);
                      return;
                    }
                    HapticFeedback.mediumImpact();
                    ref.read(activeCatalogProvider.notifier).activatePlan(plan);
                  },
                ).animate(delay: (i * 60).ms).fadeIn(duration: 350.ms).slideY(begin: 0.1);
              },
            ),
          ),

          // Reminder row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: _ReminderRow(
              reminderTime: reminderTime,
              isAr: isAr,
              s: s,
              onSet: (time) => ref.read(reminderTimeProvider.notifier).set(time),
              onClear: () => ref.read(reminderTimeProvider.notifier).clear(),
            ),
          ).animate(delay: 300.ms).fadeIn(duration: 300.ms),

          // Bottom padding
          SizedBox(height: 20 + MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}

// ─── Plan Card ────────────────────────────────────────────────────────────────

class _PlanCard extends StatelessWidget {
  final HabitPlan plan;
  final bool isActive;
  final bool isExpanded;
  final bool isAr;
  final Set<String> activeIds;
  final VoidCallback onTap;
  final VoidCallback onActivate;

  const _PlanCard({
    required this.plan,
    required this.isActive,
    required this.isExpanded,
    required this.isAr,
    required this.activeIds,
    required this.onTap,
    required this.onActivate,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final c = plan.color;
    final s = S.of(context);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: gp.surface,
          borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
          border: Border.all(
            color: isActive ? c.withOpacity(0.5) : gp.border,
            width: isActive ? 1.5 : 0.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: icon + name + xp badge + active check
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: c.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Icon(plan.icon, size: 22, color: c),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plan.localName(isAr),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: gp.textPrimary,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        plan.localDesc(isAr),
                        style: TextStyle(
                            fontSize: 12, color: gp.textSec, height: 1.3),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: c.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(
                        '+${plan.totalDailyXp} XP',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: c,
                        ),
                      ),
                    ),
                    if (isActive) ...[
                      const SizedBox(height: 4),
                      Icon(Icons.check_circle_rounded, color: c, size: 18),
                    ],
                  ],
                ),
              ],
            ),

            // Expanded habit list
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: isExpanded
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 14),
                        Container(height: 0.5, color: gp.border),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: plan.habits.map((h) {
                            final habitActive = activeIds.contains(h.id);
                            return _HabitChip(
                              habit: h,
                              isActive: habitActive,
                              planColor: c,
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: onActivate,
                            style: FilledButton.styleFrom(
                              backgroundColor:
                                  isActive ? gp.surfaceHL : c,
                              foregroundColor:
                                  isActive ? c : Colors.white,
                              minimumSize: const Size(double.infinity, 44),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              side: isActive
                                  ? BorderSide(
                                      color: c.withOpacity(0.4), width: 1)
                                  : BorderSide.none,
                            ),
                            child: Text(
                              isActive ? s.deactivatePlan : s.startPlan,
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),

            // Collapse/expand hint
            if (!isExpanded) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  ...plan.habits.take(4).map((h) => Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: c.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Center(
                            child: Icon(h.category.icon, size: 13, color: c),
                          ),
                        ),
                      )),
                  if (plan.habits.length > 4)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Text(
                        '+${plan.habits.length - 4}',
                        style: TextStyle(
                            fontSize: 11,
                            color: gp.textTert,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  const Spacer(),
                  Icon(Icons.expand_more_rounded,
                      size: 18, color: gp.textTert),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HabitChip extends StatelessWidget {
  final IslamicHabitTemplate habit;
  final bool isActive;
  final Color planColor;

  const _HabitChip(
      {required this.habit, required this.isActive, required this.planColor});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isActive
            ? planColor.withOpacity(0.12)
            : gp.surfaceHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isActive ? planColor.withOpacity(0.4) : gp.border,
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(habit.category.icon,
              size: 13, color: isActive ? planColor : gp.textSec),
          const SizedBox(width: 6),
          Text(
            habit.name,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isActive ? planColor : gp.textSec,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '+${habit.xpReward} XP',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: isActive ? planColor : gp.textTert,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Reminder Row ─────────────────────────────────────────────────────────────

class _ReminderRow extends StatelessWidget {
  final TimeOfDay? reminderTime;
  final bool isAr;
  final S s;
  final ValueChanged<TimeOfDay> onSet;
  final VoidCallback onClear;

  const _ReminderRow({
    required this.reminderTime,
    required this.isAr,
    required this.s,
    required this.onSet,
    required this.onClear,
  });

  String _formatTime(TimeOfDay t, BuildContext context) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    final period = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$m $period';
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final hasReminder = reminderTime != null;

    return GestureDetector(
      onTap: () async {
        HapticFeedback.selectionClick();
        if (hasReminder) {
          onClear();
          return;
        }
        final picked = await showTimePicker(
          context: context,
          initialTime: const TimeOfDay(hour: 20, minute: 0),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(alwaysUse24HourFormat: false),
            child: child!,
          ),
        );
        if (picked != null) onSet(picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: gp.surface,
          borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
          border: Border.all(
            color: hasReminder
                ? GameColors.gold.withOpacity(0.4)
                : gp.border,
            width: hasReminder ? 1 : 0.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: (hasReminder ? GameColors.gold : gp.textTert)
                    .withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                hasReminder
                    ? Icons.notifications_active_rounded
                    : Icons.notifications_none_rounded,
                size: 18,
                color: hasReminder ? GameColors.gold : gp.textSec,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.dailyReminder,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: gp.textPrimary,
                    ),
                  ),
                  Text(
                    hasReminder
                        ? _formatTime(reminderTime!, context)
                        : s.tapToSetReminder,
                    style: TextStyle(
                        fontSize: 12,
                        color: hasReminder ? GameColors.gold : gp.textTert),
                  ),
                ],
              ),
            ),
            Icon(
              hasReminder ? Icons.close_rounded : Icons.chevron_right_rounded,
              size: 18,
              color: gp.textTert,
            ),
          ],
        ),
      ),
    );
  }
}
