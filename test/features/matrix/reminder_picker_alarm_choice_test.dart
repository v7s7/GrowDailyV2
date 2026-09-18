// «طريقة التنبيه» in a task's reminder picker, for each AlarmChoice the
// task sheets read from alarmChoiceProvider.
//
// An iPhone older than iOS 26 used to get no choice at all, which read as
// broken (reported 2026-09-18). It now gets the same switch as everyone,
// with its alarm cell grey and explaining instead of switching, as does an
// iPhone whose alarm permission was refused; only where there is nothing
// to offer or say, such as the web, is the switch left out.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/providers/alarm_choice_provider.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
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

  final now = DateTime.now();
  final anchor = DateTime(now.year, now.month, now.day + 3, 17);

  Future<List<bool>> pump(WidgetTester tester, AlarmChoice choice) async {
    final changes = <bool>[];
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ar'),
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: GameTheme.light,
      home: Scaffold(
        body: SingleChildScrollView(
          child: ReminderPicker(
            anchorAt: anchor,
            offsets: const {0},
            color: Colors.teal,
            isAr: true,
            canStack: true,
            onPickAnchor: () {},
            onClear: () {},
            onToggleOffset: (_) {},
            onLocked: () {},
            alarmChoice: choice,
            onAlarmChanged: changes.add,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return changes;
  }

  testWidgets('where alarms ring, the switch is drawn and «منبّه» picks',
      (tester) async {
    final changes = await pump(tester, AlarmChoice.available);

    expect(find.text(ar.reminderStyleSection), findsOneWidget);
    await tester.tap(find.text(ar.reminderStyleAlarm));
    await tester.pumpAndSettle();
    expect(changes, [true]);
  });

  testWidgets(
      'on an older iPhone the switch is drawn and «منبّه» explains instead',
      (tester) async {
    final changes = await pump(tester, AlarmChoice.needsNewerIos);

    expect(find.text(ar.reminderStyleSection), findsOneWidget);
    await tester.tap(find.text(ar.reminderStyleAlarm));
    await tester.pumpAndSettle();
    expect(changes, isEmpty);
    expect(find.text(ar.alarmNeedsNewerIos), findsOneWidget);
  });

  testWidgets(
      'with the alarm permission refused, the switch is drawn and «منبّه» '
      'says where to turn it on', (tester) async {
    final changes = await pump(tester, AlarmChoice.permissionDenied);

    expect(find.text(ar.reminderStyleSection), findsOneWidget);
    await tester.tap(find.text(ar.reminderStyleAlarm));
    await tester.pumpAndSettle();
    expect(changes, isEmpty);
    expect(find.text(ar.alarmPermissionDenied), findsOneWidget);
  });

  testWidgets('with nothing to offer or say, the switch is left out',
      (tester) async {
    await pump(tester, AlarmChoice.hidden);

    expect(find.text(ar.reminderStyleSection), findsNothing);
    expect(find.text(ar.reminderStyleAlarm), findsNothing);
  });
}
