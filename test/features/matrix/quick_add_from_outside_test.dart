// The quick add asked for from outside the app: the Lock Screen's Add Task
// control and the Matrix widget's «+» (requestedMatrixQuickAddProvider,
// MatrixScreen._openQuickAdd). Aziz, 2026-10-03, from the control on his
// phone: "the keyboard open before the app loads, and also it didnt accept
// the task and when i click the x mark, it was in habit page".
//
// Pinned, one per symptom:
//  * the sheet (and so its keyboard) waits for the launch curtain to lift,
//    and opens once it has, with the request used up;
//  * a task typed in it is added even when the Tasks page under it has gone
//    (the bar's page moved), where the screen's own ref used to throw;
//  * closing it then asks for Tasks again, so it closes onto Tasks.
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/providers/home_tab_provider.dart';
import 'package:grow_daily_v2/core/providers/nav_layout_provider.dart'
    show NavTab;
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/launch/launch_curtain_up.dart';
import 'package:grow_daily_v2/features/matrix/notifiers/matrix_notifier.dart';
import 'package:grow_daily_v2/features/matrix/screens/matrix_screen.dart';
import 'package:hive/hive.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late ProviderContainer container;

  // Real I/O here, never inside a test (see matrix_add_task_test.dart).
  setUp(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('ar');
    tmp = await Directory.systemTemp.createTemp('quick_add_test_');
    Hive.init(tmp.path);
    await Hive.openBox<dynamic>('box_settings');
    container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
      ],
    );
    await container.read(authStateProvider.future);
  });

  tearDown(() => container.dispose());

  /// Frames, not pumpAndSettle: the empty quadrants' «+» breathes forever.
  Future<void> settle(WidgetTester tester, {int frames = 10}) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Whether the Tasks page is in the tree; the shell's PageView keeps only
  /// the page showing, and this stands in for it moving.
  final tasksShowing = ValueNotifier<bool>(true);

  Future<void> pumpApp(WidgetTester tester) async {
    tasksShowing.value = true;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: GameTheme.light,
          home: ValueListenableBuilder<bool>(
            valueListenable: tasksShowing,
            builder: (_, showing, __) =>
                showing ? const MatrixScreen() : const Text('Habits page'),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  /// What the deep-link handler (main.dart _openFromOutside) sets.
  void askForQuickAdd() {
    container.read(requestedMatrixQuickAddProvider.notifier).state = false;
    container.read(requestedMatrixQuickAddProvider.notifier).state = true;
  }

  final field = find.widgetWithText(TextField, 'What needs to be done?');

  testWidgets('under the curtain the sheet waits, and opens once it lifts',
      (tester) async {
    container.read(launchCurtainUpProvider.notifier).state = true;
    await pumpApp(tester);
    askForQuickAdd();
    await settle(tester);

    expect(field, findsNothing,
        reason: 'no sheet, so no keyboard, while Doum covers the app');
    expect(container.read(requestedMatrixQuickAddProvider), isTrue,
        reason: 'still asked for');

    container.read(launchCurtainUpProvider.notifier).state = false;
    await settle(tester, frames: 12); // kLaunchSettle, then the sheet
    expect(field, findsOneWidget);
    expect(container.read(requestedMatrixQuickAddProvider), isFalse,
        reason: 'used up as the sheet opened');
  });

  testWidgets('with no curtain it opens at once, and only once',
      (tester) async {
    await pumpApp(tester);
    askForQuickAdd();
    askForQuickAdd(); // the same link twice
    await settle(tester);
    expect(field, findsOneWidget);
  });

  testWidgets('the task is added after the Tasks page has gone, and the '
      'close lands on Tasks', (tester) async {
    await pumpApp(tester);
    askForQuickAdd();
    await settle(tester);
    expect(field, findsOneWidget);

    // The bar's page moves under the open sheet: the screen is disposed.
    tasksShowing.value = false;
    await settle(tester);
    expect(find.byType(MatrixScreen), findsNothing);
    expect(field, findsOneWidget, reason: 'the sheet is above the pages');

    await tester.enterText(field, 'Call the bank');
    await tester.pump(); // the button wakes with the text
    await tester.tap(find.text('ADD TASK'));
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(
      container.read(matrixProvider).tasks.map((t) => t.title),
      contains('Call the bank'),
    );

    // Closed (the empty field's «Done»), it asks the shell for Tasks.
    container.read(requestedHomeTabProvider.notifier).state = null;
    final route = ModalRoute.of(tester.element(field))!;
    route.navigator!.pop();
    await settle(tester);
    expect(container.read(requestedHomeTabProvider), NavTab.matrix);
    expect(container.read(requestedHomeTabInstantProvider), isTrue);
  });

  testWidgets('closing while Tasks is still showing asks for nothing',
      (tester) async {
    await pumpApp(tester);
    askForQuickAdd();
    await settle(tester);
    final route = ModalRoute.of(tester.element(field))!;
    route.navigator!.pop();
    await settle(tester);
    expect(container.read(requestedHomeTabProvider), isNull);
  });
}
