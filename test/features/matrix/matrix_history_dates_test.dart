// The completed-tasks archive, in Arabic under the real localization
// delegates.
//
// Two raw patterns printed Arabic-Indic digits here: the selected day's
// heading, DateFormat('EEEE, MMM d'), which also put the month first and
// kept the Latin comma («الخميس, سبتمبر ١٧»), and each row's completion
// time, DateFormat('h:mm a') («٩:٠٥ م»), under a calendar numbered 1 to 30.
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';

import 'package:grow_daily_v2/core/services/local_store_service.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/matrix/models/matrix_task.dart';
import 'package:grow_daily_v2/features/matrix/notifiers/matrix_notifier.dart';
import 'package:grow_daily_v2/features/matrix/screens/matrix_history_screen.dart';
import 'package:grow_daily_v2/features/premium/notifiers/premium_notifier.dart';

/// The tasks a test hands it, whatever the guest load reads.
class _FixedMatrix extends MatrixNotifier {
  _FixedMatrix(Ref ref, this.fixed) : super(ref, null) {
    super.state = fixed;
  }

  final MatrixState fixed;

  @override
  set state(MatrixState value) => super.state = fixed;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('matrix_history_dates_');
    Hive.init(tmp.path);
    // MatrixNotifier's guest load reads this; opened out here, never inside
    // a testWidgets body.
    await LocalStoreService.settingsBox();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await tmp.delete(recursive: true);
  });

  // Yesterday on the real calendar, because the archive opens on the real
  // month and names today «اليوم» instead of dating it.
  final now = DateTime.now();
  final yesterday = DateTime(now.year, now.month, now.day - 1);
  final doneAt = yesterday.add(const Duration(hours: 21, minutes: 5));

  final done = MatrixTask(
    id: 't1',
    title: 'راجع التقرير',
    quadrant: MatrixQuadrant.doFirst,
    isDone: true,
    createdAt: yesterday.add(const Duration(hours: 9)),
    completedAt: doneAt,
    order: 0,
  );

  Future<void> openYesterday(WidgetTester tester, Locale locale) async {
    tester.view.physicalSize = const Size(400 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
        premiumAccessProvider.overrideWithValue(false),
        matrixProvider.overrideWith((ref) => _FixedMatrix(
              ref,
              MatrixState(tasks: [done], isLoading: false),
            )),
      ],
      child: MaterialApp(
        locale: locale,
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: GameTheme.dark,
        home: const MatrixHistoryScreen(),
      ),
    ));
    await tester.pumpAndSettle();
    // On the 1st, yesterday is last month.
    if (yesterday.month != now.month) {
      await tester.tap(find.byIcon(Icons.chevron_left_rounded));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('${yesterday.day}'));
    await tester.pumpAndSettle();
  }

  testWidgets('Arabic: the day heading and the row time in Latin digits',
      (tester) async {
    await openYesterday(tester, const Locale('ar'));
    final weekday = DateFormat('EEEE', 'ar').format(yesterday);
    final month = DateFormat('MMMM', 'ar').format(yesterday);
    expect(find.text('$weekday، ${yesterday.day} $month'), findsOneWidget);
    expect(find.textContaining('· 9:05 م'), findsOneWidget,
        reason: 'the row read «... · ٩:٠٥ م»');
    expect(
      find.byWidgetPredicate((w) =>
          w is RichText && RegExp('[٠-٩]').hasMatch(w.text.toPlainText())),
      findsNothing,
    );
  });

  testWidgets('English keeps «Weekday, Mon d» and «9:05 PM»', (tester) async {
    await openYesterday(tester, const Locale('en'));
    final label = DateFormat('EEEE, MMM d', 'en').format(yesterday);
    expect(find.text(label), findsOneWidget);
    expect(find.textContaining('· 9:05 PM'), findsOneWidget);
  });
}
