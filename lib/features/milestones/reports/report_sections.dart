import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/extensions/datetime_ext.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../../core/utils/western_digits.dart';
import '../../grid/models/square_state.dart';
import '../../grid/notifiers/weekly_grid_notifier.dart' show startOfGridWeek;
import '../../habits/models/habit_model.dart' show GoalType;
import 'report_period.dart';

/// The ‹ label › stepper every tab of the reports hub carries.
///
/// A sibling of [CalendarMonthHeader] rather than a use of it: that one
/// formats a DateTime as a month itself, which is exactly right for the
/// screens that only ever step months, and exactly wrong here where the
/// same control has to say "15 - 21 أغسطس", "أغسطس 2026" and "2026" on
/// three consecutive taps. The label is computed by the caller (which knows
/// the scope) and passed in already formatted.
class ReportPeriodHeader extends StatelessWidget {
  final String label;
  final bool canGoBack;
  final bool canGoForward;
  final VoidCallback onBack;
  final VoidCallback onForward;

  /// Makes the label itself open a picker. Same reasoning as
  /// [CalendarMonthHeader.onTapMonth]: without it, reaching last January is
  /// eleven taps on an arrow that never says how far back it will go.
  final VoidCallback? onTapLabel;

  const ReportPeriodHeader({
    super.key,
    required this.label,
    required this.canGoBack,
    required this.canGoForward,
    required this.onBack,
    required this.onForward,
    this.onTapLabel,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final title = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: gp.textPrimary,
            ),
          ),
        ),
        if (onTapLabel != null) ...[
          const SizedBox(width: 4),
          Icon(Icons.expand_more_rounded, size: 18, color: gp.textSec),
        ],
      ],
    );
    return Row(
      children: [
        IconButton(
          onPressed: canGoBack
              ? () {
                  HapticFeedback.selectionClick();
                  onBack();
                }
              : null,
          tooltip: MaterialLocalizations.of(context).previousMonthTooltip,
          icon: const Icon(Icons.chevron_left_rounded),
          iconSize: 22,
          color: gp.textSec,
          disabledColor: gp.textTert.withOpacity(0.3),
          visualDensity: VisualDensity.compact,
        ),
        Expanded(
          child: onTapLabel == null
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: title,
                )
              : InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onTapLabel!();
                  },
                  borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: title,
                  ),
                ),
        ),
        IconButton(
          onPressed: canGoForward
              ? () {
                  HapticFeedback.selectionClick();
                  onForward();
                }
              : null,
          tooltip: MaterialLocalizations.of(context).nextMonthTooltip,
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

/// The one card at the top of every tab: what the period came to, and the
/// three numbers that qualify it.
///
/// Deliberately ONE card and not two. The first cut had a headline card
/// ("40 مربعًا أخضر") sitting directly above a four-cell summary row whose
/// third cell was "المجموع 40", so the same figure was printed twice, four
/// centimetres apart, under two different labels. The total is the headline
/// now, and the row underneath carries only what the headline does not say.
class ReportHeaderCard extends StatelessWidget {
  final PeriodSummary summary;
  final String locale;

  /// Change against the comparable stretch of the previous period. Null
  /// where there is no honest baseline to compare against.
  final int? delta;

  /// Milestone chips, already built by the caller. Empty for the tabs that
  /// do not have a milestone log to draw on.
  final List<Widget> chips;

  const ReportHeaderCard({
    super.key,
    required this.summary,
    required this.locale,
    this.delta,
    this.chips = const [],
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final d = delta;
    final deltaColor = d == null || d == 0
        ? gp.textTert
        : d > 0
            ? GameColors.emerald
            : GameColors.warning;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        border: Border.all(color: GameColors.gold.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              // Counts up on first paint, so the number reads as something
              // earned rather than a figure that was always sitting there.
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: summary.totalDone.toDouble()),
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) => Text(
                  toWesternDigits('${value.round()}'),
                  style: TextStyle(
                    fontSize: 38,
                    fontWeight: FontWeight.w900,
                    color: gp.textPrimary,
                    letterSpacing: -1.5,
                    height: 1,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                s.monthlyStoryGreenSquares,
                style: TextStyle(fontSize: 12.5, color: gp.textSec),
              ),
              if (d != null && d != 0) ...[
                const SizedBox(width: 8),
                Text(
                  d > 0
                      ? '+${toWesternDigits('$d')}'
                      : toWesternDigits('$d'),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: deltaColor,
                  ),
                ),
              ],
            ],
          ),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 6, runSpacing: 6, children: chips),
          ],
          const SizedBox(height: 14),
          Container(height: 0.5, color: gp.divider),
          const SizedBox(height: 12),
          Row(
            children: [
              _SummaryCell(
                // Rounded, never ceilinged: 99.6% must not print as 100%
                // beside a grid that visibly has a hole in it.
                value: '${(summary.rate * 100).round()}%',
                label: s.reportsRate,
                color: GameColors.emerald,
              ),
              _SummaryCell(
                value: summary.bestDay == null
                    ? '—'
                    : westernDate(summary.bestDay!, 'd MMM', locale),
                label: s.heatmapBestDay,
                color: GameColors.gold,
              ),
              _SummaryCell(
                value: toWesternDigits('${summary.longestRun}'),
                label: s.reportsLongestRun,
                color: GameColors.iconStreak,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryCell extends StatelessWidget {
  final String value;
  final String label;
  final Color color;

  const _SummaryCell({
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: color,
                height: 1.1,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 9.5, color: gp.textTert),
          ),
        ],
      ),
    );
  }
}

/// Which weekday someone actually shows up on, as seven bars plus the two
/// sentences that name the ends.
///
/// This is the one block on the reports hub that tells someone something a
/// grid cannot: a heatmap draws every Thursday the same size as every other
/// day, so a person who quietly collapses every Thursday can read a year of
/// their own history and never notice. See [computeWeekdayInsight] for why
/// this is an average rather than a rate.
class WeekdayRhythmCard extends StatelessWidget {
  /// Always a MEANINGFUL insight. The card does not render a "no pattern
  /// here" state, because it had one and it was the worst thing on the
  /// screen: on the yearly tab, where weekday averages are almost always
  /// even, seven identical bars and a shrug of a sentence took most of a
  /// screen to report nothing. Callers check [WeekdayInsight.isMeaningful]
  /// and draw nothing at all when it is false, so the card's presence is
  /// itself the signal that there is something worth reading.
  final WeekdayInsight insight;

  /// Average greens per occurrence, keyed by DateTime.monday..sunday, for
  /// the seven bars. Null when there is nothing to draw.
  final Map<int, double> averages;
  final String locale;

  /// The period this rhythm was measured over, printed beside the title.
  ///
  /// Not decoration. The Insights preview further down the same screen
  /// prints its own strongest-day claim computed over the whole account,
  /// so August's answer and the lifetime answer sit on one screen naming
  /// two different weekdays. Whichever a reader believes, an unlabelled
  /// pair of contradictory facts is the screen's fault, not theirs.
  final String periodLabel;

  const WeekdayRhythmCard({
    super.key,
    required this.insight,
    required this.averages,
    required this.locale,
    required this.periodLabel,
  });

  /// Saturday first, the same order the Grid and the year strip's rows use.
  static const _order = [
    DateTime.saturday,
    DateTime.sunday,
    DateTime.monday,
    DateTime.tuesday,
    DateTime.wednesday,
    DateTime.thursday,
    DateTime.friday,
  ];

  /// A real date carrying [weekday], purely so intl can name it in the
  /// active locale. 2026-08-15 is a Saturday, so adding the offset from
  /// Saturday lands on the wanted weekday.
  static DateTime _sampleDate(int weekday) {
    const saturday = DateTime.saturday;
    final offset = (weekday - saturday + 7) % 7;
    return DateTime(2026, 8, 15 + offset);
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final data = insight;
    final peak = averages.values.isEmpty
        ? 0.0
        : averages.values.reduce((a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        border: Border.all(color: gp.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.insights_rounded, size: 15, color: GameColors.gold),
              const SizedBox(width: 7),
              Text(
                s.reportsRhythmTitle,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: gp.textPrimary,
                ),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  periodLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: TextStyle(fontSize: 10.5, color: gp.textTert),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final weekday in _order)
                Expanded(
                  child: _RhythmBar(
                    label: westernDate(_sampleDate(weekday), 'EEE', locale),
                    value: averages[weekday] ?? 0,
                    peak: peak,
                    highlight: weekday == data.bestWeekday
                        ? GameColors.emerald
                        : weekday == data.worstWeekday
                            ? GameColors.warning
                            : null,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _RhythmLine(
            color: GameColors.emerald,
            icon: Icons.trending_up_rounded,
            text: s.reportsRhythmBest(
              westernDate(_sampleDate(data.bestWeekday), 'EEEE', locale),
            ),
          ),
          const SizedBox(height: 5),
          _RhythmLine(
            color: GameColors.warning,
            icon: Icons.trending_down_rounded,
            text: s.reportsRhythmWorst(
              westernDate(_sampleDate(data.worstWeekday), 'EEEE', locale),
            ),
          ),
        ],
      ),
    );
  }
}

class _RhythmBar extends StatelessWidget {
  final String label;
  final double value;
  final double peak;
  final Color? highlight;

  const _RhythmBar({
    required this.label,
    required this.value,
    required this.peak,
    required this.highlight,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final fill = peak <= 0 ? 0.0 : (value / peak).clamp(0.0, 1.0).toDouble();
    final color = highlight ?? gp.textTert.withOpacity(0.45);
    return Column(
      children: [
        SizedBox(
          // Tall enough that the difference between weekdays is legible as
          // a difference in height. At 42 the tallest and the shortest bar
          // differed by a dozen pixels across a full card width, so seven
          // weekdays read as seven blocks of roughly one size.
          height: 58,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: TweenAnimationBuilder<double>(
              // Grows from the baseline on first paint, so the shape of the
              // week reads as something that happened rather than a static
              // block that was always there.
              tween: Tween(begin: 0, end: fill),
              duration: GameMotion.relaxed,
              curve: Curves.easeOutCubic,
              builder: (context, t, _) => FractionallySizedBox(
                heightFactor: t.clamp(0.06, 1.0),
                child: Container(
                  // Wide margins on purpose: an Expanded column is roughly
                  // 48pt across, and a bar filling it is a block. These
                  // read as bars.
                  margin: const EdgeInsets.symmetric(horizontal: 9),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: TextStyle(
            fontSize: 9,
            fontWeight: highlight != null ? FontWeight.w800 : FontWeight.w500,
            color: highlight ?? gp.textTert,
          ),
        ),
      ],
    );
  }
}

class _RhythmLine extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String text;

  const _RhythmLine({
    required this.color,
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: gp.textSec,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

/// What one cell of a report grid is saying.
///
/// Eight states, not two, and every distinction earns its place:
///
///  - [notDue] versus [missed] is the difference between a blank Tuesday on a
///    Monday-and-Thursday habit and a blank Monday on one. Drawing them the
///    same accuses someone of five misses a week they never made.
///  - [rest] versus [missed] is تخطّي versus silence. A rest was chosen, and
///    it does not count against anyone, so it must not look like a hole.
///  - [failed] versus [missed] is فشل versus silence. One is an admission
///    someone typed, the other is a day they may simply not have opened the
///    app. Painting silence as failure would make the honest red meaningless.
///  - [bonus] and [partial] exist because the Grid already lets people record
///    them, and a report that flattens them is throwing away the only detail
///    those taps were for.
enum MatrixCellState { done, bonus, partial, failed, rest, missed, notDue, future }

/// One habit's week, resolved cell by cell.
///
/// Pure and top-level so the rules above are testable without painting
/// anything, in the same spirit as computeMonthlyStory and yearStripCell.
MatrixCellState cellStateFor({
  required HabitPeriodStat stat,
  required DateTime day,
  required DateTime today,
}) {
  if (day.isAfter(DateTime(today.year, today.month, today.day))) {
    return MatrixCellState.future;
  }
  return switch (stat.markOn(day)) {
    SquareState.complete => MatrixCellState.done,
    SquareState.bonus => MatrixCellState.bonus,
    SquareState.partial => MatrixCellState.partial,
    SquareState.failed => MatrixCellState.failed,
    SquareState.skipped => MatrixCellState.rest,
    // Nothing recorded. A quota habit owed a COUNT, not a calendar, so no
    // single blank day of its week is a miss; the shortfall shows up in the
    // percentage and the absent PERFECT mark instead. See
    // [missIsAttributable].
    SquareState.none =>
      missIsAttributable(stat.habit) && stat.habit.isScheduledFor(day)
          ? MatrixCellState.missed
          : MatrixCellState.notDue,
  };
}

/// One habit's week, resolved cell by cell. The month card resolves its own
/// days through [cellStateFor] too, so the two grids cannot disagree about
/// what the same day means.
List<MatrixCellState> weekCellStates({
  required HabitPeriodStat stat,
  required List<DateTime> weekDays,
  required DateTime today,
}) =>
    [
      for (final day in weekDays)
        cellStateFor(stat: stat, day: day, today: today),
    ];

/// The habit x weekday grid: the أسبوعي tab's centrepiece.
///
/// Read-only by design. The Grid screen IS this same matrix as a control
/// (tap a square, change a square), and two screens that look identical but
/// only one of which edits is how someone taps a report expecting it to do
/// something. Here a tap opens the day instead of changing it, which is the
/// one interaction a report can offer without pretending to be the Grid.
class WeeklyMatrixCard extends StatelessWidget {
  final List<HabitPeriodStat> stats;
  final List<DateTime> weekDays;
  final DateTime today;
  final String locale;

  /// Called with the tapped day. Null makes the whole grid inert.
  final void Function(DateTime day)? onTapDay;

  /// An archived block: same geometry, dimmed names.
  final bool muted;

  /// Tapping a habit's NAME opens that habit's own page. The name is the
  /// thing someone is already looking at when they want one habit's detail,
  /// so it is the shortest path to an answer and needs no new destination.
  final void Function(HabitPeriodStat)? onTapHabit;

  const WeeklyMatrixCard({
    super.key,
    required this.stats,
    required this.weekDays,
    required this.today,
    required this.locale,
    this.onTapDay,
    this.muted = false,
    this.onTapHabit,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final todayDay = DateTime(today.year, today.month, today.day);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        border: Border.all(color: gp.border, width: 0.5),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // The name column takes what it needs and the seven day columns
          // split the rest evenly, so a long Arabic habit name ellipsises
          // rather than squeezing the cells into slivers.
          final cellSize =
              ((constraints.maxWidth * 0.56) / 7).clamp(20.0, 34.0).toDouble();
          final gridWidth = cellSize * 7;
          return Column(
            children: [
              Row(
                children: [
                  const Expanded(child: SizedBox.shrink()),
                  SizedBox(
                    width: gridWidth,
                    child: Row(
                      children: [
                        for (final day in weekDays)
                          SizedBox(
                            width: cellSize,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // NARROW weekday form, not the short one:
                                // 'EEE' in Arabic renders "الأربعاء", which
                                // is four times the width of a 28pt column,
                                // so every label overflowed its cell and
                                // the seven of them painted on top of each
                                // other. 'EEEEE' is one letter in Arabic
                                // and one in English.
                                Text(
                                  westernDate(day, 'EEEEE', locale),
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: day.isSameDayAs(todayDay)
                                        ? FontWeight.w900
                                        : FontWeight.w600,
                                    color: day.isSameDayAs(todayDay)
                                        ? GameColors.gold
                                        : gp.textTert,
                                  ),
                                ),
                                // The date under it, so a cell can be tied
                                // to a real day without counting columns.
                                Text(
                                  toWesternDigits('${day.day}'),
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontSize: 8.5,
                                    fontWeight: day.isSameDayAs(todayDay)
                                        ? FontWeight.w800
                                        : FontWeight.w400,
                                    color: day.isSameDayAs(todayDay)
                                        ? GameColors.gold
                                        : gp.textTert.withOpacity(0.7),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              for (final stat in stats) ...[
                _MatrixRow(
                  stat: stat,
                  weekDays: weekDays,
                  today: today,
                  cellSize: cellSize,
                  gridWidth: gridWidth,
                  onTapDay: onTapDay,
                  muted: muted,
                  onTapHabit: onTapHabit,
                ),
                const SizedBox(height: 4),
              ],
              if (stats.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    s.reportsEmptyWeek,
                    style: TextStyle(fontSize: 12, color: gp.textTert),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _MatrixRow extends StatelessWidget {
  final HabitPeriodStat stat;
  final List<DateTime> weekDays;
  final DateTime today;
  final double cellSize;
  final double gridWidth;
  final void Function(DateTime day)? onTapDay;
  final bool muted;
  final void Function(HabitPeriodStat)? onTapHabit;

  const _MatrixRow({
    required this.stat,
    required this.weekDays,
    required this.today,
    required this.cellSize,
    required this.gridWidth,
    required this.onTapDay,
    required this.muted,
    required this.onTapHabit,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final base = stat.habit.customColor ?? GameColors.emerald;
    final color = muted ? base.withOpacity(0.55) : base;
    final states =
        weekCellStates(stat: stat, weekDays: weekDays, today: today);

    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: onTapHabit == null ? null : () => onTapHabit!(stat),
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                // The quit glyph, exactly as the year strip marks its own
                // quit rows: restraint and completion are different
                // achievements and the row should say which one it is.
                if (stat.habit.goalType == GoalType.quit) ...[
                  Icon(Icons.front_hand_rounded, size: 11, color: color),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    stat.habit.localName(s.isAr),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: muted ? gp.textSec : gp.textPrimary,
                    ),
                  ),
                ),
                if (stat.isPerfect) ...[
                  const SizedBox(width: 5),
                  Icon(Icons.verified_rounded,
                      size: 12, color: GameColors.gold),
                ],
              ],
            ),
          ),
        ),
        SizedBox(
          width: gridWidth,
          child: Row(
            children: [
              for (var i = 0; i < weekDays.length; i++)
                SizedBox(
                  width: cellSize,
                  child: _MatrixCell(
                    state: states[i],
                    color: color,
                    onTap: onTapDay == null ||
                            states[i] == MatrixCellState.future
                        ? null
                        : () => onTapDay!(weekDays[i]),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MatrixCell extends StatelessWidget {
  final MatrixCellState state;
  final Color color;
  final VoidCallback? onTap;

  const _MatrixCell({
    required this.state,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    // A missed day is an empty outline in the habit's own colour, never red.
    // This app deliberately does not punish a day off, and a wall of red is
    // exactly the guilt that makes people mark a habit done to protect a
    // number, which corrupts the data the report is built from. Red is
    // reserved for فشل, which is a word someone chose.
    final faint = gp.dark
        ? Colors.white.withOpacity(0.045)
        : Colors.black.withOpacity(0.045);
    final (Color fill, Color? border, bool flag) = switch (state) {
      MatrixCellState.done => (color, null, false),
      // Same fill, plus a small gold flag in the corner. A separate colour
      // would have said "different habit" rather than "same habit, extra".
      MatrixCellState.bonus => (color, null, true),
      // Exactly half the done colour, because it is worth exactly half a
      // day. The opacity IS the credit, so the grid encodes the arithmetic
      // rather than merely gesturing at it.
      MatrixCellState.partial => (color.withOpacity(0.5), color, false),
      MatrixCellState.failed => (
          GameColors.warning.withOpacity(0.14),
          GameColors.warning.withOpacity(0.75),
          false,
        ),
      // Rest reads as deliberate, not as a hole: a filled, calm tone rather
      // than an empty outline.
      MatrixCellState.rest => (
          GameColors.gold.withOpacity(0.16),
          null,
          false,
        ),
      MatrixCellState.missed => (
          Colors.transparent,
          color.withOpacity(0.35),
          false,
        ),
      MatrixCellState.notDue => (faint, null, false),
      // Fainter than notDue, but not invisible: a fully transparent future
      // cell collapsed the visible grid to however many days had already
      // happened, so a Wednesday showed a five-column week under a
      // seven-column header.
      MatrixCellState.future => (
          gp.dark
              ? Colors.white.withOpacity(0.02)
              : Colors.black.withOpacity(0.02),
          null,
          false,
        ),
    };
    return GestureDetector(
      onTap: onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              onTap!();
            },
      // Opaque so the whole cell box is a hit target, not just the painted
      // square inside its margin.
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(2.5),
        child: AspectRatio(
          aspectRatio: 1,
          child: Stack(
            children: [
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: fill,
                    borderRadius: BorderRadius.circular(5),
                    border:
                        border == null ? null : Border.all(color: border),
                  ),
                ),
              ),
              if (flag)
                Positioned(
                  top: 1,
                  right: 1,
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: GameColors.gold,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The month laid out as Saturday-anchored week rows, with leading and
/// trailing blanks so the 1st lands under its real weekday.
///
/// Null entries are the padding cells. Pure and top-level so the offset
/// maths (the part that silently shifts a whole month by a day when it is
/// wrong) is testable without a widget.
List<DateTime?> monthGridCells(DateTime month) {
  final first = DateTime(month.year, month.month);
  final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
  // The offset is DERIVED from [startOfGridWeek] rather than measured
  // against a literal DateTime.saturday. Saturday is the Gulf week start
  // and the right default for this app's first audience, but it is not the
  // week start in Morocco, Europe or the US, and the day this app grows a
  // first-day-of-week setting the anchor must move in exactly one place.
  // A hardcoded Saturday here would silently shift every month grid by a
  // column while the Grid screen moved correctly.
  final lead = first.difference(startOfGridWeek(first)).inDays;
  final cells = <DateTime?>[
    for (var i = 0; i < lead; i++) null,
    for (var d = 1; d <= daysInMonth; d++) DateTime(month.year, month.month, d),
  ];
  while (cells.length % 7 != 0) {
    cells.add(null);
  }
  return cells;
}

/// One habit's month as a numbered calendar, the شهري tab's per-habit card.
///
/// The percentage in the corner is [HabitPeriodStat.rate], measured against
/// what the habit actually owed, so a Monday-and-Thursday habit that never
/// missed reads 100% rather than the 29% a days-in-month denominator would
/// print under an obviously full-looking card.
class HabitMonthCard extends StatelessWidget {
  final HabitPeriodStat stat;
  final DateTime month;
  final DateTime today;

  /// Days before this draw muted and answer taps with the premium gate.
  final DateTime? lockedBefore;
  final void Function(DateTime day)? onTapDay;

  /// An archived habit: history intact, presence dimmed. The same treatment
  /// the year strip already gives its archived rows.
  final bool muted;

  /// Tapping the card's title opens that habit's own page.
  final VoidCallback? onTapHabit;

  const HabitMonthCard({
    super.key,
    required this.stat,
    required this.month,
    required this.today,
    required this.lockedBefore,
    this.onTapDay,
    this.muted = false,
    this.onTapHabit,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final base = stat.habit.customColor ?? GameColors.emerald;
    final color = muted ? base.withOpacity(0.55) : base;
    final cells = monthGridCells(month);
    final todayDay = DateTime(today.year, today.month, today.day);

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        border: Border.all(
          color: stat.isPerfect ? GameColors.gold.withOpacity(0.45) : gp.border,
          width: stat.isPerfect ? 1 : 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: onTapHabit,
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    stat.habit.localName(s.isAr),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: muted ? gp.textSec : gp.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          for (var row = 0; row * 7 < cells.length; row++)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                children: [
                  for (var col = 0; col < 7; col++)
                    Expanded(
                      child: _MonthDayCell(
                        day: cells[row * 7 + col],
                        state: () {
                          final day = cells[row * 7 + col];
                          if (day == null) return MatrixCellState.notDue;
                          return cellStateFor(
                            stat: stat,
                            day: day,
                            today: todayDay,
                          );
                        }(),
                        color: color,
                        today: todayDay,
                        lockedBefore: lockedBefore,
                        onTapDay: onTapDay,
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                '${(stat.rate * 100).round()}%',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  s.yearRecordDaysCount(stat.doneCount),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: gp.textTert),
                ),
              ),
              if (stat.isPerfect)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: GameColors.gold.withOpacity(0.16),
                    borderRadius:
                        BorderRadius.circular(GameSpacing.pillRadius),
                  ),
                  child: Text(
                    s.reportsPerfect,
                    style: TextStyle(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w900,
                      color: GameColors.gold,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MonthDayCell extends StatelessWidget {
  final DateTime? day;
  final MatrixCellState state;
  final Color color;
  final DateTime today;
  final DateTime? lockedBefore;
  final void Function(DateTime day)? onTapDay;

  const _MonthDayCell({
    required this.day,
    required this.state,
    required this.color,
    required this.today,
    required this.lockedBefore,
    required this.onTapDay,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final d = day;
    if (d == null) return const AspectRatio(aspectRatio: 1);
    final locked = lockedBefore != null && d.isBefore(lockedBefore!);
    final isToday = d.isSameDayAs(today);

    final Color fill;
    final Color text;
    Color? border;
    if (locked) {
      fill = gp.dark
          ? Colors.white.withOpacity(0.03)
          : Colors.black.withOpacity(0.03);
      text = gp.textTert.withOpacity(0.4);
    } else {
      // The same eight states the weekly matrix paints, carrying a day
      // number. Kept in one switch beside that one so a day cannot look like
      // a rest on one tab and a miss on the other.
      switch (state) {
        case MatrixCellState.done:
        case MatrixCellState.bonus:
          fill = color;
          // Black on a bright habit colour, since custom colours run light.
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
          // Not due and not yet arrived look the same on purpose: neither is
          // a miss, and neither should draw the eye.
          fill = gp.dark
              ? Colors.white.withOpacity(0.04)
              : Colors.black.withOpacity(0.04);
          text = gp.textTert.withOpacity(0.55);
      }
    }

    return GestureDetector(
      onTap: onTapDay == null || state == MatrixCellState.future
          ? null
          : () {
              HapticFeedback.selectionClick();
              onTapDay!(d);
            },
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(1),
        child: AspectRatio(
          aspectRatio: 1,
          child: Container(
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(4),
              border: isToday
                  ? Border.all(color: GameColors.gold)
                  : border == null
                      ? null
                      : Border.all(color: border),
            ),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.all(1),
                  child: Text(
                    toWesternDigits('${d.day}'),
                    style: TextStyle(
                      fontSize: 8.5,
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
        ),
      ),
    );
  }
}
