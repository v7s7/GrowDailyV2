// The week picker's two pure pieces: the list of selectable weeks, and the
// label a week wears.
//
// The label matters more than it looks. The Grid header and the picker that
// sets it now share this one function, because they used to disagree:
// the header ran DateFormat('MMM d'), which renders Arabic-Indic digits and
// puts the month first, so the same week read «يوليو ١١ – يوليو ١٧» in the
// header and «11 – 17 يوليو» in the picker one tap away.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/shared/widgets/week_picker_sheet.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  // westernDate goes through DateFormat, which needs its locale tables
  // loaded before any non-system locale can be formatted.
  setUpAll(() async {
    await initializeDateFormatting('ar');
    await initializeDateFormatting('en');
  });

  group('weeksBetween', () {
    test('runs newest first and lands every entry on a Saturday', () {
      final weeks = weeksBetween(DateTime(2026, 6, 1), DateTime(2026, 8, 19));
      expect(weeks.first, weeks.first.startOfDisplayWeek);
      for (final w in weeks) {
        expect(w.weekday, DateTime.saturday, reason: '$w is not a Saturday');
      }
      for (var i = 1; i < weeks.length; i++) {
        expect(weeks[i].isBefore(weeks[i - 1]), isTrue,
            reason: 'newest first');
        expect(weeks[i - 1].difference(weeks[i]).inDays, 7);
      }
    });

    test('includes the week holding each end, not just whole weeks between',
        () {
      // 19 Aug 2026 is a Wednesday; its week starts Saturday 15 Aug.
      final weeks = weeksBetween(DateTime(2026, 8, 17), DateTime(2026, 8, 19));
      expect(weeks, hasLength(1));
      expect(weeks.single, DateTime(2026, 8, 15));
    });

    test('is capped, so a corrupt earliest date cannot build a huge list', () {
      final weeks = weeksBetween(
        DateTime(1990, 1, 1),
        DateTime(2026, 8, 19),
        maxWeeks: 10,
      );
      expect(weeks, hasLength(10));
    });

    test('an earliest AFTER the latest yields nothing rather than looping',
        () {
      expect(weeksBetween(DateTime(2026, 9, 1), DateTime(2026, 8, 1)), isEmpty);
    });
  });

  group('weekSpanLabel', () {
    test('names the month once when the week sits inside one month', () {
      // Sat 15 Aug 2026 through Fri 21 Aug.
      expect(weekSpanLabel(DateTime(2026, 8, 15), 'en'), '15 – 21 Aug');
    });

    test('names both months when the week straddles a boundary', () {
      // Sat 29 Aug 2026 through Fri 4 Sep. Saying "29 – 4 Aug" would read
      // as a four-day week going backwards.
      expect(weekSpanLabel(DateTime(2026, 8, 29), 'en'), '29 Aug – 4 Sep');
    });

    test('Arabic keeps ASCII digits and puts the day before the month', () {
      final label = weekSpanLabel(DateTime(2026, 7, 11), 'ar');
      expect(label, startsWith('11 – 17 '),
          reason: 'day first, ASCII digits, exactly as the picker chip reads');
      // No Arabic-Indic digits anywhere: those are what made the header and
      // the picker look like two different dates.
      for (final indic in ['٠','١','٢','٣','٤','٥','٦','٧','٨','٩']) {
        expect(label.contains(indic), isFalse, reason: 'found $indic in $label');
      }
    });

    test('a year boundary still names both months', () {
      // Sat 26 Dec 2026 through Fri 1 Jan 2027.
      final label = weekSpanLabel(DateTime(2026, 12, 26), 'en');
      expect(label, '26 Dec – 1 Jan');
    });
  });
}
