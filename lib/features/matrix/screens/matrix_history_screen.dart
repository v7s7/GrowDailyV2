import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/extensions/datetime_ext.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../../shared/widgets/calendar_month_scaffold.dart';
import '../../../shared/widgets/safe_wrap_text.dart';
import '../models/matrix_task.dart';
import '../notifiers/matrix_notifier.dart';
import '../../../shared/widgets/history_demo_gate.dart';
import '../../premium/notifiers/premium_notifier.dart';

/// Saturday-start, matching the Victory Grid's own week convention
/// (`startOfGridWeek` in weekly_grid_notifier.dart) so the app doesn't mix
/// two different "first day of the week" conventions.
int _columnFor(DateTime date) => (date.weekday + 1) % 7;

/// Completed tasks don't just vanish when checked off — they move here, and
/// stay here for good until restored or permanently deleted; nothing is
/// ever auto-cleared. A month calendar lets you jump straight to any day and
/// see exactly what got finished then, instead of scrolling one long list.
class MatrixHistoryScreen extends ConsumerStatefulWidget {
  const MatrixHistoryScreen({super.key});

  @override
  ConsumerState<MatrixHistoryScreen> createState() =>
      _MatrixHistoryScreenState();
}

class _MatrixHistoryScreenState extends ConsumerState<MatrixHistoryScreen> {
  late DateTime _visibleMonth;
  DateTime? _selectedDate;

  @override
  void initState() {
    super.initState();
    // Real midnight, matching the board's own day-roll — see
    // _anchorDay's comment in matrix_screen.dart for the tasks-vs-habits
    // split (habits keep the 6 AM flex cutoff; the todo board does not).
    final today = DateTime.now().startOfDay;
    _visibleMonth = DateTime(today.year, today.month);
    _selectedDate = today;
  }

  // Switching months clears the selected day rather than carrying a
  // selection from a month that's no longer on screen — keeps the grid's
  // highlighted day and the list below it from ever disagreeing.
  void _changeMonth(int delta) {
    HapticFeedback.selectionClick();
    final target =
        DateTime(_visibleMonth.year, _visibleMonth.month + delta);
    // Same free window as every other history surface — the heatmap,
    // journal, and night review all gate at kFreeHistoryMonths, and this
    // archive was the one place the "Premium owns its whole history" story
    // quietly wasn't true. Answered with the demo gate, not a refusal,
    // like everywhere else.
    if (delta < 0 &&
        !canBrowseHistoryMonth(
          monthStart: target,
          now: DateTime.now().effectiveDay,
          isPremium: ref.read(premiumProvider),
        )) {
      showHistoryDemoGate(context);
      return;
    }
    setState(() {
      _visibleMonth = target;
      _selectedDate = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final isAr = s.isAr;
    final locale = Localizations.localeOf(context).languageCode;
    final today = DateTime.now().startOfDay;

    final doneTasks =
        ref.watch(matrixProvider).tasks.where((t) => t.isDone).toList();

    if (doneTasks.isEmpty) {
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
        body: const _EmptyHistory(),
      );
    }

    // Real calendar date, matching the board's midnight day-roll — a task
    // finished at 12:40 AM groups under the new day, exactly the day the
    // board itself showed it as "done today" on. (Habits keep the 6 AM
    // flex cutoff; the todo board deliberately does not — see
    // _anchorDay's comment in matrix_screen.dart.)
    final Map<DateTime, List<MatrixTask>> byDate = {};
    for (final t in doneTasks) {
      final d = (t.completedAt ?? t.createdAt).startOfDay;
      byDate.putIfAbsent(d, () => []).add(t);
    }

    final dayTasks = _selectedDate == null
        ? const <MatrixTask>[]
        : (List<MatrixTask>.from(byDate[_selectedDate!] ?? const [])
          ..sort((a, b) => (b.completedAt ?? b.createdAt)
              .compareTo(a.completedAt ?? a.createdAt)));

    final currentMonth = DateTime(today.year, today.month);
    // The archive's own floor. Completed tasks are never auto-cleared, so
    // the oldest completion is exactly how far back there is anything to
    // see; before this the back arrow was a bare non-nullable callback and
    // stepped forever into months that predate the account, each one an
    // empty grid. byDate is non-empty here — the doneTasks.isEmpty branch
    // above has already returned. Clamped to the current month so a
    // future-dated completedAt (clock skew, a bad import) can't push the
    // floor above the ceiling and freeze the screen, the same guard
    // earliestStoryMonth documents.
    final oldest = byDate.keys
        .map((d) => DateTime(d.year, d.month))
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final earliestMonth = oldest.isAfter(currentMonth) ? currentMonth : oldest;
    final canGoBack = _visibleMonth.isAfter(earliestMonth);
    final canGoNext = _visibleMonth.isBefore(currentMonth);

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
      body: Column(
        children: [
          // The shared header, not a fourth private copy of it — Rooms'
          // participant calendar and the Monthly Story already render this
          // exact control, and it gets the RTL arrows right on its own.
          CalendarMonthHeader(
            month: _visibleMonth,
            canGoBack: canGoBack,
            canGoForward: canGoNext,
            onBack: () => _changeMonth(-1),
            onForward: () => _changeMonth(1),
          ),
          _WeekdayHeader(locale: locale),
          const SizedBox(height: 2),
          _MonthGrid(
            month: _visibleMonth,
            today: today,
            selectedDate: _selectedDate,
            completedDates: byDate.keys.toSet(),
            onSelect: (date) {
              HapticFeedback.selectionClick();
              setState(() => _selectedDate = date);
            },
          ),
          const SizedBox(height: 10),
          Divider(height: 1, color: gp.divider, indent: 20, endIndent: 20),
          Expanded(
            child: _selectedDate == null
                ? _SelectDayPrompt(text: s.matrixPickADay)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                        child: Row(
                          children: [
                            Text(
                              _selectedDate == today
                                  ? s.navToday
                                  : DateFormat('EEEE, MMM d', locale)
                                      .format(_selectedDate!),
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: gp.textPrimary),
                            ),
                            if (dayTasks.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: GameColors.gold.withOpacity(0.16),
                                  borderRadius: BorderRadius.circular(
                                      GameSpacing.pillRadius),
                                ),
                                child: Text('${dayTasks.length}',
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: GameColors.gold)),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Expanded(
                        child: dayTasks.isEmpty
                            ? _EmptyDayState(text: s.matrixNoTasksThisDay)
                            : ListView.separated(
                                padding:
                                    const EdgeInsets.fromLTRB(20, 6, 20, 16),
                                itemCount: dayTasks.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 10),
                                itemBuilder: (context, i) {
                                  final t = dayTasks[i];
                                  return _HistoryRow(task: t, isAr: isAr)
                                      .animate(delay: (i * 30).ms)
                                      .fadeIn(duration: 220.ms)
                                      .slideY(
                                          begin: 0.06,
                                          curve: Curves.easeOutCubic);
                                },
                              ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _WeekdayHeader extends StatelessWidget {
  final String locale;
  const _WeekdayHeader({required this.locale});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    // Jan 6 2024 was a Saturday — just a fixed reference week to pull each
    // column's narrow, locale-correct single-letter label from intl, in the
    // same Saturday-start order as the grid below.
    final labels = List.generate(
      7,
      (i) => DateFormat('EEEEE', locale).format(DateTime(2024, 1, 6 + i)),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: labels
            .map((l) => Expanded(
                  child: Center(
                    child: Text(
                      l,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: gp.textTert),
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  final DateTime month;
  final DateTime today;
  final DateTime? selectedDate;
  final Set<DateTime> completedDates;
  final void Function(DateTime date) onSelect;

  const _MonthGrid({
    required this.month,
    required this.today,
    required this.selectedDate,
    required this.completedDates,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final firstOfMonth = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leadingBlanks = _columnFor(firstOfMonth);
    final totalCells = leadingBlanks + daysInMonth;
    final rows = (totalCells / 7).ceil();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: List.generate(rows, (row) {
          return Row(
            children: List.generate(7, (col) {
              final cellIndex = row * 7 + col;
              final dayNum = cellIndex - leadingBlanks + 1;
              if (dayNum < 1 || dayNum > daysInMonth) {
                return const Expanded(child: SizedBox());
              }
              final date = DateTime(month.year, month.month, dayNum);
              // Same exemption as the Grid's own _SquareCell.isFuture: the
              // real calendar day during the 6-hour window right after
              // midnight isn't "future" just because effectiveDay (`today`
              // here) hasn't caught up to it yet — see DateTimeGameExt.
              // isRealToday. This view is read-only (selecting a day just
              // shows its completed tasks, never edits anything), so
              // there's no reward question here at all — purely about not
              // needlessly blocking the tap.
              final isFuture = date.isAfter(today) && !date.isRealToday;
              return _DayCell(
                day: dayNum,
                // isRealToday, not date == today: purely the "today"
                // marker (bold ring) — see DateTimeGameExt.isRealToday's
                // doc comment. `selectedDate`'s own initial seed stays on
                // `today` (effectiveDay) elsewhere, unchanged, since that's
                // about which day's completed-tasks list loads by default,
                // not a visual marker.
                isToday: date.isRealToday,
                isSelected: selectedDate != null && date == selectedDate,
                hasCompleted: completedDates.contains(date),
                isFuture: isFuture,
                onTap: isFuture ? null : () => onSelect(date),
              );
            }),
          );
        }),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  final int day;
  final bool isToday;
  final bool isSelected;
  final bool hasCompleted;
  final bool isFuture;
  final VoidCallback? onTap;

  const _DayCell({
    required this.day,
    required this.isToday,
    required this.isSelected,
    required this.hasCompleted,
    required this.isFuture,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Expanded(
      child: AspectRatio(
        aspectRatio: 1,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Material(
            color: isSelected ? GameColors.gold : Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: isToday && !isSelected
                      ? Border.all(color: GameColors.gold, width: 1.4)
                      : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$day',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected || isToday
                            ? FontWeight.w800
                            : FontWeight.w500,
                        color: isSelected
                            ? Colors.black
                            : isFuture
                                ? gp.textTert.withOpacity(0.35)
                                : gp.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: hasCompleted
                            ? (isSelected ? Colors.black : GameColors.gold)
                            : Colors.transparent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectDayPrompt extends StatelessWidget {
  final String text;
  const _SelectDayPrompt({required this.text});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: gp.textTert, height: 1.4),
        ),
      ),
    );
  }
}

class _EmptyDayState extends StatelessWidget {
  final String text;
  const _EmptyDayState({required this.text});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.nights_stay_rounded,
                size: 26, color: gp.textTert.withOpacity(0.5)),
            const SizedBox(height: 10),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: gp.textTert, height: 1.4),
            ),
          ],
        ),
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    // ConsumerWidget only exposes ref as a build() param (unlike
    // ConsumerState, which keeps it as an instance field), so — unlike
    // AddTaskSheet/TaskDetailSheet's equivalent getters — color/title are
    // resolved here as plain locals instead.
    final matrixState = ref.watch(matrixProvider);
    final color = matrixState.colorFor(task.quadrant);
    final title = matrixState.titleFor(task.quadrant, isAr);
    final locale = Localizations.localeOf(context).languageCode;
    // Just the time-of-day — the date itself is already implied by which
    // calendar day is selected above, so repeating it here would be noise.
    final completedLabel = task.completedAt == null
        ? ''
        : DateFormat('h:mm a', locale).format(task.completedAt!);

    return Dismissible(
      key: ValueKey(task.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) {
        ref.read(matrixProvider.notifier).delete(task.id);
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(s.matrixTaskDeleted(task.title)),
            action: SnackBarAction(
              label: s.matrixUndo,
              onPressed: () => ref.read(matrixProvider.notifier).restore(task),
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      },
      // centerEnd, not centerRight — see quadrant_card_task_tile.dart's
      // dismiss background for the RTL reasoning.
      background: Container(
        alignment: AlignmentDirectional.centerEnd,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: GameColors.error.withOpacity(0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child:
            const Icon(Icons.delete_outline_rounded, color: GameColors.error),
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
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SafeWrapText(
                    task.title,
                    maxLines: 2,
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
                    completedLabel.isEmpty ? title : '$title · $completedLabel',
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
