// The "إلى متى؟" chooser, driven the way a person drives it.
//
// The whole promise of this sheet is that it does not change pausing for
// anyone who does not want it: the manual option is preselected, so
// confirming straight through must produce exactly the pause that existed
// before any of this was added. These tests hold it to that.
//
// Verified here rather than on the simulator because Flutter's long-press
// recognizer does not fire from the simulator's synthetic touch events, so
// the sheet cannot be opened by driving the real app from outside it.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/features/habits/widgets/pause_until_sheet.dart';

void main() {
  /// Opens the sheet on first frame and records what it returned.
  Widget harness(List<PauseUntilChoice> out, {Locale locale = const Locale('ar')}) =>
      MaterialApp(
        locale: locale,
        // The same delegates main.dart installs. Without them Material has
        // no Arabic localizations at all and every sheet in this file fails
        // to build, which says nothing about the sheet itself.
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('ar'), Locale('en')],
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  out.add(await showPauseUntilSheet(context,
                      habitName: 'تمرين'));
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

  Future<void> open(WidgetTester tester, List<PauseUntilChoice> out,
      {Locale locale = const Locale('ar')}) async {
    await tester.pumpWidget(harness(out, locale: locale));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('opens on the manual option, naming the habit', (tester) async {
    final out = <PauseUntilChoice>[];
    await open(tester, out);

    expect(find.text('إلى متى؟'), findsOneWidget);
    expect(find.textContaining('تمرين'), findsWidgets);
    // All four alternatives are offered, not hidden behind a menu.
    expect(find.text('أنا أقرر'), findsOneWidget);
    expect(find.text('أسبوع'), findsOneWidget);
    expect(find.text('أسبوعين'), findsOneWidget);
    expect(find.text('شهر'), findsOneWidget);
    expect(find.text('تاريخ ووقت'), findsOneWidget);
  });

  testWidgets('confirming without choosing is the old manual pause',
      (tester) async {
    // The compatibility guarantee. One extra tap, identical outcome.
    final out = <PauseUntilChoice>[];
    await open(tester, out);

    await tester.tap(find.text('إيقاف مؤقت'));
    await tester.pumpAndSettle();

    expect(out.single.confirmed, isTrue);
    expect(out.single.at, isNull,
        reason: 'no date means resumed by hand, exactly as before');
  });

  testWidgets('dismissing pauses nothing at all', (tester) async {
    // "No date" and "no thanks" are different answers, and the caller must
    // be able to tell them apart or cancelling would still archive.
    final out = <PauseUntilChoice>[];
    await open(tester, out);

    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();

    expect(out.single.confirmed, isFalse);
    expect(out.single.at, isNull);
  });

  testWidgets('a preset returns that preset\'s date', (tester) async {
    final out = <PauseUntilChoice>[];
    await open(tester, out);

    await tester.tap(find.text('أسبوعين'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إيقاف مؤقت'));
    await tester.pumpAndSettle();

    expect(out.single.confirmed, isTrue);
    final at = out.single.at;
    expect(at, isNotNull);
    expect(at!.difference(DateTime.now().effectiveDay).inDays, 14);
    // Presets carry no meaningful hour, so they land at the day's start — the
    // cutoff hour (6am), not calendar midnight, since 00:00 belongs to the
    // previous effective day (see ResumePreset.dateFrom).
    expect(at.hour, kDayCutoffHour);
  });

  testWidgets('switching back to manual clears an already-picked preset',
      (tester) async {
    // Otherwise someone who explores the options and then changes their
    // mind would still leave with a date they had rejected.
    final out = <PauseUntilChoice>[];
    await open(tester, out);

    await tester.tap(find.text('شهر'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('أنا أقرر'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إيقاف مؤقت'));
    await tester.pumpAndSettle();

    expect(out.single.at, isNull);
  });

  testWidgets('the sheet reads in English too', (tester) async {
    final out = <PauseUntilChoice>[];
    await open(tester, out, locale: const Locale('en'));
    expect(find.text('Until when?'), findsOneWidget);
    expect(find.text('I decide'), findsOneWidget);
    expect(find.text('Two weeks'), findsOneWidget);
  });
}
