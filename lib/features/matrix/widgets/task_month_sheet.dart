import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show OrdinalSortKey;
import 'package:flutter/services.dart';

import '../../../core/extensions/datetime_ext.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../../core/utils/western_digits.dart';
import '../../../shared/widgets/calendar_month_scaffold.dart'
    show CalendarMonthHeader;
import '../../grid/notifiers/weekly_grid_notifier.dart' show startOfGridWeek;
import '../../milestones/reports/report_sections.dart' show monthGridCells;
import '../models/matrix_task.dart';
import '../task_day.dart';

/// A task day as the Tasks page names it: «اليوم، 28 سبتمبر» / "Today,
/// 28 Sep" on today, the weekday and date on any other day («الأربعاء، 30
/// سبتمبر» / "Wednesday, Sep 30"), and the year added only when the day is
/// in another year than [now]'s.
///
/// Never a word for tomorrow or yesterday: Aziz asked for dates, and one
/// function naming the day for the page header, the Add sheet's day row and
/// the move sheet's meta line means the three can never disagree about it.
/// Western digits throughout (westernDate / weekdayDateLabel), since
/// DateFormat under 'ar' prints Arabic-Indic ones in the app.
String taskDayTitle(DateTime day, S s, {DateTime? now}) {
  final today = (now ?? DateTime.now()).startOfDay;
  final isAr = s.isAr;
  final locale = isAr ? 'ar' : 'en';
  if (day.isSameDayAs(today)) {
    return s.matrixTodayWithDate(
      westernDate(day, isAr ? 'd MMMM' : 'd MMM', locale),
    );
  }
  final label = weekdayDateLabel(day, isAr: isAr, locale: locale);
  if (day.year == today.year) return label;
  final year = toWesternDigits(day.year.toString());
  return isAr ? '$label $year' : '$label, $year';
}

/// The Tasks page's month: every day's board at a glance, and the way to
/// pick a day for a task.
///
/// Two uses, one sheet. Browsing (the header's date title): tapping a day
/// returns it and the page shows that day's board. Picking ([pickMode], the
/// Add sheet's day row and the move sheet's «نقل ليوم ثاني»): the heading
/// asks «لأي يوم؟», and the days before today are faded and refuse the tap,
/// because a task cannot be planned for a day that has gone.
///
/// Returns the tapped day as a local midnight, today for the «رجوع لليوم»
/// footer, or null when the sheet is dismissed. [selected] is ringed in the
/// accent and decides which month the sheet opens on. [tasks] only feeds
/// the markers (see [dayMarks]); the sheet changes nothing itself.
///
/// Browsing is free for everyone (Aziz): unlike the history screens, no
/// month here is behind Premium, so there is no lock state to draw.
Future<DateTime?> showTaskMonthSheet(
  BuildContext context, {
  required DateTime selected,
  required List<MatrixTask> tasks,
  bool pickMode = false,
}) {
  HapticFeedback.selectionClick();
  return showModalBottomSheet<DateTime>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    // Keeps the card's top clear of the status bar and notch. The bottom
    // inset is the card's own job (see its outer margin): useSafeArea does
    // not clear the gesture bar on Android 15/16.
    useSafeArea: true,
    builder: (_) => TaskMonthSheet(
      selected: selected,
      tasks: tasks,
      pickMode: pickMode,
    ),
  );
}

/// The sheet [showTaskMonthSheet] opens. Public for the tests, which pump
/// it inside their own route; everything else should call the function.
class TaskMonthSheet extends StatefulWidget {
  final DateTime selected;
  final List<MatrixTask> tasks;
  final bool pickMode;

  /// The clock the sheet reads "today" from. Null is the real clock; tests
  /// pass a fixed one so a day's past or future state does not depend on
  /// when the suite runs.
  final DateTime? now;

  const TaskMonthSheet({
    super.key,
    required this.selected,
    required this.tasks,
    this.pickMode = false,
    this.now,
  });

  @override
  State<TaskMonthSheet> createState() => _TaskMonthSheetState();
}

/// The months the sheet can step through, first and last, both on the 1st.
///
/// Back to the month of the oldest task (by the day it was created or the
/// day it belongs to, whichever is older), and never less than three months
/// back, so a new account still has somewhere to look; forward twelve
/// months, far enough for any plan a todo list is for. The [selected] day's
/// month is always inside, however it got there.
///
/// In [pickMode] the floor is the current month instead: every day before
/// today is refused there, so the older months would be pages of faded
/// numbers with nothing to pick. A selected day in an earlier month (a
/// carried-over task being moved) still opens on its own month.
@visibleForTesting
({DateTime first, DateTime last}) taskMonthRange({
  required DateTime selected,
  required Iterable<MatrixTask> tasks,
  required DateTime now,
  bool pickMode = false,
}) {
  final current = DateTime(now.year, now.month);
  final selectedMonth = DateTime(selected.year, selected.month);
  var first = DateTime(now.year, now.month - 3);
  if (pickMode) {
    first = current;
  } else {
    for (final t in tasks) {
      final created = t.createdAt.toLocal();
      final day = taskDay(t);
      final oldest = created.isBefore(day) ? created : day;
      final month = DateTime(oldest.year, oldest.month);
      if (month.isBefore(first)) first = month;
    }
  }
  if (selectedMonth.isBefore(first)) first = selectedMonth;
  var last = DateTime(now.year, now.month + 12);
  if (selectedMonth.isAfter(last)) last = selectedMonth;
  return (first: first, last: last);
}

class _TaskMonthSheetState extends State<TaskMonthSheet> {
  late DateTime _month =
      DateTime(widget.selected.year, widget.selected.month);

  // One pass over the tasks for the whole sheet, not one per cell per
  // build: stepping months re-renders 42 cells, the tasks do not change
  // while the sheet is open.
  late final Map<String, DayMark> _marks = dayMarks(widget.tasks);

  DateTime get _now => widget.now ?? DateTime.now();

  void _step(int by) {
    HapticFeedback.selectionClick();
    setState(() => _month = DateTime(_month.year, _month.month + by));
  }

  void _pick(DateTime day) {
    HapticFeedback.selectionClick();
    Navigator.pop(context, day.startOfDay);
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final now = _now;
    final today = now.startOfDay;
    final media = MediaQuery.of(context);
    final range = taskMonthRange(
      selected: widget.selected,
      tasks: widget.tasks,
      now: now,
      pickMode: widget.pickMode,
    );
    final cells = monthGridCells(_month);
    // Away from today in either sense: another day is selected, or the
    // arrows have walked off the current month. Either way there is a
    // "today" to get back to; on today's own month with today selected
    // the footer would be a button that does nothing.
    final awayFromToday = !widget.selected.isSameDayAs(today) ||
        !_month.isSameMonthAs(today);

    return Padding(
      // The sheet handles its own bottom inset: useSafeArea leaves the
      // gesture bar to it. The keyboard is included because the Add sheet
      // under this one can still be holding it up when the day row is
      // tapped.
      padding: EdgeInsets.fromLTRB(
        12,
        0,
        12,
        12 + media.padding.bottom + media.viewInsets.bottom,
      ),
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
            // The only part that can shrink: on a 568pt phone with a large
            // text size six week rows do not fit, and the grid scrolls
            // rather than painting past the card.
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.pickMode)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 4, 8, 2),
                        child: Text(
                          s.matrixPickDay,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: gp.textPrimary,
                          ),
                        ),
                      ),
                    // Arrows only, no month picker on the title: a year and
                    // a quarter of range is a few taps, and this sheet is
                    // already the picker.
                    CalendarMonthHeader(
                      month: _month,
                      canGoBack: _month.isAfter(range.first),
                      canGoForward: _month.isBefore(range.last),
                      onBack: () => _step(-1),
                      onForward: () => _step(1),
                    ),
                    const SizedBox(height: 4),
                    _WeekdayLetters(month: _month),
                    const SizedBox(height: 4),
                    for (var row = 0; row * 7 < cells.length; row++)
                      Row(
                        // Left to right in Arabic too, Saturday in the left
                        // column: Aziz's ruling for every month calendar in
                        // the app (see HeatmapMonthSection and the report's
                        // HabitMonthCard). A month is a number line, and its
                        // Western digits read left to right.
                        textDirection: TextDirection.ltr,
                        children: [
                          for (var col = 0; col < 7; col++)
                            Expanded(
                              child: _DayCell(
                                day: cells[row * 7 + col],
                                today: today,
                                selected: widget.selected,
                                mark: () {
                                  final day = cells[row * 7 + col];
                                  if (day == null) return DayMark.none;
                                  return _marks[dayKey(day)] ?? DayMark.none;
                                }(),
                                pickMode: widget.pickMode,
                                onTap: _pick,
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            if (awayFromToday)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Center(
                  child: TextButton(
                    onPressed: () => _pick(today),
                    style: TextButton.styleFrom(
                      foregroundColor: gp.goldInk,
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    child: Text(
                      s.matrixBackToToday,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: gp.goldInk,
                      ),
                    ),
                  ),
                ),
              )
            else
              const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}

/// The seven column letters, Saturday first and left to right in both
/// languages, over the same columns as their days (see the grid rows).
/// Named from real dates in the week [monthGridCells] anchors on, so the
/// letters move with the grid if the week start ever does.
class _WeekdayLetters extends StatelessWidget {
  final DateTime month;
  const _WeekdayLetters({required this.month});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final locale = S.of(context).isAr ? 'ar' : 'en';
    final start = startOfGridWeek(DateTime(month.year, month.month));
    return ExcludeSemantics(
      child: Row(
        textDirection: TextDirection.ltr,
        children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Center(
                child: Text(
                  // 'EEEEE' (narrow): every Arabic short weekday name starts
                  // with ا, so a first-letter cut printed seven identical
                  // letters (see CalendarWeekdayHeaderRow).
                  westernDate(
                    DateTime(start.year, start.month, start.day + i),
                    'EEEEE',
                    locale,
                  ),
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: gp.textTert,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One day of the month: a 44pt row slot holding a 38pt circle, the number,
/// and the day's marker under it.
///
/// The marker is a shape as well as a colour, so it reads without colour:
/// a dot when something is still open that day, a tick when the day had
/// tasks and every one is done, nothing on an empty day. The slot under the
/// number is kept on every day, marker or not, so the numbers sit on one
/// line across the week instead of hopping where a marker is drawn.
class _DayCell extends StatelessWidget {
  final DateTime? day;
  final DateTime today;
  final DateTime selected;
  final DayMark mark;
  final bool pickMode;
  final ValueChanged<DateTime> onTap;

  const _DayCell({
    required this.day,
    required this.today,
    required this.selected,
    required this.mark,
    required this.pickMode,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final d = day;
    if (d == null) return const SizedBox(height: 44);
    final gp = context.gp;
    final s = S.of(context);
    final isSelected = d.isSameDayAs(selected);
    final isToday = d.isSameDayAs(today);
    final isPast = d.isBefore(today);
    final enabled = !(pickMode && isPast);

    // The accent as a fill, with its own black-or-white ink on top; the
    // accent as a ring or a number goes through goldEdge / goldInk, which
    // stay readable on the cream light-mode surface where the raw accent
    // does not.
    final Color numberColor;
    if (isSelected) {
      numberColor = GameColors.onGold;
    } else if (isToday) {
      numberColor = gp.goldInk;
    } else if (isPast) {
      numberColor = gp.textSec;
    } else {
      numberColor = gp.textPrimary;
    }

    final Widget marker = switch (mark) {
      DayMark.none => const SizedBox.shrink(),
      DayMark.open => Container(
          width: 4,
          height: 4,
          decoration: BoxDecoration(
            color: isSelected ? GameColors.onGold : gp.goldEdge,
            shape: BoxShape.circle,
          ),
        ),
      DayMark.allDone => Icon(
          Icons.check_rounded,
          size: 9,
          color: isSelected ? GameColors.onGold : gp.emeraldInk,
        ),
    };

    final locale = s.isAr ? 'ar' : 'en';
    final date = weekdayDateLabel(d, isAr: s.isAr, locale: locale);
    final year = toWesternDigits(d.year.toString());
    final state = switch (mark) {
      DayMark.none => null,
      DayMark.open => s.matrixDayHasTasks,
      DayMark.allDone => s.matrixDayAllDone,
    };
    final sep = s.isAr ? '، ' : ', ';
    final label = state == null ? '$date $year' : '$date $year$sep$state';

    Widget cell = SizedBox(
      height: 44,
      child: Center(
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: isSelected ? GameColors.gold : null,
            shape: BoxShape.circle,
            border: !isSelected && isToday
                ? Border.all(color: gp.goldEdge, width: 1.4)
                : null,
          ),
          // Scaled down rather than overflowed at the largest text sizes:
          // the circle is a fixed 38pt so the week keeps its columns, and a
          // two-digit number with its marker slot outgrows it past about
          // 1.6x text.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  toWesternDigits('${d.day}'),
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.15,
                    fontWeight:
                        isSelected ? FontWeight.w800 : FontWeight.w700,
                    color: numberColor,
                  ),
                ),
                const SizedBox(height: 1),
                SizedBox(height: 9, child: Center(child: marker)),
              ],
            ),
          ),
        ),
      ),
    );
    if (!enabled) cell = Opacity(opacity: 0.35, child: cell);

    return Semantics(
      container: true,
      button: true,
      selected: isSelected,
      enabled: enabled,
      label: label,
      // Read in date order. The row is laid out left to right in Arabic
      // too, but a screen reader orders a row by the page's direction, so
      // without a key it read each week from Friday back to Saturday and
      // then jumped about ten days ahead at the row break. The cells are
      // one unbroken run of siblings, so the keys order only them: the
      // month header before them and the footer after keep their places.
      sortKey: OrdinalSortKey(d.day.toDouble()),
      excludeSemantics: true,
      onTap: enabled ? () => onTap(d) : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => onTap(d) : null,
        child: cell,
      ),
    );
  }
}

/// The 48pt row both task sheets use to reach the month: the Add sheet's
/// day row ([trailing] expand_more, the day as [label]) and the move
/// sheet's «نقل ليوم ثاني» ([trailing] a forward chevron). One widget so the
/// two read as the same control.
///
/// Grows with the text size instead of clipping (a minimum height, not a
/// fixed one). [semanticsLabel] replaces what a screen reader would
/// otherwise piece together from the icon and the text.
class TaskSheetRowButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final IconData trailing;
  final String? semanticsLabel;
  final VoidCallback onTap;

  const TaskSheetRowButton({
    super.key,
    required this.icon,
    required this.label,
    required this.trailing,
    required this.onTap,
    this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Semantics(
      button: true,
      label: semanticsLabel ?? label,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: gp.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: gp.border, width: 0.5),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  Icon(icon, size: 18, color: gp.textSec),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: gp.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(trailing, size: 18, color: gp.textSec),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
