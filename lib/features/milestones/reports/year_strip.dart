// The year strip's geometry and painter, lifted out of the retired
// YearRecordScreen when "سجل السنة" stopped being a destination of its own
// and became the سنوي tab of the reports hub (see
// period_report_section.dart).
//
// Only the geometry and the painter moved; the screen and its row widget
// did not, because the reports hub draws its own row against the same
// painter. Keeping ONE painter is the point: two surfaces drawing a year of
// squares from two implementations would eventually disagree about which
// column a day sits in.
import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';

import '../../../core/extensions/datetime_ext.dart';
import '../../../core/theme/game_theme.dart';
import '../../grid/notifiers/weekly_grid_notifier.dart' show startOfGridWeek;

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

  /// Days that have not happened yet.
  ///
  /// They used to be skipped entirely, which left a hole: in an RTL build the
  /// unlived part of the year sits on the LEFT, so a strip viewed in August
  /// was blank down its whole leading third and the card read as broken
  /// rather than as a year in progress. Drawn at a whisper instead, so the
  /// shape of the full year is there and the lived part reads as filling it.
  /// Fainter than [lockedColor] on purpose: locked means "there is something
  /// here you cannot see yet", future means "there is nothing here yet", and
  /// the quieter of the two should be the one that holds nothing.
  final Color futureColor;

  const YearStripPainter({
    required this.year,
    required this.doneDays,
    required this.color,
    required this.today,
    required this.isRtl,
    required this.lockedBefore,
    required this.emptyColor,
    required this.lockedColor,
    required this.futureColor,
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
        // A day still to come is neither locked nor empty, and asking either
        // of those questions about it would be meaningless: it cannot hold a
        // completion and there is nothing behind a paywall about it.
        final future = day.isAfter(todayDay);
        final locked =
            !future && lockedBefore != null && day.isBefore(lockedBefore!);
        final done = !future && doneDays.contains(day.toDateKey());
        paint.color = future
            ? futureColor
            : locked
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
      old.futureColor != futureColor ||
      old.year != year ||
      // By contents, not identity: the day sets are rebuilt every build,
      // so identity comparison repainted every strip on any rebuild.
      !setEquals(old.doneDays, doneDays) ||
      old.color != color ||
      old.lockedBefore != lockedBefore ||
      old.isRtl != isRtl;
}
