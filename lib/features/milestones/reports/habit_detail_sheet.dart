import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/datetime_ext.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../../core/utils/western_digits.dart';
import '../../../shared/widgets/history_demo_gate.dart';
import '../../dashboard/notifiers/dashboard_notifier.dart';
import '../../grid/models/square_state.dart';
import '../../grid/notifiers/weekly_grid_notifier.dart' show weeklyGridProvider;
import '../../habits/catalog/islamic_habit_catalog.dart'
    show IslamicHabitTemplate;
import '../../habits/models/habit_model.dart' show GoalType;
import '../../premium/notifiers/premium_notifier.dart';
import '../notifiers/habit_history_notifier.dart';
import 'habit_day_marks.dart';
import 'report_period.dart';
import 'report_sections.dart';
import 'year_strip.dart';

/// One habit's own page: its calendar, its year, and the four numbers that
/// actually answer why someone opened it.
///
/// ── Where this lives, and why it is a sheet ────────────────────────────
/// Reached by tapping a habit's NAME anywhere it already appears: the weekly
/// matrix rows, the monthly cards, the yearly strips. That is the whole
/// discoverability story, and it needs no new destination: by the time
/// someone wants one habit's detail they are already looking at that habit's
/// name, and tapping the thing you are asking about is the shortest possible
/// path to an answer.
///
/// A sheet rather than a pushed screen because this is a detour, not a
/// place. You open it, you look, you are back where you were. A pushed
/// screen would put the report behind a back button for the sake of one
/// glance.
///
/// ── Why four numbers ───────────────────────────────────────────────────
/// The obvious model for this screen shows eight: Volume, Total Volume,
/// Daily Average, Overall Rate, and four more. "Daily Avg. 0.02" is not a
/// fact anybody can use, and a streak measured in weeks is a riddle. What is
/// here instead is the total, this month's rate, the current streak and the
/// best one, because those are the questions people open a habit to ask.
///
/// Every number comes from data already in memory: DashboardState's per-habit
/// streak and total maps, and habitYearHistoryProvider's marks. Opening this
/// costs no reads.
Future<void> showHabitDetailSheet(
  BuildContext context,
  IslamicHabitTemplate habit,
) {
  HapticFeedback.selectionClick();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    // See add_habit_hub_sheet's showAddHabitHub for why every sheet in this
    // app sets this: without it the bottom edge renders flush with the
    // literal screen edge instead of clearing the home indicator.
    useSafeArea: true,
    builder: (_) => _HabitDetailSheet(habit: habit),
  );
}

class _HabitDetailSheet extends ConsumerStatefulWidget {
  final IslamicHabitTemplate habit;
  const _HabitDetailSheet({required this.habit});

  @override
  ConsumerState<_HabitDetailSheet> createState() => _HabitDetailSheetState();
}

class _HabitDetailSheetState extends ConsumerState<_HabitDetailSheet> {
  late DateTime _month;

  /// The day the caption under the calendar is currently describing, or null
  /// before anything has been tapped.
  DateTime? _picked;

  @override
  void initState() {
    super.initState();
    // effectiveDay, not the raw calendar: the app's day rolls at 6am, so
    // between midnight and then the current month is still the previous
    // one as far as anything the user just recorded is concerned.
    final today = DateTime.now().effectiveDay;
    _month = DateTime(today.year, today.month);
  }

  /// Steps the calendar a month, refusing with the shared demo sheet rather
  /// than moving when the target month sits outside the free window.
  ///
  /// This sheet shows the same days the reports hub shows, so it has to
  /// refuse the same way: without this check a free account reached every
  /// month it had ever recorded, one back-tap at a time, from the أسبوعي
  /// tab that is deliberately ungated - while the شهري tab beside it
  /// refused anything older than [kFreeHistoryMonths]. Same data, two
  /// prices, and the cheaper one was a tap away.
  ///
  /// Only the backward step is checked. Forward can never leave the free
  /// window (it is bounded by today), and running the predicate on it would
  /// raise the sheet while walking back TOWARD the present.
  void _stepMonth(int delta) {
    final next = DateTime(_month.year, _month.month + delta);
    if (delta < 0 &&
        !canBrowseHistoryMonth(
          monthStart: next,
          now: DateTime.now().effectiveDay,
          isPremium: ref.read(premiumProvider),
        )) {
      // The sheet brings its own haptic, so none is fired here.
      showHistoryDemoGate(context);
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {
      _month = next;
      _picked = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final habit = widget.habit;
    final color = habit.customColor ?? GameColors.emerald;
    final dash = ref.watch(dashboardProvider);
    final today = DateTime.now().effectiveDay;

    // Same live-today overlay the reports use. Without it this sheet reads the
    // raw mirror and can contradict the very day sheet it was opened from,
    // which is the same split the overlay exists to end.
    final grid = ref.watch(weeklyGridProvider);
    final marks = withLiveToday(
          mirrored: {
            habit.id:
                ref.watch(habitYearHistoryProvider).valueOrNull?[habit.id] ??
                    const <String, SquareState>{},
          },
          habitIds: [habit.id],
          squareToday: (id) => grid.squareFor(id, today),
          completionsToday: (id) => dash.completions[id] ?? 0,
          todayKey: today.toDateKey(),
          gridKnowsToday: !grid.isLoading && grid.isCurrentWeek,
        )[habit.id] ??
        const <String, SquareState>{};

    final isPremium = ref.watch(premiumProvider);

    // The earliest day THIS habit recorded anything. Bounds how far back the
    // stepper may walk, for exactly the reason the reports hub bounds its
    // own (see the earliestKey block in period_report_section.dart): without
    // a floor the back chevron marches into blank pre-account months
    // forever, and nothing on screen says the record has ended.
    //
    // Deliberately the DATA floor and never the premium one. A live arrow
    // that answers with the demo sheet sells the upgrade; an arrow killed by
    // the paywall just reads as broken. So a free account keeps a live
    // chevron all the way back to its first recorded day, and every press
    // past the free window raises the sheet instead of moving.
    String? earliestKey;
    for (final key in marks.keys) {
      if (earliestKey == null || key.compareTo(earliestKey) < 0) {
        earliestKey = key;
      }
    }
    final earliestData =
        earliestKey == null ? null : DateTime.tryParse(earliestKey);
    final canGoBack = earliestData != null && _month.isAfter(earliestData);

    // The free-history floor for the year strip below, from the same shared
    // definition the reports hub draws (see [historyFloorFor], which also
    // documents why this is null for a year that sits entirely inside the
    // free window rather than a floor that would mute nothing).
    final stripLockedBefore = historyFloorFor(
      windowStart: DateTime(_month.year),
      today: today,
      isPremium: isPremium,
    );

    // This month, measured the same way every other report measures: against
    // what the habit actually owed, with rest days excused.
    final monthDays = elapsedDaysIn(
      start: _month,
      end: DateTime(_month.year, _month.month + 1, 0),
      today: today,
    );
    final stat = computeHabitPeriodStats(
      habits: [habit],
      history: {habit.id: marks},
      days: monthDays,
    ).firstOrNull;

    final total = dash.habitTotalCompletions[habit.id] ?? marks.length;
    final streak = dash.habitStreakCounts[habit.id] ?? 0;
    final best = dash.habitLongestStreaks[habit.id] ?? 0;

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: gp.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(GameSpacing.cardRadius),
          ),
          border: Border.all(color: gp.border, width: 0.5),
        ),
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: gp.textTert.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 9),
                if (habit.goalType == GoalType.quit) ...[
                  Icon(Icons.front_hand_rounded, size: 14, color: color),
                  const SizedBox(width: 5),
                ],
                Expanded(
                  child: Text(
                    habit.localName(s.isAr),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: gp.textPrimary,
                    ),
                  ),
                ),
                if (habit.archivedAt != null)
                  Icon(Icons.inventory_2_outlined,
                      size: 16, color: gp.textTert),
              ],
            ),
            const SizedBox(height: 18),
            _Headline(total: total, color: color, isQuit: habit.goalType == GoalType.quit),
            const SizedBox(height: 14),
            Container(height: 0.5, color: gp.divider),
            const SizedBox(height: 14),
            Row(
              children: [
                _Stat(
                  value: stat == null ? '–' : '${(stat.rate * 100).round()}%',
                  label: s.habitStatsThisPeriod,
                  color: GameColors.emerald,
                ),
                _Stat(
                  value: toWesternDigits('$streak'),
                  label: s.habitStatsCurrentStreak,
                  color: GameColors.iconStreak,
                ),
                _Stat(
                  value: toWesternDigits('$best'),
                  label: s.habitStatsBestStreak,
                  color: GameColors.gold,
                ),
              ],
            ),
            const SizedBox(height: 22),
            _MonthHeader(
              month: _month,
              locale: locale,
              canGoBack: canGoBack,
              canGoForward: DateTime(_month.year, _month.month)
                  .isBefore(DateTime(today.year, today.month)),
              onBack: () => _stepMonth(-1),
              onForward: () => _stepMonth(1),
            ),
            const SizedBox(height: 10),
            _MonthCalendar(
              month: _month,
              stat: stat,
              habit: habit,
              color: color,
              today: today,
              picked: _picked,
              locale: locale,
              onPick: (day) {
                HapticFeedback.selectionClick();
                setState(() => _picked = day);
              },
            ),
            const SizedBox(height: 12),
            _DayCaption(
              picked: _picked,
              marks: marks,
              locale: locale,
            ),
            const SizedBox(height: 24),
            Text(
              toWesternDigits('${_month.year}'),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: gp.textSec,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final height = constraints.maxWidth / 7.6;
                return GestureDetector(
                  // A tap on a muted day answers with the demo sheet, the
                  // same way the hub's own year rows do. Null when nothing
                  // is muted, so an unlocked strip stays inert rather than
                  // swallowing taps.
                  onTapUp: stripLockedBefore == null
                      ? null
                      : (details) {
                          final dx =
                              (details.localPosition.dx / constraints.maxWidth)
                                  .clamp(0.0, 1.0);
                          final row = (details.localPosition.dy / (height / 7))
                              .floor()
                              .clamp(0, 6);
                          final day = yearStripDayAt(
                            year: _month.year,
                            dxFraction: dx,
                            row: row,
                            isRtl: isRtl,
                          );
                          if (day.year == _month.year &&
                              day.isBefore(stripLockedBefore)) {
                            showHistoryDemoGate(context);
                          }
                        },
                  child: CustomPaint(
                    size: Size(constraints.maxWidth, height),
                    painter: YearStripPainter(
                      year: _month.year,
                      doneDays: {
                        for (final entry in marks.entries)
                          if (markIsDone(entry.value)) entry.key,
                      },
                      color: color,
                      // The REAL calendar day for the ring, matching every
                      // other strip in the app: this is a calendar, and
                      // before 6am the ring belongs on the date the phone's
                      // own calendar shows.
                      today: DateTime.now(),
                      isRtl: isRtl,
                      lockedBefore: stripLockedBefore,
                      emptyColor: gp.dark
                          ? Colors.white.withOpacity(0.06)
                          : Colors.black.withOpacity(0.06),
                      lockedColor: gp.dark
                          ? Colors.white.withOpacity(0.03)
                          : Colors.black.withOpacity(0.03),
                      // Quieter than locked: see YearStripPainter.futureColor.
                      futureColor: gp.dark
                          ? Colors.white.withOpacity(0.015)
                          : Colors.black.withOpacity(0.015),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// The one big number: how many days this habit has ever been done.
class _Headline extends StatelessWidget {
  final int total;
  final Color color;
  final bool isQuit;

  const _Headline({
    required this.total,
    required this.color,
    required this.isQuit,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: total.toDouble()),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutCubic,
          builder: (context, value, _) => Text(
            toWesternDigits('${value.round()}'),
            style: TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w900,
              color: gp.textPrimary,
              letterSpacing: -1.5,
              height: 1,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          // A quit habit counts days kept clean, not days performed, and the
          // year strip already marks those rows differently. Saying the same
          // thing in words costs nothing and stops the number reading as
          // "you did the thing you are trying to stop doing".
          isQuit ? s.yearRecordCleanDaysCount(total) : s.yearRecordDaysCount(total),
          style: TextStyle(fontSize: 13, color: gp.textSec),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  final Color color;

  const _Stat({required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Expanded(
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w900,
                color: color,
                height: 1.1,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10.5, color: gp.textTert),
          ),
        ],
      ),
    );
  }
}

class _MonthHeader extends StatelessWidget {
  final DateTime month;
  final String locale;

  /// Whether anything was ever recorded before the month on screen. False
  /// kills the back chevron; the premium floor never does (see the
  /// earliestData block in the sheet's build).
  final bool canGoBack;
  final bool canGoForward;
  final VoidCallback onBack;
  final VoidCallback onForward;

  const _MonthHeader({
    required this.month,
    required this.locale,
    required this.canGoBack,
    required this.canGoForward,
    required this.onBack,
    required this.onForward,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Row(
      children: [
        IconButton(
          onPressed: canGoBack ? onBack : null,
          icon: const Icon(Icons.chevron_left_rounded),
          iconSize: 22,
          color: gp.textSec,
          disabledColor: gp.textTert.withOpacity(0.3),
          visualDensity: VisualDensity.compact,
        ),
        Expanded(
          child: Text(
            westernDate(month, 'MMMM yyyy', locale),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: gp.textPrimary,
            ),
          ),
        ),
        IconButton(
          onPressed: canGoForward ? onForward : null,
          icon: const Icon(Icons.chevron_right_rounded),
          iconSize: 22,
          color: gp.textSec,
          disabledColor: gp.textTert.withOpacity(0.3),
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}

/// A full-width month, big enough to actually tap.
///
/// The same [cellStateFor] the reports grids use, so a day cannot read as a
/// rest here and a miss there. Larger cells than the two-column month cards
/// because this sheet is about ONE habit and has the whole width to spend.
class _MonthCalendar extends StatelessWidget {
  final DateTime month;
  final HabitPeriodStat? stat;
  final IslamicHabitTemplate habit;
  final Color color;
  final DateTime today;
  final DateTime? picked;
  final String locale;
  final ValueChanged<DateTime> onPick;

  const _MonthCalendar({
    required this.month,
    required this.stat,
    required this.habit,
    required this.color,
    required this.today,
    required this.picked,
    required this.locale,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final cells = monthGridCells(month);
    final todayDay = DateTime(today.year, today.month, today.day);
    // A stat is absent only when the habit owed nothing and recorded nothing
    // that month. Every day then resolves as not due, which is the truth.
    final resolved = stat;

    return Column(
      children: [
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Center(
                  child: Text(
                    // The first week of cells is always a whole week, so its
                    // days name the columns without any weekday arithmetic.
                    westernDate(
                      cells.take(7).whereType<DateTime>().isEmpty
                          ? month
                          : _columnSample(cells, i, month),
                      'EEEEE',
                      locale,
                    ),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: gp.textTert,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        for (var row = 0; row * 7 < cells.length; row++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                for (var col = 0; col < 7; col++)
                  Expanded(
                    child: _DayCell(
                      day: cells[row * 7 + col],
                      state: () {
                        final day = cells[row * 7 + col];
                        if (day == null) return MatrixCellState.notDue;
                        if (resolved == null) return MatrixCellState.notDue;
                        return cellStateFor(
                          stat: resolved,
                          day: day,
                          today: todayDay,
                        );
                      }(),
                      color: color,
                      today: todayDay,
                      isPicked: picked != null &&
                          cells[row * 7 + col] != null &&
                          cells[row * 7 + col]!.isSameDayAs(picked!),
                      onTap: onPick,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  /// A real date sitting in column [i], purely so intl can name the weekday.
  static DateTime _columnSample(List<DateTime?> cells, int i, DateTime month) {
    for (var row = 0; row * 7 + i < cells.length; row++) {
      final day = cells[row * 7 + i];
      if (day != null) return day;
    }
    return month;
  }
}

class _DayCell extends StatelessWidget {
  final DateTime? day;
  final MatrixCellState state;
  final Color color;
  final DateTime today;
  final bool isPicked;
  final ValueChanged<DateTime> onTap;

  const _DayCell({
    required this.day,
    required this.state,
    required this.color,
    required this.today,
    required this.isPicked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final d = day;
    if (d == null) return const AspectRatio(aspectRatio: 1);

    final Color fill;
    final Color text;
    Color? border;
    switch (state) {
      case MatrixCellState.done:
      case MatrixCellState.bonus:
        fill = color;
        text = Colors.black.withOpacity(0.72);
      case MatrixCellState.partial:
        // Half the done colour, matching the half day it is worth.
        fill = color.withOpacity(0.5);
        text = gp.textPrimary;
      case MatrixCellState.failed:
        fill = GameColors.warning.withOpacity(0.14);
        border = GameColors.warning.withOpacity(0.7);
        text = GameColors.warning;
      case MatrixCellState.rest:
        fill = GameColors.gold.withOpacity(0.16);
        text = GameColors.gold.withOpacity(0.9);
      case MatrixCellState.missed:
        fill = gp.dark
            ? Colors.white.withOpacity(0.075)
            : Colors.black.withOpacity(0.075);
        text = gp.textTert;
      case MatrixCellState.notDue:
      case MatrixCellState.future:
        fill = gp.dark
            ? Colors.white.withOpacity(0.04)
            : Colors.black.withOpacity(0.04);
        text = gp.textTert.withOpacity(0.55);
    }

    return GestureDetector(
      onTap: state == MatrixCellState.future ? null : () => onTap(d),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: AspectRatio(
          aspectRatio: 1,
          child: AnimatedContainer(
            duration: GameMotion.relaxed,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(8),
              border: isPicked
                  ? Border.all(color: GameColors.gold, width: 1.6)
                  : d.isSameDayAs(today)
                      ? Border.all(color: GameColors.gold)
                      : border == null
                          ? null
                          : Border.all(color: border),
            ),
            child: Center(
              child: Text(
                toWesternDigits('${d.day}'),
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: state == MatrixCellState.done ||
                          state == MatrixCellState.bonus
                      ? FontWeight.w800
                      : FontWeight.w500,
                  color: text,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One line under the calendar, naming what the tapped day recorded.
///
/// This is the whole of the drill-down. Opening another sheet on top of this
/// one to say six words would make a light thing heavy.
class _DayCaption extends StatelessWidget {
  final DateTime? picked;
  final Map<String, SquareState> marks;
  final String locale;

  const _DayCaption({
    required this.picked,
    required this.marks,
    required this.locale,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final day = picked;
    final text = day == null
        ? s.habitStatsDayHint
        : s.habitStatsDayLine(
            westernDate(day, 'EEEE d MMMM', locale),
            (marks[day.toDateKey()] ?? SquareState.none).localLabel(s.isAr),
          );
    return AnimatedSwitcher(
      duration: GameMotion.relaxed,
      child: Text(
        text,
        key: ValueKey(text),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          fontWeight: day == null ? FontWeight.w400 : FontWeight.w600,
          color: day == null ? gp.textTert : gp.textSec,
        ),
      ),
    );
  }
}
