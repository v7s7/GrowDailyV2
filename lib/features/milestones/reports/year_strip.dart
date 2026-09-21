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
import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';

import '../../../core/extensions/datetime_ext.dart';
import '../../../core/theme/game_theme.dart';
import '../../grid/models/square_state.dart';
import '../../grid/notifiers/weekly_grid_notifier.dart' show startOfGridWeek;
import 'report_sections.dart' show MatrixCellState;

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

// ─── Palette ─────────────────────────────────────────────────────────────

/// What each kind of day is painted with on a year strip. One definition
/// for both strips that draw it (the reports' سنوي rows and the habit
/// sheet), so they cannot drift apart.
///
/// The same tones the bigger report grids use, less what a cell a few
/// points wide has no room for: no outline, no bonus flag, no day number.
/// Covered and partial are the weekly matrix's own fills.
@immutable
class YearStripPalette {
  final Color done;
  final Color partial;

  /// A day the habit asked nothing of (see isCoveredDay): an off-day of a
  /// specific-days schedule, or a flexible quota's rest day.
  ///
  /// This is the change the strip was missing (Aziz, 2026-09-21: "make the
  /// rest days or the not owed days have some diff than the miss days").
  /// It knew only done and تخطّي, so a four-a-week habit's three rest days
  /// a week were painted exactly like days it was owed and missed, and a
  /// year of keeping a promise read as a year of holes. The habit's own
  /// colour, soft, as the weekly matrix and the month cards paint the same
  /// day: well below partial's half, so it never passes for a half day.
  final Color covered;

  /// A day marked تخطّي. Separate from empty because a chosen rest is not
  /// nothing, and from done because it is not a completion.
  final Color rest;

  /// A day owed and left blank or marked فشل, a day still open, and a day
  /// before the habit was started: the one quiet tone the strip has always
  /// had for "nothing to credit here".
  final Color empty;

  /// Days before the free window, for an account without Premium.
  final Color locked;

  /// Days that have not happened yet.
  ///
  /// They used to be skipped entirely, which left a hole: in an RTL build the
  /// unlived part of the year sits on the LEFT, so a strip viewed in August
  /// was blank down its whole leading third and the card read as broken
  /// rather than as a year in progress. Drawn at a whisper instead, so the
  /// shape of the full year is there and the lived part reads as filling it.
  /// Fainter than [locked] on purpose: locked means "there is something
  /// here you cannot see yet", future means "there is nothing here yet", and
  /// the quieter of the two should be the one that holds nothing.
  final Color future;

  const YearStripPalette({
    required this.done,
    required this.partial,
    required this.covered,
    required this.rest,
    required this.empty,
    required this.locked,
    required this.future,
  });

  /// The strip's tones for a habit drawn in [color].
  factory YearStripPalette.of({required Color color, required bool dark}) {
    Color wash(double opacity) =>
        (dark ? Colors.white : Colors.black).withOpacity(opacity);
    return YearStripPalette(
      done: color,
      partial: color.withOpacity(0.5),
      covered: color.withOpacity(0.18),
      rest: SquareState.skipped.accent(dark).withOpacity(0.35),
      empty: wash(0.06),
      locked: wash(0.03),
      future: wash(0.015),
    );
  }

  Color forState(MatrixCellState state) => switch (state) {
        MatrixCellState.done || MatrixCellState.bonus => done,
        MatrixCellState.partial => partial,
        MatrixCellState.covered => covered,
        MatrixCellState.rest => rest,
        MatrixCellState.future => future,
        MatrixCellState.missed ||
        MatrixCellState.failed ||
        MatrixCellState.notDue =>
          empty,
      };

  @override
  bool operator ==(Object other) =>
      other is YearStripPalette &&
      other.done == done &&
      other.partial == partial &&
      other.covered == covered &&
      other.rest == rest &&
      other.empty == empty &&
      other.locked == locked &&
      other.future == future;

  @override
  int get hashCode =>
      Object.hash(done, partial, covered, rest, empty, locked, future);
}

// ─── Painter ─────────────────────────────────────────────────────────────

class YearStripPainter extends CustomPainter {
  final int year;

  /// Every day of [year] resolved to its state, by dateKey, with the same
  /// rules as the weekly matrix (see cellStatesByWeek). A day missing from
  /// the map paints as [YearStripPalette.empty].
  final Map<String, MatrixCellState> states;
  final YearStripPalette palette;
  final DateTime today;
  final bool isRtl;

  /// Days before this are locked for free accounts (drawn muted); null
  /// means everything is visible.
  final DateTime? lockedBefore;

  const YearStripPainter({
    required this.year,
    required this.states,
    required this.palette,
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
        // A day still to come is neither locked nor empty, and asking either
        // of those questions about it would be meaningless: it cannot hold a
        // completion and there is nothing behind a paywall about it.
        final future = day.isAfter(todayDay);
        final locked =
            !future && lockedBefore != null && day.isBefore(lockedBefore!);
        paint.color = future
            ? palette.future
            : locked
                ? palette.locked
                : palette.forState(
                    states[day.toDateKey()] ?? MatrixCellState.notDue,
                  );
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
      // By contents, not identity: the states are rebuilt every build, so
      // identity comparison repainted every strip on any rebuild.
      !mapEquals(old.states, states) ||
      old.palette != palette ||
      old.today != today ||
      old.lockedBefore != lockedBefore ||
      old.isRtl != isRtl;
}
