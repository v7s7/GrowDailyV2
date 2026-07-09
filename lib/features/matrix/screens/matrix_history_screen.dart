import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../models/matrix_task.dart';
import '../notifiers/matrix_notifier.dart';

/// Completed tasks don't just vanish when checked off — they move here.
/// Reached from Matrix's own header (the "Completed" icon + count badge),
/// so finishing something feels like real progress (it leaves the active
/// quadrant, decluttering what's still left to triage) without the record
/// of what got done ever actually being lost. Each row can be restored
/// back to its quadrant or deleted for good.
class MatrixHistoryScreen extends ConsumerWidget {
  const MatrixHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final isAr = s.isAr;
    final tasks = ref.watch(matrixProvider).tasks.where((t) => t.isDone).toList()
      ..sort((a, b) =>
          (b.completedAt ?? b.createdAt).compareTo(a.completedAt ?? a.createdAt));

    return Scaffold(
      backgroundColor: gp.bg,
      appBar: AppBar(
        backgroundColor: gp.bg,
        surfaceTintColor: Colors.transparent,
        title: Text(s.matrixCompletedTitle,
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: gp.textPrimary)),
      ),
      body: tasks.isEmpty
          ? const _EmptyHistory()
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: tasks.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final t = tasks[i];
                return _HistoryRow(task: t, isAr: isAr)
                    .animate(delay: (i * 30).ms)
                    .fadeIn(duration: 250.ms)
                    .slideY(begin: 0.06, curve: Curves.easeOutCubic);
              },
            ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: GameColors.gold.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check_circle_outline_rounded,
                  size: 30, color: GameColors.gold),
            ),
            const SizedBox(height: 16),
            Text(
              s.matrixNoCompletedTasks,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: gp.textPrimary),
            ),
            const SizedBox(height: 6),
            Text(
              s.matrixNoCompletedTasksDesc,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: gp.textSec, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryRow extends ConsumerWidget {
  final MatrixTask task;
  final bool isAr;
  const _HistoryRow({required this.task, required this.isAr});

  Color get _color => switch (task.quadrant) {
        MatrixQuadrant.doFirst => GameColors.error,
        MatrixQuadrant.schedule => GameColors.xpBlue,
        MatrixQuadrant.delegate => GameColors.streakOrange,
        MatrixQuadrant.eliminate => GameColors.textTertiary,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final completedLabel = task.completedAt == null
        ? ''
        : DateFormat('MMM d, h:mm a', locale).format(task.completedAt!);

    return Dismissible(
      key: ValueKey(task.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => ref.read(matrixProvider.notifier).delete(task.id),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: GameColors.error.withOpacity(0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete_outline_rounded,
            color: GameColors.error),
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: gp.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: gp.border, width: 0.5),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration:
                  BoxDecoration(color: _color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: gp.textPrimary,
                      decoration: TextDecoration.lineThrough,
                      decorationColor: gp.textTert,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    completedLabel.isEmpty
                        ? task.quadrant.localLabel(isAr)
                        : '${task.quadrant.localLabel(isAr)} · $completedLabel',
                    style: TextStyle(fontSize: 11, color: gp.textTert),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            TextButton(
              onPressed: () {
                HapticFeedback.selectionClick();
                ref.read(matrixProvider.notifier).toggle(task.id);
              },
              child: Text(s.matrixRestoreTask),
            ),
          ],
        ),
      ),
    );
  }
}
