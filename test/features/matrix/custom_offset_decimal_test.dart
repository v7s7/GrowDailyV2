// A task's custom reminder, typed as a fraction of an hour.
//
// The field took whole numbers only, on a keypad with no point, so a
// 4.5-hour reminder had to be worked out in minutes, and Aziz's came out as
// 260, ten short (2026-09-18). Add Habit's offset sheet reads the same way;
// its test is in habit_offset_sheet_test.dart.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/matrix/widgets/custom_offset_sheet.dart';
import 'package:grow_daily_v2/features/matrix/widgets/reminder_picker.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  const ar = S(Locale('ar'));

  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('ar');
  });

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    // Wider than a phone, as reminder_dates_arabic_test.dart does for this
    // sheet: the test font draws every glyph a full em wide.
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
    view.physicalSize = const Size(600 * 3, 874 * 3);
    view.devicePixelRatio = 3;
  });

  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  // Three days out at 17:00, so nothing it lands on has passed.
  final now = DateTime.now();
  final anchor = DateTime(now.year, now.month, now.day + 3, 17);

  Future<List<int>> open(WidgetTester tester) async {
    final toggled = <int>[];
    await tester.pumpWidget(MaterialApp(
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
          builder: (context) => TextButton(
            onPressed: () => showCustomOffsetSheet(
              context,
              anchor: anchor,
              offsets: const {},
              isAfter: false,
              color: Colors.teal,
              isAr: true,
              canStack: () => true,
              onToggle: toggled.add,
              onDirectionChanged: (_) {},
              onLocked: () {},
              maxOffsets: 5,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return toggled;
  }

  testWidgets('4.5 under ساعات adds four and a half hours before',
      (tester) async {
    final toggled = await open(tester);

    await tester.enterText(find.byType(TextField), '4.5');
    await tester.tap(find.text(ar.unitHours));
    await tester.pumpAndSettle();

    // 17:00 less four and a half hours is 12:30.
    expect(find.textContaining('12:30'), findsOneWidget);
    await tester.tap(find.text(ar.customReminderAdd));
    await tester.pumpAndSettle();
    expect(toggled, [-270]);
    expect(find.text(ar.customReminderTitle), findsNothing,
        reason: 'adding the one reminder closes the sheet');
  });

  // «إضافة» and «تم» on one page let a typed value be dropped by tapping
  // «تم» (Aziz, 2026-09-18). The sheet has one button now.
  testWidgets('one button, and a swipe away adds nothing', (tester) async {
    final toggled = await open(tester);

    expect(find.byType(FilledButton), findsOneWidget);
    expect(find.text(ar.matrixDone), findsNothing);

    await tester.enterText(find.byType(TextField), '4.5');
    await tester.pumpAndSettle();
    // Dismissed the way a sheet is, by the scrim above it.
    await tester.tapAt(const Offset(300, 40));
    await tester.pumpAndSettle();
    expect(find.text(ar.customReminderTitle), findsNothing);
    expect(toggled, isEmpty);
  });

  testWidgets('the keypad offers a point', (tester) async {
    await open(tester);
    expect(
      tester.widget<TextField>(find.byType(TextField)).keyboardType,
      const TextInputType.numberWithOptions(decimal: true),
    );
  });

  // What it adds shows in the task sheet as its own chip, said the way the
  // row and the notification say it: «4 ساعات ونص», not «270 دقيقة».
  testWidgets('the task sheet names the added 4.5 hours in hours',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ar'),
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: GameTheme.dark,
      home: Scaffold(
        body: SingleChildScrollView(
          child: ReminderPicker(
            anchorAt: anchor,
            offsets: const {270},
            color: Colors.teal,
            isAr: true,
            canStack: true,
            onPickAnchor: () {},
            onClear: () {},
            onToggleOffset: (_) {},
            onLocked: () {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('4 ساعات ونص'), findsOneWidget);
    expect(find.textContaining('270'), findsNothing);
  });

  /// The task sheet's reminder grid carrying [offsets], in [locale].
  Future<void> pumpGrid(
    WidgetTester tester,
    Set<int> offsets, {
    String locale = 'ar',
  }) async {
    await tester.pumpWidget(MaterialApp(
      locale: Locale(locale),
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: GameTheme.dark,
      home: Scaffold(
        body: SingleChildScrollView(
          child: ReminderPicker(
            anchorAt: anchor,
            offsets: offsets,
            color: Colors.teal,
            isAr: locale == 'ar',
            canStack: true,
            onPickAnchor: () {},
            onClear: () {},
            onToggleOffset: (_) {},
            onLocked: () {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  // «12 ساعة و45 دقيقة» was cut to «12 ساعة و45…» in its chip on the phone.
  testWidgets('hours and counted minutes take the short chip form',
      (tester) async {
    await pumpGrid(tester, const {765});
    expect(find.text('12 س و45 د'), findsOneWidget);
  });

  testWidgets('English chips are always short past an hour', (tester) async {
    await pumpGrid(tester, const {270}, locale: 'en');
    expect(find.text('4h 30m'), findsOneWidget);
  });
}
