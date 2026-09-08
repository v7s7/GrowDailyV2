// A room's contribution strip lays its days out as Saturday-start week
// columns, and a month's name must sit over that month's own columns.
//
// The rule (Aziz, 2026-09-06): a week that straddles a month boundary is
// drawn as TWO columns, one per month. August's last column holds Aug 29-31
// in its top three rows with the rest empty; September's first column holds
// Sep 1-4 in its bottom four rows under three empty ones. So a month's block
// is exactly the weeks it touches, a 31-day month starting on a Saturday is
// five columns of 7, 7, 7, 7 and 3, and no square ever sits under another
// month's name.
//
// It replaced the majority rule, which drew a straddling week once and gave
// it to whichever month owned more of its drawn days. That kept August to
// four columns but put Aug 29-31 under سبتمبر, and a month whose only days
// fell inside such a week (1-3 September of a room ending on the 3rd) was
// never named at all.
//
// These tests pin the split itself, and the invariant that makes the labels
// centre: the boxes roomStripMonthSegments lays out must cover EXACTLY the
// columns that month owns. The strip is one line that scrolls sideways
// (room_strip_scroll_test.dart), so there is a single run of columns and the
// segments have to account for every one of them.
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
        roomStripMonths;

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

  /// The strip's own column model, built by the very function the widget
  /// uses: Saturday-start weeks, invisible padding before the first day so
  /// every date lands on its true weekday row, split at month boundaries.
  ({List<DateTime> days, List<RoomStripColumn> columns}) columnsFor(
    DateTime windowStart,
    DateTime lastDay,
  ) {
    final total = lastDay.difference(windowStart).inDays + 1;
    final days = List.generate(
      total,
      (i) => lastDay.subtract(Duration(days: total - 1 - i)),
    );
    final lead = (days.first.weekday + 1) % 7;
    return (days: days, columns: roomStripColumns(lead, days));
  }

  /// The dates one column draws, top row first.
  List<DateTime> daysIn(
    ({List<DateTime> days, List<RoomStripColumn> columns}) cols,
    int c,
  ) =>
      [
        for (final i in cols.columns[c].dayIndex)
          if (i >= 0) cols.days[i],
      ];

  /// Which of the seven rows a column fills.
  List<int> rowsIn(
    ({List<DateTime> days, List<RoomStripColumn> columns}) cols,
    int c,
  ) =>
      [
        for (var r = 0; r < 7; r++)
          if (cols.columns[c].dayIndex[r] >= 0) r,
      ];

  /// Where the CELL row puts each column, in the strip's own space.
  List<({double start, double end})> columnBoxes(
    int columnCount,
    List<int> starts,
  ) {
    final out = <({double start, double end})>[];
    var x = 0.0;
    for (var c = 0; c < columnCount; c++) {
      if (c > 0) x += starts.contains(c) ? breakGap : gap;
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

  /// The assertion the header half of this file exists for: every label's
  /// box covers exactly its own columns, so its centre IS their centre.
  void expectLabelsCentredOverTheirColumns(
    DateTime windowStart,
    DateTime lastDay, {
    required String reason,
  }) {
    final cols = columnsFor(windowStart, lastDay);
    final count = cols.columns.length;
    final months = roomStripMonths(cols.columns, monthFmt);

    final segments = roomStripMonthSegments(months.keys, months.labels);
    final columns = columnBoxes(count, months.starts);
    final labels = labelBoxes(segments);

    // Every column is claimed by exactly one label.
    expect(
      segments.fold<int>(0, (a, s) => a + s.span),
      columns.length,
      reason: '$reason: labels must span every column',
    );

    var c = 0;
    for (var i = 0; i < labels.length; i++) {
      final first = columns[c];
      final last = columns[c + segments[i].span - 1];
      expect(
        labels[i].start,
        first.start,
        reason: '$reason: "${labels[i].label}" must start where '
            'its first column starts',
      );
      expect(
        labels[i].end,
        last.end,
        reason: '$reason: "${labels[i].label}" must end where '
            'its last column ends',
      );
      expect(
        (labels[i].start + labels[i].end) / 2,
        (first.start + last.end) / 2,
        reason: '$reason: "${labels[i].label}" must be centred '
            'over its own columns',
      );
      c += segments[i].span;
    }
  }

  group('the month Aziz described: August into September 2026', () {
    // 1 August 2026 is a Saturday, so August is four full columns and a
    // fifth holding the 29th, 30th and 31st. 1 September is a Tuesday.
    final start = DateTime(2026, 8, 1);
    final last = DateTime(2026, 9, 30);

    test('August is five columns: 7, 7, 7, 7 and 3', () {
      final cols = columnsFor(start, last);
      final months = roomStripMonths(cols.columns, monthFmt);
      final august = [
        for (var c = 0; c < cols.columns.length; c++)
          if (months.labels[c] == 'Aug') c,
      ];
      expect(august, [0, 1, 2, 3, 4]);
      expect(august.map((c) => daysIn(cols, c).length).toList(), [7, 7, 7, 7, 3]);
      expect(daysIn(cols, 4).first, DateTime(2026, 8, 29));
      expect(daysIn(cols, 4).last, DateTime(2026, 8, 31));
      expect(rowsIn(cols, 4), [0, 1, 2], reason: 'the three sit at the top');
    });

    test('September opens with three empty rows, then the 1st to the 4th', () {
      final cols = columnsFor(start, last);
      final months = roomStripMonths(cols.columns, monthFmt);
      expect(months.labels[5], 'Sep');
      expect(rowsIn(cols, 5), [3, 4, 5, 6]);
      expect(daysIn(cols, 5), [
        DateTime(2026, 9, 1),
        DateTime(2026, 9, 2),
        DateTime(2026, 9, 3),
        DateTime(2026, 9, 4),
      ]);
      // The two slices are the same calendar week, drawn twice.
      expect(rowsIn(cols, 4).toSet().intersection(rowsIn(cols, 5).toSet()),
          isEmpty);
    });

    test('the one gap opens between the two slices of that week', () {
      final cols = columnsFor(start, last);
      final months = roomStripMonths(cols.columns, monthFmt);
      expect(months.starts, [5]);
      expect(months.labels.sublist(0, 6), ['Aug', 'Aug', 'Aug', 'Aug', 'Aug', 'Sep']);
    });

    test('centres every label over its own columns', () {
      expectLabelsCentredOverTheirColumns(
        start,
        last,
        reason: 'August into September',
      );
    });
  });

  group('the reported room', () {
    // NO STOOOOP: started Friday 21 August 2026, read on Saturday 5 September.
    final start = DateTime(2026, 8, 21);
    final last = DateTime(2026, 9, 5);

    test('the straddling week is split, not handed to either month', () {
      final cols = columnsFor(start, last);
      expect(cols.columns.length, 5);
      final months = roomStripMonths(cols.columns, monthFmt);
      expect(months.labels, ['Aug', 'Aug', 'Aug', 'Sep', 'Sep']);
      expect(daysIn(cols, 2).map((d) => d.day).toList(), [29, 30, 31]);
      expect(daysIn(cols, 3).map((d) => d.day).toList(), [1, 2, 3, 4]);
    });

    test('opens exactly one gap, where the months actually change', () {
      final cols = columnsFor(start, last);
      final months = roomStripMonths(cols.columns, monthFmt);
      expect(months.starts, [3]);
    });

    test('centres every label over its own columns', () {
      expectLabelsCentredOverTheirColumns(
        start,
        last,
        reason: 'NO STOOOOP',
      );
    });
  });

  group('every column belongs to exactly one month', () {
    // A long room, so many boundaries fall inside weeks.
    final start = DateTime(2026, 3, 4);
    final last = DateTime(2026, 12, 31);

    test('no column draws two months', () {
      final cols = columnsFor(start, last);
      for (var c = 0; c < cols.columns.length; c++) {
        final months = daysIn(cols, c).map((d) => d.month).toSet();
        expect(months.length, 1, reason: 'column $c draws $months');
      }
    });

    test('every day of the window is drawn exactly once', () {
      final cols = columnsFor(start, last);
      final drawn = [
        for (var c = 0; c < cols.columns.length; c++) ...daysIn(cols, c),
      ];
      expect(drawn, cols.days);
    });

    test('a month owns as many columns as the Saturday-weeks it touches', () {
      final cols = columnsFor(start, last);
      final months = roomStripMonths(cols.columns, monthFmt);
      final perMonth = <int, int>{};
      for (final k in months.keys) {
        perMonth[k] = (perMonth[k] ?? 0) + 1;
      }
      for (final entry in perMonth.entries) {
        final year = entry.key ~/ 12;
        final month = entry.key % 12 + 1;
        final first = DateTime(year, month, 1);
        final lastOfMonth = DateTime(year, month + 1, 0);
        final from = first.isBefore(start) ? start : first;
        final to = lastOfMonth.isAfter(last) ? last : lastOfMonth;
        // Saturday-week index of a date: days since an arbitrary Saturday, ~/ 7.
        int week(DateTime d) =>
            d.difference(DateTime(2026, 1, 3)).inDays ~/ 7;
        expect(entry.value, week(to) - week(from) + 1,
            reason: '${monthFmt.format(first)} $year');
      }
    });
  });

  group('a long room, many boundaries inside weeks', () {
    final start = DateTime(2026, 3, 4);
    final last = DateTime(2026, 9, 5);

    test('centres every label over its own columns', () {
      expectLabelsCentredOverTheirColumns(
        start,
        last,
        reason: 'March to September',
      );
    });

    test('the header never opens with a break', () {
      // The column row only inserts a gap for c > 0, so a leading break
      // would push the whole header off by 15pt.
      final cols = columnsFor(start, last);
      final months = roomStripMonths(cols.columns, monthFmt);
      final segments = roomStripMonthSegments(months.keys, months.labels);
      expect(segments.first.leadingBreak, isFalse);
      expect(segments.skip(1).every((s) => s.leadingBreak), isTrue,
          reason: 'every later segment follows a month change');
    });
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
      await pumpLabel(tester, 'ديسمبر', 15);
      expect(tester.getRect(find.byType(RoomStripMonthLabel)).width, 15);
    });
  });

  group('edge cases', () {
    test('a room shorter than one week is a single labelled column', () {
      final cols = columnsFor(DateTime(2026, 9, 2), DateTime(2026, 9, 4));
      expect(cols.columns.length, 1);
      final months = roomStripMonths(cols.columns, monthFmt);
      expect(months.starts, isEmpty);
      expect(months.labels, ['Sep']);
      expectLabelsCentredOverTheirColumns(
        DateTime(2026, 9, 2),
        DateTime(2026, 9, 4),
        reason: 'three-day room',
      );
    });

    test('a month with no drawn Saturday still gets its own column', () {
      // 1-3 September 2026 fall inside the week that opens on August 29th.
      // Under the majority rule the strip never named September here; now
      // those three days are a column of their own, under their own name.
      final start = DateTime(2026, 8, 1);
      final last = DateTime(2026, 9, 3);
      final cols = columnsFor(start, last);
      final months = roomStripMonths(cols.columns, monthFmt);
      expect(months.labels, ['Aug', 'Aug', 'Aug', 'Aug', 'Aug', 'Sep']);
      expect(months.starts, [5]);
      expect(rowsIn(cols, 5), [3, 4, 5]);
      expectLabelsCentredOverTheirColumns(
        start,
        last,
        reason: 'trailing part-month',
      );
    });

    test('a window starting mid-week pads only the rows before its first day',
        () {
      // Tuesday 28 July 2026: three empty rows, then four July days.
      final cols = columnsFor(DateTime(2026, 7, 28), DateTime(2026, 9, 5));
      expect(rowsIn(cols, 0), [3, 4, 5, 6]);
      final months = roomStripMonths(cols.columns, monthFmt);
      final segments = roomStripMonthSegments(months.keys, months.labels);
      expect(
        segments.map((s) => '${s.label}:${s.span}').toList(),
        ['Jul:1', 'Aug:5', 'Sep:2'],
      );
    });

    test('two Decembers a year apart are two segments, not one', () {
      // MMM formats both as "Dec". Grouping on the label alone would merge
      // them into a single nine-column month.
      final cols = columnsFor(DateTime(2026, 12, 1), DateTime(2027, 12, 31));
      final months = roomStripMonths(cols.columns, monthFmt);
      final segments = roomStripMonthSegments(months.keys, months.labels);
      expect(segments.where((s) => s.label == 'Dec').length, 2);
      expectLabelsCentredOverTheirColumns(
        DateTime(2026, 12, 1),
        DateTime(2027, 12, 31),
        reason: 'two Decembers',
      );
    });
  });
}
