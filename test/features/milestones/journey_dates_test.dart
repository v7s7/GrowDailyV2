// The Journey page's dates, in Arabic under the real localization
// delegates.
//
// Three raw patterns printed Arabic-Indic digits here: «عضو منذ يوليو ٢٠٢٦»
// in the header, «سبتمبر ٢٠٢٦» over each month, and every milestone's
// «الجمعة, سبتمبر ١٨», which also put the month first and kept the Latin
// comma. The header's day count beside them was already Latin.
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/core/services/local_store_service.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/dashboard/notifiers/dashboard_notifier.dart';
import 'package:grow_daily_v2/features/milestones/models/milestone_event.dart';
import 'package:grow_daily_v2/features/milestones/notifiers/milestone_notifier.dart';
import 'package:grow_daily_v2/features/milestones/screens/journey_screen.dart';

/// An account that began on 3 July 2026, whatever the guest load reads.
class _FixedDash extends DashboardNotifier {
  _FixedDash() : super(null) {
    super.state = _joined;
  }

  static final _joined = DashboardState(
    level: 4,
    currentLevelXp: 0,
    cumulativeXp: 0,
    gold: 0,
    streak: 0,
    completions: const {},
    accountCreatedAt: DateTime(2026, 7, 3),
  );

  @override
  set state(DashboardState value) => super.state = _joined;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('journey_dates_');
    Hive.init(tmp.path);
    // Only the daily box, as heatmap_open_day_test opens it. The settings
    // box is left shut on purpose: with it open, the dashboard's guest load
    // wrote to it from inside the test's fake-async zone, and the tearDown's
    // deleteFromDisk then waited forever on that write.
    await LocalStoreService.dailyBox();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await tmp.delete(recursive: true);
  });

  final events = [
    MilestoneEvent(
      id: 'lvl4',
      type: MilestoneType.levelUp,
      occurredAt: DateTime(2026, 9, 18, 21, 5),
      data: const {'level': 4},
    ),
  ];

  Future<void> pump(WidgetTester tester, Locale locale) async {
    tester.view.physicalSize = const Size(400 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
        dashboardProvider.overrideWith((ref) => _FixedDash()),
        milestoneEventsProvider.overrideWith((ref) => Stream.value(events)),
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
        home: const JourneyScreen(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('Arabic: member-since, month header and milestone date',
      (tester) async {
    await pump(tester, const Locale('ar'));
    expect(find.textContaining('عضو منذ يوليو 2026 ('), findsOneWidget);
    expect(find.text('سبتمبر 2026'), findsOneWidget);
    expect(find.text('الجمعة، 18 سبتمبر'), findsOneWidget,
        reason: 'drew «الجمعة, سبتمبر ١٨»');
    // The origin card at the bottom, the day the account began.
    expect(find.text('الجمعة، 3 يوليو'), findsOneWidget);
    expect(
      find.byWidgetPredicate((w) =>
          w is RichText && RegExp('[٠-٩]').hasMatch(w.text.toPlainText())),
      findsNothing,
    );
  });

  testWidgets('English is unchanged', (tester) async {
    await pump(tester, const Locale('en'));
    expect(find.textContaining('Member since July 2026 ('), findsOneWidget);
    expect(find.text('SEPTEMBER 2026'), findsOneWidget);
    expect(find.text('Friday, September 18'), findsOneWidget);
  });
}
