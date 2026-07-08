import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../notifiers/quick_wins_notifier.dart';

/// The compact "Quick Wins" section on Today: one small card, two rows
/// (Today / This week), no icons-in-circles, no description paragraphs, no
/// chart — deliberately far lighter than the Weekly Challenge card it
/// replaces.
class QuickWinsCard extends ConsumerWidget {
  const QuickWinsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final state = ref.watch(quickWinsProvider);
    if (state.isLoading || state.dailyWin == null) {
      return const SizedBox.shrink();
    }
    final weeklyProgress = ref.watch(quickWinWeeklyProgressProvider);
    final weeklyWin = state.weeklyWin;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        border: Border.all(color: gp.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.quickWins,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: gp.textSec,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          _QuickWinRow(
            label: s.quickWinToday,
            title: state.dailyWin!.title(s.isAr),
            done: state.dailyDone,
            actionLabel: s.quickWinDone,
            canAct: true,
            onComplete: () {
              HapticFeedback.mediumImpact();
              ref.read(quickWinsProvider.notifier).completeDaily();
            },
            onSwap: () {
              HapticFeedback.selectionClick();
              ref.read(quickWinsProvider.notifier).swapDaily();
            },
          ),
          if (weeklyWin != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Divider(height: 1, color: gp.divider),
            ),
            _QuickWinRow(
              label: s.quickWinThisWeek,
              title: weeklyWin.title(s.isAr),
              done: state.weeklyDone,
              progressText: weeklyProgress == null
                  ? null
                  : '${weeklyProgress.$1}/${weeklyProgress.$2}',
              actionLabel: weeklyProgress == null ? s.quickWinDone : s.quickWinClaim,
              canAct: weeklyProgress == null || weeklyProgress.$1 >= weeklyProgress.$2,
              onComplete: () {
                HapticFeedback.mediumImpact();
                ref.read(quickWinsProvider.notifier).completeWeekly();
              },
              onSwap: () {
                HapticFeedback.selectionClick();
                ref.read(quickWinsProvider.notifier).swapWeekly();
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _QuickWinRow extends StatelessWidget {
  final String label;
  final String title;
  final bool done;
  final String? progressText;
  final String actionLabel;
  final bool canAct;
  final VoidCallback onComplete;
  final VoidCallback onSwap;

  const _QuickWinRow({
    required this.label,
    required this.title,
    required this.done,
    this.progressText,
    required this.actionLabel,
    required this.canAct,
    required this.onComplete,
    required this.onSwap,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: gp.textTert,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: done ? gp.textTert : gp.textPrimary,
                  decoration: done ? TextDecoration.lineThrough : TextDecoration.none,
                ),
              ),
              if (progressText != null && !done) ...[
                const SizedBox(height: 2),
                Text(
                  progressText!,
                  style: TextStyle(
                    fontSize: 11,
                    color: GameColors.xpBlue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        if (done)
          const Icon(Icons.check_circle_rounded, color: GameColors.success, size: 20)
        else ...[
          TextButton(
            onPressed: onSwap,
            style: TextButton.styleFrom(
              foregroundColor: gp.textSec,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              S.of(context).quickWinSwap,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 4),
          FilledButton(
            onPressed: canAct ? onComplete : null,
            style: FilledButton.styleFrom(
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            ),
            child: Text(actionLabel),
          ),
        ],
      ],
    );
  }
}
