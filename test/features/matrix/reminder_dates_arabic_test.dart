// A task's reminder controls, in Arabic under the real localization
// delegates.
//
// Every time and date these draw came from a raw DateFormat, which in the
// app printed Arabic-Indic digits: the reminder row «سبتمبر ٢١ · ٥:٠٠ م»
// (month first, too), the preview line under the chips, the time beside
// each reminder in the custom sheet, the wheel's «الاثنين، ٢١ سبتمبر» and
// its «أقرب وقت: ٣:٠٥ م». The chips themselves were converted to
// Arabic-Indic on purpose, to match those rows («١٥»), so once the rows
// turned Latin the chips had to follow or one row would carry both. The
// notification copy keeps its own digits and is not drawn here.
import 'package:flutter/cupertino.dart' show CupertinoDatePicker;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'package:grow_daily_v2/features/habits/widgets/pause_until_sheet.dart';
import 'package:grow_daily_v2/features/habits/notifiers/habit_resume_notifier.dart';
import 'package:grow_daily_v2/features/matrix/widgets/custom_offset_sheet.dart';
import 'package:grow_daily_v2/features/matrix/widgets/reminder_picker.dart';

/// Anything drawn on screen, plain or rich, that carries a digit ٠ to ٩.
final _arabicIndicText = find.byWidgetPredicate((w) =>
    w is RichText && RegExp('[٠-٩]').hasMatch(w.text.toPlainText()));

/// The same, outside the Cupertino wheel. The wheel's hours and minutes are
/// drawn by Flutter's own CupertinoLocalizations, which format them with
/// the same 'ar' date symbols and so still print «٠٥». That is the system
/// picker, not a pattern in this app, and is reported rather than patched
/// here (see the note in western_digits.dart).
final _arabicIndicOutsideWheel = find.byWidgetPredicate((w) =>
    w is RichText &&
    RegExp('[٠-٩]').hasMatch(w.text.toPlainText()) &&
    !_insideWheel(w));

bool _insideWheel(Widget w) => find
    .ancestor(
      of: find.byWidget(w),
      matching: find.byType(CupertinoDatePicker),
    )
    .evaluate()
    .isNotEmpty;

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('ar');
  });

  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
    view.physicalSize = const Size(402 * 3, 874 * 3);
    view.devicePixelRatio = 3;
  });

  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  Widget app(Widget home) => MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(body: home),
      );

  // Three days out, so every label dates the day instead of saying اليوم.
  final now = DateTime.now();
  final day = DateTime(now.year, now.month, now.day + 3);
  final anchor = day.add(const Duration(hours: 17));
  // Names only, no digits; read inside each test, after setUpAll has
  // loaded the locale data.
  String weekday() => DateFormat('EEEE', 'ar').format(day);
  String month() => DateFormat('MMMM', 'ar').format(day);

  testWidgets('the Add Task reminder section: row, chips and preview',
      (tester) async {
    await tester.pumpWidget(app(SingleChildScrollView(
      child: ReminderPicker(
        anchorAt: anchor,
        offsets: const {-15, -45},
        color: Colors.teal,
        isAr: true,
        canStack: true,
        onPickAnchor: () {},
        onClear: () {},
        onToggleOffset: (_) {},
        onLocked: () {},
      ),
    )));
    await tester.pumpAndSettle();

    expect(find.text('${day.day} ${month()} · 5:00 م'), findsOneWidget,
        reason: 'the reminder row, day before month');
    for (final chip in ['5', '10', '15', '30']) {
      expect(find.text(chip), findsOneWidget, reason: 'the «$chip» chip');
    }
    expect(find.text('45 دقيقة'), findsOneWidget,
        reason: 'the hand-typed offset gets its own chip');
    expect(
      find.text('${day.day} ${month()} · 4:15 م   ·   '
          '${day.day} ${month()} · 4:45 م   ·   '
          '${day.day} ${month()} · 5:00 م'),
      findsOneWidget,
      reason: 'the preview line',
    );
    expect(_arabicIndicText, findsNothing);
  });

  // The sheet adds one reminder and closes (2026-09-18), so its own list of
  // reminders is gone; the moment a typed value lands on is its one date.
  testWidgets('the custom offset sheet dates the moment it will add',
      (tester) async {
    // Wider than a phone: the test font draws every glyph a full em wide.
    tester.view.physicalSize = const Size(600 * 3, 874 * 3);
    await tester.pumpWidget(app(Builder(
      builder: (context) => TextButton(
        onPressed: () => showCustomOffsetSheet(
          context,
          anchor: anchor,
          offsets: {-15},
          isAfter: false,
          color: Colors.teal,
          isAr: true,
          canStack: () => true,
          onToggle: (_) {},
          onDirectionChanged: (_) {},
          onLocked: () {},
          maxOffsets: 5,
        ),
        child: const Text('open'),
      ),
    )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // 20 rather than 15: the task already has 15 before, which the sheet
    // answers with "already added" in place of a moment.
    await tester.enterText(find.byType(TextField), '20');
    await tester.pumpAndSettle();

    expect(find.text('${day.day} ${month()} · 4:40 م'), findsOneWidget);
    expect(_arabicIndicText, findsNothing);
  });

  testWidgets('the time wheel names the day and its floor', (tester) async {
    await tester.pumpWidget(app(Builder(
      builder: (context) => TextButton(
        onPressed: () => showReminderTimeSheet(
          context,
          day: day,
          initial: day.add(const Duration(hours: 16, minutes: 4)),
          floor: day.add(const Duration(hours: 15, minutes: 5)),
        ),
        child: const Text('open'),
      ),
    )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('${weekday()}، ${day.day} ${month()}'), findsOneWidget);
    expect(find.text('أقرب وقت: 3:05 م'), findsOneWidget);
    expect(_arabicIndicOutsideWheel, findsNothing);
  });

  testWidgets('the pause sheet dates each preset in Latin digits',
      (tester) async {
    await tester.pumpWidget(app(Builder(
      builder: (context) => TextButton(
        onPressed: () => showPauseUntilSheet(context, habitName: 'تمرين'),
        child: const Text('open'),
      ),
    )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    for (final preset in ResumePreset.values) {
      final back = preset.dateFrom(DateTime.now());
      final label = 'ترجع ${DateFormat('EEEE', 'ar').format(back)} '
          '${back.day} ${DateFormat('MMMM', 'ar').format(back)}';
      expect(find.text(label), findsOneWidget, reason: preset.name);
    }
    expect(_arabicIndicText, findsNothing);
  });
}
