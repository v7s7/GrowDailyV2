// The bug: on a room's contribution strip, a month's name did not sit over
// that month's own week columns.
//
// Seen on the NO STOOOOP room (started 21 August 2026, read on 5 September):
// the week numbers said 1 2 3 for August and 1 for September, but the wide
// month-break gap fell between August's second and third columns — so the
// eye grouped "2 1" under أغسطس and "3 1" under سبتمبر, and the أغسطس label
// itself sat 6pt off the centre of the three columns it names.
//
// Cause was two different definitions of where a month starts. The header
// band and the week numbers grouped a column by the month of its FIRST DRAWN
// day; the gap was opened on any column CONTAINING a day numbered 1. Those
// agree only when the 1st happens to be a Saturday (or the room's first day),
// so for most months the gap landed one column early. The widths still summed
// to the same total, which is why nothing overflowed and the drift was silent.
//
// Both are read off roomStripMonths now, and it hands a straddling week to
// whichever month owns most of its drawn days — first-drawn-day gave August
// five seven-day columns, 35 day-slots for a 31-day month.
//
// These tests pin the invariant that makes the labels centre: the boxes
// roomStripMonthSegments lays out must cover EXACTLY the columns that month
// owns, at every wrap width. And they pin the column counts, so no month can
// quietly claim more weeks than its days can fill.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
// intl exports its own TextDirection, which would shadow the framework's.
import 'package:intl/intl.dart' hide TextDirection;

import 'package:grow_daily_v2/features/rooms/screens/room_detail_screen.dart'
    show RoomStripMonthLabel, roomStripMonths, roomStripMonthSegments;

void main() {
  // Mirrors _MiniHeatmapStrip._cell / ._gap and the `_gap * 5` it widens a
  // month break to. The invariant below is scale-free — it compares two
  // layouts built from these same numbers — so these only have to match each
  // other, not track the widget forever.
  const cell = 15.0;
  const gap = 3.0;
  const breakGap = gap * 5;

  // The grouping compares months by (year, month), never by the printed
  // string, so the locale here only decides what the labels read as.
  initializeDateFormatting('en');
  final monthFmt = DateFormat('MMM', 'en');

  /// The strip's own column model: Saturday-start weeks, invisible padding
  /// before the first day so every date lands on its true weekday row.
  ({
    int weekCount,
    int lead,
    List<DateTime> days,
    List<DateTime> Function(int) daysIn,
  }) columnsFor(DateTime windowStart, DateTime lastDay) {
    final total = lastDay.difference(windowStart).inDays + 1;
    final days = List.generate(
      total,
      (i) => lastDay.subtract(Duration(days: total - 1 - i)),
    );
    final lead = (days.first.weekday + 1) % 7;
    final weekCount = (lead + days.length + 6) ~/ 7;
    List<DateTime> daysIn(int w) => [
          for (var r = 0; r < 7; r++)
            if (w * 7 + r - lead >= 0 && w * 7 + r - lead < days.length)
              days[w * 7 + r - lead],
        ];

    return (weekCount: weekCount, lead: lead, days: days, daysIn: daysIn);
  }

  /// Where the CELL row puts each column of one run, in the run's own space.
  List<({double start, double end})> columnBoxes(
    int run,
    int perRun,
    int weekCount,
    List<int> starts,
  ) {
    final out = <({double start, double end})>[];
    var x = 0.0;
    for (var c = 0; c < perRun && run * perRun + c < weekCount; c++) {
      if (c > 0) x += starts.contains(run * perRun + c) ? breakGap : gap;
      out.add((start: x, end: x + cell));
      x += cell;
    }
    return out;
  }

  /// Where the HEADER row puts each month label, in that same space.
  List<({String label, double start, double end})> labelBoxes(
    List<({String label, int span, bool leadingBreak})> segments,
  ) {
    final out = <({String label, double start, double end})>[];
    var x = 0.0;
    for (final seg in segments) {
      if (seg.leadingBreak) x += breakGap;
      final width = seg.span * cell + (seg.span - 1) * gap;
      out.add((label: seg.label, start: x, end: x + width));
      x += width;
    }
    return out;
  }

  /// The assertion this whole file exists for: every label's box covers
  /// exactly its own columns, so its centre IS their centre.
  void expectLabelsCentredOverTheirColumns(
    DateTime windowStart,
    DateTime lastDay, {
    required int perRun,
    required String reason,
  }) {
    final cols = columnsFor(windowStart, lastDay);
    final months = roomStripMonths(
      cols.weekCount,
      cols.lead,
      cols.days,
      monthFmt,
    );

    for (var run = 0; run * perRun < cols.weekCount; run++) {
      final segments = roomStripMonthSegments(
        run,
        perRun,
        cols.weekCount,
        months.keys,
        months.labels,
      );
      final columns =
          columnBoxes(run, perRun, cols.weekCount, months.starts);
      final labels = labelBoxes(segments);

      // Every column of the run is claimed by exactly one label.
      expect(
        segments.fold<int>(0, (a, s) => a + s.span),
        columns.length,
        reason: '$reason: run $run labels must span every column',
      );

      var c = 0;
      for (var i = 0; i < labels.length; i++) {
        final first = columns[c];
        final last = columns[c + segments[i].span - 1];
        expect(
          labels[i].start,
          first.start,
          reason: '$reason: "${labels[i].label}" (run $run) must start where '
              'its first column starts',
        );
        expect(
          labels[i].end,
          last.end,
          reason: '$reason: "${labels[i].label}" (run $run) must end where '
              'its last column ends',
        );
        expect(
          (labels[i].start + labels[i].end) / 2,
          (first.start + last.end) / 2,
          reason: '$reason: "${labels[i].label}" (run $run) must be centred '
              'over its own columns',
        );
        c += segments[i].span;
      }
    }
  }

  group('the reported room', () {
    // NO STOOOOP: started Friday 21 August 2026, read on Saturday 5 September.
    final start = DateTime(2026, 8, 21);
    final last = DateTime(2026, 9, 5);

    test('gives the straddling week to September, which owns more of it', () {
      final cols = columnsFor(start, last);
      expect(cols.weekCount, 4);

      // Column 2 draws Aug 29, 30, 31 and Sep 1, 2, 3, 4 — four September
      // days against three August ones.
      expect(cols.daysIn(2).where((d) => d.month == 8).length, 3);
      expect(cols.daysIn(2).where((d) => d.month == 9).length, 4);

      final months =
          roomStripMonths(cols.weekCount, cols.lead, cols.days, monthFmt);
      expect(months.labels, ['Aug', 'Aug', 'Sep', 'Sep']);
    });

    test('opens exactly one gap, where the months actually change', () {
      final cols = columnsFor(start, last);
      final months =
          roomStripMonths(cols.weekCount, cols.lead, cols.days, monthFmt);

      expect(cols.daysIn(2).first, DateTime(2026, 8, 29));
      expect(months.starts, [2]);
    });

    test('centres every label over its own columns', () {
      expectLabelsCentredOverTheirColumns(
        start,
        last,
        perRun: 18,
        reason: 'NO STOOOOP',
      );
    });
  });

  group('a month that owns one or two columns centres like any other', () {
    // The room in the original report: started Tuesday 28 July 2026, so July
    // owns a single column, August four, and September two.
    final start = DateTime(2026, 7, 28);
    final last = DateTime(2026, 9, 5);

    test('July 1 column, August 4, September 2', () {
      final cols = columnsFor(start, last);
      final months =
          roomStripMonths(cols.weekCount, cols.lead, cols.days, monthFmt);
      final segments = roomStripMonthSegments(
        0,
        cols.weekCount,
        cols.weekCount,
        months.keys,
        months.labels,
      );
      expect(
        segments.map((s) => '${s.label}:${s.span}').toList(),
        ['Jul:1', 'Aug:4', 'Sep:2'],
      );
    });

    test('a whole month never spans more weeks than it has days for', () {
      // The complaint that produced this rule: "how in aug its 35 days? 5
      // Col, 7 days". August is drawn in full here, so its block must fit
      // its 31 days: four columns, not five.
      final cols = columnsFor(start, last);
      final months =
          roomStripMonths(cols.weekCount, cols.lead, cols.days, monthFmt);

      final columnsPerMonth = <int, int>{};
      for (var w = 0; w < cols.weekCount; w++) {
        columnsPerMonth[months.keys[w]] =
            (columnsPerMonth[months.keys[w]] ?? 0) + 1;
      }
      const august = 2026 * 12 + 7;
      expect(cols.days.where((d) => d.month == 8).length, 31);
      expect(columnsPerMonth[august], 4);
      expect(columnsPerMonth[august]! * 7, lessThanOrEqualTo(31));
    });

    test('every column is labelled with the month that owns most of it', () {
      // The property the block sizes fall out of, checked column by column.
      // A month can only be named over a week it genuinely dominates, so a
      // block of n columns can never be more than n weeks of that month.
      final cols = columnsFor(start, last);
      final months =
          roomStripMonths(cols.weekCount, cols.lead, cols.days, monthFmt);

      for (var w = 0; w < cols.weekCount; w++) {
        final drawn = <int, int>{};
        for (final d in cols.daysIn(w)) {
          final k = d.year * 12 + d.month - 1;
          drawn[k] = (drawn[k] ?? 0) + 1;
        }
        final mine = drawn[months.keys[w]] ?? 0;
        for (final other in drawn.entries) {
          if (other.key == months.keys[w]) continue;
          expect(
            mine,
            greaterThanOrEqualTo(other.value),
            reason: 'column $w is labelled "${months.labels[w]}" but another '
                'month draws more of its days',
          );
        }
      }
    });

    test('centres every label over its own columns', () {
      expectLabelsCentredOverTheirColumns(
        start,
        last,
        perRun: 18,
        reason: 'July-September',
      );
    });
  });

  group('holds at every wrap width', () {
    // A long room, so the strip wraps into several runs and months straddle
    // run boundaries.
    final start = DateTime(2026, 3, 4);
    final last = DateTime(2026, 9, 5);

    for (final perRun in [1, 2, 3, 5, 7, 11, 18]) {
      test('perRun $perRun', () {
        expectLabelsCentredOverTheirColumns(
          start,
          last,
          perRun: perRun,
          reason: 'perRun $perRun',
        );

        // A run never opens with a break: the column row only inserts a gap
        // for c > 0, so a leading break would push the header off by 15pt.
        final cols = columnsFor(start, last);
        final months = roomStripMonths(
          cols.weekCount,
          cols.lead,
          cols.days,
          monthFmt,
        );
        for (var run = 0; run * perRun < cols.weekCount; run++) {
          final segments = roomStripMonthSegments(
            run,
            perRun,
            cols.weekCount,
            months.keys,
            months.labels,
          );
          expect(segments.first.leadingBreak, isFalse);
        }
      });
    }
  });

  // Laying the block out in the right place is only half of it: the name
  // drawn inside that block has to sit on its centre too. A month owning one
  // 15pt column cannot fit its own name, and a plain centred Text stops
  // centring the moment its line is wider than the box — it anchors to an
  // edge instead. So the one-column months drifted while the wide ones did
  // not, which is the difference these tests pin.
  group('a name wider than its block still centres on it', () {
    Future<void> pumpLabel(WidgetTester tester, String label, double width) =>
        tester.pumpWidget(
          MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Center(
                child: RoomStripMonthLabel(
                  label: label,
                  width: width,
                  color: const Color(0xFF8A8F98),
                ),
              ),
            ),
          ),
        );

    testWidgets('a one-column month, whose name does not fit', (tester) async {
      // One column: 1 * _cell + 0 * _gap.
      await pumpLabel(tester, 'سبتمبر', 15);

      final block = tester.getRect(find.byType(RoomStripMonthLabel));
      final name = tester.getRect(find.text('سبتمبر'));

      expect(
        name.width,
        greaterThan(block.width),
        reason: 'this test is only meaningful while the name overflows',
      );
      expect(block.width, 15);
      expect(
        name.center.dx,
        closeTo(block.center.dx, 0.01),
        reason: 'an overflowing name must spill equally on both sides',
      );
    });

    testWidgets('a five-column month, whose name fits', (tester) async {
      // Five columns: 5 * _cell + 4 * _gap.
      await pumpLabel(tester, 'أغسطس', 87);

      final block = tester.getRect(find.byType(RoomStripMonthLabel));
      final name = tester.getRect(find.text('أغسطس'));

      expect(block.width, 87);
      expect(
        name.center.dx,
        closeTo(block.center.dx, 0.01),
        reason: 'a name that fits is centred the same way one that does not is',
      );
    });

    testWidgets('the block never grows to fit the name', (tester) async {
      // The header row's width has to stay the columns' width, or the label
      // band and the cell row stop lining up at all.
      await pumpLabel(tester, 'ديسمبر', 15);
      expect(tester.getRect(find.byType(RoomStripMonthLabel)).width, 15);
    });
  });

  group('edge cases', () {
    test('a room shorter than one week is a single labelled column', () {
      final cols = columnsFor(DateTime(2026, 9, 2), DateTime(2026, 9, 4));
      expect(cols.weekCount, 1);
      final months = roomStripMonths(cols.weekCount, cols.lead, cols.days, monthFmt);
      expect(months.starts, isEmpty);
      expect(months.labels, ['Sep']);
      expectLabelsCentredOverTheirColumns(
        DateTime(2026, 9, 2),
        DateTime(2026, 9, 4),
        perRun: 18,
        reason: 'three-day room',
      );
    });

    test('a room starting ON the 1st still opens its months correctly', () {
      // 1 August 2026 is a Saturday, so here the day-1 rule and the
      // first-drawn-day rule agree — the fix must not move this one.
      final cols = columnsFor(DateTime(2026, 8, 1), DateTime(2026, 9, 30));
      final months = roomStripMonths(cols.weekCount, cols.lead, cols.days, monthFmt);
      expect(cols.daysIn(0).first, DateTime(2026, 8, 1));
      expect(months.labels.first, 'Aug');
      expect(months.starts.length, 1);
      expect(months.labels[months.starts.first], 'Sep');
      expectLabelsCentredOverTheirColumns(
        DateTime(2026, 8, 1),
        DateTime(2026, 9, 30),
        perRun: 18,
        reason: 'starts on the 1st',
      );
    });

    test('a month with no drawn Saturday is silent, not falsely broken', () {
      // 1-3 September 2026 fall inside the column that opens on August 29th,
      // and September has no Saturday drawn at all, so the strip never names
      // it. That is the same rule everything else here follows: a column
      // belongs to the month of its first drawn day.
      //
      // Pinned because it is a deliberate trade, not an oversight. The old
      // day-1 rule DID open a gap before that column — but the أغسطس label
      // ran straight across the gap and the week number under it counted on
      // as August's fifth week, so the break announced a month that neither
      // of its neighbours agreed existed, and left the cell row 12pt wider
      // than the header it sat under. A correct silence beats that.
      final start = DateTime(2026, 8, 1);
      final last = DateTime(2026, 9, 3);
      final cols = columnsFor(start, last);
      final months = roomStripMonths(cols.weekCount, cols.lead, cols.days, monthFmt);

      expect(cols.daysIn(4).first, DateTime(2026, 8, 29));
      expect(months.labels, ['Aug', 'Aug', 'Aug', 'Aug', 'Aug']);
      expect(months.starts, isEmpty);
      expectLabelsCentredOverTheirColumns(
        start,
        last,
        perRun: 18,
        reason: 'trailing part-month',
      );
    });

    test('two Decembers a year apart are two segments, not one', () {
      // MMM formats both as "Dec". Grouping on the label alone would merge
      // them into a single nine-column month.
      final cols = columnsFor(DateTime(2026, 12, 1), DateTime(2027, 12, 31));
      final months = roomStripMonths(cols.weekCount, cols.lead, cols.days, monthFmt);
      final segments = roomStripMonthSegments(
        0,
        cols.weekCount,
        cols.weekCount,
        months.keys,
        months.labels,
      );
      expect(segments.where((s) => s.label == 'Dec').length, 2);
      expectLabelsCentredOverTheirColumns(
        DateTime(2026, 12, 1),
        DateTime(2027, 12, 31),
        perRun: 18,
        reason: 'two Decembers',
      );
    });
  });
}
