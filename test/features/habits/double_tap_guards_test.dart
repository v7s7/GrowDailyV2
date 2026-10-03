// A double tap must count as one tap, wherever a button turns into a
// different action under the finger.
//
// Add Habit's footer button keeps its place from step to step: the second tap
// of a double tap on «متابعة» on step 2 landed on step 3's «أضف العادة» and
// saved the habit before its reminder step had been seen.
//
// A plan's «ابدأ الخطة» turns into «إيقاف الخطة» the moment it lands: a
// double tap started the plan and then stopped it, and stopping removes every
// habit of the plan never once completed, which a moment after starting is
// all of them.
import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    show AndroidFlutterLocalNotificationsPlugin;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/services/notification_service.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/habits/catalog/habit_plans.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';
import 'package:grow_daily_v2/features/habits/widgets/add_habit_sheet.dart';
import 'package:grow_daily_v2/features/habits/widgets/plan_picker_sheet.dart';
import 'package:grow_daily_v2/features/premium/notifiers/premium_notifier.dart';

import 'support/add_habit_flow.dart';

void main() {
  const dpr = 3.0;
  const ar = S(Locale('ar'));
  late Directory tmp;
  late ProviderContainer container;

  setUpAll(() async {
    await preloadIdeas();
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Bahrain'));
    AndroidFlutterLocalNotificationsPlugin.registerWith();
  });

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'),
      (call) async => false,
    );
    NotificationService.instance.celebrationsEnabled = false;
    GoogleFonts.config.allowRuntimeFetching = false;
    tmp = await Directory.systemTemp.createTemp('double_tap_guards_test_');
    Hive.init(tmp.path);
    await Hive.openBox<dynamic>('box_settings', bytes: Uint8List(0));
    await Hive.openBox<dynamic>('box_daily_logs', bytes: Uint8List(0));
    await Hive.openBox<dynamic>('box_habits', bytes: Uint8List(0));
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
    view.physicalSize = const Size(390 * dpr, 844 * dpr);
    view.devicePixelRatio = dpr;
    container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
        premiumAccessProvider.overrideWithValue(true),
      ],
    );
    await container.read(authStateProvider.future);
    container.read(customHabitsProvider);
    container.read(activeCatalogProvider);
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });

  tearDown(() async {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
    container.dispose();
    await Hive.close();
    await tmp.delete(recursive: true);
  });

  /// [page] on a pushed route, so a save's pop has somewhere to go.
  Future<void> open(WidgetTester tester, Widget page) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          navigatorKey: navigator,
          locale: const Locale('ar'),
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: GameTheme.dark,
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      ),
    );
    unawaited(
      navigator.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => Scaffold(body: page)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a double tap on «متابعة» does not add the habit',
      (tester) async {
    await open(tester, const AddHabitSheet());
    await toOften(tester, ar);
    await pickOften(tester, ar.oftenEveryDay);

    // The two taps of one double tap, 120ms apart, on the same spot.
    final footer = find.byType(FilledButton).last;
    final spot = tester.getCenter(footer);
    await tester.tapAt(spot);
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tapAt(spot);
    await tester.pumpAndSettle();

    expect(container.read(customHabitsProvider), isEmpty,
        reason: 'the reminder step has not been seen yet');
    expect(find.text(ar.addHabitAction), findsOneWidget,
        reason: 'still on «التذكير (اختياري)», waiting for a real tap');

    // A real tap once the step is in place adds it, once.
    await pressPrimary(tester);
    expect(container.read(customHabitsProvider), hasLength(1));
  });

  testWidgets('a double tap on «ابدأ الخطة» leaves the plan started',
      (tester) async {
    await open(tester, const PlanPickerSheet());
    final plan = habitPlans.first;
    await tester.tap(find.text(plan.nameAr).first);
    await tester.pumpAndSettle();

    final start = find.widgetWithText(FilledButton, ar.startPlan);
    await tester.ensureVisible(start);
    await tester.pumpAndSettle();
    final spot = tester.getCenter(start);
    await tester.tapAt(spot);
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.widgetWithText(FilledButton, ar.deactivatePlan), findsOneWidget,
        reason: 'the button has already turned into its opposite');
    await tester.tapAt(spot);
    await tester.pumpAndSettle();

    expect(container.read(activeCatalogProvider).toSet(),
        containsAll(plan.catalogIds),
        reason: 'the second tap of the same double tap did not stop it');

    // A deliberate stop, after the hold, still works.
    await tester.pump(const Duration(milliseconds: 700));
    await tester.tapAt(spot);
    await tester.pumpAndSettle();
    expect(
      container.read(activeCatalogProvider).toSet().intersection(
            plan.catalogIds.toSet(),
          ),
      isEmpty,
    );
  });
}
