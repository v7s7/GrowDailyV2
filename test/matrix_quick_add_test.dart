import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/matrix/models/matrix_task.dart';
import 'package:grow_daily_v2/features/matrix/notifiers/matrix_notifier.dart';
import 'package:grow_daily_v2/features/matrix/screens/matrix_screen.dart';
import 'package:hive/hive.dart';

/// The Goals Matrix should never require precision-tapping a tiny + icon:
/// the whole empty square is a tap target, and a one-tap suggestion chip
/// adds a goal instantly with no typing at all.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late ProviderContainer container;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('matrix_test_');
    Hive.init(tmp.path);
    // MatrixNotifier now persists guest goals to this box — open it here,
    // in the real async zone, so the notifier's guest load is synchronous
    // once the widget tree builds (the same fix the landing-flow tests
    // needed: Hive IO started inside pumpWidget's fake-async zone never
    // completes).
    await Hive.openBox<dynamic>('box_settings');
    container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
      ],
    );
    await container.read(authStateProvider.future);
  });

  tearDown(() => container.dispose());

  // The empty quadrant's "+" icon breathes with a repeat(reverse: true)
  // animation, which never settles — at least one empty quadrant is on
  // screen for nearly every test here, so pumpAndSettle() (even given a
  // timeout) always burns the full timeout and then throws. Pump a fixed
  // number of frames instead: plenty for the one-shot transitions
  // (bottom sheets, fades) to finish, and it never waits on the pulse.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpMatrix(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: GameTheme.light, home: const MatrixScreen()),
      ),
    );
    await settle(tester);
  }

  testWidgets('tapping the empty square (not the + icon) opens the add sheet',
      (tester) async {
    await pumpMatrix(tester);

    // Tap the hint text deep in the empty quadrant body — nowhere near the
    // header's + icon — and the add-task sheet should still open.
    await tester.tap(find.text('Tap anywhere to add a goal').first);
    await settle(tester);

    expect(find.text('What needs to be done?'), findsOneWidget);
  });

  testWidgets('a one-tap suggestion adds a goal with no typing', (tester) async {
    await pumpMatrix(tester);

    final suggestion = MatrixQuadrant.doFirst.quickSuggestions(false).first;
    await tester.tap(find.text(suggestion).first);
    await settle(tester);

    // No sheet opened, and the task landed straight in Do First.
    expect(find.text('What needs to be done?'), findsNothing);
    final tasks = container.read(matrixProvider);
    expect(tasks, hasLength(1));
    expect(tasks.first.title, suggestion);
    expect(tasks.first.quadrant, MatrixQuadrant.doFirst);
    expect(find.text(suggestion), findsOneWidget); // now shown as a task row
  });

  testWidgets('a populated quadrant keeps a persistent, generous add row',
      (tester) async {
    await pumpMatrix(tester);
    container.read(matrixProvider.notifier).add('First goal', MatrixQuadrant.doFirst);
    await settle(tester);

    // The empty-state suggestions are gone, replaced by a full-width
    // "+ Add another" row — never just the small header icon. (Only this
    // one quadrant is populated; the other three still show suggestions.)
    expect(find.text('+ Add another'), findsOneWidget);
    await tester.tap(find.text('+ Add another').first);
    await settle(tester);
    expect(find.text('What needs to be done?'), findsOneWidget);
  });
}
