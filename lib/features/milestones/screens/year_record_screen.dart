import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/datetime_ext.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../../core/utils/western_digits.dart';
import '../../../shared/widgets/history_demo_gate.dart';
import '../../habits/catalog/islamic_habit_catalog.dart' show IslamicHabitTemplate;
import '../../habits/models/habit_model.dart' show GoalType;
import '../../grid/notifiers/weekly_grid_notifier.dart' show startOfGridWeek;
import '../../habits/notifiers/custom_habits_notifier.dart';
import '../../premium/notifiers/premium_notifier.dart';
import '../notifiers/habit_history_notifier.dart';

// ─── Pure layout math ────────────────────────────────────────────────────
//
// The strip is a Saturday-anchored week grid, exactly like every other
// week surface in this app: rows are weekdays (Saturday first), columns
// are weeks. Top-level functions so the geometry is unit-testable without
// painting anything.

/// The Saturday starting the week that contains Jan 1 of [year] — column 0.
DateTime yearStripOrigin(int year) => startOfGridWeek(DateTime(year, 1, 1));

/// How many week-columns [year] needs (the week containing Dec 31,
/// inclusive). 53 or 54 depending on where the year's edges fall.
int yearStripColumnCount(int year) {
  final origin = yearStripOrigin(year);
  return DateTime.utc(year, 12, 31)
              .difference(
                  DateTime.utc(origin.year, origin.month, origin.day))
              .inDays ~/
          7 +
      1;
}

/// (column, row) for [day] within its year's strip.
({int column, int row}) yearStripCell(DateTime day) {
  // Calendar-day delta via UTC reconstruction, not local .difference():
  // local DateTimes absorb DST shifts, and a 23-hour day makes inDays
  // round down one short — every cell after the transition lands a column
  // early. (No DST in Bahrain; the geometry shouldn't know that.)
  final a = DateTime.utc(day.year, day.month, day.day);
  final origin = yearStripOrigin(day.year);
  final b = DateTime.utc(origin.year, origin.month, origin.day);
  final delta = a.difference(b).inDays;
  return (column: delta ~/ 7, row: delta % 7);
}

/// The calendar day sitting [daysFromOrigin] after [origin] — constructed,
/// never `.add(Duration(days:))`, for the same DST reason as
/// [yearStripCell].
DateTime yearStripDay(DateTime origin, int daysFromOrigin) =>
    DateTime(origin.year, origin.month, origin.day + daysFromOrigin);

/// The day under a tap at [dx] (fraction 0..1 of the strip's width, in
/// PAINT order) on [row], honoring the strip's reading direction: oldest
/// week sits at the START (right in Arabic, left in English), matching the
/// room strips the user already reads.
DateTime yearStripDayAt({
  required int year,
  required double dxFraction,
  required int row,
  required bool isRtl,
}) {
  final columns = yearStripColumnCount(year);
  final fraction = isRtl ? 1 - dxFraction : dxFraction;
  final column = (fraction * columns).floor().clamp(0, columns - 1);
  return yearStripDay(yearStripOrigin(year), column * 7 + row);
}

// ─── Painter ─────────────────────────────────────────────────────────────

class YearStripPainter extends CustomPainter {
  final int year;
  final Set<String> doneDays;
  final Color color;
  final DateTime today;
  final bool isRtl;

  /// Days before this are locked for free accounts (drawn muted); null
  /// means everything is visible.
  final DateTime? lockedBefore;
  final Color emptyColor;
  final Color lockedColor;

  const YearStripPainter({
    required this.year,
    required this.doneDays,
    required this.color,
    required this.today,
    required this.isRtl,
    required this.lockedBefore,
    required this.emptyColor,
    required this.lockedColor,
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
        if (day.isAfter(todayDay)) continue;
        final locked = lockedBefore != null && day.isBefore(lockedBefore!);
        final done = doneDays.contains(day.toDateKey());
        paint.color = locked
            ? lockedColor
            : done
                ? color
                : emptyColor;
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
  bool shouldRepaint(YearStripPainter old) =>
      old.year != year ||
      // By contents, not identity: the day sets are rebuilt every build,
      // so identity comparison repainted every strip on any rebuild.
      !setEquals(old.doneDays, doneDays) ||
      old.color != color ||
      old.lockedBefore != lockedBefore ||
      old.isRtl != isRtl;
}

// ─── Screen ──────────────────────────────────────────────────────────────

/// سجل السنة: every habit as a row with its own year of history — the
/// per-habit sibling of the aggregate Monthly Heatmap, and the surface the
/// owner picked first from the reporting roadmap. Free accounts see the
/// standard kFreeHistoryMonths window; older cells draw muted and answer
/// any tap with the demo gate, the same one every history surface uses.
class YearRecordScreen extends ConsumerStatefulWidget {
  const YearRecordScreen({super.key});

  @override
  ConsumerState<YearRecordScreen> createState() => _YearRecordScreenState();
}

class _YearRecordScreenState extends ConsumerState<YearRecordScreen> {
  late int _year = DateTime.now().effectiveDay.year;

  /// The archived section starts collapsed: archiving means "not part of
  /// my present", so the past shows up only when asked for — but it DOES
  /// show up, because this screen is the one place an archived habit's
  /// history still lives.
  bool _showArchived = false;

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final isPremium = ref.watch(premiumProvider);
    // The REAL calendar day, not effectiveDay: this is a calendar view,
    // and before 6am the gold ring must sit on the date the phone's own
    // calendar says — the same isRealToday convention the room calendar
    // documents. (effectiveDay still picks the initial year above, where
    // the flex window is the point.)
    final today = DateTime.now();
    final history = ref.watch(habitYearHistoryProvider);
    // allHabitsEver, not habitListProvider: archiving a habit must not
    // erase its year from this screen — the same reasoning the Monthly
    // Heatmap documents for its own percentages. Deduped by id because
    // that provider emits one synthetic template per catalog STINT and
    // this screen keys a whole year per habit id — without the dedup, a
    // habit archived and re-activated rendered as identical twin rows.
    final habits = <IslamicHabitTemplate>[];
    final seenIds = <String>{};
    for (final h in ref.watch(allHabitsEverProvider)) {
      if (seenIds.add(h.id)) habits.add(h);
    }

    // The free window's floor: the first day of the oldest month
    // canBrowseHistoryMonth still allows (Dart normalizes month - 2
    // across January into the previous year on its own).
    final freeFloor = DateTime(today.year, today.month - 2, 1);
    // Only meaningful where it actually bites the YEAR ON SCREEN: in
    // January, viewing the current year, nothing is older than the floor —
    // passing the floor anyway drew lock icons over a fully visible year.
    final floorBitesYear = DateTime(_year, 1, 1).isBefore(freeFloor);
    final lockedBefore = isPremium || !floorBitesYear ? null : freeFloor;

    // Both ends bounded by DATA; the premium gate answers only for years
    // the free window truly excludes. In January the window itself spans
    // into the previous year (Nov/Dec are free), so the back arrow must
    // navigate there, not paywall it.
    final earliestDataYear = history.maybeWhen(
      data: (byHabit) {
        var earliest = today.year;
        for (final days in byHabit.values) {
          for (final key in days) {
            final y = int.tryParse(key.split('-').first) ?? today.year;
            if (y < earliest) earliest = y;
          }
        }
        return earliest;
      },
      orElse: () => today.year,
    );
    final canGoForward = _year < today.year;
    final canGoBack = _year > earliestDataYear;
    final backNeedsPremium = !isPremium && (_year - 1) < freeFloor.year;

    return Scaffold(
      backgroundColor: gp.bg,
      appBar: AppBar(
        backgroundColor: gp.bg,
        surfaceTintColor: Colors.transparent,
        title: Text(
          s.yearRecordTitle,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: gp.textPrimary,
          ),
        ),
      ),
      body: history.when(
        loading: () => const Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        error: (_, __) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              s.monthlyStoryLoadFailed,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: gp.textSec, height: 1.4),
            ),
          ),
        ),
        data: (byHabit) {
          Set<String> yearDays(String habitId) => {
                for (final key in byHabit[habitId] ?? const <String>{})
                  if (key.startsWith('$_year-')) key,
              };
          // The label counts what the strip SHOWS. On the free tier a
          // full-history count next to a mostly-muted strip read as a
          // bug ("46 يوم" over 15 visible cells); the muted region's own
          // lock is the tell that there is more.
          final floorKey = lockedBefore?.toDateKey();
          int visibleCount(Set<String> days) => floorKey == null
              ? days.length
              : days.where((k) => k.compareTo(floorKey) >= 0).length;
          final active = [
            for (final habit in habits)
              if (habit.archivedAt == null)
                (habit: habit, days: yearDays(habit.id)),
          ];
          // Archived rows only when they have something to show for this
          // year: an archived habit with an empty strip is pure noise,
          // while an active one with an empty strip is a commitment
          // waiting to be started.
          final archived = [
            for (final habit in habits)
              if (habit.archivedAt != null)
                if (yearDays(habit.id).isNotEmpty)
                  (habit: habit, days: yearDays(habit.id)),
          ];
          final rows = active;
          return ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: canGoBack || backNeedsPremium
                        ? () {
                            HapticFeedback.selectionClick();
                            if (backNeedsPremium) {
                              showHistoryDemoGate(context);
                              return;
                            }
                            setState(() => _year--);
                          }
                        : null,
                    tooltip: MaterialLocalizations.of(context)
                        .previousMonthTooltip,
                    icon: const Icon(Icons.chevron_left_rounded),
                    iconSize: 22,
                    color: gp.textSec,
                    disabledColor: gp.textTert.withOpacity(0.3),
                    visualDensity: VisualDensity.compact,
                  ),
                  Expanded(
                    child: Text(
                      toWesternDigits('$_year'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: gp.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: canGoForward
                        ? () {
                            HapticFeedback.selectionClick();
                            setState(() => _year++);
                          }
                        : null,
                    tooltip:
                        MaterialLocalizations.of(context).nextMonthTooltip,
                    icon: const Icon(Icons.chevron_right_rounded),
                    iconSize: 22,
                    color: gp.textSec,
                    disabledColor: gp.textTert.withOpacity(0.3),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (active.isEmpty && archived.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48),
                  child: Column(
                    children: [
                      Icon(Icons.calendar_view_month_rounded,
                          size: 40, color: gp.textTert),
                      const SizedBox(height: 12),
                      Text(
                        s.yearRecordEmpty,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 13, color: gp.textSec, height: 1.4),
                      ),
                    ],
                  ),
                )
              else
                for (final row in rows) ...[
                  _HabitYearRow(
                    name: row.habit.localName(s.isAr),
                    color: row.habit.customColor ?? GameColors.emerald,
                    days: row.days,
                    year: _year,
                    today: today,
                    isRtl: isRtl,
                    lockedBefore: lockedBefore,
                    isQuit: row.habit.goalType == GoalType.quit,
                    muted: false,
                    daysLabel: row.habit.goalType == GoalType.quit
                        ? s.yearRecordCleanDaysCount(visibleCount(row.days))
                        : s.yearRecordDaysCount(visibleCount(row.days)),
                  ),
                  const SizedBox(height: 10),
                ],
              if (archived.isNotEmpty) ...[
                const SizedBox(height: 6),
                InkWell(
                  borderRadius:
                      BorderRadius.circular(GameSpacing.buttonRadius),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _showArchived = !_showArchived);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 8),
                    child: Row(
                      children: [
                        Icon(Icons.inventory_2_outlined,
                            size: 14, color: gp.textTert),
                        const SizedBox(width: 8),
                        Text(
                          '${s.yearRecordArchivedSection} · ${archived.length}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: gp.textTert,
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          _showArchived
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                          size: 18,
                          color: gp.textTert,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_showArchived) ...[
                  const SizedBox(height: 4),
                  for (final row in archived) ...[
                    _HabitYearRow(
                      name: row.habit.localName(s.isAr),
                      color: row.habit.customColor ?? GameColors.emerald,
                      days: row.days,
                      year: _year,
                      today: today,
                      isRtl: isRtl,
                      lockedBefore: lockedBefore,
                      isQuit: row.habit.goalType == GoalType.quit,
                      muted: true,
                      daysLabel: row.habit.goalType == GoalType.quit
                          ? s.yearRecordCleanDaysCount(visibleCount(row.days))
                          : s.yearRecordDaysCount(visibleCount(row.days)),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}

class _HabitYearRow extends StatelessWidget {
  final String name;
  final Color color;
  final Set<String> days;
  final int year;
  final DateTime today;
  final bool isRtl;
  final DateTime? lockedBefore;
  final String daysLabel;

  /// A quit/reduce habit: same strip, same personal color (the color IS
  /// the habit's identity here — a second color system for goal type
  /// would collide with the custom colors people already picked), marked
  /// instead by the raised-hand glyph and the التزام day label.
  final bool isQuit;

  /// Archived rows: history intact, presence dimmed.
  final bool muted;

  const _HabitYearRow({
    required this.name,
    required this.color,
    required this.days,
    required this.year,
    required this.today,
    required this.isRtl,
    required this.lockedBefore,
    required this.daysLabel,
    required this.isQuit,
    required this.muted,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
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
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: muted ? color.withOpacity(0.55) : color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              if (isQuit) ...[
                Icon(Icons.front_hand_rounded,
                    size: 12,
                    color: muted ? gp.textTert : color),
                const SizedBox(width: 5),
              ],
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: muted ? gp.textSec : gp.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                daysLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              if (lockedBefore != null) ...[
                const SizedBox(width: 6),
                Icon(Icons.lock_rounded, size: 12, color: gp.textTert),
              ],
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final height = constraints.maxWidth / 7.6;
              return GestureDetector(
                // A tap on the muted region answers with the demo gate;
                // taps on the visible window do nothing (the strip is a
                // record, not a control), so nothing here fights scrolling.
                onTapUp: lockedBefore == null
                    ? null
                    : (details) {
                        final dx = (details.localPosition.dx /
                                constraints.maxWidth)
                            .clamp(0.0, 1.0);
                        final row = (details.localPosition.dy / (height / 7))
                            .floor()
                            .clamp(0, 6);
                        final day = yearStripDayAt(
                          year: year,
                          dxFraction: dx,
                          row: row,
                          isRtl: isRtl,
                        );
                        // Blank corner cells (the origin week's days
                        // that belong to the previous year) are not
                        // history, locked or otherwise.
                        if (day.year == year &&
                            day.isBefore(lockedBefore!)) {
                          showHistoryDemoGate(context);
                        }
                      },
                child: CustomPaint(
                  size: Size(constraints.maxWidth, height),
                  painter: YearStripPainter(
                    year: year,
                    doneDays: days,
                    color: color,
                    today: today,
                    isRtl: isRtl,
                    lockedBefore: lockedBefore,
                    emptyColor: gp.dark
                        ? Colors.white.withOpacity(0.06)
                        : Colors.black.withOpacity(0.06),
                    lockedColor: gp.dark
                        ? Colors.white.withOpacity(0.03)
                        : Colors.black.withOpacity(0.03),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
