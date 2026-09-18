// «طريقة التنبيه» where no alarm can ring (ReminderStyleChoice with an
// AlarmChoice other than available): an iPhone older than iOS 26, or one
// whose alarm permission was refused.
//
// The choice used to be hidden wherever an alarm could not be made, and on
// an iPhone 14 not yet updated to iOS 26 that read as broken: neither
// «إشعار» nor «منبّه», and nothing said an update would bring them
// (reported 2026-09-18). Now the switch is drawn the same everywhere, and
// on such a phone a tap on «منبّه» explains instead of switching.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/providers/alarm_choice_provider.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/shared/widgets/reminder_style_choice.dart';

void main() {
  const ar = S(Locale('ar'));

  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  /// The switch as a sheet holds it: [alarm] is the sheet's value, and
  /// every onChanged the switch sends lands in [changes] and, like a sheet
  /// that got its permission, becomes the new value.
  Future<List<bool>> pump(
    WidgetTester tester, {
    required bool alarm,
    required AlarmChoice choice,
    double width = 402,
  }) async {
    final changes = <bool>[];
    var value = alarm;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ar'),
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: GameTheme.light,
      // Pinned to the top, so the note growing in under the switch never
      // moves the switch itself.
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: width - 40,
            child: StatefulBuilder(
              builder: (context, setState) => ReminderStyleChoice(
                alarm: value,
                accent: GameColors.gold,
                alarmChoice: choice,
                onChanged: (next) {
                  changes.add(next);
                  setState(() => value = next);
                },
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return changes;
  }

  /// The opacity the cell holding [label] is drawn at: 1 when nothing dims
  /// it, 0.35 when it is greyed out like an offset chip that cannot be
  /// picked.
  double opacityOf(WidgetTester tester, String label) {
    final dim = find.ancestor(
      of: find.text(label),
      matching: find.byType(Opacity),
    );
    return dim.evaluate().isEmpty
        ? 1
        : tester.widget<Opacity>(dim.first).opacity;
  }

  Alignment highlight(WidgetTester tester) => tester
      .widget<AnimatedAlign>(find.byType(AnimatedAlign))
      .alignment
      .resolve(TextDirection.rtl);

  testWidgets('where an alarm can ring, «منبّه» is picked with one tap',
      (tester) async {
    final changes = await pump(tester, alarm: false, choice: AlarmChoice.available);

    await tester.tap(find.text(ar.reminderStyleAlarm));
    await tester.pumpAndSettle();

    expect(changes, [true]);
    expect(find.text(ar.reminderStyleAlarmHint), findsOneWidget);
    expect(find.text(ar.alarmNeedsNewerIos), findsNothing);
    expect(opacityOf(tester, ar.reminderStyleAlarm), 1,
        reason: 'nothing is greyed where an alarm can ring');
  });

  testWidgets(
      'on an older iPhone both cells are drawn, and nothing is explained '
      'before a tap', (tester) async {
    await pump(tester, alarm: false, choice: AlarmChoice.needsNewerIos);

    expect(find.text(ar.reminderStyleSection), findsOneWidget);
    expect(find.text(ar.reminderStyleNotification), findsOneWidget);
    expect(find.text(ar.reminderStyleAlarm), findsOneWidget);
    expect(find.text(ar.alarmNeedsNewerIos), findsNothing);
    expect(opacityOf(tester, ar.reminderStyleAlarm), 0.35,
        reason: '«منبّه» is grey: it cannot be chosen on this phone');
    expect(opacityOf(tester, ar.reminderStyleNotification), 1);
  });

  testWidgets(
      'on an older iPhone a tap on «منبّه» explains and never switches',
      (tester) async {
    final changes =
        await pump(tester, alarm: false, choice: AlarmChoice.needsNewerIos);
    final before = highlight(tester);

    await tester.tap(find.text(ar.reminderStyleAlarm));
    await tester.pumpAndSettle();

    expect(changes, isEmpty,
        reason: 'the sheet must never be told alarm on a phone that '
            'cannot ring one');
    expect(highlight(tester), before,
        reason: 'the highlight stays on «إشعار»');
    expect(find.text(ar.alarmNeedsNewerIos), findsOneWidget);
    expect(find.text(ar.reminderStyleAlarmHint), findsNothing,
        reason: '"rings even on silent" would be false on this phone');

    // Asking again keeps the one note and still changes nothing.
    await tester.tap(find.text(ar.reminderStyleAlarm));
    await tester.pumpAndSettle();
    expect(changes, isEmpty);
    expect(find.text(ar.alarmNeedsNewerIos), findsOneWidget);
  });

  testWidgets('the cell shakes, then comes to rest where it was',
      (tester) async {
    await pump(tester, alarm: false, choice: AlarmChoice.needsNewerIos);
    final label = find.text(ar.reminderStyleAlarm);
    final rest = tester.getCenter(label);

    await tester.tap(label);
    await tester.pump(); // the shake's first frame, at its start
    await tester.pump(const Duration(milliseconds: 40));
    expect(tester.getCenter(label).dx, isNot(closeTo(rest.dx, 0.5)),
        reason: 'mid-shake the label is off its resting place');

    await tester.pumpAndSettle();
    expect(tester.getCenter(label), rest);
  });

  testWidgets(
      'an alarm set on another device shows this phone\'s note in place of '
      'the hint, and «إشعار» still switches back', (tester) async {
    final changes =
        await pump(tester, alarm: true, choice: AlarmChoice.needsNewerIos);

    expect(find.text(ar.alarmNeedsNewerIos), findsOneWidget);
    expect(find.text(ar.reminderStyleAlarmHint), findsNothing);
    expect(opacityOf(tester, ar.reminderStyleAlarm), 1,
        reason: 'a chosen cell never dims, as an offset chip never does');

    await tester.tap(find.text(ar.reminderStyleNotification));
    await tester.pumpAndSettle();
    expect(changes, [false]);
  });

  testWidgets('a screen reader hears why before tapping', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, alarm: false, choice: AlarmChoice.needsNewerIos);

    expect(
      tester.getSemantics(
          find.bySemanticsLabel(RegExp(ar.reminderStyleAlarm))),
      containsSemantics(
        hint: ar.alarmNeedsNewerIos,
        isButton: true,
        hasEnabledState: true,
        isEnabled: false,
      ),
    );
    semantics.dispose();
  });

  testWidgets(
      'with the alarm permission refused, «منبّه» is grey and says where to '
      'turn it on', (tester) async {
    final changes =
        await pump(tester, alarm: false, choice: AlarmChoice.permissionDenied);
    expect(opacityOf(tester, ar.reminderStyleAlarm), 0.35);

    await tester.tap(find.text(ar.reminderStyleAlarm));
    await tester.pumpAndSettle();

    expect(changes, isEmpty,
        reason: 'a refused permission is not asked again from here');
    expect(find.text(ar.alarmPermissionDenied), findsOneWidget);
    expect(find.text(ar.alarmNeedsNewerIos), findsNothing);
  });

  testWidgets('before anyone has been asked, «منبّه» is live', (tester) async {
    await pump(tester, alarm: false, choice: AlarmChoice.available);
    expect(opacityOf(tester, ar.reminderStyleAlarm), 1,
        reason: 'grey only below iOS 26 or with the permission refused');
  });

  // The oldest iPhones that can hold the app (iOS 15, the first iPhone SE)
  // are 320 points wide. An overflow is itself the failure here.
  testWidgets('the note wraps on a 320-point phone', (tester) async {
    const dpr = 2.0;
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
    view.physicalSize = const Size(320 * dpr, 568 * dpr);
    view.devicePixelRatio = dpr;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);

    await pump(tester,
        alarm: false, choice: AlarmChoice.needsNewerIos, width: 320);
    await tester.tap(find.text(ar.reminderStyleAlarm));
    await tester.pumpAndSettle();

    expect(find.text(ar.alarmNeedsNewerIos), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
