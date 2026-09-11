// The offset sheet a habit reminder row opens, under test for the first time.
//
// Three defects lived here (Aziz's IMG 2, 2026-09-11). It opened on قبل for
// every on-time or new reminder, whatever the main step showed, so «في الوقت»
// sat lit beside a lit قبل and one tap on 15 saved BEFORE under a main step
// that said بعد. Its button said «إضافة» on an edit. And flipping قبل and بعد
// unlit the amount and left the button dead, so moving 15 before to 15 after
// took a second tap on 15 (decision B: flipping keeps the amount). Each test
// opens the real sheet through showHabitOffsetSheet, in Arabic, on a phone
// sized view, and reads what a person would see.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/habits/widgets/habit_offset_sheet.dart';
import 'package:grow_daily_v2/shared/widgets/choice_chip_grid.dart';

void main() {
  const ar = S(Locale('ar'));
  const fajr = TimeOfDay(hour: 4, minute: 3);
  const presetLabels = ['5', '10', '15', '30', 'ساعة'];

  setUp(() {
    const dpr = 3.0;
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
    view.physicalSize = const Size(402 * dpr, 874 * dpr);
    view.devicePixelRatio = dpr;
  });

  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  /// Opens the sheet from a real button and hands back a reader for what it
  /// popped with: null while it is open, and null for a dismissal.
  Future<int? Function()> open(
    WidgetTester tester, {
    required int? current,
    TimeOfDay? anchor = fajr,
    bool presets = true,
    bool leanAfter = false,
    bool editing = false,
    String? anchorName = 'الفجر',
  }) async {
    int? result;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: GameTheme.dark,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () async {
                  result = await showHabitOffsetSheet(
                    context,
                    current: current,
                    anchor: anchor,
                    presets: presets,
                    leanAfter: leanAfter,
                    editing: editing,
                    anchorName: anchorName,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return () => result;
  }

  /// The chip wearing [label], as the widget, so its lit state is asserted
  /// rather than inferred from a colour.
  PlainChoiceChip chip(WidgetTester tester, String label) =>
      tester.widget<PlainChoiceChip>(
        find
            .ancestor(
              of: find.text(label),
              matching: find.byType(PlainChoiceChip),
            )
            .first,
      );

  FilledButton button(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byType(FilledButton));

  String buttonLabel(WidgetTester tester) => tester
      .widget<Text>(
        find.descendant(
          of: find.byType(FilledButton),
          matching: find.byType(Text),
        ),
      )
      .data!;

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  group('which side it opens on', () {
    testWidgets(
        'on time with the lean: بعد and «في الوقت» are lit, and 15 saves 15 '
        'after', (tester) async {
      final result =
          await open(tester, current: 0, leanAfter: true, editing: true);

      expect(chip(tester, ar.offsetAfterLabel).selected, isTrue);
      expect(
        chip(tester, ar.offsetBeforeLabel).selected,
        isFalse,
        reason: 'IMG 2 showed قبل lit beside «في الوقت» under a main step '
            'that said بعد',
      );
      expect(chip(tester, ar.leadAtTime).selected, isTrue);

      await tapText(tester, '15');
      expect(result(), 15);
    });

    testWidgets('a new reminder with the lean: 15 saves 15 after',
        (tester) async {
      final result = await open(tester, current: null, leanAfter: true);

      expect(chip(tester, ar.offsetAfterLabel).selected, isTrue);
      for (final label in [ar.leadAtTime, ...presetLabels]) {
        expect(
          chip(tester, label).selected,
          isFalse,
          reason: 'nothing is chosen yet: $label',
        );
      }
      await tapText(tester, '15');
      expect(result(), 15);
    });

    testWidgets(
        'on time without the lean still opens on قبل: 15 saves 15 before',
        (tester) async {
      final result = await open(tester, current: 0, editing: true);

      expect(chip(tester, ar.offsetBeforeLabel).selected, isTrue);
      expect(chip(tester, ar.offsetAfterLabel).selected, isFalse);
      await tapText(tester, '15');
      expect(result(), -15);
    });

    testWidgets(
        'a reminder with a shift opens on its own side, whatever the lean',
        (tester) async {
      await open(tester, current: -15, leanAfter: true, editing: true);

      expect(chip(tester, ar.offsetBeforeLabel).selected, isTrue);
      expect(chip(tester, ar.offsetAfterLabel).selected, isFalse);
      expect(chip(tester, '15').selected, isTrue);
    });
  });

  group('the button', () {
    testWidgets('says «حفظ» when editing', (tester) async {
      await open(tester, current: -15, editing: true);
      expect(buttonLabel(tester), ar.habitOffsetSave);
      expect(buttonLabel(tester), 'حفظ');
    });
  });

  group('flipping keeps the amount (decision B)', () {
    testWidgets(
        '15 before flipped to بعد: 15 stays lit, 4:18 shows, «حفظ» saves 15 '
        'after', (tester) async {
      final result = await open(tester, current: -15, editing: true);
      expect(find.text(ar.remindAtTimePreview('3:48 ص')), findsOneWidget);
      expect(button(tester).onPressed, isNotNull);

      await tapText(tester, ar.offsetAfterLabel);

      expect(chip(tester, ar.offsetAfterLabel).selected, isTrue);
      expect(
        chip(tester, '15').selected,
        isTrue,
        reason: 'the flip used to unlight the amount',
      );
      expect(find.text(ar.remindAtTimePreview('4:18 ص')), findsOneWidget);
      expect(
        button(tester).onPressed,
        isNotNull,
        reason: 'one tap on «حفظ» finishes the change',
      );

      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(result(), 15);
    });

    testWidgets('an hour after flipped to قبل saves an hour before',
        (tester) async {
      final result = await open(tester, current: 60, editing: true);
      await tapText(tester, ar.offsetBeforeLabel);

      expect(chip(tester, 'ساعة').selected, isTrue);
      expect(find.text(ar.remindAtTimePreview('3:03 ص')), findsOneWidget);
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(result(), -60);
    });
  });

  // Guards, not new behaviour: each of these already held before this change
  // and is kept so the changes around it cannot break it. A typed value
  // always carried its own side through a flip, «في الوقت» was lit by its own
  // value whatever the side, an add always opened on «إضافة» with the button
  // waiting, the sheet without presets kept its «في الوقت» button, and a
  // clock time's subtitle never named anything but the time.
  group('what already worked', () {
    testWidgets('a typed 45 before still flips to 45 after', (tester) async {
      final result = await open(tester, current: -45, editing: true);
      await tapText(tester, ar.offsetAfterLabel);

      expect(find.text(ar.remindAtTimePreview('4:48 ص')), findsOneWidget);
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(result(), 45);
    });

    testWidgets('«في الوقت» has no side, so a flip leaves it lit',
        (tester) async {
      await open(tester, current: 0, editing: true);
      await tapText(tester, ar.offsetAfterLabel);
      expect(chip(tester, ar.leadAtTime).selected, isTrue);
    });

    testWidgets('the button says «إضافة» when adding, and waits for an amount',
        (tester) async {
      await open(tester, current: null, leanAfter: true);
      expect(buttonLabel(tester), ar.customReminderAdd);
      expect(button(tester).onPressed, isNull);
    });

    testWidgets('without presets the «في الوقت» button is still there',
        (tester) async {
      await open(tester, current: 20, presets: false, anchorName: null);
      expect(find.widgetWithText(TextButton, ar.leadAtTime), findsOneWidget);
      expect(find.text('15'), findsNothing);
    });

    testWidgets('a clock time keeps its own subtitle', (tester) async {
      await open(
        tester,
        current: 0,
        anchor: const TimeOfDay(hour: 7, minute: 30),
        anchorName: null,
      );
      expect(find.text(ar.habitOffsetFromTime('7:30 ص')), findsOneWidget);
    });
  });

  group('what it draws', () {
    testWidgets('the preset chips use Latin digits', (tester) async {
      await open(tester, current: null);
      for (final label in presetLabels) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      for (final label in ['٥', '١٠', '١٥', '٣٠']) {
        expect(find.text(label), findsNothing, reason: label);
      }
    });

    testWidgets('the subtitle names the prayer and its time', (tester) async {
      await open(tester, current: 0);
      expect(find.text('بالنسبة لوقت الفجر، 4:03 ص'), findsOneWidget);
    });

    testWidgets('with no location it still names the prayer', (tester) async {
      await open(tester, current: -15, anchor: null, editing: true);
      expect(find.text('بالنسبة لوقت الفجر'), findsOneWidget);
      expect(
        find.textContaining('سيتم تذكيرك'),
        findsNothing,
        reason: 'no time to resolve a shift against',
      );
    });
  });
}
