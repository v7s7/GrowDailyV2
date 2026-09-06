// A room's contribution strip must never spill its week columns past the card.
//
// The strip wraps its columns into runs, and it decided how many fit on one
// line with a single division:
//
//     perRun = ((maxWidth + _gap) / (_cell + _gap)).floor()
//
// which prices EVERY inter-column gap at _gap (3pt). But both rows widen a
// gap to `_gap * 5` at each month break — roomStripMonths' starts — so a run
// holding B breaks is 12pt wider per break than that division allowed:
//
//     perRun * _cell + (perRun - 1 - B) * _gap + B * (_gap * 5)
//   = perRun * 18 - 3 + 12 * B
//
// Measured before the fix, driving the real roomStripMonths: a four-month
// room at a 402pt phone width (274pt after the 64pt _labelInset) has 16 week
// columns and month breaks at columns 1, 6, 10 and 14. The division chose 15
// columns per run; that run carries all four breaks and needs 315pt against
// 274pt available — 41pt over. Across a sweep of window lengths and widths,
// 1,032 (window, width, run) combinations overflowed.
//
// In RELEASE there is no warning stripe, because RenderFlex only paints that
// under an assert and clipBehavior is Clip.none — so the columns simply spill
// past the card, exactly the way the leaderboard row's badges did
// (leaderboard_row_fit_test.dart).
//
// The fix can't be a bigger division, because the question is circular:
// perRun decides which breaks land inside a run, and those breaks decide the
// width perRun needs. roomStripPerRun starts at the division's answer — an
// upper bound, since breaks only ever cost width — and steps down until every
// run fits. These tests pin that no run is ever laid out wider than the width
// it was chosen for, at the lengths and widths where it actually broke.
//
// The month-boundary rule itself is not this file's business: it belongs to
// roomStripColumns (a straddling week is drawn as two columns, one per
// month), and room_strip_month_header_alignment_test.dart pins the
// header/column alignment that depends on it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
// intl exports its own TextDirection, which would shadow the framework's.
import 'package:intl/intl.dart' hide TextDirection;

import 'package:grow_daily_v2/features/rooms/screens/room_detail_screen.dart'
    show
        RoomStripColumn,
        RoomStripMonthLabel,
        roomStripColumns,
        roomStripMonthSegments,
        roomStripMonths,
        roomStripPerRun;

void main() {
  // Mirrors _MiniHeatmapStrip._cell / ._gap and the `_gap * 5` it widens a
  // month break to. The replica below is a faithful copy of the two rows the
  // strip builds, so these have to match the widget — the guard-the-guard
  // test at the bottom is what catches it if they ever stop matching.
  const cell = 15.0;
  const gap = 3.0;
  const breakGap = gap * 5;

  // Grouping compares months by (year, month), never by the printed string,
  // so the locale here only decides what the labels read as.
  initializeDateFormatting('en');
  final monthFmt = DateFormat('MMM', 'en');

  /// The strip's own column model, from the function the widget uses:
  /// Saturday-start weeks, invisible padding before the first day so every
  /// date lands on its true weekday row, split at month boundaries.
  ({int weekCount, List<RoomStripColumn> columns}) columnsFor(
    DateTime windowStart,
    DateTime lastDay,
  ) {
    final total = lastDay.difference(windowStart).inDays + 1;
    final days = List.generate(
      total,
      (i) => lastDay.subtract(Duration(days: total - 1 - i)),
    );
    final lead = (days.first.weekday + 1) % 7;
    final columns = roomStripColumns(lead, days);
    return (weekCount: columns.length, columns: columns);
  }

  /// A faithful replica of the two rows the strip lays out inside its
  /// LayoutBuilder, at the width that LayoutBuilder is handed.
  ///
  /// Deliberately a replica rather than a pump of the real widget:
  /// _MiniHeatmapStrip is private and needs a RoomModel, a RoomParticipant
  /// and several providers, so pumping it would test Firestore plumbing
  /// rather than the layout decision. Everything that decides WIDTH is real —
  /// the month boundaries come from roomStripMonths, the header segments from
  /// roomStripMonthSegments, the labels from the real RoomStripMonthLabel —
  /// and the pieces replaced by a plain SizedBox are the ones whose width is
  /// already pinned by a SizedBox in the widget (a column is as wide as its
  /// widest child, and every child is `SizedBox(width: _cell)`).
  ///
  /// [maxWidth] is what the LayoutBuilder sees, i.e. already inside the 64pt
  /// _labelInset the grid is padded by.
  Widget stripReplica({
    required double maxWidth,
    required int weekCount,
    required List<int> starts,
    required List<int> monthKeys,
    required List<String> monthLabels,
    required int perRun,
  }) {
    return SizedBox(
      width: maxWidth,
      child: IntrinsicWidth(
        child: Column(
          children: [
            for (var run = 0; run * perRun < weekCount; run++) ...[
              if (run > 0) const SizedBox(height: gap * 2),
              // The merged header band.
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final seg in roomStripMonthSegments(
                    run,
                    perRun,
                    weekCount,
                    monthKeys,
                    monthLabels,
                  )) ...[
                    if (seg.leadingBreak) const SizedBox(width: breakGap),
                    RoomStripMonthLabel(
                      label: seg.label,
                      width: seg.span * cell + (seg.span - 1) * gap,
                      color: const Color(0xFF888888),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              // The column row.
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var c = 0;
                      c < perRun && run * perRun + c < weekCount;
                      c++) ...[
                    if (c > 0)
                      SizedBox(
                        width: starts.contains(run * perRun + c)
                            ? breakGap
                            : gap,
                      ),
                    // One week column: seven cells on a _cell pitch, plus the
                    // week-number slot, all of them _cell wide.
                    const SizedBox(width: cell, height: cell * 7 + gap * 6),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Pumps the replica and returns every overflow the framework reported.
  Future<List<String>> overflowsAt(
    WidgetTester tester, {
    required double maxWidth,
    required DateTime windowStart,
    required DateTime lastDay,
    required bool isAr,
    // Null means "the real decision"; a value lets the guard test drive the
    // old flat division through the very same replica.
    int Function(double maxWidth, int weekCount, List<int> starts)? chooseRun,
  }) async {
    final errors = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (d) => errors.add(d.exceptionAsString());
    addTearDown(() => FlutterError.onError = previous);

    final cols = columnsFor(windowStart, lastDay);
    final months = roomStripMonths(cols.columns, monthFmt);
    final perRun = (chooseRun ?? roomStripPerRun)(
      maxWidth,
      cols.weekCount,
      months.starts,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: stripReplica(
              maxWidth: maxWidth,
              weekCount: cols.weekCount,
              starts: months.starts,
              monthKeys: months.keys,
              monthLabels: months.labels,
              perRun: perRun,
            ),
          ),
        ),
      ),
    );
    return errors.where((e) => e.contains('overflowed')).toList();
  }

  // The old formula's answer, kept only so the guard test can prove the
  // replica still reproduces the original overflow.
  int flatDivision(double maxWidth, int weekCount, List<int> starts) =>
      ((maxWidth + gap) / (cell + gap)).floor().clamp(1, weekCount);

  final lastDay = DateTime(2026, 9, 5);

  group('every run fits the width it was chosen for', () {
    // 274pt is a 402pt phone inside the 64pt label inset; the others cover
    // smaller phones and the wider cards a fold or tablet gives.
    for (final maxWidth in const [180.0, 220.0, 240.0, 274.0, 300.0, 338.0]) {
      for (final windowDays in const [30, 60, 90, 104, 120, 150]) {
        for (final isAr in const [true, false]) {
          testWidgets(
            'a ${windowDays}d room at ${maxWidth.toInt()}pt '
            '(${isAr ? "ar" : "en"})',
            (tester) async {
              final overflows = await overflowsAt(
                tester,
                maxWidth: maxWidth,
                windowStart: lastDay.subtract(Duration(days: windowDays - 1)),
                lastDay: lastDay,
                isAr: isAr,
              );
              expect(
                overflows,
                isEmpty,
                reason: 'the strip overflowed its card; a run must be chosen '
                    'to fit the wide gaps its month breaks open: $overflows',
              );
            },
          );
        }
      }
    }
  });

  // Every start day of a whole year, so no particular alignment of month
  // boundaries to Saturday-start weeks can slip through the cases above.
  testWidgets('no window length overflows at a 402pt phone width',
      (tester) async {
    const maxWidth = 274.0;
    final failures = <String>[];
    for (var windowDays = 7; windowDays <= 200; windowDays += 1) {
      final overflows = await overflowsAt(
        tester,
        maxWidth: maxWidth,
        windowStart: lastDay.subtract(Duration(days: windowDays - 1)),
        lastDay: lastDay,
        isAr: true,
      );
      if (overflows.isNotEmpty) failures.add('${windowDays}d');
    }
    expect(failures, isEmpty,
        reason: 'these window lengths still overflow at ${maxWidth}pt');
  });

  testWidgets('the replica really does catch the old formula '
      '(guard the guard)', (tester) async {
    // Without this, a replica that silently stopped measuring anything would
    // let every case above pass vacuously. The reported case — a four-month
    // room at a 402pt phone width — must still overflow under the division
    // that shipped the bug.
    final overflows = await overflowsAt(
      tester,
      maxWidth: 274,
      windowStart: lastDay.subtract(const Duration(days: 104)),
      lastDay: lastDay,
      isAr: true,
      chooseRun: flatDivision,
    );
    expect(overflows, isNotEmpty,
        reason: 'the replica no longer reproduces the original overflow, so '
            'the passing cases above prove nothing');
  });

  group('roomStripPerRun gives up no more width than it has to', () {
    // Shrinking is only ever the answer to a run that does not fit. A fix
    // that shrank harder than necessary would pass every test above while
    // wrapping a strip that had room to stay on one line.
    test('never exceeds the flat division, and never returns less than 1', () {
      for (var windowDays = 7; windowDays <= 200; windowDays++) {
        final cols = columnsFor(
          lastDay.subtract(Duration(days: windowDays - 1)),
          lastDay,
        );
        final months = roomStripMonths(cols.columns, monthFmt);
        for (final maxWidth in const [180.0, 220.0, 274.0, 338.0]) {
          final perRun =
              roomStripPerRun(maxWidth, cols.weekCount, months.starts);
          expect(perRun, greaterThanOrEqualTo(1));
          expect(perRun, lessThanOrEqualTo(cols.weekCount));
          expect(
            perRun,
            lessThanOrEqualTo(
              flatDivision(maxWidth, cols.weekCount, months.starts),
            ),
            reason: 'a break can only ever cost width, so the flat division '
                'is an upper bound',
          );
        }
      }
    });

    test('one more column would not have fitted', () {
      // The exact statement of "no more than it has to": whenever the answer
      // is below both the column count and the flat division, perRun + 1 must
      // genuinely overflow.
      double runWidth(int first, int n, Set<int> breaks) {
        var w = n * cell + (n - 1) * gap;
        for (var c = 1; c < n; c++) {
          if (breaks.contains(first + c)) w += breakGap - gap;
        }
        return w;
      }

      for (var windowDays = 7; windowDays <= 200; windowDays++) {
        final cols = columnsFor(
          lastDay.subtract(Duration(days: windowDays - 1)),
          lastDay,
        );
        final months = roomStripMonths(cols.columns, monthFmt);
        final breaks = months.starts.toSet();
        for (final maxWidth in const [180.0, 220.0, 274.0, 338.0]) {
          final perRun =
              roomStripPerRun(maxWidth, cols.weekCount, months.starts);
          if (perRun >= cols.weekCount) continue;
          if (perRun >= flatDivision(maxWidth, cols.weekCount, months.starts)) {
            continue;
          }
          final bigger = perRun + 1;
          var anyOverflows = false;
          for (var first = 0; first < cols.weekCount; first += bigger) {
            final remaining = cols.weekCount - first;
            final n = bigger < remaining ? bigger : remaining;
            if (runWidth(first, n, breaks) > maxWidth) anyOverflows = true;
          }
          expect(anyOverflows, isTrue,
              reason: '${windowDays}d at ${maxWidth}pt wrapped to $perRun '
                  'columns, but $bigger would have fitted');
        }
      }
    });
  });
}
