// The small pictures of the record that سجلّي adds around the report tabs:
// a card per year on «الكل», the year's twelve months on «سنة», the «منذ»
// line that stands in for the period stepper on «الكل», and the last two
// weeks on the Profile row that opens it.
//
// Aziz, 2026-09-21, on the first design: "still hard for the user to go back
// 3 years to search for a square in a month, day". So the tabs became zoom
// levels, the way Apple Photos (Years, Months, Days) and the iPhone
// Calendar's year view work: a year card opens that year, a month opens
// that month, a day opens the map's day sheet. Three taps to any day, with
// no month-by-month scrolling.
//
// Every colour here is the map's own rule (the share of the day's owed
// habits that went green, in the map's heat colours; see recordDayColor),
// so a day is the same shade at every zoom.
import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../../core/extensions/datetime_ext.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../../core/utils/western_digits.dart';
import '../../../shared/widgets/milestone_tally_chip.dart';
import '../../grid/models/square_state.dart';
import '../../grid/notifiers/weekly_grid_notifier.dart' show startOfGridWeek;
import '../../grid/screens/monthly_heatmap_screen.dart'
    show heatColor, heatLevel, heatmapScheduledOn;
import '../../habits/catalog/islamic_habit_catalog.dart'
    show IslamicHabitTemplate;
import '../../habits/models/habit_day_demand.dart' show GreenOnDay;
import 'year_strip.dart'
    show yearStripColumnCount, yearStripDay, yearStripOrigin;

/// A lived day's colour on every small picture of the record, by the map's
/// rule: how many of the habits that day owed went green, as a heat level.
Color recordDayColor({
  required int count,
  required DateTime day,
  required List<IslamicHabitTemplate> habits,
  required GreenOnDay isGreen,
  required bool dark,
}) =>
    heatColor(heatLevel(count, heatmapScheduledOn(habits, day, isGreen)), dark);

Color _wash(bool dark, double opacity) =>
    (dark ? Colors.white : Colors.black).withOpacity(opacity);

// ─── «الكل»: one card per year ───────────────────────────────────────────

/// A year of the whole record: its squares as one strip, its total, its
/// milestones. Tapping it opens that year on the «سنة» tab.
class RecordYearCard extends StatelessWidget {
  final int year;

  /// Green squares that year, from the same counts as the lifetime total
  /// (see RecordLifetime.totalIn), so the cards add up to it.
  final int total;

  /// Every lived day's colour, by dateKey (see [recordDayColor]).
  final Map<String, Color> colors;
  final DateTime today;

  /// Days before this are behind the free window: drawn muted.
  final DateTime? lockedBefore;
  final List<MilestoneTallyChip> chips;
  final VoidCallback onTap;

  const RecordYearCard({
    super.key,
    required this.year,
    required this.total,
    required this.colors,
    required this.today,
    required this.lockedBefore,
    required this.chips,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    return Semantics(
      button: true,
      label: toWesternDigits('$year'),
      child: Material(
        color: gp.surface,
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
              border: Border.all(color: gp.border, width: 0.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      toWesternDigits('$year'),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: gp.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        toWesternDigits(s.lifeTimelineYearTotal(total)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: gp.textSec),
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        size: 18, color: gp.textTert),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 44,
                  child: CustomPaint(
                    painter: YearHeatPainter(
                      year: year,
                      colors: colors,
                      empty: SquareState.none.fill(gp.dark),
                      future: _wash(gp.dark, 0.015),
                      locked: _wash(gp.dark, 0.03),
                      today: today,
                      isRtl: isRtl,
                      lockedBefore: lockedBefore,
                    ),
                  ),
                ),
                if (chips.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  MilestoneTallyRows(chips: chips),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A year of days as the reports' year strip lays them out (Saturday-first
/// weeks as columns, the oldest week at the start of the reading direction),
/// each day in its own colour rather than one habit's states.
class YearHeatPainter extends CustomPainter {
  final int year;
  final Map<String, Color> colors;

  /// A day with nothing green, and any day before the record began.
  final Color empty;
  final Color future;
  final Color locked;
  final DateTime today;
  final bool isRtl;
  final DateTime? lockedBefore;

  const YearHeatPainter({
    required this.year,
    required this.colors,
    required this.empty,
    required this.future,
    required this.locked,
    required this.today,
    required this.isRtl,
    required this.lockedBefore,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final columns = yearStripColumnCount(year);
    final cellW = size.width / columns;
    final cellH = size.height / 7;
    final side = (cellW < cellH ? cellW : cellH) - 1.2;
    if (side <= 0) return;
    final paint = Paint();
    final origin = yearStripOrigin(year);
    final todayDay = DateTime(today.year, today.month, today.day);
    for (var c = 0; c < columns; c++) {
      for (var r = 0; r < 7; r++) {
        final day = yearStripDay(origin, c * 7 + r);
        if (day.year != year) continue;
        final isFuture = day.isAfter(todayDay);
        final isLocked =
            !isFuture && lockedBefore != null && day.isBefore(lockedBefore!);
        paint.color = isFuture
            ? future
            : isLocked
                ? locked
                : colors[day.toDateKey()] ?? empty;
        final drawColumn = isRtl ? columns - 1 - c : c;
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(
            drawColumn * cellW + (cellW - side) / 2,
            r * cellH + (cellH - side) / 2,
            side,
            side,
          ),
          const Radius.circular(1.6),
        );
        canvas.drawRRect(rect, paint);
        if (day == todayDay) {
          canvas.drawRRect(
            rect,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1
              ..color = GameColors.gold,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(YearHeatPainter old) =>
      old.year != year ||
      !mapEquals(old.colors, colors) ||
      old.empty != empty ||
      old.future != future ||
      old.locked != locked ||
      old.today != today ||
      old.isRtl != isRtl ||
      old.lockedBefore != lockedBefore;
}

// ─── «سنة»: the year's twelve months ────────────────────────────────────

/// The twelve months of [year] as small calendars, three to a row, January
/// first in the reading direction. Each month's own days run left to right
/// with Saturday on the left, the map's style for every month grid (Aziz,
/// 2026-09-21: "the one in map is the correct style"). Tapping a month that
/// has lived days opens it on the «شهر» tab.
class YearMonthsGrid extends StatelessWidget {
  final int year;
  final Map<String, int> counts;
  final List<IslamicHabitTemplate> habits;
  final GreenOnDay isGreen;
  final DateTime today;

  /// The first day anything was marked; days before it are not part of the
  /// record and a month wholly before it cannot be opened.
  final DateTime? firstMark;
  final DateTime? lockedBefore;
  final ValueChanged<DateTime> onTapMonth;

  const YearMonthsGrid({
    super.key,
    required this.year,
    required this.counts,
    required this.habits,
    required this.isGreen,
    required this.today,
    required this.firstMark,
    required this.lockedBefore,
    required this.onTapMonth,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var row = 0; row < 4; row++)
          Padding(
            padding: EdgeInsets.only(bottom: row < 3 ? 8 : 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var col = 0; col < 3; col++) ...[
                  if (col > 0) const SizedBox(width: 8),
                  Expanded(
                    child: _MiniMonth(
                      month: DateTime(year, row * 3 + col + 1),
                      counts: counts,
                      habits: habits,
                      isGreen: isGreen,
                      today: today,
                      firstMark: firstMark,
                      lockedBefore: lockedBefore,
                      onTap: onTapMonth,
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _MiniMonth extends StatelessWidget {
  final DateTime month;
  final Map<String, int> counts;
  final List<IslamicHabitTemplate> habits;
  final GreenOnDay isGreen;
  final DateTime today;
  final DateTime? firstMark;
  final DateTime? lockedBefore;
  final ValueChanged<DateTime> onTap;

  const _MiniMonth({
    required this.month,
    required this.counts,
    required this.habits,
    required this.isGreen,
    required this.today,
    required this.firstMark,
    required this.lockedBefore,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final locale = Localizations.localeOf(context).languageCode;
    final todayDay = DateTime(today.year, today.month, today.day);
    final first = firstMark == null
        ? null
        : DateTime(firstMark!.year, firstMark!.month, firstMark!.day);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final lead = month.difference(startOfGridWeek(month)).inDays;
    final lastDay = DateTime(month.year, month.month, daysInMonth);
    // A month can be opened when at least one of its days is both lived and
    // part of the record.
    final enabled = first != null &&
        !month.isAfter(todayDay) &&
        !lastDay.isBefore(first);

    var total = 0;
    final cells = <Widget>[];
    for (var i = 0; i < 42; i++) {
      final d = i - lead + 1;
      if (d < 1 || d > daysInMonth) {
        cells.add(const SizedBox.shrink());
        continue;
      }
      final day = DateTime(month.year, month.month, d);
      final isFuture = day.isAfter(todayDay);
      final beforeRecord = first == null || day.isBefore(first);
      final isLocked = !isFuture &&
          lockedBefore != null &&
          day.isBefore(lockedBefore!);
      final count = counts[day.toDateKey()] ?? 0;
      if (!isFuture && !beforeRecord) total += count;
      final color = isFuture
          ? _wash(gp.dark, 0.015)
          : beforeRecord || isLocked
              ? _wash(gp.dark, 0.03)
              : recordDayColor(
                  count: count,
                  day: day,
                  habits: habits,
                  isGreen: isGreen,
                  dark: gp.dark,
                );
      cells.add(DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
          border: day == todayDay
              ? Border.all(color: GameColors.gold, width: 1)
              : null,
        ),
      ));
    }

    final name = DateFormat.MMMM(locale).format(month);
    return Semantics(
      button: enabled,
      label: toWesternDigits(DateFormat.yMMMM(locale).format(month)),
      child: Material(
        color: gp.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: enabled
              ? () {
                  HapticFeedback.selectionClick();
                  onTap(month);
                }
              : null,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: gp.border, width: 0.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: enabled ? gp.textPrimary : gp.textTert,
                        ),
                      ),
                    ),
                    if (enabled && total > 0)
                      Text(
                        toWesternDigits('$total'),
                        style: TextStyle(fontSize: 10.5, color: gp.textTert),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                // Left to right with Saturday first, like the map's month.
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Column(
                    children: [
                      for (var row = 0; row < 6; row++)
                        Padding(
                          padding: EdgeInsets.only(bottom: row < 5 ? 2 : 0),
                          child: Row(
                            children: [
                              for (var col = 0; col < 7; col++)
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 1),
                                    child: AspectRatio(
                                      aspectRatio: 1,
                                      child: cells[row * 7 + col],
                                    ),
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
          ),
        ),
      ),
    );
  }
}

// ─── «الكل»: the line where the period stepper sits on the other tabs ───

/// «منذ يونيو 2026» in the place the other tabs show their period.
///
/// Drawn as a control only when given [onTap]; «الكل» gives none (see its
/// call site for why a month list there was taken out).
class RecordSinceHeader extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const RecordSinceHeader({super.key, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final title = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: gp.textPrimary,
            ),
          ),
        ),
        if (onTap != null) ...[
          const SizedBox(width: 4),
          Icon(Icons.expand_more_rounded, size: 18, color: gp.textSec),
        ],
      ],
    );
    return SizedBox(
      height: 40,
      child: Center(
        child: onTap == null
            ? title
            : InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  onTap!();
                },
                borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: title,
                ),
              ),
      ),
    );
  }
}

// ─── The Profile row ─────────────────────────────────────────────────────

/// The last days of the record as a line of small squares, on the Profile
/// row that opens سجلّي: a glimpse of the map where people already look,
/// rather than a plain row to guess about. The oldest day sits at the start
/// of the reading direction and today at the end, ringed in gold like every
/// other today in the app.
class RecordRecentStrip extends StatelessWidget {
  /// Oldest first; the last one is today.
  final List<Color> colors;

  const RecordRecentStrip({super.key, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < colors.length; i++)
          Padding(
            padding: EdgeInsetsDirectional.only(start: i == 0 ? 0 : 3),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: colors[i],
                borderRadius: BorderRadius.circular(2),
                border: i == colors.length - 1
                    ? Border.all(color: GameColors.gold, width: 1)
                    : null,
              ),
            ),
          ),
      ],
    );
  }
}
