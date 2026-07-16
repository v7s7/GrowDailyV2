import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/extensions/datetime_ext.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../grid/notifiers/weekly_grid_notifier.dart' show startOfGridWeek;
import '../../matrix/notifiers/matrix_notifier.dart';
import '../notifiers/night_review_history_notifier.dart';

/// A month calendar of past mood/reflection check-ins, color-coded by mood —
/// the same "browse an interactive calendar, tap a day to reopen that
/// entry" pattern Day One, Daylio, and Moodistory all converge on for this
/// exact job. Read-only: this is for looking back, not editing a past day
/// (NightReviewScreen itself stays today-only, unchanged).
class NightReviewHistoryScreen extends ConsumerWidget {
  const NightReviewHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final state = ref.watch(nightReviewHistoryProvider);
    final locale = Localizations.localeOf(context).languageCode;
    final monthLabel = DateFormat.yMMMM(locale).format(state.monthStart);

    return Scaffold(
      backgroundColor: gp.bg,
      appBar: AppBar(title: Text(s.nightReviewHistoryTitle)),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  _NavArrow(
                    icon: Icons.chevron_left_rounded,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      ref.read(nightReviewHistoryProvider.notifier).previousMonth();
                    },
                  ),
                  Expanded(
                    child: Center(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: Text(
                          monthLabel,
                          key: ValueKey(monthLabel),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: gp.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  _NavArrow(
                    icon: Icons.chevron_right_rounded,
                    enabled: state.canGoForward,
                    onTap: state.canGoForward
                        ? () {
                            HapticFeedback.selectionClick();
                            ref.read(nightReviewHistoryProvider.notifier).nextMonth();
                          }
                        : null,
                  ),
                ],
              ),
            ),
            Expanded(
              child: state.isLoading
                  ? Center(
                      child: CircularProgressIndicator(
                          color: GameColors.gold, strokeWidth: 2))
                  : SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _WeekdayHeaderRow(),
                          const SizedBox(height: 6),
                          _MonthGrid(
                            monthStart: state.monthStart,
                            entries: state.entries,
                            onTapDay: (day, entry) =>
                                _showDayDetail(context, ref, day, entry),
                          ).animate().fadeIn(duration: 300.ms),
                          if (state.entries.isEmpty) ...[
                            const SizedBox(height: 40),
                            Center(
                              child: Text(
                                s.nightReviewHistoryEmpty,
                                style:
                                    TextStyle(fontSize: 13, color: gp.textTert),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDayDetail(BuildContext context, WidgetRef ref, DateTime day,
      NightReviewDayEntry entry) {
    HapticFeedback.selectionClick();
    // Counted here (not stored on the entry) because Matrix tasks live in
    // their own collection, already fully loaded by matrixProvider — same
    // completedAt-by-effectiveDay grouping MatrixHistoryScreen uses, so
    // the two screens can never disagree about which day a task belongs
    // to. Read once at tap time: the sheet is a static snapshot anyway.
    final tasksDone = ref
        .read(matrixProvider)
        .tasks
        .where((t) =>
            t.isDone &&
            t.completedAt != null &&
            t.completedAt!.effectiveDay.isSameDayAs(day))
        .length;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) =>
          _DayDetailSheet(day: day, entry: entry, tasksDone: tasksDone),
    );
  }
}

// ─── Month nav arrow ─────────────────────────────────────────────────────────

class _NavArrow extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool enabled;
  const _NavArrow({required this.icon, this.onTap, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Opacity(
      opacity: enabled ? 1 : 0.3,
      child: Material(
        color: gp.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: gp.border, width: 0.5),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(icon, color: gp.textSec, size: 20),
          ),
        ),
      ),
    );
  }
}

// ─── Weekday header row ────────────────────────────────────────────────────

/// Sat → Fri, matching the Victory Grid's own week convention
/// (startOfGridWeek) so this calendar's rhythm never disagrees with the
/// rest of the app.
class _WeekdayHeaderRow extends StatelessWidget {
  const _WeekdayHeaderRow();

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final locale = Localizations.localeOf(context).languageCode;
    // Any real Saturday works as a labeling anchor — reusing today's own
    // grid week start (guaranteed to be a Saturday) instead of a hardcoded
    // date keeps this in lockstep with startOfGridWeek's own convention.
    final saturday = startOfGridWeek(DateTime.now());
    return Row(
      children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Center(
              child: Text(
                DateFormat.E(locale)
                    .format(saturday.add(Duration(days: i)))
                    .substring(0, 1),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: gp.textTert,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ─── Month grid ────────────────────────────────────────────────────────────

class _MonthGrid extends StatelessWidget {
  final DateTime monthStart;
  final Map<String, NightReviewDayEntry> entries;
  final void Function(DateTime day, NightReviewDayEntry entry) onTapDay;

  const _MonthGrid({
    required this.monthStart,
    required this.entries,
    required this.onTapDay,
  });

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateTime(monthStart.year, monthStart.month + 1, 0).day;
    // How many blank leading cells before day 1, so day 1 lands under its
    // real weekday column instead of always starting at the grid's edge —
    // reuses startOfGridWeek rather than re-deriving the Sat-first offset
    // by hand, so this can never quietly disagree with the Victory Grid's
    // own week convention.
    final leading = monthStart.difference(startOfGridWeek(monthStart)).inDays;
    final today = DateTime.now().effectiveDay;

    final cells = <Widget>[
      for (var i = 0; i < leading; i++) const SizedBox.shrink(),
      for (var d = 1; d <= daysInMonth; d++)
        _dayCell(DateTime(monthStart.year, monthStart.month, d), today),
    ];

    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
      children: cells,
    );
  }

  Widget _dayCell(DateTime day, DateTime today) {
    final entry = entries[day.toDateKey()];
    return _DayCell(
      day: day,
      entry: entry,
      // Same exemption as the Grid's own _SquareCell.isFuture: the real
      // calendar day during the 3-hour window right after midnight isn't
      // "future" just because effectiveDay (`today` here) hasn't caught up
      // to it yet — see DateTimeGameExt.isRealToday.
      isFuture: day.isAfter(today) && !day.isRealToday,
      // hasAnything, not hasEntry: a day with real activity (habits done,
      // squares colored) but no saved mood/reflection still deserves to
      // open — its numbers ARE the review for that day.
      onTap: (entry != null && entry.hasAnything)
          ? () => onTapDay(day, entry)
          : null,
    );
  }
}

class _DayCell extends StatelessWidget {
  final DateTime day;
  final NightReviewDayEntry? entry;
  final bool isFuture;
  final VoidCallback? onTap;

  const _DayCell({
    required this.day,
    required this.entry,
    required this.isFuture,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final mood = entry?.mood;
    final color = mood?.visual.$2;
    return AspectRatio(
      aspectRatio: 1,
      child: Opacity(
        opacity: isFuture ? 0.3 : 1,
        child: Material(
          color: color?.withOpacity(gp.dark ? 0.22 : 0.16) ?? gp.surface,
          borderRadius: BorderRadius.circular(9),
          child: InkWell(
            borderRadius: BorderRadius.circular(9),
            onTap: onTap,
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                // isRealToday, not isToday: purely the "today" marker — see
                // DateTimeGameExt.isRealToday's doc comment.
                border: Border.all(
                  color: day.isRealToday ? GameColors.gold : gp.border,
                  width: day.isRealToday ? 1.4 : 0.5,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${day.day}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight:
                          day.isRealToday ? FontWeight.w800 : FontWeight.w600,
                      color: day.isRealToday
                          ? GameColors.gold
                          : (color ?? gp.textSec),
                    ),
                  ),
                  if (mood != null) ...[
                    const SizedBox(height: 2),
                    Icon(mood.visual.$1, size: 12, color: color),
                  ] else if (entry?.hasAnything ?? false) ...[
                    // Activity happened but no review was saved — a quiet
                    // emerald dot instead of a mood icon, so the calendar
                    // still shows the day was lived without pretending a
                    // mood was logged.
                    const SizedBox(height: 3),
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: GameColors.emerald.withOpacity(0.8),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One compact stat inside the day-detail sheet's numbers row — the
/// sheet-local sibling of NightReviewScreen's own _SummaryStat, kept
/// separate since that one is private to its screen.
class _SheetStat extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  const _SheetStat({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(height: 5),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: gp.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 9, color: gp.textTert),
          ),
        ],
      ),
    );
  }
}

// ─── Day detail sheet ──────────────────────────────────────────────────────

class _DayDetailSheet extends StatelessWidget {
  final DateTime day;
  final NightReviewDayEntry entry;

  /// Matrix tasks completed that day — counted by the caller from
  /// matrixProvider (see _showDayDetail), since tasks don't live in the
  /// daily docs the entry itself was parsed from.
  final int tasksDone;

  const _DayDetailSheet({
    required this.day,
    required this.entry,
    required this.tasksDone,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final dateLabel = DateFormat('EEEE, MMM d', locale).format(day);
    final mood = entry.mood;

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(10),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: gp.surfaceHigh,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: gp.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              dateLabel,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: gp.textTert,
              ),
            ),
            const SizedBox(height: 10),
            if (mood != null)
              Row(
                children: [
                  Icon(mood.visual.$1, size: 22, color: mood.visual.$2),
                  const SizedBox(width: 8),
                  Text(
                    mood.label(s.isAr),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: gp.textPrimary,
                    ),
                  ),
                ],
              ),
            // The day's actual numbers — what got done, not just how it
            // felt. Same three stats the live Night Review summary leads
            // with, so past and present reviews read the same way.
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: gp.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: gp.border, width: 0.5),
              ),
              child: Row(
                children: [
                  _SheetStat(
                    icon: Icons.check_circle_rounded,
                    color: GameColors.emerald,
                    value: '${entry.habitsDone}',
                    label: s.nightReviewHabitsDoneLabel,
                  ),
                  _SheetStat(
                    icon: Icons.grid_view_rounded,
                    color: GameColors.emerald,
                    value: '${entry.greenSquares}',
                    label: s.nightReviewGreenSquares,
                  ),
                  _SheetStat(
                    icon: Icons.task_alt_rounded,
                    color: GameColors.iconXp,
                    value: '$tasksDone',
                    label: s.nightReviewTasksDoneLabel,
                  ),
                ],
              ),
            ),
            if (entry.reflection.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                entry.reflection,
                style: TextStyle(
                    fontSize: 14, color: gp.textSec, height: 1.5),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
