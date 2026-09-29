import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/extensions/datetime_ext.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../../core/utils/western_digits.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../models/matrix_task.dart';
import '../notifiers/matrix_notifier.dart';
import '../task_day.dart';
import 'quadrant_card.dart' show ActionRow;
import 'reminder_picker.dart' show pickReminderTimeOnDay;
import 'task_month_sheet.dart'
    show TaskSheetRowButton, showTaskMonthSheet, taskDayTitle;

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
///
/// It also moves a task in TIME: «نقل ليوم ثاني» under the quadrants opens
/// the month and moves the task to the day picked (MatrixNotifier.
/// moveToDay), then says where it went with an Undo. The sheet does that
/// itself, through the notifier, so the tile opening it needs no new
/// plumbing.
///
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
    // Scroll-controlled so the card sizes itself (up to 0.85 of the screen)
    // and its body scrolls: with the day line and the day row added, the
    // default half-screen cap overflowed a 568pt phone.
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _MoveTaskSheet(task: task, onMove: onMove),
  );
}

class _MoveTaskSheet extends ConsumerWidget {
  final MatrixTask task;
  final void Function(MatrixQuadrant quadrant) onMove;
  const _MoveTaskSheet({required this.task, required this.onMove});

  /// «الأربعاء، 30 سبتمبر · 4:30 م»: the day the task is on now, and its
  /// time when it has one, so the move below starts from a known place.
  static String _dayLine(MatrixTask task, S s) {
    final day = taskDayTitle(taskDay(task), s);
    final anchor =
        MatrixTask.resolveAnchor(task.reminderAnchorAt, task.reminderAts);
    if (anchor == null) return day;
    final time = westernDate(anchor.toLocal(), 'h:mm a', s.isAr ? 'ar' : 'en');
    return '$day · $time';
  }

  /// «نقل ليوم ثاني»: the month in pick mode, then the move.
  ///
  /// A timed task keeps its clock time on the new day. When that time has
  /// already gone there (moving a 9:00 task to today at noon) moveToDay
  /// refuses rather than store a past moment, and the answer is to ask for
  /// a time on today's wheel, floored at the next minute, and move with it.
  ///
  /// Everything the Undo needs is captured before the move and the notifier
  /// is read before any await: the Undo runs from the snackbar after this
  /// sheet is gone, when neither its context nor its ref may be used.
  Future<void> _moveToAnotherDay(
    BuildContext context,
    WidgetRef ref,
    MatrixTask current,
  ) async {
    final notifier = ref.read(matrixProvider.notifier);
    final from = taskDay(current);
    final picked = await showTaskMonthSheet(
      context,
      selected: from,
      tasks: ref.read(matrixProvider).tasks,
      pickMode: true,
    );
    if (picked == null || !context.mounted) return;
    if (picked.isSameDayAs(from)) return;

    final previousReminders = current.reminderAts;
    final previousAnchor = current.reminderAnchorAt;
    final previousPlannedDay = current.plannedDay;

    var moved = notifier.moveToDay(current.id, picked);
    if (!moved) {
      final at = await pickReminderTimeOnDay(
        context,
        day: picked,
        initial:
            MatrixTask.resolveAnchor(previousAnchor, previousReminders),
      );
      if (at == null || !context.mounted) return;
      moved = notifier.moveToDay(
        current.id,
        picked,
        time: TimeOfDay.fromDateTime(at),
      );
      if (!moved) return;
    }

    HapticFeedback.selectionClick();
    final s = S.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final locale = s.isAr ? 'ar' : 'en';
    final message = picked.isSameDayAs(DateTime.now())
        ? s.matrixMovedToToday
        : s.matrixMovedToDay(
            weekdayDateLabel(picked, isAr: s.isAr, locale: locale),
          );
    Navigator.pop(context);
    // The root messenger, so the bar outlives this sheet and shows over the
    // board the task just left.
    messenger.showOne(
      SnackBar(
        content: Text(message),
        // Never pin the bar open. See AppSnackBar.
        persist: false,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: s.matrixUndo,
          onPressed: () => notifier.restoreSchedule(
            current.id,
            reminderAts: previousReminders,
            anchor: previousAnchor,
            plannedDay: previousPlannedDay,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final isAr = s.isAr;
    final matrixState = ref.watch(matrixProvider);
    // The live copy, so the day line follows a change made while the sheet
    // is open (a sync from another device); the one handed in otherwise.
    final current = matrixState.tasks.firstWhere(
      (t) => t.id == task.id,
      orElse: () => task,
    );
    // Its current quadrant is left out: "move to where it already is" is not
    // a choice, and offering it would make the sheet look like a picker with
    // one wrong answer in it.
    final others =
        MatrixQuadrant.values.where((q) => q != current.quadrant).toList();
    final media = MediaQuery.of(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 12, 12 + media.padding.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.85),
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
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
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
                    // about to move: these tiles sit four to a screen and the
                    // handles are small.
                    Text(
                      current.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: gp.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _dayLine(current, s),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: gp.textSec,
                      ),
                    ),
                    const SizedBox(height: 6),
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
                    // A done task stays where it was finished: its board is
                    // history, and moveToDay refuses it anyway.
                    if (!current.isDone) ...[
                      const SizedBox(height: 14),
                      Divider(height: 0.5, thickness: 0.5, color: gp.divider),
                      const SizedBox(height: 14),
                      TaskSheetRowButton(
                        icon: Icons.calendar_today_rounded,
                        label: s.matrixMoveToAnotherDay,
                        // chevron_right mirrors under RTL, so it points
                        // forward in either reading direction.
                        trailing: Icons.chevron_right_rounded,
                        onTap: () => _moveToAnotherDay(context, ref, current),
                      ),
                    ],
                  ],
                ),
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
