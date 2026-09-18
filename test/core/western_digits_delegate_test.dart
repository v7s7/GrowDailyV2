// What DateFormat prints once the app's localization delegates have loaded,
// and the shared date formatters that now go through westernDate.
//
// GlobalMaterialLocalizations.delegate writes flutter_localizations' own
// date symbols into intl's global table on its first load, and their 'ar'
// set carries the Arabic-Indic zero digit. From then on, for the rest of
// the process, DateFormat('d', 'ar') prints «١٨». A plain test process
// never loads those symbols, which is why every unit test printed "18" and
// none of them saw what the app drew. So each case here pumps a MaterialApp
// under the real delegates first, the way main.dart builds the app.
//
// Kept apart from western_digits_test.dart on purpose: that file pins what
// intl returns BEFORE the delegates load, and the load is process-wide, so
// one pump in the same file would flip its answer.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'package:grow_daily_v2/core/utils/western_digits.dart';
import 'package:grow_daily_v2/features/habits/notifiers/habit_resume_notifier.dart';
import 'package:grow_daily_v2/features/matrix/widgets/reminder_picker.dart';

final _arabicIndic = RegExp('[٠-٩]');

/// The app's own order: intl's data first (main.dart's
/// initializeDateFormatting), then MaterialApp under the real delegates.
Future<void> _loadAppDelegates(WidgetTester tester) async {
  await tester.runAsync(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('ar');
  });
  await tester.pumpWidget(const MaterialApp(
    locale: Locale('ar'),
    supportedLocales: [Locale('en'), Locale('ar')],
    localizationsDelegates: [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: SizedBox(),
  ));
}

void main() {
  // Friday 18 September 2026, 21:05.
  final fri = DateTime(2026, 9, 18, 21, 5);

  group('under the delegates', () {
    testWidgets('a raw DateFormat prints Arabic-Indic digits', (tester) async {
      await _loadAppDelegates(tester);
      // Pinned so the day Flutter changes this is noticed: westernDate would
      // then be a no-op again, and the reason for it would be gone.
      expect(DateFormat('d MMMM', 'ar').format(fri), '١٨ سبتمبر');
      expect(DateFormat('h:mm a', 'ar').format(fri), '٩:٠٥ م');
      expect(DateFormat('d MMMM', 'en').format(fri), '18 September');
    });

    testWidgets('westernDate and weekdayDateLabel print Latin ones',
        (tester) async {
      await _loadAppDelegates(tester);
      expect(westernDate(fri, 'd MMMM', 'ar'), '18 سبتمبر');
      expect(westernDate(fri, 'h:mm a', 'ar'), '9:05 م');
      expect(weekdayDateLabel(fri, isAr: true, locale: 'ar'),
          'الجمعة، 18 سبتمبر');
      expect(weekdayDateLabel(fri, isAr: false, locale: 'en'),
          'Friday, Sep 18');
    });
  });

  group('formatReminderMoment (task reminder rows and chips)', () {
    final now = DateTime(2026, 9, 14, 9);

    testWidgets('Arabic: Latin digits, the day before the month',
        (tester) async {
      await _loadAppDelegates(tester);
      expect(formatReminderMoment(fri, true, now: now), '18 سبتمبر · 9:05 م',
          reason: 'drew «سبتمبر ١٨ · ٩:٠٥ م»');
      expect(
        formatReminderMoment(DateTime(2026, 9, 14, 17), true, now: now),
        'اليوم · 5:00 م',
      );
      expect(
        formatReminderMoment(DateTime(2026, 9, 15, 9, 30), true, now: now),
        'غدًا · 9:30 ص',
      );
    });

    testWidgets('English is unchanged', (tester) async {
      await _loadAppDelegates(tester);
      expect(formatReminderMoment(fri, false, now: now), 'Sep 18 · 9:05 PM');
    });
  });

  group('formatReminderDay (the time wheel title)', () {
    testWidgets('Arabic spells the day out in Latin digits', (tester) async {
      await _loadAppDelegates(tester);
      expect(
        formatReminderDay(fri, true, now: DateTime(2026, 9, 14)),
        'الجمعة، 18 سبتمبر',
        reason: 'drew «الجمعة، ١٨ سبتمبر»',
      );
    });
  });

  group('formatResumeDate (pause sheet, badges)', () {
    testWidgets('Arabic, with and without the hour', (tester) async {
      await _loadAppDelegates(tester);
      expect(formatResumeDate(fri, true), 'الجمعة 18 سبتمبر');
      expect(formatResumeDate(fri, true, withTime: true),
          'الجمعة 18 سبتمبر، 9:05 م',
          reason: 'drew «الجمعة ١٨ سبتمبر، ٩:٠٥ م»');
      expect(_arabicIndic.hasMatch(formatResumeDate(fri, true)), isFalse);
    });

    testWidgets('English is unchanged', (tester) async {
      await _loadAppDelegates(tester);
      expect(formatResumeDate(fri, false, withTime: true),
          'Friday 18 September, 9:05 PM');
    });
  });
}
