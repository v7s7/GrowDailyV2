// The Today / Fav / All toggle and its two counted chips (carried-over and
// upcoming) are three lenses on one board, and they have to read as one
// strip. They used to sit in a Wrap, which quietly dropped "upcoming" onto a
// second line the moment the three outgrew the width — most reliably in
// Arabic, where every one of those labels runs longer, and on the narrow
// phones with the least room to give.
//
// "All devices" is the actual requirement, so this file is a width sweep
// rather than a single case: the narrowest phone still sold through the
// widest Pro Max, in both languages, with both chips on screen. Everything
// here is measured off the real MatrixScreen — no reimplementation of the
// layout in the test, which would only ever prove the test agrees with
// itself.
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/matrix/models/matrix_task.dart';
import 'package:grow_daily_v2/features/matrix/notifiers/matrix_notifier.dart';
import 'package:grow_daily_v2/features/matrix/screens/matrix_screen.dart';
import 'package:hive/hive.dart';

/// Logical width × height for the phones this has to survive on. The narrow
/// end is what actually decides the layout: 320 is the smallest screen the
/// app still ships to (SE 1st gen / iPod touch), and if the strip holds
/// there it holds everywhere above it.
const _devices = <String, Size>{
  'iPhone SE 1st gen (320)': Size(320, 568),
  'iPhone SE 3rd gen (375)': Size(375, 667),
  'iPhone 15 (393)': Size(393, 852),
  'iPhone 15 Pro Max (430)': Size(430, 932),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late ProviderContainer container;

  // Hive is a process-wide singleton and its open boxes outlive any one
  // test, so it gets set up once rather than per-test. Doing it per-test
  // also means tearing it down per-test, and Hive.deleteFromDisk() in a
  // tearDown deadlocks outright here: the guest writes this file's seeding
  // kicks off run inside pumpWidget's fake-async zone, where their real
  // file IO never completes, so the close deleteFromDisk waits on never
  // returns and the whole run hangs with no timeout to rescue it. One box,
  // opened once in the real async zone, and per-test isolation done in the
  // notifier instead (see pumpMatrixAt).
  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('matrix_filter_row_');
    Hive.init(tmp.path);
    await Hive.openBox<dynamic>('box_settings');
  });

  setUp(() async {
    container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
      ],
    );
    await container.read(authStateProvider.future);
  });

  tearDown(() => container.dispose());

  // Best-effort, and only once every box is done being written to. Leaving
  // a temp tree behind on a crashed run is untidy; deleting it out from
  // under a still-open box would be worse.
  tearDownAll(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// A task created [daysAgo] days back with no reminder — open, dated
  /// before today, so it lands under the carried-over chip.
  MatrixTask carriedOver(String id, {int daysAgo = 1}) => MatrixTask(
        id: id,
        title: 'مهمة $id',
        quadrant: MatrixQuadrant.doFirst,
        isDone: false,
        createdAt: DateTime.now().subtract(Duration(days: daysAgo)),
        order: 0,
      );

  /// A task whose earliest reminder lands on a later day — the exact rule
  /// _isUpcoming applies, so it lands under the upcoming chip.
  MatrixTask upcoming(String id, {int daysAhead = 3}) => MatrixTask(
        id: id,
        title: 'مهمة $id',
        quadrant: MatrixQuadrant.schedule,
        isDone: false,
        createdAt: DateTime.now(),
        reminderAts: [DateTime.now().add(Duration(days: daysAhead))],
        order: 0,
      );

  /// The empty quadrants' "+" pulses on a repeat(reverse: true) animation
  /// that never settles, so pumpAndSettle would burn its timeout and throw.
  /// Fixed frames instead — plenty for the one-shot fades, never waits on
  /// the pulse. (Same trick, same reason, as matrix_add_task_test.dart.)
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpMatrixAt(
    WidgetTester tester,
    Size size, {
    required Locale locale,
    int carriedOverCount = 9,
    int upcomingCount = 1,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);

    // Every test in this file shares one guest store, so the board has to
    // be emptied before it is seeded — otherwise the counts on the chips
    // are whatever the tests before this one happened to leave behind, and
    // the finders below start matching a label nobody chose.
    final notifier = container.read(matrixProvider.notifier);
    notifier.deleteMany(
      container.read(matrixProvider).tasks.map((t) => t.id).toSet(),
    );
    notifier.restoreMany([
      for (var i = 0; i < carriedOverCount; i++) carriedOver('c$i'),
      for (var i = 0; i < upcomingCount; i++) upcoming('u$i'),
    ]);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('ar'), Locale('en')],
          theme: GameTheme.light,
          home: const MatrixScreen(),
        ),
      ),
    );
    await settle(tester);
  }

  for (final entry in _devices.entries) {
    for (final locale in const [Locale('ar'), Locale('en')]) {
      final s = S(locale);
      final lang = locale.languageCode;

      testWidgets('${entry.key} · $lang — toggle and both chips share one row',
          (tester) async {
        await pumpMatrixAt(tester, entry.value, locale: locale);

        final today = find.text(s.matrixToday);
        final carried = find.text(s.matrixCarriedOverCount(9));
        final soon = find.text(s.matrixUpcomingCount(1));

        // If any of the three is missing the row assertion below would pass
        // vacuously, which is exactly the failure this test exists to catch.
        expect(today, findsOneWidget, reason: 'Today segment missing');
        expect(carried, findsOneWidget, reason: 'carried-over chip missing');
        expect(soon, findsOneWidget, reason: 'upcoming chip missing');

        // One row means one shared vertical centre. A wrapped Upcoming sits
        // a full chip-height lower, so the tolerance can stay tight enough
        // to still catch a near-miss — it only absorbs the sub-pixel drift
        // of differently-sized glyph boxes.
        final baseline = tester.getCenter(today).dy;
        for (final control in [carried, soon]) {
          expect(
            (tester.getCenter(control).dy - baseline).abs(),
            lessThan(2.0),
            reason: 'control is on a different row than the Today segment',
          );
        }
      });

      testWidgets('${entry.key} · $lang — the strip fits inside the screen',
          (tester) async {
        await pumpMatrixAt(tester, entry.value, locale: locale);

        // Sharing a row is only half of it: a Row that overflows would also
        // report one shared centre while painting a yellow-and-black bar
        // and clipping the last chip off the edge. Every control has to be
        // inside the screen, and clear of the 20pt gutter the strip is
        // padded to on both sides.
        final width = entry.value.width;
        for (final control in [
          find.text(s.matrixToday),
          find.text(s.matrixCarriedOverCount(9)),
          find.text(s.matrixUpcomingCount(1)),
        ]) {
          final box = tester.getRect(control);
          expect(
            box.left,
            greaterThanOrEqualTo(0.0),
            reason: 'control runs off the leading edge',
          );
          expect(
            box.right,
            lessThanOrEqualTo(width),
            reason: 'control runs off the trailing edge',
          );
        }

        expect(
          tester.takeException(),
          isNull,
          reason: 'layout overflowed at ${entry.value.width}pt',
        );
      });
    }
  }

  testWidgets('the strip still holds when both counts run to two digits',
      (tester) async {
    // The counts are the one part of the strip that grows on its own, with
    // nobody watching. What costs width is the extra digit, not the size of
    // the number, so two-digit counts on the narrowest phone in Arabic is
    // the widest the strip can actually get.
    await pumpMatrixAt(
      tester,
      _devices['iPhone SE 1st gen (320)']!,
      locale: const Locale('ar'),
      carriedOverCount: 20,
      upcomingCount: 20,
    );

    const s = S(Locale('ar'));
    final today = find.text(s.matrixToday);
    final soon = find.text(s.matrixUpcomingCount(20));
    expect(soon, findsOneWidget);
    expect(
      (tester.getCenter(soon).dy - tester.getCenter(today).dy).abs(),
      lessThan(2.0),
    );
    expect(tester.getRect(soon).left, greaterThanOrEqualTo(0.0));
    expect(tester.takeException(), isNull);
  });
}
