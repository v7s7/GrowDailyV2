import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../models/matrix_task.dart';
import '../notifiers/matrix_notifier.dart';

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

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
    final today = _dateOnly(DateTime.now());
    _visibleMonth = DateTime(today.year, today.month);
    _selectedDate = today;
  }

  // Switching months clears the selected day rather than carrying a
  // selection from a month that's no longer on screen — keeps the grid's
  // highlighted day and the list below it from ever disagreeing.
  void _changeMonth(int delta) {
    HapticFeedback.selectionClick();
    setState(() {
      _visibleMonth =
          DateTime(_visibleMonth.year, _visibleMonth.month + delta);
      _selectedDate = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final isAr = s.isAr;
    final locale = Localizations.localeOf(context).languageCode;
    final today = _dateOnly(DateTime.now());

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

    final Map<DateTime, List<MatrixTask>> byDate = {};
    for (final t in doneTasks) {
      final d = _dateOnly(t.completedAt ?? t.createdAt);
      byDate.putIfAbsent(d, () => []).add(t);
    }

    final dayTasks = _selectedDate == null
        ? const <MatrixTask>[]
        : (List<MatrixTask>.from(byDate[_selectedDate!] ?? const [])
          ..sort((a, b) => (b.completedAt ?? b.createdAt)
              .compareTo(a.completedAt ?? a.createdAt)));

    final canGoNext =
        _visibleMonth.isBefore(DateTime(today.year, today.month));

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
          _MonthHeader(
            label: DateFormat('MMMM yyyy', locale).format(_visibleMonth),
            onPrev: () => _changeMonth(-1),
            onNext: canGoNext ? () => _changeMonth(1) : null,
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
                                  borderRadius: BorderRadius.circular(100),
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

class _MonthHeader extends StatelessWidget {
  final String label;
  final VoidCallback onPrev;
  final VoidCallback? onNext;

  const _MonthHeader({
    required this.label,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    // Icon has no built-in RTL-mirroring flag (that's Image/ImageIcon's
    // matchTextDirection) — flip the chevron glyph by hand so "previous"
    // still visually points the right way once Row's own RTL mirroring
    // has already swapped which side of the header this button sits on.
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    Widget chevron(IconData icon, Color color) {
      final glyph = Icon(icon, color: color, size: 22);
      return isRtl ? Transform.flip(flipX: true, child: glyph) : glyph;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: onPrev,
            icon: chevron(Icons.chevron_left_rounded, gp.textSec),
          ),
          Expanded(
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: gp.textPrimary),
              ),
            ),
          ),
          IconButton(
            onPressed: onNext,
            icon: chevron(
              Icons.chevron_right_rounded,
              onNext == null ? gp.textTert.withOpacity(0.3) : gp.textSec,
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
              final isFuture = date.isAfter(today);
              return _DayCell(
                day: dayNum,
                isToday: date == today,
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
            content: Text(s.matrixTaskDeleted),
            action: SnackBarAction(
              label: s.matrixUndo,
              onPressed: () =>
                  ref.read(matrixProvider.notifier).restore(task),
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      },
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
