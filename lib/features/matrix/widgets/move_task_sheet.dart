import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../models/matrix_task.dart';
import '../notifiers/matrix_notifier.dart';
import 'quadrant_card.dart' show ActionRow;

/// "Move this task to…" — the tappable half of a task's move handle.
///
/// Moving a task between quadrants was drag-only. The handle for it was
/// visible on every tile, so people found it and tapped it — and tapping did
/// nothing at all (its onTap was an empty closure that existed purely to stop
/// the touch falling through and completing the task). The gesture that
/// actually worked, press-and-hold-then-drag, was advertised by nothing. If
/// you already knew, it was quick; if you didn't, the matrix looked like four
/// lists you couldn't move anything between.
///
/// So the handle now answers a tap too. Drag still works exactly as it did —
/// this doesn't replace it, it just means the obvious thing is no longer a
/// dead end.
/// Takes no [WidgetRef]: the sheet below is a ConsumerWidget and reads the
/// matrix state itself, so callers that aren't Consumers (the task tile is a
/// plain StatefulWidget) can open it without being converted first.
Future<void> showMoveTaskSheet(
  BuildContext context,
  MatrixTask task,
  void Function(MatrixQuadrant quadrant) onMove,
) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    useSafeArea: true,
    builder: (_) => _MoveTaskSheet(task: task, onMove: onMove),
  );
}

class _MoveTaskSheet extends ConsumerWidget {
  final MatrixTask task;
  final void Function(MatrixQuadrant quadrant) onMove;
  const _MoveTaskSheet({required this.task, required this.onMove});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final isAr = s.isAr;
    final matrixState = ref.watch(matrixProvider);
    // Its current quadrant is left out: "move to where it already is" is not
    // a choice, and offering it would make the sheet look like a picker with
    // one wrong answer in it.
    final others =
        MatrixQuadrant.values.where((q) => q != task.quadrant).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Container(
        decoration: BoxDecoration(
          color: gp.surfaceHigh,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: gp.border, width: 0.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 6),
              child: Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: gp.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.matrixMoveToQuadrant,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: gp.textTert,
                      letterSpacing: isAr ? 0 : 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  // The task's own title, so there's no doubt which one is
                  // about to move — these tiles sit four to a screen and the
                  // handles are small.
                  Text(
                    task.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: gp.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final q in others)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: ActionRow(
                        dotColor: matrixState.colorFor(q),
                        label: matrixState.titleFor(q, isAr),
                        subtitle: q.localSubtitle(isAr),
                        onTap: () {
                          HapticFeedback.selectionClick();
                          Navigator.pop(context);
                          onMove(q);
                        },
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      )
          .animate()
          .slideY(begin: 0.08, duration: 260.ms, curve: Curves.easeOutCubic)
          .fadeIn(duration: 180.ms),
    );
  }
}
